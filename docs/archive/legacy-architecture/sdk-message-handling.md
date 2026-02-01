# SDK Message Handling Architecture

This document describes how SDK messages flow into app state in CC-Insights V2, with particular focus on tool_use/tool_result pairing for display widgets.

---

## Overview

The Claude SDK communicates via JSON-line messages through stdin/stdout. Messages arrive asynchronously and must be:

1. Parsed into typed SDK message objects
2. Routed to the correct conversation (primary or subagent)
3. Used to update app state (entries, agents, usage)
4. Paired when necessary (tool_use with tool_result)

---

## Message Types

| Message Type | Description | Key Fields |
|--------------|-------------|------------|
| `SDKSystemMessage` | Session init, status updates, compaction | `subtype`, `permissionMode`, `compactMetadata` |
| `SDKAssistantMessage` | Claude's responses | `content` (text, thinking, tool_use), `parentToolUseId` |
| `SDKUserMessage` | Tool results, synthetic context | `content` (tool_result, text), `toolUseResult`, `isSynthetic` |
| `SDKResultMessage` | Turn completion | `usage`, `totalCostUsd`, `result`, `errors` |
| `SDKStreamEvent` | Streaming text deltas | `textDelta`, `parentToolUseId` |
| `SDKErrorMessage` | Backend errors | `error` |

---

## The Tool Use/Result Pairing Problem

### Why Pairing is Needed

Display widgets like `DiffView` and `ToolCard` need both the tool input AND result to render correctly:

- **Edit tool**: Shows diff between old and new file content
- **TodoWrite tool**: Shows before/after todo list
- **Read tool**: Shows file content that was read

But these arrive in **separate messages**:

1. `SDKAssistantMessage` with `tool_use` block → has `toolInput`
2. `SDKUserMessage` with `tool_result` block → has `result`, `structuredResult`

### Sample Message Flow

```json
// Message 1: tool_use arrives
{
  "type": "assistant",
  "message": {
    "content": [{
      "type": "tool_use",
      "id": "toolu_01ABC...",
      "name": "Edit",
      "input": { "file_path": "/path/to/file.dart", "old_string": "...", "new_string": "..." }
    }]
  }
}

// Message 2: tool_result arrives (matched by toolUseId)
{
  "type": "user",
  "message": {
    "content": [{
      "type": "tool_result",
      "tool_use_id": "toolu_01ABC...",
      "content": "The file has been updated..."
    }]
  },
  "tool_use_result": {
    "filePath": "/path/to/file.dart",
    "originalFile": "...",
    "structuredPatch": [...]
  }
}
```

---

## Solution: Mutable ToolUseOutputEntry

### Design Decision

`ToolUseOutputEntry` is **intentionally mutable** while other `OutputEntry` types remain immutable. This is pragmatic because:

1. Tool use entries represent an **ongoing operation** that completes later
2. Display widgets expect the **paired data** to be in one place
3. Immutability at the **conversation level** is sufficient for state management
4. This matches V1's proven, working approach

### ToolUseOutputEntry Structure

```dart
/// A tool use output entry representing a tool invocation and its result.
///
/// Unlike other OutputEntry types, this is mutable because tool results
/// arrive in a separate message after the tool use.
class ToolUseOutputEntry extends OutputEntry {
  // Immutable fields (set at creation from tool_use message)
  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> toolInput;
  final String? model;

  // Mutable fields (set later from tool_result message)
  dynamic result;
  bool isError;
  Map<String, dynamic>? structuredResult;

  // UI state
  bool isExpanded;

  // Debug data
  final List<Map<String, dynamic>> rawMessages = [];
}
```

### Pairing Flow

```
tool_use arrives
      │
      ▼
Create ToolUseOutputEntry
(result = null, isError = false)
      │
      ▼
Add to conversation.entries
      │
      ▼
Store toolUseId → conversationId mapping
      │
      ... time passes ...
      │
      ▼
tool_result arrives
      │
      ▼
Look up conversationId by toolUseId
      │
      ▼
Find ToolUseOutputEntry in conversation
      │
      ▼
Update entry in-place:
  entry.result = resultText
  entry.isError = block.isError
  entry.structuredResult = msg.toolUseResult
      │
      ▼
notifyListeners() → UI rebuilds
```

---

## Message Handler Architecture

### SdkMessageHandler Class

```dart
class SdkMessageHandler {
  final NotifyListenersCallback? _notifyListeners;
  final NotificationCallback? _notificationCallback;

  SdkMessageHandler({
    NotifyListenersCallback? onNotifyListeners,
    NotificationCallback? onNotification,
  });

  /// Handle an SDK message and update chat state.
  void handleMessage(ChatState chat, SDKMessage msg);

  /// Handle a permission request from the SDK.
  void handlePermissionRequest(ChatState chat, PermissionRequest req);
}
```

### Message Routing

```dart
void handleMessage(ChatState chat, SDKMessage msg) {
  switch (msg) {
    case SDKSystemMessage m:
      _handleSystemMessage(chat, m);
    case SDKAssistantMessage m:
      _handleAssistantMessage(chat, m);
    case SDKUserMessage m:
      _handleUserMessage(chat, m);
    case SDKResultMessage m:
      _handleResultMessage(chat, m);
    case SDKStreamEvent m:
      _handleStreamEvent(chat, m);
    case SDKErrorMessage m:
      _handleErrorMessage(chat, m);
    case SDKUnknownMessage _:
      break; // Ignore unknown messages
  }
}
```

---

## Conversation Routing

### Determining Target Conversation

Messages include `parentToolUseId` to indicate which agent/conversation they belong to:

