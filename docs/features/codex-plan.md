# Multi-Backend Architecture: Claude + Codex

## Overview

Add Codex as a second backend alongside Claude, with a shared abstraction
layer so the UI is nearly identical for both. Three-package SDK structure:
`agent_sdk_core` (shared interfaces/types), `claude_dart_sdk` (Claude CLI),
`codex_dart_sdk` (Codex app-server).

---

## Phase 1: Create `agent_sdk_core` package (extract shared types)

No behavioral changes. All existing tests must pass.

### New package: `agent_sdk_core/`

```
agent_sdk_core/
  lib/
    agent_sdk_core.dart              # Main export barrel
    src/
      backend_interface.dart         # AgentBackend, AgentSession (moved)
      types/
        callbacks.dart               # PermissionRequest, PermissionResponse, HookRequest (moved)
        permission_suggestion.dart   # PermissionSuggestion, PermissionRule, PermissionDestination (moved)
        content_blocks.dart          # ContentBlock, TextBlock, ImageBlock, etc. (moved)
        session_options.dart         # SessionOptions, PermissionMode, etc. (moved)
        errors.dart                  # BackendError, ClaudeError hierarchy (moved)
        usage.dart                   # Usage, ModelUsage, ModelInfo, SlashCommand, etc. (moved)
  pubspec.yaml                       # deps: meta, uuid
```

### Changes to `claude_dart_sdk`

- Add dependency on `agent_sdk_core`
- Replace moved files with re-exports: `export 'package:agent_sdk_core/...';`
- `claude_sdk.dart` barrel file continues to export everything (no change
  for downstream consumers)
- Claude-specific types stay: `SDKMessage` hierarchy, `CliProcess`,
  `CliSession`, `ClaudeCliBackend`, `ClaudeBackend`, `ClaudeSession`,
  control messages, protocol

### Changes to `AgentSession` interface

Add one getter to `backend_interface.dart`:

```dart
/// Session ID suitable for resume. Defaults to [sessionId].
/// Claude overrides to return sdkSessionId; Codex returns threadId.
String? get resolvedSessionId => sessionId;
```

### Files to move (from claude_dart_sdk/lib/src/ to agent_sdk_core/lib/src/):

- `backend_interface.dart`
- `types/callbacks.dart`
- `types/permission_suggestion.dart`
- `types/content_blocks.dart`
- `types/session_options.dart`
- `types/errors.dart`
- `types/usage.dart`

### Verification

- All existing `claude_dart_sdk` tests pass unchanged
- All existing `frontend` tests pass unchanged (imports via `claude_sdk`
  still resolve because of re-exports)

---

## Phase 2: Refactor frontend for backend-agnostic message handling

No behavioral changes. All existing tests must pass.

### Extract MessageHandler interface

**New file**: `frontend/lib/services/message_handler.dart`

```dart
abstract class MessageHandler {
  void handleMessage(ChatState chat, Map<String, dynamic> rawMessage);
  void clear();
}
```

### Rename existing handler

- Rename `SdkMessageHandler` -> `ClaudeMessageHandler`
- Implements `MessageHandler`
- File stays at same path or rename to `claude_message_handler.dart`
- Update all imports

### Fix ClaudeSession type check in ChatState

In `chat.dart` line 774, replace:

```dart
final newSessionId = session is sdk.ClaudeSession
    ? session.sdkSessionId
    : session.sessionId;
```

With:

```dart
final newSessionId = session.resolvedSessionId ?? session.sessionId;
```

### Extend BackendType enum

In `backend_factory.dart`, add `codex` to the enum (factory throws
`UnimplementedError` for now):

```dart
enum BackendType { nodejs, directCli, codex }
```

### Verification

- All existing tests pass unchanged

---

## Phase 3: Implement `codex_dart_sdk`

### New package: `codex_dart_sdk/`

```
codex_dart_sdk/
  lib/
    codex_sdk.dart                   # Main export
    src/
      codex_backend.dart             # CodexBackend implements AgentBackend
      codex_session.dart             # CodexSession implements AgentSession
      codex_process.dart             # Manages codex app-server subprocess
      json_rpc.dart                  # JSON-RPC framing (request/response/notification)
      types/
        codex_events.dart            # Notification event types
        codex_items.dart             # ThreadItem types
        codex_approval.dart          # Approval request/response types
  test/
    codex_process_test.dart
    codex_session_test.dart
    codex_backend_test.dart
  pubspec.yaml                       # deps: agent_sdk_core, meta, uuid
```

### CodexProcess (`codex_process.dart`)

- Spawns `codex app-server` as subprocess
- Manages stdin/stdout JSON-RPC communication (line-delimited JSON)
- Handles initialize/initialized handshake on startup
- Routes incoming messages: responses (by request ID), notifications
  (broadcast), server requests (by method)
- Tracks pending request IDs for correlation
- Provides: `Stream<Map<String, dynamic>> notifications`,
  `Future<Map<String, dynamic>> sendRequest(method, params)`

### CodexBackend (`codex_backend.dart`)

- Implements `AgentBackend`
- Owns single `CodexProcess` instance
- `createSession()` sends `thread/start` (or `thread/resume`), returns
  `CodexSession`
- `dispose()` terminates the process
- Maps process errors to `BackendError` stream

### CodexSession (`codex_session.dart`)

- Implements `AgentSession`
- Wraps a thread ID from the `CodexProcess`
- `sessionId` = thread ID
- `resolvedSessionId` = thread ID
- `send(message)` sends `turn/start` with `[{type: "text", text: message}]`
- `sendWithContent(content)` maps `ContentBlock` list to Codex input format
- `interrupt()` sends `turn/interrupt`
- `kill()` = interrupt + mark inactive
- `messages` stream: filters process notifications for this thread,
  maps to `SDKMessage` objects
