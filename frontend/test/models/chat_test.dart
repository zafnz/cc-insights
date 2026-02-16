import 'dart:async';

import 'package:cc_insights_v2/models/agent.dart';
import 'package:cc_insights_v2/models/agent_config.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/models/conversation.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatModelCatalog.defaultForBackend', () {
    test('resolves preferred model for Claude', () {
      final model = ChatModelCatalog.defaultForBackend(
        sdk.BackendType.directCli,
        'haiku',
      );
      check(model).equals(
        const ChatModel(
          id: 'haiku',
          label: 'Haiku',
          backend: sdk.BackendType.directCli,
        ),
      );
    });

    test('falls back to first model for unknown', () {
      final model = ChatModelCatalog.defaultForBackend(
        sdk.BackendType.directCli,
        'unknown',
      );
      check(model).equals(ChatModelCatalog.claudeModels.first);
    });
  });

  group('PermissionMode.fromApiName', () {
    test('resolves default', () {
      check(
        PermissionMode.fromApiName('default'),
      ).equals(PermissionMode.defaultMode);
    });

    test('resolves acceptEdits', () {
      check(
        PermissionMode.fromApiName('acceptEdits'),
      ).equals(PermissionMode.acceptEdits);
    });

    test('resolves plan', () {
      check(PermissionMode.fromApiName('plan')).equals(PermissionMode.plan);
    });

    test('resolves bypassPermissions', () {
      check(
        PermissionMode.fromApiName('bypassPermissions'),
      ).equals(PermissionMode.bypass);
    });

    test('falls back to defaultMode for unknown', () {
      check(
        PermissionMode.fromApiName('unknown'),
      ).equals(PermissionMode.defaultMode);
    });
  });

  group('Chat canonical type compatibility', () {
    test('supports both Chat and Chat constructors', () {
      final canonical = Chat.create(name: 'Canonical', worktreeRoot: '/tmp');
      final legacy = Chat.create(name: 'Legacy', worktreeRoot: '/tmp');

      check(canonical).isA<Chat>();
      check(canonical).isA<Chat>();
      check(legacy).isA<Chat>();
      check(legacy).isA<Chat>();
    });
  });

  group('Chat default model/permission from RuntimeConfig', () {
    setUp(() {
      RuntimeConfig.resetForTesting();
      RuntimeConfig.initialize([]);
    });

    test('uses RuntimeConfig defaults from default agent', () {
      // Default agent is 'claude-default' with defaultModel='opus'.
      final chat = Chat(ChatData.create(name: 'Test', worktreeRoot: '/tmp'));
      check(chat.settings.model).equals(
        const ChatModel(
          id: 'opus',
          label: 'Opus',
          backend: sdk.BackendType.directCli,
        ),
      );
      check(chat.settings.permissionMode).equals(PermissionMode.defaultMode);
    });

    test('picks up non-default agent model and permission', () {
      RuntimeConfig.instance.agents = [
        const AgentConfig(
          id: 'test-agent',
          name: 'Test',
          driver: 'claude',
          defaultModel: 'haiku',
          defaultPermissions: 'default',
        ),
      ];
      RuntimeConfig.instance.defaultAgentId = 'test-agent';
      RuntimeConfig.instance.defaultPermissionMode = 'acceptEdits';

      final chat = Chat(ChatData.create(name: 'Test', worktreeRoot: '/tmp'));
      check(chat.settings.model).equals(
        const ChatModel(
          id: 'haiku',
          label: 'Haiku',
          backend: sdk.BackendType.directCli,
        ),
      );
      check(chat.settings.permissionMode).equals(PermissionMode.acceptEdits);
    });
  });

  group('ChatData', () {
    group('create() factory', () {
      test('generates unique ID based on timestamp', () {
        // Arrange & Act
        final chat = ChatData.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );

        // Assert
        check(chat.id).startsWith('chat-');
        check(chat.name).equals('Test Chat');
        check(chat.worktreeRoot).equals('/path/to/worktree');
      });

      test('creates primary conversation with matching ID', () {
        // Arrange & Act
        final chat = ChatData.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );

        // Assert
        check(chat.primaryConversation.id).startsWith('conv-primary-chat-');
        check(chat.primaryConversation.isPrimary).isTrue();
      });

      test('creates empty subagentConversations map', () {
        // Arrange & Act
        final chat = ChatData.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );

        // Assert
        check(chat.subagentConversations).isEmpty();
      });

      test('sets createdAt to current time', () {
        // Arrange
        final before = DateTime.now();

        // Act
        final chat = ChatData.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );
        final after = DateTime.now();

        // Assert
        final createdAt = chat.createdAt;
        check(createdAt).isNotNull();
        check(createdAt!.isAfter(before) || createdAt == before).isTrue();
        check(createdAt.isBefore(after) || createdAt == after).isTrue();
      });
    });

    group('allConversations', () {
      test('returns primary first when no subagents', () {
        // Arrange
        final chat = ChatData.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );

        // Act
        final conversations = chat.allConversations;

        // Assert
        check(conversations.length).equals(1);
        check(conversations.first.isPrimary).isTrue();
      });

      test('returns primary first followed by subagents', () {
        // Arrange
        const primaryConv = ConversationData.primary(id: 'conv-primary');
        const subagentConv1 = ConversationData.subagent(
          id: 'conv-sub-1',
          label: 'Explore',
        );
        const subagentConv2 = ConversationData.subagent(
          id: 'conv-sub-2',
          label: 'Plan',
        );

        final chat = ChatData(
          id: 'chat-1',
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
          createdAt: DateTime.now(),
          primaryConversation: primaryConv,
          subagentConversations: {
            'conv-sub-1': subagentConv1,
            'conv-sub-2': subagentConv2,
          },
        );

        // Act
        final conversations = chat.allConversations;

        // Assert
        check(conversations.length).equals(3);
        check(conversations.first.isPrimary).isTrue();
        check(conversations[0].id).equals('conv-primary');
      });
    });

    group('copyWith()', () {
      test('preserves unchanged fields', () {
        // Arrange
        final original = ChatData.create(
          name: 'Original',
          worktreeRoot: '/path/to/worktree',
        );

        // Act
        final modified = original.copyWith(name: 'Modified');

        // Assert
        check(modified.id).equals(original.id);
        check(modified.name).equals('Modified');
        check(modified.worktreeRoot).equals(original.worktreeRoot);
        check(modified.createdAt).equals(original.createdAt);
        check(
          modified.primaryConversation,
        ).equals(original.primaryConversation);
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        final time = DateTime(2025, 1, 27);
        const primaryConv = ConversationData.primary(id: 'conv-1');
        final chat1 = ChatData(
          id: 'chat-1',
          name: 'Chat',
          worktreeRoot: '/path',
          createdAt: time,
          primaryConversation: primaryConv,
        );
        final chat2 = ChatData(
          id: 'chat-1',
          name: 'Chat',
          worktreeRoot: '/path',
          createdAt: time,
          primaryConversation: primaryConv,
        );

        // Act & Assert
        check(chat1 == chat2).isTrue();
        check(chat1.hashCode).equals(chat2.hashCode);
      });
    });
  });

  group('Chat', () {
    group('create() factory', () {
      test('creates state with new ChatData', () {
        // Arrange & Act
        final state = Chat.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );

        // Assert
        check(state.data.name).equals('Test Chat');
        check(state.data.worktreeRoot).equals('/path/to/worktree');
        check(state.session.hasActiveSession).isFalse();
        check(state.agents.activeAgents).isEmpty();
      });
    });

    group('rename()', () {
      test('updates name and notifies listeners', () {
        // Arrange
        final state = Chat.create(name: 'Original', worktreeRoot: '/path');
        var notified = false;
        state.conversations.addListener(() => notified = true);

        // Act
        state.conversations.rename('New Name');

        // Assert
        check(state.data.name).equals('New Name');
        check(notified).isTrue();
      });
    });

    group('addSubagentConversation()', () {
      test('creates conversation and agent', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        var notified = false;
        state.conversations.addListener(() => notified = true);

        // Act
        state.conversations.addSubagentConversation(
          'sdk-agent-123',
          'Explore',
          'Find all test files',
        );

        // Assert
        check(state.data.subagentConversations.length).equals(1);
        check(state.agents.activeAgents.length).equals(1);
        check(state.agents.activeAgents['sdk-agent-123']).isNotNull();
        check(notified).isTrue();

        final conversation = state.data.subagentConversations.values.first;
        check(conversation.label).equals('Explore');
        check(conversation.taskDescription).equals('Find all test files');

        final agent = state.agents.activeAgents['sdk-agent-123']!;
        check(agent.status).equals(AgentStatus.working);
        check(agent.conversationId).equals(conversation.id);
      });

      test('creates multiple subagent conversations', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        // Act - add delay to ensure different timestamp-based IDs
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        await Future<void>.delayed(const Duration(milliseconds: 2));
        state.conversations.addSubagentConversation(
          'agent-2',
          'Plan',
          'Make a plan',
        );

        // Assert
        check(state.data.subagentConversations.length).equals(2);
        check(state.agents.activeAgents.length).equals(2);
      });
    });

    group('selectConversation()', () {
      test('changes selected conversation', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        final subagentConv = state.data.subagentConversations.values.first;
        var notified = false;
        state.conversations.addListener(() => notified = true);

        // Act
        state.conversations.selectConversation(subagentConv.id);

        // Assert
        check(
          state.conversations.selectedConversation.id,
        ).equals(subagentConv.id);
        check(state.conversations.isInputEnabled).isFalse();
        check(notified).isTrue();
      });

      test('selects primary conversation when null', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        final subagentConv = state.data.subagentConversations.values.first;
        state.conversations.selectConversation(subagentConv.id);

        // Act
        state.conversations.selectConversation(null);

        // Assert
        check(state.conversations.selectedConversation.isPrimary).isTrue();
        check(state.conversations.isInputEnabled).isTrue();
      });

      test('does not notify if same conversation selected', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        var notifyCount = 0;
        state.conversations.addListener(() => notifyCount++);

        // Act
        state.conversations.selectConversation(null);
        state.conversations.selectConversation(null);

        // Assert
        check(notifyCount).equals(0);
      });
    });

    group('isInputEnabled', () {
      test('returns true for primary conversation', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        // Assert
        check(state.conversations.isInputEnabled).isTrue();
      });

      test('returns false for subagent conversation', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        final subagentConv = state.data.subagentConversations.values.first;
        state.conversations.selectConversation(subagentConv.id);

        // Assert
        check(state.conversations.isInputEnabled).isFalse();
      });
    });

    group('updateAgent()', () {
      test('updates agent status', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        var notified = false;
        state.agents.addListener(() => notified = true);

        // Act
        state.agents.updateAgent(
          AgentStatus.completed,
          'agent-1',
          result: 'Done',
        );

        // Assert
        final agent = state.agents.activeAgents['agent-1']!;
        check(agent.status).equals(AgentStatus.completed);
        check(agent.result).equals('Done');
        check(notified).isTrue();
      });

      test('does nothing for unknown agent', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        var notified = false;
        state.agents.addListener(() => notified = true);

        // Act
        state.agents.updateAgent(AgentStatus.completed, 'unknown-agent');

        // Assert
        check(notified).isFalse();
      });
    });

    group('addOutputEntry()', () {
      test('adds entry to primary conversation', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        final entry = UserInputEntry(timestamp: DateTime.now(), text: 'Hello');
        var notified = false;
        state.conversations.addListener(() => notified = true);

        // Act
        state.conversations.addOutputEntry(
          state.data.primaryConversation.id,
          entry,
        );

        // Assert
        check(state.data.primaryConversation.entries.length).equals(1);
        check(
          (state.data.primaryConversation.entries.first as UserInputEntry).text,
        ).equals('Hello');
        check(notified).isTrue();
      });

      test('adds entry to subagent conversation', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        final subagentConv = state.data.subagentConversations.values.first;
        final entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'Working...',
          contentType: 'text',
        );

        // Act
        state.conversations.addOutputEntry(subagentConv.id, entry);

        // Assert
        final updatedConv = state.data.subagentConversations[subagentConv.id]!;
        check(updatedConv.entries.length).equals(1);
        check(
          (updatedConv.entries.first as TextOutputEntry).text,
        ).equals('Working...');
      });
    });

    group('session management', () {
      test('setHasActiveSessionForTesting activates session', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        var notified = false;
        state.session.addListener(() => notified = true);

        // Act
        state.session.setHasActiveSessionForTesting(true);

        // Assert
        check(state.session.hasActiveSession).isTrue();
        check(notified).isTrue();
      });

      test('clearSession deactivates session and clears agents', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setHasActiveSessionForTesting(true);
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        var notified = false;
        state.session.addListener(() => notified = true);

        // Act
        state.session.clear();

        // Assert
        check(state.session.hasActiveSession).isFalse();
        check(state.agents.activeAgents).isEmpty();
        check(notified).isTrue();
      });
    });

    group('resetSession()', () {
      test(
        'clears session, sessionId, context, and adds marker entry',
        () async {
          // Arrange
          final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
          state.session.setHasActiveSessionForTesting(true);
          state.session.setLastSessionIdFromRestore('session-123');
          state.session.setWorking(true);
          state.session.setCompacting(true);
          state.conversations.addSubagentConversation(
            'agent-1',
            'Explore',
            null,
          );
          var notifyCount = 0;
          state.session.addListener(() => notifyCount++);

          // Act
          await state.session.reset();

          // Assert
          check(state.session.hasActiveSession).isFalse();
          check(state.session.lastSessionId).isNull();
          check(state.agents.activeAgents).isEmpty();
          check(state.session.isWorking).isFalse();
          check(state.session.isCompacting).isFalse();
          check(notifyCount).isGreaterThan(0);

          // Should have added a ContextClearedEntry
          final entries = state.data.primaryConversation.entries;
          check(entries).isNotEmpty();
          check(entries.last).isA<ContextClearedEntry>();
        },
      );

      test('works when no session is active', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        // Act
        await state.session.reset();

        // Assert
        check(state.session.hasActiveSession).isFalse();
        check(state.session.lastSessionId).isNull();

        final entries = state.data.primaryConversation.entries;
        check(entries).length.equals(1);
        check(entries.last).isA<ContextClearedEntry>();
      });
    });

    group('interrupt()', () {
      test('sets isWorking to false', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setHasActiveSessionForTesting(true);
        state.session.setWorking(true);
        check(state.session.isWorking).isTrue();

        // Act
        await state.session.interrupt();

        // Assert
        check(state.session.isWorking).isFalse();
      });

      test('updates all working agents to error status', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setHasActiveSessionForTesting(true);
        state.conversations.addSubagentConversation(
          'agent-1',
          'Explore',
          'Task 1',
        );
        state.conversations.addSubagentConversation(
          'agent-2',
          'Plan',
          'Task 2',
        );
        state.conversations.addSubagentConversation(
          'agent-3',
          'general',
          'Task 3',
        );

        // Verify all agents are working
        check(
          state.agents.activeAgents['agent-1']!.status,
        ).equals(AgentStatus.working);
        check(
          state.agents.activeAgents['agent-2']!.status,
        ).equals(AgentStatus.working);
        check(
          state.agents.activeAgents['agent-3']!.status,
        ).equals(AgentStatus.working);

        // Act
        await state.session.interrupt();

        // Assert - all agents should be in error state with "Interrupted" message
        check(
          state.agents.activeAgents['agent-1']!.status,
        ).equals(AgentStatus.error);
        check(
          state.agents.activeAgents['agent-1']!.result,
        ).equals('Interrupted by user');
        check(
          state.agents.activeAgents['agent-2']!.status,
        ).equals(AgentStatus.error);
        check(
          state.agents.activeAgents['agent-2']!.result,
        ).equals('Interrupted by user');
        check(
          state.agents.activeAgents['agent-3']!.status,
        ).equals(AgentStatus.error);
        check(
          state.agents.activeAgents['agent-3']!.result,
        ).equals('Interrupted by user');
      });

      test('does not modify already completed agents', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setHasActiveSessionForTesting(true);
        state.conversations.addSubagentConversation(
          'agent-1',
          'Explore',
          'Task 1',
        );
        state.conversations.addSubagentConversation(
          'agent-2',
          'Plan',
          'Task 2',
        );

        // Mark agent-1 as completed before interrupt
        state.agents.updateAgent(
          AgentStatus.completed,
          'agent-1',
          result: 'Completed successfully',
        );

        check(
          state.agents.activeAgents['agent-1']!.status,
        ).equals(AgentStatus.completed);
        check(
          state.agents.activeAgents['agent-2']!.status,
        ).equals(AgentStatus.working);

        // Act
        await state.session.interrupt();

        // Assert - agent-1 should still be completed, agent-2 should be interrupted
        check(
          state.agents.activeAgents['agent-1']!.status,
        ).equals(AgentStatus.completed);
        check(
          state.agents.activeAgents['agent-1']!.result,
        ).equals('Completed successfully');
        check(
          state.agents.activeAgents['agent-2']!.status,
        ).equals(AgentStatus.error);
        check(
          state.agents.activeAgents['agent-2']!.result,
        ).equals('Interrupted by user');
      });

      test('notifies listeners', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setHasActiveSessionForTesting(true);
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        var notified = false;
        state.session.addListener(() => notified = true);

        // Act
        await state.session.interrupt();

        // Assert
        check(notified).isTrue();
      });

      test('does nothing when no session is active', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setWorking(true);
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);
        var notified = false;
        state.session.addListener(() => notified = true);

        // Act
        await state.session.interrupt();

        // Assert - nothing should change
        check(state.session.isWorking).isTrue();
        check(
          state.agents.activeAgents['agent-1']!.status,
        ).equals(AgentStatus.working);
        check(notified).isFalse();
      });
    });

    group('dispose()', () {
      test('clears session and agents', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setHasActiveSessionForTesting(true);
        state.conversations.addSubagentConversation('agent-1', 'Explore', null);

        // Act
        state.dispose();

        // Assert
        check(state.session.hasActiveSession).isFalse();
        check(state.agents.activeAgents).isEmpty();
      });
    });

    group('lastSessionId', () {
      test('returns null by default', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        // Assert
        check(state.session.lastSessionId).isNull();
      });

      test('setLastSessionIdFromRestore sets the session ID', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        // Act
        state.session.setLastSessionIdFromRestore('session-123');

        // Assert
        check(state.session.lastSessionId).equals('session-123');
      });

      test('setLastSessionIdFromRestore does not notify listeners', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        var notified = false;
        state.session.addListener(() => notified = true);

        // Act
        state.session.setLastSessionIdFromRestore('session-123');

        // Assert
        check(notified).isFalse();
      });

      test('setLastSessionIdFromRestore can clear the session ID', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setLastSessionIdFromRestore('session-123');

        // Act
        state.session.setLastSessionIdFromRestore(null);

        // Assert
        check(state.session.lastSessionId).isNull();
      });
    });

    group('initPersistence', () {
      test('accepts projectRoot parameter', () async {
        // Arrange
        final state = Chat.create(
          name: 'Test Chat',
          worktreeRoot: '/path/to/worktree',
        );
        state.persistence.persistenceService = _FakePersistenceService();

        // Act - should not throw
        await state.persistence.initPersistence(
          'project-123',
          projectRoot: '/path/to/project',
        );

        // Assert
        check(state.persistence.projectId).equals('project-123');
      });

      test('sets projectId when initialized', () async {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.persistence.persistenceService = _FakePersistenceService();

        // Act
        await state.persistence.initPersistence('test-project-id');

        // Assert
        check(state.persistence.projectId).equals('test-project-id');
      });
    });

    group('session ID persistence', () {
      test(
        'does not persist session ID when persistence not initialized',
        () async {
          // Arrange
          final fakePersistence = _FakePersistenceService();
          final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
          state.persistence.persistenceService = fakePersistence;
          // Note: intentionally NOT calling initPersistence

          // Act - manually set session ID to simulate session update
          state.session.setLastSessionIdFromRestore('session-123');

          // Assert
          check(fakePersistence.updateChatSessionIdCalls).isEmpty();
        },
      );
    });

    group('persistence coordinator', () {
      Future<void> waitFor(
        bool Function() condition, {
        Duration timeout = const Duration(seconds: 2),
      }) async {
        final stopwatch = Stopwatch()..start();
        while (!condition()) {
          if (stopwatch.elapsed > timeout) {
            fail('Timed out waiting for condition');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      test('retries append writes after transient failures', () async {
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        addTearDown(state.dispose);
        final fakePersistence = _FakePersistenceService()
          ..appendFailuresBeforeSuccess = 2;
        state.persistence.persistenceService = fakePersistence;
        await state.persistence.initPersistence(
          'project-123',
          projectRoot: '/project-root',
        );

        state.conversations.addEntry(
          UserInputEntry(timestamp: DateTime.now(), text: 'hello'),
        );

        await waitFor(() => fakePersistence.appendChatEntryAttempts >= 3);
        check(fakePersistence.appendChatEntryAttempts).equals(3);
        check(fakePersistence.appendChatEntryCalls.length).equals(1);
      });

      test('serializes index writes for consecutive renames', () async {
        final state = Chat.create(
          name: 'Original',
          worktreeRoot: '/path/to/worktree',
        );
        addTearDown(state.dispose);
        final fakePersistence = _FakePersistenceService()
          ..renameDelay = const Duration(milliseconds: 40);
        state.persistence.persistenceService = fakePersistence;
        await state.persistence.initPersistence(
          'project-123',
          projectRoot: '/path/to/project',
        );

        state.conversations.rename('First Name');
        state.conversations.rename('Second Name');

        await waitFor(() => fakePersistence.renameChatInIndexCalls.length == 2);
        check(fakePersistence.maxConcurrentRenameCalls).equals(1);
        check(
          fakePersistence.renameChatInIndexCalls.map((c) => c.newName).toList(),
        ).deepEquals(['First Name', 'Second Name']);
      });

      test('retries index writes after transient failures', () async {
        final state = Chat.create(
          name: 'Original',
          worktreeRoot: '/path/to/worktree',
        );
        addTearDown(state.dispose);
        final fakePersistence = _FakePersistenceService()
          ..renameFailuresBeforeSuccess = 2;
        state.persistence.persistenceService = fakePersistence;
        await state.persistence.initPersistence(
          'project-123',
          projectRoot: '/path/to/project',
        );

        state.conversations.rename('Renamed');

        await waitFor(() => fakePersistence.renameChatInIndexAttempts >= 3);
        check(fakePersistence.renameChatInIndexAttempts).equals(3);
        check(fakePersistence.renameChatInIndexCalls.length).equals(1);
        check(
          fakePersistence.renameChatInIndexCalls.single.newName,
        ).equals('Renamed');
      });
    });

    group('concurrent permission requests', () {
      /// Creates a fake PermissionRequest for testing.
      sdk.PermissionRequest createFakeRequest({
        required String id,
        String sessionId = 'test-session',
        String toolName = 'Bash',
        Map<String, dynamic> toolInput = const {'command': 'ls'},
      }) {
        final completer = Completer<sdk.PermissionResponse>();
        return sdk.PermissionRequest(
          id: id,
          sessionId: sessionId,
          toolName: toolName,
          toolInput: toolInput,
          completer: completer,
        );
      }

      test('queues multiple concurrent permission requests', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        final request1 = createFakeRequest(id: 'req-1', toolName: 'Read');
        final request2 = createFakeRequest(id: 'req-2', toolName: 'Write');
        final request3 = createFakeRequest(id: 'req-3', toolName: 'Bash');

        // Act - simulate three permission requests arriving concurrently
        state.permissions.add(request1);
        state.permissions.add(request2);
        state.permissions.add(request3);

        // Assert - all requests should be queued
        check(state.permissions.pendingPermissionCount).equals(3);
        // First request should be the current one
        check(state.permissions.pendingPermission?.id).equals('req-1');
      });

      test('processes permission requests in FIFO order', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        final request1 = createFakeRequest(id: 'req-1', toolName: 'Read');
        final request2 = createFakeRequest(id: 'req-2', toolName: 'Write');

        state.permissions.add(request1);
        state.permissions.add(request2);

        // Act - allow the first request
        state.permissions.allow();

        // Assert - second request should now be current
        check(state.permissions.pendingPermission?.id).equals('req-2');
        check(state.permissions.pendingPermissionCount).equals(1);
      });

      test('handles allow then processes next in queue', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        final request1 = createFakeRequest(id: 'req-1', toolName: 'Read');
        final request2 = createFakeRequest(id: 'req-2', toolName: 'Write');
        final request3 = createFakeRequest(id: 'req-3', toolName: 'Bash');

        state.permissions.add(request1);
        state.permissions.add(request2);
        state.permissions.add(request3);

        // Act & Assert - process all three
        check(state.permissions.pendingPermission?.id).equals('req-1');
        state.permissions.allow();

        check(state.permissions.pendingPermission?.id).equals('req-2');
        state.permissions.allow();

        check(state.permissions.pendingPermission?.id).equals('req-3');
        state.permissions.allow();

        check(state.permissions.pendingPermission).isNull();
        check(state.permissions.pendingPermissionCount).equals(0);
      });

      test('handles deny then processes next in queue', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        final request1 = createFakeRequest(id: 'req-1', toolName: 'Read');
        final request2 = createFakeRequest(id: 'req-2', toolName: 'Write');

        state.permissions.add(request1);
        state.permissions.add(request2);

        // Act - deny the first request
        state.permissions.deny('Not allowed');

        // Assert - second request should now be current
        check(state.permissions.pendingPermission?.id).equals('req-2');
        check(state.permissions.pendingPermissionCount).equals(1);
      });

      test('clears all queued permissions on session clear', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        final request1 = createFakeRequest(id: 'req-1');
        final request2 = createFakeRequest(id: 'req-2');

        state.permissions.add(request1);
        state.permissions.add(request2);
        check(state.permissions.pendingPermissionCount).equals(2);

        // Act
        state.session.clear();

        // Assert
        check(state.permissions.pendingPermission).isNull();
        check(state.permissions.pendingPermissionCount).equals(0);
      });

      test('isWaitingForPermission is true when queue is not empty', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');

        // Assert - initially false
        check(state.permissions.isWaitingForPermission).isFalse();

        // Act - add request
        final request = createFakeRequest(id: 'req-1');
        state.permissions.add(request);

        // Assert - now true
        check(state.permissions.isWaitingForPermission).isTrue();

        // Act - allow request
        state.permissions.allow();

        // Assert - back to false
        check(state.permissions.isWaitingForPermission).isFalse();
      });

      test('notifies listeners when permission queue changes', () {
        // Arrange
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        var notifyCount = 0;
        state.permissions.addListener(() => notifyCount++);

        final request1 = createFakeRequest(id: 'req-1');
        final request2 = createFakeRequest(id: 'req-2');

        // Act & Assert
        state.permissions.add(request1);
        check(notifyCount).equals(1);

        state.permissions.add(request2);
        check(notifyCount).equals(2);

        state.permissions.allow();
        check(notifyCount).equals(3);

        state.permissions.deny('denied');
        check(notifyCount).equals(4);
      });
    });

    group('working stopwatch pauses during permission requests', () {
      /// Creates a fake PermissionRequest for testing.
      sdk.PermissionRequest createFakeRequest({
        required String id,
        String sessionId = 'test-session',
        String toolName = 'Bash',
        Map<String, dynamic> toolInput = const {'command': 'ls'},
      }) {
        final completer = Completer<sdk.PermissionResponse>();
        return sdk.PermissionRequest(
          id: id,
          sessionId: sessionId,
          toolName: toolName,
          toolInput: toolInput,
          completer: completer,
        );
      }

      test('pauses stopwatch when first permission arrives while working', () {
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setWorking(true);
        check(state.session.workingStopwatch).isNotNull();
        check(state.session.workingStopwatch!.isRunning).isTrue();

        // Act - permission request arrives
        final request = createFakeRequest(id: 'req-1');
        state.permissions.add(request);

        // Assert - stopwatch should be paused
        check(state.session.workingStopwatch).isNotNull();
        check(state.session.workingStopwatch!.isRunning).isFalse();
      });

      test('resumes stopwatch when last permission is allowed', () {
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setWorking(true);

        final request = createFakeRequest(id: 'req-1');
        state.permissions.add(request);
        check(state.session.workingStopwatch!.isRunning).isFalse();

        // Act - allow the permission
        state.permissions.allow();

        // Assert - stopwatch should be running again
        check(state.session.workingStopwatch).isNotNull();
        check(state.session.workingStopwatch!.isRunning).isTrue();
      });

      test('resumes stopwatch when last permission is denied', () {
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setWorking(true);

        final request = createFakeRequest(id: 'req-1');
        state.permissions.add(request);
        check(state.session.workingStopwatch!.isRunning).isFalse();

        // Act - deny the permission
        state.permissions.deny('Not allowed');

        // Assert - stopwatch should be running again
        check(state.session.workingStopwatch).isNotNull();
        check(state.session.workingStopwatch!.isRunning).isTrue();
      });

      test(
        'stays paused when one permission is resolved but others remain',
        () {
          final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
          state.session.setWorking(true);

          final request1 = createFakeRequest(id: 'req-1', toolName: 'Read');
          final request2 = createFakeRequest(id: 'req-2', toolName: 'Write');
          state.permissions.add(request1);
          state.permissions.add(request2);
          check(state.session.workingStopwatch!.isRunning).isFalse();

          // Act - allow the first permission
          state.permissions.allow();

          // Assert - still paused because req-2 is pending
          check(state.session.workingStopwatch!.isRunning).isFalse();

          // Act - allow the second permission
          state.permissions.allow();

          // Assert - now resumed
          check(state.session.workingStopwatch!.isRunning).isTrue();
        },
      );

      test('resumes stopwatch when permission times out and is removed', () {
        final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
        state.session.setWorking(true);

        // Create request with toolUseId set (used by removePendingPermissionByToolUseId)
        final completer = Completer<sdk.PermissionResponse>();
        final request = sdk.PermissionRequest(
          id: 'req-1',
          sessionId: 'test-session',
          toolName: 'Bash',
          toolInput: const {'command': 'ls'},
          toolUseId: 'tool-use-1',
          completer: completer,
        );
        state.permissions.add(request);
        check(state.session.workingStopwatch!.isRunning).isFalse();

        // Act - permission times out (removed by toolUseId)
        state.permissions.removeByToolUseId('tool-use-1');

        // Assert - stopwatch should be running again
        check(state.session.workingStopwatch).isNotNull();
        check(state.session.workingStopwatch!.isRunning).isTrue();
      });

      test(
        'does not pause stopwatch when permission arrives while not working',
        () {
          final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
          // Not working - no stopwatch
          check(state.session.workingStopwatch).isNull();

          final request = createFakeRequest(id: 'req-1');
          state.permissions.add(request);

          // Assert - no stopwatch to pause
          check(state.session.workingStopwatch).isNull();
        },
      );

      test(
        'does not resume stopwatch after setWorking(false) during permission',
        () {
          final state = Chat.create(name: 'Test Chat', worktreeRoot: '/path');
          state.session.setWorking(true);

          final request = createFakeRequest(id: 'req-1');
          state.permissions.add(request);
          check(state.session.workingStopwatch!.isRunning).isFalse();

          // Turn completes while waiting for permission
          state.session.setWorking(false);
          check(state.session.workingStopwatch).isNull();

          // Allow the permission
          state.permissions.allow();

          // Assert - stopwatch should NOT be resumed since we're no longer working
          check(state.session.workingStopwatch).isNull();
          check(state.session.isWorking).isFalse();
        },
      );
    });
  });
}

