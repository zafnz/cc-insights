# SDK Message Types Reference

This document defines the SDK message types that the Dart SDK must parse. These match the TypeScript SDK's message format exactly.

## Message Hierarchy

```dart
sealed class SDKMessage {
  String get type;
  String get sessionId;
  String get uuid;
}

class SDKAssistantMessage extends SDKMessage { ... }
class SDKUserMessage extends SDKMessage { ... }
class SDKResultMessage extends SDKMessage { ... }
class SDKSystemMessage extends SDKMessage { ... }
class SDKStreamEvent extends SDKMessage { ... }
```

---

## SDKSystemMessage

System initialization message sent at session start.

```json
{
  "type": "system",
  "subtype": "init",
  "uuid": "string",
  "session_id": "string",
  "apiKeySource": "user" | "project" | "org" | "temporary",
  "cwd": "string",
  "tools": ["string"],
  "mcp_servers": [
    {
      "name": "string",
      "status": "string"
    }
  ],
  "model": "string",
  "permissionMode": "default" | "acceptEdits" | "bypassPermissions" | "plan",
  "slash_commands": ["string"],
  "output_style": "string"
}
```

### Dart Type

```dart
class SDKSystemMessage extends SDKMessage {
  @override
  final String type = 'system';

  final String subtype; // 'init' or 'compact_boundary'
  final String uuid;
  final String sessionId;

  // For 'init' subtype:
  final String? apiKeySource;
  final String? cwd;
  final List<String>? tools;
  final List<McpServerInfo>? mcpServers;
  final String? model;
  final String? permissionMode;
  final List<String>? slashCommands;
  final String? outputStyle;

  // For 'compact_boundary' subtype:
  final CompactMetadata? compactMetadata;
}

class McpServerInfo {
  final String name;
  final String status;
}

class CompactMetadata {
  final String trigger; // 'manual' or 'auto'
  final int preTokens;
}
```

---

## SDKAssistantMessage

Assistant response containing content blocks.

```json
{
  "type": "assistant",
  "uuid": "string",
  "session_id": "string",
  "message": {
    "role": "assistant",
    "content": [ContentBlock],
    "model": "string",
    "stop_reason": "string" | null,
    "stop_sequence": "string" | null,
    "usage": Usage
  },
  "parent_tool_use_id": "string" | null
}
```

### Dart Type

```dart
class SDKAssistantMessage extends SDKMessage {
  @override
  final String type = 'assistant';

  final String uuid;
  final String sessionId;
  final APIAssistantMessage message;
  final String? parentToolUseId;
}

class APIAssistantMessage {
  final String role; // always 'assistant'
  final List<ContentBlock> content;
  final String? model;
  final String? stopReason;
  final String? stopSequence;
  final Usage? usage;
}
```

---

## SDKUserMessage

User message or tool results.

```json
{
  "type": "user",
  "uuid": "string",
  "session_id": "string",
  "message": {
    "role": "user",
    "content": [ContentBlock]
  },
  "parent_tool_use_id": "string" | null
}
```

### Dart Type

```dart
class SDKUserMessage extends SDKMessage {
  @override
  final String type = 'user';

  final String uuid;
  final String sessionId;
  final APIUserMessage message;
  final String? parentToolUseId;
}

class APIUserMessage {
  final String role; // always 'user'
  final List<ContentBlock> content;
}
```

---

## SDKResultMessage

Turn completion message with usage and cost.

```json
{
  "type": "result",
  "subtype": "success" | "error_max_turns" | "error_during_execution" | "error_max_budget_usd" | "error_max_structured_output_retries",
  "uuid": "string",
  "session_id": "string",
  "duration_ms": number,
  "duration_api_ms": number,
  "is_error": boolean,
  "num_turns": number,
  "total_cost_usd": number,
  "usage": Usage,
  "modelUsage": { [modelName]: ModelUsage },
  "permission_denials": [PermissionDenial],

  // Only on success:
  "result": "string",
  "structured_output": any,

  // Only on error:
  "errors": ["string"]
}
```

### Dart Type

```dart
class SDKResultMessage extends SDKMessage {
  @override
  final String type = 'result';

  final String subtype;
  final String uuid;
  final String sessionId;
  final int durationMs;
  final int durationApiMs;
  final bool isError;
  final int numTurns;
  final double? totalCostUsd;
  final Usage usage;
  final Map<String, ModelUsage> modelUsage;
  final List<PermissionDenial> permissionDenials;

  // Success fields
  final String? result;
  final dynamic structuredOutput;

  // Error fields
  final List<String>? errors;
}

class PermissionDenial {
  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> toolInput;
}
```

---

## SDKStreamEvent

Partial message for streaming (when `includePartialMessages` is true).

```json
{
  "type": "stream_event",
  "uuid": "string",
  "session_id": "string",
  "event": RawMessageStreamEvent,
  "parent_tool_use_id": "string" | null
}
```

The `event` field contains raw Anthropic API stream events:

```json
// message_start
{ "type": "message_start", "message": {...} }

// content_block_start
{ "type": "content_block_start", "index": 0, "content_block": {...} }

// content_block_delta
{ "type": "content_block_delta", "index": 0, "delta": { "type": "text_delta", "text": "..." } }

// content_block_stop
{ "type": "content_block_stop", "index": 0 }

// message_delta
{ "type": "message_delta", "delta": {...}, "usage": {...} }

// message_stop
{ "type": "message_stop" }
```

### Dart Type

```dart
class SDKStreamEvent extends SDKMessage {
  @override
  final String type = 'stream_event';

  final String uuid;
  final String sessionId;
  final Map<String, dynamic> event; // Raw event data
  final String? parentToolUseId;

  // Convenience getters
  String get eventType => event['type'] as String;

  String? get textDelta {
    if (eventType == 'content_block_delta') {
      final delta = event['delta'] as Map<String, dynamic>?;
      if (delta?['type'] == 'text_delta') {
        return delta?['text'] as String?;
      }
    }
    return null;
  }
}
```

---

## Content Blocks

Content blocks appear in assistant and user messages.

```dart
sealed class ContentBlock {
  String get type;
}
```

### TextBlock

```json
{
  "type": "text",
  "text": "string"
}
```

```dart
class TextBlock extends ContentBlock {
  @override
  final String type = 'text';
  final String text;
}
```

### ThinkingBlock

```json
{
  "type": "thinking",
  "thinking": "string",
  "signature": "string"
}
```

```dart
class ThinkingBlock extends ContentBlock {
  @override
  final String type = 'thinking';
  final String thinking;
  final String signature;
}
```

### ToolUseBlock

```json
{
  "type": "tool_use",
  "id": "string",
  "name": "string",
  "input": object
}
```

```dart
class ToolUseBlock extends ContentBlock {
  @override
  final String type = 'tool_use';
  final String id;
  final String name;
  final Map<String, dynamic> input;
}
```

### ToolResultBlock

```json
{
  "type": "tool_result",
  "tool_use_id": "string",
  "content": string | [ContentBlock] | null,
  "is_error": boolean | null
}
```

```dart
class ToolResultBlock extends ContentBlock {
  @override
  final String type = 'tool_result';
  final String toolUseId;
  final dynamic content; // String, List<ContentBlock>, or null
  final bool? isError;
}
```

### ImageBlock

```json
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "string",
    "data": "string"
  }
}
```

```dart
class ImageBlock extends ContentBlock {
  @override
  final String type = 'image';
  final ImageSource source;
}

class ImageSource {
  final String type; // 'base64' or 'url'
  final String? mediaType;
  final String? data;
  final String? url;
}
```

---

## Usage Types

### Usage

Basic token usage.

```json
{
  "input_tokens": number,
  "output_tokens": number,
  "cache_creation_input_tokens": number | null,
  "cache_read_input_tokens": number | null
}
```

```dart
class Usage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;

  int get totalTokens => inputTokens + outputTokens;
}
```

### ModelUsage

Per-model usage breakdown.

```json
{
  "inputTokens": number,
  "outputTokens": number,
  "cacheReadInputTokens": number,
  "cacheCreationInputTokens": number,
  "webSearchRequests": number,
  "costUSD": number,
  "contextWindow": number
}
```

```dart
class ModelUsage {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
  final int webSearchRequests;
  final double costUsd;
  final int contextWindow;
}
```

---

## Parsing Example

```dart
SDKMessage parseSDKMessage(Map<String, dynamic> json) {
  final type = json['type'] as String;

  switch (type) {
    case 'system':
      return SDKSystemMessage.fromJson(json);
    case 'assistant':
      return SDKAssistantMessage.fromJson(json);
    case 'user':
      return SDKUserMessage.fromJson(json);
    case 'result':
      return SDKResultMessage.fromJson(json);
    case 'stream_event':
      return SDKStreamEvent.fromJson(json);
    default:
      throw FormatException('Unknown SDK message type: $type');
  }
}

ContentBlock parseContentBlock(Map<String, dynamic> json) {
  final type = json['type'] as String;

  switch (type) {
    case 'text':
      return TextBlock.fromJson(json);
    case 'thinking':
      return ThinkingBlock.fromJson(json);
    case 'tool_use':
      return ToolUseBlock.fromJson(json);
    case 'tool_result':
      return ToolResultBlock.fromJson(json);
    case 'image':
      return ImageBlock.fromJson(json);
    default:
      throw FormatException('Unknown content block type: $type');
  }
}
```

---

## JSON Serialization

All types should implement `fromJson` factory constructors and `toJson` methods:

```dart
class TextBlock extends ContentBlock {
  @override
  final String type = 'text';
  final String text;

  TextBlock({required this.text});

  factory TextBlock.fromJson(Map<String, dynamic> json) {
    return TextBlock(text: json['text'] as String);
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'text': text,
  };
}
```

Consider using `json_serializable` or `freezed` for code generation:

```dart
@freezed
class TextBlock with _$TextBlock implements ContentBlock {
  const factory TextBlock({
    @Default('text') String type,
    required String text,
  }) = _TextBlock;

  factory TextBlock.fromJson(Map<String, dynamic> json) =>
      _$TextBlockFromJson(json);
}
```
