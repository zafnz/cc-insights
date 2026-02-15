import 'dart:async';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/chat_session_service.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/services/internal_tools_service.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

// =============================================================================
// Fakes
// =============================================================================

class FakeBackendService extends BackendService {
  FakeTestSession? sessionToReturn;
  bool shouldThrow = false;
  String? lastPrompt;
  int createSessionCount = 0;

  @override
  bool get isReady => true;

  @override
  Future<sdk.AgentSession> createSession({
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    sdk.InternalToolRegistry? registry,
  }) async {
    createSessionCount++;
    lastPrompt = prompt;
    if (shouldThrow) throw Exception('Backend error');
    return sessionToReturn ?? FakeTestSession();
  }

  @override
  Future<sdk.AgentSession> createSessionForBackend({
    required sdk.BackendType type,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    String? executablePath,
    sdk.InternalToolRegistry? registry,
  }) async {
    return createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
  }

  @override
  Future<sdk.EventTransport> createTransport({
    required sdk.BackendType type,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    String? executablePath,
    sdk.InternalToolRegistry? registry,
  }) async {
    final session = await createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
    return sdk.InProcessTransport(
      session: session,
      capabilities: const sdk.BackendCapabilities(),
    );
  }

  @override
  Future<sdk.EventTransport> createTransportForAgent({
    required String agentId,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    sdk.InternalToolRegistry? registry,
  }) async {
    return createTransport(
      type: sdk.BackendType.directCli,
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
  }
}

class FakeTestSession implements sdk.TestSession {
  final _eventsController = StreamController<sdk.InsightsEvent>.broadcast();
  final _permissionsController =
      StreamController<sdk.PermissionRequest>.broadcast();
  final _hooksController = StreamController<sdk.HookRequest>.broadcast();
  final List<String> sentMessages = [];
  bool interruptCalled = false;

  @override
  String get sessionId => 'fake-session-id';
  @override
  String? sdkSessionId;
  @override
  String? get resolvedSessionId => sdkSessionId ?? sessionId;
  @override
  Stream<sdk.InsightsEvent> get events => _eventsController.stream;
  @override
  Stream<sdk.PermissionRequest> get permissionRequests =>
      _permissionsController.stream;
  @override
  Stream<sdk.HookRequest> get hookRequests => _hooksController.stream;
  @override
  bool get isActive => true;
  @override
  Future<void> send(String message) async => sentMessages.add(message);
  @override
  Future<void> sendWithContent(List<sdk.ContentBlock> content) async {}
  @override
  Future<void> interrupt() async => interruptCalled = true;
  @override
  Future<void> kill() async {
    await _eventsController.close();
    await _permissionsController.close();
    await _hooksController.close();
  }

  @override
  Future<void> setModel(String? model) async {}
  @override
  Future<void> setPermissionMode(String? mode) async {}
  @override
  Future<void> setConfigOption(String configId, dynamic value) async {}
  @override
  Future<void> setReasoningEffort(String? effort) async {}
  @override
  String? get serverModel => null;
  @override
  String? get serverReasoningEffort => null;
  @override
  final List<String> testSentMessages = [];
  @override
  Future<void> Function(String message)? onTestSend;
  @override
  void emitTestEvent(sdk.InsightsEvent event) => _eventsController.add(event);
  @override
  Future<sdk.PermissionResponse> emitTestPermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) async =>
      const sdk.PermissionDenyResponse(message: 'Test deny');
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  final resources = TestResources();
  late FakeBackendService fakeBackend;
  late EventHandler eventHandler;
  late InternalToolsService internalTools;
  late ChatSessionService service;

  setUp(() {
    fakeBackend = FakeBackendService();
    eventHandler = EventHandler();
    internalTools = InternalToolsService();
    service = ChatSessionService(
      backend: fakeBackend,
      eventHandler: eventHandler,
      internalTools: internalTools,
    );
  });

  tearDown(() async {
    eventHandler.dispose();
    await resources.disposeAll();
  });

