import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_sdk_core/agent_sdk_core.dart' show BackendProvider, ToolKind;
import 'package:flutter/foundation.dart';

/// Per-model usage breakdown from SDK result message.
///
/// Tracks token usage and cost for a specific model within a conversation.
/// This is typically received in the result message from the SDK and includes
/// the context window size for that model.
@immutable
class ModelUsageInfo {
  /// The full model identifier (e.g., "claude-sonnet-4-5-20250929").
  final String modelName;

  /// Number of input tokens consumed.
  final int inputTokens;

  /// Number of output tokens generated.
  final int outputTokens;

  /// Number of tokens read from cache.
  final int cacheReadTokens;

  /// Number of tokens written to cache.
  final int cacheCreationTokens;

  /// Total cost in USD for this model's usage.
  final double costUsd;

  /// Maximum context window size for this model.
  final int contextWindow;

  /// Creates a new [ModelUsageInfo] instance.
  const ModelUsageInfo({
    required this.modelName,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheCreationTokens,
    required this.costUsd,
    required this.contextWindow,
  });

  /// Total tokens consumed (input + output).
  int get totalTokens => inputTokens + outputTokens;

  /// Creates a short display name from the full model ID.
  ///
  /// Examples:
  /// - "claude-sonnet-4-5-20250929" -> "Sonnet 4.5"
  /// - "claude-haiku-4-5-20251001" -> "Haiku 4.5"
  /// - "claude-opus-4-5-20251101" -> "Opus 4.5"
  /// - "claude-3-5-sonnet-20241022" -> "Sonnet 3.5"
  /// - "unknown-model" -> "unknown-model"
  String get displayName {
    final lower = modelName.toLowerCase();

    // Match patterns like "claude-sonnet-4-5-YYYYMMDD"
    // or "claude-4-5-sonnet-YYYYMMDD"
    final newFormatMatch = RegExp(
      r'claude-(\w+)-(\d+)-(\d+)-\d+',
    ).firstMatch(lower);

    if (newFormatMatch != null) {
      final name = newFormatMatch.group(1)!;
      final major = newFormatMatch.group(2)!;
      final minor = newFormatMatch.group(3)!;
      final capitalizedName = name[0].toUpperCase() + name.substring(1);
      return '$capitalizedName $major.$minor';
    }

    // Match patterns like "claude-3-5-sonnet-YYYYMMDD"
    final oldFormatMatch = RegExp(
      r'claude-(\d+)-(\d+)-(\w+)-\d+',
    ).firstMatch(lower);

    if (oldFormatMatch != null) {
      final major = oldFormatMatch.group(1)!;
      final minor = oldFormatMatch.group(2)!;
      final name = oldFormatMatch.group(3)!;
      final capitalizedName = name[0].toUpperCase() + name.substring(1);
      return '$capitalizedName $major.$minor';
    }

    // Fallback: return as-is
    return modelName;
  }

