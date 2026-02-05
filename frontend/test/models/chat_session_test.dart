import 'dart:async';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/conversation.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/sdk_message_handler.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:claude_sdk/claude_sdk.dart'
    show
        APIAssistantMessage,
        ClaudeSession,
        ContentBlock,
        HookRequest,
        McpServerStatus,
        ModelInfo,
        PermissionDenyResponse,
        PermissionRequest,
        PermissionResponse,
        SDKAssistantMessage,
        SDKMessage,
        SessionOptions,
        SlashCommand,
        TextBlock;
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

// =============================================================================
// Fake Implementations
// =============================================================================

/// Fake implementation of [BackendService] for testing.
class FakeBackendService extends BackendService {
  FakeClaudeSession? sessionToReturn;
  SessionOptions? lastOptions;
  String? lastPrompt;
  String? lastCwd;
  bool shouldThrow = false;
  String errorMessage = 'Backend error';

  @override
  bool get isReady => true;

  @override
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    if (shouldThrow) {
      throw Exception(errorMessage);
    }

    lastPrompt = prompt;
    lastCwd = cwd;
    lastOptions = options;

    if (sessionToReturn == null) {
      throw StateError('No session configured for FakeBackendService');
    }

    return sessionToReturn!;
  }

  @override
  Future<sdk.AgentSession> createSessionForBackend({
    required sdk.BackendType type,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    String? executablePath,
  }) async {
    return createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
    );
  }
}

/// Fake implementation of [ClaudeSession] for testing.
class FakeClaudeSession implements ClaudeSession {
  final StreamController<SDKMessage> _messagesController =
      StreamController<SDKMessage>.broadcast();
  final StreamController<PermissionRequest> _permissionRequestsController =
      StreamController<PermissionRequest>.broadcast();
  final StreamController<HookRequest> _hookRequestsController =
      StreamController<HookRequest>.broadcast();

  final List<String> sentMessages = [];
  bool killCalled = false;
  bool interruptCalled = false;

  @override
  Stream<SDKMessage> get messages => _messagesController.stream;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  @override
  Stream<HookRequest> get hookRequests => _hookRequestsController.stream;

  @override
  bool get isActive => true;

  @override
  String get sessionId => 'fake-session-id';

  @override
  String? sdkSessionId;

  @override
  String? get resolvedSessionId => sdkSessionId ?? sessionId;

  @override
  Future<void> send(String message) async {
    sentMessages.add(message);
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {}

  @override
  Future<void> kill() async {
    killCalled = true;
    await _messagesController.close();
    await _permissionRequestsController.close();
    await _hookRequestsController.close();
  }

  @override
  Future<void> interrupt() async {
    interruptCalled = true;
  }

  @override
  Future<List<ModelInfo>> supportedModels() async => [];

  @override
  Future<List<SlashCommand>> supportedCommands() async => [];

  @override
  Future<List<McpServerStatus>> mcpServerStatus() async => [];

  @override
  Future<void> setModel(String? model) async {}

  @override
  Future<void> setPermissionMode(String? mode) async {}

  @override
  Future<void> setReasoningEffort(String? effort) async {}

  // Test-only members
  @override
  final List<String> testSentMessages = [];

  @override
  Future<void> Function(String message)? onTestSend;

  @override
  void emitTestMessage(SDKMessage message) {
    _messagesController.add(message);
  }

  @override
  Future<PermissionResponse> emitTestPermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) async =>
      PermissionDenyResponse(message: 'Test deny');

  /// Emit a message to the stream.
  void emitMessage(SDKMessage message) {
    _messagesController.add(message);
  }

  /// Emit an error to the stream.
  void emitError(Object error) {
    _messagesController.addError(error);
  }

  /// Complete the message stream (simulates session end).
  void completeStream() {
    _messagesController.close();
  }

  /// Emit a permission request.
  void emitPermissionRequest(PermissionRequest request) {
    _permissionRequestsController.add(request);
  }
}

/// Fake implementation of [SdkMessageHandler] for testing.
class FakeSdkMessageHandler extends SdkMessageHandler {
  final List<Map<String, dynamic>> handledMessages = [];
  ChatState? lastChatState;

  @override
  void handleMessage(ChatState chat, Map<String, dynamic> rawMessage) {
    lastChatState = chat;
    handledMessages.add(rawMessage);
  }

  @override
  void clear() {
    handledMessages.clear();
    lastChatState = null;
  }
}

