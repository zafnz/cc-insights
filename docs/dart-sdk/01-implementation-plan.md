# Implementation Plan (Historical)

> **Note:** This document describes the original Node.js backend implementation plan.
> The architecture has since evolved to use direct CLI communication as the default.
> See `BackendFactory` with `BackendType.directCli` for the current recommended approach.
> The Node.js backend has been removed entirely.

This document outlines the phased implementation plan for the Dart SDK architecture.

## Phase 1: Protocol Specification

**Goal:** Define the complete JSON protocol between Dart SDK and backend.

**Deliverables:**
- [ ] Document all Dart → Backend messages
- [ ] Document all Backend → Dart messages
- [ ] Document callback request/response flow
- [ ] Document error handling

**Output:** `02-protocol.md` (this phase produces the spec we implement against)

---

## Phase 2: Backend Rewrite (Historical - Node.js backend removed)

**Goal:** Originally implemented a thin Node.js backend (~200 lines). This has been replaced by direct CLI communication.

**Tasks:**

### 2.1 Project Setup
- [x] Clean out existing backend files (removed)
- [ ] Keep `package.json`, update dependencies
- [ ] Simple `tsconfig.json` for ESM output

### 2.2 Core Implementation
- [ ] `index.ts` - stdin/stdout JSON line loop
- [ ] `session-manager.ts` - Session map and lifecycle
- [ ] `callback-bridge.ts` - Pending callback Promise management
- [ ] `protocol.ts` - TypeScript types for protocol messages

### 2.3 Session Lifecycle
- [ ] `session.create` - Create session with full SDK options
- [ ] `session.send` - Send follow-up message (resume session)
- [ ] `session.interrupt` - Call `query.interrupt()`
- [ ] `session.kill` - Abort and cleanup

### 2.4 SDK Message Forwarding
- [ ] Forward all SDK messages as `sdk.message`
- [ ] Include raw message payload unchanged
- [ ] Handle all message types (assistant, user, result, system, stream_event)

### 2.5 Callback Bridge
- [ ] Implement `canUseTool` callback → `callback.request`
- [ ] Implement hook callbacks → `callback.request`
- [ ] Handle `callback.response` → resolve Promise
- [ ] Timeout handling for unresponded callbacks

### 2.6 Query Method Proxy
- [ ] `query.call` for supportedModels, supportedCommands, etc.
- [ ] `query.call` for setModel, setPermissionMode, etc.
- [ ] Return results via `query.result`

### 2.7 Testing
- [ ] Simple Node.js test client (read/write JSON lines)
- [ ] Test session create/message flow
- [ ] Test callback round-trip
- [ ] Test interruption

**Estimated lines:** ~200

---

## Phase 3: Dart SDK Types

**Goal:** Define all Dart types matching the TypeScript SDK.

**Tasks:**

### 3.1 Project Setup
- [ ] Create `claude_dart_sdk/` directory
- [ ] `pubspec.yaml` with minimal dependencies
- [ ] Directory structure under `lib/src/`

### 3.2 SDK Message Types
- [ ] `SDKMessage` sealed class hierarchy
- [ ] `SDKAssistantMessage` - assistant responses
- [ ] `SDKUserMessage` - user messages (including tool results)
- [ ] `SDKResultMessage` - turn completion with usage
- [ ] `SDKSystemMessage` - init message with session info
- [ ] `SDKStreamEvent` - partial message streaming
- [ ] `SDKCompactBoundary` - context compaction marker

### 3.3 Content Block Types
- [ ] `ContentBlock` sealed class
- [ ] `TextBlock` - text content
- [ ] `ThinkingBlock` - thinking content
- [ ] `ToolUseBlock` - tool invocation
- [ ] `ToolResultBlock` - tool result

### 3.4 Session Options
- [ ] `SessionOptions` - all SDK options
- [ ] `PermissionMode` enum
- [ ] `SystemPromptConfig` - string or preset
- [ ] `McpServerConfig` - MCP server settings
- [ ] `SandboxSettings` - sandbox configuration
- [ ] `AgentDefinition` - programmatic agents
- [ ] `HookConfig` - hook definitions

### 3.5 Callback Types
- [ ] `PermissionRequest` - canUseTool callback
- [ ] `PermissionResult` - allow/deny response
- [ ] `HookRequest` - hook callback
- [ ] `HookResult` - hook response

### 3.6 Result Types
- [ ] `Usage` - token counts
- [ ] `ModelUsage` - per-model breakdown
- [ ] `ModelInfo` - available model info
- [ ] `AccountInfo` - user account info
- [ ] `McpServerStatus` - MCP server health

