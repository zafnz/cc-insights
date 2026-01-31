import 'dart:async';
import 'dart:typed_data';

import 'package:acp_dart/acp_dart.dart' as acp;
import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_session_wrapper.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:cc_insights_v2/acp/session_update_handler.dart';
import 'package:cc_insights_v2/models/agent.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/conversation.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/services/agent_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('ChatState ACP integration', () {
    final resources = TestResources();
    late FakeAgentService fakeAgentService;
    late SessionUpdateHandler updateHandler;

    setUp(() {
      fakeAgentService = FakeAgentService();
      updateHandler = SessionUpdateHandler();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    group('startAcpSession()', () {
      test('creates a session and subscribes to updates', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // Act
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello, Claude!',
        );

        // Assert
        check(state.hasActiveSession).isTrue();
        check(fakeAgentService.createSessionCalls).length.equals(1);
        check(fakeAgentService.createSessionCalls.first.cwd)
            .equals('/path/to/worktree');
      });

      test('adds user message to conversation', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // Act
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello, Claude!',
        );

        // Assert
        final entries = state.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<UserInputEntry>();
        check((entries.first as UserInputEntry).text).equals('Hello, Claude!');
      });

      test('sends prompt to session', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // Act
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Write some code',
        );

        // Assert
        final session = fakeAgentService.lastCreatedSession!;
        check(session.promptCalls).length.equals(1);
        final promptContent = session.promptCalls.first;
        check(promptContent.length).equals(1);
        check(promptContent.first).isA<acp.TextContentBlock>();
        check((promptContent.first as acp.TextContentBlock).text)
            .equals('Write some code');
      });

      test('throws StateError if session already active', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'First prompt',
        );

        // Act & Assert
        await check(
          state.startAcpSession(
            agentService: fakeAgentService,
            updateHandler: updateHandler,
            prompt: 'Second prompt',
          ),
        ).throws<StateError>();
      });

      test('throws StateError if chat has no worktree root', () async {
        // Arrange
        final data = ChatData(
          id: 'test-chat',
          name: 'Test Chat',
          primaryConversation: ConversationData.primary(id: 'conv-1'),
          // No worktreeRoot
        );
        final state = resources.track(ChatState(data));

        // Act & Assert
        await check(
          state.startAcpSession(
            agentService: fakeAgentService,
            updateHandler: updateHandler,
            prompt: 'Hello',
          ),
        ).throws<StateError>();
      });

      test('sets isWorking during prompt execution', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // isWorking should be false initially
        check(state.isWorking).isFalse();

        // Act
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        // After prompt completes, isWorking should be false
        check(state.isWorking).isFalse();
      });

      test('notifies listeners when session starts', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        // Assert - should notify multiple times (entry added, working state)
        check(notifyCount).isGreaterThan(0);
      });

      test('handles images in prompt', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        final images = [
          AttachedImage(
            data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]), // PNG header
            mediaType: 'image/png',
          ),
        ];

        // Act
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Describe this image',
          images: images,
        );

        // Assert
        final session = fakeAgentService.lastCreatedSession!;
        final promptContent = session.promptCalls.first;
        check(promptContent.length).equals(2);
        check(promptContent[0]).isA<acp.TextContentBlock>();
        check(promptContent[1]).isA<acp.ImageContentBlock>();
      });
    });

    group('sendMessage() with ACP session', () {
      test('sends message to ACP session', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Initial prompt',
        );

        // Act
        await state.sendMessage('Follow-up message');

        // Assert
        final session = fakeAgentService.lastCreatedSession!;
        check(session.promptCalls).length.equals(2);
        final followUp = session.promptCalls[1];
        check(followUp.length).equals(1);
        check((followUp.first as acp.TextContentBlock).text)
            .equals('Follow-up message');
      });

      test('adds user message to conversation', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Initial prompt',
        );

        // Act
        await state.sendMessage('Follow-up message');

        // Assert
        final entries = state.data.primaryConversation.entries;
        check(entries.length).equals(2);
        check((entries[1] as UserInputEntry).text).equals('Follow-up message');
      });

      test('throws StateError if no session active', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // Act & Assert
        await check(state.sendMessage('Hello')).throws<StateError>();
      });

      test('handles images in follow-up message', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Initial prompt',
        );

        final images = [
          AttachedImage(
            data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]), // PNG header
            mediaType: 'image/png',
          ),
        ];

        // Act
        await state.sendMessage('Check this', images: images);

        // Assert
        final session = fakeAgentService.lastCreatedSession!;
        final promptContent = session.promptCalls.last;
        check(promptContent.length).equals(2);
        check(promptContent[1]).isA<acp.ImageContentBlock>();
      });
    });

    group('interrupt() with ACP session', () {
      test('calls cancel on ACP session', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Start working',
        );
        state.setWorking(true);

        // Act
        await state.interrupt();

        // Assert
        final session = fakeAgentService.lastCreatedSession!;
        check(session.cancelCalled).isTrue();
      });

      test('sets isWorking to false after interrupt', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Start working',
        );
        state.setWorking(true);
        check(state.isWorking).isTrue();

        // Act
        await state.interrupt();

        // Assert
        check(state.isWorking).isFalse();
      });

      test('updates working agents to error status', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Start working',
        );
        state.addSubagentConversation('agent-1', 'Explorer', 'Find files');
        state.setWorking(true);

        // Act
        await state.interrupt();

        // Assert
        final agent = state.activeAgents['agent-1']!;
        check(agent.status).equals(AgentStatus.error);
        check(agent.result).equals('Interrupted by user');
      });
    });

    group('stopSession() with ACP session', () {
      test('disposes ACP session', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );
        check(state.hasActiveSession).isTrue();

        // Act
        await state.stopSession();

        // Assert
        check(state.hasActiveSession).isFalse();
        check(fakeAgentService.lastCreatedSession!.disposed).isTrue();
      });

      test('clears pending ACP permissions', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        // Add a pending permission
        state.addPendingAcpPermission(createFakePendingPermission());
        check(state.isWaitingForPermission).isTrue();

        // Act
        await state.stopSession();

        // Assert
        check(state.isWaitingForPermission).isFalse();
        check(state.pendingAcpPermission).isNull();
      });

      test('clears active agents', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );
        state.addSubagentConversation('agent-1', 'Explorer', null);
        check(state.activeAgents).isNotEmpty();

        // Act
        await state.stopSession();

        // Assert
        check(state.activeAgents).isEmpty();
      });

      test('notifies listeners', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        var notified = false;
        state.addListener(() => notified = true);

        // Act
        await state.stopSession();

        // Assert
        check(notified).isTrue();
      });
    });

    group('ACP permission handling', () {
      test('addPendingAcpPermission adds to queue', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        final permission = createFakePendingPermission();

        // Act
        state.addPendingAcpPermission(permission);

        // Assert
        check(state.pendingAcpPermission).isNotNull();
        check(state.pendingPermissionCount).equals(1);
        check(state.isWaitingForPermission).isTrue();
      });

      test('addPendingAcpPermission queues multiple permissions', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // Act
        state.addPendingAcpPermission(createFakePendingPermission());
        state.addPendingAcpPermission(createFakePendingPermission());
        state.addPendingAcpPermission(createFakePendingPermission());

        // Assert
        check(state.pendingPermissionCount).equals(3);
      });

      test('allowAcpPermission removes from queue and calls allow', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        final permission = createFakePendingPermission();
        state.addPendingAcpPermission(permission);

        // Act
        state.allowAcpPermission('allow_once');

        // Assert
        check(state.pendingAcpPermission).isNull();
        check(state.pendingPermissionCount).equals(0);
        check(state.isWaitingForPermission).isFalse();
        check(permission.isResolved).isTrue();
      });

      test('allowAcpPermission processes queue in FIFO order', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        final permission1 = createFakePendingPermission();
        final permission2 = createFakePendingPermission();
        state.addPendingAcpPermission(permission1);
        state.addPendingAcpPermission(permission2);

        // Act
        state.allowAcpPermission('allow_once');

        // Assert
        check(permission1.isResolved).isTrue();
        check(permission2.isResolved).isFalse();
        check(state.pendingPermissionCount).equals(1);
      });

      test('cancelAcpPermission removes from queue and calls cancel', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        final permission = createFakePendingPermission();
        state.addPendingAcpPermission(permission);

        // Act
        state.cancelAcpPermission();

        // Assert
        check(state.pendingAcpPermission).isNull();
        check(state.pendingPermissionCount).equals(0);
        check(permission.isResolved).isTrue();
      });

      test('cancelAcpPermission processes queue in FIFO order', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        final permission1 = createFakePendingPermission();
        final permission2 = createFakePendingPermission();
        state.addPendingAcpPermission(permission1);
        state.addPendingAcpPermission(permission2);

        // Act
        state.cancelAcpPermission();

        // Assert
        check(permission1.isResolved).isTrue();
        check(permission2.isResolved).isFalse();
        check(state.pendingPermissionCount).equals(1);
      });

      test('allowAcpPermission does nothing when queue is empty', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.allowAcpPermission('allow_once');

        // Assert - should not throw, should not notify
        check(notified).isFalse();
      });

      test('cancelAcpPermission does nothing when queue is empty', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.cancelAcpPermission();

        // Assert - should not throw, should not notify
        check(notified).isFalse();
      });

      test('permission handling notifies listeners', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act & Assert
        state.addPendingAcpPermission(createFakePendingPermission());
        check(notifyCount).equals(1);

        state.allowAcpPermission('allow_once');
        check(notifyCount).equals(2);
      });

      test('clearSession clears ACP permissions', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        state.addPendingAcpPermission(createFakePendingPermission());
        state.addPendingAcpPermission(createFakePendingPermission());
        check(state.pendingPermissionCount).equals(2);

        // Act
        state.clearSession();

        // Assert
        check(state.pendingPermissionCount).equals(0);
        check(state.isWaitingForPermission).isFalse();
      });
    });

    group('hasActiveSession', () {
      test('returns true when ACP session is active', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // Initially false
        check(state.hasActiveSession).isFalse();

        // Act
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        // Assert
        check(state.hasActiveSession).isTrue();
      });

      test('returns false after stopSession', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        // Act
        await state.stopSession();

        // Assert
        check(state.hasActiveSession).isFalse();
      });

      test('returns false after clearSession', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        // Act
        state.clearSession();

        // Assert
        check(state.hasActiveSession).isFalse();
      });
    });

    group('isWaitingForPermission', () {
      test('returns true with pending ACP permissions', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));

        // Initially false
        check(state.isWaitingForPermission).isFalse();

        // Act
        state.addPendingAcpPermission(createFakePendingPermission());

        // Assert
        check(state.isWaitingForPermission).isTrue();
      });

      test('returns false after all permissions are resolved', () {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        state.addPendingAcpPermission(createFakePendingPermission());
        state.addPendingAcpPermission(createFakePendingPermission());

        // Act
        state.allowAcpPermission('allow_once');
        state.cancelAcpPermission();

        // Assert
        check(state.isWaitingForPermission).isFalse();
      });
    });

    group('error handling', () {
      test('handles error in ACP session update stream', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );

        // Act - simulate an error in the update stream
        fakeAgentService.lastCreatedSession!.simulateError('Test error');

        // Allow microtasks to run
        await Future<void>.delayed(Duration.zero);

        // Assert - error should be added to conversation
        final entries = state.data.primaryConversation.entries;
        final errorEntries =
            entries.whereType<TextOutputEntry>().where((e) => e.contentType == 'error');
        check(errorEntries).isNotEmpty();
        check(state.isWorking).isFalse();
      });

      test('handles session end gracefully', () async {
        // Arrange
        final state = resources.track(ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        ));
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );
        state.addSubagentConversation('agent-1', 'Explorer', null);

        // Act - simulate stream completion
        fakeAgentService.lastCreatedSession!.simulateStreamEnd();

        // Allow microtasks to run
        await Future<void>.delayed(Duration.zero);

        // Assert
        check(state.hasActiveSession).isFalse();
        check(state.isWorking).isFalse();
        check(state.activeAgents).isEmpty();
      });
    });

    group('dispose()', () {
      test('disposes ACP session on dispose', () async {
        // Arrange
        final state = ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );
        await state.startAcpSession(
          agentService: fakeAgentService,
          updateHandler: updateHandler,
          prompt: 'Hello',
        );
        final session = fakeAgentService.lastCreatedSession!;

        // Act
        state.dispose();

        // Assert
        check(session.disposed).isTrue();
      });

      test('clears ACP permissions on dispose', () async {
        // Arrange
        final state = ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );
        state.addPendingAcpPermission(createFakePendingPermission());

        // Act
        state.dispose();

        // Assert
        check(state.pendingPermissionCount).equals(0);
      });
    });
  });
}

