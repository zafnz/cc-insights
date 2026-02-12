import 'package:meta/meta.dart';

import 'backend_provider.dart';
import 'content_blocks.dart';
import 'tool_kind.dart';
import 'usage.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// Represents a permission denial in a turn result.
///
/// Records when the agent requested permission to use a tool but the user
/// denied that permission.
class PermissionDenial {
  const PermissionDenial({
    required this.toolName,
    required this.toolUseId,
    required this.toolInput,
  });

  factory PermissionDenial.fromJson(Map<String, dynamic> json) {
    return PermissionDenial(
      toolName: json['tool_name'] as String? ?? '',
      toolUseId: json['tool_use_id'] as String? ?? '',
      toolInput: json['tool_input'] as Map<String, dynamic>? ?? {},
    );
  }

  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> toolInput;

  Map<String, dynamic> toJson() => {
        'tool_name': toolName,
        'tool_use_id': toolUseId,
        'tool_input': toolInput,
      };
}

// ---------------------------------------------------------------------------
// Supporting enums
// ---------------------------------------------------------------------------

/// Session status changes during a session.
enum SessionStatus {
  compacting,
  resuming,
  interrupted,
  ended,
  error,
}

/// The kind of text content in a [TextEvent].
enum TextKind {
  text,
  thinking,
  plan,
  error,
}

/// Completion status of a tool call.
enum ToolCallStatus {
  completed,
  failed,
  cancelled,
}

/// What triggered a context compaction.
enum CompactionTrigger {
  auto,
  manual,
  cleared,
}

/// The kind of streaming delta.
enum StreamDeltaKind {
  text,
  thinking,
  toolInput,
  messageStart,
  messageStop,
  blockStart,
  blockStop,
}

// ---------------------------------------------------------------------------
// Supporting data classes
// ---------------------------------------------------------------------------

/// Aggregate token usage for a turn.
@immutable
class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheReadTokens;
  final int? cacheCreationTokens;

  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadTokens,
    this.cacheCreationTokens,
  });

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      cacheReadTokens: json['cacheReadTokens'] as int?,
      cacheCreationTokens: json['cacheCreationTokens'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        if (cacheReadTokens != null) 'cacheReadTokens': cacheReadTokens,
        if (cacheCreationTokens != null)
          'cacheCreationTokens': cacheCreationTokens,
      };
}

/// Per-model usage breakdown with cost and context window info.
@immutable
class ModelTokenUsage extends TokenUsage {
  final double? costUsd;
  final int? contextWindow;
  final int? webSearchRequests;

  const ModelTokenUsage({
    required super.inputTokens,
    required super.outputTokens,
    super.cacheReadTokens,
    super.cacheCreationTokens,
    this.costUsd,
    this.contextWindow,
    this.webSearchRequests,
  });

  factory ModelTokenUsage.fromJson(Map<String, dynamic> json) {
    return ModelTokenUsage(
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      cacheReadTokens: json['cacheReadTokens'] as int?,
      cacheCreationTokens: json['cacheCreationTokens'] as int?,
      costUsd: (json['costUsd'] as num?)?.toDouble(),
      contextWindow: json['contextWindow'] as int?,
      webSearchRequests: json['webSearchRequests'] as int?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        if (cacheReadTokens != null) 'cacheReadTokens': cacheReadTokens,
        if (cacheCreationTokens != null)
          'cacheCreationTokens': cacheCreationTokens,
        if (costUsd != null) 'costUsd': costUsd,
        if (contextWindow != null) 'contextWindow': contextWindow,
        if (webSearchRequests != null) 'webSearchRequests': webSearchRequests,
      };
}

/// Image data attached to a user input event.
@immutable
class ImageData {
  final String mediaType;
  final String data;

  const ImageData({
    required this.mediaType,
    required this.data,
  });

