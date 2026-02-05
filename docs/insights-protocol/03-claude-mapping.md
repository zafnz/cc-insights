# Claude CLI → InsightsEvent Mapping

Claude CLI communicates via JSON Lines (`--output-format stream-json --input-format stream-json`). Each line is a JSON object with a `type` field. This document maps every Claude CLI message type to its corresponding `InsightsEvent`.

## Claude Is the Richest Backend

Claude CLI provides more metadata than any other backend. The InsightsEvent model is designed to carry all of it — nothing is dropped. Other backends simply leave the Claude-rich fields null.

## Message Type Mapping

### `system` (subtype: `init`)

The initialization message, sent after the CLI is ready.

```json
{
  "type": "system",
  "subtype": "init",
  "session_id": "abc-123",
  "uuid": "...",
  "model": "claude-sonnet-4-5-20250929",
  "cwd": "/Users/zaf/project",
  "tools": ["Bash", "Read", "Write", "Edit", ...],
  "mcp_servers": [{"name": "flutter-test", "status": "connected"}],
  "permissionMode": "default",
  "apiKeySource": "ANTHROPIC_API_KEY",
  "slash_commands": ["compact", "clear", "help", ...],
  "output_style": "concise"
}
```

**→ `SessionInitEvent`**

| JSON field | InsightsEvent field | Notes |
|------------|---------------------|-------|
| `session_id` | `sessionId` | |
| `model` | `model` | |
| `cwd` | `cwd` | |
| `tools` | `availableTools` | |
| `mcp_servers` | `mcpServers` | Parsed to `List<McpServerStatus>` |
| `permissionMode` | `permissionMode` | |
| `slash_commands` | `slashCommands` | |
| `apiKeySource` | `extensions['claude.apiKeySource']` | Claude-specific |
| `output_style` | `extensions['claude.outputStyle']` | Claude-specific |

Additionally, the `control_response` received during initialization provides:

```json
{
  "type": "control_response",
  "response": {
    "models": [{"value": "claude-sonnet-4-5-20250929", "displayName": "Sonnet 4.5"}],
    "account": {"email": "...", "organization": "...", "subscriptionType": "pro"},
    "commands": [{"name": "compact", "description": "..."}]
  }
}
```

| JSON field | InsightsEvent field | Notes |
|------------|---------------------|-------|
| `response.models` | `availableModels` | `List<ModelInfo>` |
| `response.account` | `account` | `AccountInfo` — Claude-only |
| `response.commands` | `slashCommands` | Richer than the string list from system/init |

Both are merged into a single `SessionInitEvent`.

### `system` (subtype: `status`)

```json
{"type": "system", "subtype": "status", "status": "compacting"}
```

**→ `SessionStatusEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `status` | `status` → `SessionStatus.compacting` |

### `system` (subtype: `compact_boundary`)

```json
{
  "type": "system",
  "subtype": "compact_boundary",
  "compact_metadata": {"trigger": "auto", "pre_tokens": 180000}
}
```

**→ `ContextCompactionEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `compact_metadata.trigger` | `trigger` → `CompactionTrigger.auto` |
| `compact_metadata.pre_tokens` | `preTokens` |

### `system` (subtype: `context_cleared`)

**→ `ContextCompactionEvent`** with `trigger: CompactionTrigger.cleared`.

### `assistant`

The main response message. Contains a list of content blocks.

```json
{
  "type": "assistant",
  "uuid": "...",
  "session_id": "...",
  "parent_tool_use_id": null,
  "message": {
    "role": "assistant",
    "model": "claude-sonnet-4-5-20250929",
    "content": [
      {"type": "text", "text": "Here's the fix..."},
      {"type": "thinking", "thinking": "Let me analyze...", "signature": "..."},
      {"type": "tool_use", "id": "tu_123", "name": "Edit", "input": {"file_path": "...", "old_string": "...", "new_string": "..."}}
    ],
    "usage": {"input_tokens": 1000, "output_tokens": 500}
  }
}
```

Each content block produces a **separate** `InsightsEvent`:

#### `text` block → `TextEvent`

| JSON field | InsightsEvent field |
|------------|---------------------|
| `content[].text` | `text` |
| `parent_tool_use_id` | `parentCallId` |
| `message.model` | `model` |
| — | `kind` = `TextKind.text` |

#### `thinking` block → `TextEvent`

| JSON field | InsightsEvent field |
|------------|---------------------|
| `content[].thinking` | `text` |
| `parent_tool_use_id` | `parentCallId` |
| — | `kind` = `TextKind.thinking` |

#### `tool_use` block → `ToolInvocationEvent`