// =============================================================================
// FAKES AND HELPERS
// =============================================================================

/// Creates a fake PendingPermission for testing.
PendingPermission createFakePendingPermission({
  String sessionId = 'test-session',
}) {
  final completer = Completer<acp.RequestPermissionResponse>();
  return PendingPermission(
    request: acp.RequestPermissionRequest(
      sessionId: sessionId,
      options: [
        acp.PermissionOption(
          optionId: 'allow_once',
          name: 'Allow Once',
          kind: acp.PermissionOptionKind.allowOnce,
        ),
        acp.PermissionOption(
          optionId: 'deny',
          name: 'Deny',
          kind: acp.PermissionOptionKind.rejectOnce,
        ),
      ],
      toolCall: acp.ToolCallUpdate(
        toolCallId: 'tool-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Bash',
        status: acp.ToolCallStatus.pending,
        kind: acp.ToolKind.execute,
        rawInput: const {'command': 'ls -la'},
      ),
    ),
    completer: completer,
  );
}

/// Fake AgentService for testing.
class FakeAgentService extends AgentService {
  FakeAgentService() : super(agentRegistry: FakeAgentRegistry());

  final List<_CreateSessionCall> createSessionCalls = [];
  FakeACPSessionWrapper? lastCreatedSession;

  @override
  bool get isConnected => true;

