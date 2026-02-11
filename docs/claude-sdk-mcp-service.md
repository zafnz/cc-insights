# Claude SDK In-Process MCP Server Protocol

How the Claude Agent SDK implements in-process MCP servers (custom tools) — the mechanism behind `createSdkMcpServer()` in TypeScript/Python.

---

## Overview

The Claude Agent SDK provides `createSdkMcpServer()` (TS) / `create_sdk_mcp_server()` (Python) to define custom tools that run **entirely in-process** — no subprocess, no HTTP server, no stdio pipe to a separate MCP server. The tool handler functions execute in the same process as your application.

This works because the SDK communicates with the Claude CLI subprocess via **bidirectional JSON-RPC over stdin/stdout**. The CLI already uses this channel for control messages (initialize, permissions). SDK MCP servers add a new message type — `mcp_message` — that allows the CLI to send MCP JSON-RPC calls back to the parent process for in-process tool execution.

---

## Architecture

```
Your Application (Node.js / Python / Dart)
├─ SDK
│  ├─ InternalToolRegistry (tool definitions + handlers)
│  └─ CliProcess (stdin/stdout pipe to Claude CLI)
│     ├─ Writes: control_request (initialize, with sdkMcpServers names)
│     ├─ Writes: user messages
│     ├─ Reads:  assistant responses, tool invocations
│     ├─ Reads:  control_request (can_use_tool) → permission flow
│     └─ Reads:  control_request (mcp_message) → tool call flow ← THIS
│
└─ Claude CLI subprocess
   ├─ Knows about SDK MCP servers by NAME only (not instances)
   ├─ For SDK tool calls: sends mcp_message back to parent
   ├─ For stdio/HTTP/SSE tool calls: communicates directly
   └─ Processes tool results and continues conversation
```

**Key insight:** The CLI doesn't need the tool handler code — it only needs the **names** of SDK MCP servers. When it wants to call a tool from an SDK server, it sends the call back to the parent process via the existing stdio pipe.

---

## Protocol Messages

### 1. Initialize: Declare SDK MCP Servers

During session creation, the SDK tells the CLI which servers are SDK-hosted by adding `sdkMcpServers` to the initialize control request:

```json
{
  "type": "control_request",
  "request_id": "init-001",
  "request": {
    "subtype": "initialize",
    "system_prompt": { "type": "preset", "preset": "claude_code" },
    "mcp_servers": {},
    "sdkMcpServers": ["cci"],
    "agents": {},
    "hooks": {}
  }
}
```

**Fields:**
- `mcp_servers` — External MCP servers (stdio, HTTP, SSE) that the CLI spawns/connects to directly
- `sdkMcpServers` — Array of server **names** for in-process SDK servers. The CLI will route tool calls for these back to the parent.

### 2. Tool Discovery: `tools/list`

After initialization, the CLI discovers what tools each SDK server provides by sending an `mcp_message` with the MCP `tools/list` method:

**CLI → SDK (control_request):**
```json
{
  "type": "control_request",
  "request_id": "req-001",
  "request": {
    "subtype": "mcp_message",
    "server_name": "cci",
    "message": {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/list",
      "params": {}
    }
  }
}
```

**SDK → CLI (control_response):**
```json
{
  "type": "control_response",
  "request_id": "req-001",
  "response": {
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
      "tools": [
        {
          "name": "create_ticket",
          "description": "Create a ticket on the project board",
          "inputSchema": {
            "type": "object",
            "properties": {
              "title": { "type": "string", "description": "Ticket title" },
              "description": { "type": "string", "description": "Ticket description" },
              "kind": { "type": "string", "enum": ["bug", "feature", "task"] }
            },
            "required": ["title", "description", "kind"]
          }
        }
      ]
    }
  }
}
```

The CLI uses this to build the tool list for the model. Tools from SDK server `cci` appear as `mcp__cci__create_ticket`.

### 3. Tool Invocation: `tools/call`

When the model decides to use an SDK MCP tool, the CLI sends a `tools/call` message:

**CLI → SDK (control_request):**
```json
{
  "type": "control_request",
  "request_id": "req-002",
  "request": {
    "subtype": "mcp_message",
    "server_name": "cci",
    "message": {
      "jsonrpc": "2.0",
      "id": 2,
      "method": "tools/call",
      "params": {
        "name": "create_ticket",
        "arguments": {
          "title": "Fix login bug",
          "description": "Users can't log in on mobile",
          "kind": "bug"
        }
      }
    }
  }
}
```

**SDK → CLI (control_response):**
```json
{
  "type": "control_response",
  "request_id": "req-002",
  "response": {
    "jsonrpc": "2.0",
    "id": 2,
    "result": {
      "content": [
        {
          "type": "text",
          "text": "Ticket 'Fix login bug' created successfully (ID: TKT-42)"
        }
      ]
    }
  }
}
```