| `parentToolUseId` | Target |
|-------------------|--------|
| `null` | Primary conversation |
| Some ID | Subagent conversation (ID is the Task tool's toolUseId) |

### ToolUseId → ConversationId Mapping

`ChatState` maintains a mapping for routing tool results:

```dart
class ChatState extends ChangeNotifier {
  // Maps tool_use_id to conversation_id for routing tool results
  final Map<String, String> _toolUseIdToConversationId = {};

  void addToolUseMapping(String toolUseId, String conversationId) {
    _toolUseIdToConversationId[toolUseId] = conversationId;
  }

  String? getConversationForToolUse(String toolUseId) {
    return _toolUseIdToConversationId[toolUseId];
  }
}
```

---

## Special Message Handling

### 1. System Messages

#### Init (`subtype: 'init'`)
- Store permission mode, model, available tools
- Session is ready for use

#### Status (`subtype: 'status'`)
- `status: 'compacting'` → show compaction indicator
- `status: null` → clear compaction indicator

#### Compact Boundary (`subtype: 'compact_boundary'`)
- Context was compacted
- Show notification in output
- Next message may be synthetic context summary

### 2. Task Tool (Subagent Creation)

When a `tool_use` with `name: 'Task'` arrives:

```dart
void _handleToolUse(ChatState chat, String agentId, ToolUseBlock block, ...) {
  if (block.name == 'Task') {
    final resumeId = block.input['resume'] as String?;

    if (resumeId != null) {
      // Resume existing agent
      final existingConv = chat.findConversationByAgentId(resumeId);
      if (existingConv != null) {
        chat.addToolUseMapping(block.id, existingConv.id);
        chat.addOutputEntry(existingConv.id, toolEntry);
        return;
      }
    }

    // Create new subagent conversation
    final label = block.input['name'] as String? ?? _generateLabel(chat);
    final taskDescription = block.input['prompt'] as String?;

    chat.addSubagentConversation(
      block.id,  // SDK agent ID = tool_use_id for Task
      label,
      taskDescription,
    );

    chat.addOutputEntry(block.id, toolEntry);
  } else {
    // Regular tool - add to current agent's conversation
    chat.addOutputEntry(conversationId, toolEntry);
    chat.addToolUseMapping(block.id, conversationId);
  }
}
```

### 3. Synthetic Context (After Compaction)

When `SDKUserMessage.isSynthetic == true`:

```dart
if (msg.isSynthetic == true) {
  for (final block in msg.message.content) {
    if (block is TextBlock && block.text.isNotEmpty) {
      chat.addEntry(ContextSummaryEntry(
        timestamp: DateTime.now(),
        summary: block.text,
      ));
    }
  }
  return;
}
```

### 4. Permission Requests

Permission requests arrive via a separate callback, not the message stream:

```dart
void handlePermissionRequest(ChatState chat, PermissionRequest req) {
  // Route to correct conversation using toolUseId
  String conversationId = chat.data.primaryConversation.id;

  if (req.toolUseId != null) {
    final mapped = chat.getConversationForToolUse(req.toolUseId!);
    if (mapped != null) {
      conversationId = mapped;
    }
  }

  // Add to pending requests queue
  chat.addPendingRequest(conversationId, req);

  // Trigger notification for first request in queue
  if (chat.pendingRequests.length == 1) {
    _notificationCallback?.call(chat, req);
  }
}
```

### 5. Structured Tool Results

Some tools provide structured data beyond the text result:

| Tool | `structuredResult` Contains |
|------|----------------------------|
| Edit | `filePath`, `originalFile`, `structuredPatch`, `oldString`, `newString` |
| TodoWrite | `oldTodos`, `newTodos` |
| Read | (file content is in result text) |
| Bash | (output is in result text) |

The `structuredResult` is extracted from `SDKUserMessage.toolUseResult`:

```dart
session.updateToolResult(
  conversationId,
  block.toolUseId,
  resultText,
  block.isError ?? false,
  structuredResult: msg.toolUseResult,  // Structured data for display widgets
);
```

---

## State Update Flow

### Complete Message Flow Diagram

```
                    SDK Backend
                         │
                         │ JSON Lines (stdout)
                         ▼
                  ┌─────────────┐
                  │ ClaudeSession│
                  │   Stream    │
                  └──────┬──────┘
                         │
           ┌─────────────┼─────────────┐
           │             │             │
           ▼             ▼             ▼
      SDKMessage   PermissionRequest  Error
           │             │             │
           ▼             ▼             ▼
     ┌─────────────────────────────────────┐
     │          SdkMessageHandler          │
     │  ┌───────────────────────────────┐  │
     │  │ handleMessage()               │  │
     │  │ handlePermissionRequest()     │  │
     │  └───────────────────────────────┘  │
     └──────────────────┬──────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
   Add Entry      Update Tool      Add Pending
   to Conv        Result           Request
        │               │               │
        └───────────────┼───────────────┘
                        │
                        ▼
                  ┌───────────┐
                  │ ChatState │
                  │ notifyListeners()
                  └─────┬─────┘
                        │
                        ▼
                  ┌───────────────┐
                  │ UI Rebuilds   │
                  │ - ConversationPanel
                  │ - ToolCard    │
                  │ - DiffView    │
                  │ - PermissionWidget
                  └───────────────┘
```

---

## ChatState Integration

### Required Methods

```dart
class ChatState extends ChangeNotifier {
  ChatData _data;
  final Map<String, String> _toolUseIdToConversationId = {};
  final List<PendingRequest> pendingRequests = [];

  // Add output entry to a conversation
  void addOutputEntry(String conversationId, OutputEntry entry);

  // Update a tool use entry with its result
  void updateToolResult(
    String conversationId,
    String toolUseId,
    String result,
    bool isError, {
    Map<String, dynamic>? structuredResult,
  });

  // Track tool_use_id → conversation_id mapping
  void addToolUseMapping(String toolUseId, String conversationId);
  String? getConversationForToolUse(String toolUseId);

  // Create subagent conversation
  void addSubagentConversation(
    String sdkAgentId,
    String label,
    String? taskDescription,
  );

  // Permission request management
  void addPendingRequest(String conversationId, PermissionRequest req);
  void removePendingRequest(String callbackId);
  void removePendingRequestByToolUseId(String toolUseId);
  PendingRequest? getNextPendingRequest();
}
```

### updateToolResult Implementation

```dart
void updateToolResult(
  String conversationId,
  String toolUseId,
  String result,
  bool isError, {
  Map<String, dynamic>? structuredResult,
}) {
  // Check primary conversation
  if (conversationId == _data.primaryConversation.id) {
    for (final entry in _data.primaryConversation.entries) {
      if (entry is ToolUseOutputEntry && entry.toolUseId == toolUseId) {
        entry.result = result;
        entry.isError = isError;
        entry.structuredResult = structuredResult;
        notifyListeners();
        return;
      }
    }
  }

  // Check subagent conversations
  final subConv = _data.subagentConversations[conversationId];
  if (subConv != null) {
    for (final entry in subConv.entries) {
      if (entry is ToolUseOutputEntry && entry.toolUseId == toolUseId) {
        entry.result = result;
        entry.isError = isError;
        entry.structuredResult = structuredResult;
        notifyListeners();
        return;
      }
    }
  }
}
```

---

## Display Widget Integration

### ToolCard Widget

```dart
class ToolCard extends StatelessWidget {
  final ToolUseOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(entry.toolName),
      subtitle: entry.result != null
          ? Text(entry.isError ? 'Error' : 'Completed')
          : Text('Running...'),
      children: [
        // Show tool input
        _buildInput(entry.toolInput),

        // Show result if available
        if (entry.result != null)
          _buildResult(entry),

        // Show structured result (diff, todos, etc.)
        if (entry.structuredResult != null)
          _buildStructuredResult(entry),
      ],
    );
  }
}
```

### DiffView Widget

```dart
class DiffView extends StatelessWidget {
  final ToolUseOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    final structured = entry.structuredResult;
    if (structured == null) return const SizedBox.shrink();

    final filePath = structured['filePath'] as String?;
    final patch = structured['structuredPatch'] as List?;

    // Render diff using patch data
    return Column(
      children: [
        Text(filePath ?? 'Unknown file'),
        for (final hunk in patch ?? [])
          _buildHunk(hunk),
      ],
    );
  }
}
```

---

## Error Handling

### SDK Error Messages

```dart
void _handleErrorMessage(ChatState chat, SDKErrorMessage msg) {
  final errorText = msg.error?.toString() ?? 'Unknown error';

  // Add error to primary conversation
  chat.addEntry(TextOutputEntry(
    timestamp: DateTime.now(),
    text: '❌ Error: $errorText',
    contentType: 'error',
  ));

  // Update chat state
  chat.setError(errorText);
}
```

### Permission Request Timeout

When a permission request times out, the SDK sends a tool_result with an error. Clean up the stale request:

```dart
// In _handleUserMessage, after processing tool_result:
if (block is ToolResultBlock) {
  // ... update tool result ...

  // Clear any stale permission request for this tool
  chat.removePendingRequestByToolUseId(block.toolUseId);
}
```

---

## Testing Considerations

### Unit Tests

Test the message handler with mock ChatState:

```dart
test('pairs tool_use with tool_result', () {
  final chat = ChatState.create(name: 'Test', worktreeRoot: '/tmp');
  final handler = SdkMessageHandler();

  // Simulate tool_use
  handler.handleMessage(chat, SDKAssistantMessage(
    uuid: '1',
    sessionId: 'sess',
    message: APIAssistantMessage(
      role: 'assistant',
      content: [ToolUseBlock(
        id: 'tool_1',
        name: 'Read',
        input: {'file_path': '/tmp/test.txt'},
      )],
    ),
  ));

  // Verify entry created with no result
  final entry = chat.data.primaryConversation.entries.last as ToolUseOutputEntry;
  expect(entry.toolUseId, 'tool_1');
  expect(entry.result, isNull);

  // Simulate tool_result
  handler.handleMessage(chat, SDKUserMessage(
    sessionId: 'sess',
    message: APIUserMessage(
      role: 'user',
      content: [ToolResultBlock(
        toolUseId: 'tool_1',
        content: 'File contents here',
      )],
    ),
  ));

  // Verify result paired
  expect(entry.result, 'File contents here');
  expect(entry.isError, false);
});
```

### Widget Tests

Test display widgets handle both paired and unpaired entries:

```dart
testWidgets('ToolCard shows running state before result', (tester) async {
  final entry = ToolUseOutputEntry(
    timestamp: DateTime.now(),
    toolName: 'Read',
    toolUseId: 'tool_1',
    toolInput: {'file_path': '/tmp/test.txt'},
  );

  await tester.pumpWidget(MaterialApp(
    home: ToolCard(entry: entry),
  ));

  expect(find.text('Running...'), findsOneWidget);

  // Update entry
  entry.result = 'File contents';
  entry.isError = false;

  await tester.pump();

  expect(find.text('Completed'), findsOneWidget);
});
```

---

## Migration from V1

### Files to Preserve/Adapt

| V1 File | V2 Action |
|---------|-----------|
| `flutter_app/lib/services/sdk_message_handler.dart` | Adapt for V2 ChatState |
| `flutter_app/lib/models/session.dart` (OutputEntry classes) | Already moved to V2 output_entry.dart |
| `flutter_app/lib/widgets/tool_card.dart` | Preserve, update imports |
| `flutter_app/lib/widgets/diff_view.dart` | Preserve, update imports |

### Key Differences from V1

| Aspect | V1 | V2 |
|--------|----|----|
| State holder | `Session` (flat) | `ChatState` with `ConversationData` |
| Agent storage | `Session.agents` map | `ChatState._activeAgents` + `ConversationData.entries` |
| Routing | `parentToolUseId` → agentId | `parentToolUseId` → conversationId |
| Selection | `Session.selectedAgentId` | `ChatState._selectedConversationId` |

---

## Streaming Support

The SDK sends real-time streaming events that allow text to appear in the UI as it's generated, rather than waiting for the complete response.

### Stream Event Types

| Event Type | Description |
|------------|-------------|
| `message_start` | New message beginning, clear streaming state |
| `content_block_start` | New content block (text, thinking, tool_use) |
| `content_block_delta` | Incremental content (text_delta, thinking_delta, input_json_delta) |
| `content_block_stop` | Content block complete |
| `message_delta` | Message metadata (stop_reason) |
| `message_stop` | Message complete |

### Message Ordering

Observed message ordering from the SDK:

```
1. system (init)
2. stream_event: message_start
3. stream_event: content_block_start (index=0, type=text)
4. stream_event: content_block_delta (text_delta: "To")
5. stream_event: content_block_delta (text_delta: " fin")
6. stream_event: content_block_delta (text_delta: "d the prime...")
   ... many more deltas ...
7. assistant (COMPLETE message - arrives BEFORE content_block_stop!)
8. stream_event: content_block_stop
9. stream_event: message_delta (stop_reason: "end_turn")
10. stream_event: message_stop
11. result
```

**Key observation**: The complete `assistant` message arrives **before** `content_block_stop`. This allows us to finalize streaming entries with the complete text.

### Streaming Architecture

#### Mutable TextOutputEntry

Similar to `ToolUseOutputEntry`, `TextOutputEntry` is mutable to support streaming:

```dart
class TextOutputEntry extends OutputEntry {
  final String contentType; // 'text', 'thinking', 'error'

  /// The text content. Mutable during streaming.
  String text;

  /// Whether this entry is still receiving streaming deltas.
  bool isStreaming;

  TextOutputEntry({
    required super.timestamp,
    required this.text,
    this.contentType = 'text',
    this.isStreaming = false,
  });

  void appendDelta(String delta) {
    text += delta;
  }
}
```

#### Streaming State Tracking

The handler tracks which entries are currently streaming:

```dart
class SdkMessageHandler {
  // Track streaming entries per conversation
  final Map<String, TextOutputEntry?> _streamingTextEntry = {};
  final Map<String, ToolUseOutputEntry?> _streamingToolEntry = {};

  // Throttle notifications for performance
  Timer? _notifyTimer;

  void _throttledNotify() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 16), () {
      _notifyListeners?.call();
    });
  }
}
```

### Stream Event Handling

```dart
void _handleStreamEvent(ChatState chat, SDKStreamEvent msg) {
  final conversationId = _resolveConversationId(chat, msg.parentToolUseId);
  final event = msg.event;
  final eventType = event['type'] as String?;

  switch (eventType) {
    case 'message_start':
      // Clear any previous streaming state
      _streamingTextEntry[conversationId] = null;
      _streamingToolEntry[conversationId] = null;

    case 'content_block_start':
      final block = event['content_block'] as Map<String, dynamic>;
      final blockType = block['type'] as String?;

      if (blockType == 'text') {
        // Create streaming text entry
        final entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: block['text'] as String? ?? '',
          contentType: 'text',
          isStreaming: true,
        );
        _streamingTextEntry[conversationId] = entry;
        chat.addOutputEntry(conversationId, entry);

      } else if (blockType == 'thinking') {
        // Create streaming thinking entry
        final entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: block['thinking'] as String? ?? '',
          contentType: 'thinking',
          isStreaming: true,
        );
        _streamingTextEntry[conversationId] = entry;
        chat.addOutputEntry(conversationId, entry);

      } else if (blockType == 'tool_use') {
        // Create placeholder tool entry (input streams separately)
        final entry = ToolUseOutputEntry(
          timestamp: DateTime.now(),
          toolName: block['name'] as String? ?? '',
          toolUseId: block['id'] as String? ?? '',
          toolInput: {},
          isStreaming: true,
        );
        _streamingToolEntry[conversationId] = entry;
        chat.addOutputEntry(conversationId, entry);
        chat.addToolUseMapping(entry.toolUseId, conversationId);
      }

    case 'content_block_delta':
      final delta = event['delta'] as Map<String, dynamic>;
      final deltaType = delta['type'] as String?;

      if (deltaType == 'text_delta') {
        final text = delta['text'] as String? ?? '';
        _streamingTextEntry[conversationId]?.appendDelta(text);
        _throttledNotify();

      } else if (deltaType == 'thinking_delta') {
        final thinking = delta['thinking'] as String? ?? '';
        _streamingTextEntry[conversationId]?.appendDelta(thinking);
        _throttledNotify();

      } else if (deltaType == 'input_json_delta') {
        // Tool input JSON - accumulate but don't parse until complete
        // The assistant message will have the complete parsed input
      }

    case 'content_block_stop':
    case 'message_delta':
    case 'message_stop':
      // Finalization happens in _handleAssistantMessage
      break;
  }
}
```

### Finalizing Streaming Entries

When the complete `assistant` message arrives, finalize any streaming entries:

```dart
void _handleAssistantMessage(ChatState chat, SDKAssistantMessage msg) {
  final conversationId = _resolveConversationId(chat, msg.parentToolUseId);

  for (final block in msg.message.content) {
    switch (block) {
      case TextBlock b:
        final streamingEntry = _streamingTextEntry[conversationId];
        if (streamingEntry != null && streamingEntry.isStreaming) {
          // Finalize streaming entry with complete text
          streamingEntry.text = b.text;
          streamingEntry.isStreaming = false;
          _streamingTextEntry[conversationId] = null;
        } else {
          // No streaming - add as normal entry
          chat.addOutputEntry(conversationId, TextOutputEntry(
            timestamp: DateTime.now(),
            text: b.text,
            contentType: 'text',
          ));
        }

      case ThinkingBlock b:
        final streamingEntry = _streamingTextEntry[conversationId];
        if (streamingEntry != null &&
            streamingEntry.isStreaming &&
            streamingEntry.contentType == 'thinking') {
          // Finalize streaming thinking entry
          streamingEntry.text = b.thinking;
          streamingEntry.isStreaming = false;
          _streamingTextEntry[conversationId] = null;
        } else {
          chat.addOutputEntry(conversationId, TextOutputEntry(
            timestamp: DateTime.now(),
            text: b.thinking,
            contentType: 'thinking',
          ));
        }

      case ToolUseBlock b:
        final streamingEntry = _streamingToolEntry[conversationId];
        if (streamingEntry != null &&
            streamingEntry.isStreaming &&
            streamingEntry.toolUseId == b.id) {
          // Finalize streaming tool entry with complete input
          streamingEntry.toolInput.addAll(b.input);
          streamingEntry.isStreaming = false;
          _streamingToolEntry[conversationId] = null;
        } else {
          // No streaming - handle normally
          _handleToolUse(chat, conversationId, b, msg.message.model, msg.rawJson);
        }
    }
  }

  _notifyListeners?.call();
}
```

### UI Streaming Indicator

Display widgets show a streaming indicator while content is arriving:

```dart
class TextEntryWidget extends StatelessWidget {
  final TextOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Render text with markdown
        MarkdownBody(data: entry.text),

        // Show streaming indicator
        if (entry.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '...',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

### Tool Use Streaming

Tool use blocks also stream their input JSON in `input_json_delta` events. For simplicity, we show a placeholder while streaming:

```dart
class ToolCardWidget extends StatelessWidget {
  final ToolUseOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.isStreaming) {
      return ListTile(
        leading: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Using ${entry.toolName}...'),
        subtitle: Text('Preparing...'),
      );
    }

    // Normal tool card rendering
    return ExpansionTile(
      title: Text(entry.toolName),
      // ...
    );
  }
}
```

### Throttling for Performance

Streaming deltas arrive rapidly (many per second). Throttling prevents UI thrashing:

```dart
class SdkMessageHandler {
  Timer? _notifyTimer;

