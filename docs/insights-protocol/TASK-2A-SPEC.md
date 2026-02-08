# Task 2a Implementation Spec: Claude Events Emission

**For:** Sonnet implementation in Task 2b
**Purpose:** Detailed specification for converting Claude CLI JSON messages to InsightsEvent objects
**File to modify:** `claude_dart_sdk/lib/src/cli_session.dart` (626 lines)

---

## Overview

The conversion layer sits in `CliSession._handleMessage()` (line 78). After the existing SDKMessage parsing, we'll add InsightsEvent conversion and emit to `_eventsController`.

### Architecture

```
JSON from CLI → _handleMessage() → SDKMessage (existing)
                                 ↓
                                 _convertToInsightsEvents() → List<InsightsEvent>
                                 ↓
                                 _eventsController.add(event)
```

**Key principle:** One incoming message can produce **multiple** InsightsEvent objects. For example, an `assistant` message with [text, thinking, tool_use] produces 3 events.

---

## Session State Management

### Store control_response Data

The `control_response` received during session initialization contains data needed later for `SessionInitEvent`. Store it as instance state.

**Add to CliSession class (after line 34):**

```dart
Map<String, dynamic>? _controlResponseData;
```

**In the `create()` method, capture it (around line 282):**

```dart
if (type == 'control_response') {
  controlResponseReceived = true;
  _controlResponseData = json['response'] as Map<String, dynamic>?; // STORE THIS
  _t('CliSession', 'Step 3: control_response received');
  SdkLogger.instance.debug('Received control_response');
}
```

**Pass it to constructor (line 329):**

```dart
return CliSession._(
  process: process,
  sessionId: sessionId,
  systemInit: systemInit,
  controlResponseData: _controlResponseData,
);
```

**Update constructor signature (line 24):**

```dart
CliSession._({
  required CliProcess process,
  required this.sessionId,
  required this.systemInit,
  Map<String, dynamic>? controlResponseData,
}) : _process = process,
     _controlResponseData = controlResponseData {
  _setupMessageRouting();
}
```

---

## UUID Generation Strategy

Use `DateTime.now().microsecondsSinceEpoch` combined with a counter for guaranteed uniqueness within a session.

**Add to CliSession class (after the _controlResponseData field):**

```dart
int _eventIdCounter = 0;

String _nextEventId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  _eventIdCounter++;
  return 'evt-$now-$_eventIdCounter';
}
```

---

## Main Conversion Method

**Add after the `_handleMessage()` method (around line 168):**

```dart
/// Convert a CLI JSON message into one or more InsightsEvent objects.
///
/// Returns a list because some messages (e.g., assistant with multiple content
/// blocks) produce multiple events.
List<InsightsEvent> _convertToInsightsEvents(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  final subtype = json['subtype'] as String?;

  switch (type) {
    case 'system':
      if (subtype == 'init') {
        return [_convertSystemInit(json)];
      } else if (subtype == 'status') {
        return [_convertSystemStatus(json)];
      } else if (subtype == 'compact_boundary') {
        return [_convertCompactBoundary(json)];
      } else if (subtype == 'context_cleared') {
        return [_convertContextCleared(json)];
      }
      return [];

    case 'assistant':
      return _convertAssistant(json);

    case 'user':
      return _convertUser(json);

    case 'result':
      return _convertResult(json);

    case 'control_request':
      return _convertControlRequest(json);

    case 'stream_event':
      return _convertStreamEvent(json);

    default:
      return [];
  }
}
```

---

## Per-Message Conversion Methods

### 1. _convertSystemInit

Merges data from both `system/init` message and the stored `control_response`.

**Signature:**

```dart
SessionInitEvent _convertSystemInit(Map<String, dynamic> json)
```

**Implementation:**

