# Direct Claude CLI Protocol Flow

This document describes the complete protocol for communicating directly with the claude-cli binary.

---

## Overview

When using `--permission-prompt-tool stdio`, the claude-cli communicates via JSON Lines over stdin/stdout. The protocol uses a unified `control_request`/`control_response` pattern for both initialization and permission callbacks.

```
Dart SDK ←→ claude-cli (stdin/stdout JSON Lines)
```

---

## CLI Arguments

```bash
claude \
  --output-format stream-json \
  --input-format stream-json \
  --model sonnet \
  --permission-mode default \
  --permission-prompt-tool stdio \
  --setting-sources user,project,local \
  --verbose
```

| Argument | Description |
|----------|-------------|
| `--output-format stream-json` | JSON Lines output (not human-readable) |
| `--input-format stream-json` | JSON Lines input |
| `--model <model>` | Model to use (sonnet, opus, haiku) |
| `--permission-mode <mode>` | Permission mode (default, acceptEdits, bypassPermissions, plan) |
| `--permission-prompt-tool stdio` | Use stdin/stdout for permission prompts |
| `--setting-sources <sources>` | Comma-separated: user, project, local, or empty |
| `--verbose` | Required for stream-json mode. Always included. |

**Additional arguments:**
- `--max-turns <n>` - Maximum conversation turns
- `--max-budget-usd <n>` - Maximum budget in USD
- `--cwd <path>` - Working directory
- `--resume <session-id>` - Resume previous session

**Environment variable:**
- `CLAUDE_CODE_PATH` - Path to claude-cli executable (alternative to system PATH)

---

## Session Lifecycle

### 1. Initialization

**Request (Dart → CLI):**
```json
{
  "request_id": "unique-id",
  "type": "control_request",
  "request": {
    "subtype": "initialize",
    "systemPrompt": "",
    "mcpServers": {},
    "agents": {},
    "hooks": {}
  }
}
```

**Response (CLI → Dart):**
```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "unique-id",
    "response": {
      "commands": [
        {"name": "compact", "description": "...", "argumentHint": "..."},
        {"name": "context", "description": "...", "argumentHint": ""}
      ],
      "output_style": "default",
      "available_output_styles": ["default", "Explanatory", "Learning"],
      "models": [
        {"value": "default", "displayName": "Default (recommended)", "description": "Opus 4.5"},
        {"value": "sonnet", "displayName": "Sonnet", "description": "Sonnet 4.5"},
        {"value": "haiku", "displayName": "Haiku", "description": "Haiku 4.5"}
      ],
      "account": {
        "email": "user@example.com",
        "organization": "Org Name",
        "subscriptionType": "Claude Max"
      }
    }
  }
}
```

### 2. System Init Message

After `control_response`, the CLI sends a `system` message with session info:

```json
{
  "type": "system",
  "subtype": "init",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "cwd": "/path/to/working/directory",
  "tools": ["Task", "Bash", "Read", "Write", "Edit", "..."],
  "mcp_servers": [{"name": "flutter-test", "status": "connected"}],
  "model": "claude-sonnet-4-5-20250929",
  "permissionMode": "default",
  "slash_commands": ["compact", "context", "cost", "..."],
  "apiKeySource": "none",
  "claude_code_version": "2.1.17",
  "output_style": "default",
  "agents": ["Bash", "general-purpose", "Explore", "Plan"],
  "skills": [],
  "plugins": []
}
```

### 3. Send User Message

**Request (Dart → CLI):**
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "Your message here"
  },
  "parent_tool_use_id": null,
  "session_id": "session-uuid"
}
```

**Note:** The `session_id` in user messages is for client tracking. The CLI uses its internal session from initialization.

---

## Message Flow

### Standard Turn (No Permission Required)

```
Dart                                    CLI
 │                                       │
 │─── control_request (initialize) ─────>│
 │<── control_response (success) ────────│
 │<── system (init) ─────────────────────│
 │                                       │
 │─── user message ─────────────────────>│
 │<── assistant (with tool_use) ─────────│
 │<── user (tool_result) ────────────────│
 │<── assistant (text response) ─────────│
 │<── result (success) ──────────────────│
