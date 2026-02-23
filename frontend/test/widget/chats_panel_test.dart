import 'dart:async';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/chats_panel.dart';
import 'package:cc_insights_v2/services/log_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();

  late WorktreeState worktree;
  late ProjectState project;
  late SelectionState selection;

  setUp(() {
    worktree = WorktreeState(
      const WorktreeData(
        worktreeRoot: '/test/repo',
        isPrimary: true,
        branch: 'main',
      ),
    );

    project = resources.track(
      ProjectState(
        const ProjectData(name: 'Test', repoRoot: '/test/repo'),
        worktree,
        autoValidate: false,
        watchFilesystem: false,
      ),
    );

    selection = resources.track(SelectionState(project));
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SelectionState>.value(value: selection),
          ChangeNotifierProvider<ProjectState>.value(value: project),
        ],
        child: const Scaffold(body: ChatsPanel()),
      ),
    );
  }

  group('ChatsPanel rebuilds on worktree changes', () {
    testWidgets('shows spinner when chat added with select: false',
        (tester) async {
      // Start with one chat so the panel renders the list.
      final existingChat = Chat.create(
        name: 'Orchestrator',
        worktreeRoot: '/test/repo',
      );
      worktree.addChat(existingChat, select: true);
      selection.selectChat(existingChat);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // No spinner yet — only the orchestrator chat, which is idle.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Simulate launch_agent: create a new chat, add without selecting,
      // then mark it as working.
      final workerChat = Chat.create(
        name: 'Worker Agent',
        worktreeRoot: '/test/repo',
      );
      worktree.addChat(workerChat, select: false);
      workerChat.session.setWorking(true);

      // Pump one frame — the ListenableBuilder on the worktree should
      // trigger a rebuild that includes the new chat tile.
      await tester.pump();

      // The worker chat tile should now show a spinner.
      expect(find.text('Worker Agent'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Drain LogService periodic timer created by addChat logging.
      LogService.instance.clearBuffer();
    });

    testWidgets('shows permission icon when unselected chat gets request',
        (tester) async {
      final chat = Chat.create(
        name: 'Worker',
        worktreeRoot: '/test/repo',
      );
      worktree.addChat(chat, select: false);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // No permission icon yet.
      expect(find.byIcon(Icons.notifications_active), findsNothing);

      // Simulate a permission request arriving.
      final request = sdk.PermissionRequest(
        id: 'perm-1',
        sessionId: 'session-1',
        toolName: 'Read',
        toolInput: const {'file': 'a.txt'},
        completer: Completer<sdk.PermissionResponse>(),
      );
      chat.permissions.add(request);

      await tester.pump();

      // The permission bell icon should appear in the chat tile.
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);

      LogService.instance.clearBuffer();
    });

    testWidgets('new chat appears without selecting it', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Panel shows empty state.
      expect(find.text('No chats in this worktree'), findsOneWidget);

      // Add a chat without selecting it.
      final chat = Chat.create(
        name: 'Background Chat',
        worktreeRoot: '/test/repo',
      );
      worktree.addChat(chat, select: false);

      await tester.pump();

      // Chat should appear even though it wasn't selected.
      expect(find.text('Background Chat'), findsOneWidget);
      expect(find.text('No chats in this worktree'), findsNothing);

      LogService.instance.clearBuffer();
    });
  });
}