/// Creates a fake [PermissionRequest] for testing.
PermissionRequest createFakePermissionRequest({
  String id = 'perm-1',
  String toolName = 'Bash',
  Map<String, dynamic>? toolInput,
}) {
  final completer = Completer<PermissionResponse>();
  return PermissionRequest(
    id: id,
    sessionId: 'fake-session-id',
    toolName: toolName,
    toolInput: toolInput ?? {'command': 'ls -la'},
    completer: completer,
  );
}

/// Creates a fake [SDKMessage] for testing.
SDKMessage createFakeAssistantMessage({
  String text = 'Hello from Claude',
}) {
  return SDKAssistantMessage(
    uuid: 'msg-1',
    sessionId: 'fake-session-id',
    message: APIAssistantMessage(
      role: 'assistant',
      content: [TextBlock(text: text)],
    ),
    rawJson: {
      'type': 'assistant',
      'uuid': 'msg-1',
      'session_id': 'fake-session-id',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
    },
  );
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  final resources = TestResources();

  tearDown(() async {
    await resources.disposeAll();
  });

  group('ChatState Session Lifecycle', () {
    group('initial state', () {
      test('hasActiveSession is false initially', () {
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );

        check(state.hasActiveSession).isFalse();
      });

      test('pendingPermission is null initially', () {
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );

        check(state.pendingPermission).isNull();
      });

      test('isWaitingForPermission is false initially', () {
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );

        check(state.isWaitingForPermission).isFalse();
      });
    });

    group('startSession()', () {
      test('creates session and subscribes to streams', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path/to/worktree'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        // Act
        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello Claude',
        );

        // Assert
        check(state.hasActiveSession).isTrue();
        check(backend.lastPrompt).equals('Hello Claude');
        check(backend.lastCwd).equals('/path/to/worktree');
        check(backend.lastOptions).isNotNull();
        check(backend.lastOptions!.model).equals('opus');
      });

      test('notifies listeners when session starts', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        backend.sessionToReturn = FakeClaudeSession();
        final handler = FakeSdkMessageHandler();
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Assert
        check(notified).isTrue();
      });

      test('throws StateError when session already active', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        backend.sessionToReturn = FakeClaudeSession();
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'First session',
        );

        // Act & Assert
        await check(
          state.startSession(
            backend: backend,
            messageHandler: handler,
            prompt: 'Second session',
          ),
        ).throws<StateError>();
      });

      test('throws StateError when chat has no worktree root', () async {
        // Arrange - create chat data without worktreeRoot
        final chatData = ChatData(
          id: 'chat-1',
          name: 'Test',
          worktreeRoot: null,
          primaryConversation: ConversationData.primary(id: 'conv-1'),
        );
        final state = resources.track(ChatState(chatData));
        final backend = FakeBackendService();
        backend.sessionToReturn = FakeClaudeSession();
        final handler = FakeSdkMessageHandler();

        // Act & Assert
        await check(
          state.startSession(
            backend: backend,
            messageHandler: handler,
            prompt: 'Hello',
          ),
        ).throws<StateError>();
      });

      test('passes correct permission mode to backend', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        // Use app's PermissionMode
        state.setPermissionMode(PermissionMode.acceptEdits);
        final backend = FakeBackendService();
        backend.sessionToReturn = FakeClaudeSession();
        final handler = FakeSdkMessageHandler();

        // Act
        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Assert - the SDK permission mode should be acceptEdits
        check(backend.lastOptions).isNotNull();
        // Compare to SDK's PermissionMode
        check(backend.lastOptions!.permissionMode)
            .equals(sdk.PermissionMode.acceptEdits);
      });
    });

    group('sendMessage()', () {
      test('adds UserInputEntry and sends to session', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Initial',
        );

        // Act
        await state.sendMessage('Follow-up message');

        // Assert
        check(session.sentMessages).contains('Follow-up message');

        // Check that a UserInputEntry was added
        final entries = state.data.primaryConversation.entries;
        check(entries.length).equals(1); // The follow-up
        final lastEntry = entries.last;
        check(lastEntry).isA<UserInputEntry>();
        check((lastEntry as UserInputEntry).text).equals('Follow-up message');
      });

      test('throws StateError when no active session', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );

        // Act & Assert
        await check(state.sendMessage('Hello')).throws<StateError>();
      });
    });

    group('stopSession()', () {
      test('cancels subscriptions and kills session', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Act
        await state.stopSession();

        // Assert
        check(state.hasActiveSession).isFalse();
        check(session.killCalled).isTrue();
      });

      test('clears pending permission and active agents', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Add a pending permission and an agent
        state.setPendingPermission(createFakePermissionRequest());
        state.addSubagentConversation('agent-1', 'Test Agent', 'Task desc');

        check(state.pendingPermission).isNotNull();
        check(state.activeAgents).isNotEmpty();

        // Act
        await state.stopSession();

        // Assert
        check(state.pendingPermission).isNull();
        check(state.activeAgents).isEmpty();
      });

      test('notifies listeners', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        backend.sessionToReturn = FakeClaudeSession();
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        var notified = false;
        state.addListener(() => notified = true);

        // Act
        await state.stopSession();

        // Assert
        check(notified).isTrue();
      });

      test('does nothing when no session active', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );

        // Act - should not throw
        await state.stopSession();

        // Assert
        check(state.hasActiveSession).isFalse();
      });
    });

    group('setPendingPermission()', () {
      test('sets permission and notifies listeners', () {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        var notified = false;
        state.addListener(() => notified = true);

        final request = createFakePermissionRequest();

        // Act
        state.setPendingPermission(request);

        // Assert
        check(state.pendingPermission).equals(request);
        check(state.isWaitingForPermission).isTrue();
        check(notified).isTrue();
      });

      test('ignores null when setPendingPermission is called', () {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        state.setPendingPermission(createFakePermissionRequest());
        check(state.pendingPermission).isNotNull();
        check(state.pendingPermissionCount).equals(1);

        var notified = false;
        state.addListener(() => notified = true);

        // Act - null is ignored in the queue model
        state.setPendingPermission(null);

        // Assert - permission is still pending (null was ignored)
        check(state.pendingPermission).isNotNull();
        check(state.isWaitingForPermission).isTrue();
        check(state.pendingPermissionCount).equals(1);
        check(notified).isFalse(); // No notification since nothing changed
      });
    });

    group('allowPermission()', () {
      test('allows permission and clears pending', () {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final request = createFakePermissionRequest();
        state.setPendingPermission(request);

        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.allowPermission();

        // Assert
        check(state.pendingPermission).isNull();
        check(notified).isTrue();
      });

      test('does nothing when no pending permission', () {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );

        // Act - should not throw
        state.allowPermission();

        // Assert
        check(state.pendingPermission).isNull();
      });
    });

    group('denyPermission()', () {
      test('denies permission and clears pending', () {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final request = createFakePermissionRequest();
        state.setPendingPermission(request);

        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.denyPermission('User denied');

        // Assert
        check(state.pendingPermission).isNull();
        check(notified).isTrue();
      });

      test('does nothing when no pending permission', () {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );

        // Act - should not throw
        state.denyPermission('Denied');

        // Assert
        check(state.pendingPermission).isNull();
      });
    });

    group('error handling', () {
      test('_handleError adds error entry to conversation', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Act - emit an error through the stream
        session.emitError(Exception('Test error'));

        // Give the stream time to process
        await Future<void>.delayed(Duration.zero);

        // Assert
        final entries = state.data.primaryConversation.entries;
        final errorEntries =
            entries.whereType<TextOutputEntry>().where(
              (e) => e.contentType == 'error',
            );
        check(errorEntries).isNotEmpty();
      });
    });

    group('session end', () {
      test('_handleSessionEnd cleans up state', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Add pending permission
        state.setPendingPermission(createFakePermissionRequest());

        var notified = false;
        state.addListener(() => notified = true);

        // Act - complete the stream (simulates session end)
        session.completeStream();

        // Give the stream time to process
        await Future<void>.delayed(Duration.zero);

        // Assert
        check(state.hasActiveSession).isFalse();
        check(state.pendingPermission).isNull();
        check(notified).isTrue();
      });
    });

    group('message handling', () {
      test('routes messages to handler', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Act - emit a message
        final message = createFakeAssistantMessage(text: 'Hello!');
        session.emitMessage(message);

        // Give the stream time to process
        await Future<void>.delayed(Duration.zero);

        // Assert
        check(handler.handledMessages).isNotEmpty();
        check(handler.lastChatState).equals(state);
      });
    });

    group('permission request handling', () {
      test('sets pending permission when request received', () async {
        // Arrange
        final state = resources.track(
          ChatState.create(name: 'Test', worktreeRoot: '/path'),
        );
        final backend = FakeBackendService();
        final session = FakeClaudeSession();
        backend.sessionToReturn = session;
        final handler = FakeSdkMessageHandler();

        await state.startSession(
          backend: backend,
          messageHandler: handler,
          prompt: 'Hello',
        );

        // Act - emit a permission request
        final request = createFakePermissionRequest(toolName: 'Read');
        session.emitPermissionRequest(request);

        // Give the stream time to process
        await Future<void>.delayed(Duration.zero);

        // Assert
        check(state.pendingPermission).equals(request);
        check(state.isWaitingForPermission).isTrue();
      });
    });
  });
}
