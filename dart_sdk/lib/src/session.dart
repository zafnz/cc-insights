part of 'core.dart';

/// A Claude session for interacting with Claude Code.
///
/// This class implements [AgentSession] and provides a session for interacting
/// with Claude Code via the Node.js backend.
class ClaudeSession implements AgentSession {
  ClaudeSession._({
    required ClaudeBackend backend,
    required this.sessionId,
    this.sdkSessionId,
  })  : _backend = backend,
        _isTestSession = false;

  /// Creates a test session that is not connected to a real backend.
  ///
  /// Test sessions can receive messages via [emitTestMessage] and track
  /// sent messages via [testSentMessages]. They do not communicate with
  /// any backend process.
  ///
  /// Example:
  /// ```dart
  /// final session = ClaudeSession.forTesting(sessionId: 'test-123');
  /// session.emitTestMessage(SDKAssistantMessage(...));
  /// ```
  @visibleForTesting
  ClaudeSession.forTesting({
    required this.sessionId,
    this.sdkSessionId,
  })  : _backend = null,
        _isTestSession = true;

  final ClaudeBackend? _backend;
  final bool _isTestSession;

  /// The session ID (Dart-side).
  @override
  final String sessionId;

  /// The SDK session ID (from Claude Code).
  String? sdkSessionId;

  final _messagesController = StreamController<SDKMessage>.broadcast();
  final _permissionRequestsController =
      StreamController<PermissionRequest>.broadcast();
  final _hookRequestsController = StreamController<HookRequest>.broadcast();

  /// Stream of SDK messages.
  @override
  Stream<SDKMessage> get messages => _messagesController.stream;

  /// Stream of permission requests.
  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  /// Stream of hook requests.
  @override
  Stream<HookRequest> get hookRequests => _hookRequestsController.stream;

  bool _disposed = false;

  /// Whether the session is active.
  @override
  bool get isActive => !_disposed;

  /// Messages sent via [send] when this is a test session.
  ///
  /// Only populated for sessions created with [ClaudeSession.forTesting].
  @visibleForTesting
  final List<String> testSentMessages = [];

  /// Callback invoked when [send] is called on a test session.
  ///
  /// Use this to trigger mock responses when the session receives a message.
  /// Returns a Future to support async operations like permission requests.
  @visibleForTesting
  Future<void> Function(String message)? onTestSend;

  /// Send a follow-up message to the session.
  @override
  Future<void> send(String message) async {
    if (_disposed) return;
    if (_isTestSession) {
      testSentMessages.add(message);
      await onTestSend?.call(message);
      return;
    }
    await _backend!._sendToSession(sessionId, message);
  }

  /// Send a message with content blocks (text and images).
  ///
  /// Use this instead of [send] when attaching images to a message.
  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) return;
    if (_isTestSession) {
      // For test sessions, track the text content
      final textParts = content.whereType<TextBlock>().map((b) => b.text);
      testSentMessages.add(textParts.join('\n'));
      await onTestSend?.call(textParts.join('\n'));
      return;
    }
    await _backend!._sendToSessionWithContent(sessionId, content);
  }

  /// Interrupt the current execution.
  @override
  Future<void> interrupt() async {
    if (_disposed) return;
    if (_isTestSession) return;
    await _backend!._interruptSession(sessionId);
  }

  /// Kill the session.
  @override
  Future<void> kill() async {
    if (_disposed) return;
    if (_isTestSession) {
      _dispose();
      return;
    }
    await _backend!._killSession(sessionId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Query Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the list of supported models.
  Future<List<ModelInfo>> supportedModels() async {
    if (_disposed || _isTestSession) return [];
    final result = await _backend!._querySession<List<dynamic>>(
      sessionId,
      'supportedModels',
    );
    return result
        .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Get the list of supported slash commands.
  Future<List<SlashCommand>> supportedCommands() async {
    if (_disposed || _isTestSession) return [];
    final result = await _backend!._querySession<List<dynamic>>(
      sessionId,
      'supportedCommands',
    );
    return result
        .map((c) => SlashCommand.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Get the status of MCP servers.
  Future<List<McpServerStatus>> mcpServerStatus() async {
    if (_disposed || _isTestSession) return [];
    final result = await _backend!._querySession<List<dynamic>>(
      sessionId,
      'mcpServerStatus',
    );
    return result
        .map((s) => McpServerStatus.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Set the model for this session.
  @override
  Future<void> setModel(String? model) async {
    if (_disposed || _isTestSession) return;
    await _backend!._querySession<void>(sessionId, 'setModel', [model]);
  }

  /// Set the permission mode for this session.
  @override
  Future<void> setPermissionMode(String? mode) async {
    if (_disposed || _isTestSession) return;
    await _backend!._querySession<void>(
      sessionId,
      'setPermissionMode',
      [mode],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Internal Message Handlers
  // ═══════════════════════════════════════════════════════════════════════════

  void _handleSdkMessage(SDKMessage msg) {
    if (_disposed) return;

    // Update SDK session ID from messages
    if (msg.sessionId.isNotEmpty) {
      sdkSessionId = msg.sessionId;
    }

    _messagesController.add(msg);
  }

  void _handlePermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    List<dynamic>? suggestions,
    String? toolUseId,
    String? agentId,
    String? blockedPath,
    String? decisionReason,
    Map<String, dynamic>? rawJson,
  }) {
    if (_disposed) return;

    final completer = Completer<PermissionResponse>();
    final request = PermissionRequest(
      id: id,
      sessionId: sessionId,
      toolName: toolName,
      toolInput: toolInput,
      suggestions: suggestions,
      toolUseId: toolUseId,
      agentId: agentId,
      blockedPath: blockedPath,
      decisionReason: decisionReason,
      rawJson: rawJson,
      completer: completer,
    );

    _permissionRequestsController.add(request);

    // When the request is responded to, send the response to backend
    // (skip for test sessions as there's no backend)
    if (!_isTestSession) {
      completer.future.then((response) {
        _backend!._sendCallbackResponse(id, sessionId, response.toJson());
      });
    }
  }

  void _handleHookRequest({
    required String id,
    required String event,
    required dynamic input,
    String? toolUseId,
  }) {
    if (_disposed) return;

    final completer = Completer<HookResponse>();
    final request = HookRequest(
      id: id,
      sessionId: sessionId,
      event: event,
      input: input,
      toolUseId: toolUseId,
      completer: completer,
    );

    _hookRequestsController.add(request);

    // When the request is responded to, send the response to backend
    // (skip for test sessions as there's no backend)
    if (!_isTestSession) {
      completer.future.then((response) {
        _backend!._sendCallbackResponse(id, sessionId, response.toJson());
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Test Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Emits a message to the [messages] stream.
  ///
  /// Only available for sessions created with [ClaudeSession.forTesting].
  @visibleForTesting
  void emitTestMessage(SDKMessage message) {
    if (_disposed) return;
    _messagesController.add(message);
  }

  /// Emits a permission request to the [permissionRequests] stream.
  ///
  /// Only available for sessions created with [ClaudeSession.forTesting].
  /// Returns the completer's future so tests can verify the response.
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
