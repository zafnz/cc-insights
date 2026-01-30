# JSON Protocol Specification

This document defines the JSON line protocol between the Dart SDK and Node backend.

## Transport

- **Format:** Newline-delimited JSON (JSON Lines / NDJSON)
- **Direction:** Bidirectional over stdin/stdout
- **Encoding:** UTF-8
- **Logging:** Debug output goes to stderr (never stdout)

Each message is a single line of JSON followed by `\n`.

## Message Envelope

All messages follow this structure:

```typescript
{
  "type": string,       // Message type identifier
  "id": string?,        // Optional correlation ID for request/response
  "session_id": string?, // Session identifier (when applicable)
  "payload": object     // Message-specific data
}
```

---

## Dart → Backend Messages

### `session.create`

Create a new Claude session.

```typescript
{
  "type": "session.create",
  "id": "uuid",  // Correlation ID for response
  "payload": {
    "prompt": "string",           // Initial prompt
    "cwd": "string",              // Working directory
    "options": {                  // All optional
      "model": "string",
      "permission_mode": "default" | "acceptEdits" | "bypassPermissions" | "plan",
      "allowed_tools": ["string"],
      "disallowed_tools": ["string"],
      "system_prompt": "string" | { "type": "preset", "preset": "claude_code", "append": "string?" },
      "max_turns": number,
      "max_budget_usd": number,
      "max_thinking_tokens": number,
      "include_partial_messages": boolean,
      "enable_file_checkpointing": boolean,
      "additional_directories": ["string"],
      "mcp_servers": { [name]: McpServerConfig },
      "agents": { [name]: AgentDefinition },
      "hooks": { [event]: HookConfig[] },
      "sandbox": SandboxSettings,
      "setting_sources": ["user" | "project" | "local"],
      "betas": ["string"],
      "output_format": { "type": "json_schema", "schema": object },
      "fallback_model": "string"
    }
  }
}
```

**Response:** `session.created` or `error`

---

### `session.send`

Send a follow-up message to an existing session.

```typescript
{
  "type": "session.send",
  "id": "uuid",
  "session_id": "string",
  "payload": {
    "message": "string"   // User's message
  }
}
```

**Response:** Continues with `sdk.message` stream

---

### `session.interrupt`

Interrupt the current execution.

```typescript
{
  "type": "session.interrupt",
  "id": "uuid",
  "session_id": "string",
  "payload": {}
}
```

**Response:** `session.interrupted` or `error`

---

### `session.kill`

Terminate a session permanently.

```typescript
{
  "type": "session.kill",
  "id": "uuid",
  "session_id": "string",
  "payload": {}
}
```

**Response:** `session.killed` or `error`

---

### `callback.response`

Respond to a `callback.request` (canUseTool or hook).

```typescript
{
  "type": "callback.response",
  "id": "string",  // Must match callback.request id
  "session_id": "string",
  "payload": {
    // For canUseTool:
    "behavior": "allow" | "deny",
    "updated_input": object?,      // Modified tool input (allow only)
    "message": "string?",          // Denial reason (deny only)
    "updated_permissions": [...]?, // Permission updates (allow only)

    // For hooks:
    "continue": boolean?,
    "decision": "approve" | "block"?,
    "system_message": "string?",
    "reason": "string?",
    "hook_specific_output": object?
  }
}
```

---

### `query.call`

Call a method on the Query object.

```typescript
{
  "type": "query.call",
  "id": "uuid",
  "session_id": "string",
  "payload": {
    "method": "supportedModels" | "supportedCommands" | "mcpServerStatus" |
              "accountInfo" | "setModel" | "setPermissionMode" |
              "setMaxThinkingTokens" | "rewindFiles",
    "args": any[]  // Method arguments
  }
}
```

**Response:** `query.result` or `error`

---

## Backend → Dart Messages

### `session.created`

Session successfully created.

