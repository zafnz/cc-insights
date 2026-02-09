# Phase 4: Transport Layer — Implementation Plan

## Goal

Add a transport abstraction (`EventTransport`) between the frontend and backend SDKs so that:
1. The frontend consumes events via a transport interface, not directly from in-process sessions
2. The same interface can later support WebSocket, Docker, or remote backends
3. InsightsEvents gain JSON serialization for wire transport
4. Backend commands (send message, permission response, interrupt, etc.) gain a unified command model

**This phase introduces zero behavioral changes.** The `InProcessTransport` wraps the current in-process sessions behind the new interface. The frontend works identically — just through an additional layer of indirection.

---

## Architecture

### Current (Direct)

```
ChatState → BackendService.createSession() → AgentSession (in-process)
         → session.events.listen(eventHandler.handleEvent)
         → session.send(text)
         → session.interrupt()
         → session.permissionRequests.listen(setPendingPermission)
```

### After Phase 4 (Abstracted)

```
ChatState → BackendService.createTransport() → EventTransport
         → transport.events.listen(eventHandler.handleEvent)
         → transport.send(SendMessageCommand(text))
         → transport.send(InterruptCommand())
         → transport.events (PermissionRequestEvent included in events stream)

EventTransport implementations:
  InProcessTransport → wraps AgentSession (same behavior)
  WebSocketTransport → future
  DockerTransport    → future
```

---

## Task Breakdown

### Task 4.1: BackendCommand Sealed Class Hierarchy

**File to create:** `agent_sdk_core/lib/src/types/backend_commands.dart`
**Test file to create:** `agent_sdk_core/test/types/backend_commands_test.dart`

Define the unified command model for frontend → backend communication.

#### Types to Define

```dart
sealed class BackendCommand {
  Map<String, dynamic> toJson();
  static BackendCommand fromJson(Map<String, dynamic> json);
}

class SendMessageCommand extends BackendCommand {
  final String sessionId;
  final String text;
  final List<ContentBlock>? content;  // For images
}

class PermissionResponseCommand extends BackendCommand {
  final String requestId;
  final bool allowed;
  final String? message;
  final Map<String, dynamic>? updatedInput;
  final List<dynamic>? updatedPermissions;
}

class InterruptCommand extends BackendCommand {
  final String sessionId;
}

class KillCommand extends BackendCommand {
  final String sessionId;
}

class SetModelCommand extends BackendCommand {
  final String sessionId;
  final String model;
}

class SetPermissionModeCommand extends BackendCommand {
  final String sessionId;
  final String mode;
}

class SetReasoningEffortCommand extends BackendCommand {
  final String sessionId;
  final String effort;
}

class CreateSessionCommand extends BackendCommand {
  final String cwd;
  final String prompt;
  final SessionOptions? options;
  final List<ContentBlock>? content;
}
```

#### Wire Format

Each command serializes with a `command` type discriminator:

```json
{"command": "send_message", "sessionId": "abc", "text": "Fix the bug"}
{"command": "permission_response", "requestId": "req-42", "allowed": true}
{"command": "interrupt", "sessionId": "abc"}
{"command": "set_model", "sessionId": "abc", "model": "claude-sonnet-4-5"}
```

#### Instructions for Agent

1. Create `agent_sdk_core/lib/src/types/backend_commands.dart` with the sealed class hierarchy above.
2. Every subclass must have:
   - Named constructor with required fields
   - `toJson()` method producing a map with `'command'` discriminator field
   - Fields matching the table above
3. Add a static `BackendCommand.fromJson(Map<String, dynamic> json)` factory that dispatches on `json['command']` string.
4. Add `export 'src/types/backend_commands.dart';` to `agent_sdk_core/lib/agent_sdk_core.dart`.
5. Write round-trip tests: for each command type, verify `BackendCommand.fromJson(cmd.toJson())` produces an equal command.
6. Run `./frontend/run-flutter-test.sh` — all existing tests must still pass.

---

### Task 4.2: InsightsEvent JSON Serialization

**File to modify:** `agent_sdk_core/lib/src/types/insights_events.dart`
**Test file to create:** `agent_sdk_core/test/types/insights_events_serialization_test.dart`