  /// Serializes this [ModelUsageInfo] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'model_name': modelName,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'cache_read_tokens': cacheReadTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cost_usd': costUsd,
      'context_window': contextWindow,
    };
  }

  /// Deserializes a [ModelUsageInfo] from a JSON map.
  factory ModelUsageInfo.fromJson(Map<String, dynamic> json) {
    return ModelUsageInfo(
      modelName: json['model_name'] as String? ?? '',
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      cacheReadTokens: json['cache_read_tokens'] as int? ?? 0,
      cacheCreationTokens: json['cache_creation_tokens'] as int? ?? 0,
      costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0.0,
      contextWindow: json['context_window'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModelUsageInfo &&
        other.modelName == modelName &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.cacheReadTokens == cacheReadTokens &&
        other.cacheCreationTokens == cacheCreationTokens &&
        other.costUsd == costUsd &&
        other.contextWindow == contextWindow;
  }

  @override
  int get hashCode {
    return Object.hash(
      modelName,
      inputTokens,
      outputTokens,
      cacheReadTokens,
      cacheCreationTokens,
      costUsd,
      contextWindow,
    );
  }

  @override
  String toString() {
    return 'ModelUsageInfo(modelName: $modelName, inputTokens: $inputTokens, '
        'outputTokens: $outputTokens, cacheReadTokens: $cacheReadTokens, '
        'cacheCreationTokens: $cacheCreationTokens, costUsd: $costUsd, '
        'contextWindow: $contextWindow)';
  }
}

/// Token and cost tracking information for a conversation or agent.
///
/// All fields are immutable. Use [copyWith] to create modified copies,
/// or [UsageInfo.zero] for a default instance with all values at zero.
@immutable
class UsageInfo {
  /// Number of input tokens consumed.
  final int inputTokens;

  /// Number of output tokens generated.
  final int outputTokens;

  /// Number of tokens read from cache.
  final int cacheReadTokens;

  /// Number of tokens written to cache.
  final int cacheCreationTokens;

  /// Total cost in USD.
  final double costUsd;

  /// Creates a new [UsageInfo] instance.
  const UsageInfo({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheCreationTokens,
    required this.costUsd,
  });

  /// Creates a [UsageInfo] with all values set to zero.
  const UsageInfo.zero()
    : inputTokens = 0,
      outputTokens = 0,
      cacheReadTokens = 0,
      cacheCreationTokens = 0,
      costUsd = 0.0;

  /// Total tokens consumed (input + output).
  int get totalTokens => inputTokens + outputTokens;

  /// Creates a copy with the given fields replaced.
  UsageInfo copyWith({
    int? inputTokens,
    int? outputTokens,
    int? cacheReadTokens,
    int? cacheCreationTokens,
    double? costUsd,
  }) {
    return UsageInfo(
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      cacheReadTokens: cacheReadTokens ?? this.cacheReadTokens,
      cacheCreationTokens: cacheCreationTokens ?? this.cacheCreationTokens,
      costUsd: costUsd ?? this.costUsd,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UsageInfo &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.cacheReadTokens == cacheReadTokens &&
        other.cacheCreationTokens == cacheCreationTokens &&
        other.costUsd == costUsd;
  }

  @override
  int get hashCode {
    return Object.hash(
      inputTokens,
      outputTokens,
      cacheReadTokens,
      cacheCreationTokens,
      costUsd,
    );
  }

  @override
  String toString() {
    return 'UsageInfo(inputTokens: $inputTokens, outputTokens: $outputTokens, '
        'cacheReadTokens: $cacheReadTokens, '
        'cacheCreationTokens: $cacheCreationTokens, costUsd: $costUsd)';
  }

  /// Serializes this [UsageInfo] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'cache_read_tokens': cacheReadTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cost_usd': costUsd,
    };
  }

  /// Deserializes a [UsageInfo] from a JSON map.
  factory UsageInfo.fromJson(Map<String, dynamic> json) {
    return UsageInfo(
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      cacheReadTokens: json['cache_read_tokens'] as int? ?? 0,
      cacheCreationTokens: json['cache_creation_tokens'] as int? ?? 0,
      costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Display format for user input entries.
///
/// Controls how the user's message text is rendered in the output window.
/// This is frontend-only metadata — it is not sent to the backend.
enum DisplayFormat {
  /// Regular text display (default).
  plain,

  /// Fixed-width / monospace font display.
  fixedWidth,

  /// Rendered as markdown.
  markdown,
}

/// Base class for conversation log entries.
///
/// All output entries are immutable and contain a timestamp indicating
/// when the entry was created. Subclasses represent different types of
/// conversation content (text, tool usage, user input, etc.).
@immutable
abstract class OutputEntry {
  /// When this entry was created.
  final DateTime timestamp;

  /// Creates an [OutputEntry] with the given timestamp.
  const OutputEntry({required this.timestamp});

  /// Serializes this [OutputEntry] to a JSON map.
  ///
  /// Each subclass must implement this method to include a `type` field
  /// for deserialization dispatch.
  Map<String, dynamic> toJson();

  /// Deserializes an [OutputEntry] from a JSON map.
  ///
  /// Dispatches to the appropriate subclass based on the `type` field.
  /// Throws [ArgumentError] if the type is unknown.
  factory OutputEntry.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'user':
        return UserInputEntry.fromJson(json);
      case 'assistant':
        return TextOutputEntry.fromJson(json);
      case 'tool_use':
        return ToolUseOutputEntry.fromJson(json);
      case 'tool_result':
        return ToolResultEntry.fromJson(json);
      case 'context_summary':
        return ContextSummaryEntry.fromJson(json);
      case 'context_cleared':
        return ContextClearedEntry.fromJson(json);
      case 'session_marker':
        return SessionMarkerEntry.fromJson(json);
      case 'auto_compaction':
        return AutoCompactionEntry.fromJson(json);
      case 'unknown_message':
        return UnknownMessageEntry.fromJson(json);
      case 'system_notification':
        return SystemNotificationEntry.fromJson(json);
      default:
        throw ArgumentError('Unknown OutputEntry type: $type');
    }
  }
}

/// A text output entry from the assistant.
///
/// Represents either regular text output or extended thinking content.
/// This class is intentionally mutable to support streaming - text can be
/// appended as deltas arrive, then finalized when the complete message arrives.
class TextOutputEntry extends OutputEntry {
  /// The text content. Mutable during streaming.
  String text;

  /// The type of content: 'text' for regular output, 'thinking' for
  /// extended thinking content.
  final String contentType;

  /// Whether this entry is still receiving streaming deltas.
  /// Default false for non-streaming mode.
  bool isStreaming;

  /// The error type if this message represents an error (e.g., 'unknown').
  /// Null for normal messages.
  final String? errorType;

  /// Raw JSON messages associated with this entry for debugging.
  ///
  /// Populated when messages arrive from the SDK. Used by the JSON viewer.
  /// Uses a nullable backing field with getter to handle hot reload gracefully.
  List<Map<String, dynamic>>? _rawMessages;

  /// Gets the raw messages, returning empty list if not initialized.
  List<Map<String, dynamic>> get rawMessages => _rawMessages ??= [];

  /// Sets the raw messages.
  set rawMessages(List<Map<String, dynamic>> value) => _rawMessages = value;

  /// Creates a [TextOutputEntry].
  TextOutputEntry({
    required super.timestamp,
    required this.text,
    required this.contentType,
    this.isStreaming = false,
    this.errorType,
    List<Map<String, dynamic>>? rawMessages,
  }) : _rawMessages = rawMessages;

  /// Appends a delta to the text content during streaming.
  void appendDelta(String delta) {
    text += delta;
  }

  /// Adds a raw message to this entry.
  void addRawMessage(Map<String, dynamic> message) {
    rawMessages.add(message);
  }

  /// Creates a copy with the given fields replaced.
  TextOutputEntry copyWith({
    DateTime? timestamp,
    String? text,
    String? contentType,
    bool? isStreaming,
    String? errorType,
    List<Map<String, dynamic>>? rawMessages,
  }) {
    return TextOutputEntry(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      contentType: contentType ?? this.contentType,
      isStreaming: isStreaming ?? this.isStreaming,
      errorType: errorType ?? this.errorType,
      rawMessages: rawMessages ?? this.rawMessages,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextOutputEntry &&
        other.timestamp == timestamp &&
        other.text == text &&
        other.contentType == contentType &&
        other.isStreaming == isStreaming &&
        other.errorType == errorType &&
        listEquals(other.rawMessages, rawMessages);
  }

  @override
  int get hashCode => Object.hash(
      timestamp, text, contentType, isStreaming, errorType, rawMessages);

  @override
  String toString() {
    return 'TextOutputEntry(timestamp: $timestamp, text: $text, '
        'contentType: $contentType, isStreaming: $isStreaming, '
        'errorType: $errorType)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'assistant',
      'timestamp': timestamp.toIso8601String(),
      'text': text,
      'content_type': contentType,
      if (errorType != null) 'error_type': errorType,
    };
  }

  /// Deserializes a [TextOutputEntry] from a JSON map.
  static TextOutputEntry fromJson(Map<String, dynamic> json) {
    return TextOutputEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      text: json['text'] as String,
      contentType: json['content_type'] as String? ?? 'text',
      isStreaming: false, // Restored entries are never streaming
      errorType: json['error_type'] as String?,
    );
  }
}

