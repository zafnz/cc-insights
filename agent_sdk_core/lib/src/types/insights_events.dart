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
}

// PermissionDenial is imported from sdk_messages.dart (existing type).

/// Image data attached to a user input event.
@immutable
class ImageData {
  final String mediaType;
  final String data;

  const ImageData({
    required this.mediaType,
    required this.data,
  });
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
}

// ---------------------------------------------------------------------------
// Session lifecycle events
// ---------------------------------------------------------------------------

/// Emitted once when the session is established and ready for prompts.
class SessionInitEvent extends InsightsEvent {
  final String sessionId;
  final String? model;
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
    this.cwd,
    this.availableTools,
    this.mcpServers,
    this.permissionMode,
    this.account,
    this.slashCommands,
    this.availableModels,
  });
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
}

/// A user message was sent.
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
}

// ---------------------------------------------------------------------------
// Permission events
// ---------------------------------------------------------------------------

/// The backend needs user permission to proceed.
///
/// Note: The `Completer` for responding is an in-process concern handled
/// separately — this event only carries the data fields.
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
}
