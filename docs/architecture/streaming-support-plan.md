# Streaming Support Implementation Plan

This document describes the implementation plan for supporting partial messages (streaming) in CC-Insights via ACP.

## Overview

ACP sends incremental `agent_message_chunk` and `agent_thought_chunk` updates that need to be accumulated and displayed in real-time. Tool calls arrive via `tool_call` and update via `tool_call_update`. All of these can be interleaved during a single turn.

### Key Requirements

1. **Streaming text always appears at the bottom** of the conversation
2. **Tool calls and other content insert above** the streaming text
3. **Buttery smooth rendering** - no jank during rapid text updates
4. **Unknown/unhandled messages must be visible** - never silently discard

### Rendering Order (Bottom = Newest)

```
┌─────────────────────────────────────────┐
│ [Persisted entries from entries list]   │
│   - User message                        │
│   - Tool call (completed)               │
│   - Assistant text (completed)          │
│   - Tool call (in_progress)             │
├─────────────────────────────────────────┤
│ [Streaming text entry]                  │  ← Always last (or second-to-last)
│   "The quick brown fox..." ▌            │     with blinking cursor
├─────────────────────────────────────────┤
│ [Streaming thinking entry]              │  ← Could be last or above text
│   "Let me reason about..." ▌            │     (order configurable later)
└─────────────────────────────────────────┘
```

Note: The order of streaming text vs thinking is configurable. Initially we'll put text last, thinking second-to-last. This can be swapped easily since they're rendered separately.

---

## Architecture

### Streaming State in ChatState

```dart
class ChatState extends ChangeNotifier {
  // Streaming entries (NOT in the entries list - rendered separately)
  TextOutputEntry? _streamingTextEntry;
  TextOutputEntry? _streamingThinkingEntry;

  // High-frequency update notifiers (avoid full widget tree rebuild)
  final ValueNotifier<String> streamingText = ValueNotifier('');
  final ValueNotifier<String> streamingThinking = ValueNotifier('');

  // Public getters for UI
  TextOutputEntry? get streamingTextEntry => _streamingTextEntry;
  TextOutputEntry? get streamingThinkingEntry => _streamingThinkingEntry;
  bool get hasStreamingContent =>
      _streamingTextEntry != null || _streamingThinkingEntry != null;
}
```

### Message Flow

```
ACP Agent
    ↓ agent_message_chunk / agent_thought_chunk / tool_call / etc.
SessionUpdateHandler (stateless - just routes)
    ↓ callbacks
ChatState
    ↓ updates streaming entries + notifies
UI (ConversationPanel)
    ↓ renders entries list + streaming widgets
StreamingTextWidget (uses ValueListenableBuilder)
    ↓ smooth text updates via ValueNotifier
```

### Interleaving Behavior

When a tool call arrives during text streaming:
1. Finalize current streaming text → move to entries list
2. Add tool call to entries list
3. If more text arrives later → start new streaming entry

This ensures tool calls always appear in correct chronological position.

**Important:** We do NOT finalize thinking when a tool call arrives. Thinking represents the agent's ongoing reasoning, which continues across tool calls. Only text (the agent's response to the user) gets finalized on tool call boundaries.

---

## Implementation Tasks

### Phase 1: Core Streaming Infrastructure

#### Task 1.1: Add Streaming State to ChatState
**File:** `frontend/lib/models/chat.dart`

Add streaming entry fields and ValueNotifiers:
- `_streamingTextEntry` - accumulates agent_message_chunk
- `_streamingThinkingEntry` - accumulates agent_thought_chunk
- `streamingText` ValueNotifier for high-frequency text updates
- `streamingThinking` ValueNotifier for high-frequency thinking updates
- Public getters for UI access
- `hasStreamingContent` convenience getter

#### Task 1.2: Add Streaming Handler Methods to ChatState
**File:** `frontend/lib/models/chat.dart`

Implement methods:
- `handleAgentMessageChunk(String text)` - accumulate text stream
- `handleAgentThoughtChunk(String text)` - accumulate thinking stream
- `finalizeStreamingText()` - move streaming text to entries list
- `finalizeStreamingThinking()` - move streaming thinking to entries list
- `finalizeAllStreams()` - finalize both on turn complete

Logic:
- First chunk creates new streaming entry with `isStreaming: true`
- Subsequent chunks call `appendDelta()` and update ValueNotifier
- Finalize sets `isStreaming: false` and moves to entries list

#### Task 1.3: Update Tool Call Handling to Finalize Streams
**File:** `frontend/lib/models/chat.dart`