/// A tool use output entry representing a tool invocation and its result.
///
/// This class is intentionally mutable to support:
/// 1. Tool pairing - result arrives in a separate message after tool_use
/// 2. Streaming - input may stream in via input_json_delta events
class ToolUseOutputEntry extends OutputEntry {
  /// The name of the tool being used.
  final String toolName;

  /// Semantic category of the tool.
  final ToolKind toolKind;

  /// Which backend produced this tool call.
  final BackendProvider? provider;

  /// The unique identifier for this tool use.
  final String toolUseId;

  /// The input parameters passed to the tool.
  /// Mutable - input may be updated when streaming completes.
  final Map<String, dynamic> toolInput;

  /// The model that invoked the tool, if known.
  final String? model;

  /// The result returned by the tool, if completed.
  /// Mutable - set when tool_result message arrives.
  dynamic result;

  /// Whether the tool execution resulted in an error.
  /// Mutable - set when tool_result message arrives.
  bool isError;

  /// Whether the tool card is expanded in the UI.
  bool isExpanded;

  /// Whether this entry is still receiving streaming input.
  /// Default false for non-streaming mode.
  bool isStreaming;

  /// Raw JSON messages associated with this entry for debugging.
  ///
  /// Populated when messages arrive from the SDK. Used by the JSON viewer.
  /// For tools, this includes the tool_use and tool_result messages.
  /// Uses a nullable backing field with getter to handle hot reload gracefully.
  List<Map<String, dynamic>>? _rawMessages;

