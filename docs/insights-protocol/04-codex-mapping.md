# Codex → InsightsEvent Mapping

Codex communicates via JSON-RPC 2.0 over stdin/stdout. The Codex app-server sends **notifications** (one-way events) and **server requests** (events requiring a response). This document maps every Codex event to its corresponding `InsightsEvent`.

## Current State: The "Squish"

Today, `CodexSession` translates Codex events into synthetic Claude-format JSON, which is then parsed into `SDKMessage` objects, which are then destructured back into raw JSON by `SdkMessageHandler`. This triple conversion:

1. Builds synthetic `{type: 'assistant', message: {content: [{type: 'tool_use', ...}]}}` dicts
2. Parses them with `SDKMessage.fromJson()`
3. Reads `msg.rawJson` in the handler

With InsightsEvent, Codex events map **directly** to typed events. No synthetic JSON, no round-trip.

## Architecture: Single Shared Process

Unlike Claude CLI (one process per session), Codex uses a **single shared `CodexProcess`** for all sessions. The process runs `codex app-server` and multiplexes sessions via `threadId`.

- Session creation: `thread/start` or `thread/resume` JSON-RPC request
- Messages: `turn/start` JSON-RPC request with `{threadId, input}`
- Events: Filtered by `threadId` in each notification

## Notification Mapping

### `thread/started`

```json
{
  "jsonrpc": "2.0",
  "method": "thread/started",
  "params": {
    "thread": {
      "id": "thread-abc-123",
      "model": "o4-mini"
    }
  }
}
```

**→ `SessionInitEvent`**

| JSON field | InsightsEvent field | Notes |
|------------|---------------------|-------|
| `thread.id` | `sessionId` | |
| `thread.model` | `model` | |
| — | `cwd` | Not provided by Codex |
| — | `availableTools` | Not provided (Codex manages tools internally) |
| — | `mcpServers` | Not provided |
| — | `permissionMode` | Not applicable (Codex manages server-side) |
| — | `account` | Not provided |
| — | `slashCommands` | Not provided |

Available models come from a separate `model/list` JSON-RPC call on the backend, not from session initialization.

### `turn/started`

```json
{
  "jsonrpc": "2.0",
  "method": "turn/started",
  "params": {
    "threadId": "thread-abc-123",
    "turn": {"id": "turn-xyz"}
  }
}
```

**→ No InsightsEvent emitted directly.** The turn ID is tracked internally for interrupt support. The frontend sees the turn via subsequent item events.

Alternatively, could emit a lightweight `SessionStatusEvent` with `status: SessionStatus.processing` if we want a "thinking" indicator.

### `item/started`

Emitted when the agent begins a tool invocation.

#### `commandExecution`

```json
{
  "jsonrpc": "2.0",
  "method": "item/started",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-001",
      "type": "commandExecution",
      "command": "npm test",
      "cwd": "/Users/zaf/project"
    }
  }
}
```

**→ `ToolInvocationEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `item.id` | `callId` |
| — | `parentCallId` = null (Codex doesn't support subagents) |
| `"commandExecution"` | `kind` = `ToolKind.execute` |
| `"Bash"` | `toolName` (mapped for display compatibility) |
| `item.command` | `input.command` |
| `item.cwd` | `input.cwd` |

#### `fileChange`

```json
{
  "jsonrpc": "2.0",
  "method": "item/started",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-002",
      "type": "fileChange",
      "changes": [
        {"path": "/project/src/main.dart", "diff": "--- a/...\n+++ b/..."}
      ]
    }
  }
}
```

**→ `ToolInvocationEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `item.id` | `callId` |
| `"fileChange"` | `kind` = `ToolKind.edit` |
| `"FileChange"` | `toolName` (NOT "Write" — preserves Codex semantics) |
| `changes[].path` | `locations` |
| `{paths: [...], diffs: [...]}` | `input` (structured, not flattened) |

**Key change from current approach:** Instead of flattening multi-file changes into a single `file_path` + `content` string (losing all but the first path), we preserve the full `changes` array in `input` and extract all paths into `locations`.

#### `mcpToolCall`

```json
{
  "jsonrpc": "2.0",
  "method": "item/started",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-003",
      "type": "mcpToolCall",
      "server": "flutter-test",
      "tool": "run_tests",
      "arguments": {"project_path": "/project"}
    }
  }
}
```

