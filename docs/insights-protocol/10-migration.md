# Migration Guide: SDKMessage → InsightsEvent

This document provides a concrete, phased plan for migrating from the current `SDKMessage` architecture to `InsightsEvent`.

## What Exists Today

### Current Data Flow

```
Claude CLI stdout
  → CliProcess (raw JSON lines)
  → CliSession._handleMessage (parses JSON)
    → SDKMessage.fromJson(json)     ← typed object created
    → emit on messages stream
  → ChatState._messageSubscription
    → msg.rawJson ?? {}             ← typed object discarded!
    → SdkMessageHandler.handleMessage(chat, rawJson)
      → switch on rawJson['type'] string
      → creates OutputEntry objects
      → dispatches to ToolCard via toolName string
```

```
Codex JSON-RPC notification
  → JsonRpcClient (parsed notification)
  → CodexSession._handleNotification
    → builds synthetic Claude-format JSON dict
    → SDKMessage.fromJson(syntheticJson)     ← unnecessary parse
    → emit on messages stream
  → same ChatState path as above
```

### Files That Change

| File | Lines | Change |
|------|-------|--------|
| `agent_sdk_core/lib/src/types/sdk_messages.dart` | 599 | Eventually removed (replaced by InsightsEvent) |
| `agent_sdk_core/lib/src/types/content_blocks.dart` | 213 | Kept (content blocks are reused) |
| `agent_sdk_core/lib/src/backend_interface.dart` | ~130 | `AgentSession.messages` type changes |
| `claude_dart_sdk/lib/src/cli_session.dart` | ~300 | Emits InsightsEvent instead of SDKMessage |
| `codex_dart_sdk/lib/src/codex_session.dart` | 616 | Maps directly to InsightsEvent (removes synthetic JSON) |
| `frontend/lib/services/sdk_message_handler.dart` | 1114 | Replaced by EventHandler |
| `frontend/lib/models/chat.dart` | 1563 | Consumes InsightsEvent instead of rawJson |
| `frontend/lib/models/output_entry.dart` | 1174 | Adds `toolKind`, `provider` fields |
| `frontend/lib/widgets/tool_card.dart` | 1730 | Dispatches on ToolKind enum |

## Phase 0: Preparation (No Behavioral Changes)

### 0.1: Define InsightsEvent in agent_sdk_core

Create the sealed class hierarchy alongside the existing `SDKMessage`:

```
agent_sdk_core/lib/src/
  types/
    sdk_messages.dart          ← existing, untouched
    content_blocks.dart        ← existing, untouched
    insights_events.dart       ← NEW
    tool_kind.dart             ← NEW
    backend_provider.dart      ← NEW
```

No code changes to existing files. Just new types sitting alongside the old ones.

### 0.2: Add ToolKind to ToolUseOutputEntry

Add `toolKind` and `provider` fields to `ToolUseOutputEntry` with sensible defaults so existing code keeps working:

```dart
class ToolUseOutputEntry extends OutputEntry {
  // Existing fields unchanged
  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> toolInput;

  // New fields with defaults
  final ToolKind toolKind;              // default: ToolKind.other
  final BackendProvider? provider;      // default: null
  final List<String>? locations;        // default: null
  List<ContentBlock>? richContent;      // default: null
}
```

Update the existing `SdkMessageHandler` to populate `toolKind` using the tool name mapping table. This gives us `ToolKind`-based dispatch in `ToolCard` immediately, before the full migration.

### 0.3: Migrate ToolCard to ToolKind Dispatch

Change `ToolCard`'s dispatch from string tool names to `ToolKind`:

```dart
// Before:
switch (toolName) {
  case 'Bash': return _BashInputWidget(...);
  case 'Read': return _ReadInputWidget(...);
  ...
}

// After:
switch (toolKind) {
  case ToolKind.execute: return _ExecuteToolCard(...);
  case ToolKind.read:    return _ReadToolCard(...);
  ...
}
```

Within each tool card, the existing rendering code is preserved — it still reads from `toolInput` and `result`. We're just changing the dispatch mechanism.

**Tests:** Update tool card tests to set `toolKind` on test entries.

## Phase 1: Dual Emission (Parallel Streams)

### 1.1: Add InsightsEvent Stream to AgentSession

```dart
abstract class AgentSession {
  // Existing (kept for backwards compatibility)
  Stream<SDKMessage> get messages;

  // New
  Stream<InsightsEvent> get events;

  // Everything else unchanged
}
```

### 1.2: Claude CliSession Emits Both

In `CliSession._handleMessage`, after parsing to `SDKMessage`, also create the corresponding `InsightsEvent`:

```dart
void _handleMessage(Map<String, dynamic> json) {
  // Existing: parse and emit SDKMessage
  final sdkMessage = SDKMessage.fromJson(json);
  _messagesController.add(sdkMessage);

  // New: also emit InsightsEvent
  final event = _convertToInsightsEvent(json, sdkMessage);
  if (event != null) {
    _eventsController.add(event);
  }
}
```

The conversion uses the typed `SDKMessage` fields (not raw JSON) to build `InsightsEvent`. This validates that the mapping is correct by comparing with the existing `SdkMessageHandler` behavior.

### 1.3: Codex CodexSession Emits Both

In `CodexSession`, instead of building synthetic JSON:

```dart
void _handleItemStarted(Map<String, dynamic> params) {
  // Existing: build synthetic JSON and emit SDKMessage
  _emitToolUse(toolUseId: ..., toolName: 'Bash', toolInput: ...);

  // New: also emit InsightsEvent directly
  _eventsController.add(ToolInvocationEvent(
    id: _nextUuid(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    callId: item['id'],
    kind: ToolKind.execute,
    toolName: 'Bash',
    input: {'command': item['command'], 'cwd': item['cwd']},
    sessionId: threadId,
  ));
}
```

### 1.4: Validation

Write tests that consume both streams for the same session and verify they produce equivalent data:

```dart
test('dual emission produces matching events', () async {
  final session = await backend.createSession(...);

  final sdkMessages = <SDKMessage>[];
  final insightsEvents = <InsightsEvent>[];

  session.messages.listen(sdkMessages.add);
  session.events.listen(insightsEvents.add);

  await session.send('Hello');

  // Verify the events match semantically
  expect(insightsEvents.whereType<TextEvent>().length,
         sdkMessages.whereType<SDKAssistantMessage>()
           .where((m) => m.message.content.any((c) => c is TextBlock))
           .length);
});
```

## Phase 2: EventHandler Replaces SdkMessageHandler

### 2.1: Create EventHandler

New file: `frontend/lib/services/event_handler.dart`

Port the logic from `SdkMessageHandler` but consuming typed `InsightsEvent` instead of raw JSON:

```dart
class EventHandler {
  final _toolCallIndex = <String, ToolUseOutputEntry>{};
  final _parentCallToConversation = <String, String>{};

  void handleEvent(ChatState chat, InsightsEvent event) {
    switch (event) {
      case TextEvent e:           _handleText(chat, e);
      case ToolInvocationEvent e: _handleToolInvocation(chat, e);
      case ToolCompletionEvent e: _handleToolCompletion(chat, e);
      case TurnCompleteEvent e:   _handleTurnComplete(chat, e);
      case StreamDeltaEvent e:    _handleStreamDelta(chat, e);
      // ... etc
    }
  }
}
```

### 2.2: Wire Up ChatState

Switch `ChatState` from `messages` to `events`:

```dart
// Before:
_messageSubscription = _session!.messages.listen(
  (msg) {
    messageHandler.handleMessage(this, msg.rawJson ?? {});
  },
);

// After:
_eventSubscription = _session!.events.listen(
  (event) {
    eventHandler.handleEvent(this, event);
  },
);
```

### 2.3: Test Parity

Run the full test suite to verify that `EventHandler` produces identical `OutputEntry` sequences as `SdkMessageHandler` for the same inputs.

The `TestableAgentSession` needs to be updated to emit `InsightsEvent` via an `events` stream, in addition to the existing `messages` stream.

### 2.4: Remove SdkMessageHandler

Once `EventHandler` passes all tests, delete:
- `frontend/lib/services/sdk_message_handler.dart`
- All references to `SdkMessageHandler`

## Phase 3: Remove SDKMessage

### 3.1: Remove Dual Emission

`AgentSession` keeps only `events`:

```dart
abstract class AgentSession {
  Stream<InsightsEvent> get events;  // The only stream
  // messages removed
}
```

### 3.2: Remove Synthetic JSON from Codex

`CodexSession` no longer builds Claude-format JSON dicts. It maps Codex events directly to `InsightsEvent`:

```dart
// Before (current):
void _emitToolUse({...}) {
  _emitSdkMessage({
    'type': 'assistant',
    'uuid': _nextUuid(),
    'session_id': threadId,
    'message': {
      'role': 'assistant',
      'content': [
        {'type': 'tool_use', 'id': toolUseId, 'name': toolName, 'input': toolInput}
      ],
    },
  });
}

// After:
void _emitToolInvocation({...}) {
  _eventsController.add(ToolInvocationEvent(
    id: _nextUuid(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    callId: toolUseId,
    kind: toolKind,
    toolName: toolName,
    input: toolInput,
    sessionId: threadId,
  ));
}
```

