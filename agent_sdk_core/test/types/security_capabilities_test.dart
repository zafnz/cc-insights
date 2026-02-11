import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

void main() {
  group('CodexSecurityCapabilities.isSandboxModeAllowed', () {
    test('returns true for all modes when allowedSandboxModes is null', () {
      const capabilities = CodexSecurityCapabilities();

      for (final mode in CodexSandboxMode.values) {
        expect(capabilities.isSandboxModeAllowed(mode), isTrue);
      }
    });

    test('returns true for allowed mode, false for disallowed mode', () {
      const capabilities = CodexSecurityCapabilities(
        allowedSandboxModes: [
          CodexSandboxMode.readOnly,
          CodexSandboxMode.workspaceWrite,
        ],
      );

      expect(
          capabilities.isSandboxModeAllowed(CodexSandboxMode.readOnly), isTrue);
      expect(capabilities.isSandboxModeAllowed(CodexSandboxMode.workspaceWrite),
          isTrue);
      expect(capabilities.isSandboxModeAllowed(CodexSandboxMode.dangerFullAccess),
          isFalse);
    });
  });

  group('CodexSecurityCapabilities.isApprovalPolicyAllowed', () {
    test('returns true for all policies when allowedApprovalPolicies is null',
        () {
      const capabilities = CodexSecurityCapabilities();

      for (final policy in CodexApprovalPolicy.values) {
        expect(capabilities.isApprovalPolicyAllowed(policy), isTrue);
      }
    });

    test('returns true for allowed policy, false for disallowed policy', () {
      const capabilities = CodexSecurityCapabilities(
        allowedApprovalPolicies: [
          CodexApprovalPolicy.onRequest,
          CodexApprovalPolicy.never,
        ],
      );

      expect(capabilities.isApprovalPolicyAllowed(CodexApprovalPolicy.onRequest),
          isTrue);
      expect(capabilities.isApprovalPolicyAllowed(CodexApprovalPolicy.never),
          isTrue);
      expect(capabilities.isApprovalPolicyAllowed(CodexApprovalPolicy.untrusted),
          isFalse);
      expect(capabilities.isApprovalPolicyAllowed(CodexApprovalPolicy.onFailure),
          isFalse);
    });
  });
}
