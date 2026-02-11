import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

void main() {
  group('CodexSandboxMode.fromWire', () {
    test('round-trips all three values', () {
      for (final mode in CodexSandboxMode.values) {
        expect(CodexSandboxMode.fromWire(mode.wireValue), equals(mode));
      }
    });

    test('returns workspaceWrite for unknown string', () {
      expect(CodexSandboxMode.fromWire('unknown'),
          equals(CodexSandboxMode.workspaceWrite));
    });
  });

  group('CodexApprovalPolicy.fromWire', () {
    test('round-trips all four values', () {
      for (final policy in CodexApprovalPolicy.values) {
        expect(CodexApprovalPolicy.fromWire(policy.wireValue), equals(policy));
      }
    });

    test('returns onRequest for unknown string', () {
      expect(CodexApprovalPolicy.fromWire('unknown'),
          equals(CodexApprovalPolicy.onRequest));
    });
  });

  group('CodexWebSearchMode.fromWire', () {
    test('round-trips all three values', () {
      for (final mode in CodexWebSearchMode.values) {
        expect(CodexWebSearchMode.fromWire(mode.wireValue), equals(mode));
      }
    });

    test('returns cached for unknown string', () {
      expect(CodexWebSearchMode.fromWire('unknown'),
          equals(CodexWebSearchMode.cached));
    });
  });

  group('CodexWorkspaceWriteOptions', () {
    test('fromJson/toJson round-trip with all fields set', () {
      final original = const CodexWorkspaceWriteOptions(
        networkAccess: true,
        writableRoots: ['/path/one', '/path/two'],
        excludeSlashTmp: true,
        excludeTmpdirEnvVar: true,
      );

      final json = original.toJson();
      final roundTripped = CodexWorkspaceWriteOptions.fromJson(json);

      expect(roundTripped, equals(original));
    });

    test('default constructor has expected defaults', () {
      const options = CodexWorkspaceWriteOptions();

      expect(options.networkAccess, equals(false));
      expect(options.writableRoots, isEmpty);
      expect(options.excludeSlashTmp, equals(false));
      expect(options.excludeTmpdirEnvVar, equals(false));
    });

    test('copyWith preserves unchanged fields and updates specified fields', () {
      const original = CodexWorkspaceWriteOptions(
        networkAccess: true,
        writableRoots: ['/path/one'],
        excludeSlashTmp: true,
        excludeTmpdirEnvVar: false,
      );

      final updated = original.copyWith(
        networkAccess: false,
        writableRoots: ['/path/two', '/path/three'],
      );

      expect(updated.networkAccess, equals(false));
      expect(updated.writableRoots, equals(['/path/two', '/path/three']));
      expect(updated.excludeSlashTmp, equals(true)); // unchanged
      expect(updated.excludeTmpdirEnvVar, equals(false)); // unchanged
    });
  });

  group('SecurityConfig serialization', () {
    test('CodexSecurityConfig.toJson/fromJson round-trip', () {
      final original = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.readOnly,
        approvalPolicy: CodexApprovalPolicy.never,
        workspaceWriteOptions: const CodexWorkspaceWriteOptions(
          networkAccess: true,
          writableRoots: ['/workspace'],
        ),
        webSearch: CodexWebSearchMode.live,
      );

      final json = original.toJson();
      final roundTripped = SecurityConfig.fromJson(json) as CodexSecurityConfig;

      expect(roundTripped, equals(original));
    });

    test('ClaudeSecurityConfig.toJson/fromJson round-trip', () {
      const original = ClaudeSecurityConfig(
        permissionMode: PermissionMode.acceptEdits,
      );

      final json = original.toJson();
      final roundTripped =
          SecurityConfig.fromJson(json) as ClaudeSecurityConfig;

      expect(roundTripped, equals(original));
    });

    test('SecurityConfig.fromJson dispatches to correct subclass', () {
      final codexJson = {
        'type': 'codex',
        'sandboxMode': 'workspace-write',
        'approvalPolicy': 'on-request',
      };

      final codexConfig = SecurityConfig.fromJson(codexJson);
      expect(codexConfig, isA<CodexSecurityConfig>());

      final claudeJson = {
        'type': 'claude',
        'permissionMode': 'default',
      };

      final claudeConfig = SecurityConfig.fromJson(claudeJson);
      expect(claudeConfig, isA<ClaudeSecurityConfig>());
    });
  });

  group('CodexSecurityConfig.defaultConfig', () {
    test('has sandboxMode == workspaceWrite', () {
      expect(CodexSecurityConfig.defaultConfig.sandboxMode,
          equals(CodexSandboxMode.workspaceWrite));
    });

    test('has approvalPolicy == onRequest', () {
      expect(CodexSecurityConfig.defaultConfig.approvalPolicy,
          equals(CodexApprovalPolicy.onRequest));
    });
  });
}
