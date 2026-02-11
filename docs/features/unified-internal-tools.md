# Unified Internal MCP Support

## Context

CC-Insights needs a way for agent backends (Claude CLI, Codex, future ACP) to call functions provided by the CC-Insights app itself. The example use case is `create_ticket` — the agent calls it, CC-Insights handles it locally (e.g. staging tickets for user review), and returns a result.

Currently `create_tickets` is hardcoded in `EventHandler` as a special-case interception of `ToolInvocationEvent`. This doesn't scale, doesn't actually send results back to the agent, and isn't extensible to new tools or backends.

**Goal:** A unified `InternalToolRegistry` that lets CC-Insights register tool handlers, with each backend adapter exposing them via its native mechanism.

---

## Key Insight: Claude SDK MCP Servers Are In-Process

See [docs/claude-sdk-mcp-service.md](../claude-sdk-mcp-service.md) for the full protocol documentation.

The TypeScript/Python SDK's `createSdkMcpServer()` does **NOT** spawn a subprocess or HTTP server. It uses bidirectional JSON-RPC over the existing stdio pipe between the SDK and CLI via the `mcp_message` control request/response protocol.

Our Dart `CliSession` already handles `control_request` with `subtype: 'can_use_tool'` for permissions. We just need to add handling for `subtype: 'mcp_message'`.

---

## Architecture

### How Each Backend Exposes Internal Tools

| Backend | Mechanism |
|---------|-----------|
| **Claude CLI** | Send `sdkMcpServers` names in initialize. Handle `mcp_message` control requests by routing to in-process tool handlers. Respond via `control_response`. |
| **Codex** | Register tools via thread config or dynamic tool mechanism. Route tool server requests to in-process handlers. Respond via `sendResponse()`. |
| **ACP (future)** | Declare MCP server with `"transport": "acp"`. Handle `mcp/message` methods. Route to in-process handlers. |

### Data Flow (Claude CLI)

```
1. ChatState.startSession() → passes InternalToolRegistry
2. CliSession.create() sends sdkMcpServers: ["cci"] in initialize control_request
3. CLI discovers tools (sends mcp_message with tools/list → we respond with tool defs)
4. Agent calls mcp__cci__create_ticket
5. CLI sends control_request { subtype: "mcp_message", server_name: "cci", message: {method: "tools/call", ...} }
6. CliSession routes to InternalToolRegistry, calls handler (async)
7. Handler returns InternalToolResult
8. CliSession sends control_response with JSON-RPC result
9. CLI feeds result back to model
```

### Data Flow (Codex)

```
1. ChatState.startSession() → passes InternalToolRegistry
2. CodexSession registers tools with Codex via thread/start or similar
3. Agent calls registered tool → Codex sends server request to CodexSession
4. CodexSession matches tool name against registry, invokes handler
5. Handler returns InternalToolResult → CodexSession sends response via sendResponse()
```

---

## Implementation Plan

### Phase 1: Core Types in `agent_sdk_core`

**New file: `agent_sdk_core/lib/src/types/internal_tools.dart`**

```dart
/// A tool provided by CC-Insights to agent backends.
class InternalToolDefinition {
  final String name;           // e.g. "create_ticket"
  final String description;    // For model context
  final Map<String, dynamic> inputSchema;  // JSON Schema
  final Future<InternalToolResult> Function(Map<String, dynamic> input) handler;
}

class InternalToolResult {
  final String content;
  final bool isError;
  factory InternalToolResult.text(String text);
  factory InternalToolResult.error(String message);
}
```

**New file: `agent_sdk_core/lib/src/internal_tool_registry.dart`**

```dart
class InternalToolRegistry {
  static const String serverName = 'cci';  // tools → mcp__cci__<name>

  void register(InternalToolDefinition tool);
  void unregister(String name);
  InternalToolDefinition? operator [](String name);
  List<InternalToolDefinition> get tools;
  bool get isEmpty / isNotEmpty;

  /// Handle a JSON-RPC MCP message and return the response.
  /// Routes tools/list → tool definitions, tools/call → handler invocation.
  Future<Map<String, dynamic>> handleMcpMessage(Map<String, dynamic> message);
}
```