| JSON field | InsightsEvent field |
|------------|---------------------|
| `content[].id` | `callId` |
| `content[].name` | `toolName` |
| `content[].input` | `input` |
| `parent_tool_use_id` | `parentCallId` |
| `content[].name` | `kind` (derived — see Tool Kind Mapping in 02-event-model.md) |
| `message.model` | `model` |
| Extracted from `input.file_path`, `input.path`, etc. | `locations` |

**Special case: Task tool**

When `toolName == "Task"`, also emit a `SubagentSpawnEvent`:

| JSON field | InsightsEvent field |
|------------|---------------------|
| `input.subagent_type` or `input.name` | `agentType` |
| `input.description` or `input.prompt` or `input.task` | `description` |
| `input.resume` | `isResume` (true if present) |
| `input.resume` | `resumeAgentId` |

### `user`

User messages carry tool results and context summaries.

```json
{
  "type": "user",
  "uuid": "...",
  "session_id": "...",
  "parent_tool_use_id": null,
  "isSynthetic": false,
  "tool_use_result": {"stdout": "...", "stderr": "", "exit_code": 0},
  "message": {
    "role": "user",
    "content": [
      {"type": "tool_result", "tool_use_id": "tu_123", "content": "...", "is_error": false}
    ]
  }
}
```

#### `tool_result` block → `ToolCompletionEvent`

| JSON field | InsightsEvent field |
|------------|---------------------|
| `content[].tool_use_id` | `callId` |
| `tool_use_result` (preferred) or `content[].content` | `output` |
| `content[].is_error` | `isError` |
| — | `status` = `isError ? ToolCallStatus.failed : ToolCallStatus.completed` |

**The `tool_use_result` field** is Claude-specific structured data (e.g., TodoWrite returns `{oldTodos, newTodos}`). This is richer than the `content` field and should be preferred when present.

#### Context summary (synthetic user message after compaction)

When `isSynthetic == true` and the content is a text block following a `compact_boundary`, it's a context summary.

**→ `TextEvent`** with `kind: TextKind.text` and `extensions['claude.isSynthetic'] = true`.

The frontend uses this to display the compaction summary.

#### Replay messages

When `isReplay == true`, the message contains `<local-command-stdout>` XML tags.

**→ `TextEvent`** with `extensions['claude.isReplay'] = true`. The frontend extracts the command output for display.

### `result`

Turn completion with usage, cost, and error information.

```json
{
  "type": "result",
  "subtype": "success",
  "uuid": "...",
  "session_id": "...",
  "duration_ms": 15000,
  "duration_api_ms": 12000,
  "is_error": false,
  "num_turns": 3,
  "total_cost_usd": 0.0234,
  "usage": {
    "input_tokens": 50000,
    "output_tokens": 3000,
    "cache_creation_input_tokens": 10000,
    "cache_read_input_tokens": 40000
  },
  "modelUsage": {
    "claude-sonnet-4-5-20250929": {
      "inputTokens": 50000,
      "outputTokens": 3000,
      "cacheReadInputTokens": 40000,
      "cacheCreationInputTokens": 10000,
      "webSearchRequests": 0,
      "costUsd": 0.0234,
      "contextWindow": 200000
    }
  },
  "permission_denials": [
    {"tool_name": "Bash", "tool_use_id": "tu_456", "tool_input": {"command": "rm -rf /"}}
  ]
}
```

**→ `TurnCompleteEvent`**

| JSON field | InsightsEvent field | Notes |
|------------|---------------------|-------|
| `subtype` | `subtype` | "success", "error_max_turns", etc. |
| `is_error` | `isError` | |
| `duration_ms` | `durationMs` | Claude-only (null for others) |
| `duration_api_ms` | `durationApiMs` | Claude-only |
| `num_turns` | `numTurns` | Claude-only |
| `total_cost_usd` | `costUsd` | Claude-only |
| `usage` | `usage` → `TokenUsage` | |
| `modelUsage` | `modelUsage` → `Map<String, ModelTokenUsage>` | Claude-only. Note JSON uses camelCase. |
| `permission_denials` | `permissionDenials` | Claude-only |
| `result` | `result` | Final text result |
| `errors` | `errors` | Error messages |

**Special case: Task tool result**

When the `result` message corresponds to a subagent turn:

**→ Also emit `SubagentCompleteEvent`** with `agentId`, `status`, and `summary` extracted from the structured result.

### `control_request`

Permission request from the CLI.

```json
{
  "type": "control_request",
  "request_id": "req-789",
  "session_id": "...",
  "request": {
    "subtype": "can_use_tool",
    "tool_name": "Bash",
    "input": {"command": "npm test"},
    "tool_use_id": "tu_789",
    "permission_suggestions": [
      {"type": "allow_tool", "tool_name": "Bash", "description": "Allow all Bash commands"}
    ],
    "blocked_path": "/Users/zaf/project"
  }
}
```

