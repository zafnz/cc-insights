part of 'core.dart';

/// Backend for communicating with Claude Code via a Node.js subprocess.
///
/// This class implements [AgentBackend] and manages the lifecycle of a
/// Node.js backend process that communicates with the Claude Agent SDK.
class ClaudeBackend implements AgentBackend {
  ClaudeBackend._({
    required Process process,
    required Protocol protocol,
  })  : _process = process,
        _protocol = protocol;

  final Process _process;
  final Protocol _protocol;
  final _uuid = const Uuid();

  final _sessions = <String, ClaudeSession>{};
  final _pendingCreates = <String, Completer<ClaudeSession>>{};
  final _pendingQueries = <String, Completer<dynamic>>{};
  final _pendingInterrupts = <String, Completer<void>>{};
  final _pendingKills = <String, Completer<void>>{};

  final _errorsController = StreamController<BackendError>.broadcast();

  /// Stream of backend errors.
  @override
  Stream<BackendError> get errors => _errorsController.stream;

  /// Stream of backend stderr logs.
  @override
  Stream<String> get logs => _protocol.stderrLogs;

  /// Path to the backend log file, if file logging is enabled.
  String? get logFilePath => _protocol.logFilePath;

  /// Whether the backend process is running.
  @override
  bool get isRunning => !_disposed;

  /// List of active sessions.
  @override
  List<AgentSession> get sessions => List.unmodifiable(_sessions.values);

  bool _disposed = false;

  /// Spawn the Node.js backend process.
  static Future<ClaudeBackend> spawn({
    required String backendPath,
    String? nodeExecutable,
  }) async {
    final executable = nodeExecutable ?? 'node';

    final process = await Process.start(
      executable,
      [backendPath],
      mode: ProcessStartMode.normal,
    );

    late final ClaudeBackend backend;
    late final Protocol protocol;

    protocol = Protocol(
      process: process,
      onMessage: (msg) => backend._handleMessage(msg),
      onError: (err) => backend._errorsController.add(
        err is BackendError ? err : BackendError(err.message, code: err.code),
      ),
    );

    backend = ClaudeBackend._(
      process: process,
      protocol: protocol,
    );

    // Monitor for early process exit (e.g., module not found)
    backend._setupProcessExitHandler();

    // Wait for process to be ready and check if it crashed
    final exitCode = await Future.any([
      process.exitCode,
      Future.delayed(const Duration(milliseconds: 200), () => -1),
    ]);

    // If process exited during startup, it failed
    if (exitCode != -1) {
      // Give stderr a moment to flush
      await Future.delayed(const Duration(milliseconds: 50));
      final stderrLines = protocol.getBufferedStderr();
      final errorMessage = stderrLines.isNotEmpty
          ? 'Backend process failed to start:\n${stderrLines.join('\n')}'
          : 'Backend process exited with code $exitCode';
      await backend.dispose();
      throw BackendProcessError(errorMessage);
    }

    return backend;
  }

  /// Sets up handler for unexpected process exit after spawn.
  void _setupProcessExitHandler() {
    _process.exitCode.then((exitCode) {
      if (!_disposed && exitCode != 0) {
        _errorsController.add(BackendError(
          'Backend process exited unexpectedly with code $exitCode',
          code: 'PROCESS_EXIT',
        ));
      }
    });
  }

  /// Create a new Claude session.
  ///
  /// If [content] is provided (e.g., text + images), it takes precedence over
  /// the [prompt] string. Use [content] when you need to send images with the
  /// initial message.
  @override
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    final id = _uuid.v4();
    final completer = Completer<ClaudeSession>();
    _pendingCreates[id] = completer;

    _protocol.send(SessionCreateMessage(
      id: id,
      prompt: prompt,
      cwd: cwd,
      options: options?.toJson(),
      content: content,
    ));

