# Claude CLI JSON Stream Protocol

This document describes the JSON stream protocol used for communication between the Dart SDK and the Claude CLI.

## Overview

The SDK communicates with the Claude CLI using bidirectional JSON Lines (JSONL) format over stdin/stdout. Each message is a single JSON object terminated by a newline.

### CLI Arguments

The SDK launches the CLI with these arguments:

```bash
claude \
  --output-format stream-json \
  --input-format stream-json \
  --permission-prompt-tool stdio \
  [additional options...]
```

### Message Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      Initialization                         │
└─────────────────────────────────────────────────────────────┘
     │
     │  1. SDK sends control_request (initialize)
     │  2. CLI responds with control_response
     │  3. SDK sends initial user message
     │  4. CLI sends system (init) message
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Conversation Loop                         │
└─────────────────────────────────────────────────────────────┘
     │
     │  ┌──── assistant messages (Claude's responses)
     │  │
     │  ├──── user messages (tool results, subagent output)
     │  │
     │  ├──── callback.request (permission requests)
     │  │         │
     │  │         └── SDK responds with callback.response
     │  │
     │  └──── result message (turn complete)
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Follow-up Messages                        │
└─────────────────────────────────────────────────────────────┘
     │
     │  SDK sends user message
     │  ... conversation continues ...
     │
     ▼
```

---

## Initialization

### Step 1: Control Request (Initialize)

The SDK sends an initialization request:

```json
{
  "type": "control_request",
  "request_id": "req-1234567890-abc123",
  "request": {
    "subtype": "initialize",
    "system_prompt": {
      "type": "preset",
      "preset": "claude_code"
    },
    "mcp_servers": {},
    "agents": {},
    "hooks": {}
  }
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `string` | Always `"control_request"` |
| `request_id` | `string` | Unique request ID for correlation |
| `request.subtype` | `string` | `"initialize"` for initialization |
| `request.system_prompt` | `object` | System prompt configuration |
| `request.mcp_servers` | `object` | MCP server configurations |
| `request.agents` | `object` | Subagent configurations |
| `request.hooks` | `object` | Hook configurations |

### Step 2: Control Response

The CLI responds with available commands and models:

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req-1234567890-abc123",
    "response": {
      "commands": [
        {
          "name": "compact",
          "description": "Clear conversation history...",
          "argumentHint": "<optional instructions>"
        }
      ],
      "output_style": "default",
      "available_output_styles": ["default", "Explanatory", "Learning"],
      "models": [
        {
          "value": "default",
          "displayName": "Default (recommended)",
          "description": "Opus 4.5 · Most capable"
        },
        {
          "value": "sonnet",
          "displayName": "Sonnet",
          "description": "Sonnet 4.5 · Best for everyday tasks"
        }
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

### Step 3: Initial User Message

The SDK sends the initial prompt:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "Hello, Claude!"
  },
  "parent_tool_use_id": null
}
```

### Step 4: System Init Message

The CLI sends session initialization info:

```json
{
  "type": "system",
  "subtype": "init",
  "cwd": "/path/to/project",
  "session_id": "ee5e97bf-0000-0000-0000-000000000001",
  "tools": ["Task", "Bash", "Read", "Edit", "Write", "Glob", "Grep"],
  "mcp_servers": [
    {"name": "flutter-test", "status": "connected"}
  ],
  "model": "claude-sonnet-4-5-20250929",
  "permissionMode": "default",
  "slash_commands": ["compact", "cost", "context"],
  "apiKeySource": "none",
  "claude_code_version": "2.1.29",
  "output_style": "default",
  "agents": ["Bash", "general-purpose", "Explore", "Plan"],
  "skills": ["keybindings-help"],
  "plugins": [],
  "uuid": "ee5e97bf-0000-0000-0000-000000000002"
}
```

---

## Message Types

### Assistant Message

Claude's response:

```json
{
  "type": "assistant",
  "message": {
    "model": "claude-sonnet-4-5-20250929",
    "id": "msg_01ABC123",
    "type": "message",
    "role": "assistant",
    "content": [
      {"type": "text", "text": "I'll help you with that."},
      {
        "type": "tool_use",
        "id": "toolu_01XYZ789",
        "name": "Bash",
        "input": {
          "command": "ls -la",
          "description": "List files in directory"
        }
      }
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 100,
      "output_tokens": 50,
      "cache_creation_input_tokens": 500,
      "cache_read_input_tokens": 1000
    }
  },
  "parent_tool_use_id": null,
  "session_id": "ee5e97bf-0000-0000-0000-000000000001",
  "uuid": "ee5e97bf-0000-0000-0000-000000000003"
}
```

### User Message (Tool Result)

After a tool executes:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_01XYZ789",
        "content": "file1.txt\nfile2.txt\nfile3.txt",
        "is_error": false
      }
    ]
  },
  "parent_tool_use_id": null,
  "session_id": "ee5e97bf-0000-0000-0000-000000000001",
  "uuid": "ee5e97bf-0000-0000-0000-000000000004",
  "tool_use_result": {
    "stdout": "file1.txt\nfile2.txt\nfile3.txt",
    "stderr": "",
    "interrupted": false,
    "isImage": false
  }
}
```

### Result Message

Turn completion:

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 5234,
  "duration_api_ms": 3890,
  "num_turns": 2,
  "result": "I found 3 files in the directory.",
  "session_id": "ee5e97bf-0000-0000-0000-000000000001",
  "total_cost_usd": 0.0342,
  "usage": {
    "input_tokens": 150,
    "output_tokens": 75,
    "cache_creation_input_tokens": 500,
    "cache_read_input_tokens": 1500,
    "server_tool_use": {
      "web_search_requests": 0,
      "web_fetch_requests": 0
    },
    "service_tier": "standard"
  },
  "modelUsage": {
    "claude-sonnet-4-5-20250929": {
      "inputTokens": 150,
      "outputTokens": 75,
      "cacheReadInputTokens": 1500,
      "cacheCreationInputTokens": 500,
      "webSearchRequests": 0,
      "costUSD": 0.0342,
      "contextWindow": 200000,
      "maxOutputTokens": 64000
    }
  },
  "permission_denials": [],
  "uuid": "ee5e97bf-0000-0000-0000-000000000010"
}
```

---

## Permission Requests

When Claude wants to use a tool that requires approval:

### Callback Request

```json
{
  "type": "callback.request",
  "id": "cb-001",
  "session_id": "ee5e97bf-0000-0000-0000-000000000002",
  "payload": {
    "callback_type": "can_use_tool",
    "tool_name": "Bash",
    "tool_input": {
      "command": "rm -rf /tmp/test",
      "description": "Delete test directory"
    },
    "tool_use_id": "toolu_01ABC123",
    "blocked_path": "/tmp/test",
    "suggestions": [
      {
        "type": "addRules",
        "rules": [
          {"toolName": "Bash", "ruleContent": "rm -rf /tmp/**"}
        ],
        "behavior": "allow",
        "destination": "session"
      }
    ]
  }
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | Unique request ID for response correlation |
| `payload.callback_type` | `string` | Always `"can_use_tool"` for permissions |
| `payload.tool_name` | `string` | Name of the tool |
| `payload.tool_input` | `object` | Tool parameters |
| `payload.tool_use_id` | `string` | Unique tool use identifier |
| `payload.blocked_path` | `string?` | Path that triggered permission (if applicable) |
| `payload.suggestions` | `array` | Suggested permission rules |

### Callback Response (Allow)

```json
{
  "type": "callback.response",
  "id": "cb-001",
  "session_id": "ee5e97bf-0000-0000-0000-000000000002",
  "payload": {
    "behavior": "allow",
    "updated_input": {
      "command": "rm -rf /tmp/test",
      "description": "Delete test directory"
    },
    "updated_permissions": []
  }
}
```

### Callback Response (Deny)

```json
{
  "type": "callback.response",
  "id": "cb-001",
  "session_id": "ee5e97bf-0000-0000-0000-000000000002",
  "payload": {
    "behavior": "deny",
    "message": "User denied file deletion"
  }
}
```

---

## AskUserQuestion Tool

When Claude needs clarification:

### Assistant Message with AskUserQuestion

```json
{
  "type": "assistant",
  "message": {
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_ask_001",
        "name": "AskUserQuestion",
        "input": {
          "questions": [
            {
              "question": "How should I format the output?",
              "header": "Format",
              "options": [
                {"label": "Summary", "description": "Brief overview"},
                {"label": "Detailed", "description": "Full explanation"}
              ],
              "multiSelect": false
            }
          ]
        }
      }
    ]
  }
}
```

### Permission Response with Answers

```json
{
  "type": "callback.response",
  "id": "cb-ask-001",
  "session_id": "...",
  "payload": {
    "behavior": "allow",
    "updated_input": {
      "questions": [...],
      "answers": {
        "How should I format the output?": "Summary"
      }
    }
  }
}
```

---

## Images

### Sending Images

Send images as base64-encoded content blocks:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {"type": "text", "text": "What is in this image?"},
      {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": "image/png",
          "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB..."
        }
      }
    ]
  }
}
```

**Supported formats:**

- `image/png`
- `image/jpeg`
- `image/gif`
- `image/webp`

### Receiving Image Results

Tool results can include images:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_screenshot_001",
        "content": [
          {
            "type": "image",
            "source": {
              "type": "base64",
              "media_type": "image/png",
              "data": "..."
            }
          }
        ]
      }
    ]
  },
  "tool_use_result": {
    "isImage": true
  }
}
```