This removes ~150 lines of synthetic JSON construction from `CodexSession`.

### 3.3: Simplify CliSession

`CliSession` no longer needs to emit `SDKMessage`. It can parse CLI JSON directly into `InsightsEvent`:

```dart
void _handleMessage(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  switch (type) {
    case 'assistant':
      _handleAssistant(json);  // emits TextEvent, ToolInvocationEvent
    case 'user':
      _handleUser(json);       // emits ToolCompletionEvent
    case 'result':
      _handleResult(json);     // emits TurnCompleteEvent
    case 'stream_event':
      _handleStream(json);     // emits StreamDeltaEvent
    case 'control_request':
      _handlePermission(json); // emits PermissionRequestEvent
    case 'system':
      _handleSystem(json);     // emits SessionInitEvent, etc.
  }
}
```

### 3.4: Delete SDKMessage

Remove from `agent_sdk_core`:
- `sdk_messages.dart` (SDKMessage, SDKAssistantMessage, SDKUserMessage, SDKResultMessage, SDKStreamEvent, SDKControlRequest, SDKControlResponse, SDKUnknownMessage, SDKErrorMessage, APIAssistantMessage, APIUserMessage)
- Related control message types that are only used by SDKMessage

Retain:
- `content_blocks.dart` (ContentBlock and subtypes — used by InsightsEvent)
- `callbacks.dart` (PermissionRequest — still used)
- `usage.dart` (Usage types — still used)
- `control_messages.dart` (parts used for CLI wire format, not for the event model)

### 3.5: Delete Re-Export Shims

The 10 single-line re-export files in `claude_dart_sdk/lib/src/types/` that just re-export `agent_sdk_core` types — evaluate which are still needed.

## Phase 4: Transport Layer

After Phases 1-3, the InsightsEvent model is the sole communication path. Adding transport separation:

### 4.1: Define EventTransport Interface

```dart
abstract class EventTransport {
  Stream<InsightsEvent> get events;
  Future<void> send(BackendCommand command);
  Stream<TransportStatus> get status;
  Future<void> dispose();
}
```

### 4.2: InProcessTransport

Wraps the existing in-process sessions. Zero behavioral change.

### 4.3: JSON Serialization

Add `toJson()` / `fromJson()` to all `InsightsEvent` subtypes and `BackendCommand` subtypes.

### 4.4: WebSocketTransport / DockerTransport

Implement as needed. See [07-transport-separation.md](07-transport-separation.md).

## Risk Mitigation

### Rollback Plan

Each phase can be rolled back independently:
- Phase 0: Revert ToolKind additions (but they're additive, no need)
- Phase 1: Stop listening to `events` stream, continue using `messages`
- Phase 2: Re-enable `SdkMessageHandler` (keep it around until Phase 3)
- Phase 3: This is the point of no return — all prior phases must be stable

### Testing Strategy

- **Unit tests** for each `InsightsEvent` subclass (`toJson`/`fromJson` round-trip)
- **Integration tests** comparing `SDKMessage` vs `InsightsEvent` output for the same backend interactions
- **Golden tests** for `ToolCard` rendering with different `ToolKind` values
- **Existing test suite** must pass at every phase

### What Could Go Wrong

| Risk | Mitigation |
|------|------------|
| Missed edge case in mapping | Phase 1 dual emission catches discrepancies |
| ToolCard rendering regression | Phase 0 migrates dispatch first, keeps rendering code |
| Codex behavior change | Phase 2/3 removes synthetic JSON only after EventHandler is proven |
| Permission flow breakage | PermissionRequest stays unchanged; only the event wrapper changes |
| Persistence format change | OutputEntry format is unchanged; only how entries are created changes |
| Test breakage | TestableAgentSession updated in Phase 1 to support both streams |

## Estimated Effort

| Phase | Scope | Risk |
|-------|-------|------|
| Phase 0 | New types + ToolKind dispatch | Low — additive only |
| Phase 1 | Dual emission in both SDKs | Medium — parallel streams must match |
| Phase 2 | EventHandler + ChatState rewire | Medium — largest functional change |
| Phase 3 | Remove SDKMessage + synthetic JSON | Low — just deletion after Phase 2 is stable |
| Phase 4 | Transport abstraction | Low — adds an interface, no behavior change |

Phases 0-2 can be done incrementally with passing tests at each step. Phase 3 is a cleanup pass. Phase 4 is independent and can be deferred.