  /// Notify listeners at most once per frame (~60fps)
  void _throttledNotify() {
    if (_notifyTimer?.isActive ?? false) return;

    _notifyTimer = Timer(const Duration(milliseconds: 16), () {
      _notifyListeners?.call();
    });
  }

  void dispose() {
    _notifyTimer?.cancel();
  }
}
```

Alternative: Use `SchedulerBinding` for frame-aligned updates:

```dart
bool _hasPendingUpdates = false;

void _scheduleNotify() {
  if (!_hasPendingUpdates) {
    _hasPendingUpdates = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _hasPendingUpdates = false;
      _notifyListeners?.call();
    });
  }
}
```

### Streaming Flow Diagram

```
stream_event: message_start
         │
         ▼
stream_event: content_block_start (type=text)
         │
         ▼
    Create TextOutputEntry
    (text="", isStreaming=true)
         │
         ▼
    Add to conversation.entries
         │
         ▼
stream_event: content_block_delta (text="To")
         │
         ▼
    entry.appendDelta("To")
    throttledNotify() ──────────► UI shows "To"
         │
         ▼
stream_event: content_block_delta (text=" find")
         │
         ▼
    entry.appendDelta(" find")
    throttledNotify() ──────────► UI shows "To find"
         │
         ▼
    ... more deltas ...
         │
         ▼