  group('ChatSessionService', () {
    group('submitMessage', () {
      test('does nothing when text is empty and no images', () async {
        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        await service.submitMessage(chat, text: '');

        check(chat.data.primaryConversation.entries).isEmpty();
        check(fakeBackend.createSessionCount).equals(0);
      });

      test('does nothing when text is whitespace only', () async {
        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        await service.submitMessage(chat, text: '   ');

        check(chat.data.primaryConversation.entries).isEmpty();
      });

      test('handles /clear command by resetting session', () async {
        final session = FakeTestSession();
        fakeBackend.sessionToReturn = session;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );
        chat.draftText = '/clear';

        // Start a session first
        await chat.startSession(
          backend: fakeBackend,
          eventHandler: eventHandler,
          prompt: 'initial',
          internalToolsService: internalTools,
        );
        check(chat.hasActiveSession).isTrue();

        // Submit /clear
        await service.submitMessage(chat, text: '/clear');

        // Draft should be cleared
        check(chat.draftText).equals('');
        // Session should be reset (no active session, no session ID for resume)
        check(chat.hasActiveSession).isFalse();
      });

      test('starts session when no active session', () async {
        final session = FakeTestSession();
        fakeBackend.sessionToReturn = session;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );
        chat.draftText = 'Hello';

        await service.submitMessage(chat, text: 'Hello');

        // Draft should be cleared
        check(chat.draftText).equals('');
        // Session should have been created
        check(fakeBackend.createSessionCount).equals(1);
        check(fakeBackend.lastPrompt).equals('Hello');
        // User entry should be added
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<UserInputEntry>();
      });

      test('adds error entry when startSession fails', () async {
        fakeBackend.shouldThrow = true;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        await service.submitMessage(chat, text: 'Hello');

        // Should have user entry + error entry
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(2);
        check(entries[0]).isA<UserInputEntry>();
        check(entries[1]).isA<TextOutputEntry>();
        final errorEntry = entries[1] as TextOutputEntry;
        check(errorEntry.text).contains('Failed to start session');
      });

      test('sends message when session is active', () async {
        final session = FakeTestSession();
        fakeBackend.sessionToReturn = session;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        // Start a session first
        await chat.startSession(
          backend: fakeBackend,
          eventHandler: eventHandler,
          prompt: 'initial',
          internalToolsService: internalTools,
        );
        check(chat.hasActiveSession).isTrue();

        // Now send a follow-up message
        await service.submitMessage(chat, text: 'Follow up');

        check(session.sentMessages).contains('Follow up');
      });
    });

    group('interrupt', () {
      test('calls chat.interrupt()', () async {
        final session = FakeTestSession();
        fakeBackend.sessionToReturn = session;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        await chat.startSession(
          backend: fakeBackend,
          eventHandler: eventHandler,
          prompt: 'test',
          internalToolsService: internalTools,
        );

        await service.interrupt(chat);

        check(session.interruptCalled).isTrue();
      });

      test('handles errors gracefully', () async {
        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        // Calling interrupt with no active session - should not throw
        await service.interrupt(chat);
      });
    });

    group('startSession', () {
      test('adds UserInputEntry when showInConversation is true', () async {
        final session = FakeTestSession();
        fakeBackend.sessionToReturn = session;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        await service.startSession(
          chat,
          prompt: 'Hello',
          showInConversation: true,
        );

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<UserInputEntry>();
      });

      test('does not add UserInputEntry when showInConversation is false',
          () async {
        final session = FakeTestSession();
        fakeBackend.sessionToReturn = session;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        await service.startSession(
          chat,
          prompt: 'Hidden prompt',
          showInConversation: false,
        );

        // No user entry, but session was started
        final entries = chat.data.primaryConversation.entries;
        check(entries).isEmpty();
        check(fakeBackend.createSessionCount).equals(1);
      });

      test('adds error entry on failure', () async {
        fakeBackend.shouldThrow = true;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        await service.startSession(
          chat,
          prompt: 'Hello',
          showInConversation: false,
        );

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<TextOutputEntry>();
        final errorEntry = entries.first as TextOutputEntry;
        check(errorEntry.text).contains('Failed to start session');
      });
    });

    group('approvePlanWithClearContext', () {
      test('runs the 4-step workflow', () async {
        final session1 = FakeTestSession();
        final session2 = FakeTestSession();
        var sessionCount = 0;
        // Return different sessions for first and second startSession calls
        fakeBackend.sessionToReturn = session1;

        final chat = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/test'),
        );

        // Start initial session
        await chat.startSession(
          backend: fakeBackend,
          eventHandler: eventHandler,
          prompt: 'initial',
          internalToolsService: internalTools,
        );

        // Set up a pending permission (required for allowPermission to work)
        final completer = Completer<sdk.PermissionResponse>();
        chat.setPendingPermission(sdk.PermissionRequest(
          id: 'test-perm',
          sessionId: 'fake-session-id',
          toolName: 'ExitPlanMode',
          toolInput: {},
          completer: completer,
        ));

        // Switch to session2 for the new session after reset
        fakeBackend.sessionToReturn = session2;

        await service.approvePlanWithClearContext(chat, 'My plan text');

        // Verify permission was cleared
        check(chat.pendingPermission).isNull();

        // Verify a new session was started (2 total: initial + after plan)
        check(fakeBackend.createSessionCount).equals(2);

        // Verify the prompt includes the plan text
        check(fakeBackend.lastPrompt).isNotNull();
        check(fakeBackend.lastPrompt!).contains('My plan text');

        // Verify user entry was added
        final entries = chat.data.primaryConversation.entries;
        final hasApprovalEntry = entries.any((e) =>
            e is UserInputEntry &&
            e.text.contains('Plan approved'));
        check(hasApprovalEntry).isTrue();
      });
    });
  });
}
