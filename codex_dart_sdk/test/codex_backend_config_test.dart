import 'dart:async';

import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

/// Tests for CodexBackend config reading during initialization.
///
/// Verifies that CodexBackend correctly reads security config and capabilities
/// when the backend is created.
void main() {
  group('CodexBackend config reading', () {
    late _MockCodexProcess mockProcess;
    late CodexBackend backend;

    setUp(() {
      mockProcess = _MockCodexProcess();
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('reads config and capabilities on initialization', () async {
      // Arrange - Mock config responses
      mockProcess.setConfigResponses(
        configResponse: {
          'config': {
            'sandbox_mode': 'read-only',
            'approval_policy': 'untrusted',
          },
        },
        requirementsResponse: {
          'requirements': {
            'allowedSandboxModes': ['read-only'],
            'allowedApprovalPolicies': ['untrusted', 'on-request'],
          },
        },
      );

      // Act - Create backend and call _readInitialConfig
      backend = CodexBackend.createForTesting(process: mockProcess);
      // Manually trigger config read (normally called by create())
      await backend.testReadConfig();

      // Assert
      final config = backend.currentSecurityConfig;
      expect(config, isNotNull);
      expect(config!.sandboxMode, CodexSandboxMode.readOnly);
      expect(config.approvalPolicy, CodexApprovalPolicy.untrusted);

      final capabilities = backend.securityCapabilities;
      expect(capabilities.allowedSandboxModes, isNotNull);
      expect(capabilities.allowedSandboxModes!.length, 1);
      expect(
        capabilities.allowedSandboxModes,
        contains(CodexSandboxMode.readOnly),
      );
      expect(capabilities.allowedApprovalPolicies, isNotNull);
      expect(capabilities.allowedApprovalPolicies!.length, 2);
    });

    test('falls back to defaults on config read failure', () async {
      // Arrange - Mock config read to throw error
      mockProcess.setConfigReadError('Connection failed');

      // Act
      backend = CodexBackend.createForTesting(process: mockProcess);
      await backend.testReadConfig();

      // Assert - Should use defaults
      final config = backend.currentSecurityConfig;
      expect(config, isNotNull);
      expect(config!.sandboxMode, CodexSecurityConfig.defaultConfig.sandboxMode);
      expect(
        config.approvalPolicy,
        CodexSecurityConfig.defaultConfig.approvalPolicy,
      );

      final capabilities = backend.securityCapabilities;
      expect(capabilities.allowedSandboxModes, isNull);
      expect(capabilities.allowedApprovalPolicies, isNull);
    });

    test('exposes configWriter getter', () async {
      // Arrange
      mockProcess.setConfigResponses(
        configResponse: {'config': {}},
        requirementsResponse: {},
      );

      // Act
      backend = CodexBackend.createForTesting(process: mockProcess);

      // Assert
      final writer = backend.configWriter;
      expect(writer, isA<CodexConfigWriter>());
    });
  });
}

/// Mock CodexProcess that simulates config responses for testing.
class _MockCodexProcess implements CodexProcess {
  Map<String, dynamic>? _configResponse;
  Map<String, dynamic>? _requirementsResponse;
  String? _configReadError;

  final _notificationsController =
      StreamController<JsonRpcNotification>.broadcast();
  final _serverRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  final _logEntriesController = StreamController<LogEntry>.broadcast();

  void setConfigResponses({
    required Map<String, dynamic> configResponse,
    required Map<String, dynamic> requirementsResponse,
  }) {
    _configResponse = configResponse;
    _requirementsResponse = requirementsResponse;
  }

  void setConfigReadError(String error) {
    _configReadError = error;
  }

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
    if (_configReadError != null) {
      throw Exception(_configReadError);
    }

    if (method == 'config/read') {
      return _configResponse ?? {'config': {}};
    }

    if (method == 'configRequirements/read') {
      return _requirementsResponse ?? {};
    }

    // Default responses for other methods
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