  factory ImageData.fromJson(Map<String, dynamic> json) {
    return ImageData(
      mediaType: json['mediaType'] as String? ?? '',
      data: json['data'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'mediaType': mediaType,
        'data': data,
      };
}

// ---------------------------------------------------------------------------
// InsightsEvent — sealed base class
// ---------------------------------------------------------------------------

/// Base class for all insights protocol events.
///
/// All events carry an [id], [timestamp], [provider], and optional
/// [raw] / [extensions] maps for debugging and backend-specific data.
sealed class InsightsEvent {
  /// Unique event ID (UUID or backend-provided).
  final String id;

  /// When this event was created.
  final DateTime timestamp;

  /// Which backend produced this event.
  final BackendProvider provider;

  /// Original wire-format data for debugging.
  final Map<String, dynamic>? raw;

  /// Provider-specific extensions that don't fit the common model.
  final Map<String, dynamic>? extensions;

  const InsightsEvent({
    required this.id,
    required this.timestamp,
    required this.provider,
    this.raw,
    this.extensions,
  });

  /// Serialize this event to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserialize an event from a JSON map, dispatching on `json['event']`.
  static InsightsEvent fromJson(Map<String, dynamic> json) {
    final event = json['event'] as String;
    return switch (event) {
      'session_init' => SessionInitEvent.fromJson(json),
      'session_status' => SessionStatusEvent.fromJson(json),
      'text' => TextEvent.fromJson(json),
      'user_input' => UserInputEvent.fromJson(json),
      'tool_invocation' => ToolInvocationEvent.fromJson(json),
      'tool_completion' => ToolCompletionEvent.fromJson(json),
      'subagent_spawn' => SubagentSpawnEvent.fromJson(json),
      'subagent_complete' => SubagentCompleteEvent.fromJson(json),
      'turn_complete' => TurnCompleteEvent.fromJson(json),
      'context_compaction' => ContextCompactionEvent.fromJson(json),
      'permission_request' => PermissionRequestEvent.fromJson(json),
      'config_options' => ConfigOptionsEvent.fromJson(json),
      'available_commands' => AvailableCommandsEvent.fromJson(json),
      'session_mode' => SessionModeEvent.fromJson(json),
      'stream_delta' => StreamDeltaEvent.fromJson(json),
      'usage_update' => UsageUpdateEvent.fromJson(json),
      'rate_limit_update' => RateLimitUpdateEvent.fromJson(json),
      _ => throw ArgumentError('Unknown event type: $event'),
    };
  }

  /// Common base fields serialized by every event.
  @protected
  Map<String, dynamic> baseJson(String eventType) => {
        'event': eventType,
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'provider': provider.name,
        if (raw != null) 'raw': raw,
        if (extensions != null) 'extensions': extensions,
      };

  /// Parse common base fields from JSON.
  static ({
    String id,
    DateTime timestamp,
    BackendProvider provider,
    Map<String, dynamic>? raw,
    Map<String, dynamic>? extensions,
  }) parseBase(Map<String, dynamic> json) {
    return (
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      provider: BackendProvider.values.byName(json['provider'] as String),
      raw: json['raw'] as Map<String, dynamic>?,
      extensions: json['extensions'] as Map<String, dynamic>?,
    );
  }
}

// ---------------------------------------------------------------------------
// Session lifecycle events
// ---------------------------------------------------------------------------

/// Emitted once when the session is established and ready for prompts.
class SessionInitEvent extends InsightsEvent {
  final String sessionId;
  final String? model;
  final String? reasoningEffort;
  final String? cwd;
  final List<String>? availableTools;
  final List<McpServerStatus>? mcpServers;
  final String? permissionMode;
  final AccountInfo? account;
  final List<SlashCommand>? slashCommands;
  final List<ModelInfo>? availableModels;

  const SessionInitEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    this.model,
    this.reasoningEffort,
    this.cwd,
    this.availableTools,
    this.mcpServers,
    this.permissionMode,
    this.account,
    this.slashCommands,
    this.availableModels,
  });