- `permissionRequests` stream: intercepts server requests
  (`requestApproval`), wraps as `PermissionRequest`, sends response
  back via process when `allow()`/`deny()` is called

### Message mapping (Codex notification -> SDKMessage)

| Codex Event | SDKMessage | rawJson type field |
|-------------|------------|-------------------|
| `item/completed` (agentMessage) | `SDKAssistantMessage` with TextBlock | `'assistant'` |
| `item/completed` (commandExecution) | `SDKAssistantMessage` with ToolUseBlock | `'assistant'` |
| `item/completed` (fileChange) | `SDKAssistantMessage` with ToolUseBlock | `'assistant'` |
| `item/completed` (reasoning) | `SDKAssistantMessage` with ThinkingBlock | `'assistant'` |
| `item/completed` (mcpToolCall) | `SDKAssistantMessage` with ToolUseBlock | `'assistant'` |
| `item/agentMessage/delta` | `SDKStreamEvent` with textDelta | `'stream_event'` |
| `turn/completed` | `SDKResultMessage` | `'result'` |
| Thread started | `SDKSystemMessage` (subtype: init) | `'system'` |

The key insight: Codex items are mapped into the same `rawJson` shape that
the Claude handler expects (`type: 'assistant'` with `content` blocks).
This means `ClaudeMessageHandler` can handle both, OR we create a
`CodexMessageHandler` that emits `OutputEntry` directly (cleaner).

### Permission mapping

| Codex | PermissionRequest field |
|-------|------------------------|
| `item/commandExecution/requestApproval` | `toolName: 'Bash'`, `toolInput: {command, cwd}` |
| `item/fileChange/requestApproval` | `toolName: 'Write'`/`'Edit'`, `toolInput: {changes}` |
| `item/tool/requestUserInput` | `toolName: 'AskUserQuestion'`, `toolInput: {questions}` |

Approval responses:
- `allow()` -> JSON-RPC response `{decision: "accept"}`
- `allow()` with session flag -> `{decision: "acceptForSession"}`
- `deny()` -> `{decision: "decline"}`
- `deny(interrupt: true)` -> `{decision: "cancel"}`

### Verification

- Unit tests for CodexProcess (mock subprocess)
- Unit tests for CodexSession (mock CodexProcess)
- Integration test: connect to real `codex app-server` and run a simple turn

---

## Phase 4: Implement `CodexMessageHandler`

### New file: `frontend/lib/services/codex_message_handler.dart`

Implements `MessageHandler`. Maps Codex rawJson (which the SDK has already
partially normalized) to `OutputEntry` objects.

Handles these rawJson types:
- `'assistant'` with tool_use content -> `ToolUseOutputEntry`
- `'assistant'` with text content -> `TextOutputEntry`
- `'assistant'` with thinking content -> `TextOutputEntry(contentType: 'thinking')`
- `'result'` -> updates usage, sets working=false
- `'system'` -> system init, config info

Two approaches for this handler:

**Option A**: Have `CodexSession` normalize messages into the exact same
rawJson format as Claude, so `ClaudeMessageHandler` works for both.
One handler, zero UI changes.

**Option B**: Create a separate `CodexMessageHandler` that handles Codex's
native notification format directly, mapping to `OutputEntry`.

Recommend **Option A** for MVP (less code), with the option to split
later if Codex-specific behavior diverges significantly.

### Verification

- Widget tests with mock Codex messages
- Verify OutputEntry types match expectations

---

## Phase 5: Wire it together

### BackendFactory (`backend_factory.dart`)

```dart
case BackendType.codex:
  return CodexBackend.create(executablePath: executablePath);
```

### BackendService

Support configurable backend type. Simplest approach: pass `BackendType`
to `start()`:

```dart
Future<void> start({BackendType type = BackendType.directCli}) async {
  _backend = await BackendFactory.create(type: type);
}
```

### ChatState

- Select `MessageHandler` based on backend type
- Most code unchanged (uses `AgentSession` interface)
- `SessionOptions` fields ignored by Codex backend are simply unused

### Model selection

- Add `codex` models alongside Claude models, selected based on backend
- For MVP: hardcode a few Codex models (o3, o4-mini, gpt-4.1, codex-mini)
- Later: query `model/list` from app-server at runtime

### Backend selection UI

For MVP: environment variable `AGENT_BACKEND=codex` or `=claude`
Later: per-project setting in project config

### Verification

- End-to-end: select Codex backend, start chat, send message, see response
- Permission dialog appears for Codex approval requests
- Multi-turn conversation works (thread resume)
- All existing Claude tests still pass

---

## Files Summary

### New files
- `agent_sdk_core/` (entire package, ~8 files)
- `codex_dart_sdk/` (entire package, ~10 files)
- `frontend/lib/services/message_handler.dart` (interface)
- `frontend/lib/services/codex_message_handler.dart` (if Option B)

### Modified files
- `claude_dart_sdk/pubspec.yaml` (add agent_sdk_core dep)
- `claude_dart_sdk/lib/claude_sdk.dart` (re-export agent_sdk_core)
- `claude_dart_sdk/lib/src/` (remove moved files, add re-exports)
- `frontend/pubspec.yaml` (add codex_dart_sdk dep)
- `frontend/lib/services/backend_service.dart` (configurable backend type)
- `frontend/lib/services/sdk_message_handler.dart` (rename/refactor)
- `frontend/lib/models/chat.dart` (resolvedSessionId, handler selection)
- `claude_dart_sdk/lib/src/backend_factory.dart` (add codex type)

### Unchanged files (the goal)
- All panel files
- All widget files (including PermissionDialog)
- ConversationData, Agent, OutputEntry models
- SelectionState