---

## Session Control

### Interrupt

Send interrupt to gracefully stop:

```json
{
  "type": "control_request",
  "request_id": "req-interrupt-001",
  "request": {
    "subtype": "interrupt"
  }
}
```

### Set Model

Change model mid-session:

```json
{
  "type": "control_request",
  "request_id": "req-model-001",
  "request": {
    "subtype": "set_model",
    "model": "opus"
  }
}
```

**Response:**

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req-model-001"
  }
}
```

### Set Permission Mode

Change permission mode:

```json
{
  "type": "control_request",
  "request_id": "req-perm-001",
  "request": {
    "subtype": "set_permission_mode",
    "mode": "acceptEdits"
  }
}
```

---

## Token Usage & Cost Tracking

### Usage Fields

Each assistant message includes usage data:

```json
{
  "usage": {
    "input_tokens": 100,
    "output_tokens": 50,
    "cache_creation_input_tokens": 500,
    "cache_read_input_tokens": 1000,
    "cache_creation": {
      "ephemeral_5m_input_tokens": 0,
      "ephemeral_1h_input_tokens": 500
    },
    "service_tier": "standard"
  }
}
```

| Field | Description |
|-------|-------------|
| `input_tokens` | New input tokens processed |
| `output_tokens` | Tokens generated in response |
| `cache_creation_input_tokens` | Tokens used to create cache |
| `cache_read_input_tokens` | Tokens read from cache |
| `service_tier` | Service tier used |

### Result Message Usage

The result message has cumulative usage:

```json
{
  "type": "result",
  "total_cost_usd": 0.0342,
  "usage": {
    "input_tokens": 250,
    "output_tokens": 150,
    "cache_creation_input_tokens": 500,
    "cache_read_input_tokens": 2500,
    "server_tool_use": {
      "web_search_requests": 1,
      "web_fetch_requests": 0
    }
  },
  "modelUsage": {
    "claude-sonnet-4-5-20250929": {
      "inputTokens": 200,
      "outputTokens": 120,
      "cacheReadInputTokens": 2000,
      "cacheCreationInputTokens": 400,
      "webSearchRequests": 1,
      "costUSD": 0.0300,
      "contextWindow": 200000,
      "maxOutputTokens": 64000
    },
    "claude-haiku-4-5-20251001": {
      "inputTokens": 50,
      "outputTokens": 30,
      "cacheReadInputTokens": 500,
      "cacheCreationInputTokens": 100,
      "webSearchRequests": 0,
      "costUSD": 0.0042,
      "contextWindow": 200000,
      "maxOutputTokens": 64000
    }
  }
}
```

### Cost Tracking Best Practices

1. **Use `total_cost_usd`** from the result message for billing
2. **Use `modelUsage`** for per-model breakdown
3. **Messages with same ID have same usage** - don't double-count
4. **Track by message ID** to avoid duplicate charges

---

## Subagent Messages

When Claude spawns subagents via the Task tool:

### Subagent User Message

Initial message sent to subagent:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [{"type": "text", "text": "What is 2+2?"}]
  },
  "parent_tool_use_id": "toolu_task_001",
  "session_id": "...",
  "uuid": "..."
}
```