  factory SessionInitEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return SessionInitEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      model: json['model'] as String?,
      reasoningEffort: json['reasoningEffort'] as String?,
      cwd: json['cwd'] as String?,
      availableTools: (json['availableTools'] as List<dynamic>?)
          ?.cast<String>(),
      mcpServers: (json['mcpServers'] as List<dynamic>?)
          ?.map((e) => McpServerStatus.fromJson(e as Map<String, dynamic>))
          .toList(),
      permissionMode: json['permissionMode'] as String?,
      account: json['account'] != null
          ? AccountInfo.fromJson(json['account'] as Map<String, dynamic>)
          : null,
      slashCommands: (json['slashCommands'] as List<dynamic>?)
          ?.map((e) => SlashCommand.fromJson(e as Map<String, dynamic>))
          .toList(),
      availableModels: (json['availableModels'] as List<dynamic>?)
          ?.map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('session_init'),
        'sessionId': sessionId,
        if (model != null) 'model': model,
        if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
        if (cwd != null) 'cwd': cwd,
        if (availableTools != null) 'availableTools': availableTools,
        if (mcpServers != null)
          'mcpServers': mcpServers!.map((s) => s.toJson()).toList(),
        if (permissionMode != null) 'permissionMode': permissionMode,
        if (account != null) 'account': account!.toJson(),
        if (slashCommands != null)
          'slashCommands': slashCommands!.map((c) => c.toJson()).toList(),
        if (availableModels != null)
          'availableModels': availableModels!.map((m) => m.toJson()).toList(),
      };
}

/// Session configuration options (ACP-specific).
class ConfigOptionsEvent extends InsightsEvent {
  final String sessionId;
  final List<Map<String, dynamic>> configOptions;

  const ConfigOptionsEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.configOptions,
  });

  factory ConfigOptionsEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return ConfigOptionsEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      configOptions:
          (json['configOptions'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('config_options'),
        'sessionId': sessionId,
        'configOptions': configOptions,
      };
}

/// Available commands update (ACP-specific).
class AvailableCommandsEvent extends InsightsEvent {
  final String sessionId;
  final List<Map<String, dynamic>> availableCommands;

  const AvailableCommandsEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.availableCommands,
  });

  factory AvailableCommandsEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return AvailableCommandsEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      availableCommands:
          (json['availableCommands'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('available_commands'),
        'sessionId': sessionId,
        'availableCommands': availableCommands,
      };
}

/// Session mode update (ACP-specific).
class SessionModeEvent extends InsightsEvent {
  final String sessionId;
  final String currentModeId;
  final List<Map<String, dynamic>> availableModes;

  const SessionModeEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.currentModeId,
    required this.availableModes,
  });

  factory SessionModeEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return SessionModeEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      currentModeId: json['currentModeId'] as String,
      availableModes:
          (json['availableModes'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('session_mode'),
        'sessionId': sessionId,
        'currentModeId': currentModeId,
        'availableModes': availableModes,
      };
}

/// Backend status changes during a session.
class SessionStatusEvent extends InsightsEvent {
  final String sessionId;
  final SessionStatus status;
  final String? message;

  const SessionStatusEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.status,
    this.message,
  });

  factory SessionStatusEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return SessionStatusEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      status: SessionStatus.values.byName(json['status'] as String),
      message: json['message'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('session_status'),
        'sessionId': sessionId,
        'status': status.name,
        if (message != null) 'message': message,
      };
}

// ---------------------------------------------------------------------------
// Content events
// ---------------------------------------------------------------------------

/// Text output from the assistant.
class TextEvent extends InsightsEvent {
  final String sessionId;
  final String text;
  final TextKind kind;
  final String? parentCallId;
  final String? model;

  const TextEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.text,
    required this.kind,
    this.parentCallId,
    this.model,
  });

  factory TextEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return TextEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      text: json['text'] as String,
      kind: TextKind.values.byName(json['kind'] as String),
      parentCallId: json['parentCallId'] as String?,
      model: json['model'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('text'),
        'sessionId': sessionId,
        'text': text,
        'kind': kind.name,
        if (parentCallId != null) 'parentCallId': parentCallId,
        if (model != null) 'model': model,
      };
}

/// A user message was sent.
///
/// Note: [images] serialization is skipped for now — images are binary data
/// that will need special transport handling later.
class UserInputEvent extends InsightsEvent {
  final String sessionId;
  final String text;
  final List<ImageData>? images;
  final bool isSynthetic;