**→ `ToolInvocationEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `item.id` | `callId` |
| `"mcpToolCall"` | `kind` = `ToolKind.mcp` |
| `"mcp__flutter-test__run_tests"` | `toolName` (reconstructed to match Claude's naming convention for UI rendering) |
| `{server, tool, arguments}` | `input` |

**Key change from current approach:** Instead of mapping to the made-up name `McpTool`, we reconstruct the `mcp__<server>__<tool>` naming convention so `ToolCard` can apply its MCP-specific rendering.

### `item/completed`

Emitted when a tool finishes (or when the agent produces text/thinking output).

#### `commandExecution` completed

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-001",
      "type": "commandExecution",
      "aggregatedOutput": "All tests passed\n",
      "exitCode": 0
    }
  }
}
```

**→ `ToolCompletionEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `item.id` | `callId` |
| `item.exitCode != 0` | `isError` |
| `item.exitCode != 0` | `status` = `failed` or `completed` |
| `{stdout: aggregatedOutput, exit_code: exitCode}` | `output` |

**Also emit a `TerminalBlock` in `content`** with the full output and exit code, so the frontend can render it consistently.

#### `fileChange` completed

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-002",
      "type": "fileChange",
      "status": "completed",
      "changes": [
        {"path": "/project/src/main.dart", "diff": "--- a/...\n+++ b/..."}
      ]
    }
  }
}
```

**→ `ToolCompletionEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `item.id` | `callId` |
| `item.status == "failed"` | `isError` |
| `{changes: [...]}` | `output` |
| `DiffBlock` per change | `content` — one `DiffBlock` per file in `changes[]` |

**Key change from current approach:** Instead of joining diffs into a single string and putting it in `{diff: "..."}`, we produce proper `DiffBlock` content blocks that the frontend can render as real diffs.

#### `mcpToolCall` completed

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-003",
      "type": "mcpToolCall",
      "result": {"summary": "5 tests passed"},
      "error": null
    }
  }
}
```

**→ `ToolCompletionEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `item.id` | `callId` |
| `item.error != null` | `isError` |
| `item.result ?? item.error` | `output` |

#### `agentMessage` completed

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-004",
      "type": "agentMessage",
      "text": "Here's what I found..."
    }
  }
}
```

**→ `TextEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `item.text` | `text` |
| — | `kind` = `TextKind.text` |
| — | `parentCallId` = null |

#### `reasoning` completed

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-005",
      "type": "reasoning",
      "summary": ["Analyzing the code structure..."],
      "content": ["Let me think about this..."]
    }
  }
}
```

**→ `TextEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `summary.join('\n')` or `content.join('\n')` | `text` (prefer summary) |
| — | `kind` = `TextKind.thinking` |

#### `plan` completed

**→ `TextEvent`** with `kind: TextKind.plan`.

### `thread/tokenUsage/updated`

```json
{
  "jsonrpc": "2.0",
  "method": "thread/tokenUsage/updated",
  "params": {
    "threadId": "thread-abc-123",
    "tokenUsage": {
      "total": {
        "inputTokens": 5000,
        "outputTokens": 1500,
        "cachedInputTokens": 3000
      }
    }
  }
}
```

**→ No InsightsEvent emitted directly.** Stored internally and included in the `TurnCompleteEvent` when the turn finishes.

### `turn/completed`

```json
{
  "jsonrpc": "2.0",
  "method": "turn/completed",
  "params": {
    "threadId": "thread-abc-123"
  }
}
```

**→ `TurnCompleteEvent`**

| JSON field | InsightsEvent field | Notes |
|------------|---------------------|-------|
| — | `isError` = false | Codex doesn't report turn-level errors |
| — | `subtype` = `"success"` | |
| Accumulated from `tokenUsage/updated` | `usage` | `TokenUsage(inputTokens, outputTokens, cacheReadTokens)` |
| — | `costUsd` = null | Codex doesn't report cost |
| — | `durationMs` = null | Codex doesn't report duration |
| — | `durationApiMs` = null | |
| — | `numTurns` = null | |
| — | `modelUsage` = null | Codex doesn't report per-model breakdown |
| — | `permissionDenials` = null | |

## Server Request Mapping (Permissions)

### `item/commandExecution/requestApproval`

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "method": "item/commandExecution/requestApproval",
  "params": {
    "threadId": "thread-abc-123",
    "command": "rm -rf node_modules",
    "cwd": "/Users/zaf/project",
    "itemId": "item-010",
    "commandActions": ["allow", "deny"],
    "reason": "This command modifies the filesystem"
  }
}
```

