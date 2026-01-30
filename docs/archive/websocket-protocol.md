# WebSocket Protocol Specification

This document defines the WebSocket protocol between the Flutter frontend and the backend server for Claude Agent Insights.

## Connection

- **Default Host:** `localhost`
- **Default Port:** `8765`
- **Protocol:** `ws://`
- **Message Format:** JSON strings

## Message Structure

All messages follow this structure:

```json
{
  "type": "message.type",
  "id": "uuid-v4 (optional, client-generated)",
  "payload": { ... }
}
```

---

## Client → Server Messages

### `session.create`

Creates a new Claude session.

```json
{
  "type": "session.create",
  "id": "uuid-v4",
  "payload": {
    "prompt": "string - the initial prompt for Claude",
    "cwd": "string - working directory for the session",
    "allowed_tools": ["string array - tool names (typically empty)"],
    "permission_mode": "string - 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan'",
    "model": "string - 'sonnet' | 'opus' | 'haiku'"
  }
}
```

**Response:** `session.created`, then `agent.spawned` for main agent

---

### `user.input`

Sends user input to a session. Used for:
- Answering questions from `agent.question`
- Resuming conversation after `session.completed`

```json
{
  "type": "user.input",
  "id": "uuid-v4",
  "payload": {
    "session_id": "string",
    "agent_id": "string | null - target agent (null = main)",
    "text": "string - user's input"
  }
}
```

---

### `session.kill`

Terminates a session permanently.

```json
{
  "type": "session.kill",
  "id": "uuid-v4",
  "payload": {
    "session_id": "string"
  }
}
```

---

### `session.interrupt`

Stops current execution but preserves session for resumption.

```json
{
  "type": "session.interrupt",
  "id": "uuid-v4",
  "payload": {
    "session_id": "string"
  }
}
```

---

### `permission_mode.change`

Changes the permission mode for a running session.

```json
{
  "type": "permission_mode.change",
  "id": "uuid-v4",
  "payload": {
    "session_id": "string",
    "permission_mode": "string - 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan'"
  }
}
```

**Response:** `permission_mode.changed`

---

### `permission.response`

Responds to a permission request (approve or deny tool use).

```json
{
  "type": "permission.response",
  "id": "uuid-v4",
  "payload": {
    "session_id": "string",
    "permission_id": "string - from permission.request",
    "approved": "boolean"
  }
}
```

---

## Server → Client Messages

### `session.created`

Confirms session creation.

```json
{
  "type": "session.created",
  "payload": {
    "session_id": "string"
  }
}
```

---

### `agent.spawned`

A new agent was created (main agent or Task subagent).

```json
{
  "type": "agent.spawned",
  "payload": {
    "session_id": "string",
    "agent_id": "string - 'main' or tool_use_id for subagents",
    "parent_id": "string | null - parent agent ID",
    "label": "string - display name ('Main', 'Sub1', 'Sub1.1')",
    "task_description": "string | null - prompt/description for this agent"
  }
}
```

---

### `agent.output`

Text or thinking output from an agent.

```json
{
  "type": "agent.output",
  "payload": {
    "session_id": "string",
    "agent_id": "string",
    "content": "string - the output text",
    "content_type": "string - 'text' | 'thinking'"
  }
}
```

---

### `agent.tool_use`

Agent is invoking a tool.

```json
{
  "type": "agent.tool_use",
  "payload": {
    "session_id": "string",
    "agent_id": "string",
    "tool_name": "string - e.g., 'Read', 'Write', 'Bash', 'Task'",
    "tool_input": "object - tool parameters",
    "tool_use_id": "string - unique ID for this tool invocation",
    "model": "string | null"
  }
}
```

**Note:** For `Task` tool, `tool_use_id` becomes the `agent_id` of the spawned subagent.

---

### `agent.tool_result`

Result of tool execution.

```json
{
  "type": "agent.tool_result",
  "payload": {
    "session_id": "string",
    "agent_id": "string",
    "tool_use_id": "string - matches tool_use",
    "result": "string - tool output",
    "is_error": "boolean"
  }
}
```

---

### `agent.question`

Agent is asking a question (via AskUserQuestion tool).

```json
{
  "type": "agent.question",
  "payload": {
    "session_id": "string",
    "agent_id": "string",
    "question_id": "string",
    "question": "string - the question text",
    "options": [
      {
        "label": "string",
        "description": "string | null"
      }
    ]
  }
}
```

**Response required:** `user.input` with answer text

---

### `agent.completed`

An agent (typically a subagent) has finished.

```json
{
  "type": "agent.completed",
  "payload": {
    "session_id": "string",
    "agent_id": "string",
    "result": "string | null - final result/summary",
    "usage": {
      "input_tokens": "integer",
      "output_tokens": "integer",
      "cache_read_tokens": "integer",
      "cache_creation_tokens": "integer",
      "cost_usd": "float"
    }
  }
}
```

