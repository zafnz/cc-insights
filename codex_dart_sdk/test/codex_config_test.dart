import 'dart:async';

import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

/// Mock CodexProcess for testing config operations.
class MockCodexProcess implements CodexProcess {
  Map<String, dynamic> Function(String, Map<String, dynamic>?)?
      _sendRequestHandler;

  void setSendRequestHandler(
    Map<String, dynamic> Function(String, Map<String, dynamic>?)? handler,
  ) {
    _sendRequestHandler = handler;
  }

  @override
  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic>? params,
  ) async {
    if (_sendRequestHandler != null) {
      return _sendRequestHandler!(method, params);
    }
    return {};
  }

  @override
  void sendNotification(String method, Map<String, dynamic>? params) {}

  @override
  void sendResponse(Object id, Map<String, dynamic> result) {}

  @override
  void sendError(Object id, int code, String message, {dynamic data}) {}

  @override
  Stream<JsonRpcNotification> get notifications =>
      const Stream<JsonRpcNotification>.empty();

  @override
  Stream<JsonRpcServerRequest> get serverRequests =>
      const Stream<JsonRpcServerRequest>.empty();

  @override
  Stream<String> get logs => const Stream<String>.empty();

  @override
  Stream<LogEntry> get logEntries => const Stream<LogEntry>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  group('CodexConfigReader', () {
    late MockCodexProcess mockProcess;
    late CodexConfigReader reader;

    setUp(() {
      mockProcess = MockCodexProcess();
      reader = CodexConfigReader(mockProcess);
    });

    group('readSecurityConfig', () {
      test('parses full config response with all fields', () async {
        mockProcess.setSendRequestHandler((method, params) {
          expect(method, 'config/read');
          return {
            'config': {
              'sandbox_mode': 'read-only',
              'approval_policy': 'untrusted',
              'sandbox_workspace_write': {
                'network_access': true,
                'writable_roots': ['/tmp', '/var/tmp'],
                'exclude_slash_tmp': true,
                'exclude_tmpdir_env_var': false,
              },
              'web_search': 'live',
            },
          };
        });

        final config = await reader.readSecurityConfig();

        expect(config.sandboxMode, CodexSandboxMode.readOnly);
        expect(config.approvalPolicy, CodexApprovalPolicy.untrusted);
        expect(config.workspaceWriteOptions, isNotNull);
        expect(config.workspaceWriteOptions!.networkAccess, isTrue);
        expect(config.workspaceWriteOptions!.writableRoots, ['/tmp', '/var/tmp']);
        expect(config.workspaceWriteOptions!.excludeSlashTmp, isTrue);
        expect(config.workspaceWriteOptions!.excludeTmpdirEnvVar, isFalse);
        expect(config.webSearch, CodexWebSearchMode.live);
      });

      test('handles missing fields with defaults', () async {
        mockProcess.setSendRequestHandler((method, params) {
          return {
            'config': {},
          };
        });

        final config = await reader.readSecurityConfig();

        expect(config.sandboxMode, CodexSandboxMode.workspaceWrite);
        expect(config.approvalPolicy, CodexApprovalPolicy.onRequest);
        expect(config.workspaceWriteOptions, isNull);
        expect(config.webSearch, isNull);
      });

      test('handles null config', () async {
        mockProcess.setSendRequestHandler((method, params) {
          return {};
        });

        final config = await reader.readSecurityConfig();

        expect(config.sandboxMode, CodexSandboxMode.workspaceWrite);
        expect(config.approvalPolicy, CodexApprovalPolicy.onRequest);
      });

      test('parses workspace-write options', () async {
        mockProcess.setSendRequestHandler((method, params) {
          return {
            'config': {
              'sandbox_mode': 'workspace-write',
              'approval_policy': 'on-request',
              'sandbox_workspace_write': {
                'network_access': false,
                'writable_roots': ['/home/user/project'],
                'exclude_slash_tmp': false,
                'exclude_tmpdir_env_var': true,
              },
            },
          };
        });

        final config = await reader.readSecurityConfig();

        expect(config.sandboxMode, CodexSandboxMode.workspaceWrite);
        expect(config.workspaceWriteOptions, isNotNull);
        expect(config.workspaceWriteOptions!.networkAccess, isFalse);
        expect(
          config.workspaceWriteOptions!.writableRoots,
          ['/home/user/project'],
        );
      });
    });

    group('readCapabilities', () {
      test('returns default capabilities when no requirements', () async {
        mockProcess.setSendRequestHandler((method, params) {
          expect(method, 'config/requirementsRead');
          return {};
        });

        final capabilities = await reader.readCapabilities();

        expect(capabilities.allowedSandboxModes, isNull);
        expect(capabilities.allowedApprovalPolicies, isNull);
      });

      test('parses restricted sandbox modes and approval policies', () async {
        mockProcess.setSendRequestHandler((method, params) {
          return {
            'requirements': {
              'allowedSandboxModes': ['read-only', 'workspace-write'],
              'allowedApprovalPolicies': ['untrusted', 'on-request'],
            },
          };
        });

        final capabilities = await reader.readCapabilities();

        expect(capabilities.allowedSandboxModes, isNotNull);
        expect(capabilities.allowedSandboxModes!.length, 2);
        expect(
          capabilities.allowedSandboxModes,
          contains(CodexSandboxMode.readOnly),
        );
        expect(
          capabilities.allowedSandboxModes,
          contains(CodexSandboxMode.workspaceWrite),
        );

        expect(capabilities.allowedApprovalPolicies, isNotNull);
        expect(capabilities.allowedApprovalPolicies!.length, 2);
        expect(
          capabilities.allowedApprovalPolicies,
          contains(CodexApprovalPolicy.untrusted),
        );
        expect(
          capabilities.allowedApprovalPolicies,
          contains(CodexApprovalPolicy.onRequest),
        );
      });

      test('handles empty requirements object', () async {
        mockProcess.setSendRequestHandler((method, params) {
          return {
            'requirements': {},
          };
        });

        final capabilities = await reader.readCapabilities();

        expect(capabilities.allowedSandboxModes, isNull);
        expect(capabilities.allowedApprovalPolicies, isNull);
      });
    });
  });

  group('CodexConfigWriter', () {
    late MockCodexProcess mockProcess;
    late CodexConfigWriter writer;

    setUp(() {
      mockProcess = MockCodexProcess();
      writer = CodexConfigWriter(mockProcess);
    });

    group('writeValue', () {
      test('constructs correct JSON-RPC params', () async {
        String? capturedMethod;
        Map<String, dynamic>? capturedParams;

        mockProcess.setSendRequestHandler((method, params) {
          capturedMethod = method;
          capturedParams = params;
          return {
            'status': 'ok',
            'filePath': '/path/to/config.json',
            'version': '1.0.0',
          };
        });

        await writer.writeValue(
          keyPath: 'sandbox_mode',
          value: 'read-only',
        );

        expect(capturedMethod, 'config/write');
        expect(capturedParams, isNotNull);
        expect(capturedParams!['keyPath'], 'sandbox_mode');
        expect(capturedParams!['value'], 'read-only');
        expect(capturedParams!['mergeStrategy'], 'replace');
      });
    });

    group('batchWrite', () {
      test('sends array of edits', () async {
        String? capturedMethod;
        Map<String, dynamic>? capturedParams;

        mockProcess.setSendRequestHandler((method, params) {
          capturedMethod = method;
          capturedParams = params;
          return {
            'status': 'ok',
          };
        });

        await writer.batchWrite([
          CodexConfigEdit(
            keyPath: 'sandbox_mode',
            value: 'workspace-write',
          ),
          CodexConfigEdit(
            keyPath: 'approval_policy',
            value: 'on-request',
          ),
        ]);

        expect(capturedMethod, 'config/batchWrite');
        expect(capturedParams, isNotNull);
        final edits = capturedParams!['edits'] as List;
        expect(edits.length, 2);
        expect(edits[0]['keyPath'], 'sandbox_mode');
        expect(edits[0]['value'], 'workspace-write');
        expect(edits[1]['keyPath'], 'approval_policy');
        expect(edits[1]['value'], 'on-request');
      });
    });

    group('setSandboxMode', () {
      test('sends correct keyPath and value', () async {
        String? capturedMethod;
        Map<String, dynamic>? capturedParams;

        mockProcess.setSendRequestHandler((method, params) {
          capturedMethod = method;
          capturedParams = params;
          return {
            'status': 'ok',
          };
        });

        await writer.setSandboxMode(CodexSandboxMode.readOnly);

        expect(capturedMethod, 'config/write');
        expect(capturedParams!['keyPath'], 'sandbox_mode');
        expect(capturedParams!['value'], 'read-only');
        expect(capturedParams!['mergeStrategy'], 'replace');
      });
    });

    group('setApprovalPolicy', () {
      test('sends correct keyPath and value', () async {
        String? capturedMethod;
        Map<String, dynamic>? capturedParams;

        mockProcess.setSendRequestHandler((method, params) {
          capturedMethod = method;
          capturedParams = params;
          return {
            'status': 'ok',
          };
        });

        await writer.setApprovalPolicy(CodexApprovalPolicy.onFailure);

        expect(capturedMethod, 'config/write');
        expect(capturedParams!['keyPath'], 'approval_policy');
        expect(capturedParams!['value'], 'on-failure');
        expect(capturedParams!['mergeStrategy'], 'replace');
      });
    });

    group('setWorkspaceWriteOptions', () {
      test('sends correct structure', () async {
        String? capturedMethod;
        Map<String, dynamic>? capturedParams;

        mockProcess.setSendRequestHandler((method, params) {
          capturedMethod = method;
          capturedParams = params;
          return {
            'status': 'ok',
          };
        });

        const options = CodexWorkspaceWriteOptions(
          networkAccess: true,
          writableRoots: ['/tmp'],
          excludeSlashTmp: false,
          excludeTmpdirEnvVar: true,
        );

        await writer.setWorkspaceWriteOptions(options);

        expect(capturedMethod, 'config/write');
        expect(capturedParams!['keyPath'], 'sandbox_workspace_write');
        expect(capturedParams!['mergeStrategy'], 'upsert');
        final value = capturedParams!['value'] as Map<String, dynamic>;
        expect(value['network_access'], isTrue);
        expect(value['writable_roots'], ['/tmp']);
        expect(value['exclude_slash_tmp'], isFalse);
        expect(value['exclude_tmpdir_env_var'], isTrue);
      });
    });
  });

  group('CodexConfigWriteResult', () {
    test('fromJson parses ok status correctly', () {
      final result = CodexConfigWriteResult.fromJson({
        'status': 'ok',
        'filePath': '/path/to/config.json',
        'version': '1.0.0',
      });

      expect(result.status, 'ok');
      expect(result.filePath, '/path/to/config.json');
      expect(result.version, '1.0.0');
      expect(result.wasOverridden, isFalse);
      expect(result.overrideMessage, isNull);
      expect(result.effectiveValue, isNull);
    });

    test('fromJson parses okOverridden status with metadata', () {
      final result = CodexConfigWriteResult.fromJson({
        'status': 'okOverridden',
        'filePath': '/path/to/config.json',
        'version': '1.0.0',
        'overriddenMetadata': {
          'message': 'Policy requires read-only mode',
          'effectiveValue': 'read-only',
        },
      });

      expect(result.status, 'okOverridden');
      expect(result.wasOverridden, isTrue);
      expect(result.overrideMessage, 'Policy requires read-only mode');
      expect(result.effectiveValue, 'read-only');
    });
  });
}