When a tool call arrives:
- Call `finalizeStreamingText()` before adding tool to list
- This ensures tools appear in correct chronological order

When turn completes (prompt returns):
- Call `finalizeAllStreams()` to move any remaining content to list

#### Task 1.4: Unit Tests for Streaming Assembly
**File:** `frontend/test/models/chat_streaming_test.dart`

Uses `package:checks` for assertions (matching existing test patterns).

Test cases:
- Single text chunk creates streaming entry with `isStreaming: true`
- Multiple text chunks accumulate correctly (text appends)
- `finalizeStreamingText()` moves entry to list with `isStreaming: false`
- Finalized entry has correct accumulated content
- `handleToolCall()` finalizes current text stream before adding tool
- Text chunk after tool call starts NEW streaming entry
- Thinking chunks accumulate separately from text (different entry)
- Empty chunks (text: '') don't create entries or append empty string
- `finalizeAllStreams()` finalizes both text and thinking
- Interleaved text/tool/text creates correct entry order in list
- ValueNotifier updates on each chunk
- ValueNotifier resets on finalize

---

### Phase 2: Unknown Message Handling

#### Task 2.1: Update SessionUpdateHandler for Unknown Updates
**File:** `frontend/lib/acp/session_update_handler.dart`

Currently `UnknownSessionUpdate` just calls `debugPrint`. Change to:
- Add `onUnknownUpdate` callback with signature `void Function(Map<String, dynamic> rawJson)?`
- Call this callback for `UnknownSessionUpdate` cases
- Ensure we never silently discard updates

#### Task 2.2: Wire Up Unknown Update Display
**File:** `frontend/lib/panels/conversation_panel.dart`

- Add `onUnknownUpdate` handler in `_createUpdateHandler()`
- Create `UnknownMessageEntry` (already exists in output_entry.dart) with the raw data
- Add entry to conversation so it's visible in UI

#### Task 2.3: Unit Tests for Unknown Message Handling
**File:** `frontend/test/acp/session_update_handler_test.dart` (extend existing)

Add test cases:
- `UnknownSessionUpdate` triggers `onUnknownUpdate` callback with raw JSON
- Callback receives correct raw data
- Handler doesn't throw when callback is null (graceful no-op)

---

### Phase 3: UI Rendering

#### Task 3.1: Create StreamingTextWidget
**File:** `frontend/lib/widgets/display/streaming_text_widget.dart`

A widget optimized for streaming text display:
- Uses `ValueListenableBuilder` to listen to text ValueNotifier
- Wrapped in `RepaintBoundary` for isolation
- Blinking cursor indicator when streaming
- Smooth text updates without layout jank

#### Task 3.2: Create StreamingThinkingWidget
**File:** `frontend/lib/widgets/display/streaming_thinking_widget.dart`

Similar to StreamingTextWidget but styled for thinking content:
- Different visual treatment (e.g., italic, different background)
- Same performance optimizations

#### Task 3.3: Update ConversationPanel to Render Streaming Entries
**File:** `frontend/lib/panels/conversation_panel.dart`

Modify the conversation list rendering:
- Render normal entries list as before
- Append streaming widgets at bottom when present
- Order: entries → streaming thinking → streaming text (configurable)
- Use `context.watch<ChatState>()` for streaming entry presence
- Use ValueListenableBuilder inside streaming widgets for text content

#### Task 3.4: Widget Tests for Streaming Display
**File:** `frontend/test/widget/streaming_display_test.dart`

Test cases:
- Streaming widget appears when streaming entry exists
- Streaming widget disappears when stream finalizes
- Cursor blinks during streaming
- Text updates smoothly without rebuilding list
- Correct ordering of entries vs streaming widgets

---

### Phase 4: Integration

#### Task 4.1: Update Callback Wiring in ConversationPanel
**File:** `frontend/lib/panels/conversation_panel.dart`

Update `_createUpdateHandler()`:
- Change `onAgentMessage` to call `chat.handleAgentMessageChunk()`
- Change `onThinkingMessage` to call `chat.handleAgentThoughtChunk()`
- Add `onUnhandledUpdate` callback
- Ensure turn completion calls `chat.finalizeAllStreams()`

#### Task 4.2: Handle Turn Completion Signal
**File:** `frontend/lib/panels/conversation_panel.dart` or `chat.dart`

When `sendMessage()` returns (prompt completes):
- Call `finalizeAllStreams()`
- This handles the `stopReason: "end_turn"` case

Also handle error cases:
- On prompt error, still finalize streams
- On cancel, finalize streams