**→ `PermissionRequestEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `id` (JSON-RPC) | `requestId` (as string) |
| `"Bash"` | `toolName` |
| `ToolKind.execute` | `toolKind` |
| `{command, cwd}` | `toolInput` |
| `params.itemId` | `toolUseId` |
| — | `suggestions` = null (Codex doesn't support) |
| — | `blockedPath` = null |
| `params.reason` | `reason` |
| `params.commandActions` | `extensions['codex.commandActions']` |

**Response mapping:**
- `allow()` → JSON-RPC response: `{decision: "accept"}`
- `deny(interrupt: false)` → `{decision: "decline"}`
- `deny(interrupt: true)` → `{decision: "cancel"}`

### `item/fileChange/requestApproval`

```json
{
  "jsonrpc": "2.0",
  "id": 43,
  "method": "item/fileChange/requestApproval",
  "params": {
    "threadId": "thread-abc-123",
    "grantRoot": "/Users/zaf/project/src",
    "itemId": "item-011"
  }
}
```

**→ `PermissionRequestEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `id` | `requestId` |
| `"Write"` | `toolName` |
| `ToolKind.edit` | `toolKind` |
| `{file_path: grantRoot}` | `toolInput` |
| `params.itemId` | `toolUseId` |
| `params.grantRoot` | `extensions['codex.grantRoot']` |

### `item/tool/requestUserInput`

```json
{
  "jsonrpc": "2.0",
  "id": 44,
  "method": "item/tool/requestUserInput",
  "params": {
    "threadId": "thread-abc-123",
    "questions": [{"text": "Which database?", "options": ["PostgreSQL", "SQLite"]}],
    "itemId": "item-012"
  }
}
```

**→ `PermissionRequestEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `id` | `requestId` |
| `"AskUserQuestion"` | `toolName` |
| `ToolKind.ask` | `toolKind` |
| `{questions}` | `toolInput` |
| `params.itemId` | `toolUseId` |

**Response mapping:**
- `allow(updatedInput: {answers: {...}})` → JSON-RPC response: `{answers: {...}}`
- `deny()` → `{answers: {}}`

## What Codex Doesn't Provide

| Feature | Status | Frontend Behavior |
|---------|--------|-------------------|
| Cost tracking | Not available | Cost badge hidden |
| Duration metrics | Not available | Duration hidden |
| Per-model usage | Not available | Model breakdown hidden |
| Context window size | Not available | Context meter hidden |
| Permission suggestions | Not available | No auto-approve suggestions shown |
| Permission denials | Not reported | Turn summary omits denials |
| Subagent routing | No `parentToolUseId` | All output in primary conversation |
| Streaming deltas | Not supported | No typing effect; content appears on completion |
| MCP server status | Not reported | MCP panel hidden |
| Available tools list | Not reported | Tool palette hidden |
| Slash commands | Not available | Command palette hidden |
| Account info | Not available | Account badge hidden |
| Compaction events | Not available | No compaction indicators |
| File read events | Not reported | Read operations invisible |
| Search events | Not reported | Search operations invisible |

## Codex-Specific Data

| Data | Where It Goes | Why It Matters |
|------|--------------|----------------|
| `turnId` | `extensions['codex.turnId']` | Needed for interrupt support |
| `effortLevel` | `extensions['codex.effortLevel']` | Codex supports reasoning effort |
| `commandActions` | `extensions['codex.commandActions']` | Richer approval options |
| `grantRoot` | `extensions['codex.grantRoot']` | Directory-level approval |
| `item.type` (original) | `extensions['codex.itemType']` | Preserves native vocabulary |
| Multi-file changes | `ToolInvocationEvent.input` and `.locations` | Full change set preserved |

## Process Architecture Note

Codex uses a **single shared process** for all sessions, unlike Claude (one process per session). This means:

- The `CodexProcess` is created once when the backend starts
- Sessions are `thread/start` requests on the same process
- All notifications are multiplexed; each must be filtered by `threadId`
- The process lifecycle is tied to the backend, not individual sessions

For containerization (see [07-transport-separation.md](07-transport-separation.md)), this means one container per Codex backend, not one container per session.