Add `toJson()` and `fromJson()` to every `InsightsEvent` subclass.

#### Wire Format

Each event serializes with an `event` type discriminator:

```json
{"event": "session_init", "id": "evt-1", "timestamp": "2025-01-01T00:00:00.000Z", "provider": "claude", "sessionId": "abc", "model": "claude-sonnet-4-5", ...}
{"event": "text", "id": "evt-2", "timestamp": "...", "provider": "claude", "sessionId": "abc", "text": "Hello", "kind": "text", ...}
{"event": "tool_invocation", "id": "evt-3", "timestamp": "...", "provider": "claude", "callId": "tu-1", "kind": "execute", "toolName": "Bash", "input": {"command": "ls"}, ...}
{"event": "tool_completion", "id": "evt-4", "timestamp": "...", "provider": "claude", "callId": "tu-1", "status": "completed", "output": {...}, ...}
{"event": "turn_complete", "id": "evt-5", "timestamp": "...", "provider": "claude", "costUsd": 0.012, ...}
```

#### Event Type Discriminator Table

| `event` value | Dart class |
|---|---|
| `session_init` | `SessionInitEvent` |
| `session_status` | `SessionStatusEvent` |
| `text` | `TextEvent` |
| `user_input` | `UserInputEvent` |
| `tool_invocation` | `ToolInvocationEvent` |
| `tool_completion` | `ToolCompletionEvent` |
| `subagent_spawn` | `SubagentSpawnEvent` |
| `subagent_complete` | `SubagentCompleteEvent` |
| `turn_complete` | `TurnCompleteEvent` |
| `context_compaction` | `ContextCompactionEvent` |
| `permission_request` | `PermissionRequestEvent` |
| `stream_delta` | `StreamDeltaEvent` |

#### Enum Serialization

Enums serialize as their `.name` string:
- `BackendProvider.claude` → `"claude"`
- `ToolKind.execute` → `"execute"`
- `TextKind.thinking` → `"thinking"`
- `SessionStatus.compacting` → `"compacting"`
- `ToolCallStatus.completed` → `"completed"`
- `CompactionTrigger.auto` → `"auto"`
- `StreamDeltaKind.text` → `"text"`

#### Instructions for Agent

1. Read the existing `insights_events.dart` file completely.
2. Add `toJson()` to the `InsightsEvent` base class and every subclass.
3. Add `static InsightsEvent fromJson(Map<String, dynamic> json)` factory on the base class that dispatches on `json['event']`.
4. Add `fromJson` factory constructors on each subclass for the factory to delegate to.
5. **Common base fields** serialized by every event:
   - `'event'` — type discriminator string
   - `'id'` — event ID
   - `'timestamp'` — ISO 8601 string via `timestamp.toIso8601String()`
   - `'provider'` — enum name string
   - `'raw'` — include if non-null
   - `'extensions'` — include if non-null