The `handleMcpMessage()` method is the core: it implements the MCP JSON-RPC protocol for `tools/list` and `tools/call`, making the registry usable by any backend that routes MCP messages to it.

**Modify: `agent_sdk_core/lib/agent_sdk_core.dart`** — Add exports.

### Phase 2: Claude CLI Integration — `mcp_message` Protocol

**Modify: `claude_dart_sdk/lib/src/cli_session.dart`**

1. **`CliSession.create()` accepts `InternalToolRegistry?`**:
   - Stores reference to registry
   - Adds `'sdkMcpServers': ['cci']` to the initialize `control_request` (alongside existing `mcp_servers`)

2. **`_handleMessage()` handles `mcp_message` subtype**:
   ```dart
   case 'control_request':
     final request = json['request'] as Map<String, dynamic>?;
     final subtype = request?['subtype'] as String?;
     final requestId = json['request_id'] as String? ?? '';

     if (subtype == 'can_use_tool') {
       // ... existing permission handling ...
     } else if (subtype == 'mcp_message') {
       _handleMcpMessage(requestId, request!);
     }
   ```

3. **New `_handleMcpMessage()` method**:
   ```dart
   Future<void> _handleMcpMessage(String requestId, Map<String, dynamic> request) async {
     final serverName = request['server_name'] as String?;
     final message = request['message'] as Map<String, dynamic>?;
     if (serverName != InternalToolRegistry.serverName || message == null || _registry == null) {
       _sendMcpError(requestId, message, -32601, 'Unknown server: $serverName');
       return;
     }
     final response = await _registry!.handleMcpMessage(message);
     _process.send({
       'type': 'control_response',
       'request_id': requestId,
       'response': response,
     });
   }
   ```

**Modify: `claude_dart_sdk/lib/src/cli_backend.dart`**
- `createSession()` accepts and forwards `InternalToolRegistry?`

### Phase 3: Codex Integration

**Modify: `codex_dart_sdk/lib/src/codex_session.dart`**
- Accept `InternalToolRegistry?` in constructor/create
- In `_handleServerRequest()`: when a tool call arrives for a tool name in the registry, route to `registry.handleMcpMessage()` (or call the handler directly) instead of emitting as a permission request
- Send the handler result back via `_process?.sendResponse()`

**Modify: `codex_dart_sdk/lib/src/codex_backend.dart`**
- `createSession()` accepts and forwards `InternalToolRegistry?`

**Note:** Codex's exact tool registration mechanism (how we tell Codex about our tools) needs investigation during implementation. The tool call interception is straightforward; the advertisement is the open question.

### Phase 4: Transport & BackendService Wiring

**Modify: `agent_sdk_core/lib/src/backend_interface.dart`**
- Add `InternalToolRegistry?` parameter to `AgentBackend.createSession()`

**Modify: `agent_sdk_core/lib/src/transport/in_process_transport.dart`**
- No changes needed — tool calls flow through the CLI's `mcp_message` mechanism, not the transport event stream

**Modify: `frontend/lib/services/backend_service.dart`**
- `createTransport()` accepts `InternalToolRegistry?`
- Passes registry to `createSessionForBackend()` → backend's `createSession()`

**Modify: `frontend/lib/models/chat.dart`**
- `startSession()` passes `InternalToolRegistry` from `InternalToolsService` to `backend.createTransport()`

### Phase 5: Frontend — InternalToolsService

**New file: `frontend/lib/services/internal_tools_service.dart`**

```dart
class InternalToolsService extends ChangeNotifier {
  final InternalToolRegistry _registry = InternalToolRegistry();
  InternalToolRegistry get registry => _registry;

  /// Register the create_ticket tool.
  void registerTicketTools(TicketBoardState board) {
    _registry.register(InternalToolDefinition(
      name: 'create_ticket',
      description: 'Create a ticket on the project board',
      inputSchema: { /* ticket JSON schema */ },
      handler: (input) async {
        // Parse ticket proposals from input
        // Stage in board for user review (uses Completer to wait)
        // Return result after user completes review
      },
    ));
  }
}
```

