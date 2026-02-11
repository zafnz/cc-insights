# Unified Internal MCP Tools — Implementation Plan

## Context

CC-Insights needs a way for agent backends to call functions provided by the app itself (e.g., `create_ticket`). Currently this is hardcoded as a special-case interception in `EventHandler._handleToolInvocation()` — it doesn't scale, can't send results back to the agent, and isn't extensible.

**Goal:** A unified `InternalToolRegistry` that lets CC-Insights register tool handlers, with each backend adapter exposing them via its native mechanism (Claude CLI via `mcp_message` control requests, Codex via tool registration).

---

## Chunk 1: Core Types — `InternalToolDefinition` + `InternalToolResult`

### Context
These are the fundamental data types the entire feature is built on. They live in `agent_sdk_core` so they're available to all backends and the frontend.

### Task
Create `agent_sdk_core/lib/src/types/internal_tools.dart` with:
- `InternalToolDefinition` — name, description, inputSchema (JSON Schema), async handler function
- `InternalToolResult` — content string, isError flag, with `.text()` and `.error()` factory constructors

Add export to `agent_sdk_core/lib/agent_sdk_core.dart`.

### Key Files
- **NEW:** `agent_sdk_core/lib/src/types/internal_tools.dart`
- **MODIFY:** `agent_sdk_core/lib/agent_sdk_core.dart` (add export line)

### Agent Type
**Sonnet** — straightforward data class creation

### Tests
- `agent_sdk_core/test/types/internal_tools_test.dart`
  - `InternalToolDefinition` stores name, description, inputSchema, handler
  - `InternalToolResult.text()` creates non-error result with content
  - `InternalToolResult.error()` creates error result with isError=true
  - Handler function can be invoked and returns a Future

### Definition of Done
- [ ] `InternalToolDefinition` and `InternalToolResult` classes exist and compile
- [ ] Factory constructors `.text()` and `.error()` work correctly
- [ ] Export added to `agent_sdk_core.dart`
- [ ] All existing tests still pass

### Checklist
- [x] Implemented
- [x] Tests run (106/106 pass)
- [x] Code review passed (no major issues)
- [x] Done

---

## Chunk 2: `InternalToolRegistry` with `handleMcpMessage()`

### Context
The registry is the central piece — it holds tool definitions and implements JSON-RPC MCP protocol handling for `initialize`, `notifications/initialized`, `tools/list`, `tools/call`, and `ping`. This makes it backend-agnostic: any backend just routes JSON-RPC messages to it.

**MCP Protocol Reference** (from `docs/claude-sdk-mcp-service.md`):
- `initialize` → return server info + capabilities `{"tools": {"listChanged": false}}`
- `notifications/initialized` → no response (notification, not request)
- `tools/list` → return array of tool definitions
- `tools/call` → execute handler, return `{content: [{type: "text", text: "..."}], isError: bool}`
- `ping` → return empty result
- Unknown methods → JSON-RPC error `-32601`

### Task
Create `agent_sdk_core/lib/src/internal_tool_registry.dart`:
- `static const String serverName = 'cci'`
- `register(InternalToolDefinition)`, `unregister(String name)`, `operator [](String name)`
- `List<InternalToolDefinition> get tools`, `bool get isEmpty`, `bool get isNotEmpty`
- `Future<Map<String, dynamic>> handleMcpMessage(Map<String, dynamic> message)` — the core JSON-RPC router

Add export to `agent_sdk_core/lib/agent_sdk_core.dart`.

### Key Files
- **NEW:** `agent_sdk_core/lib/src/internal_tool_registry.dart`
- **MODIFY:** `agent_sdk_core/lib/agent_sdk_core.dart` (add export)
- **REF:** `docs/claude-sdk-mcp-service.md` (protocol spec)

### Agent Type
**Opus** — JSON-RPC protocol implementation requires precision

### Tests
- `agent_sdk_core/test/internal_tool_registry_test.dart`
  - Register/unregister tools
  - `tools` getter returns registered tools
  - `operator []` returns tool by name, null for unknown
  - `isEmpty`/`isNotEmpty` reflect registration state
  - `handleMcpMessage` with `initialize` → returns server info with capabilities
  - `handleMcpMessage` with `notifications/initialized` → returns null (notification)
  - `handleMcpMessage` with `tools/list` → returns tool definitions in MCP format
  - `handleMcpMessage` with `tools/call` for known tool → calls handler, returns content result
  - `handleMcpMessage` with `tools/call` for unknown tool → returns error result
  - `handleMcpMessage` with `tools/call` for handler that throws → returns error result
  - `handleMcpMessage` with `ping` → returns empty result
  - `handleMcpMessage` with unknown method → returns JSON-RPC error -32601
  - Preserves JSON-RPC `id` in all responses
  - `handleMcpMessage` with `tools/call` for async handler → waits for completion

