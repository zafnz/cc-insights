import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:claude_sdk/claude_sdk.dart';
import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

import '../fakes/fake_codex_backend.dart';

void main() {
  group('BackendService Codex security', () {
    late BackendService service;
    late FakeCodexBackend fakeCodexBackend;

    setUp(() {
      service = BackendService();
      fakeCodexBackend = FakeCodexBackend();
    });

    tearDown(() {
      service.dispose();
    });

    test('codexSecurityConfig returns null when no Codex backend active',
        () {
      // Act
      final config = service.codexSecurityConfig;

      // Assert
      expect(config, isNull);
    });

    test('codexSecurityConfig returns config when Codex backend active',
        () async {
      // Arrange
      const testConfig = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.readOnly,
        approvalPolicy: CodexApprovalPolicy.untrusted,
      );
      fakeCodexBackend.setSecurityConfig(testConfig);

      service.registerBackendForTesting(BackendType.codex, fakeCodexBackend);

      // Act
      final config = service.codexSecurityConfig;

      // Assert
      expect(config, isNotNull);
      expect(config!.sandboxMode, CodexSandboxMode.readOnly);
      expect(config.approvalPolicy, CodexApprovalPolicy.untrusted);
    });

    test(
        'codexSecurityCapabilities returns default when no Codex backend active',
        () {
      // Act
      final capabilities = service.codexSecurityCapabilities;

      // Assert
      expect(capabilities.allowedSandboxModes, isNull);
      expect(capabilities.allowedApprovalPolicies, isNull);
    });

    test(
        'codexSecurityCapabilities returns capabilities when Codex backend active',
        () async {
      // Arrange
      const testCapabilities = CodexSecurityCapabilities(
        allowedSandboxModes: [
          CodexSandboxMode.readOnly,
          CodexSandboxMode.workspaceWrite,
        ],
        allowedApprovalPolicies: [
          CodexApprovalPolicy.untrusted,
          CodexApprovalPolicy.onRequest,
        ],
      );
      fakeCodexBackend.setCapabilities(testCapabilities);

      service.registerBackendForTesting(BackendType.codex, fakeCodexBackend);

      // Act
      final capabilities = service.codexSecurityCapabilities;

      // Assert
      expect(capabilities.allowedSandboxModes, isNotNull);
      expect(capabilities.allowedSandboxModes!.length, 2);
      expect(
        capabilities.allowedSandboxModes,
        contains(CodexSandboxMode.readOnly),
      );
      expect(capabilities.allowedApprovalPolicies, isNotNull);
      expect(capabilities.allowedApprovalPolicies!.length, 2);
    });
  });
}