```dart
SessionInitEvent _convertSystemInit(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final model = json['model'] as String?;
  final cwd = json['cwd'] as String?;
  final tools = (json['tools'] as List?)?.cast<String>();
  final permissionMode = json['permissionMode'] as String?;

  // Parse MCP servers
  List<McpServerStatus>? mcpServers;
  final mcpList = json['mcp_servers'] as List?;
  if (mcpList != null) {
    mcpServers = mcpList
        .whereType<Map<String, dynamic>>()
        .map((m) => McpServerStatus.fromJson(m))
        .toList();
  }

  // Parse slash commands (simple string list from system/init)
  List<SlashCommand>? slashCommands;
  final slashList = json['slash_commands'] as List?;
  if (slashList != null) {
    slashCommands = slashList
        .whereType<String>()
        .map((name) => SlashCommand(
              name: name,
              description: '',
              argumentHint: '',
            ))
        .toList();
  }

  // From control_response (if available)
  List<ModelInfo>? availableModels;
  AccountInfo? account;
  if (_controlResponseData != null) {
    final models = _controlResponseData!['models'] as List?;
    if (models != null) {
      availableModels = models
          .whereType<Map<String, dynamic>>()
          .map((m) => ModelInfo.fromJson(m))
          .toList();
    }

    final accountJson = _controlResponseData!['account'] as Map<String, dynamic>?;
    if (accountJson != null) {
      account = AccountInfo.fromJson(accountJson);
    }

    // Richer slash commands from control_response
    final commands = _controlResponseData!['commands'] as List?;
    if (commands != null) {
      slashCommands = commands
          .whereType<Map<String, dynamic>>()
          .map((c) => SlashCommand.fromJson(c))
          .toList();
    }
  }

  // Extensions for Claude-specific fields
  final extensions = <String, dynamic>{};
  final apiKeySource = json['apiKeySource'] as String?;
  if (apiKeySource != null) {
    extensions['claude.apiKeySource'] = apiKeySource;
  }
  final outputStyle = json['output_style'] as String?;
  if (outputStyle != null) {
    extensions['claude.outputStyle'] = outputStyle;
  }

  return SessionInitEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    extensions: extensions.isNotEmpty ? extensions : null,
    sessionId: sessionId,
    model: model,
    cwd: cwd,
    availableTools: tools,
    mcpServers: mcpServers,
    permissionMode: permissionMode,
    account: account,
    slashCommands: slashCommands,
    availableModels: availableModels,
  );
}
```

---

### 2. _convertSystemStatus

**Signature:**

```dart
SessionStatusEvent _convertSystemStatus(Map<String, dynamic> json)
```

**Implementation:**

```dart
SessionStatusEvent _convertSystemStatus(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final statusStr = json['status'] as String?;

  SessionStatus status;
  switch (statusStr) {
    case 'compacting':
      status = SessionStatus.compacting;
    case 'resuming':
      status = SessionStatus.resuming;
    case 'interrupted':
      status = SessionStatus.interrupted;
    case 'ended':
      status = SessionStatus.ended;
    case 'error':
      status = SessionStatus.error;
    default:
      status = SessionStatus.error;
  }

  return SessionStatusEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    sessionId: sessionId,
    status: status,
    message: json['message'] as String?,
  );
}
```

---

### 3. _convertCompactBoundary

**Signature:**

```dart
ContextCompactionEvent _convertCompactBoundary(Map<String, dynamic> json)
```

**Implementation:**

```dart
ContextCompactionEvent _convertCompactBoundary(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final metadata = json['compact_metadata'] as Map<String, dynamic>?;

  final triggerStr = metadata?['trigger'] as String?;
  CompactionTrigger trigger;
  switch (triggerStr) {
    case 'auto':
      trigger = CompactionTrigger.auto;
    case 'manual':
      trigger = CompactionTrigger.manual;
    default:
      trigger = CompactionTrigger.auto;
  }

  final preTokens = metadata?['pre_tokens'] as int?;

  return ContextCompactionEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    sessionId: sessionId,
    trigger: trigger,
    preTokens: preTokens,
  );
}
```

---

### 4. _convertContextCleared

**Signature:**

```dart
ContextCompactionEvent _convertContextCleared(Map<String, dynamic> json)
```

**Implementation:**

```dart
ContextCompactionEvent _convertContextCleared(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;

  return ContextCompactionEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    sessionId: sessionId,
    trigger: CompactionTrigger.cleared,
  );
}
```

---

### 5. _convertAssistant

**Returns multiple events** — one per content block.

**Signature:**

```dart
List<InsightsEvent> _convertAssistant(Map<String, dynamic> json)
```

**Implementation:**

