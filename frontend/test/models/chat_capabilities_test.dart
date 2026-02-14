import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackendCapabilities', () {
    test('default constructor has all false', () {
      const caps = sdk.BackendCapabilities();

      check(caps.supportsHooks).isFalse();
      check(caps.supportsModelListing).isFalse();
      check(caps.supportsReasoningEffort).isFalse();
      check(caps.supportsPermissionModeChange).isFalse();
      check(caps.supportsModelChange).isFalse();
    });

    test('equality works', () {
      const a = sdk.BackendCapabilities(supportsHooks: true);
      const b = sdk.BackendCapabilities(supportsHooks: true);
      const c = sdk.BackendCapabilities(supportsModelListing: true);

      check(a).equals(b);
      check(a).not((it) => it.equals(c));
    });

    test('hashCode is consistent with equality', () {
      const a = sdk.BackendCapabilities(supportsHooks: true);
      const b = sdk.BackendCapabilities(supportsHooks: true);

      check(a.hashCode).equals(b.hashCode);
    });

    test('toString includes all fields', () {
      const caps = sdk.BackendCapabilities(
        supportsHooks: true,
        supportsModelListing: true,
      );

      final str = caps.toString();
      check(str).contains('hooks: true');
      check(str).contains('modelListing: true');
      check(str).contains('reasoningEffort: false');
    });
  });

  group('ClaudeCliBackend capabilities', () {
    test('supports permission mode change and model change', () {
      final backend = sdk.ClaudeCliBackend();
      addTearDown(() => backend.dispose());

      check(backend.capabilities.supportsPermissionModeChange).isTrue();
      check(backend.capabilities.supportsModelChange).isTrue();
      check(backend.capabilities.supportsHooks).isFalse();
      check(backend.capabilities.supportsModelListing).isTrue();
      check(backend.capabilities.supportsReasoningEffort).isFalse();
    });
  });

  group('ChatState capability guards', () {
    test('capabilities defaults to all-false before session start', () {
      final chat = ChatState.create(
        name: 'Test',
        worktreeRoot: '/test',
      );
      addTearDown(chat.dispose);

      check(chat.capabilities).equals(const sdk.BackendCapabilities());
    });

    test(
      'setReasoningEffort stores value locally even without capability',
      () {
        final chat = ChatState.create(
          name: 'Test',
          worktreeRoot: '/test',
        );
        addTearDown(chat.dispose);

        // No session active, capabilities default (no reasoning support)
        chat.setReasoningEffort(sdk.ReasoningEffort.high);

        check(chat.reasoningEffort).equals(sdk.ReasoningEffort.high);
      },
    );

    test(
      'setPermissionMode stores value locally even without capability',
      () {
        final chat = ChatState.create(
          name: 'Test',
          worktreeRoot: '/test',
        );
        addTearDown(chat.dispose);

        chat.setPermissionMode(PermissionMode.acceptEdits);

        check(chat.permissionMode).equals(PermissionMode.acceptEdits);
      },
    );
  });

  group('BackendService capabilities', () {
    test('capabilities returns empty when no backend started', () {
      final service = BackendService();
      addTearDown(service.dispose);

      check(service.capabilities).equals(const sdk.BackendCapabilities());
    });

    test('capabilitiesFor returns empty for unknown backend', () {
      final service = BackendService();
      addTearDown(service.dispose);

      check(service.capabilitiesFor(sdk.BackendType.codex))
          .equals(const sdk.BackendCapabilities());
    });
  });
}