```typescript
{
  "type": "session.created",
  "id": "uuid",  // Correlation ID from request
  "session_id": "string",  // Backend-generated session ID
  "payload": {
    "sdk_session_id": "string"  // SDK's internal session ID (for resume)
  }
}
```

---

### `sdk.message`

Raw SDK message, forwarded verbatim.

```typescript
{
  "type": "sdk.message",
  "session_id": "string",
  "payload": SDKMessage  // Exact SDK message, see SDK Message Types
}
```

The `payload` is the raw SDK message with its original structure:

```typescript
// Examples of payload content:
{ "type": "system", "subtype": "init", "session_id": "...", ... }
{ "type": "assistant", "uuid": "...", "message": {...}, ... }
{ "type": "user", "uuid": "...", "message": {...}, ... }
{ "type": "result", "subtype": "success", ... }
{ "type": "stream_event", "event": {...}, ... }
```

---

### `callback.request`

Backend needs a response for canUseTool or hook.

```typescript
{
  "type": "callback.request",
  "id": "uuid",  // Use this ID in callback.response
  "session_id": "string",
  "payload": {
    "callback_type": "can_use_tool" | "hook",

    // For can_use_tool:
    "tool_name": "string?",
    "tool_input": object?,
    "suggestions": PermissionUpdate[]?,

    // For hooks:
    "hook_event": "PreToolUse" | "PostToolUse" | "PostToolUseFailure" |
                  "Notification" | "UserPromptSubmit" | "SessionStart" |
                  "SessionEnd" | "Stop" | "SubagentStart" | "SubagentStop" |
                  "PreCompact" | "PermissionRequest",
    "hook_input": object,  // Hook-specific input data
    "tool_use_id": "string?"
  }
}
```

**Must respond with:** `callback.response` using the same `id`

---

### `query.result`

Response to a `query.call`.

```typescript
{
  "type": "query.result",
  "id": "uuid",  // Correlation ID from request
  "session_id": "string",
  "payload": {
    "success": boolean,
    "result": any,      // Method return value
    "error": "string?"  // Error message if success=false
  }
}
```

---

### `session.interrupted`

Session was successfully interrupted.

```typescript
{
  "type": "session.interrupted",
  "id": "uuid",
  "session_id": "string",
  "payload": {}
}
```

---

### `session.killed`

Session was terminated.

```typescript
{
  "type": "session.killed",
  "id": "uuid",
  "session_id": "string",
  "payload": {}
}
```

---

### `error`

An error occurred.

```typescript
{
  "type": "error",
  "id": "uuid?",       // Correlation ID if responding to request
  "session_id": "string?",
  "payload": {
    "code": "string",     // Error code
    "message": "string",  // Human-readable message
    "details": object?    // Additional error details
  }
}
```

**Error codes:**
- `INVALID_MESSAGE` - Malformed or unknown message
- `SESSION_NOT_FOUND` - Session ID doesn't exist
- `SESSION_CREATE_FAILED` - Failed to create session
- `CALLBACK_TIMEOUT` - Callback response not received in time
- `CALLBACK_NOT_FOUND` - Callback ID doesn't exist
- `QUERY_METHOD_FAILED` - Query method threw error
- `SDK_ERROR` - Error from Claude SDK

---

## Message Flows

### Session Lifecycle

```
Dart                              Backend                           SDK
 │                                   │                               │
 │─── session.create ───────────────>│                               │
 │                                   │─── query({ prompt, ... }) ───>│
 │                                   │                               │
 │<── session.created ───────────────│                               │
 │                                   │                               │
 │                                   │<── SDKSystemMessage ──────────│
 │<── sdk.message (system/init) ─────│                               │
 │                                   │                               │
 │                                   │<── SDKAssistantMessage ───────│
 │<── sdk.message (assistant) ───────│                               │
 │                                   │                               │
 │                                   │<── (canUseTool callback) ─────│
 │<── callback.request ──────────────│                               │
 │                                   │         (waiting...)          │
 │─── callback.response ────────────>│                               │
 │                                   │─── (resolve callback) ───────>│
 │                                   │                               │
 │                                   │<── SDKUserMessage (result) ───│
 │<── sdk.message (user) ────────────│                               │
 │                                   │                               │
 │                                   │<── SDKResultMessage ──────────│
 │<── sdk.message (result) ──────────│                               │
 │                                   │                               │
 │─── session.send ─────────────────>│                               │
 │                                   │─── query({ resume, ... }) ───>│
 │                                   │           ...                 │
```