The CLI feeds this result back to the model as a `tool_result`, and the conversation continues.

### 4. Error Response

If the tool handler fails:

```json
{
  "type": "control_response",
  "request_id": "req-002",
  "response": {
    "jsonrpc": "2.0",
    "id": 2,
    "result": {
      "content": [
        {
          "type": "text",
          "text": "Error: Invalid ticket kind 'enhancement'. Must be one of: bug, feature, task"
        }
      ],
      "isError": true
    }
  }
}
```

For JSON-RPC level errors (unknown method, invalid params):

```json
{
  "type": "control_response",
  "request_id": "req-002",
  "response": {
    "jsonrpc": "2.0",
    "id": 2,
    "error": {
      "code": -32601,
      "message": "Unknown method: tools/unknown"
    }
  }
}
```

---

## MCP Methods to Implement

The SDK MCP server only needs to handle a small subset of the MCP protocol:

| Method | Required | Description |
|--------|----------|-------------|
| `initialize` | Yes | MCP handshake. Return server info and capabilities. |
| `notifications/initialized` | Yes | Client acknowledgment. No response needed. |
| `tools/list` | Yes | Return array of tool definitions with names, descriptions, and input schemas. |
| `tools/call` | Yes | Execute a tool by name with arguments. Return content result. |
| `ping` | Optional | Health check. Return empty result. |

Other MCP methods (resources, prompts, sampling) are not needed for tool-only servers.

---

## Tool Naming Convention

MCP tools follow the pattern: `mcp__{server_name}__{tool_name}`

- Server name `cci` + tool name `create_ticket` → `mcp__cci__create_ticket`
- This naming is applied by the CLI when presenting tools to the model
- In `tools/list` and `tools/call`, use the **bare tool name** (e.g., `create_ticket`)
- The `mcp__` prefix is only visible to the model and in `ToolInvocationEvent.toolName`

---

## Async / Long-Running Tool Calls

The `mcp_message` protocol naturally supports async tool handlers:

1. CLI sends `control_request` with `tools/call`
2. SDK starts the async handler (e.g., stages tickets for user review)
3. The CLI **blocks waiting** for the `control_response` — this is fine because the CLI is designed for async tool execution
4. When the handler completes (e.g., user approves tickets), SDK sends `control_response`
5. CLI resumes with the result

**Timeout consideration:** If tools will take >60s, set `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` environment variable on the CLI process to prevent timeout.

---

## Concurrency

Multiple `mcp_message` requests can be in flight simultaneously (the model may call tools in parallel). Each request has a unique `request_id`. The SDK must:

1. Track pending requests by `request_id`
2. Handle each tool call independently (don't block others)
3. Send responses matched by `request_id`

---

## Permissions

SDK MCP tools need to be explicitly allowed. Options:

1. **`allowedTools`**: Add `"mcp__cci__*"` to auto-permit all tools from the server
2. **Permission mode**: `acceptEdits` or `bypassPermissions` grants broader access
3. **`can_use_tool` callback**: If not in allowedTools, the CLI may send a `can_use_tool` control request for user approval

For CC-Insights internal tools, we add them to `allowedTools` so they're auto-permitted.

---

## Comparison: SDK MCP Server Types

| Type | Config | Communication | Where handler runs |
|------|--------|--------------|-------------------|
| **stdio** | `{ command: "npx", args: [...] }` | CLI spawns subprocess, stdio pipe | Separate process |
| **HTTP** | `{ type: "http", url: "..." }` | CLI makes HTTP requests | Remote server |
| **SSE** | `{ type: "sse", url: "..." }` | CLI uses Server-Sent Events | Remote server |
| **SDK (in-process)** | `sdkMcpServers: ["name"]` | CLI sends `mcp_message` control requests | Same process as SDK |

Only SDK servers use the `mcp_message` control request protocol. The others are handled directly by the CLI.

---

## Implementation in CC-Insights Dart SDK

Our `CliSession` currently handles these control_request subtypes:
- `can_use_tool` → Permission request flow

We need to add:
- `mcp_message` → Route to `InternalToolRegistry.handleMcpMessage()`, respond via `control_response`

And in the initialize message, add:
- `sdkMcpServers: ['cci']` alongside the existing `mcp_servers` field

See [docs/features/unified-internal-tools.md](features/unified-internal-tools.md) for the full implementation plan.

---

## References

- TypeScript SDK type: `SDKControlMcpMessageRequest` in `sdk.d.ts`
- TypeScript SDK type: `McpSdkServerConfigWithInstance` — contains `type: 'sdk'`, `name`, `instance`
- Custom tools guide: `docs/anthropic-agent-cli-sdk/custom-tools.md`
- MCP integration guide: `docs/anthropic-agent-cli-sdk/mcp.md`
- MCP specification: https://modelcontextprotocol.io