  const UserInputEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.text,
    this.images,
    this.isSynthetic = false,
  });

  factory UserInputEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return UserInputEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      text: json['text'] as String,
      images: (json['images'] as List<dynamic>?)
          ?.map((e) => ImageData.fromJson(e as Map<String, dynamic>))
          .toList(),
      isSynthetic: json['isSynthetic'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('user_input'),
        'sessionId': sessionId,
        'text': text,
        if (images != null) 'images': images!.map((i) => i.toJson()).toList(),
        if (isSynthetic) 'isSynthetic': isSynthetic,
      };
}

// ---------------------------------------------------------------------------
// Tool events
// ---------------------------------------------------------------------------

/// A tool has been invoked.
class ToolInvocationEvent extends InsightsEvent {
  final String callId;
  final String? parentCallId;
  final String sessionId;
  final ToolKind kind;
  final String toolName;
  final String? title;
  final Map<String, dynamic> input;
  final List<String>? locations;
  final String? model;

  const ToolInvocationEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.callId,
    this.parentCallId,
    required this.sessionId,
    required this.kind,
    required this.toolName,
    this.title,
    required this.input,
    this.locations,
    this.model,
  });

  factory ToolInvocationEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return ToolInvocationEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      callId: json['callId'] as String,
      parentCallId: json['parentCallId'] as String?,
      sessionId: json['sessionId'] as String,
      kind: ToolKind.values.byName(json['kind'] as String),
      toolName: json['toolName'] as String,
      title: json['title'] as String?,
      input: json['input'] as Map<String, dynamic>,
      locations: (json['locations'] as List<dynamic>?)?.cast<String>(),
      model: json['model'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('tool_invocation'),
        'callId': callId,
        if (parentCallId != null) 'parentCallId': parentCallId,
        'sessionId': sessionId,
        'kind': kind.name,
        'toolName': toolName,
        if (title != null) 'title': title,
        'input': input,
        if (locations != null) 'locations': locations,
        if (model != null) 'model': model,
      };
}

/// A tool call has completed.
class ToolCompletionEvent extends InsightsEvent {
  final String callId;
  final String sessionId;
  final ToolCallStatus status;
  final dynamic output;
  final bool isError;
  final List<ContentBlock>? content;
  final List<String>? locations;

  const ToolCompletionEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.callId,
    required this.sessionId,
    required this.status,
    this.output,
    this.isError = false,
    this.content,
    this.locations,
  });

  factory ToolCompletionEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return ToolCompletionEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      callId: json['callId'] as String,
      sessionId: json['sessionId'] as String,
      status: ToolCallStatus.values.byName(json['status'] as String),
      output: json['output'],
      isError: json['isError'] as bool? ?? false,
      content: (json['content'] as List<dynamic>?)
          ?.map((e) => ContentBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
      locations: (json['locations'] as List<dynamic>?)?.cast<String>(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('tool_completion'),
        'callId': callId,
        'sessionId': sessionId,
        'status': status.name,
        if (output != null) 'output': output,
        if (isError) 'isError': isError,
        if (content != null)
          'content': content!.map((c) => c.toJson()).toList(),
        if (locations != null) 'locations': locations,
      };
}

/// A subagent was spawned.
class SubagentSpawnEvent extends InsightsEvent {
  final String sessionId;
  final String callId;
  final String? agentType;
  final String? description;
  final bool isResume;
  final String? resumeAgentId;

  const SubagentSpawnEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.callId,
    this.agentType,
    this.description,
    this.isResume = false,
    this.resumeAgentId,
  });

  factory SubagentSpawnEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return SubagentSpawnEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      callId: json['callId'] as String,
      agentType: json['agentType'] as String?,
      description: json['description'] as String?,
      isResume: json['isResume'] as bool? ?? false,
      resumeAgentId: json['resumeAgentId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('subagent_spawn'),
        'sessionId': sessionId,
        'callId': callId,
        if (agentType != null) 'agentType': agentType,
        if (description != null) 'description': description,
        if (isResume) 'isResume': isResume,
        if (resumeAgentId != null) 'resumeAgentId': resumeAgentId,
      };
}

/// A subagent finished its work.
class SubagentCompleteEvent extends InsightsEvent {
  final String sessionId;
  final String callId;
  final String? agentId;
  final String? status;
  final String? summary;