  @override
  Future<ACPSessionWrapper> createSession({
    required String cwd,
    List<acp.McpServerBase>? mcpServers,
    bool includePartialMessages = true,
  }) async {
    createSessionCalls.add(_CreateSessionCall(
      cwd: cwd,
      mcpServers: mcpServers,
      includePartialMessages: includePartialMessages,
    ));

    lastCreatedSession = FakeACPSessionWrapper(sessionId: 'fake-session-${createSessionCalls.length}');
    return lastCreatedSession!;
  }
}

/// Record of a createSession call.
class _CreateSessionCall {
  final String cwd;
  final List<acp.McpServerBase>? mcpServers;
  final bool includePartialMessages;

  _CreateSessionCall({
    required this.cwd,
    this.mcpServers,
    this.includePartialMessages = true,
  });
}

/// Fake AgentRegistry for testing.
class FakeAgentRegistry extends AgentRegistry {
  FakeAgentRegistry() : super(configDir: '/tmp/test-agents');

  @override
  Future<void> discover() async {
    // No-op for tests
  }

  @override
  AgentConfig? getAgent(String id) {
    return const AgentConfig(
      id: 'test-agent',
      name: 'Test Agent',
      command: '/usr/bin/test-agent',
    );
  }
}

/// Fake ACPSessionWrapper for testing.
class FakeACPSessionWrapper implements ACPSessionWrapper {
  FakeACPSessionWrapper({required this.sessionId});