6. **Nullable fields**: Only include in JSON if non-null (use `if (field != null) 'key': field` pattern).
7. **`DateTime` handling**: Serialize with `toIso8601String()`, deserialize with `DateTime.parse()`.
8. **`TokenUsage` and `ModelTokenUsage`**: Add `toJson()`/`fromJson()` to these supporting types in `usage.dart` if not already present.
9. **`PermissionSuggestionData`**: Add `toJson()`/`fromJson()` if not already present.
10. **`PermissionDenial`**: Already has `fromJson()` — add `toJson()` if missing.
11. Write comprehensive round-trip tests: for each event type, construct an instance with all fields populated, serialize to JSON, deserialize back, and verify all fields match.
12. Also test with minimal fields (all optional fields null) to verify nullable handling.
13. The `PermissionRequestEvent` should NOT serialize the Completer (it's in-process only) — omit any non-serializable fields, add a note in the doc comment.
14. Run `./frontend/run-flutter-test.sh` — all existing tests must still pass.

#### Edge Cases

- `ToolCompletionEvent.output` is `dynamic` — serialize as-is (it's already JSON-compatible data from the backend).
- `UserInputEvent.images` — skip serialization for now (images are binary, transport will need special handling later).
- `PermissionRequestEvent` — serialize all data fields but NOT the Completer. Add a `hasCompleter` flag that's `false` when deserialized.
- `raw` field is `Map<String, dynamic>?` — serialize directly.

---

### Task 4.3: EventTransport Interface + InProcessTransport

**File to create:** `agent_sdk_core/lib/src/transport/event_transport.dart`
**File to create:** `agent_sdk_core/lib/src/transport/in_process_transport.dart`
**Test file to create:** `agent_sdk_core/test/transport/in_process_transport_test.dart`

#### EventTransport Interface

```dart
abstract class EventTransport {
  /// Incoming events from the backend.
  Stream<InsightsEvent> get events;

  /// Send a command to the backend.
  Future<void> send(BackendCommand command);

  /// Connection/session status.
  Stream<TransportStatus> get status;

  /// The session ID (available after session creation).
  String? get sessionId;

  /// Backend capabilities.
  BackendCapabilities? get capabilities;

  /// Clean up resources.
  Future<void> dispose();
}

enum TransportStatus {
  connecting,
  connected,
  disconnected,
  error,
}
```

#### InProcessTransport

Wraps an existing `AgentSession` + `AgentBackend` behind the `EventTransport` interface. This is the only transport implementation for now.

```dart
class InProcessTransport implements EventTransport {
  final AgentSession _session;
  final BackendCapabilities? _capabilities;
  final StreamController<TransportStatus> _statusController;
  final StreamController<InsightsEvent> _mergedEventsController;

  // Permission handling: maps requestId → PermissionRequest
  final Map<String, PermissionRequest> _pendingPermissions;
}
```

**Key behaviors:**

1. **`events` stream**: Merges the session's `events` stream with synthesized `PermissionRequestEvent` objects from the `permissionRequests` stream. This unifies both into a single event stream.

   Wait — actually, the `events` stream from CliSession already emits `PermissionRequestEvent`. The `permissionRequests` stream emits `PermissionRequest` objects (with Completers) for interactive response. The transport needs to handle BOTH:
   - Forward `events` stream as-is (includes `PermissionRequestEvent` for observation)
   - Track `permissionRequests` stream internally so `PermissionResponseCommand` can resolve the correct Completer

2. **`send(BackendCommand command)`**: Dispatches commands:
   - `SendMessageCommand` → `_session.send(text)` or `_session.sendWithContent(content)`
   - `PermissionResponseCommand` → resolve the stored `PermissionRequest` Completer
   - `InterruptCommand` → `_session.interrupt()`
   - `KillCommand` → `_session.kill()`
   - `SetModelCommand` → `_session.setModel(model)`
   - `SetPermissionModeCommand` → `_session.setPermissionMode(mode)`
   - `SetReasoningEffortCommand` → `_session.setReasoningEffort(effort)`

3. **`status` stream**: Emits `connected` immediately after creation, `disconnected` when session ends.

4. **Permission handling**: When a `PermissionRequest` arrives on the permission stream, store it in `_pendingPermissions[request.id]`. When `PermissionResponseCommand` arrives via `send()`, look up the stored request and call `allow()` or `deny()`.

#### Instructions for Agent

1. Create `agent_sdk_core/lib/src/transport/` directory.
2. Create `event_transport.dart` with the `EventTransport` abstract class and `TransportStatus` enum.
3. Create `in_process_transport.dart` with `InProcessTransport`.
4. The constructor takes `AgentSession session` and optional `BackendCapabilities? capabilities`.
5. **Events stream**: Forward `_session.events` directly to the transport's events stream.
6. **Permission tracking**: Subscribe to `_session.permissionRequests`, store each in `_pendingPermissions[request.id]`.
7. **`send()` implementation**: Switch on command type, dispatch to session methods.
8. **Permission response dispatch**: When `PermissionResponseCommand` is sent:
   - Look up `_pendingPermissions[cmd.requestId]`
   - If `cmd.allowed`: call `request.allow(updatedInput: cmd.updatedInput, updatedPermissions: cmd.updatedPermissions)`
   - If `!cmd.allowed`: call `request.deny(cmd.message ?? 'Denied', interrupt: cmd.interrupt ?? false)` — add `interrupt` field to `PermissionResponseCommand` if not present
   - Remove from `_pendingPermissions`
9. **`dispose()`**: Cancel all subscriptions, close controllers.
10. Add exports to `agent_sdk_core/lib/agent_sdk_core.dart`.
11. Write tests using a mock/fake `AgentSession` that:
    - Verifies `SendMessageCommand` calls `session.send()`
    - Verifies `InterruptCommand` calls `session.interrupt()`
    - Verifies `PermissionResponseCommand` resolves the correct PermissionRequest
    - Verifies events flow through from session to transport
    - Verifies status transitions (connected → disconnected on dispose)
12. Run `./frontend/run-flutter-test.sh` — all existing tests must still pass.

---

### Task 4.4: BackendService Creates Transports

**Files to modify:**
- `frontend/lib/services/backend_service.dart` — add `createTransport()` method
- `frontend/lib/models/chat.dart` — store transport, use it for commands

**Test files to update:**
- `frontend/test/models/chat_session_test.dart`
- Any test that calls `startSession`

This is the wiring task — the frontend starts using `EventTransport` instead of directly calling `AgentSession`.

#### What Changes in BackendService

Add a new method:

```dart
/// Creates an EventTransport wrapping an in-process session.
Future<EventTransport> createTransport({
  required BackendType type,
  required String prompt,
  required String cwd,
  SessionOptions? options,
  List<ContentBlock>? content,
}) async {
  final session = await createSessionForBackend(
    type: type, prompt: prompt, cwd: cwd, options: options, content: content,
  );
  final caps = capabilitiesFor(type);
  return InProcessTransport(session: session, capabilities: caps);
}
```

#### What Changes in ChatState

Replace direct session usage with transport:

1. **New field**: `EventTransport? _transport;` (alongside or replacing `_session`)
2. **`startSession`**: Call `backend.createTransport(...)` instead of `backend.createSessionForBackend(...)`. Store the transport. Subscribe to `transport.events` for EventHandler. Subscribe to `transport.events` filtered for `PermissionRequestEvent` for permission handling — BUT we still need the Completer-based `PermissionRequest` flow for the permission dialog. This means:
   - Keep `_session` reference internally for the permission stream
   - OR have the transport expose the permission stream separately
   - **Recommended**: `InProcessTransport` has a `permissionRequests` stream getter that forwards the session's permission stream. The frontend subscribes to this for the interactive dialog flow. When ready for remote transports, this becomes command-based.
3. **`sendMessage`**: Call `_transport!.send(SendMessageCommand(...))` instead of `_session!.send(text)`
4. **`interrupt`**: Call `_transport!.send(InterruptCommand(...))` instead of `_session!.interrupt()`
5. **`setModel`**, **`setPermissionMode`**: Call via transport commands
6. **Cleanup**: `_transport!.dispose()` in stopSession/clearSession/dispose

#### Key Decision: Permission Flow During Transition

For `InProcessTransport`, permissions still use the Completer pattern (the `PermissionRequest` objects are passed through). The transport adds a `permissionRequests` stream that forwards from the session. This keeps the existing permission dialog working unchanged.

For future remote transports, permissions will work via `PermissionResponseCommand` and request ID correlation (as designed in `07-transport-separation.md`). That conversion happens in the remote transport, not now.

#### Instructions for Agent

1. Read `frontend/lib/services/backend_service.dart` completely.
2. Read `frontend/lib/models/chat.dart` — focus on `startSession`, `sendMessage`, `interrupt`, `stopSession`, `clearSession`, `dispose`, `allowPermission`, `denyPermission`, and any method that calls `_session!.xxx()`.
3. Add `createTransport()` to `BackendService`.
4. Add `permissionRequests` stream getter to `InProcessTransport` that forwards from the wrapped session.
5. In `ChatState`:
   - Add `EventTransport? _transport` field
   - In `startSession`: create transport, subscribe to `transport.events` and `transport.permissionRequests`
   - Replace `_session!.send(text)` with `_transport!.send(SendMessageCommand(sessionId: ..., text: text))` in `sendMessage`
   - Replace `_session!.sendWithContent(content)` with `_transport!.send(SendMessageCommand(sessionId: ..., text: text, content: content))` in `sendMessage`
   - Replace `_session!.interrupt()` with `_transport!.send(InterruptCommand(sessionId: ...))` in `interrupt`
   - Replace `_session!.setModel(model)` with `_transport!.send(SetModelCommand(...))` wherever called
   - Replace `_session!.setPermissionMode(mode)` with `_transport!.send(SetPermissionModeCommand(...))` wherever called
   - Keep `_session` reference for `session.sessionId` and `session.resolvedSessionId` — add these to `EventTransport` interface
   - Update all cleanup sites (stopSession, clearSession, _handleSessionEnd, dispose) to also dispose transport
6. Update `startSession` signature: keep `EventHandler eventHandler` parameter, remove or keep `SdkMessageHandler messageHandler` if it's still there (it shouldn't be post-Phase 3).
7. Update all tests that create sessions to work with the transport-based flow.
8. Run `./frontend/run-flutter-test.sh` — all existing tests must still pass.
9. **CRITICAL: Zero behavioral change.** The app must work identically before and after this task.

---

### Task 4.5: Cleanup and Phase 3 Remnants

**Files to modify:** Various

Final cleanup pass for anything left from earlier phases.

#### Instructions for Agent

1. **Test files with SDKMessage references**: Search for `SDKMessage` across `frontend/test/` and `claude_dart_sdk/test/` and `codex_dart_sdk/test/`. Remove or update any stale references. These may be in comments, unused imports, or dead test code.

2. **`control_messages.dart` cleanup**: Check `agent_sdk_core/lib/src/types/control_messages.dart` for any `CliMessageType.sdkMessage` enum value or other SDKMessage remnants. Remove if unused.

3. **Re-export shim audit**: Check all files in `claude_dart_sdk/lib/src/types/`. Verify each re-export is actually used by consumers. Remove unused re-exports.

4. **Dead import cleanup**: Run `dart analyze` on each package to find unused imports.

5. **Verify complete test suite**: Run `./frontend/run-flutter-test.sh` and ensure all tests pass.

6. **Update CLAUDE.md**: Add a brief note about the EventTransport layer to the Architecture section:
   - EventTransport interface sits between ChatState and AgentSession
   - InProcessTransport wraps in-process sessions
   - Commands (SendMessageCommand, InterruptCommand, etc.) replace direct session method calls

---

## Task Dependency Graph

```
4.1 (BackendCommand types)
  ↓
4.2 (InsightsEvent serialization)    ← can run in parallel with 4.1
  ↓                    ↓
4.3 (EventTransport + InProcessTransport)  ← depends on both 4.1 and 4.2
  ↓
4.4 (Wire into ChatState/BackendService)   ← depends on 4.3
  ↓
4.5 (Cleanup)                              ← depends on 4.4
```

**4.1 and 4.2 are independent** — they can be implemented in parallel.
**4.3 depends on 4.1** (needs BackendCommand types) and conceptually on 4.2 (serialization is needed for the interface contract, even though InProcessTransport doesn't serialize).
**4.4 depends on 4.3** (needs the transport interface to wire up).
**4.5 depends on 4.4** (final cleanup after everything is wired).

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Behavioral regression in ChatState | Medium | All 2044 existing tests must pass after each task |
| Permission flow breakage | Medium | InProcessTransport forwards PermissionRequest stream directly — same Completer pattern |
| Missing edge case in serialization | Low | Round-trip tests for every event type with all fields |
| Test infrastructure changes | Low | TestableAgentSession already has events stream; transport wraps it cleanly |

## What This Phase Does NOT Do

- No WebSocket transport (future)
- No Docker transport (future)
- No remote backend support (future)
- No behavioral changes to the app
- No UI changes
- No new user-facing features

This phase is **purely structural** — adding the right seam so future transport implementations slot in with zero frontend changes.

---

## Estimated Total: ~5 tasks, ~1200 lines of new code, ~200 lines of modifications