### Callback Flow (canUseTool)

```
Dart                              Backend                           SDK
 │                                   │                               │
 │                                   │<── canUseTool(tool, input) ───│
 │                                   │                               │
 │                                   │    (create pending Promise)   │
 │                                   │                               │
 │<── callback.request ──────────────│                               │
 │    {                              │                               │
 │      id: "cb-123",                │                               │
 │      callback_type: "can_use_tool"│                               │
 │      tool_name: "Bash",           │                               │
 │      tool_input: { command: ... } │                               │
 │    }                              │                               │
 │                                   │                               │
 │    (show permission UI)           │                               │
 │    (user clicks approve)          │                               │
 │                                   │                               │
 │─── callback.response ────────────>│                               │
 │    {                              │                               │
 │      id: "cb-123",                │                               │
 │      behavior: "allow",           │                               │
 │      updated_input: { ... }       │                               │
 │    }                              │                               │
 │                                   │                               │
 │                                   │    (resolve Promise)          │
 │                                   │─── return { allow, ... } ────>│
 │                                   │                               │
```

### Query Method Call

```
Dart                              Backend
 │                                   │
 │─── query.call ───────────────────>│
 │    {                              │
 │      id: "qc-456",                │
 │      method: "supportedModels",   │
 │      args: []                     │
 │    }                              │
 │                                   │
 │                                   │    query.supportedModels()
 │                                   │
 │<── query.result ──────────────────│
 │    {                              │
 │      id: "qc-456",                │
 │      success: true,               │
 │      result: [                    │
 │        { value: "...", ... }      │
 │      ]                            │
 │    }                              │
```

---

## SDK Message Types Reference

The `sdk.message` payload contains the raw SDK message. See [06-sdk-message-types.md](./06-sdk-message-types.md) for the complete type definitions.

Summary of SDK message types:

| Type | Subtype | Description |
|------|---------|-------------|
| `system` | `init` | Session initialization info |
| `system` | `compact_boundary` | Context was compacted |
| `assistant` | - | Assistant response with content blocks |
| `user` | - | User message or tool results |
| `result` | `success` | Turn completed successfully |
| `result` | `error_*` | Turn ended with error |
| `stream_event` | - | Partial message (when streaming enabled) |

---

## Configuration Types

### McpServerConfig

```typescript
McpServerConfig =
  | { type?: "stdio", command: string, args?: string[], env?: object }
  | { type: "sse", url: string, headers?: object }
  | { type: "http", url: string, headers?: object }
```

### AgentDefinition

```typescript
{
  "description": "string",   // When to use this agent
  "prompt": "string",        // Agent's system prompt
  "tools": ["string"]?,      // Allowed tools (optional)
  "model": "sonnet" | "opus" | "haiku" | "inherit"?
}
```

### SandboxSettings

```typescript
{
  "enabled": boolean?,
  "auto_allow_bash_if_sandboxed": boolean?,
  "excluded_commands": ["string"]?,
  "allow_unsandboxed_commands": boolean?,
  "network": {
    "allow_local_binding": boolean?,
    "allow_unix_sockets": ["string"]?,
    "allow_all_unix_sockets": boolean?
  }?,
  "ignore_violations": {
    "file": ["string"]?,
    "network": ["string"]?
  }?
}
```

### HookConfig

```typescript
{
  "matcher": "string?",  // Tool name pattern (e.g., "Bash", "Write|Edit")
  // Note: Actual hook callbacks are handled via callback.request/response
}
```