#### Task 4.3: Integration Tests
**File:** `frontend/test/integration/streaming_integration_test.dart`

End-to-end tests with mock ACP session:
- Send message, receive streaming chunks, verify display
- Interleaved tool calls appear in correct order
- Cancel mid-stream finalizes content
- Unknown updates appear in UI

---

### Phase 5: Polish

#### Task 5.1: Smooth Scrolling During Streaming
**File:** `frontend/lib/panels/conversation_panel.dart`

Ensure the conversation auto-scrolls to bottom during streaming:
- Only auto-scroll if user is already at bottom
- Smooth scroll animation
- Don't interrupt user manual scrolling

#### Task 5.2: Persistence Handling
**File:** `frontend/lib/models/chat.dart`

Streaming entries should NOT be persisted mid-stream:
- Only persist when finalized (moved to entries list)
- On app quit with active stream, finalize first
- Add note in entry that it was cut short if interrupted

#### Task 5.3: Visual Polish for Streaming Indicators
**Files:** Various widget files

- Blinking cursor animation
- "Thinking..." label or icon for thinking stream
- Subtle animation or glow during active streaming
- Consistent with existing UI theme

---

## Testing Strategy

### Unit Tests (Phase 1 & 2)
- Streaming assembly logic in ChatState
- Entry creation and finalization
- Interleaving behavior
- Unknown message handling

### Widget Tests (Phase 3)
- StreamingTextWidget rendering
- Cursor blinking behavior
- ValueNotifier updates
- RepaintBoundary effectiveness

### Integration Tests (Phase 4)
- Full flow from ACP update to UI display
- Mock ACP session for controlled testing
- Verify entry order and content

### Manual Testing
- Visual smoothness during rapid updates
- Scroll behavior during streaming
- Various interleaving scenarios
- Edge cases (very long text, rapid chunks, etc.)

---

## Files to Create/Modify Summary

### New Files
- `frontend/lib/widgets/display/streaming_text_widget.dart`
- `frontend/lib/widgets/display/streaming_thinking_widget.dart`
- `frontend/test/models/chat_streaming_test.dart`
- `frontend/test/widget/streaming_display_test.dart`
- `frontend/test/integration/streaming_integration_test.dart`

### Modified Files
- `frontend/lib/models/chat.dart` - streaming state and methods
- `frontend/lib/acp/session_update_handler.dart` - add onUnknownUpdate callback
- `frontend/lib/panels/conversation_panel.dart` - rendering and callback wiring
- `frontend/test/acp/session_update_handler_test.dart` - add unknown update tests

---

## Task Dependencies

```
Phase 1 (Core Infrastructure)
├── Task 1.1: Streaming State    ← Start here
├── Task 1.2: Handler Methods    ← Depends on 1.1
├── Task 1.3: Tool Call Handling ← Depends on 1.2
└── Task 1.4: Unit Tests         ← Depends on 1.1-1.3

Phase 2 (Unknown Messages)       ← Can run in parallel with Phase 1
├── Task 2.1: Handler Callback
├── Task 2.2: Wire Up Display    ← Depends on 2.1
└── Task 2.3: Unit Tests         ← Depends on 2.1

Phase 3 (UI Rendering)           ← Depends on Phase 1
├── Task 3.1: StreamingTextWidget
├── Task 3.2: StreamingThinkingWidget
├── Task 3.3: ConversationPanel  ← Depends on 3.1, 3.2
└── Task 3.4: Widget Tests       ← Depends on 3.1-3.3

Phase 4 (Integration)            ← Depends on Phase 1, 2, 3
├── Task 4.1: Callback Wiring    ← Depends on all above
├── Task 4.2: Turn Completion    ← Depends on 4.1
└── Task 4.3: Integration Tests  ← Depends on 4.1, 4.2

Phase 5 (Polish)                 ← After Phase 4
├── Task 5.1: Smooth Scrolling
├── Task 5.2: Persistence
└── Task 5.3: Visual Polish
```

---

## Open Questions / Future Considerations

1. **Order of thinking vs text** - Currently: thinking above text. Could be swapped. Consider making this a user preference.

2. **Multiple concurrent tool calls** - The current design handles this (each tool has unique ID, updates in-place). No special handling needed.

3. **Very long streaming content** - May need virtualization for extremely long streams. Defer unless performance issues arise.

4. **Resume behavior** - When resuming a session, the agent may replay history. Current design should handle this (chunks come through same path).

5. **Subagent streaming** - Subagent conversations should also support streaming. The same pattern applies - just route to the correct conversation.
