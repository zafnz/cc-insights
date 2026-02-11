import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/backend_service.dart';

/// Configuration for automatic mock responses.
///
/// Use this to configure how a test session responds to incoming messages.
class MockResponseConfig {
  const MockResponseConfig({
    this.autoReply = false,
    this.replyDelay = Duration.zero,
    this.replyText = 'Mock response',
    this.permissionTrigger,
  });

  /// Whether to automatically reply when [TestSession.send] is called.
  final bool autoReply;

  /// Delay before sending the automatic reply.
  final Duration replyDelay;

  /// Text to include in automatic replies.
  ///
  /// Supports the placeholder `{message}` which will be replaced with the
  /// user's message text.
  final String replyText;

  /// Configuration for triggering a permission (can_use_tool) request.
  ///
  /// If set, when the user's message contains the trigger phrase, the mock
  /// backend will emit a permission request instead of (or before) the reply.
  final PermissionTriggerConfig? permissionTrigger;
}

/// Configuration for a permission trigger in mock tests.
class PermissionTriggerConfig {
  const PermissionTriggerConfig({
    required this.triggerPhrase,
    required this.toolName,
    required this.toolInput,
    this.replyOnAllow = 'pass',
    this.blockedPath,
  });

  /// The phrase that triggers the permission request (e.g., "run ls -l /tmp").
  final String triggerPhrase;

  /// The tool name for the permission request (e.g., "Bash").
  final String toolName;

  /// The tool input for the permission request.
  final Map<String, dynamic> toolInput;

  /// The reply text to send when permission is allowed.
  final String replyOnAllow;

  /// Optional blocked path shown in the permission dialog.
  final String? blockedPath;
}

/// Callback for configuring a test session before it's returned.
typedef TestSessionConfigurator = void Function(
  TestSession session,
  MockResponseConfig config,
);

/// A mock implementation of [BackendService] for testing.
///
/// Uses [TestSession] to create real session instances that
/// can be controlled via test message emission. This allows integration
/// tests to verify the full message flow without a real backend.
///
/// Example usage:
/// ```dart
/// final mockBackend = MockBackendService();
/// await mockBackend.start();
///
/// // Configure auto-reply for the next session
/// mockBackend.nextSessionConfig = MockResponseConfig(
///   autoReply: true,
///   replyDelay: Duration(milliseconds: 100),
///   replyText: 'I received your message: {message}',
/// );
///
/// // Inject into app
/// CCInsightsApp(backendService: mockBackend)
/// ```
class MockBackendService extends BackendService {
  MockBackendService();

  final _uuid = const Uuid();
  final _sessions = <String, TestSession>{};

  bool _mockIsReady = false;
  bool _mockIsStarting = false;
  String? _mockError;

  TestSession? _lastCreatedSession;

  /// The most recently created session.
  TestSession? get lastCreatedSession => _lastCreatedSession;

  /// Configuration for the next session to be created.
  ///
  /// Reset to default after each session creation.
  MockResponseConfig nextSessionConfig = const MockResponseConfig();

  /// All active test sessions.
  Map<String, TestSession> get sessions => Map.unmodifiable(_sessions);

  bool _disposed = false;

  @override
  bool get isReady => _mockIsReady;

  @override
  bool get isStarting => _mockIsStarting;

  @override
  String? get error => _mockError;

  /// Start the mock backend.
  ///
  /// This immediately sets [isReady] to true without spawning any process.
  @override
  Future<void> start({
    BackendType type = BackendType.directCli,
    String? executablePath,
  }) async {
    if (_disposed) {
      throw StateError('MockBackendService has been disposed');
    }

    _mockIsStarting = true;
    _mockError = null;
    notifyListeners();

    // Brief delay to simulate startup
    await Future.delayed(const Duration(milliseconds: 10));

    _mockIsStarting = false;
    _mockIsReady = true;
    notifyListeners();
  }