**→ `PermissionRequestEvent`**

| JSON field | InsightsEvent field |
|------------|---------------------|
| `request_id` | `requestId` |
| `request.tool_name` | `toolName` |
| `request.tool_name` | `toolKind` (derived) |
| `request.input` | `toolInput` |
| `request.tool_use_id` | `toolUseId` |
| `request.permission_suggestions` | `suggestions` → `List<PermissionSuggestion>` |
| `request.blocked_path` | `blockedPath` |

### `stream_event`

Streaming events for real-time UI updates. Only Claude CLI emits these.

```json
{"type": "stream_event", "session_id": "...", "parent_tool_use_id": null,
 "event": {"type": "message_start", ...}}
{"type": "stream_event", "session_id": "...",
 "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}}
{"type": "stream_event", "session_id": "...",
 "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Here"}}}
{"type": "stream_event", "session_id": "...",
 "event": {"type": "content_block_stop", "index": 0}}
{"type": "stream_event", "session_id": "...",
 "event": {"type": "message_stop"}}
```

**→ `StreamDeltaEvent`**

| Event subtype | InsightsEvent fields |
|---------------|---------------------|
| `message_start` | `kind: StreamDeltaKind.messageStart` |
| `content_block_start` (text) | `kind: StreamDeltaKind.blockStart`, `blockIndex` |
| `content_block_start` (tool_use) | `kind: StreamDeltaKind.blockStart`, `blockIndex`, `callId` |
| `content_block_delta` (text_delta) | `kind: StreamDeltaKind.text`, `textDelta`, `blockIndex` |
| `content_block_delta` (thinking_delta) | `kind: StreamDeltaKind.thinking`, `textDelta`, `blockIndex` |
| `content_block_delta` (input_json_delta) | `kind: StreamDeltaKind.toolInput`, `jsonDelta`, `callId`, `blockIndex` |
| `content_block_stop` | `kind: StreamDeltaKind.blockStop`, `blockIndex` |
| `message_stop` | `kind: StreamDeltaKind.messageStop` |
| `message_delta` (stop_reason) | `kind: StreamDeltaKind.messageStop` with stop reason in extensions |

## Outgoing Messages (Frontend → Claude CLI)

These are not InsightsEvents (they go the other direction), but documented here for completeness.

### Send user message

```json
{"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": "..."}]}}
```

### Permission response (allow)

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req-789",
    "response": {
      "behavior": "allow",
      "toolUseID": "tu_789",
      "updatedInput": null,
      "updatedPermissions": {"allow_tool_bash": true}
    }
  }
}
```

### Permission response (deny)

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req-789",
    "response": {
      "behavior": "deny",
      "toolUseID": "tu_789",
      "message": "User denied this action"
    }
  }
}
```

### Control requests (model, permissions, interrupt)

```json
{"type": "control_request", "request": {"subtype": "set_model", "model": "..."}}
{"type": "control_request", "request": {"subtype": "set_permission_mode", "permissionMode": "..."}}
{"type": "control_request", "request": {"subtype": "interrupt"}}
```

## Claude-Specific Data Not in Other Backends

These fields are only populated when `provider == BackendProvider.claude`:

| Data | Where It Appears | Why It Matters |
|------|-----------------|----------------|
| `totalCostUsd` | `TurnCompleteEvent.costUsd` | Cost tracking is a core Insights feature |
| `modelUsage` (per-model) | `TurnCompleteEvent.modelUsage` | Shows Sonnet vs Haiku vs Opus breakdown |
| `contextWindow` | `ModelTokenUsage.contextWindow` | Powers the context meter widget |
| `durationMs` / `durationApiMs` | `TurnCompleteEvent` | Performance monitoring |
| `permissionSuggestions` | `PermissionRequestEvent.suggestions` | One-click auto-approve rules |
| `permissionDenials` | `TurnCompleteEvent.permissionDenials` | Turn summary shows what was blocked |
| `account` (email, org, sub) | `SessionInitEvent.account` | Account badge in UI |
| `mcpServers` | `SessionInitEvent.mcpServers` | MCP status indicators |
| `slashCommands` | `SessionInitEvent.slashCommands` | Command palette |
| `compactMetadata` | `ContextCompactionEvent` | Context window management |
| `parentToolUseId` | Multiple events | Subagent conversation routing |
| Streaming deltas | `StreamDeltaEvent` | Real-time typing effect |
| `isReplay` / `isSynthetic` | Extensions | Session resume display |
