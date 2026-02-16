import 'dart:async';

import 'package:cc_insights_v2/models/agent.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat sub-state compatibility scaffold', () {
    setUp(() {
      RuntimeConfig.resetForTesting();
      RuntimeConfig.initialize([]);
    });

    test('exposes sub-state facade objects', () {
      final chat = Chat.create(name: 'Test', worktreeRoot: '/tmp');
      addTearDown(chat.dispose);

      check(chat.session).isA<ChatSessionState>();
      check(chat.permissions).isA<ChatPermissionState>();
      check(chat.settings).isA<ChatSettingsState>();
      check(chat.metrics).isA<ChatMetricsState>();
      check(chat.persistence).isA<ChatPersistenceState>();
      check(chat.agents).isA<ChatAgentState>();
      check(chat.conversations).isA<ChatConversationState>();
      check(chat.viewState).isA<ChatViewState>();
    });

    test('rename emits only conversation notifications', () {
      final chat = Chat.create(name: 'Test', worktreeRoot: '/tmp');
      addTearDown(chat.dispose);

      var sessionNotifications = 0;
      var permissionsNotifications = 0;
      var settingsNotifications = 0;
      var metricsNotifications = 0;
      var agentsNotifications = 0;
      var conversationsNotifications = 0;
      var viewNotifications = 0;

      chat.session.addListener(() => sessionNotifications++);
      chat.permissions.addListener(() => permissionsNotifications++);
      chat.settings.addListener(() => settingsNotifications++);
      chat.metrics.addListener(() => metricsNotifications++);
      chat.agents.addListener(() => agentsNotifications++);
      chat.conversations.addListener(() => conversationsNotifications++);
      chat.viewState.addListener(() => viewNotifications++);

      chat.conversations.rename('Renamed');

      check(sessionNotifications).equals(0);
      check(permissionsNotifications).equals(0);
      check(settingsNotifications).equals(0);
      check(metricsNotifications).equals(0);
      check(agentsNotifications).equals(0);
      check(conversationsNotifications).equals(1);
      check(viewNotifications).equals(0);
    });

    test('delegates session and settings mutations through facade', () {
      final chat = Chat.create(name: 'Test', worktreeRoot: '/tmp');
      addTearDown(chat.dispose);

      check(chat.session.isWorking).isFalse();
      check(chat.session.isCompacting).isFalse();

      chat.session.setWorking(true);
      chat.session.setCompacting(true);
      chat.settings.setPermissionMode(PermissionMode.acceptEdits);

      check(chat.session.isWorking).isTrue();
      check(chat.session.isCompacting).isTrue();
      check(chat.settings.permissionMode).equals(PermissionMode.acceptEdits);
      check(chat.settings.permissionMode).equals(PermissionMode.acceptEdits);

      chat.session.setWorking(false);
      chat.session.setCompacting(false);

      check(chat.session.isWorking).isFalse();
      check(chat.session.isCompacting).isFalse();
    });

    test(
      'delegates conversation, view, and agent mutations through facade',
      () {
        final chat = Chat.create(name: 'Test', worktreeRoot: '/tmp');
        addTearDown(chat.dispose);

        final primaryId = chat.conversations.primaryConversation.id;
        chat.viewState.markAsNotViewed();
        chat.conversations.addOutputEntry(
          primaryId,
          TextOutputEntry(
            timestamp: DateTime.now(),
            text: 'assistant response',
            contentType: 'text',
          ),
        );

        check(chat.viewState.unreadCount).equals(1);
        check(chat.viewState.hasUnreadMessages).isTrue();

        chat.conversations.addSubagentConversation(
          'agent-1',
          'Explore',
          'Inspect repository state',
        );

        check(chat.agents.activeAgents.containsKey('agent-1')).isTrue();

        chat.agents.updateAgent(
          AgentStatus.completed,
          'agent-1',
          result: 'Done',
        );

        check(
          chat.agents.activeAgents['agent-1']?.status,
        ).equals(AgentStatus.completed);

        chat.viewState.markAsViewed();
        check(chat.viewState.unreadCount).equals(0);
      },
    );

    test('keeps Chat view APIs as compatibility delegates', () {
      final chat = Chat.create(name: 'Test', worktreeRoot: '/tmp');
      addTearDown(chat.dispose);

      check(chat.viewState.draftText).equals('');
      check(chat.viewState.draftText).equals('');

      chat.viewState.draftText = 'draft-from-chat';
      check(chat.viewState.draftText).equals('draft-from-chat');

      chat.viewState.draftText = 'draft-from-view';
      check(chat.viewState.draftText).equals('draft-from-view');

      chat.viewState.markAsNotViewed();
      chat.conversations.addEntry(
        TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'assistant response',
          contentType: 'text',
        ),
      );

      check(chat.viewState.unreadCount).equals(1);
      check(chat.viewState.unreadCount).equals(1);
      check(chat.viewState.hasUnreadMessages).isTrue();

      chat.viewState.markAsViewed();
      check(chat.viewState.unreadCount).equals(0);
      check(chat.viewState.unreadCount).equals(0);
      check(chat.viewState.hasUnreadMessages).isFalse();
    });

    test('delegates permission queue flow through facade', () {
      final chat = Chat.create(name: 'Test', worktreeRoot: '/tmp');
      addTearDown(chat.dispose);

      final request1 = sdk.PermissionRequest(
        id: 'perm-1',
        sessionId: 'session-1',
        toolName: 'Read',
        toolInput: const {'file': 'a.txt'},
        completer: Completer<sdk.PermissionResponse>(),
      );
      final request2 = sdk.PermissionRequest(
        id: 'perm-2',
        sessionId: 'session-1',
        toolName: 'Write',
        toolInput: const {'file': 'b.txt'},
        completer: Completer<sdk.PermissionResponse>(),
      );

      chat.permissions.add(request1);
      chat.permissions.add(request2);
      check(chat.permissions.pendingPermissionCount).equals(2);
      check(chat.permissions.pendingPermissionCount).equals(2);

      chat.permissions.allow();
      check(chat.permissions.pendingPermission?.id).equals('perm-2');

      chat.permissions.deny('no');
      check(chat.permissions.pendingPermission).isNull();
      check(chat.permissions.pendingPermissionCount).equals(0);
    });

    test('delegates metrics/context flow through facade', () {
      final chat = Chat.create(name: 'Test', worktreeRoot: '/tmp');
      addTearDown(chat.dispose);

      chat.metrics.addInTurnOutputTokens(9);
      check(chat.metrics.cumulativeUsage.outputTokens).equals(9);

      chat.metrics.updateCumulativeUsage(
        usage: const UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.01,
        ),
        totalCostUsd: 0.01,
        modelUsage: const [
          ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
        contextWindow: 200000,
      );

      check(chat.metrics.cumulativeUsage.outputTokens).equals(50);
      check(chat.metrics.modelUsage.length).equals(1);
      check(chat.metrics.contextTracker.maxTokens).equals(200000);
    });
  });
}