/// Fake PersistenceService for testing that tracks method calls.
class _FakePersistenceService extends PersistenceService {
  final List<_UpdateChatSessionIdCall> updateChatSessionIdCalls = [];
  final List<_AppendChatEntryCall> appendChatEntryCalls = [];
  final List<_RenameChatInIndexCall> renameChatInIndexCalls = [];

  int appendChatEntryAttempts = 0;
  int appendFailuresBeforeSuccess = 0;

  int renameChatInIndexAttempts = 0;
  int renameFailuresBeforeSuccess = 0;
  int activeRenameCalls = 0;
  int maxConcurrentRenameCalls = 0;
  Duration renameDelay = Duration.zero;

  @override
  Future<void> ensureDirectories(String projectId) async {
    // No-op for testing
  }

  @override
  Future<void> appendChatEntry(
    String projectId,
    String chatId,
    OutputEntry entry,
  ) async {
    appendChatEntryAttempts++;
    if (appendChatEntryAttempts <= appendFailuresBeforeSuccess) {
      throw StateError('append transient failure');
    }
    appendChatEntryCalls.add(
      _AppendChatEntryCall(projectId: projectId, chatId: chatId, entry: entry),
    );
  }

  @override
  Future<void> updateChatSessionId({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
    required String? sessionId,
  }) async {
    updateChatSessionIdCalls.add(
      _UpdateChatSessionIdCall(
        projectRoot: projectRoot,
        worktreePath: worktreePath,
        chatId: chatId,
        sessionId: sessionId,
      ),
    );
  }