  const SubagentCompleteEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.callId,
    this.agentId,
    this.status,
    this.summary,
  });

  factory SubagentCompleteEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return SubagentCompleteEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      callId: json['callId'] as String,
      agentId: json['agentId'] as String?,
      status: json['status'] as String?,
      summary: json['summary'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('subagent_complete'),
        'sessionId': sessionId,
        'callId': callId,
        if (agentId != null) 'agentId': agentId,
        if (status != null) 'status': status,
        if (summary != null) 'summary': summary,
      };
}

// ---------------------------------------------------------------------------
// Turn lifecycle
// ---------------------------------------------------------------------------

/// A turn (prompt → response cycle) has completed.
class TurnCompleteEvent extends InsightsEvent {
  final String sessionId;
  final bool isError;
  final String? subtype;
  final List<String>? errors;
  final String? result;
  final double? costUsd;
  final int? durationMs;
  final int? durationApiMs;
  final int? numTurns;
  final TokenUsage? usage;
  final Map<String, ModelTokenUsage>? modelUsage;
  final List<PermissionDenial>? permissionDenials;

  const TurnCompleteEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    this.isError = false,
    this.subtype,
    this.errors,
    this.result,
    this.costUsd,
    this.durationMs,
    this.durationApiMs,
    this.numTurns,
    this.usage,
    this.modelUsage,
    this.permissionDenials,
  });

  factory TurnCompleteEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return TurnCompleteEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      isError: json['isError'] as bool? ?? false,
      subtype: json['subtype'] as String?,
      errors: (json['errors'] as List<dynamic>?)?.cast<String>(),
      result: json['result'] as String?,
      costUsd: (json['costUsd'] as num?)?.toDouble(),
      durationMs: json['durationMs'] as int?,
      durationApiMs: json['durationApiMs'] as int?,
      numTurns: json['numTurns'] as int?,
      usage: json['usage'] != null
          ? TokenUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      modelUsage: json['modelUsage'] != null
          ? (json['modelUsage'] as Map<String, dynamic>).map(
              (k, v) =>
                  MapEntry(k, ModelTokenUsage.fromJson(v as Map<String, dynamic>)),
            )
          : null,
      permissionDenials: (json['permissionDenials'] as List<dynamic>?)
          ?.map((e) => PermissionDenial.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('turn_complete'),
        'sessionId': sessionId,
        if (isError) 'isError': isError,
        if (subtype != null) 'subtype': subtype,
        if (errors != null) 'errors': errors,
        if (result != null) 'result': result,
        if (costUsd != null) 'costUsd': costUsd,
        if (durationMs != null) 'durationMs': durationMs,
        if (durationApiMs != null) 'durationApiMs': durationApiMs,
        if (numTurns != null) 'numTurns': numTurns,
        if (usage != null) 'usage': usage!.toJson(),
        if (modelUsage != null)
          'modelUsage':
              modelUsage!.map((k, v) => MapEntry(k, v.toJson())),
        if (permissionDenials != null)
          'permissionDenials':
              permissionDenials!.map((d) => d.toJson()).toList(),
      };
}

// ---------------------------------------------------------------------------
// Context management
// ---------------------------------------------------------------------------

/// The context window was compacted.
class ContextCompactionEvent extends InsightsEvent {
  final String sessionId;
  final CompactionTrigger trigger;
  final int? preTokens;
  final String? summary;

  const ContextCompactionEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.trigger,
    this.preTokens,
    this.summary,
  });

  factory ContextCompactionEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return ContextCompactionEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      trigger: CompactionTrigger.values.byName(json['trigger'] as String),
      preTokens: json['preTokens'] as int?,
      summary: json['summary'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('context_compaction'),
        'sessionId': sessionId,
        'trigger': trigger.name,
        if (preTokens != null) 'preTokens': preTokens,
        if (summary != null) 'summary': summary,
      };
}

// ---------------------------------------------------------------------------
// Permission events
// ---------------------------------------------------------------------------