  /// Gets the raw messages, returning empty list if not initialized.
  List<Map<String, dynamic>> get rawMessages => _rawMessages ??= [];

  /// Sets the raw messages.
  set rawMessages(List<Map<String, dynamic>> value) => _rawMessages = value;

  /// Creates a [ToolUseOutputEntry].
  ToolUseOutputEntry({
    required super.timestamp,
    required this.toolName,
    this.toolKind = ToolKind.other,
    this.provider,
    required this.toolUseId,
    required this.toolInput,
    this.model,
    this.result,
    this.isError = false,
    this.isExpanded = false,
    this.isStreaming = false,
    List<Map<String, dynamic>>? rawMessages,
  }) : _rawMessages = rawMessages;

  /// Accumulated partial JSON string for streaming tool input.
  /// Only used during streaming; cleared when finalized.
  String _partialInputJson = '';

  /// Appends a partial JSON delta during streaming.
  void appendInputDelta(String delta) {
    _partialInputJson += delta;
  }

  /// Updates the result when tool_result message arrives.
  void updateResult(dynamic newResult, bool error) {
    result = newResult;
    isError = error;
  }

  /// Adds a raw message to this entry.
  void addRawMessage(Map<String, dynamic> message) {
    rawMessages.add(message);
  }

  /// Creates a copy with the given fields replaced.
  ToolUseOutputEntry copyWith({
    DateTime? timestamp,
    String? toolName,
    ToolKind? toolKind,
    BackendProvider? provider,
    String? toolUseId,
    Map<String, dynamic>? toolInput,
    String? model,
    dynamic result,
    bool? isError,
    bool? isExpanded,
    bool? isStreaming,
    List<Map<String, dynamic>>? rawMessages,
  }) {
    return ToolUseOutputEntry(
      timestamp: timestamp ?? this.timestamp,
      toolName: toolName ?? this.toolName,
      toolKind: toolKind ?? this.toolKind,
      provider: provider ?? this.provider,
      toolUseId: toolUseId ?? this.toolUseId,
      toolInput: toolInput ?? this.toolInput,
      model: model ?? this.model,
      result: result ?? this.result,
      isError: isError ?? this.isError,
      isExpanded: isExpanded ?? this.isExpanded,
      isStreaming: isStreaming ?? this.isStreaming,
      rawMessages: rawMessages ?? this.rawMessages,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ToolUseOutputEntry &&
        other.timestamp == timestamp &&
        other.toolName == toolName &&
        other.toolKind == toolKind &&
        other.provider == provider &&
        other.toolUseId == toolUseId &&
        mapEquals(other.toolInput, toolInput) &&
        other.model == model &&
        other.result == result &&
        other.isError == isError &&
        other.isExpanded == isExpanded &&
        other.isStreaming == isStreaming &&
        listEquals(other.rawMessages, rawMessages);
  }

  @override
  int get hashCode {
    return Object.hash(
      timestamp,
      toolName,
      toolKind,
      provider,
      toolUseId,
      Object.hashAll(toolInput.entries),
      model,
      result,
      isError,
      isExpanded,
      isStreaming,
    );
  }

  @override
  String toString() {
    return 'ToolUseOutputEntry(timestamp: $timestamp, toolName: $toolName, '
        'toolUseId: $toolUseId, isError: $isError, isExpanded: $isExpanded, '
        'isStreaming: $isStreaming)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'tool_use',
      'timestamp': timestamp.toIso8601String(),
      'tool_name': toolName,
      'tool_kind': toolKind.name,
      'tool_use_id': toolUseId,
      'tool_input': toolInput,
      if (model != null) 'model': model,
      if (result != null) 'result': result,
      'is_error': isError,
    };
  }

