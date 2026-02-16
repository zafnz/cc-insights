import 'dart:async';

import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

/// Tests for Codex security config passing to thread/start and thread/resume.
///
/// Verifies that CodexBackend correctly includes sandbox and approvalPolicy
/// parameters when codexSecurityConfig is provided in SessionOptions.
void main() {
  group('CodexBackend security config', () {
    late _MockCodexProcess mockProcess;
    late CodexBackend backend;

    setUp(() {
      mockProcess = _MockCodexProcess();
      backend = CodexBackend.createForTesting(process: mockProcess);
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('thread/start includes sandbox and approvalPolicy when config provided',
        () async {
      // Arrange
      final securityConfig = const CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      final options = SessionOptions(
        codexSecurityConfig: securityConfig,
      );

      // Act
      await backend.createSession(
        prompt: 'test',
        cwd: '/test/path',
        options: options,
      );

      // Assert - find the thread/start request among captured requests
      final startRequest = mockProcess.capturedRequests
          .firstWhere((r) => r.method == 'thread/start');
      expect(startRequest.params['cwd'], '/test/path');
      expect(startRequest.params['sandbox'], 'workspace-write');
      expect(startRequest.params['approvalPolicy'], 'on-request');
    });

    test('thread/start omits sandbox and approvalPolicy when config is null',
        () async {
      // Arrange
      final options = SessionOptions();

      // Act
      await backend.createSession(
        prompt: 'test',
        cwd: '/test/path',
        options: options,
      );

      // Assert - find the thread/start request among captured requests
      final startRequest = mockProcess.capturedRequests
          .firstWhere((r) => r.method == 'thread/start');
      expect(startRequest.params['cwd'], '/test/path');
      expect(startRequest.params.containsKey('sandbox'), isFalse);
      expect(startRequest.params.containsKey('approvalPolicy'), isFalse);
    });

    test(
        'thread/resume includes sandbox and approvalPolicy when config provided',
        () async {
      // Arrange
      final securityConfig = const CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.readOnly,
        approvalPolicy: CodexApprovalPolicy.never,
      );
      final options = SessionOptions(
        resume: 'existing-thread-123',
        codexSecurityConfig: securityConfig,
      );

      // Act
      await backend.createSession(
        prompt: '',
        cwd: '/test/path',
        options: options,
      );

      // Assert - find the thread/resume request among captured requests
      final resumeRequest = mockProcess.capturedRequests
          .firstWhere((r) => r.method == 'thread/resume');
      expect(resumeRequest.params['threadId'], 'existing-thread-123');
      expect(resumeRequest.params['cwd'], '/test/path');
      expect(resumeRequest.params['sandbox'], 'read-only');
      expect(resumeRequest.params['approvalPolicy'], 'never');
    });

    test('SessionOptions without codexSecurityConfig is backward compatible',
        () async {
      // Arrange - Options with no security config at all
      final options = SessionOptions(model: 'o4-mini');

      // Act
      await backend.createSession(
        prompt: 'test',
        cwd: '/test/path',
        options: options,
      );

      // Assert - find the thread/start request among captured requests
      final startRequest = mockProcess.capturedRequests
          .firstWhere((r) => r.method == 'thread/start');
      expect(startRequest.params['cwd'], '/test/path');
      expect(startRequest.params['model'], 'o4-mini');
      expect(startRequest.params.containsKey('sandbox'), isFalse);
      expect(startRequest.params.containsKey('approvalPolicy'), isFalse);
    });
  });
}

/// Captured request for testing.
class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.params,
  });

  final String method;
  final Map<String, dynamic> params;
}

/// Mock CodexProcess that captures sendRequest calls for testing.
class _MockCodexProcess implements CodexProcess {
  final List<_CapturedRequest> capturedRequests = [];
  final _notificationsController =
      StreamController<JsonRpcNotification>.broadcast();
  final _serverRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  final _logEntriesController = StreamController<LogEntry>.broadcast();

  @override
  Stream<JsonRpcNotification> get notifications =>
      _notificationsController.stream;

  @override
  Stream<JsonRpcServerRequest> get serverRequests =>
      _serverRequestsController.stream;

  @override
  Stream<String> get logs => _logsController.stream;

  @override
  Stream<LogEntry> get logEntries => _logEntriesController.stream;

  @override
  set traceSessionId(String? value) {
    // No-op for test mock.
  }

  @override
  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic>? params,
  ) async {
    capturedRequests.add(_CapturedRequest(
      method: method,
      params: params ?? {},
    ));

    // Return a mock thread response
    if (method == 'thread/start' || method == 'thread/resume') {
      return {
        'thread': {
          'id': 'mock-thread-id',
          'model': 'o4-mini',
        },
      };
    }

    return {};
  }

  @override
  void sendNotification(String method, Map<String, dynamic>? params) {
    // Not needed for these tests
  }

  @override
  void sendResponse(Object id, Map<String, dynamic> result) {
    // Not needed for these tests
  }

  @override
  void sendError(Object id, int code, String message, {dynamic data}) {
    // Not needed for these tests
  }

  @override
  Future<void> dispose() async {
    await _notificationsController.close();
    await _serverRequestsController.close();
    await _logsController.close();
    await _logEntriesController.close();
  }
}
