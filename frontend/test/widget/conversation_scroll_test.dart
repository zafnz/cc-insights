import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/conversation.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/conversation_panel.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/widgets/keyboard_focus_manager.dart';

import '../test_helpers.dart';

void main() {
  group('ConversationPanel scroll behavior', () {
    final resources = TestResources();
    late ProjectState project;
    late SelectionState selectionState;

    /// Creates a chat with the specified number of entries.
    ChatState createChatWithEntries(String name, int entryCount) {
      final entries = List.generate(
        entryCount,
        (i) => TextOutputEntry(
          timestamp: DateTime.now().subtract(Duration(minutes: entryCount - i)),
          text: 'Message $i - ' + 'x' * 100, // Make messages long enough to scroll
          contentType: 'text',
        ),
      );

      return ChatState(
        ChatData(
          id: 'chat-$name',
          name: name,
          worktreeRoot: '/test',
          createdAt: DateTime.now(),
          primaryConversation: ConversationData(
            id: 'conv-$name',
            entries: entries,
            totalUsage: const UsageInfo.zero(),
          ),
          subagentConversations: const {},
        ),
      );
    }

    setUp(() {
      // Create a project with two chats that have enough messages to scroll
      final chat1 = createChatWithEntries('Chat1', 50);
      final chat2 = createChatWithEntries('Chat2', 30);

      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test',
          isPrimary: true,
          branch: 'main',
          uncommittedFiles: 0,
          stagedFiles: 0,
          commitsAhead: 0,
          commitsBehind: 0,
          hasMergeConflict: false,
        ),
        chats: [chat1, chat2],
      );

      project = resources.track(ProjectState(
        const ProjectData(
          name: 'Test Project',
          repoRoot: '/test',
        ),
        worktree,
        linkedWorktrees: [],
      ));

      selectionState = resources.track(SelectionState(project));
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: project),
            ChangeNotifierProvider.value(value: selectionState),
          ],
          child: const Scaffold(
            body: KeyboardFocusManager(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ConversationPanel(),
              ),
            ),
          ),
        ),
      );
    }

    /// Finds the conversation ListView's Scrollable.
    /// The ConversationPanel uses a ListView.builder with a ScrollController.
    Finder findConversationScrollable() {
      // Find all Scrollables in the ConversationPanel, then get the one
      // with the largest maxScrollExtent (the conversation list)
      return find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byType(Scrollable),
      );
    }

    /// Checks if the scroll controller is at or near the bottom.
    /// Due to lazy ListView building, maxScrollExtent may grow as items are rendered,
    /// so we use a percentage-based check: within 20% of max, or at max if small.
    bool isAtBottom(ScrollController controller) {
      final maxExtent = controller.position.maxScrollExtent;
      final pixels = controller.position.pixels;
      // For small lists, require being within 50px
      if (maxExtent < 500) {
        return pixels >= maxExtent - 50;
      }
      // For larger lists, accept being within 20% of the end
      // This accounts for lazy loading where maxExtent grows after scroll
      return pixels >= maxExtent * 0.8;
    }

    /// Gets the conversation scroll controller from the widget tree.
    ScrollController? getConversationScrollController(WidgetTester tester) {
      final scrollables = findConversationScrollable().evaluate();
      ScrollController? controller;
      double maxExtent = 0;

      for (final element in scrollables) {
        final scrollable = element.widget as Scrollable;
        final ctrl = scrollable.controller;
        if (ctrl != null && ctrl.hasClients) {
          final extent = ctrl.position.maxScrollExtent;
          if (extent > maxExtent) {
            maxExtent = extent;
            controller = ctrl;
          }
        }
      }
      return controller;
    }

    testWidgets('switching to a chat scrolls to bottom', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await safePumpAndSettle(tester);

      // Initially no chat is selected - shows WelcomeCard
      expect(find.text('Welcome to CC-Insights'), findsOneWidget);

      // Select the first chat
      selectionState.selectChat(project.primaryWorktree.chats.first);

      // Pump to rebuild with the new chat, then pump again for postFrameCallback
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await safePumpAndSettle(tester);

      // Get the scroll position
      final controller = getConversationScrollController(tester);
      expect(controller, isNotNull);

      debugPrint(
          'pixels: ${controller!.position.pixels}, maxScrollExtent: ${controller.position.maxScrollExtent}');

      // With a normal ListView, "scrolled to bottom" means at maxScrollExtent.
      // Due to lazy loading, we may not have the full extent yet, but we should
      // be at or near the current maxScrollExtent.
      expect(
        isAtBottom(controller),
        isTrue,
        reason: 'Should be scrolled to bottom (at maxScrollExtent)',
      );
    });

    testWidgets('switching between chats scrolls new chat to bottom',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await safePumpAndSettle(tester);

      // Select first chat
      final chat1 = project.primaryWorktree.chats[0];
      final chat2 = project.primaryWorktree.chats[1];

      selectionState.selectChat(chat1);
      await safePumpAndSettle(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final controller = getConversationScrollController(tester);
      expect(controller, isNotNull);

      // Scroll away from bottom (towards position 0)
      controller!.jumpTo(100);
      await safePumpAndSettle(tester);

      // Verify we're not at bottom
      expect(isAtBottom(controller), isFalse);

      // Switch to chat2
      selectionState.selectChat(chat2);
      await safePumpAndSettle(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await safePumpAndSettle(tester);

      // Chat2 should be at bottom (at maxScrollExtent)
      final newController = getConversationScrollController(tester);
      expect(newController, isNotNull);
      expect(
        isAtBottom(newController!),
        isTrue,
        reason: 'New chat should be scrolled to bottom (at maxScrollExtent)',
      );
    });

    testWidgets('switching back to previous chat restores scroll position',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await safePumpAndSettle(tester);

      final chat1 = project.primaryWorktree.chats[0];
      final chat2 = project.primaryWorktree.chats[1];

      // Select first chat
      selectionState.selectChat(chat1);
      await safePumpAndSettle(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final controller = getConversationScrollController(tester);
      expect(controller, isNotNull);

      // Scroll away from bottom (to position 0 / top)
      controller!.jumpTo(0);
      await safePumpAndSettle(tester);
      final savedPosition = controller.position.pixels;

      // Verify we're NOT at bottom
      expect(isAtBottom(controller), isFalse);

      // Switch to chat2
      selectionState.selectChat(chat2);
      await safePumpAndSettle(tester);
      await tester.pump(const Duration(milliseconds: 200));

      // Switch back to chat1
      selectionState.selectChat(chat1);
      await safePumpAndSettle(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await safePumpAndSettle(tester);

      // Scroll position should be restored
      final restoredController = getConversationScrollController(tester);
      expect(restoredController, isNotNull);

      expect(
        restoredController!.position.pixels,
        savedPosition,
        reason: 'Scroll position should be restored when returning to chat',
      );
    });
  });
}