    return completer.future;
  }

  void _handleMessage(IncomingMessage msg) {
    switch (msg) {
      case SessionCreatedMessage m:
        _handleSessionCreated(m);
      case SdkMessageMessage m:
        _handleSdkMessage(m);
      case CallbackRequestMessage m:
        _handleCallbackRequest(m);
      case QueryResultMessage m:
        _handleQueryResult(m);
      case SessionInterruptedMessage m:
        _handleSessionInterrupted(m);
      case SessionKilledMessage m:
        _handleSessionKilled(m);
      case ErrorMessage m:
        _handleError(m);
      case UnknownIncomingMessage _:
        // Ignore unknown messages
        break;
    }
  }

  void _handleSessionCreated(SessionCreatedMessage msg) {
    final completer = _pendingCreates.remove(msg.id);
    if (completer == null) return;

    final session = ClaudeSession._(
      backend: this,
      sessionId: msg.sessionId,
      sdkSessionId: msg.sdkSessionId,
    );

    _sessions[msg.sessionId] = session;
    completer.complete(session);
  }

  void _handleSdkMessage(SdkMessageMessage msg) {
    final session = _sessions[msg.sessionId];
    session?._handleSdkMessage(msg.payload);
  }

  void _handleCallbackRequest(CallbackRequestMessage msg) {
    final session = _sessions[msg.sessionId];
    if (session == null) return;

    if (msg.callbackType == 'can_use_tool') {
      session._handlePermissionRequest(
        id: msg.id,
        toolName: msg.toolName ?? '',
        toolInput: msg.toolInput ?? {},
        suggestions: msg.suggestions,
        toolUseId: msg.toolUseId,
        agentId: msg.agentId,
        blockedPath: msg.blockedPath,
        decisionReason: msg.decisionReason,
        rawJson: msg.rawJson,
      );
    } else if (msg.callbackType == 'hook') {
      session._handleHookRequest(
        id: msg.id,
        event: msg.hookEvent ?? '',
        input: msg.hookInput,
        toolUseId: msg.toolUseId,
      );
    }
  }

  void _handleQueryResult(QueryResultMessage msg) {
    final completer = _pendingQueries.remove(msg.id);
    if (completer == null) return;

    if (msg.success) {
      completer.complete(msg.result);
    } else {
      completer.completeError(QueryError(msg.error ?? 'Query failed'));
    }
  }

  void _handleSessionInterrupted(SessionInterruptedMessage msg) {
    final completer = _pendingInterrupts.remove(msg.id);
    completer?.complete();
  }

  void _handleSessionKilled(SessionKilledMessage msg) {
    final completer = _pendingKills.remove(msg.id);
    completer?.complete();
    _sessions.remove(msg.sessionId)?._dispose();
  }

  void _handleError(ErrorMessage msg) {
    final error = BackendError(msg.message, code: msg.code, details: msg.details);

    // Check if this is a response to a pending request
    if (msg.id != null) {
      final createCompleter = _pendingCreates.remove(msg.id);
      if (createCompleter != null) {
        createCompleter.completeError(error);
        return;
      }

      final queryCompleter = _pendingQueries.remove(msg.id);
      if (queryCompleter != null) {
        queryCompleter.completeError(error);
        return;
      }

      final interruptCompleter = _pendingInterrupts.remove(msg.id);
      if (interruptCompleter != null) {
        interruptCompleter.completeError(error);
        return;
      }

      final killCompleter = _pendingKills.remove(msg.id);
      if (killCompleter != null) {
        killCompleter.completeError(error);
        return;
      }
    }

    // If error is for a specific session, emit as an error message to that session
    if (msg.sessionId != null) {
      final session = _sessions[msg.sessionId];
      if (session != null) {
        session._messagesController.add(SDKErrorMessage(
          error: error,
          sessionId: msg.sessionId!,
        ));
        return;
      }
    }

    // Otherwise emit to global error stream
    _errorsController.add(error);
  }

  /// Send a message to a session.
  Future<void> _sendToSession(String sessionId, String message) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    final id = _uuid.v4();
    _protocol.send(SessionSendMessage(
      id: id,
      sessionId: sessionId,
      message: message,
    ));
  }

  /// Send a message with content blocks (text + images) to a session.
  ///
  /// Ensures there is always at least one non-empty text block, as the API
  /// rejects messages with empty text content blocks.
  Future<void> _sendToSessionWithContent(
    String sessionId,
    List<ContentBlock> content,
  ) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    // Ensure there's at least one non-empty text block.
    // The API rejects messages where text content blocks are empty.
    final hasNonEmptyText = content.any(
      (block) => block is TextBlock && block.text.trim().isNotEmpty,
    );

    final adjustedContent = hasNonEmptyText
        ? content
        : [const TextBlock(text: ' '), ...content];

    final id = _uuid.v4();
    _protocol.send(SessionSendMessage(
      id: id,
      sessionId: sessionId,
      content: adjustedContent,
    ));
  }

  /// Interrupt a session.
  Future<void> _interruptSession(String sessionId) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    final id = _uuid.v4();
    final completer = Completer<void>();
    _pendingInterrupts[id] = completer;

    _protocol.send(SessionInterruptMessage(
      id: id,
      sessionId: sessionId,
    ));

    return completer.future;
  }

  /// Kill a session.
  Future<void> _killSession(String sessionId) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    final id = _uuid.v4();
    final completer = Completer<void>();
    _pendingKills[id] = completer;

    _protocol.send(SessionKillMessage(
      id: id,
      sessionId: sessionId,
    ));

    return completer.future;
  }

  /// Send a callback response.
  void _sendCallbackResponse(
    String id,
    String sessionId,
    Map<String, dynamic> payload,
  ) {
    if (_disposed) return;

    _protocol.send(CallbackResponseMessage(
      id: id,
      sessionId: sessionId,
      payload: payload,
    ));
  }

  /// Call a query method on a session.
  Future<T> _querySession<T>(
    String sessionId,
    String method, [
    List<dynamic>? args,
  ]) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    final id = _uuid.v4();
    final completer = Completer<dynamic>();
    _pendingQueries[id] = completer;

    _protocol.send(QueryCallMessage(
      id: id,
      sessionId: sessionId,
      method: method,
      args: args,
    ));

    final result = await completer.future;
    return result as T;
  }

  /// Dispose of the backend and all sessions.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Dispose all sessions
    for (final session in _sessions.values) {
      session._dispose();
    }
    _sessions.clear();

    // Cancel pending requests
    for (final completer in _pendingCreates.values) {
      completer.completeError(const BackendProcessError('Backend disposed'));
    }
    _pendingCreates.clear();

    for (final completer in _pendingQueries.values) {
      completer.completeError(const BackendProcessError('Backend disposed'));
    }
    _pendingQueries.clear();

    for (final completer in _pendingInterrupts.values) {
      completer.completeError(const BackendProcessError('Backend disposed'));
    }
    _pendingInterrupts.clear();

    for (final completer in _pendingKills.values) {
      completer.completeError(const BackendProcessError('Backend disposed'));
    }
    _pendingKills.clear();

    // Clean up protocol and process
    await _protocol.dispose();
    _process.kill();
    await _errorsController.close();
  }
}