assistant message (complete text)
         │
         ▼
    entry.text = completeText
    entry.isStreaming = false
    notifyListeners() ──────────► UI shows final text, no indicator
         │
         ▼
stream_event: content_block_stop
stream_event: message_stop
result
```

### Thinking Block Streaming

Extended thinking blocks (when enabled) stream similarly with `thinking_delta` events:

```json
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me "}}}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"analyze "}}}
...
```

The handling is identical to text blocks, just with `contentType: 'thinking'`.

**Note**: Extended thinking requires `maxThinkingTokens` in session options (e.g., 16000). The backend can enable this with:
```typescript
maxThinkingTokens: 16000,
```

### Multi-Block Streaming

With extended thinking enabled, the model produces **multiple concurrent content blocks**:

1. `index: 0` - thinking block (streams first)
2. `index: 1` - text block (streams after thinking completes)

The architecture must track streaming entries by **block index**, not just conversation:

```dart
class SdkMessageHandler {
  // Track streaming entries by (conversationId, blockIndex)
  final Map<String, Map<int, OutputEntry>> _streamingEntries = {};

  void _handleContentBlockStart(String conversationId, int index, Map<String, dynamic> block) {
    _streamingEntries[conversationId] ??= {};

    final blockType = block['type'] as String?;
    final entry = switch (blockType) {
      'thinking' => TextOutputEntry(
        timestamp: DateTime.now(),
        text: '',
        contentType: 'thinking',
        isStreaming: true,
      ),
      'text' => TextOutputEntry(
        timestamp: DateTime.now(),
        text: '',
        contentType: 'text',
        isStreaming: true,
      ),
      'tool_use' => ToolUseOutputEntry(
        timestamp: DateTime.now(),
        toolName: block['name'] as String? ?? '',
        toolUseId: block['id'] as String? ?? '',
        toolInput: {},
        isStreaming: true,
      ),
      _ => null,
    };

    if (entry != null) {
      _streamingEntries[conversationId]![index] = entry;
      chat.addOutputEntry(conversationId, entry);
    }
  }