/// The backend needs user permission to proceed.
///
/// Note: The `Completer` for responding is an in-process concern handled
/// separately — this event only carries the data fields. When deserialized
/// from JSON, no Completer is available.
class PermissionRequestEvent extends InsightsEvent {
  final String sessionId;
  final String requestId;
  final String toolName;
  final ToolKind toolKind;
  final Map<String, dynamic> toolInput;
  final String? toolUseId;
  final String? reason;
  final String? blockedPath;
  final List<PermissionSuggestionData>? suggestions;

  const PermissionRequestEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.requestId,
    required this.toolName,
    required this.toolKind,
    required this.toolInput,
    this.toolUseId,
    this.reason,
    this.blockedPath,
    this.suggestions,
  });

  factory PermissionRequestEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return PermissionRequestEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      requestId: json['requestId'] as String,
      toolName: json['toolName'] as String,
      toolKind: ToolKind.values.byName(json['toolKind'] as String),
      toolInput: json['toolInput'] as Map<String, dynamic>,
      toolUseId: json['toolUseId'] as String?,
      reason: json['reason'] as String?,
      blockedPath: json['blockedPath'] as String?,
      suggestions: (json['suggestions'] as List<dynamic>?)
          ?.map((e) =>
              PermissionSuggestionData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('permission_request'),
        'sessionId': sessionId,
        'requestId': requestId,
        'toolName': toolName,
        'toolKind': toolKind.name,
        'toolInput': toolInput,
        if (toolUseId != null) 'toolUseId': toolUseId,
        if (reason != null) 'reason': reason,
        if (blockedPath != null) 'blockedPath': blockedPath,
        if (suggestions != null)
          'suggestions': suggestions!.map((s) => s.toJson()).toList(),
      };
}

/// Permission suggestion data for [PermissionRequestEvent].
///
/// This is a simplified data-only version. The full [PermissionSuggestion]
/// type with raw JSON passthrough lives in `permission_suggestion.dart`.
@immutable
class PermissionSuggestionData {
  final String type;
  final String? toolName;
  final String? directory;
  final String? mode;
  final String description;

  const PermissionSuggestionData({
    required this.type,
    this.toolName,
    this.directory,
    this.mode,
    required this.description,
  });

  factory PermissionSuggestionData.fromJson(Map<String, dynamic> json) {
    return PermissionSuggestionData(
      type: json['type'] as String,
      toolName: json['toolName'] as String?,
      directory: json['directory'] as String?,
      mode: json['mode'] as String?,
      description: json['description'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (toolName != null) 'toolName': toolName,
        if (directory != null) 'directory': directory,
        if (mode != null) 'mode': mode,
        'description': description,
      };
}

// ---------------------------------------------------------------------------
// Usage update events
// ---------------------------------------------------------------------------

/// Intermediate usage data emitted during a turn.
///
/// This event carries per-step usage from a single API call, allowing the
/// frontend to update context and token displays in real-time rather than
/// waiting for the [TurnCompleteEvent] at the end of the turn.
///
/// The [stepUsage] contains per-API-call token counts (input, output, cache).
/// These are NOT cumulative across steps — they reflect a single step.
///
/// When the turn completes, [TurnCompleteEvent] provides authoritative
/// cumulative totals that overwrite any intermediate estimates.
class UsageUpdateEvent extends InsightsEvent {
  final String sessionId;

  /// Per-step usage from a single API call.
  ///
  /// Keys use snake_case wire format:
  /// - `input_tokens`
  /// - `output_tokens`
  /// - `cache_creation_input_tokens`
  /// - `cache_read_input_tokens`
  final Map<String, dynamic> stepUsage;

  const UsageUpdateEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    required this.stepUsage,
  });

  factory UsageUpdateEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return UsageUpdateEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      stepUsage: json['stepUsage'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('usage_update'),
        'sessionId': sessionId,
        'stepUsage': stepUsage,
      };
}

// ---------------------------------------------------------------------------
// Streaming events
// ---------------------------------------------------------------------------

/// Partial content arriving during streaming.
class StreamDeltaEvent extends InsightsEvent {
  final String sessionId;
  final String? parentCallId;
  final StreamDeltaKind kind;
  final String? textDelta;
  final String? jsonDelta;
  final int? blockIndex;
  final String? callId;