```

### Turn with Permission Request

```
Dart                                    CLI
 │                                       │
 │─── user message ─────────────────────>│
 │<── assistant (with tool_use) ─────────│
 │                                       │
 │<── control_request (can_use_tool) ────│  ← CLI pauses here
 │                                       │
 │    (show permission UI)               │
 │    (user approves/denies)             │
 │                                       │
 │─── control_response (allow/deny) ────>│  ← CLI resumes
 │                                       │
 │<── user (tool_result) ────────────────│
 │<── assistant (response) ──────────────│
 │<── result (success) ──────────────────│
```

---

## Permission Protocol

### Permission Request (CLI → Dart)

The CLI sends a `control_request` with `subtype: "can_use_tool"`:

```json
{
  "type": "control_request",
  "request_id": "uuid",
  "request": {
    "subtype": "can_use_tool",
    "tool_name": "Bash",
    "input": {
      "command": "ls /tmp/test/",
      "description": "List contents of /tmp/test/ directory"
    },
    "tool_use_id": "toolu_xxx",
    "permission_suggestions": [
      {
        "type": "addRules",
        "rules": [
          {"toolName": "Read", "ruleContent": "//private/tmp/test/**"}
        ],
        "behavior": "allow",
        "destination": "session"
      }
    ],
    "blocked_path": "/private/tmp/test"
  }
}
```

| Field | Description |
|-------|-------------|
| `tool_name` | Name of the tool requesting permission |
| `input` | Tool input parameters |
| `tool_use_id` | Correlation ID for the tool use |
| `permission_suggestions` | Suggested permission rules (optional) |
| `blocked_path` | Path that triggered the permission check (optional) |

### Permission Response - Allow (Dart → CLI)

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "matching-uuid",
    "response": {
      "behavior": "allow",
      "updatedInput": {
        "command": "ls /tmp/test/",
        "description": "List contents of /tmp/test/ directory"
      },
      "updatedPermissions": [],
      "toolUseID": "toolu_xxx"
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `behavior` | `"allow"` to permit the tool |
| `updatedInput` | Modified tool input (optional, can change parameters) |
| `updatedPermissions` | Permission rules to add (from suggestions) |
| `toolUseID` | Must match the `tool_use_id` from request |

### Permission Response - Deny (Dart → CLI)

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "matching-uuid",
    "response": {
      "behavior": "deny",
      "message": "User declined this operation",
      "toolUseID": "toolu_xxx"
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `behavior` | `"deny"` to reject the tool |
| `message` | Reason for denial (shown to Claude) |
| `toolUseID` | Must match the `tool_use_id` from request |

---

## AskUserQuestion Special Handling

The `AskUserQuestion` tool uses permissions to collect user input. The response includes the user's answers in `updatedInput`:

### Request (CLI → Dart)

```json
{
  "type": "control_request",
  "request_id": "uuid",
  "request": {
    "subtype": "can_use_tool",
    "tool_name": "AskUserQuestion",
    "input": {
      "questions": [
        {
          "question": "Which color do you prefer?",
          "header": "Color",
          "multiSelect": false,
          "options": [
            {"label": "Red", "description": "Choose the color red"},
            {"label": "Green", "description": "Choose the color green"},
            {"label": "Blue", "description": "Choose the color blue"}
          ]
        }
      ]
    },
    "tool_use_id": "toolu_xxx"
  }
}
```

### Response with Answers (Dart → CLI)

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "uuid",
    "response": {
      "behavior": "allow",
      "updatedInput": {
        "answers": {
          "Which color do you prefer?": "Green"
        }
      },
      "toolUseID": "toolu_xxx"
    }
  }
}
```

The `answers` map uses the question text as the key and the selected option label as the value. For `multiSelect: true`, the value would be an array of selected labels.

---

## SDK Messages (CLI → Dart)

These messages are sent during normal operation:

### Assistant Message

```json
{
  "type": "assistant",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "parent_tool_use_id": null,
  "message": {
    "model": "claude-sonnet-4-5-20250929",
    "id": "msg_xxx",
    "type": "message",
    "role": "assistant",
    "content": [
      {"type": "text", "text": "I'll help you with that."},
      {"type": "tool_use", "id": "toolu_xxx", "name": "Read", "input": {"file_path": "/path"}}
    ],
    "stop_reason": null,
    "usage": {
      "input_tokens": 100,
      "output_tokens": 50,
      "cache_creation_input_tokens": 1000,
      "cache_read_input_tokens": 500
    }
  }
}
```