```dart
List<InsightsEvent> _convertAssistant(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final parentToolUseId = json['parent_tool_use_id'] as String?;
  final message = json['message'] as Map<String, dynamic>?;
  final model = message?['model'] as String?;
  final content = message?['content'] as List?;

  if (content == null || content.isEmpty) return [];

  final events = <InsightsEvent>[];

  for (final block in content) {
    if (block is! Map<String, dynamic>) continue;

    final blockType = block['type'] as String?;

    switch (blockType) {
      case 'text':
        final text = block['text'] as String? ?? '';
        events.add(TextEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          sessionId: sessionId,
          text: text,
          kind: TextKind.text,
          parentCallId: parentToolUseId,
          model: model,
        ));

      case 'thinking':
        final thinking = block['thinking'] as String? ?? '';
        events.add(TextEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          sessionId: sessionId,
          text: thinking,
          kind: TextKind.thinking,
          parentCallId: parentToolUseId,
          model: model,
        ));

      case 'tool_use':
        final toolUseId = block['id'] as String?;
        final toolName = block['name'] as String? ?? '';
        final input = block['input'] as Map<String, dynamic>? ?? {};

        // Extract locations from common input fields
        final locations = _extractLocations(toolName, input);

        events.add(ToolInvocationEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          callId: toolUseId ?? _nextEventId(),
          parentCallId: parentToolUseId,
          sessionId: sessionId,
          kind: ToolKind.fromToolName(toolName),
          toolName: toolName,
          input: input,
          locations: locations,
          model: model,
        ));

        // Special case: Task tool → also emit SubagentSpawnEvent
        if (toolName == 'Task') {
          final agentType = input['subagent_type'] as String? ?? input['name'] as String?;
          final description = input['description'] as String? ??
              input['prompt'] as String? ??
              input['task'] as String?;
          final resume = input['resume'] as String?;

          events.add(SubagentSpawnEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            sessionId: sessionId,
            callId: toolUseId ?? _nextEventId(),
            agentType: agentType,
            description: description,
            isResume: resume != null,
            resumeAgentId: resume,
          ));
        }
    }
  }

  return events;
}
```

**Helper method for location extraction:**

```dart
/// Extract file/directory locations from tool input.
List<String>? _extractLocations(String toolName, Map<String, dynamic> input) {
  final locations = <String>[];

  // Common location fields
  final filePath = input['file_path'] as String?;
  if (filePath != null) locations.add(filePath);

  final path = input['path'] as String?;
  if (path != null) locations.add(path);

  final notebookPath = input['notebook_path'] as String?;
  if (notebookPath != null) locations.add(notebookPath);

  final cwd = input['cwd'] as String?;
  if (cwd != null) locations.add(cwd);

  final pattern = input['pattern'] as String?;
  if (pattern != null && toolName == 'Glob') locations.add(pattern);

  return locations.isNotEmpty ? locations : null;
}
```

---

### 6. _convertUser

**Signature:**

```dart
List<InsightsEvent> _convertUser(Map<String, dynamic> json)
```

**Implementation:**

```dart
List<InsightsEvent> _convertUser(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final isSynthetic = json['isSynthetic'] as bool? ?? false;
  final isReplay = json['isReplay'] as bool? ?? false;
  final message = json['message'] as Map<String, dynamic>?;
  final content = message?['content'] as List?;

  if (content == null || content.isEmpty) return [];

  final events = <InsightsEvent>[];

  for (final block in content) {
    if (block is! Map<String, dynamic>) continue;

    final blockType = block['type'] as String?;

    switch (blockType) {
      case 'tool_result':
        final toolUseId = block['tool_use_id'] as String?;
        final isError = block['is_error'] as bool? ?? false;

        // Prefer structured tool_use_result over content field
        final output = json['tool_use_result'] ?? block['content'];

        events.add(ToolCompletionEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          callId: toolUseId ?? _nextEventId(),
          sessionId: sessionId,
          status: isError ? ToolCallStatus.failed : ToolCallStatus.completed,
          output: output,
          isError: isError,
        ));

      case 'text':
        // Synthetic user messages (context summaries after compaction)
        if (isSynthetic) {
          final text = block['text'] as String? ?? '';
          final extensions = <String, dynamic>{'claude.isSynthetic': true};

          events.add(TextEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            extensions: extensions,
            sessionId: sessionId,
            text: text,
            kind: TextKind.text,
          ));
        }
        // Replay messages
        else if (isReplay) {
          final text = block['text'] as String? ?? '';
          final extensions = <String, dynamic>{'claude.isReplay': true};

          events.add(TextEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            extensions: extensions,
            sessionId: sessionId,
            text: text,
            kind: TextKind.text,
          ));
        }
    }
  }

  return events;
}
```

---

### 7. _convertResult

**Signature:**

```dart
List<InsightsEvent> _convertResult(Map<String, dynamic> json)
```

**Implementation:**

