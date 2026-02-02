# JSON Protocol Specification

This document defines the JSON line protocol between the Dart SDK and the Claude CLI.

## Transport

- **Format:** Newline-delimited JSON (JSON Lines / NDJSON)
- **Direction:** Bidirectional over stdin/stdout
- **Encoding:** UTF-8
- **Logging:** Debug output goes to stderr (never stdout)

Each message is a single line of JSON followed by `\n`.

## CLI Arguments

The Dart SDK spawns the Claude CLI with these required arguments:

```bash
claude --output-format stream-json \
       --input-format stream-json \
       --permission-prompt-tool stdio \
       --cwd <working-directory>
```

Optional arguments:
- `--model <model>` - Model selection (sonnet, opus, haiku)
- `--permission-mode <mode>` - Permission mode (default, acceptEdits, plan)
- `--max-turns <n>` - Maximum conversation turns
- `--verbose` - Enable verbose logging
- `--resume <session-id>` - Resume a previous session

---

## Dart → CLI Messages

### `control_request` (Initialize)

Initialize the session and get available commands/models.

```json
{
  "type": "control_request",
  "request_id": "uuid",
  "request": {
    "subtype": "initialize",
    "system_prompt": "optional custom system prompt",
    "mcp_servers": {},
    "agents": {},
    "hooks": {}
  }
}
```

**Response:** `control_response`

---

### `session.create`

Start a new conversation with an initial message.

```json
{
  "type": "session.create",
  "message": {
    "role": "user",
    "content": "Hello, Claude!"
  }
}
```

For multimodal content (text + images):

```json
{
  "type": "session.create",
  "message": {
    "role": "user",
    "content": [
      { "type": "text", "text": "What is in this image?" },
      { "type": "image", "source": { "type": "base64", "media_type": "image/png", "data": "..." } }
    ]
  }
}
```

**Response:** `session.created`, then SDK messages

---

### `session.send`

Send a follow-up message to an existing conversation.

```json
{
  "type": "session.send",
  "message": {
    "role": "user",
    "content": "Follow-up question..."
  }
}
```

**Response:** SDK messages continue streaming

---

### `control_request` (Interrupt)

Interrupt the current execution.

```json
{
  "type": "control_request",
  "request_id": "uuid",
  "request": {
    "subtype": "interrupt"
  }
}
```

**Response:** `control_response` and the session stops processing

---

### `callback.response`

Respond to a permission request from the CLI.

```json
{
  "type": "callback.response",
  "response": {
    "subtype": "success",
    "request_id": "original-request-id",
    "response": {
      "behavior": "allow",
      "updated_input": {},
      "updated_permissions": [],
      "tool_use_id": "tool-use-uuid"
    }
  }
}
```

For denial:

```json
{
  "type": "callback.response",
  "response": {
    "subtype": "success",
    "request_id": "original-request-id",
    "response": {
      "behavior": "deny",
      "message": "User denied permission",
      "tool_use_id": "tool-use-uuid"
    }
  }
}
```

---

## CLI → Dart Messages

### `control_response`

Response to `control_request` (initialize).

```json
{
  "type": "control_response",
  "request_id": "uuid",
  "response": {
    "commands": [
      { "name": "/help", "description": "..." },
      { "name": "/clear", "description": "..." }
    ],
    "output_style": "markdown",
    "available_output_styles": ["markdown", "json"],
    "models": [
      { "value": "sonnet", "display": "Sonnet (Fast)" },
      { "value": "opus", "display": "Opus (Powerful)" }
    ],
    "account": {
      "account_type": "pro",
      "email": "user@example.com"
    }
  }
}
```

---

### `session.created`

Session successfully created.

```json
{
  "type": "session.created",
  "session_id": "session-uuid"
}
```

---

### `system`

System initialization message with tools and MCP servers.

```json
{
  "type": "system",
  "subtype": "init",
  "session_id": "session-uuid",
  "tools": [
    { "name": "Bash", "description": "Execute bash commands" },
    { "name": "Read", "description": "Read file contents" }
  ],
  "mcp_servers": []
}
```

---

### `assistant`

Assistant response with content blocks.

