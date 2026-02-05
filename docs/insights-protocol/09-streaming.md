# Streaming Model Across Backends

Streaming — seeing text and tool input appear character-by-character — is important for a responsive UI. But each backend handles it very differently.

## Streaming Support by Backend

| Backend | Text Streaming | Tool Input Streaming | Mechanism |
|---------|---------------|---------------------|-----------|
| Claude CLI | Yes | Yes | `stream_event` messages with SSE-style deltas |
| Codex | No | No | Complete items via `item/started`/`item/completed` |
| ACP | Partial | No | `session/update` message chunks |
| Gemini CLI | Partial | No | `message` events with `delta: true` |

## Claude CLI Streaming (Full)

Claude provides the richest streaming experience with Anthropic's SSE-style events.

### Event Sequence

A typical streamed assistant response:

```
stream_event: message_start
stream_event: content_block_start (index=0, type=text)
stream_event: content_block_delta (index=0, text_delta: "Let me ")
stream_event: content_block_delta (index=0, text_delta: "fix that ")
stream_event: content_block_delta (index=0, text_delta: "bug.")
stream_event: content_block_stop (index=0)
stream_event: content_block_start (index=1, type=tool_use, name=Edit)
stream_event: content_block_delta (index=1, input_json_delta: '{"file_')
stream_event: content_block_delta (index=1, input_json_delta: 'path":"')
stream_event: content_block_delta (index=1, input_json_delta: 'src/main.dart"}')
stream_event: content_block_stop (index=1)
stream_event: message_stop
assistant: (full message with all content blocks)
```

### Mapped to InsightsEvent

```
StreamDeltaEvent(kind: messageStart)
StreamDeltaEvent(kind: blockStart, blockIndex: 0)
StreamDeltaEvent(kind: text, textDelta: "Let me ", blockIndex: 0)
StreamDeltaEvent(kind: text, textDelta: "fix that ", blockIndex: 0)
StreamDeltaEvent(kind: text, textDelta: "bug.", blockIndex: 0)
StreamDeltaEvent(kind: blockStop, blockIndex: 0)
StreamDeltaEvent(kind: blockStart, blockIndex: 1, callId: "tu_001")
StreamDeltaEvent(kind: toolInput, jsonDelta: '{"file_', callId: "tu_001", blockIndex: 1)
StreamDeltaEvent(kind: toolInput, jsonDelta: 'path":"', callId: "tu_001", blockIndex: 1)
StreamDeltaEvent(kind: toolInput, jsonDelta: 'src/main.dart"}', callId: "tu_001", blockIndex: 1)
StreamDeltaEvent(kind: blockStop, blockIndex: 1)
StreamDeltaEvent(kind: messageStop)
// Then the finalized events:
TextEvent(text: "Let me fix that bug.")
ToolInvocationEvent(callId: "tu_001", toolName: "Edit", input: {file_path: "src/main.dart", ...})
```

### Frontend Handling

The frontend handles streaming in two phases:

**Phase 1: Deltas (real-time UI)**
- `StreamDeltaEvent(kind: blockStart, type: text)` → Create `TextOutputEntry(isStreaming: true)` with empty text
- `StreamDeltaEvent(kind: text)` → `entry.appendDelta(delta)` + throttled `notifyListeners()`
- `StreamDeltaEvent(kind: blockStart, type: tool_use)` → Create `ToolUseOutputEntry(isStreaming: true)` with empty input
- `StreamDeltaEvent(kind: toolInput)` → `entry.appendInputDelta(delta)` (accumulate partial JSON)
- `StreamDeltaEvent(kind: blockStop)` → `entry.isStreaming = false`

**Phase 2: Finalization (authoritative data)**
- `TextEvent` arrives → Update existing streaming entry with final text, or create new if no streaming entry exists
- `ToolInvocationEvent` arrives → Update existing streaming entry with parsed input, or create new

This two-phase approach means:
- Streaming backends show text appearing character-by-character
- Non-streaming backends show text appearing all at once
- The same `OutputEntry` objects are used either way
- Persistence uses the finalized data, not deltas

## Codex: No Streaming

Codex emits complete items. There is no partial content.

```
item/started (commandExecution)  → ToolInvocationEvent (complete input)
item/completed (agentMessage)    → TextEvent (complete text)
item/completed (commandExecution) → ToolCompletionEvent (complete output)
```

**Frontend behavior:** Content appears as complete blocks. No typing effect. This is fine — Codex sessions feel more "batch-like" than Claude sessions.

The `StreamDeltaEvent` is simply never emitted by the Codex adapter.

## ACP: Message Chunks

ACP agents stream message content via `session/update` notifications with `agent_message_chunk` or `agent_thought_chunk` types. These are partial — multiple chunks build up the full message.