```dart
List<InsightsEvent> _convertResult(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final subtype = json['subtype'] as String?;
  final isError = json['is_error'] as bool? ?? false;
  final durationMs = json['duration_ms'] as int?;
  final durationApiMs = json['duration_api_ms'] as int?;
  final numTurns = json['num_turns'] as int?;
  final totalCostUsd = (json['total_cost_usd'] as num?)?.toDouble();
  final result = json['result'] as String?;
  final errors = (json['errors'] as List?)?.cast<String>();

  // Parse usage
  TokenUsage? usage;
  final usageJson = json['usage'] as Map<String, dynamic>?;
  if (usageJson != null) {
    usage = TokenUsage(
      inputTokens: usageJson['input_tokens'] as int? ?? 0,
      outputTokens: usageJson['output_tokens'] as int? ?? 0,
      cacheReadTokens: usageJson['cache_read_input_tokens'] as int?,
      cacheCreationTokens: usageJson['cache_creation_input_tokens'] as int?,
    );
  }

  // Parse per-model usage
  Map<String, ModelTokenUsage>? modelUsage;
  final modelUsageJson = json['modelUsage'] as Map<String, dynamic>?;
  if (modelUsageJson != null) {
    modelUsage = {};
    for (final entry in modelUsageJson.entries) {
      final modelJson = entry.value as Map<String, dynamic>;
      modelUsage[entry.key] = ModelTokenUsage(
        inputTokens: modelJson['inputTokens'] as int? ?? 0,
        outputTokens: modelJson['outputTokens'] as int? ?? 0,
        cacheReadTokens: modelJson['cacheReadInputTokens'] as int?,
        cacheCreationTokens: modelJson['cacheCreationInputTokens'] as int?,
        costUsd: (modelJson['costUsd'] as num?)?.toDouble(),
        contextWindow: modelJson['contextWindow'] as int?,
        webSearchRequests: modelJson['webSearchRequests'] as int?,
      );
    }
  }

  // Parse permission denials
  List<PermissionDenial>? permissionDenials;
  final denialsJson = json['permission_denials'] as List?;
  if (denialsJson != null) {
    permissionDenials = denialsJson
        .whereType<Map<String, dynamic>>()
        .map((d) => PermissionDenial.fromJson(d))
        .toList();
  }

  final event = TurnCompleteEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    sessionId: sessionId,
    isError: isError,
    subtype: subtype,
    errors: errors,
    result: result,
    costUsd: totalCostUsd,
    durationMs: durationMs,
    durationApiMs: durationApiMs,
    numTurns: numTurns,
    usage: usage,
    modelUsage: modelUsage,
    permissionDenials: permissionDenials,
  );

  return [event];
}
```

---

### 8. _convertControlRequest

**Signature:**

```dart
List<InsightsEvent> _convertControlRequest(Map<String, dynamic> json)
```

**Implementation:**

```dart
List<InsightsEvent> _convertControlRequest(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final requestId = json['request_id'] as String?;
  final request = json['request'] as Map<String, dynamic>?;

  if (request == null) return [];

  final subtype = request['subtype'] as String?;

  // Only convert can_use_tool requests
  if (subtype != 'can_use_tool') return [];

  final toolName = request['tool_name'] as String? ?? '';
  final toolInput = request['input'] as Map<String, dynamic>? ?? {};
  final toolUseId = request['tool_use_id'] as String?;
  final blockedPath = request['blocked_path'] as String?;

  // Parse permission suggestions
  List<PermissionSuggestionData>? suggestions;
  final suggestionsJson = request['permission_suggestions'] as List?;
  if (suggestionsJson != null) {
    suggestions = suggestionsJson
        .whereType<Map<String, dynamic>>()
        .map((s) => PermissionSuggestionData(
              type: s['type'] as String? ?? '',
              toolName: s['tool_name'] as String?,
              directory: s['directory'] as String?,
              mode: s['mode'] as String?,
              description: s['description'] as String? ?? '',
            ))
        .toList();
  }

  return [
    PermissionRequestEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      sessionId: sessionId,
      requestId: requestId ?? _nextEventId(),
      toolName: toolName,
      toolKind: ToolKind.fromToolName(toolName),
      toolInput: toolInput,
      toolUseId: toolUseId,
      blockedPath: blockedPath,
      suggestions: suggestions,
    ),
  ];
}
```

---

### 9. _convertStreamEvent

**Signature:**

```dart
List<InsightsEvent> _convertStreamEvent(Map<String, dynamic> json)
```

**Implementation:**