  void _handleContentBlockDelta(String conversationId, int index, Map<String, dynamic> delta) {
    final entry = _streamingEntries[conversationId]?[index];
    if (entry == null) return;

    final deltaType = delta['type'] as String?;
    switch (deltaType) {
      case 'thinking_delta':
        (entry as TextOutputEntry).appendDelta(delta['thinking'] as String? ?? '');
      case 'text_delta':
        (entry as TextOutputEntry).appendDelta(delta['text'] as String? ?? '');
      case 'input_json_delta':
        // Accumulate for tool input - parsed in assistant message
        break;
    }
    _throttledNotify();
  }

  void _handleContentBlockStop(String conversationId, int index) {
    // Individual block complete - entry remains until assistant message finalizes
  }

  void _handleAssistantMessage(ChatState chat, SDKAssistantMessage msg) {
    final conversationId = _resolveConversationId(chat, msg.parentToolUseId);
    final streamingMap = _streamingEntries[conversationId];

    for (var i = 0; i < msg.message.content.length; i++) {
      final block = msg.message.content[i];
      final streamingEntry = streamingMap?[i];

      switch (block) {
        case TextBlock b:
          if (streamingEntry is TextOutputEntry && streamingEntry.isStreaming) {
            streamingEntry.text = b.text;
            streamingEntry.isStreaming = false;
          } else {
            chat.addOutputEntry(conversationId, TextOutputEntry(...));
          }
        case ThinkingBlock b:
          if (streamingEntry is TextOutputEntry &&
              streamingEntry.isStreaming &&
              streamingEntry.contentType == 'thinking') {
            streamingEntry.text = b.thinking;
            streamingEntry.isStreaming = false;
          } else {
            chat.addOutputEntry(conversationId, TextOutputEntry(...));
          }
        case ToolUseBlock b:
          // Similar pattern...
      }
    }

    // Clear streaming state for this conversation
    _streamingEntries.remove(conversationId);
  }
}
```

### UI with Concurrent Streaming

During extended thinking, the UI shows both blocks updating in real-time:

```
┌──────────────────────────────────────────────────┐
│ Yes, there are infinitely many primes p where    │
│ p ≡ 3 (mod 4). This is a classic result in       │
│ number theory, proven by Euclid-style...         │
└──────────────────────────────────────────────────┘
◐
_The user is asking about Dirichlet's theorem on primes in arithmetic progressions..._
```

- Main response in a box (text block, index 1)
- Spinner below
- Thinking in italics/grey (thinking block, index 0)

The thinking entry is rendered with distinct styling:

```dart
class TextEntryWidget extends StatelessWidget {
  final TextOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    final isThinking = entry.contentType == 'thinking';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: isThinking ? BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isThinking)
            Text(
              entry.text,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            )
          else
            MarkdownBody(data: entry.text),

          if (entry.isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}