  /// Deserializes a [ToolUseOutputEntry] from a JSON map.
  static ToolUseOutputEntry fromJson(Map<String, dynamic> json) {
    final toolName = json['tool_name'] as String;
    final toolKindStr = json['tool_kind'] as String?;
    final toolKind = toolKindStr != null
        ? ToolKind.values.asNameMap()[toolKindStr] ?? ToolKind.other
        : ToolKind.fromToolName(toolName);

    return ToolUseOutputEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      toolName: toolName,
      toolKind: toolKind,
      toolUseId: json['tool_use_id'] as String,
      toolInput: Map<String, dynamic>.from(json['tool_input'] as Map),
      model: json['model'] as String?,
      result: json['result'],
      isError: json['is_error'] as bool? ?? false,
      isExpanded: false, // UI state not persisted
      isStreaming: false, // Restored entries are never streaming
    );
  }
}

/// A tool result entry representing the result of a tool execution.
///
/// This is a persistence-only entry used to store tool results in the JSONL
/// file. When loading history, these entries are applied to their corresponding
/// [ToolUseOutputEntry] via [toolUseId] matching.
///
/// This class is not displayed directly in the UI - instead, the result is
/// merged into the [ToolUseOutputEntry] during history loading.
@immutable
class ToolResultEntry extends OutputEntry {
  /// The ID of the tool use this result corresponds to.
  final String toolUseId;

  /// The result data from the tool execution.
  final dynamic result;

  /// Whether the tool execution resulted in an error.
  final bool isError;

  /// Creates a [ToolResultEntry].
  const ToolResultEntry({
    required super.timestamp,
    required this.toolUseId,
    required this.result,
    this.isError = false,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ToolResultEntry &&
        other.timestamp == timestamp &&
        other.toolUseId == toolUseId &&
        other.result == result &&
        other.isError == isError;
  }

  @override
  int get hashCode => Object.hash(timestamp, toolUseId, result, isError);

  @override
  String toString() {
    return 'ToolResultEntry(timestamp: $timestamp, toolUseId: $toolUseId, '
        'isError: $isError)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'tool_result',
      'timestamp': timestamp.toIso8601String(),
      'tool_use_id': toolUseId,
      'result': result,
      'is_error': isError,
    };
  }

  /// Deserializes a [ToolResultEntry] from a JSON map.
  static ToolResultEntry fromJson(Map<String, dynamic> json) {
    return ToolResultEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      toolUseId: json['tool_use_id'] as String,
      result: json['result'],
      isError: json['is_error'] as bool? ?? false,
    );
  }
}