### Subagent Tool Result

When subagent completes:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_task_001",
        "content": [
          {"type": "text", "text": "4"},
          {"type": "text", "text": "agentId: ae01306 (for resuming...)"}
        ]
      }
    ]
  },
  "parent_tool_use_id": null,
  "tool_use_result": {
    "status": "completed",
    "prompt": "What is 2+2?",
    "agentId": "ae01306",
    "content": [{"type": "text", "text": "4"}],
    "totalDurationMs": 2427,
    "totalTokens": 18038,
    "totalToolUseCount": 0,
    "usage": {...}
  }
}
```

---

## Stream Events

For streaming responses:

### Content Block Delta

```json
{
  "type": "stream_event",
  "event_type": "content_block_delta",
  "event": {
    "type": "content_block_delta",
    "index": 0,
    "delta": {
      "type": "text_delta",
      "text": "Hello, "
    }
  }
}
```

### Thinking Delta

For extended thinking:

```json
{
  "type": "stream_event",
  "event_type": "content_block_delta",
  "event": {
    "type": "content_block_delta",
    "index": 0,
    "delta": {
      "type": "thinking_delta",
      "thinking": "Let me consider this..."
    }
  }
}
```

---

## Error Handling

### Error Message

```json
{
  "type": "error",
  "error": {
    "type": "overloaded_error",
    "message": "Service is temporarily overloaded"
  }
}
```

### Result Error

```json
{
  "type": "result",
  "subtype": "error",
  "is_error": true,
  "result": "An error occurred",
  "errors": ["Connection timeout"]
}
```

---

## System Messages

### Compact Boundary

When context is compacted:

```json
{
  "type": "system",
  "subtype": "compact_boundary",
  "summary": "Previous conversation summary..."
}
```

### Status Update

```json
{
  "type": "system",
  "subtype": "status",
  "status": "processing",
  "message": "Running tests..."
}
```

---

## Complete Message Flow Example

```
→ SDK: control_request (initialize)
← CLI: control_response (success)
→ SDK: user message "List files in /tmp"
← CLI: system (init)
← CLI: assistant "I'll list the files..."
← CLI: assistant (tool_use: Bash)
← CLI: callback.request (can_use_tool: Bash)
→ SDK: callback.response (allow)
← CLI: user (tool_result)
← CLI: assistant "Here are the files..."
← CLI: result (success, usage, cost)
```
