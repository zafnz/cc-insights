import 'dart:async';

import 'types/callbacks.dart';
import 'types/content_blocks.dart';
import 'types/errors.dart';
import 'types/sdk_messages.dart';
import 'types/session_options.dart';

/// Abstract interface for agent backends.
///
/// This interface defines the contract for backend implementations that
/// communicate with Claude agents. Both the Node.js backend (ClaudeBackend)
/// and the direct CLI backend (ClaudeCliBackend) implement this interface.
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
  /// Whether the backend is running.
  bool get isRunning;

  /// Stream of backend errors.
  Stream<BackendError> get errors;

  /// Stream of log messages.
  Stream<String> get logs;

  /// Create a new session.
  ///
  /// [prompt] - The initial message to send to Claude.
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

/// Abstract interface for agent sessions.
///
/// This interface defines the contract for session implementations.
/// Sessions manage the lifecycle of a conversation with Claude.
abstract class AgentSession {
  /// Unique session identifier.
  String get sessionId;

  /// Whether the session is active.
  bool get isActive;

  /// Stream of SDK messages (assistant, user, result, etc.).
  Stream<SDKMessage> get messages;

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
}