/// Represents an image attached to a user message.
@immutable
class AttachedImage {
  /// The raw image data.
  final Uint8List data;

  /// The MIME type of the image (e.g., "image/png", "image/jpeg").
  final String mediaType;

  /// Creates an [AttachedImage].
  const AttachedImage({
    required this.data,
    required this.mediaType,
  });

  /// Get base64-encoded image data for sending to SDK.
  String get base64 => base64Encode(data);

  /// Serializes this [AttachedImage] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'data': base64,
      'media_type': mediaType,
    };
  }

  /// Deserializes an [AttachedImage] from a JSON map.
  factory AttachedImage.fromJson(Map<String, dynamic> json) {
    return AttachedImage(
      data: base64Decode(json['data'] as String),
      mediaType: json['media_type'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttachedImage &&
        listEquals(other.data, data) &&
        other.mediaType == mediaType;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(data), mediaType);

  @override
  String toString() =>
      'AttachedImage(mediaType: $mediaType, size: ${data.length} bytes)';
}

/// A user input entry representing a message sent by the user.
@immutable
class UserInputEntry extends OutputEntry {
  /// The text of the user's message.
  final String text;

  /// Images attached to the user's message.
  final List<AttachedImage> images;

  /// How this message should be displayed in the output window.
  final DisplayFormat displayFormat;

  /// Creates a [UserInputEntry].
  const UserInputEntry({
    required super.timestamp,
    required this.text,
    this.images = const [],
    this.displayFormat = DisplayFormat.plain,
  });

  /// Creates a copy with the given fields replaced.
  UserInputEntry copyWith({
    DateTime? timestamp,
    String? text,
    List<AttachedImage>? images,
    DisplayFormat? displayFormat,
  }) {
    return UserInputEntry(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      images: images ?? this.images,
      displayFormat: displayFormat ?? this.displayFormat,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserInputEntry &&
        other.timestamp == timestamp &&
        other.text == text &&
        listEquals(other.images, images) &&
        other.displayFormat == displayFormat;
  }

  @override
  int get hashCode =>
      Object.hash(timestamp, text, Object.hashAll(images), displayFormat);

  @override
  String toString() =>
      'UserInputEntry(timestamp: $timestamp, text: $text, '
      'images: ${images.length}, displayFormat: $displayFormat)';

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'user',
      'timestamp': timestamp.toIso8601String(),
      'text': text,
      if (images.isNotEmpty)
        'images': images.map((img) => img.toJson()).toList(),
      if (displayFormat != DisplayFormat.plain)
        'display_format': displayFormat.name,
    };
  }

  /// Deserializes a [UserInputEntry] from a JSON map.
  static UserInputEntry fromJson(Map<String, dynamic> json) {
    final imagesList = json['images'] as List?;
    final formatStr = json['display_format'] as String?;
    final format = formatStr != null
        ? DisplayFormat.values.firstWhere(
            (e) => e.name == formatStr,
            orElse: () => DisplayFormat.plain,
          )
        : DisplayFormat.plain;
    return UserInputEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      text: json['text'] as String,
      images: imagesList
              ?.map((img) =>
                  AttachedImage.fromJson(img as Map<String, dynamic>))
              .toList() ??
          const [],
      displayFormat: format,
    );
  }
}

/// A context summary entry shown after context compaction.
///
/// When the context window is compacted to make room for more conversation,
/// this entry displays a summary of what was removed.
@immutable
class ContextSummaryEntry extends OutputEntry {
  /// The summary of the compacted context.
  final String summary;

  /// Creates a [ContextSummaryEntry].
  const ContextSummaryEntry({required super.timestamp, required this.summary});

  /// Creates a copy with the given fields replaced.
  ContextSummaryEntry copyWith({DateTime? timestamp, String? summary}) {
    return ContextSummaryEntry(
      timestamp: timestamp ?? this.timestamp,
      summary: summary ?? this.summary,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContextSummaryEntry &&
        other.timestamp == timestamp &&
        other.summary == summary;
  }

  @override
  int get hashCode => Object.hash(timestamp, summary);

  @override
  String toString() {
    return 'ContextSummaryEntry(timestamp: $timestamp, summary: $summary)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'context_summary',
      'timestamp': timestamp.toIso8601String(),
      'summary': summary,
    };
  }

