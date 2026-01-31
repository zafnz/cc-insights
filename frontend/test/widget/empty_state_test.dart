import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/chats_panel.dart';
import 'package:cc_insights_v2/panels/conversation_panel.dart';
import 'package:cc_insights_v2/panels/worktree_panel.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  group('Empty State Tests', () {
    late ProjectState project;
    late SelectionState selection;

    /// Creates a project with just the primary worktree (no chats).
    ProjectState createEmptyProject() {
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/Users/test/my-project',
          isPrimary: true,
          branch: 'main',
        ),
      );

      return ProjectState(
        const ProjectData(name: 'My Project', repoRoot: '/Users/test/my-project'),
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );
    }

    Widget createTestApp({required Widget child}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ProjectState>.value(value: project),
          ChangeNotifierProxyProvider<ProjectState, SelectionState>(
            create: (_) => selection,
            update: (_, __, previous) => previous!,
          ),
          Provider<ProjectRestoreService>(
            create: (_) => ProjectRestoreService(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: child),
        ),
      );
    }

    setUp(() {
      project = createEmptyProject();
      selection = SelectionState(project);
    });

    // Note: Don't dispose - Provider handles disposal when widget is removed

    group('WorktreePanel', () {
      testWidgets('shows New Worktree card', (tester) async {
        await tester.pumpWidget(createTestApp(child: const WorktreePanel()));
        await safePumpAndSettle(tester);

        // Should show the ghost card
        expect(find.text('New Worktree'), findsOneWidget);
        expect(find.byType(CreateWorktreeCard), findsOneWidget);
      });

      testWidgets('shows worktree and ghost card together', (tester) async {
        await tester.pumpWidget(createTestApp(child: const WorktreePanel()));
        await safePumpAndSettle(tester);

        // Should show the primary worktree
        expect(find.text('main'), findsOneWidget);
        // Primary worktree shows full path
        expect(find.text('/Users/test/my-project'), findsOneWidget);

        // And the ghost card
        expect(find.text('New Worktree'), findsOneWidget);
      });

      testWidgets('ghost card is tappable', (tester) async {
        await tester.pumpWidget(createTestApp(child: const WorktreePanel()));
        await safePumpAndSettle(tester);

        // Verify the ghost card can be tapped (doesn't throw)
        await tester.tap(find.text('New Worktree'));
        await tester.pump();
        // No assertion - just verifying it doesn't throw
      });
    });

    group('ChatsPanel', () {
      testWidgets('shows New Chat card when worktree is selected', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ChatsPanel()));
        await safePumpAndSettle(tester);

        // Worktree is selected by default
        expect(selection.selectedWorktree, isNotNull);

        // Should show the ghost card
        expect(find.text('New Chat'), findsOneWidget);
        expect(find.byType(NewChatCard), findsOneWidget);
      });

      testWidgets('ghost card is tappable', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ChatsPanel()));
        await safePumpAndSettle(tester);

        // Verify the ghost card can be tapped (doesn't throw)
        await tester.tap(find.text('New Chat'));
        await tester.pump();
        // No assertion - just verifying it doesn't throw
      });

      testWidgets('shows placeholder when no worktree selected', (tester) async {
        // Deselect worktree using project directly (allows null)
        project.selectWorktree(null);

        await tester.pumpWidget(createTestApp(child: const ChatsPanel()));
        await safePumpAndSettle(tester);

        // Should show the placeholder, not the ghost card
        expect(find.text('Select a worktree to view chats'), findsOneWidget);
        expect(find.text('New Chat'), findsNothing);
      });
    });

    group('ConversationPanel - WelcomeCard', () {
      testWidgets('shows WelcomeCard when no chat is selected', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ConversationPanel()));
        await safePumpAndSettle(tester);

        // No chat is selected (project has no chats)
        expect(selection.selectedChat, isNull);

        // Should show the welcome card
        expect(find.byType(WelcomeCard), findsOneWidget);
        expect(find.text('Welcome to CC-Insights'), findsOneWidget);
      });

      testWidgets('WelcomeCard shows project name', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ConversationPanel()));
        await safePumpAndSettle(tester);

        // Should show the project name
        expect(find.text('My Project'), findsOneWidget);
      });

      testWidgets('WelcomeCard shows worktree path', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ConversationPanel()));
        await safePumpAndSettle(tester);

        // Should show the worktree path
        expect(find.text('/Users/test/my-project'), findsOneWidget);
      });

      testWidgets('WelcomeCard shows invitation to chat', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ConversationPanel()));
        await safePumpAndSettle(tester);

        // Should show the invitation text
        expect(
          find.textContaining('Start a new conversation'),
          findsOneWidget,
        );
      });

      testWidgets('WelcomeCard includes message input', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ConversationPanel()));
        await safePumpAndSettle(tester);

        // Should include the message input box
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('WelcomeCard has folder icon', (tester) async {
        await tester.pumpWidget(createTestApp(child: const ConversationPanel()));
        await safePumpAndSettle(tester);

        // Should show the folder icon
        expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      });
    });
  });
}