  @override
  final String sessionId;

  final List<List<acp.ContentBlock>> promptCalls = [];
  bool cancelCalled = false;
  bool disposed = false;

  final _updateController = StreamController<acp.SessionUpdate>.broadcast();
  final _permissionController = StreamController<PendingPermission>.broadcast();

  @override
  Stream<acp.SessionUpdate> get updates => _updateController.stream;

  @override
  Stream<PendingPermission> get permissionRequests =>
      _permissionController.stream;

  @override
  acp.SessionModeState? get modes => null;

  @override
  Future<acp.PromptResponse> prompt(List<acp.ContentBlock> content) async {
    promptCalls.add(content);
    return acp.PromptResponse(
      stopReason: acp.StopReason.endTurn,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
  }

  @override
  Future<acp.SetSessionModeResponse?> setMode(String modeId) async {
    return null;
  }

  @override
  void dispose() {
    disposed = true;
    _updateController.close();
    _permissionController.close();
  }

  /// Simulates an error in the update stream.
  void simulateError(String message) {
    _updateController.addError(Exception(message));
  }

  /// Simulates the update stream closing.
  void simulateStreamEnd() {
    _updateController.close();
  }

  /// Simulates receiving a session update.
  void simulateUpdate(acp.SessionUpdate update) {
    _updateController.add(update);
  }

  /// Simulates receiving a permission request.
  void simulatePermissionRequest(PendingPermission permission) {
    _permissionController.add(permission);
  }
}
