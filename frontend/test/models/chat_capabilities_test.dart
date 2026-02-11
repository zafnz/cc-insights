import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:codex_sdk/codex_sdk.dart' show CodexSecurityConfig, CodexSecurityCapabilities;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// =============================================================================
// FAKE BACKEND SERVICE
// =============================================================================

/// Minimal fake backend for testing capability-guarded calls.
class _FakeBackendService extends ChangeNotifier implements BackendService {
  _FakeBackendService({
    this.backendCaps = const sdk.BackendCapabilities(),
  });

  final sdk.BackendCapabilities backendCaps;

  @override
  bool get isReady => true;

  @override
  bool get isStarting => false;

  @override
  String? get error => null;

  @override
  sdk.BackendType? get backendType => sdk.BackendType.directCli;

  @override
  bool isReadyFor(sdk.BackendType type) => true;

  @override
  bool isStartingFor(sdk.BackendType type) => false;

  @override
  bool isModelListLoadingFor(sdk.BackendType type) => false;

  @override
  String? errorFor(sdk.BackendType type) => null;

  @override
  sdk.BackendCapabilities get capabilities => backendCaps;

  @override
  sdk.BackendCapabilities capabilitiesFor(sdk.BackendType type) => backendCaps;

  @override
  Future<void> start({
    sdk.BackendType type = sdk.BackendType.directCli,
    String? executablePath,
  }) async {}

  @override
  Future<void> switchBackend({
    required sdk.BackendType type,
    String? executablePath,
  }) async {}

  @override
  Future<sdk.AgentBackend> createBackend({
    required sdk.BackendType type,
    String? executablePath,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<sdk.AgentSession> createSession({
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
  }) async {
    return _FakeSession();
  }

  @override
  Future<sdk.AgentSession> createSessionForBackend({
    required sdk.BackendType type,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    String? executablePath,
  }) async {
    return _FakeSession();
  }

  @override
  Future<sdk.EventTransport> createTransport({
    required sdk.BackendType type,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    String? executablePath,
  }) async {
    final session = await createSessionForBackend(
      type: type, prompt: prompt, cwd: cwd, options: options, content: content,
    );
    return sdk.InProcessTransport(
      session: session,
      capabilities: capabilitiesFor(type),
    );
  }

  @override
  CodexSecurityConfig? get codexSecurityConfig => null;

  @override
  CodexSecurityCapabilities get codexSecurityCapabilities =>
      const CodexSecurityCapabilities();

  @override
  void registerBackendForTesting(sdk.BackendType type, sdk.AgentBackend backend) {
    // Not needed for these tests
  }
}

/// Fake session that records method calls and can be configured to throw.
class _FakeSession implements sdk.AgentSession {
  final List<String> calls = [];

  @override
  String get sessionId => 'fake-session';

  @override
  String? get resolvedSessionId => sessionId;

  @override
  bool get isActive => true;

  @override

  @override
  Stream<sdk.InsightsEvent> get events => const Stream.empty();

  @override
  Stream<sdk.PermissionRequest> get permissionRequests => const Stream.empty();

  @override
  Stream<sdk.HookRequest> get hookRequests => const Stream.empty();

  @override
  Future<void> send(String message) async => calls.add('send:$message');

  @override
  Future<void> sendWithContent(List<sdk.ContentBlock> content) async =>
      calls.add('sendWithContent');

  @override
  Future<void> interrupt() async => calls.add('interrupt');

  @override
  Future<void> kill() async => calls.add('kill');

  @override
  Future<void> setModel(String? model) async =>
      calls.add('setModel:$model');

  @override
  Future<void> setPermissionMode(String? mode) async =>
      calls.add('setPermissionMode:$mode');

  @override
  Future<void> setReasoningEffort(String? effort) async =>
      calls.add('setReasoningEffort:$effort');
}

// =============================================================================
// TESTS
// =============================================================================

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
      check(backend.capabilities.supportsModelListing).isFalse();
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