  /// Create a new test Claude session.
  ///
  /// Returns a [TestSession] instance that can emit messages
  /// and tracks sent messages.
  @override
  Future<TestSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    InternalToolRegistry? registry,
  }) async {
    if (_disposed) {
      throw StateError('MockBackendService has been disposed');
    }
    if (!_mockIsReady) {
      throw StateError('MockBackendService is not ready');
    }

    final sessionId = _uuid.v4();
    final sdkSessionId = _uuid.v4();

    final session = TestSession(
      sessionId: sessionId,
      sdkSessionId: sdkSessionId,
    );

    _sessions[sessionId] = session;
    _lastCreatedSession = session;

    // Set up message handling
    final config = nextSessionConfig;
    debugPrint('MockBackend: createSession using config with permissionTrigger=${config.permissionTrigger?.triggerPhrase}');
    session.onTestSend = (message) async {
      debugPrint('MockBackend: onTestSend called with: $message');
      if (config.replyDelay > Duration.zero) {
        await Future.delayed(config.replyDelay);
      }

      // Check for permission trigger
      final permTrigger = config.permissionTrigger;
      debugPrint('MockBackend: permTrigger=${permTrigger?.triggerPhrase}');
      if (permTrigger != null && message.contains(permTrigger.triggerPhrase)) {
        debugPrint('MockBackend: Permission trigger matched! Emitting permission request...');
        // Emit assistant text saying it will use the tool
        _emitTextEvent(
          session: session,
          sessionId: sdkSessionId,
          text: 'I\'ll run that command for you.',
        );

        // Emit the tool use message
        final toolUseId = 'toolu_${_generateEventId()}';
        _emitToolInvocationEvent(
          session: session,
          sessionId: sdkSessionId,
          toolName: permTrigger.toolName,
          toolInput: permTrigger.toolInput,
          toolUseId: toolUseId,
        );

        // Emit permission request and wait for response
        final response = await session.emitTestPermissionRequest(
          id: _generateEventId(),
          toolName: permTrigger.toolName,
          toolInput: permTrigger.toolInput,
          toolUseId: toolUseId,
        );

        // Handle the response based on type
        switch (response) {
          case PermissionAllowResponse():
            // Emit tool result
            _emitToolCompletionEvent(
              session: session,
              sessionId: sdkSessionId,
              toolUseId: toolUseId,
              result: 'Command executed successfully',
            );

            // Emit success reply
            _emitTextEvent(
              session: session,
              sessionId: sdkSessionId,
              text: permTrigger.replyOnAllow,
            );

            // Emit result message to signal completion
            _emitTurnCompleteEvent(
              session: session,
              sessionId: sdkSessionId,
            );

          case PermissionDenyResponse(message: final message):
            // Permission denied - emit error
            _emitTextEvent(
              session: session,
              sessionId: sdkSessionId,
              text: 'Permission denied: $message',
            );

            _emitTurnCompleteEvent(
              session: session,
              sessionId: sdkSessionId,
              isError: true,
            );
        }
        return;
      }

      // Normal auto-reply if configured
      if (config.autoReply) {
        final replyText = config.replyText.replaceAll('{message}', message);

        // Emit assistant text response
        _emitTextEvent(
          session: session,
          sessionId: sdkSessionId,
          text: replyText,
        );

        // Emit result message to signal completion
        _emitTurnCompleteEvent(
          session: session,
          sessionId: sdkSessionId,
        );
      }
    };

    // Reset config for next session
    nextSessionConfig = const MockResponseConfig();

    // Emit system init message
    _emitSessionInitEvent(
      session: session,
      sessionId: sdkSessionId,
      cwd: cwd,
    );

    // Handle the initial prompt - check for permission trigger or auto-reply
    // Schedule with a small delay to allow subscription setup in startSession()
    // Using Future.delayed instead of Future.microtask because microtask runs
    // before the await returns in async context, but we need the caller to
    // finish subscribing first.
    debugPrint('MockBackend: Scheduling delayed callback for prompt: $prompt');
    Future.delayed(const Duration(milliseconds: 10), () async {
      debugPrint('MockBackend: Delayed callback running');
      if (config.replyDelay > Duration.zero) {
        await Future.delayed(config.replyDelay);
      }

      // Check for permission trigger in initial prompt
      final permTrigger = config.permissionTrigger;
      debugPrint('MockBackend: Checking prompt for trigger phrase: ${permTrigger?.triggerPhrase}');
      if (permTrigger != null && prompt.contains(permTrigger.triggerPhrase)) {
        debugPrint('MockBackend: Initial prompt matched trigger! Calling onTestSend...');
        // Process initial prompt through onTestSend which handles permission trigger
        await session.onTestSend?.call(prompt);
        return;
      }

      // Auto-reply to the initial prompt if configured
      if (config.autoReply) {
        final replyText = config.replyText.replaceAll('{message}', prompt);

        // Emit assistant text response
        _emitTextEvent(
          session: session,
          sessionId: sdkSessionId,
          text: replyText,
        );

        // Emit result message to signal completion
        _emitTurnCompleteEvent(
          session: session,
          sessionId: sdkSessionId,
        );
      }
    });

    return session;
  }

  @override
  Future<AgentSession> createSessionForBackend({
    required BackendType type,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    String? executablePath,
    InternalToolRegistry? registry,
  }) async {
    return createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
  }

  /// Get a session by ID.
  TestSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessions.clear();
    super.dispose();
  }

  /// Simulate a backend error.
  void simulateError(String message) {
    _mockError = message;
    _mockIsReady = false;
    notifyListeners();
  }

  /// Reset the mock backend to initial state.
  void reset() {
    _sessions.clear();
    _lastCreatedSession = null;
    _mockIsReady = false;
    _mockIsStarting = false;
    _mockError = null;
    _disposed = false;
    nextSessionConfig = const MockResponseConfig();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Event Emitters
  // ═══════════════════════════════════════════════════════════════════════════

  int _eventCounter = 0;

  String _generateEventId() => 'mock-evt-${_eventCounter++}';

  void _emitSessionInitEvent({
    required TestSession session,
    required String sessionId,
    required String cwd,
  }) {
    session.emitTestEvent(SessionInitEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: const {},
      sessionId: sessionId,
      model: 'claude-sonnet-4-20250514',
      cwd: cwd,
      availableTools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep'],
      permissionMode: 'default',
    ));
  }

  void _emitTextEvent({
    required TestSession session,
    required String sessionId,
    required String text,
    String? parentCallId,
  }) {
    session.emitTestEvent(TextEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: const {},
      sessionId: sessionId,
      text: text,
      kind: TextKind.text,
      parentCallId: parentCallId,
    ));
  }

  void _emitToolInvocationEvent({
    required TestSession session,
    required String sessionId,
    required String toolName,
    required Map<String, dynamic> toolInput,
    required String toolUseId,
    String? parentCallId,
  }) {
    session.emitTestEvent(ToolInvocationEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: const {},
      callId: toolUseId,
      sessionId: sessionId,
      kind: ToolKind.fromToolName(toolName),
      toolName: toolName,
      input: toolInput,
      parentCallId: parentCallId,
    ));
  }

  void _emitToolCompletionEvent({
    required TestSession session,
    required String sessionId,
    required String toolUseId,
    required dynamic result,
    bool isError = false,
  }) {
    session.emitTestEvent(ToolCompletionEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: const {},
      callId: toolUseId,
      sessionId: sessionId,
      status: isError ? ToolCallStatus.failed : ToolCallStatus.completed,
      output: result,
      isError: isError,
    ));
  }

  void _emitTurnCompleteEvent({
    required TestSession session,
    required String sessionId,
    bool isError = false,
  }) {
    session.emitTestEvent(TurnCompleteEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: const {},
      sessionId: sessionId,
      isError: isError,
      subtype: isError ? 'error' : 'success',
      usage: const TokenUsage(inputTokens: 100, outputTokens: 50),
      costUsd: 0.001,
      durationMs: 1000,
      numTurns: 1,
    ));
  }
}