```json
{
  "type": "assistant",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "message": {
    "type": "message",
    "content": [
      { "type": "text", "text": "Hello! How can I help you?" }
    ]
  },
  "model": "sonnet",
  "usage": {
    "input_tokens": 100,
    "output_tokens": 50,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0
  }
}
```

---

### `user`

User message or tool results.

```json
{
  "type": "user",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "message": {
    "type": "message",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "tool-use-uuid",
        "content": "Command output..."
      }
    ]
  }
}
```

---

### `result`

Turn completion status.

```json
{
  "type": "result",
  "subtype": "success",
  "session_id": "session-uuid",
  "turn_count": 1,
  "duration_seconds": 5.2,
  "usage": {
    "input_tokens": 100,
    "output_tokens": 50
  }
}
```

Error result:

```json
{
  "type": "result",
  "subtype": "error_max_turns",
  "session_id": "session-uuid",
  "error": "Maximum turns exceeded"
}
```

---

### `callback.request`

Permission request for tool execution.

```json
{
  "type": "callback.request",
  "request_id": "callback-uuid",
  "request": {
    "subtype": "can_use_tool",
    "tool_name": "Bash",
    "input": {
      "command": "ls -la"
    },
    "tool_use_id": "tool-use-uuid",
    "permission_suggestions": [
      {
        "type": "bash",
        "action": "allow",
        "pattern": "ls *",
        "scope": "session"
      }
    ],
    "blocked_path": null
  }
}
```

**Must respond with:** `callback.response` using the same `request_id`

---

### `error`

An error occurred.

```json
{
  "type": "error",
  "error": {
    "code": "SESSION_NOT_FOUND",
    "message": "Session not found"
  }
}
```

---

## Message Flows

### Session Initialization

```
Dart                              CLI
 │                                 │
 │─── control_request ────────────>│
 │    (subtype: "initialize")      │
 │                                 │
 │<── control_response ────────────│
 │    (commands, models, account)  │
 │                                 │
 │<── system ──────────────────────│
 │    (subtype: "init", tools)     │
 │                                 │
 │─── session.create ─────────────>│
 │    (initial user message)       │
 │                                 │
 │<── session.created ─────────────│
 │    (session_id)                 │
 │                                 │
 │<── assistant ───────────────────│
 │    (response content)           │
 │                                 │
 │<── result ──────────────────────│
 │    (subtype: "success")         │
```

### Permission Request Flow

```
Dart                              CLI
 │                                 │
 │<── callback.request ────────────│
 │    {                            │
 │      request_id: "cb-123",      │
 │      request: {                 │
 │        subtype: "can_use_tool", │
 │        tool_name: "Bash",       │
 │        input: { command: ... }  │
 │      }                          │
 │    }                            │
 │                                 │
 │    (show permission UI)         │
 │    (user clicks approve)        │
 │                                 │
 │─── callback.response ──────────>│
 │    {                            │
 │      response: {                │
 │        subtype: "success",      │
 │        request_id: "cb-123",    │
 │        response: {              │
 │          behavior: "allow"      │
 │        }                        │
 │      }                          │
 │    }                            │
 │                                 │
 │<── user ────────────────────────│
 │    (tool_result content)        │
 │                                 │
```

### Follow-up Message

```
Dart                              CLI
 │                                 │
 │─── session.send ───────────────>│
 │    (follow-up message)          │
 │                                 │
 │<── assistant ───────────────────│
 │    (response content)           │
 │                                 │
 │<── result ──────────────────────│
 │    (subtype: "success")         │
```

---

## SDK Message Types Reference

The CLI sends various message types. See [06-sdk-message-types.md](./06-sdk-message-types.md) for complete type definitions.

Summary of CLI message types:

| Type | Subtype | Description |
|------|---------|-------------|
| `control_response` | - | Response to initialize request |
| `session.created` | - | Session successfully created |
| `system` | `init` | Session initialization info |
| `system` | `compact_boundary` | Context was compacted |
| `assistant` | - | Assistant response with content blocks |
| `user` | - | User message or tool results |
| `result` | `success` | Turn completed successfully |
| `result` | `error_*` | Turn ended with error |
| `callback.request` | - | Permission request (can_use_tool) |
| `error` | - | Error occurred |