### 3.7 Tool Types
- [ ] Tool input types (matching SDK)
- [ ] Tool output types (matching SDK)

**Estimated lines:** ~400

---

## Phase 4: Dart SDK Core

**Goal:** Implement the core SDK classes.

**Tasks:**

### 4.1 Protocol Layer
- [ ] `JsonLineCodec` - encode/decode JSON lines
- [ ] `BackendProtocol` - send/receive with message routing
- [ ] Message ID generation and correlation

### 4.2 AgentBackend
- [ ] Backend interface
- [ ] Process lifecycle management
- [ ] Message routing to sessions
- [ ] `createSession()` - create new session
- [ ] `dispose()` - cleanup

### 4.3 AgentSession
- [ ] Session state management
- [ ] `messages` stream - all SDK messages
- [ ] `send()` - send follow-up
- [ ] `interrupt()` - interrupt execution
- [ ] `kill()` - terminate session

### 4.4 Callback Handling
- [ ] `permissionRequests` stream
- [ ] `hookRequests` stream
- [ ] `PermissionRequest.allow()` / `.deny()`
- [ ] `HookRequest.respond()`
- [ ] Auto-timeout with configurable behavior

### 4.5 Query Methods
- [ ] `supportedModels()`
- [ ] `supportedCommands()`
- [ ] `mcpServerStatus()`
- [ ] `accountInfo()`
- [ ] `setModel()`
- [ ] `setPermissionMode()`
- [ ] `setMaxThinkingTokens()`
- [ ] `rewindFiles()`

### 4.6 Error Handling
- [ ] Backend crash detection
- [ ] Message parse errors
- [ ] Callback timeouts
- [ ] Session errors

**Estimated lines:** ~400

---

## Phase 5: Flutter Integration

**Goal:** Refactor Flutter app to use Dart SDK.

**Tasks:**

### 5.1 Dependency Setup
- [ ] Add `claude_dart_sdk` as path dependency
- [ ] Remove old WebSocket dependencies

### 5.2 App Startup
- [ ] Spawn backend in `main.dart`
- [ ] Pass backend to providers
- [ ] Handle backend path (bundled vs dev)

### 5.3 Provider Refactor
- [ ] New `AppState` holding `AgentBackend`
- [ ] Session creation via SDK
- [ ] Wire SDK streams to state
- [ ] Simplify session state (SDK owns truth)

### 5.4 Permission Handling
- [ ] Listen to `permissionRequests` stream
- [ ] Show permission dialog
- [ ] Call `request.allow()` / `.deny()`

### 5.5 Hook Handling
- [ ] Listen to `hookRequests` stream
- [ ] Process hooks (or auto-respond)
- [ ] Call `request.respond()`

### 5.6 Message Display
- [ ] Update output panel for SDK message types
- [ ] Handle partial streaming (`SDKStreamEvent`)
- [ ] Display system init info

### 5.7 Session Controls
- [ ] Model selector using `supportedModels()`
- [ ] Permission mode selector
- [ ] Account info display

### 5.8 Cleanup
- [ ] Delete old WebSocket service
- [ ] Delete old message types
- [ ] Delete old provider logic
- [ ] Update imports

**Estimated changes:** Net reduction in code

---

## Phase 6: Polish

**Goal:** Production readiness.

**Tasks:**

### 6.1 Error Handling
- [ ] Backend crash recovery
- [ ] Graceful degradation
- [ ] User-friendly error messages

### 6.2 Bundling
- [ ] Bundle backend executable
- [ ] Determine backend location at runtime
- [ ] Handle first-run setup

### 6.3 Testing
- [ ] Dart SDK unit tests
- [ ] Integration tests
- [ ] Manual testing checklist

### 6.4 Documentation
- [ ] Update CLAUDE.md
- [ ] API documentation
- [ ] README updates

---

## Execution Order

```
Week 1:
├── Phase 1: Protocol spec (1 day)
├── Phase 2: Backend (2-3 days)
└── Phase 3: Dart types (1-2 days)

Week 2:
├── Phase 4: Dart SDK core (2-3 days)
└── Phase 5: Flutter integration (2-3 days)

Week 3:
└── Phase 6: Polish (as needed)
```

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| SDK message format changes | Types generated from SDK where possible |
| Backend process crashes | Automatic restart, error reporting |
| Callback timeouts | Configurable timeout, default allow/deny |
| Breaking existing functionality | Keep old code until new code verified |

## Success Criteria

1. All existing functionality works with new architecture
2. Backend is under 250 lines of code
3. Partial message streaming works
4. All Query methods accessible from Flutter
5. No information lost from SDK messages
6. Clean separation: backend has no business logic