---

### `agent.status`

Agent status changed.

```json
{
  "type": "agent.status",
  "payload": {
    "session_id": "string",
    "agent_id": "string",
    "status": "string - 'working' | 'waiting_tool' | 'waiting_user' | 'completed' | 'error'"
  }
}
```

---

### `session.completed`

A conversation turn has completed. Session remains alive for follow-ups.

```json
{
  "type": "session.completed",
  "payload": {
    "session_id": "string",
    "total_usage": {
      "input_tokens": "integer",
      "output_tokens": "integer",
      "cache_read_tokens": "integer",
      "cache_creation_tokens": "integer",
      "cost_usd": "float"
    }
  }
}
```

**Note:** After this message, send `user.input` to continue the conversation.

---

### `permission_mode.changed`

Permission mode was updated.

```json
{
  "type": "permission_mode.changed",
  "payload": {
    "session_id": "string",
    "permission_mode": "string"
  }
}
```

---

### `permission.request`

Backend requires user approval for a tool.

```json
{
  "type": "permission.request",
  "payload": {
    "session_id": "string",
    "agent_id": "string",
    "permission_id": "string",
    "tool_name": "string",
    "tool_input": "object - tool parameters",
    "tool_use_id": "string"
  }
}
```

**Response required:** `permission.response`

---

### `error`

An error occurred.

```json
{
  "type": "error",
  "payload": {
    "session_id": "string | null",
    "agent_id": "string | null",
    "message": "string - human-readable error",
    "code": "string - error code"
  }
}
```

**Error Codes:**
- `INVALID_JSON` - Failed to parse message
- `INVALID_MESSAGE` - Unknown message type or validation failed
- `HANDLER_ERROR` - Error processing message
- `SESSION_CREATE_FAILED` - Failed to create session
- `SESSION_NOT_FOUND` - Session ID not found
- `INPUT_FAILED` - Failed to process user input
- `INTERRUPT_FAILED` - Failed to interrupt session
- `PERMISSION_MODE_CHANGE_FAILED` - Failed to change mode
- `PERMISSION_RESPONSE_FAILED` - Permission request not found

---

## Message Flows

### Session Lifecycle

```
Client                          Server
  |                               |
  |--- session.create ----------->|
  |                               |
  |<-- session.created -----------|
  |<-- agent.spawned (main) ------|
  |                               |
  |<-- agent.output --------------|  (streaming)
  |<-- agent.tool_use ------------|
  |<-- agent.tool_result ---------|
  |     ...                       |
  |                               |
  |<-- session.completed ---------|
  |                               |
  |--- user.input (follow-up) --->|  (resume)
  |                               |
  |<-- agent.output --------------|
  |     ...                       |
  |                               |
  |--- session.kill ------------->|  (end)
```

### Permission Flow

```
Client                          Server
  |                               |
  |<-- agent.tool_use ------------|
  |<-- permission.request --------|
  |                               |
  |    (user approves/denies)     |
  |                               |
  |--- permission.response ------>|
  |                               |
  |<-- agent.tool_result ---------|  (if approved)
```

### Question Flow

```
Client                          Server
  |                               |
  |<-- agent.question ------------|
  |                               |
  |    (user selects answer)      |
  |                               |
  |--- user.input --------------->|
  |                               |
  |<-- agent.output --------------|  (continues)
```

### Subagent (Task) Flow

```
Client                          Server
  |                               |
  |<-- agent.tool_use (Task) -----|  tool_use_id = X
  |<-- agent.spawned -------------|  agent_id = X
  |                               |
  |<-- agent.output (X) ----------|  (subagent output)
  |<-- agent.tool_use (X) --------|
  |<-- agent.tool_result (X) -----|
  |     ...                       |
  |                               |
  |<-- agent.tool_result (Task) --|  tool_use_id = X
  |<-- agent.completed (X) -------|
```

---

## Implementation Notes

1. **Field Naming:** All fields use `snake_case` (not camelCase)

2. **Null vs Absent:** Send explicit `null` for optional fields, not omit them

3. **Message ID:** The `id` field in client messages is client-generated for tracking; server does not echo it back

4. **Agent Hierarchy:**
   - Main agent has `agent_id = "main"`, `parent_id = null`
   - Subagents have `agent_id` = Task's `tool_use_id`, `parent_id` = parent agent's ID

5. **Session State:**
   - `isRunning = true` during processing
   - `isRunning = false` after `session.completed`
   - Sending `user.input` sets `isRunning = true` again

6. **Usage Tracking:**
   - Accumulate tokens across all agents
   - Cost calculation: input=$3/1M, output=$15/1M, cache_read=$0.30/1M, cache_creation=$3.75/1M