  const StreamDeltaEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    this.parentCallId,
    required this.kind,
    this.textDelta,
    this.jsonDelta,
    this.blockIndex,
    this.callId,
  });

  factory StreamDeltaEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return StreamDeltaEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      parentCallId: json['parentCallId'] as String?,
      kind: StreamDeltaKind.values.byName(json['kind'] as String),
      textDelta: json['textDelta'] as String?,
      jsonDelta: json['jsonDelta'] as String?,
      blockIndex: json['blockIndex'] as int?,
      callId: json['callId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('stream_delta'),
        'sessionId': sessionId,
        if (parentCallId != null) 'parentCallId': parentCallId,
        'kind': kind.name,
        if (textDelta != null) 'textDelta': textDelta,
        if (jsonDelta != null) 'jsonDelta': jsonDelta,
        if (blockIndex != null) 'blockIndex': blockIndex,
        if (callId != null) 'callId': callId,
      };
}

// ---------------------------------------------------------------------------
// Rate limit events
// ---------------------------------------------------------------------------

/// A single rate limit window (primary or secondary).
@immutable
class RateLimitWindow {
  final int usedPercent;
  final int? windowDurationMins;
  final int? resetsAt;

  const RateLimitWindow({
    required this.usedPercent,
    this.windowDurationMins,
    this.resetsAt,
  });

  factory RateLimitWindow.fromJson(Map<String, dynamic> json) {
    return RateLimitWindow(
      usedPercent: json['usedPercent'] as int? ?? 0,
      windowDurationMins: json['windowDurationMins'] as int?,
      resetsAt: (json['resetsAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'usedPercent': usedPercent,
        if (windowDurationMins != null)
          'windowDurationMins': windowDurationMins,
        if (resetsAt != null) 'resetsAt': resetsAt,
      };
}

/// Credit information from the rate limit update.
@immutable
class RateLimitCredits {
  final bool hasCredits;
  final bool unlimited;
  final String? balance;

  const RateLimitCredits({
    required this.hasCredits,
    required this.unlimited,
    this.balance,
  });

  factory RateLimitCredits.fromJson(Map<String, dynamic> json) {
    return RateLimitCredits(
      hasCredits: json['hasCredits'] as bool? ?? false,
      unlimited: json['unlimited'] as bool? ?? false,
      balance: json['balance'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'hasCredits': hasCredits,
        'unlimited': unlimited,
        if (balance != null) 'balance': balance,
      };
}

/// Account rate limit data updated by the backend.
///
/// This event is emitted when the backend reports updated rate limit
/// information for the account. It carries primary and secondary rate
/// limit windows, credit info, and the plan type.
class RateLimitUpdateEvent extends InsightsEvent {
  final String sessionId;
  final RateLimitWindow? primary;
  final RateLimitWindow? secondary;
  final RateLimitCredits? credits;
  final String? planType;

  const RateLimitUpdateEvent({
    required super.id,
    required super.timestamp,
    required super.provider,
    super.raw,
    super.extensions,
    required this.sessionId,
    this.primary,
    this.secondary,
    this.credits,
    this.planType,
  });

  factory RateLimitUpdateEvent.fromJson(Map<String, dynamic> json) {
    final base = InsightsEvent.parseBase(json);
    return RateLimitUpdateEvent(
      id: base.id,
      timestamp: base.timestamp,
      provider: base.provider,
      raw: base.raw,
      extensions: base.extensions,
      sessionId: json['sessionId'] as String,
      primary: json['primary'] != null
          ? RateLimitWindow.fromJson(json['primary'] as Map<String, dynamic>)
          : null,
      secondary: json['secondary'] != null
          ? RateLimitWindow.fromJson(json['secondary'] as Map<String, dynamic>)
          : null,
      credits: json['credits'] != null
          ? RateLimitCredits.fromJson(json['credits'] as Map<String, dynamic>)
          : null,
      planType: json['planType'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson('rate_limit_update'),
        'sessionId': sessionId,
        if (primary != null) 'primary': primary!.toJson(),
        if (secondary != null) 'secondary': secondary!.toJson(),
        if (credits != null) 'credits': credits!.toJson(),
        if (planType != null) 'planType': planType,
      };
}