### User Message (Tool Results)

```json
{
  "type": "user",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "parent_tool_use_id": null,
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_xxx",
        "content": "file contents here...",
        "is_error": false
      }
    ]
  },
  "tool_use_result": {
    "stdout": "output",
    "stderr": "",
    "interrupted": false
  }
}
```

### Result Message

```json
{
  "type": "result",
  "subtype": "success",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "is_error": false,
  "duration_ms": 5000,
  "duration_api_ms": 4500,
  "num_turns": 2,
  "result": "Final text response",
  "total_cost_usd": 0.05,
  "usage": {
    "input_tokens": 200,
    "output_tokens": 100,
    "cache_creation_input_tokens": 1000,
    "cache_read_input_tokens": 500
  },
  "modelUsage": {
    "claude-sonnet-4-5-20250929": {
      "inputTokens": 200,
      "outputTokens": 100,
      "cacheReadInputTokens": 500,
      "cacheCreationInputTokens": 1000,
      "costUSD": 0.05,
      "contextWindow": 200000
    }
  },
  "permission_denials": []
}
```

**Result subtypes:**
- `success` - Turn completed normally
- `error_max_turns` - Hit max turns limit
- `error_during_execution` - Error during execution
- `error_max_budget_usd` - Hit budget limit

---

## Complete Example Flow

```
# 1. Start CLI
$ claude --output-format stream-json --input-format stream-json \
         --permission-prompt-tool stdio --permission-mode default

# 2. Initialize (STDIN)
{"request_id":"init-1","type":"control_request","request":{"subtype":"initialize"}}

# 3. Receive control_response (STDOUT)
{"type":"control_response","response":{"subtype":"success","request_id":"init-1",...}}

# 4. Receive system init (STDOUT)
{"type":"system","subtype":"init","session_id":"sess-123","tools":[...],...}

# 5. Send user message (STDIN)
{"type":"user","message":{"role":"user","content":"List files in /tmp"},...}

# 6. Receive assistant with tool_use (STDOUT)
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash",...}]},...}

# 7. Receive permission request (STDOUT)
{"type":"control_request","request_id":"perm-1","request":{"subtype":"can_use_tool",...}}

# 8. Send permission response (STDIN)
{"type":"control_response","response":{"subtype":"success","request_id":"perm-1","response":{"behavior":"allow",...}}}

# 9. Receive tool result (STDOUT)
{"type":"user","message":{"content":[{"type":"tool_result",...}]},...}

# 10. Receive final response (STDOUT)
{"type":"assistant","message":{"content":[{"type":"text","text":"Here are the files..."}]},...}

# 11. Receive result (STDOUT)
{"type":"result","subtype":"success","result":"Here are the files...",...}
```

---

## Dart SDK Implementation Notes

### Key Design Decisions

| Aspect | Direct CLI |
|--------|------------|
| Message format | Direct JSON messages (no wrapper envelope) |
| Permission bridge | `control_request`/`control_response` |
| Session creation | CLI args + `control_request` (initialize) |
| Process per session | One CLI process per session |

### Implementation Checklist

1. **Spawn claude-cli** with correct arguments
2. **Send `control_request` (initialize)** and wait for `control_response`
3. **Parse messages directly** - remove `sdk.message` wrapper handling
4. **Handle `control_request` (can_use_tool)** for permissions
5. **Send `control_response`** with user's decision
6. **Handle `AskUserQuestion`** by populating `answers` in `updatedInput`

### Session ID Handling

- The CLI generates its own `session_id` (in `system` init message)
- User messages include `session_id` for client-side tracking
- For multi-session support, spawn separate CLI processes

---

## References

- Protocol captures: `examples/typescript-claude.jsonl`
- Current Dart SDK types: `claude_dart_sdk/lib/src/types/sdk_messages.dart`
- TypeScript SDK docs: `docs/sdk/typescript.md`