### Definition of Done
- [ ] Registry can register, unregister, and look up tools
- [ ] `handleMcpMessage` correctly handles `initialize`, `notifications/initialized`, `tools/list`, `tools/call`, `ping`
- [ ] JSON-RPC `id` field is preserved in responses
- [ ] Error cases return proper JSON-RPC error format
- [ ] All tests pass

### Checklist
- [x] Implemented
- [x] Tests run (127/127 pass)
- [x] Code review passed (no major issues)
- [x] Done

---

## Chunk 3: `AgentBackend.createSession()` Interface Update

### Context
The `AgentBackend` abstract interface in `agent_sdk_core/lib/src/backend_interface.dart` defines `createSession()` with `prompt`, `cwd`, `options`, and `content` parameters. We need to add an optional `InternalToolRegistry?` parameter so backends can receive the registry.

This is a breaking interface change that affects `ClaudeCliBackend` and `CodexBackend` implementations.

### Task
- Add `InternalToolRegistry? registry` parameter to `AgentBackend.createSession()`
- Update `ClaudeCliBackend.createSession()` in `claude_dart_sdk/lib/src/cli_backend.dart` to accept and store the parameter (pass-through only, actual usage comes in Chunk 4)
- Update `CodexBackend.createSession()` in `codex_dart_sdk/lib/src/codex_backend.dart` to accept the parameter (stub only, actual usage comes in Chunk 5)
- Update `BackendService.createSessionForBackend()` and `createTransport()` in `frontend/lib/services/backend_service.dart` to accept and forward the registry

### Key Files
- **MODIFY:** `agent_sdk_core/lib/src/backend_interface.dart` — add parameter
- **MODIFY:** `claude_dart_sdk/lib/src/cli_backend.dart` — accept parameter, forward to CliSession
- **MODIFY:** `codex_dart_sdk/lib/src/codex_backend.dart` — accept parameter (stub)
- **MODIFY:** `frontend/lib/services/backend_service.dart` — accept and forward parameter

### Agent Type
**Sonnet** — mechanical signature updates across files

### Tests
- Existing tests must still compile and pass (parameter is optional)
- No new test file needed — existing `cli_backend_test.dart`, `backend_service_test.dart` etc. verify compilation

### Definition of Done
- [ ] `AgentBackend.createSession()` has `InternalToolRegistry? registry` parameter
- [ ] All backend implementations accept the parameter without errors
- [ ] `BackendService.createTransport()` and `createSessionForBackend()` forward registry
- [ ] All existing tests still pass (no behavioral change yet)

### Checklist
- [x] Implemented
- [x] Tests run (all 4 packages pass)
- [x] Code review passed (no major issues)
- [x] Done

---

## Chunk 4: Claude CLI Integration — `mcp_message` Handling in `CliSession`

### Context
This is the core protocol integration. `CliSession` (in `claude_dart_sdk/lib/src/cli_session.dart`) needs to:

1. Accept `InternalToolRegistry?` in `create()` and store it
2. Add `sdkMcpServers: ['cci']` to the initialize `control_request` (line 822-835) when a registry with tools is provided
3. Handle `mcp_message` subtype in `_handleMessage()` (alongside existing `can_use_tool` at line 112)
4. Implement `_handleMcpMessage()` that routes to `registry.handleMcpMessage()` and sends back `control_response`

**Current `_handleMessage` switch at line 106:**
```dart
case 'control_request':
  if (subtype == 'can_use_tool') { ... }
```
**After:**
```dart
case 'control_request':
  if (subtype == 'can_use_tool') { ... }
  else if (subtype == 'mcp_message') { _handleMcpMessage(requestId, request!); }
```

**Control response format** (from `docs/claude-sdk-mcp-service.md`):
```json
{
  "type": "control_response",
  "request_id": "<matches request>",
  "response": { "jsonrpc": "2.0", "id": "<matches message id>", "result": {...} }
}
```