```json
{"method": "session/update", "params": {"sessionUpdate": {"type": "agent_message_chunk", "content": [{"type": "text", "text": "Let me "}]}}}
{"method": "session/update", "params": {"sessionUpdate": {"type": "agent_message_chunk", "content": [{"type": "text", "text": "fix that "}]}}}
{"method": "session/update", "params": {"sessionUpdate": {"type": "agent_message_chunk", "content": [{"type": "text", "text": "bug."}]}}}
```

### Mapped to InsightsEvent

**Option A: As StreamDeltaEvents** (consistent with Claude):
```
StreamDeltaEvent(kind: text, textDelta: "Let me ")
StreamDeltaEvent(kind: text, textDelta: "fix that ")
StreamDeltaEvent(kind: text, textDelta: "bug.")
```

**Option B: As buffered TextEvents** (simpler):
Each chunk replaces the previous text entry or appends to it.

**Recommendation: Option A.** This gives the frontend a consistent streaming model. The `EventHandler` doesn't need to know whether deltas came from Claude SSE or ACP message chunks — it handles `StreamDeltaEvent` the same way.

### What ACP Doesn't Stream

- **Tool input**: ACP reports tool calls via `tool_call_update` with complete `rawInput`. No partial input streaming.
- **Tool output**: Tool results arrive complete in `tool_call_update` with `status: completed`.
- **Thinking content**: `agent_thought_chunk` streams thinking text, but individual thoughts may arrive as complete chunks rather than character-level deltas.

## Gemini CLI: Message-Level Deltas

Gemini CLI's `stream-json` format indicates streaming via `delta: true` on message events:

```jsonl
{"type":"message","role":"assistant","content":"Let me ","delta":true,"timestamp":"..."}
{"type":"message","role":"assistant","content":"fix that ","delta":true,"timestamp":"..."}
{"type":"message","role":"assistant","content":"bug.","delta":false,"timestamp":"..."}
```

When `delta: true`, the content is a chunk. When `delta: false` (or absent), the content is the complete message.

### Mapped to InsightsEvent

```
StreamDeltaEvent(kind: text, textDelta: "Let me ")
StreamDeltaEvent(kind: text, textDelta: "fix that ")
TextEvent(text: "Let me fix that bug.")  // Final, complete
```

## Frontend Streaming Architecture

### Throttled Notifications

Streaming deltas can arrive very rapidly (potentially hundreds per second). The frontend uses throttled notifications:

```dart
Timer? _notifyTimer;

void _handleStreamDelta(ChatState chat, StreamDeltaEvent event) {
  // Apply delta immediately to the entry
  _applyDelta(event);

  // Throttle UI updates to every 50ms
  _notifyTimer ??= Timer(Duration(milliseconds: 50), () {
    _notifyTimer = null;
    chat.notifyListeners();
  });
}
```

This prevents unnecessary widget rebuilds while keeping the UI responsive.

### Streaming State on OutputEntry

```dart
class TextOutputEntry extends OutputEntry {
  String text;
  bool isStreaming;  // true while receiving deltas

  void appendDelta(String delta) {
    text += delta;
  }
}

class ToolUseOutputEntry extends OutputEntry {
  Map<String, dynamic> toolInput;
  bool isStreaming;
  String _partialInputJson = '';

  void appendInputDelta(String delta) {
    _partialInputJson += delta;
    // Optionally try to parse partial JSON for progressive display
  }

  void finalizeInput(Map<String, dynamic> parsedInput) {
    toolInput.clear();
    toolInput.addAll(parsedInput);
    _partialInputJson = '';
    isStreaming = false;
  }
}
```

### Content Block Tracking

During streaming, the handler tracks which output entries correspond to which content block indices:

```dart
final _streamingBlocks = <(String conversationId, int blockIndex), OutputEntry>{};
```

This allows deltas (which reference a `blockIndex`) to find the correct entry to update.

When `StreamDeltaEvent(kind: blockStop)` arrives, the entry is removed from the tracking map and marked as `isStreaming = false`.

When the final `TextEvent` or `ToolInvocationEvent` arrives, any remaining streaming entries are finalized with the authoritative data.

## Transport Considerations

Streaming over a transport (WebSocket, Docker) works naturally because `StreamDeltaEvent` is just another serialized event:

```jsonl
{"event":"stream_delta","kind":"text","textDelta":"Let me ","blockIndex":0}
{"event":"stream_delta","kind":"text","textDelta":"fix that ","blockIndex":0}
```

The transport does not need to buffer or aggregate — individual deltas are forwarded as they arrive. The frontend's existing throttling handles rapid arrival.

For high-latency transports, the backend could optionally batch deltas:

```jsonl
{"event":"stream_delta","kind":"text","textDelta":"Let me fix that ","blockIndex":0}
```

This reduces message count at the cost of slightly chunkier streaming appearance.