  /// Deserializes a [ContextSummaryEntry] from a JSON map.
  static ContextSummaryEntry fromJson(Map<String, dynamic> json) {
    return ContextSummaryEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      summary: json['summary'] as String,
    );
  }
}

/// A context cleared entry shown when the conversation context is reset.
///
/// This is a visual divider indicating that the context has been cleared,
/// typically after a `/clear` command.
@immutable
class ContextClearedEntry extends OutputEntry {
  /// Creates a [ContextClearedEntry].
  const ContextClearedEntry({required super.timestamp});

  /// Creates a copy with the given fields replaced.
  ContextClearedEntry copyWith({DateTime? timestamp}) {
    return ContextClearedEntry(timestamp: timestamp ?? this.timestamp);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContextClearedEntry && other.timestamp == timestamp;
  }

  @override
  int get hashCode => timestamp.hashCode;

  @override
  String toString() => 'ContextClearedEntry(timestamp: $timestamp)';

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'context_cleared',
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Deserializes a [ContextClearedEntry] from a JSON map.
  static ContextClearedEntry fromJson(Map<String, dynamic> json) {
    return ContextClearedEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Type of session marker.
enum SessionMarkerType {
  /// Indicates the session was resumed.
  resumed,

  /// Indicates the app quit while the session was active.
  quit,
}

/// A session marker entry shown when a session is resumed or the app quits.
///
/// This is a visual divider indicating that the session was resumed from
/// a previous state, or that the app was quit while the session was active.
/// The marker persists across app restarts so users can see the session
/// boundaries in the conversation history.
@immutable
class SessionMarkerEntry extends OutputEntry {
  /// The type of session marker.
  final SessionMarkerType markerType;

  /// Creates a [SessionMarkerEntry].
  const SessionMarkerEntry({
    required super.timestamp,
    required this.markerType,
  });

  /// Creates a copy with the given fields replaced.
  SessionMarkerEntry copyWith({
    DateTime? timestamp,
    SessionMarkerType? markerType,
  }) {
    return SessionMarkerEntry(
      timestamp: timestamp ?? this.timestamp,
      markerType: markerType ?? this.markerType,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SessionMarkerEntry &&
        other.timestamp == timestamp &&
        other.markerType == markerType;
  }

  @override
  int get hashCode => Object.hash(timestamp, markerType);

  @override
  String toString() {
    return 'SessionMarkerEntry(timestamp: $timestamp, '
        'markerType: $markerType)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'session_marker',
      'timestamp': timestamp.toIso8601String(),
      'marker_type': markerType.name,
    };
  }

  /// Deserializes a [SessionMarkerEntry] from a JSON map.
  static SessionMarkerEntry fromJson(Map<String, dynamic> json) {
    final markerTypeStr = json['marker_type'] as String;
    final markerType = SessionMarkerType.values.firstWhere(
      (e) => e.name == markerTypeStr,
      orElse: () => SessionMarkerType.resumed,
    );

    return SessionMarkerEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      markerType: markerType,
    );
  }
}

/// A compaction entry shown when context is compacted.
///
/// This is shown when context is compacted either automatically (when context
/// grows too large) or manually via `/compact` command. The [isManual] flag
/// indicates which type of compaction occurred.
@immutable
class AutoCompactionEntry extends OutputEntry {
  /// Optional message describing what was compacted.
  final String? message;

  /// Whether this was a manual compaction (via /compact command).
  ///
  /// When false, this was an automatic compaction triggered by context size.
  final bool isManual;

  /// Creates an [AutoCompactionEntry].
  const AutoCompactionEntry({
    required super.timestamp,
    this.message,
    this.isManual = false,
  });