### Key Files
- **MODIFY:** `claude_dart_sdk/lib/src/cli_session.dart`
  - `create()` method (line 770) — add `InternalToolRegistry? registry` parameter
  - Constructor `CliSession._` (line 25) — add `_registry` field
  - `_handleMessage()` (line 92) — add `mcp_message` branch
  - New `_handleMcpMessage()` method
  - Initialize request (line 822) — add `sdkMcpServers` when registry is non-empty
- **MODIFY:** `claude_dart_sdk/lib/src/cli_backend.dart` — forward registry from `createSession()` to `CliSession.create()`

### Agent Type
**Opus** — protocol integration with precise message formatting

### Tests
- `claude_dart_sdk/test/cli_session_mcp_test.dart` (NEW)
  - Uses existing `MockCliProcessHelper` and `CliSessionForTesting` patterns from `cli_session_test.dart`
  - Test: Initialize request includes `sdkMcpServers: ['cci']` when registry has tools
  - Test: Initialize request does NOT include `sdkMcpServers` when registry is null/empty
  - Test: `mcp_message` with `tools/list` → sends correct control_response with tool definitions
  - Test: `mcp_message` with `tools/call` → invokes handler, sends result as control_response
  - Test: `mcp_message` with `tools/call` for error handler → sends error result
  - Test: `mcp_message` for unknown server → sends JSON-RPC error response
  - Test: Multiple concurrent `mcp_message` requests → each gets independent response matched by request_id
  - Test: `mcp_message` does NOT emit as InsightsEvent (only the resulting tool_use/tool_result flow through events)

### Definition of Done
- [ ] `CliSession.create()` accepts `InternalToolRegistry?`
- [ ] Initialize control_request includes `sdkMcpServers: ['cci']` when registry is non-empty
- [ ] `_handleMessage()` routes `mcp_message` to `_handleMcpMessage()`
- [ ] `_handleMcpMessage()` calls `registry.handleMcpMessage()` and sends `control_response`
- [ ] Response `request_id` matches the incoming request
- [ ] All tests pass (existing + new)

### Checklist
- [x] Implemented
- [x] Tests run (284/284 pass, 10 skipped)
- [x] Code review passed (1 major fixed: added .catchError() for fire-and-forget async)
- [x] Done

---

## Chunk 5: Codex Integration (Stub)

### Context
The Codex backend (`codex_dart_sdk/lib/src/codex_session.dart`) needs to accept `InternalToolRegistry?` and pass it through. The exact mechanism for advertising tools to Codex needs investigation — the spec notes this as an open question. For now, we store the registry and add a TODO for the advertisement mechanism. Tool call interception (if Codex calls a registered tool) can be added later.

### Task
- `CodexSession` accepts `InternalToolRegistry?` in constructor/create
- Store the registry reference
- Add TODO comments for tool advertisement and call interception
- `CodexBackend.createSession()` forwards registry to session

### Key Files
- **MODIFY:** `codex_dart_sdk/lib/src/codex_session.dart` — accept and store registry
- **MODIFY:** `codex_dart_sdk/lib/src/codex_backend.dart` — forward registry

### Agent Type
**Sonnet** — simple pass-through wiring

### Tests
- No new tests needed (stub only)
- Existing Codex tests must still pass

### Definition of Done
- [ ] `CodexSession` accepts and stores `InternalToolRegistry?`
- [ ] `CodexBackend.createSession()` forwards registry
- [ ] TODO comments clearly mark where advertisement/interception logic goes
- [ ] All existing tests pass

### Checklist
- [x] Implemented
- [x] Tests run (codex_dart_sdk 73/73 pass)
- [x] Code review passed (no major issues)
- [x] Done

---

## Chunk 6: Frontend — `InternalToolsService` + Provider Wiring

### Context
The frontend needs a service that creates and manages the `InternalToolRegistry`, registers application-level tools, and makes the registry available for session creation.

Currently `EventHandler` (line 89) holds a `TicketBoardState? ticketBoard` reference for the hardcoded `create_tickets` interception. The new `InternalToolsService` will own tool registration instead.

### Task
Create `frontend/lib/services/internal_tools_service.dart`:
```dart
class InternalToolsService extends ChangeNotifier {
  final InternalToolRegistry _registry = InternalToolRegistry();
  InternalToolRegistry get registry => _registry;

  void registerTicketTools(TicketBoardState board) {
    _registry.register(InternalToolDefinition(
      name: 'create_ticket',
      description: 'Create a ticket on the project board',
      inputSchema: { /* ticket JSON schema matching TicketProposal */ },
      handler: (input) async {
        // Parse ticket proposals from input
        // Stage in board for user review (uses Completer to wait)
        // Return result after user completes review
      },
    ));
  }
}
```