```

---

## Summary

1. **ToolUseOutputEntry is mutable** - allows pairing tool_use with tool_result
2. **TextOutputEntry is mutable** - allows streaming text updates
3. **Route by parentToolUseId** - null means primary, otherwise find/create subagent conversation
4. **Track toolUseId → conversationId** - for routing tool results to correct conversation
5. **Update in place** - when tool_result or complete message arrives, update entry fields
6. **Stream deltas in real-time** - text appears as it's generated
7. **Finalize on assistant message** - replace streaming text with complete text, clear streaming flag
8. **Throttle notifications** - batch rapid delta updates to ~60fps for performance
9. **Handle special cases** - Task tool, permissions, compaction, synthetic messages
10. **Display widgets expect paired data** - DiffView, ToolCard need both input and result

---

## Implementation Plan

This section provides a concrete implementation roadmap that builds message handling in phases, ensuring streaming can be added later without redesign.

### Current State

The V2 models (`output_entry.dart`, `chat.dart`) are currently marked `@immutable` with `copyWith` patterns. This conflicts with the mutable approach needed for tool pairing and streaming. The implementation plan addresses this.

### Phase 1: Make OutputEntry Classes Mutable

**Goal**: Enable tool pairing without breaking existing code.

**Changes to `output_entry.dart`**:

```dart
// Remove @immutable annotation from these classes:
// - TextOutputEntry
// - ToolUseOutputEntry

// Add streaming support fields:
class TextOutputEntry extends OutputEntry {
  final String contentType; // 'text', 'thinking', 'error'

  /// The text content. Mutable during streaming.
  String text;

  /// Whether this entry is still receiving streaming deltas.
  /// Default false for non-streaming mode.
  bool isStreaming;

  TextOutputEntry({
    required super.timestamp,
    required this.text,
    required this.contentType,
    this.isStreaming = false,
  });

  void appendDelta(String delta) {
    text += delta;
  }

  // Keep copyWith for backwards compatibility
}

class ToolUseOutputEntry extends OutputEntry {
  final String toolName;
  final String toolUseId;

  /// Mutable - input may stream in via input_json_delta
  final Map<String, dynamic> toolInput;

  /// Mutable - result arrives in separate message
  dynamic result;

  /// Mutable - set when tool_result arrives
  bool isError;

  /// Whether this entry is still receiving streaming input.
  bool isStreaming;

  // ... existing fields ...

  void updateResult(dynamic result, bool isError) {
    this.result = result;
    this.isError = isError;
  }
}
```

**Impact**: Minimal. Existing code using `copyWith` still works. New code can use mutation.

### Phase 2: Create SdkMessageHandler

**Goal**: Central message routing and entry management.

**New file**: `flutter_app_v2/lib/services/sdk_message_handler.dart`

```dart
import 'dart:async';
import '../models/chat.dart';
import '../models/output_entry.dart';

/// Handles SDK messages and routes them to the correct conversation.
///
/// Manages:
/// - Tool use → tool result pairing via _toolUseIdToEntry
/// - Conversation routing via parentToolUseId → _agentIdToConversationId
/// - Agent lifecycle (Task tool spawning)
/// - Future: streaming state tracking
class SdkMessageHandler {
  final ChatState _chat;