  /// Creates a copy with the given fields replaced.
  AutoCompactionEntry copyWith({
    DateTime? timestamp,
    String? message,
    bool? isManual,
  }) {
    return AutoCompactionEntry(
      timestamp: timestamp ?? this.timestamp,
      message: message ?? this.message,
      isManual: isManual ?? this.isManual,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AutoCompactionEntry &&
        other.timestamp == timestamp &&
        other.message == message &&
        other.isManual == isManual;
  }

  @override
  int get hashCode => Object.hash(timestamp, message, isManual);

  @override
  String toString() {
    return 'AutoCompactionEntry(timestamp: $timestamp, message: $message, isManual: $isManual)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'auto_compaction',
      'timestamp': timestamp.toIso8601String(),
      if (message != null) 'message': message,
      'isManual': isManual,
    };
  }

  /// Deserializes an [AutoCompactionEntry] from a JSON map.
  static AutoCompactionEntry fromJson(Map<String, dynamic> json) {
    return AutoCompactionEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      message: json['message'] as String?,
      isManual: json['isManual'] as bool? ?? false,
    );
  }
}

/// An unknown message entry shown when an unrecognized SDK message is received.
///
/// This is a fallback entry type used to display SDK messages that don't
/// match any known type. It helps with debugging and ensures no messages
/// are silently dropped.
@immutable
class UnknownMessageEntry extends OutputEntry {
  /// The type of the unknown message.
  final String messageType;

  /// The full message content for debugging.
  final Map<String, dynamic> rawMessage;

  /// Creates an [UnknownMessageEntry].
  const UnknownMessageEntry({
    required super.timestamp,
    required this.messageType,
    required this.rawMessage,
  });

  /// Creates a copy with the given fields replaced.
  UnknownMessageEntry copyWith({
    DateTime? timestamp,
    String? messageType,
    Map<String, dynamic>? rawMessage,
  }) {
    return UnknownMessageEntry(
      timestamp: timestamp ?? this.timestamp,
      messageType: messageType ?? this.messageType,
      rawMessage: rawMessage ?? this.rawMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UnknownMessageEntry &&
        other.timestamp == timestamp &&
        other.messageType == messageType &&
        mapEquals(other.rawMessage, rawMessage);
  }

  @override
  int get hashCode => Object.hash(timestamp, messageType, rawMessage);

  @override
  String toString() {
    return 'UnknownMessageEntry(timestamp: $timestamp, '
        'messageType: $messageType)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'unknown_message',
      'timestamp': timestamp.toIso8601String(),
      'message_type': messageType,
      'raw_message': rawMessage,
    };
  }

  /// Deserializes an [UnknownMessageEntry] from a JSON map.
  static UnknownMessageEntry fromJson(Map<String, dynamic> json) {
    return UnknownMessageEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      messageType: json['message_type'] as String? ?? 'unknown',
      rawMessage: Map<String, dynamic>.from(
        json['raw_message'] as Map? ?? {},
      ),
    );
  }
}

/// A system notification entry for displaying SDK result messages.
///
/// Used to show feedback from the SDK that doesn't come through normal
/// assistant messages, such as "Unknown skill: clear" for unrecognized
/// slash commands.
@immutable
class SystemNotificationEntry extends OutputEntry {
  /// The notification message to display.
  final String message;

  /// Creates a [SystemNotificationEntry].
  const SystemNotificationEntry({
    required super.timestamp,
    required this.message,
  });

  /// Creates a copy with the given fields replaced.
  SystemNotificationEntry copyWith({DateTime? timestamp, String? message}) {
    return SystemNotificationEntry(
      timestamp: timestamp ?? this.timestamp,
      message: message ?? this.message,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SystemNotificationEntry &&
        other.timestamp == timestamp &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(timestamp, message);

  @override
  String toString() {
    return 'SystemNotificationEntry(timestamp: $timestamp, message: $message)';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'system_notification',
      'timestamp': timestamp.toIso8601String(),
      'message': message,
    };
  }

  /// Deserializes a [SystemNotificationEntry] from a JSON map.
  static SystemNotificationEntry fromJson(Map<String, dynamic> json) {
    return SystemNotificationEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      message: json['message'] as String? ?? '',
    );
  }
}