```dart
List<InsightsEvent> _convertStreamEvent(Map<String, dynamic> json) {
  final sessionId = json['session_id'] as String? ?? this.sessionId;
  final parentToolUseId = json['parent_tool_use_id'] as String?;
  final event = json['event'] as Map<String, dynamic>?;

  if (event == null) return [];

  final eventType = event['type'] as String?;

  StreamDeltaKind? kind;
  String? textDelta;
  String? jsonDelta;
  int? blockIndex;
  String? callId;

  switch (eventType) {
    case 'message_start':
      kind = StreamDeltaKind.messageStart;

    case 'content_block_start':
      kind = StreamDeltaKind.blockStart;
      blockIndex = event['index'] as int?;

      final contentBlock = event['content_block'] as Map<String, dynamic>?;
      if (contentBlock != null) {
        final blockType = contentBlock['type'] as String?;
        if (blockType == 'tool_use') {
          callId = contentBlock['id'] as String?;
        }
      }

    case 'content_block_delta':
      blockIndex = event['index'] as int?;
      final delta = event['delta'] as Map<String, dynamic>?;

      if (delta != null) {
        final deltaType = delta['type'] as String?;

        switch (deltaType) {
          case 'text_delta':
            kind = StreamDeltaKind.text;
            textDelta = delta['text'] as String?;

          case 'thinking_delta':
            kind = StreamDeltaKind.thinking;
            textDelta = delta['thinking'] as String?;

          case 'input_json_delta':
            kind = StreamDeltaKind.toolInput;
            jsonDelta = delta['partial_json'] as String?;
            callId = event['tool_use_id'] as String?;
        }
      }

    case 'content_block_stop':
      kind = StreamDeltaKind.blockStop;
      blockIndex = event['index'] as int?;

    case 'message_stop':
      kind = StreamDeltaKind.messageStop;

    case 'message_delta':
      kind = StreamDeltaKind.messageStop;
      final stopReason = event['delta']?['stop_reason'] as String?;
      if (stopReason != null) {
        // Store in extensions
      }
  }

  if (kind == null) return [];

  return [
    StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      sessionId: sessionId,
      parentCallId: parentToolUseId,
      kind: kind,
      textDelta: textDelta,
      jsonDelta: jsonDelta,
      blockIndex: blockIndex,
      callId: callId,
    ),
  ];
}
```

---

## Integration into _handleMessage

**Modify the existing `_handleMessage()` method (line 78). After the switch statement, add:**

```dart
void _handleMessage(Map<String, dynamic> json) {
  // ... existing code (lines 79-167) ...

  // NEW: Convert to InsightsEvents and emit
  try {
    final events = _convertToInsightsEvents(json);
    for (final event in events) {
      _eventsController.add(event);
    }
  } catch (e, stack) {
    SdkLogger.instance.error(
      'Failed to convert message to InsightsEvent',
      sessionId: sessionId,
      data: {'error': e.toString(), 'json': json, 'stack': stack.toString()},
    );
  }
}
```

---

## Required Imports

Add to the top of `cli_session.dart` (after existing imports):

```dart
import 'types/insights_events.dart';
import 'types/tool_kind.dart';
import 'types/backend_provider.dart';
import 'types/usage.dart';
```

---

## Summary of Changes

| Location | Change |
|----------|--------|
| Instance fields | Add `_controlResponseData`, `_eventIdCounter` |
| Constructor | Accept and store `controlResponseData` |
| `create()` method | Capture `control_response` data |
| After `_handleMessage()` | Add `_convertToInsightsEvents()` and 9 converter methods |
| Helper method | Add `_extractLocations()` |
| Helper method | Add `_nextEventId()` |
| End of `_handleMessage()` | Add event conversion and emission |
| Imports | Add 4 new imports |

**Total new code:** ~500 lines
**Modified existing code:** ~10 lines

---

## Testing Strategy (for Task 2c)

Create tests that:
1. Feed known JSON (from `03-claude-mapping.md`) into a `CliSession`
2. Listen to the `events` stream
3. Verify correct event types and field values

Example:
```dart
test('converts assistant message with text', () async {
  final session = await CliSession.create(...);

  final events = <InsightsEvent>[];
  session.events.listen(events.add);

  // Inject mock JSON via process
  // ...

  expect(events.whereType<TextEvent>().length, 1);
  final textEvent = events.whereType<TextEvent>().first;
  expect(textEvent.text, 'Here is the fix...');
  expect(textEvent.kind, TextKind.text);
});
```

---

## Edge Cases & Error Handling

1. **Missing fields:** All field access uses null-aware operators or defaults
2. **Malformed JSON:** Wrapped in try-catch, logs error but doesn't crash
3. **Empty content arrays:** Returns empty list, no error
4. **Unknown enum values:** Falls back to sensible defaults
5. **Multiple events from one message:** All added to list, emitted sequentially

---

## Performance Considerations

- Event ID generation is O(1) (microseconds + counter)
- Location extraction is O(n) where n = number of input keys (typically < 10)
- Per-message overhead: ~1-5 event objects (small allocations)
- No blocking operations, all synchronous transforms

---

## End of Specification

This spec provides everything Sonnet needs to implement Task 2b. All field mappings, method signatures, and control flow are explicitly defined.
