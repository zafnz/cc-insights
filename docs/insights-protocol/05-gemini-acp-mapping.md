# Gemini / ACP → InsightsEvent Mapping

This document covers two related but distinct integration paths:

1. **Gemini CLI** via its `stream-json` output (similar to Claude CLI)
2. **Any ACP-compatible agent** via the Agent Client Protocol (JSON-RPC 2.0)

Gemini CLI is also an ACP agent (it was the first reference implementation). The ACP path is the more general and future-proof integration.

## ACP: The Standard Path

### Why ACP Is the Primary Integration

The [Agent Client Protocol](https://agentclientprotocol.com/) is supported by:
- **Editors**: Zed, JetBrains, Neovim, VS Code extensions
- **Agents**: Claude Code, Codex CLI, Gemini CLI, Goose, Qwen Code, StackPack

ACP uses JSON-RPC 2.0 over stdio (or HTTP/WebSocket for remote agents). Its event model maps almost 1:1 to InsightsEvent because InsightsEvent was designed with ACP alignment in mind.

### ACP Session Lifecycle → InsightsEvent

#### `initialize` (request/response)

Client sends capabilities, agent responds with its capabilities.

```json
// Request (Client → Agent)
{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
  "protocolVersion": 1,
  "clientCapabilities": {"fileSystem": true, "terminals": true}
}}

// Response (Agent → Client)
{"jsonrpc": "2.0", "id": 1, "result": {
  "protocolVersion": 1,
  "agentCapabilities": {"streaming": true, "loadSession": true}
}}
```

**→ Part of `SessionInitEvent`** (combined with `session/new`).

#### `session/new` (request/response)

Creates a conversation session.

```json
// Request
{"jsonrpc": "2.0", "id": 2, "method": "session/new", "params": {
  "cwd": "/Users/zaf/project",
  "mcpServers": []
}}

// Response
{"jsonrpc": "2.0", "id": 2, "result": {
  "sessionId": "sess-abc-123"
}}
```

**→ `SessionInitEvent`**

| ACP field | InsightsEvent field |
|-----------|---------------------|
| `result.sessionId` | `sessionId` |
| From capabilities | `extensions['acp.capabilities']` |
| — | `model` = null (ACP doesn't report model in session/new) |
| — | Most Claude-specific fields = null |

### `session/prompt` → `session/update`* → response

The core conversation flow. Client sends a prompt, agent streams updates, then returns a final response.

#### Prompt request

```json
{"jsonrpc": "2.0", "id": 3, "method": "session/prompt", "params": {
  "sessionId": "sess-abc-123",
  "prompt": [{"type": "text", "text": "Fix the login bug"}]
}}
```

**→ `UserInputEvent`** (emitted by the SDK when it sends the prompt)

#### `session/update` notifications

The agent streams progress via notifications. These carry different update kinds.

##### `agent_message_chunk`

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "agent_message_chunk",
    "content": {"type": "text", "text": "I'll fix the login..."}
  }
}}
```

**→ `TextEvent`** (or `StreamDeltaEvent` if treated as a delta)

| ACP field | InsightsEvent field |
|-----------|---------------------|
| `content.text` | `text` |
| — | `kind` = `TextKind.text` |

ACP message chunks are partial — they arrive incrementally. The SDK can either:
- Emit a `StreamDeltaEvent` per chunk (like Claude streaming)
- Buffer and emit a single `TextEvent` when the message is complete
- Both (delta for UI, finalized event for persistence)

##### `agent_thought_chunk`

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "agent_thought_chunk",
    "content": {"type": "text", "text": "Let me analyze the auth flow..."}
  }
}}
```

**→ `TextEvent`** with `kind: TextKind.thinking`

##### `user_message_chunk`

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "user_message_chunk",
    "content": {"type": "text", "text": "Replaying a prior user turn"}
  }
}}
```

**→ `UserInputEvent`** with `isSynthetic: true`

##### `plan`

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "plan",
    "entries": [{"text": "Step 1"}, {"text": "Step 2"}]
  }
}}
```

**→ `TextEvent`** with `kind: TextKind.plan` and full entries in
`extensions['acp.planEntries']`.

##### `config_option_update`

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "config_option_update",
    "configOptions": [{"id": "model", "values": ["model-a", "model-b"]}]
  }
}}
```

**→ `ConfigOptionsEvent`**

##### `available_commands_update`

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "available_commands_update",
    "availableCommands": [{"id": "help", "name": "Help"}]
  }
}}
```

**→ `AvailableCommandsEvent`**