Wire into `frontend/lib/main.dart`:
- Create `InternalToolsService` in `_initializeServices()`
- Provide via `ChangeNotifierProvider`

Wire into `frontend/lib/models/chat.dart`:
- `startSession()` reads `InternalToolsService` registry and passes to `backend.createTransport()`
- Add `mcp__cci__*` to `allowedTools` in `SessionOptions` so internal tools are auto-permitted

### Key Files
- **NEW:** `frontend/lib/services/internal_tools_service.dart`
- **MODIFY:** `frontend/lib/main.dart` — create service, add provider
- **MODIFY:** `frontend/lib/models/chat.dart` — pass registry in `startSession()`, add allowedTools

### Agent Type
**Opus** — async handler with Completer pattern, provider wiring

### Tests
- `frontend/test/services/internal_tools_service_test.dart` (NEW)
  - Service creates with empty registry
  - `registerTicketTools()` adds `create_ticket` to registry
  - Registry is accessible via `.registry` getter
  - Handler correctly parses single ticket proposal
  - Handler correctly parses multiple ticket proposals
  - Handler returns error for invalid input (missing fields)
  - Handler waits for board review completion via Completer
  - Handler returns appropriate result text after approval
  - Handler returns appropriate result text after rejection

### Definition of Done
- [ ] `InternalToolsService` exists with `registerTicketTools()` method
- [ ] Service is provided in `main.dart` via Provider
- [ ] `ChatState.startSession()` passes registry to `createTransport()`
- [ ] `allowedTools` includes `mcp__cci__*` pattern
- [ ] Service tests pass
- [ ] All existing tests pass

### Checklist
- [x] Implemented
- [x] Tests run (2683/2683 pass, 2 skipped)
- [x] Code review passed (no major issues)
- [x] Done

---

## Chunk 7: Remove Hardcoded `create_tickets` from EventHandler

### Context
With the MCP integration complete, `create_tickets` now flows natively through the `mcp_message` protocol:
1. CLI calls MCP tool → `mcp_message` control_request
2. `CliSession` routes to registry → handler stages tickets, waits for review via Completer
3. Returns result → `control_response` → CLI feeds back to model

The `ToolInvocationEvent` and `ToolCompletionEvent` still flow through to the frontend via the normal event stream — EventHandler processes them as standard tool entries (no special interception needed).

### Task
Remove from `frontend/lib/services/event_handler.dart`:
- Line 84-89: `ticketBoard` field
- Line 91-101: `_pendingTicketToolUseId`, `_pendingTicketChat`
- Line 104: `maxProposalCount`
- Line 146: `ticketBoard` constructor parameter
- Line 196-201: `create_tickets` interception in `_handleToolInvocation()`
- Line 269-402: `_handleCreateTickets()` method
- Line 404-448: `completeTicketReview()` method
- Line 451: `hasPendingTicketReview` property
- Line 1264-1265: Clear of `_pendingTicketToolUseId` and `_pendingTicketChat` in `clear()`

Also remove from `main.dart` where `ticketBoard` is set on `EventHandler`:
- Search for `_eventHandler?.ticketBoard = ` or similar assignment

Update `TicketBoardState` if it has `onBulkReviewComplete` callback — this will now be wired differently through `InternalToolsService`.

### Key Files
- **MODIFY:** `frontend/lib/services/event_handler.dart` — remove all create_tickets code
- **MODIFY:** `frontend/lib/main.dart` — remove ticketBoard assignment to EventHandler
- **MODIFY:** `frontend/lib/state/ticket_board_state.dart` — update callback mechanism if needed

### Agent Type
**Sonnet** — deletion and cleanup

### Tests
- `frontend/test/services/event_handler_ticket_test.dart` — needs to be deleted or refactored:
  - Tests for the hardcoded `create_tickets` interception should be removed
  - Any tests for `completeTicketReview()` should be removed
  - If the file tests ONLY ticket interception, delete it entirely
- `frontend/test/services/event_handler_test.dart` — update if any tests reference `ticketBoard`
- Run full test suite to catch any compilation errors from removed fields/methods

