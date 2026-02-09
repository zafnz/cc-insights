import 'dart:async';

import 'package:meta/meta.dart';

import 'sdk_logger.dart';
import 'types/callbacks.dart';
import 'types/content_blocks.dart';
import 'types/errors.dart';
import 'types/insights_events.dart';
import 'types/sdk_messages.dart';
import 'types/session_options.dart';
import 'types/usage.dart';

/// Describes the capabilities of a backend implementation.
///
/// Each backend declares what features it supports, allowing callers
/// to adapt their behavior (e.g., hiding unsupported UI controls)
/// rather than calling methods that silently no-op.
@immutable
class BackendCapabilities {
  const BackendCapabilities({
    this.supportsHooks = false,
    this.supportsModelListing = false,
    this.supportsReasoningEffort = false,
    this.supportsPermissionModeChange = false,
    this.supportsModelChange = false,
  });

  /// Whether the backend supports hook requests (PreToolUse, PostToolUse, etc.).
  final bool supportsHooks;

  /// Whether the backend can enumerate available models.
  final bool supportsModelListing;

  /// Whether the backend supports reasoning effort levels.
  final bool supportsReasoningEffort;

  /// Whether the backend supports mid-session permission mode changes.
  final bool supportsPermissionModeChange;

  /// Whether the backend supports mid-session model changes.
  final bool supportsModelChange;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackendCapabilities &&
        other.supportsHooks == supportsHooks &&
        other.supportsModelListing == supportsModelListing &&
        other.supportsReasoningEffort == supportsReasoningEffort &&
        other.supportsPermissionModeChange == supportsPermissionModeChange &&
        other.supportsModelChange == supportsModelChange;
  }

  @override
  int get hashCode => Object.hash(
        supportsHooks,
        supportsModelListing,
        supportsReasoningEffort,
        supportsPermissionModeChange,
        supportsModelChange,
      );

  @override
  String toString() => 'BackendCapabilities('
      'hooks: $supportsHooks, '
      'modelListing: $supportsModelListing, '
      'reasoningEffort: $supportsReasoningEffort, '
      'permissionModeChange: $supportsPermissionModeChange, '
      'modelChange: $supportsModelChange)';
}

/// Abstract interface for agent backends.
///
/// This interface defines the contract for backend implementations that
/// communicate with agent runtimes. Backends are responsible for spawning
/// and managing sessions.
///
/// Example:
/// ```dart
/// // Use the interface to be backend-agnostic
/// AgentBackend backend = await BackendFactory.create();
/// AgentSession session = await backend.createSession(
///   prompt: 'Hello!',
///   cwd: '/my/project',
/// );
/// ```
abstract class AgentBackend {
  /// The capabilities this backend supports.
  BackendCapabilities get capabilities;

  /// Whether the backend is running.
  bool get isRunning;

  /// Stream of backend errors.
  Stream<BackendError> get errors;

  /// Stream of log messages (plain text, for backwards compatibility).
  Stream<String> get logs;

  /// Stream of structured log entries.
  ///
  /// Provides structured log data with direction, content, and metadata.
  /// Prefer this over [logs] for new code as it preserves JSON structure.
  Stream<LogEntry> get logEntries;

  /// Create a new session.
  ///
  /// [prompt] - The initial message to send to the agent.
  /// [cwd] - The working directory for the session.
  /// [options] - Optional session configuration.
  /// [content] - Optional content blocks (for multi-modal input).
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  });

  /// List of active sessions.
  List<AgentSession> get sessions;

  /// Dispose the backend and all its sessions.
  Future<void> dispose();
}

/// Optional interface for backends that can list available models.
abstract class ModelListingBackend {
  /// Returns models available to the current account/runtime.
  Future<List<ModelInfo>> listModels();
}

/// Abstract interface for agent sessions.
///
/// This interface defines the contract for session implementations.
/// Sessions manage the lifecycle of a conversation with an agent.
abstract class AgentSession {
  /// Unique session identifier.
  String get sessionId;

  /// Session ID suitable for resume. Defaults to [sessionId].
  ///
  /// Backends that distinguish between local and SDK-provided IDs can
  /// override this to return the correct resume identifier.
  String? get resolvedSessionId => sessionId;

  /// Whether the session is active.
  bool get isActive;

  /// Stream of insights events.
  Stream<InsightsEvent> get events;

  /// Stream of permission requests.
  Stream<PermissionRequest> get permissionRequests;

  /// Stream of hook requests.
  Stream<HookRequest> get hookRequests;

  /// Send a message to the session.
  Future<void> send(String message);

  /// Send content blocks (text and images) to the session.
  Future<void> sendWithContent(List<ContentBlock> content);

  /// Interrupt the current execution.
  Future<void> interrupt();

  /// Terminate the session.
  Future<void> kill();

  /// Set the model for this session.
  ///
  /// Note: This may not be supported by all session implementations.
  /// Check the specific implementation for availability.
  Future<void> setModel(String? model);

  /// Set the permission mode for this session.
  ///
  /// Note: This may not be supported by all session implementations.
  /// Check the specific implementation for availability.
  Future<void> setPermissionMode(String? mode);

  /// Set the reasoning effort level for this session.
  ///
  /// Only applicable to Codex backends with reasoning-capable models.
  /// Claude backends will ignore this setting.
  Future<void> setReasoningEffort(String? effort);
}
