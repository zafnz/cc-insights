import 'dart:async';

import 'package:flutter/foundation.dart';

import 'callbacks.dart';
import 'content_blocks.dart';
import 'errors.dart';
import 'sdk_messages.dart';
import 'session_options.dart';
import 'usage.dart';

/// Backend for communicating with Claude Code via a Node.js subprocess.
///
/// DEPRECATED: The Node.js backend has been removed. This class remains
/// for backwards compatibility but will throw an error if [spawn] is called.
/// Use [AgentService] with ACP instead.
class ClaudeBackend {
  ClaudeBackend._();

  bool _disposed = false;

  final _errorsController = StreamController<BackendError>.broadcast();

  /// Stream of backend errors.
  Stream<BackendError> get errors => _errorsController.stream;

  /// Stream of backend stderr logs.
  Stream<String> get logs => const Stream.empty();

  /// Path to the backend log file, if file logging is enabled.
  String? get logFilePath => null;

  /// Whether the backend process is running.
  bool get isRunning => !_disposed;

  /// Spawn the Node.js backend process.
  ///
  /// DEPRECATED: This method now throws [UnsupportedError].
  /// Use [AgentService] with ACP instead.
  static Future<ClaudeBackend> spawn({
    required String backendPath,
    String? nodeExecutable,
  }) async {
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Create a new Claude session.
  ///
  /// DEPRECATED: This method throws [UnsupportedError].
  /// Use [AgentService] with ACP instead.
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Dispose of the backend and all sessions.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _errorsController.close();
  }
}

/// A Claude session for interacting with Claude Code.
///
/// DEPRECATED: This class remains for backwards compatibility with testing code.
/// For new code, use [ACPSessionWrapper] with ACP instead.
class ClaudeSession {
  ClaudeSession._({
    required this.sessionId,
    this.sdkSessionId,
  }) : _isTestSession = false;

  /// Creates a test session that is not connected to a real backend.
  ///
  /// Test sessions can receive messages via [emitTestMessage] and track
  /// sent messages via [testSentMessages]. They do not communicate with
  /// any backend process.
  @visibleForTesting
  ClaudeSession.forTesting({
    required this.sessionId,
    this.sdkSessionId,
  }) : _isTestSession = true;

  final bool _isTestSession;

  /// The session ID (Dart-side).
  final String sessionId;

  /// The SDK session ID (from Claude Code).
  String? sdkSessionId;

  final _messagesController = StreamController<SDKMessage>.broadcast();
  final _permissionRequestsController =
      StreamController<PermissionRequest>.broadcast();
  final _hookRequestsController = StreamController<HookRequest>.broadcast();

  /// Stream of SDK messages.
  Stream<SDKMessage> get messages => _messagesController.stream;

  /// Stream of permission requests.
  Stream<PermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  /// Stream of hook requests.
  Stream<HookRequest> get hookRequests => _hookRequestsController.stream;

  bool _disposed = false;

  /// Messages sent via [send] when this is a test session.
  @visibleForTesting
  final List<String> testSentMessages = [];

  /// Callback invoked when [send] is called on a test session.
  @visibleForTesting
  Future<void> Function(String message)? onTestSend;

  /// Send a follow-up message to the session.
  Future<void> send(String message) async {
    if (_disposed) return;
    if (_isTestSession) {
      testSentMessages.add(message);
      await onTestSend?.call(message);
      return;
    }
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Send a message with content blocks (text and images).
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) return;
    if (_isTestSession) {
      final textParts = content.whereType<TextBlock>().map((b) => b.text);
      testSentMessages.add(textParts.join('\n'));
      await onTestSend?.call(textParts.join('\n'));
      return;
    }
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Interrupt the current execution.
  Future<void> interrupt() async {
    if (_disposed) return;
    if (_isTestSession) return;
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Kill the session.
  Future<void> kill() async {
    if (_disposed) return;
    if (_isTestSession) {
      _dispose();
      return;
    }
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Get the list of supported models.
  Future<List<ModelInfo>> supportedModels() async {
    if (_disposed || _isTestSession) return [];
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Get the list of supported slash commands.
  Future<List<SlashCommand>> supportedCommands() async {
    if (_disposed || _isTestSession) return [];
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Get the status of MCP servers.
  Future<List<McpServerStatus>> mcpServerStatus() async {
    if (_disposed || _isTestSession) return [];
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Set the model for this session.
  Future<void> setModel(String? model) async {
    if (_disposed || _isTestSession) return;
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Set the permission mode for this session.
  Future<void> setPermissionMode(PermissionMode mode) async {
    if (_disposed || _isTestSession) return;
    throw UnsupportedError(
      'The Node.js backend has been removed. '
      'Use AgentService with ACP instead.',
    );
  }

  /// Emits a message to the [messages] stream.
  @visibleForTesting
  void emitTestMessage(SDKMessage message) {
    if (_disposed) return;
    _messagesController.add(message);
  }

  /// Emits a permission request to the [permissionRequests] stream.
  @visibleForTesting
  Future<PermissionResponse> emitTestPermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) {
    final completer = Completer<PermissionResponse>();
    final request = PermissionRequest(
      id: id,
      sessionId: sessionId,
      toolName: toolName,
      toolInput: toolInput,
      toolUseId: toolUseId,
      completer: completer,
    );
    _permissionRequestsController.add(request);
    return completer.future;
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _messagesController.close();
    _permissionRequestsController.close();
    _hookRequestsController.close();
  }
}