### Definition of Done
- [ ] No `create_tickets` interception code remains in `EventHandler`
- [ ] `ticketBoard`, `_pendingTicketToolUseId`, `_pendingTicketChat`, `hasPendingTicketReview` removed
- [ ] `completeTicketReview()` and `_handleCreateTickets()` removed
- [ ] All references cleaned up (main.dart, tests)
- [ ] Tool invocations for `create_tickets` / `mcp__cci__create_ticket` flow through normal EventHandler path
- [ ] All tests pass

### Checklist
- [x] Implemented
- [x] Tests run (2650/2650 pass, 2 skipped)
- [x] Code review passed (no issues — clean removal verified)
- [x] Done

---

## Chunk 8: Full Integration Test + Final Test Suite Run

### Context
All pieces are now in place. Run the full test suite and verify end-to-end flow.

### Task
1. Run `./frontend/run-flutter-test.sh` — all tests must pass
2. Fix any failures
3. Verify the end-to-end flow conceptually:
   - `InternalToolsService` registers `create_ticket` with registry
   - `ChatState.startSession()` passes registry to transport → backend → CliSession
   - CliSession sends `sdkMcpServers: ['cci']` in initialize
   - When CLI sends `mcp_message` with `tools/list`, CliSession responds with tool defs
   - When CLI sends `mcp_message` with `tools/call`, CliSession invokes handler via registry
   - Handler waits for user review, returns result
   - CliSession sends `control_response` back to CLI
   - MCP tool calls auto-permitted via `allowedTools`

### Agent Type
**Sonnet** — test execution and fix-up

### Tests
- Full test suite: `./frontend/run-flutter-test.sh`
- Also run `agent_sdk_core` and `claude_dart_sdk` tests individually if needed

### Definition of Done
- [x] All tests in all packages pass (2977 total: 127 + 127 + 73 + 2650)
- [x] No regressions
- [x] Code is clean (no TODO artifacts, no dead code from migration)

### Checklist
- [x] Implemented
- [x] Tests run (2977/2977 pass, 2 skipped)
- [x] Code review passed
- [x] Done

---

## Execution Process (Per Chunk)

Each chunk follows this process:

1. **Implementation Agent** (flutter-engineer or appropriate type) implements the code and writes tests
2. **Test Runner Agent** (Bash) runs `./frontend/run-flutter-test.sh` (or package-specific test command) and reports results
3. **Code Review Agent** (separate agent) reviews the implementation for:
   - Adherence to spec
   - Code quality / SOLID principles
   - Test coverage
   - Edge cases
   - Protocol correctness (for MCP-related chunks)
4. If issues found → back to Implementation Agent to fix → re-test → re-review
5. Only mark "Done" when tests pass AND code review passes

## File Summary

| File | Action | Chunk |
|------|--------|-------|
| `agent_sdk_core/lib/src/types/internal_tools.dart` | NEW | 1 |
| `agent_sdk_core/lib/agent_sdk_core.dart` | MODIFY | 1, 2 |
| `agent_sdk_core/lib/src/internal_tool_registry.dart` | NEW | 2 |
| `agent_sdk_core/lib/src/backend_interface.dart` | MODIFY | 3 |
| `claude_dart_sdk/lib/src/cli_backend.dart` | MODIFY | 3, 4 |
| `codex_dart_sdk/lib/src/codex_backend.dart` | MODIFY | 3, 5 |
| `codex_dart_sdk/lib/src/codex_session.dart` | MODIFY | 5 |
| `claude_dart_sdk/lib/src/cli_session.dart` | MODIFY | 4 |
| `frontend/lib/services/internal_tools_service.dart` | NEW | 6 |
| `frontend/lib/main.dart` | MODIFY | 6, 7 |
| `frontend/lib/models/chat.dart` | MODIFY | 6 |
| `frontend/lib/services/backend_service.dart` | MODIFY | 3 |
| `frontend/lib/services/event_handler.dart` | MODIFY | 7 |
| `frontend/lib/state/ticket_board_state.dart` | MODIFY | 7 |
| `agent_sdk_core/test/types/internal_tools_test.dart` | NEW | 1 |
| `agent_sdk_core/test/internal_tool_registry_test.dart` | NEW | 2 |
| `claude_dart_sdk/test/cli_session_mcp_test.dart` | NEW | 4 |
| `frontend/test/services/internal_tools_service_test.dart` | NEW | 6 |
| `frontend/test/services/event_handler_ticket_test.dart` | DELETE/REFACTOR | 7 |