##### `current_mode_update`

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "current_mode_update",
    "currentModeId": "fast"
  }
}}
```

**→ `SessionModeEvent`**

##### `tool_call_update`

The richest ACP event type — reports tool invocations and their progress.

```json
{"jsonrpc": "2.0", "method": "session/update", "params": {
  "sessionId": "sess-abc-123",
  "update": {
    "sessionUpdate": "tool_call_update",
    "toolCall": {
      "toolCallId": "call-001",
      "title": "Reading login controller",
      "kind": "read",
      "status": "in_progress",
      "content": {"type": "content", "content": {"type": "text", "text": "Reading /src/auth/login.dart..."}},
      "locations": ["/src/auth/login.dart"],
      "rawInput": {"path": "/src/auth/login.dart"}
    }
  }
}}
```

ACP tool call updates can report multiple status transitions:

| `status` | InsightsEvent |
|----------|---------------|
| `pending` | `ToolInvocationEvent` (initial) |
| `in_progress` | Update to existing event (or second `ToolInvocationEvent`) |
| `completed` | `ToolCompletionEvent` |
| `failed` | `ToolCompletionEvent` with `isError: true` |

**→ `ToolInvocationEvent`** (on first update with `pending` or `in_progress`):

| ACP field | InsightsEvent field |
|-----------|---------------------|
| `toolCallId` | `callId` |
| `kind` | `kind` → `ToolKind` (direct mapping!) |
| `title` | `title` |
| `rawInput` | `input` |
| `locations` | `locations` |

**→ `ToolCompletionEvent`** (on update with `completed` or `failed`):

| ACP field | InsightsEvent field |
|-----------|---------------------|
| `toolCallId` | `callId` |
| `status` | `status` → `ToolCallStatus` |
| `content` | `content` (ACP content blocks → InsightsEvent content blocks) |
| `rawOutput` | `output` |

**ACP `kind` → `ToolKind` mapping:**

| ACP `kind` | `ToolKind` | Notes |
|------------|------------|-------|
| `read` | `read` | Direct match |
| `edit` | `edit` | Direct match |
| `delete` | `delete` | Direct match |
| `move` | `move` | Direct match |
| `search` | `search` | Direct match |
| `execute` | `execute` | Direct match |
| `think` | `think` | Direct match |
| `fetch` | `fetch` | Direct match |
| `browse` | `browse` | Direct match |
| `ask` | `ask` | Direct match |
| `memory` | `memory` | Direct match |
| `mcp` | `mcp` | Direct match |
| `other` | `other` | Direct match |

This is why InsightsEvent's `ToolKind` was designed to align with ACP — the mapping is trivial.

**Tool content mapping:**

- `content.type == "content"` → parse `content.content` into `ContentBlock` list.
- `content.type == "diff"` or `content.type == "terminal"` → stored in
  `ToolCompletionEvent.output` and `extensions['acp.toolContent']`.

#### Prompt response

```json
{"jsonrpc": "2.0", "id": 3, "result": {
  "stopReason": "end_turn"
}}
```

**→ `TurnCompleteEvent`**

| ACP field | InsightsEvent field |
|-----------|---------------------|
| `stopReason` | `subtype` |
| `stopReason != "end_turn"` | `isError` (if error stop reason) |
| — | All cost/duration/usage fields = null |

### `session/request_permission` (Agent → Client)

ACP's permission model. The request uses a `ToolCallUpdate` payload.

```json
{"jsonrpc": "2.0", "id": 100, "method": "session/request_permission", "params": {
  "sessionId": "sess-abc-123",
  "toolCall": {
    "toolCallId": "call-77",
    "title": "Run tests",
    "kind": "execute",
    "rawInput": {"command": "npm test"}
  },
  "options": [
    {"optionId": "allow_once", "name": "Allow once", "kind": "allow_once"},
    {"optionId": "allow_always", "name": "Always allow", "kind": "allow_always"},
    {"optionId": "reject_once", "name": "Reject once", "kind": "reject_once"},
    {"optionId": "reject_always", "name": "Always reject", "kind": "reject_always"}
  ]
}}
```

**→ `PermissionRequestEvent`**

| ACP field | InsightsEvent field |
|-----------|---------------------|
| `id` (JSON-RPC) | `requestId` |
| `toolCall.title` / `toolCall.kind` | `toolName` |
| `toolCall.kind` | `toolKind` |
| `toolCall.rawInput` | `toolInput` |
| `toolCall.toolCallId` | `toolUseId` |
| `options` | `extensions['acp.options']` |

**Response (selected option):**
```json
{"jsonrpc": "2.0", "id": 100, "result": {
  "outcome": {"outcome": "selected", "optionId": "allow_once"}
}}
```

**Response (cancelled):**
```json
{"jsonrpc": "2.0", "id": 100, "result": {
  "outcome": {"outcome": "cancelled"}
}}
```

The UI renders the ACP options list and returns the chosen `optionId` via
`updatedInput` so the backend can send `outcome: selected`.

### File System Operations (Agent → Client)

ACP agents can request file operations from the client.

```json
{"jsonrpc": "2.0", "id": 101, "method": "fs/read_text_file", "params": {
  "sessionId": "sess-abc-123",
  "path": "/src/auth/login.dart",
  "line": 1,
  "limit": 50
}}
```

These are **not InsightsEvents** — they are handled by the ACP SDK internally (the SDK reads the file and responds). However, they could optionally emit a `ToolInvocationEvent` with `kind: ToolKind.read` for visibility.

Similarly for `fs/write_text_file` (with `content`) and `terminal/*` operations.

### Terminal Operations (Agent → Client)

ACP agents can create and manage terminals.

```json
{"jsonrpc": "2.0", "id": 102, "method": "terminal/create", "params": {
  "sessionId": "sess-abc-123",
  "command": "npm test",
  "cwd": "/project",
  "outputByteLimit": 65536
}}
```

The SDK creates a real terminal process and streams output back via `terminal/output` requests. This maps naturally to:

**→ `ToolInvocationEvent`** with `kind: ToolKind.execute`

Terminal output responses map to:

**→ `ToolCompletionEvent`** with `TerminalBlock` content

## Gemini CLI `stream-json` (Alternative Path)

If integrating Gemini CLI directly (without ACP), its `stream-json` format is simpler:

### Event Types

```jsonl
{"type":"init","timestamp":"...","session_id":"abc123","model":"gemini-2.0-flash-exp"}
{"type":"message","role":"user","content":"Fix the bug","timestamp":"..."}
{"type":"tool_use","tool_name":"Bash","tool_id":"bash-123","parameters":{"command":"ls -la"},"timestamp":"..."}
{"type":"tool_result","tool_id":"bash-123","status":"success","output":"file1.txt\nfile2.txt","timestamp":"..."}
{"type":"message","role":"assistant","content":"Here are the files...","delta":true,"timestamp":"..."}
{"type":"result","status":"success","stats":{"total_tokens":250,"input_tokens":50,"output_tokens":200,"duration_ms":3000,"tool_calls":1},"timestamp":"..."}
```

### Gemini `stream-json` → InsightsEvent

| Gemini event | InsightsEvent |
|-------------|---------------|
| `init` | `SessionInitEvent(sessionId, model)` |
| `message` (role=user) | `UserInputEvent(text)` |
| `message` (role=assistant, delta=false) | `TextEvent(text, kind: text)` |
| `message` (role=assistant, delta=true) | `StreamDeltaEvent(textDelta, kind: text)` |
| `tool_use` | `ToolInvocationEvent(callId: tool_id, toolName: tool_name, input: parameters)` |
| `tool_result` | `ToolCompletionEvent(callId: tool_id, output, isError: status != "success")` |
| `error` | `SessionStatusEvent(status: error, message)` |
| `result` | `TurnCompleteEvent(usage: stats, durationMs: stats.duration_ms)` |

### Gemini tool names → ToolKind

| Gemini Tool | ToolKind |
|------------|----------|
| `ShellTool` / `Bash` | `execute` |
| `ReadFileTool` | `read` |
| `WriteFileTool` | `edit` |
| `EditTool` | `edit` |
| `GrepTool` | `search` |
| `GlobTool` | `search` |
| `WebFetchTool` | `fetch` |
| `WebSearchTool` | `browse` |
| `MemoryTool` | `memory` |
| MCP-prefixed | `mcp` |

### Gemini Limitations

| Feature | Status |
|---------|--------|
| Bidirectional communication | Limited — primarily one-shot prompts |
| Runtime permission callbacks | Not yet supported in stream-json mode |
| Session resume | `--resume` flag with `--prompt` (deprecated path) |
| Multi-turn interactive | `--prompt-interactive` (but no stream-json input) |
| Streaming | `delta: true` on message events |
| Cost tracking | Not reported |
| Context window | Not reported |
| Subagents | Not reported |

## Recommendation: ACP First, stream-json as Fallback

For Gemini integration:

1. **Primary path: ACP** — Use the ACP protocol, which Gemini CLI supports. This gives you bidirectional communication, permission handling, file system access, and terminal management.

2. **Fallback: stream-json** — For simpler "fire and forget" monitoring of Gemini CLI runs (CI/CD, batch processing), the stream-json format works but lacks interactivity.

For **any other ACP-compatible agent** (Goose, Qwen Code, future agents):

- The ACP SDK handles everything. No agent-specific code needed.
- The agent connects, negotiates capabilities, and starts streaming events.
- InsightsEvent captures what the agent provides and gracefully degrades for missing features.

## What ACP Agents Don't Provide (vs Claude)

| Feature | Impact |
|---------|--------|
| Cost tracking | No cost badge |
| Per-model usage | No model breakdown |
| Context window | No context meter |
| Permission suggestions | No auto-approve rules |
| Compaction events | No compaction indicators |
| Account info | No account badge |
| `parentToolUseId` | No subagent routing (unless agent implements it) |
| MCP server status | No MCP panel |
| Structured tool results (`tool_use_result`) | Falls back to `content` |

These all degrade gracefully — the UI hides what's not available.