**Modify: `frontend/lib/main.dart`**
- Create `InternalToolsService` and provide via `Provider`
- Register ticket tools after `TicketBoardState` is available

### Phase 6: Migrate `create_tickets` from EventHandler

**Modify: `frontend/lib/services/event_handler.dart`**
- Remove hardcoded `create_tickets` interception from `_handleToolInvocation()`
- Remove: `_handleCreateTickets()`, `completeTicketReview()`, `_pendingTicketToolUseId`, `_pendingTicketChat`, `hasPendingTicketReview`
- Remove: `ticketBoard` field

The `create_tickets` tool now flows through MCP natively:
- CLI calls MCP tool → `mcp_message` control_request → CliSession routes to registry → handler stages tickets, waits for user review via `Completer` → returns result → control_response → CLI feeds back to model
- The `ToolInvocationEvent` and `ToolCompletionEvent` still flow through to the frontend for UI display (the CLI emits them as part of its normal message flow)

---

## Files Summary

| File | Action | Description |
|------|--------|-------------|
| `agent_sdk_core/lib/src/types/internal_tools.dart` | **NEW** | InternalToolDefinition, InternalToolResult |
| `agent_sdk_core/lib/src/internal_tool_registry.dart` | **NEW** | InternalToolRegistry with handleMcpMessage() |
| `agent_sdk_core/lib/agent_sdk_core.dart` | **MODIFY** | Add exports |
| `agent_sdk_core/lib/src/backend_interface.dart` | **MODIFY** | Add registry param to createSession |
| `claude_dart_sdk/lib/src/cli_session.dart` | **MODIFY** | Send sdkMcpServers in init, handle mcp_message control_request |
| `claude_dart_sdk/lib/src/cli_backend.dart` | **MODIFY** | Forward registry to session |
| `codex_dart_sdk/lib/src/codex_session.dart` | **MODIFY** | Route tool calls to registry |
| `codex_dart_sdk/lib/src/codex_backend.dart` | **MODIFY** | Forward registry to session |
| `frontend/lib/services/internal_tools_service.dart` | **NEW** | Tool registration service |
| `frontend/lib/services/backend_service.dart` | **MODIFY** | Pass registry to createTransport |
| `frontend/lib/models/chat.dart` | **MODIFY** | Pass registry in startSession |
| `frontend/lib/services/event_handler.dart` | **MODIFY** | Remove hardcoded create_tickets |
| `frontend/lib/main.dart` | **MODIFY** | Provide InternalToolsService |

---

## Verification

1. **Unit tests:** InternalToolRegistry (register, unregister, handleMcpMessage for tools/list and tools/call)
2. **Unit tests:** CliSession mcp_message handling (mock control_request, verify control_response)
3. **Integration test:** Start a Claude session with registered tools, verify `sdkMcpServers` sent in init, verify tools discoverable
4. **End-to-end:** Send message triggering `create_ticket`, verify ticket board shows proposals, approve, verify agent receives result
5. **Run all tests:** `./frontend/run-flutter-test.sh`

---

## Notes

- **Tool naming:** Tools appear as `mcp__cci__<name>` (e.g. `mcp__cci__create_ticket`)
- **Auto-permitted:** Internal tools should be auto-permitted (no permission dialog). We can add them to `allowedTools` in SessionOptions.
- **ToolInvocationEvent still emitted:** For Claude, MCP tool calls appear as ToolInvocationEvent in the event stream. EventHandler processes them normally (ToolUseOutputEntry, pairs with ToolCompletionEvent). No special UI interception needed.
- **Async handlers:** Handlers return `Future<InternalToolResult>`, so they can wait for user interaction (e.g., ticket review via Completer). The `mcp_message` response is held until the handler completes.
- **Concurrency:** Multiple `mcp_message` requests can be in flight simultaneously (agent may call tools in parallel). Each is handled independently via its own async handler invocation.