  // Tool pairing: toolUseId → entry (for updating with result)
  final Map<String, ToolUseOutputEntry> _toolUseIdToEntry = {};

  // Agent routing: parentToolUseId → conversationId
  final Map<String, String> _agentIdToConversationId = {};

  // Streaming state (for future use - not implemented in Phase 2)
  // final Map<String, Map<int, OutputEntry>> _streamingEntries = {};
  // Timer? _notifyTimer;

  SdkMessageHandler(this._chat);

  /// Handle an incoming SDK message.
  void handleMessage(Map<String, dynamic> rawMessage) {
    final type = rawMessage['type'] as String?;

    switch (type) {
      case 'system':
        _handleSystemMessage(rawMessage);
      case 'assistant':
        _handleAssistantMessage(rawMessage);
      case 'user':
        _handleUserMessage(rawMessage);
      case 'result':
        _handleResultMessage(rawMessage);
      case 'stream_event':
        _handleStreamEvent(rawMessage);
    }
  }

  String _resolveConversationId(String? parentToolUseId) {
    if (parentToolUseId == null) {
      return _chat.data.primaryConversation.id;
    }
    return _agentIdToConversationId[parentToolUseId]
        ?? _chat.data.primaryConversation.id;
  }

  void _handleAssistantMessage(Map<String, dynamic> msg) {
    final parentToolUseId = msg['parent_tool_use_id'] as String?;
    final conversationId = _resolveConversationId(parentToolUseId);
    final content = msg['message']?['content'] as List<dynamic>? ?? [];

    for (final block in content) {
      final blockType = block['type'] as String?;

      switch (blockType) {
        case 'text':
          _chat.addOutputEntry(conversationId, TextOutputEntry(
            timestamp: DateTime.now(),
            text: block['text'] as String? ?? '',
            contentType: 'text',
          ));

        case 'thinking':
          _chat.addOutputEntry(conversationId, TextOutputEntry(
            timestamp: DateTime.now(),
            text: block['thinking'] as String? ?? '',
            contentType: 'thinking',
          ));

        case 'tool_use':
          final toolUseId = block['id'] as String? ?? '';
          final entry = ToolUseOutputEntry(
            timestamp: DateTime.now(),
            toolName: block['name'] as String? ?? '',
            toolUseId: toolUseId,
            toolInput: Map<String, dynamic>.from(block['input'] ?? {}),
            model: msg['message']?['model'] as String?,
          );

          _toolUseIdToEntry[toolUseId] = entry;
          _chat.addOutputEntry(conversationId, entry);

          // Check for Task tool (spawns subagent)
          if (entry.toolName == 'Task') {
            _handleTaskToolSpawn(toolUseId, entry);
          }
      }
    }
  }

  void _handleUserMessage(Map<String, dynamic> msg) {
    final content = msg['message']?['content'] as List<dynamic>? ?? [];

    for (final block in content) {
      if (block['type'] == 'tool_result') {
        final toolUseId = block['tool_use_id'] as String? ?? '';
        final entry = _toolUseIdToEntry[toolUseId];

        if (entry != null) {
          // Get structured result if available
          final toolUseResult = msg['tool_use_result'];
          entry.updateResult(
            toolUseResult ?? block['content'],
            block['is_error'] == true,
          );
          // Entry already in list - just notify
          _chat.notifyListeners();
        }
      }
    }
  }

  void _handleTaskToolSpawn(String toolUseId, ToolUseOutputEntry entry) {
    final input = entry.toolInput;
    final agentType = input['subagent_type'] as String? ?? 'unknown';
    final description = input['description'] as String? ?? 'Agent';

    _chat.addSubagentConversation(toolUseId, agentType, description);

    // Map this toolUseId to the new conversation
    final agent = _chat.activeAgents[toolUseId];
    if (agent != null) {
      _agentIdToConversationId[toolUseId] = agent.conversationId;
    }
  }

  void _handleSystemMessage(Map<String, dynamic> msg) {
    final subtype = msg['subtype'] as String?;

    if (subtype == 'compact_boundary') {
      final summary = msg['compactMetadata']?['summary'] as String? ?? '';
      _chat.addEntry(ContextSummaryEntry(
        timestamp: DateTime.now(),
        summary: summary,
      ));
    }
  }

  void _handleResultMessage(Map<String, dynamic> msg) {
    // Update usage info if available
    // final usage = msg['usage'];
    // final cost = msg['totalCostUsd'];
  }

  void _handleStreamEvent(Map<String, dynamic> msg) {
    // Phase 3: Streaming support
    // For now, ignore stream events - we get complete messages anyway
  }

  void dispose() {
    _toolUseIdToEntry.clear();
    _agentIdToConversationId.clear();
  }
}
```

### Phase 3: Add Streaming Support (Future)

**Goal**: Real-time text as it's generated.

**Backend changes** (already prepared):
```typescript
// session-manager.ts - uncomment these lines:
includePartialMessages: true,
maxThinkingTokens: 16000,
```

**Handler additions**:
```dart
class SdkMessageHandler {
  // Add streaming state
  final Map<String, Map<int, OutputEntry>> _streamingEntries = {};
  Timer? _notifyTimer;

  void _handleStreamEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as Map<String, dynamic>?;
    if (event == null) return;

    final parentToolUseId = msg['parent_tool_use_id'] as String?;
    final conversationId = _resolveConversationId(parentToolUseId);
    final eventType = event['type'] as String?;
    final index = event['index'] as int? ?? 0;