  @override
  Future<void> renameChatInIndex({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
    required String newName,
  }) async {
    renameChatInIndexAttempts++;
    if (renameChatInIndexAttempts <= renameFailuresBeforeSuccess) {
      throw StateError('rename transient failure');
    }

    activeRenameCalls++;
    if (activeRenameCalls > maxConcurrentRenameCalls) {
      maxConcurrentRenameCalls = activeRenameCalls;
    }

    try {
      if (renameDelay > Duration.zero) {
        await Future<void>.delayed(renameDelay);
      }
      renameChatInIndexCalls.add(
        _RenameChatInIndexCall(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
          newName: newName,
        ),
      );
    } finally {
      activeRenameCalls--;
    }
  }
}

/// Record of a call to updateChatSessionId.
class _UpdateChatSessionIdCall {
  final String projectRoot;
  final String worktreePath;
  final String chatId;
  final String? sessionId;

  _UpdateChatSessionIdCall({
    required this.projectRoot,
    required this.worktreePath,
    required this.chatId,
    required this.sessionId,
  });
}

/// Record of a call to appendChatEntry.
class _AppendChatEntryCall {
  final String projectId;
  final String chatId;
  final OutputEntry entry;

  _AppendChatEntryCall({
    required this.projectId,
    required this.chatId,
    required this.entry,
  });
}

/// Record of a call to renameChatInIndex.
class _RenameChatInIndexCall {
  final String projectRoot;
  final String worktreePath;
  final String chatId;
  final String newName;

  _RenameChatInIndexCall({
    required this.projectRoot,
    required this.worktreePath,
    required this.chatId,
    required this.newName,
  });
}