    switch (eventType) {
      case 'message_start':
        _streamingEntries[conversationId] = {};

      case 'content_block_start':
        _handleContentBlockStart(conversationId, index, event);

      case 'content_block_delta':
        _handleContentBlockDelta(conversationId, index, event);

      case 'content_block_stop':
        // Entry remains until finalized by assistant message
        break;
    }
  }

  void _handleContentBlockStart(String conversationId, int index, Map<String, dynamic> event) {
    final block = event['content_block'] as Map<String, dynamic>? ?? {};
    final blockType = block['type'] as String?;

    _streamingEntries[conversationId] ??= {};

    final entry = switch (blockType) {
      'thinking' => TextOutputEntry(
        timestamp: DateTime.now(),
        text: '',
        contentType: 'thinking',
        isStreaming: true,
      ),
      'text' => TextOutputEntry(
        timestamp: DateTime.now(),
        text: '',
        contentType: 'text',
        isStreaming: true,
      ),
      'tool_use' => ToolUseOutputEntry(
        timestamp: DateTime.now(),
        toolName: block['name'] as String? ?? '',
        toolUseId: block['id'] as String? ?? '',
        toolInput: {},
        isStreaming: true,
      ),
      _ => null,
    };

    if (entry != null) {
      _streamingEntries[conversationId]![index] = entry;
      _chat.addOutputEntry(conversationId, entry);

      // Track tool_use for pairing
      if (entry is ToolUseOutputEntry) {
        _toolUseIdToEntry[entry.toolUseId] = entry;
      }
    }
  }

  void _handleContentBlockDelta(String conversationId, int index, Map<String, dynamic> event) {
    final entry = _streamingEntries[conversationId]?[index];
    if (entry == null) return;

    final delta = event['delta'] as Map<String, dynamic>? ?? {};
    final deltaType = delta['type'] as String?;

    switch (deltaType) {
      case 'thinking_delta':
        (entry as TextOutputEntry).appendDelta(delta['thinking'] as String? ?? '');
        _throttledNotify();
      case 'text_delta':
        (entry as TextOutputEntry).appendDelta(delta['text'] as String? ?? '');
        _throttledNotify();
      case 'input_json_delta':
        // Ignore - we get complete input in assistant message
        break;
    }
  }

  void _throttledNotify() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 16), () {
      _chat.notifyListeners();
    });
  }

  // Update _handleAssistantMessage to finalize streaming entries
  void _handleAssistantMessage(Map<String, dynamic> msg) {
    final parentToolUseId = msg['parent_tool_use_id'] as String?;
    final conversationId = _resolveConversationId(parentToolUseId);
    final content = msg['message']?['content'] as List<dynamic>? ?? [];
    final streamingMap = _streamingEntries[conversationId];

    for (var i = 0; i < content.length; i++) {
      final block = content[i];
      final blockType = block['type'] as String?;
      final streamingEntry = streamingMap?[i];

      switch (blockType) {
        case 'text':
          if (streamingEntry is TextOutputEntry && streamingEntry.isStreaming) {
            // Finalize streaming entry
            streamingEntry.text = block['text'] as String? ?? '';
            streamingEntry.isStreaming = false;
          } else {
            // No streaming - add normally
            _chat.addOutputEntry(conversationId, TextOutputEntry(
              timestamp: DateTime.now(),
              text: block['text'] as String? ?? '',
              contentType: 'text',
            ));
          }

        case 'thinking':
          if (streamingEntry is TextOutputEntry &&
              streamingEntry.isStreaming &&
              streamingEntry.contentType == 'thinking') {
            streamingEntry.text = block['thinking'] as String? ?? '';
            streamingEntry.isStreaming = false;
          } else {
            _chat.addOutputEntry(conversationId, TextOutputEntry(
              timestamp: DateTime.now(),
              text: block['thinking'] as String? ?? '',
              contentType: 'thinking',
            ));
          }

        case 'tool_use':
          final toolUseId = block['id'] as String? ?? '';
          if (streamingEntry is ToolUseOutputEntry &&
              streamingEntry.isStreaming &&
              streamingEntry.toolUseId == toolUseId) {
            // Finalize with complete input
            streamingEntry.toolInput.addAll(
              Map<String, dynamic>.from(block['input'] ?? {}),
            );
            streamingEntry.isStreaming = false;
          } else {
            // No streaming - handle normally
            final entry = ToolUseOutputEntry(
              timestamp: DateTime.now(),
              toolName: block['name'] as String? ?? '',
              toolUseId: toolUseId,
              toolInput: Map<String, dynamic>.from(block['input'] ?? {}),
              model: msg['message']?['model'] as String?,
            );
            _toolUseIdToEntry[toolUseId] = entry;
            _chat.addOutputEntry(conversationId, entry);

            if (entry.toolName == 'Task') {
              _handleTaskToolSpawn(toolUseId, entry);
            }
          }
      }
    }

    // Clear streaming state for this conversation
    _streamingEntries.remove(conversationId);
    _chat.notifyListeners();
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _toolUseIdToEntry.clear();
    _agentIdToConversationId.clear();
    _streamingEntries.clear();
  }
}
```

### Phase Summary

| Phase | Scope | Streaming | Dependencies |
|-------|-------|-----------|--------------|
| 1 | Make OutputEntry mutable | Prepared | None |
| 2 | SdkMessageHandler with tool pairing | No | Phase 1 |
| 3 | Add streaming support | Yes | Phase 2, backend config |

### Key Design Decisions

1. **Mutable entries, immutable conversations**: Entries are mutable for pairing/streaming, but the conversation list itself is managed immutably via `copyWith`.

2. **Handler owns pairing state**: The `SdkMessageHandler` keeps `_toolUseIdToEntry` - the ChatState doesn't need to know about pairing.

3. **Streaming is additive**: Phase 2 works without streaming. Phase 3 adds streaming handling without changing Phase 2 code.

4. **Block index tracking**: Streaming uses `(conversationId, blockIndex)` to track multiple concurrent blocks (thinking + text).

5. **Finalize on assistant message**: Streaming entries get their final content from the complete `assistant` message, not from `content_block_stop`.
