import 'package:agent_sdk_core/agent_sdk_core.dart' show ToolKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/conversation.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/conversation_panel.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/widgets/keyboard_focus_manager.dart';
import 'package:cc_insights_v2/widgets/output_entries/output_entry_widget.dart';
import 'package:cc_insights_v2/widgets/tool_card.dart';

import '../fakes/fake_cli_availability_service.dart';
import '../test_helpers.dart';

void main() {
  group('Conversation scroll issues', () {
    final resources = TestResources();
    late ProjectState project;
    late SelectionState selectionState;
    late Chat chat;
    late BackendService backendService;
    late FakeCliAvailabilityService fakeCliAvailability;

    /// Creates a chat with the specified number of entries.
    Chat createChatWithEntries(String name, int entryCount) {
      final entries = List.generate(
        entryCount,
        (i) => TextOutputEntry(
          timestamp: DateTime.now().subtract(Duration(minutes: entryCount - i)),
          text: 'Message $i - ${'x' * 200}', // Long enough to ensure scrolling
          contentType: 'text',
        ),
      );

      return Chat(
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

    /// Creates a chat with tool entries.
    Chat createChatWithToolEntries(String name, int entryCount) {
      final entries = <OutputEntry>[];

      for (var i = 0; i < entryCount; i++) {
        // Add a text entry
        entries.add(
          TextOutputEntry(
            timestamp: DateTime.now().subtract(
              Duration(minutes: entryCount - i),
            ),
            text: 'Text before tool $i - ${'x' * 100}',
            contentType: 'text',
          ),
        );

        // Add a tool entry
        entries.add(
          ToolUseOutputEntry(
            timestamp: DateTime.now().subtract(
              Duration(minutes: entryCount - i, seconds: 30),
            ),
            toolName: 'Bash',
            toolKind: ToolKind.execute,
            toolUseId: 'tool-$i',
            toolInput: {
              'command': 'echo "test $i"',
              'description': 'Test command $i',
            },
          )..updateResult('Output for test $i\n${'y' * 50}', false),
        );
      }

      return Chat(
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
      chat = createChatWithEntries('Test', 30);

      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test',
          isPrimary: true,
          branch: 'main',
        ),
        chats: [chat],
      );

      project = resources.track(
        ProjectState(
          const ProjectData(name: 'Test Project', repoRoot: '/test'),
          worktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );

      selectionState = resources.track(SelectionState(project));
      backendService = resources.track(BackendService());
      fakeCliAvailability = FakeCliAvailabilityService();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    Widget buildTestWidget({Chat? overrideChat}) {
      // Ensure chat is in worktree if overriding
      if (overrideChat != null &&
          !project.primaryWorktree.chats.contains(overrideChat)) {
        project.primaryWorktree.addChat(overrideChat);
      }

      return MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: project),
            ChangeNotifierProvider.value(value: selectionState),
            ChangeNotifierProvider<BackendService>.value(value: backendService),
            ChangeNotifierProvider<CliAvailabilityService>.value(
              value: fakeCliAvailability,
            ),
          ],
          child: const Scaffold(
            body: KeyboardFocusManager(
              child: SizedBox(
                width: 600,
                height: 800,
                child: ConversationPanel(),
              ),
            ),
          ),
        ),
      );
    }

    ScrollController? getScrollController(WidgetTester tester) {
      final scrollables = find
          .descendant(
            of: find.byType(ConversationPanel),
            matching: find.byType(Scrollable),
          )
          .evaluate();

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

    group('Scroll position stability when new content arrives', () {
      testWidgets(
        'scroll position should NOT change when user is scrolled up and new entry arrives',
        (tester) async {
          await tester.pumpWidget(buildTestWidget());
          await safePumpAndSettle(tester);

          // Select the chat
          selectionState.selectChat(chat);
          await safePumpAndSettle(tester);

          final controller = getScrollController(tester);
          expect(controller, isNotNull);

          // Initially at bottom (maxScrollExtent in normal list)
          // Wait for initial scroll to bottom
          await tester.pump(const Duration(milliseconds: 200));

          // Scroll up significantly (away from bottom, towards position 0)
          controller!.jumpTo(100);
          await safePumpAndSettle(tester);

          // Verify we're scrolled up (not at bottom)
          expect(controller.position.pixels, equals(100));

          // Add a new entry (simulating streaming content)
          final newEntry = TextOutputEntry(
            timestamp: DateTime.now(),
            text: 'New message that just arrived!',
            contentType: 'text',
          );
          chat.conversations.addEntry(newEntry);
          await tester.pump();

          // Scroll position should stay at 100 - no auto-scroll since user was scrolled up
          expect(
            controller.position.pixels,
            equals(100),
            reason:
                'Scroll position should NOT change when user is scrolled up and new content arrives',
          );
        },
      );

      testWidgets(
        'content visible to user should NOT shift when new entry arrives while scrolled up',
        (tester) async {
          await tester.pumpWidget(buildTestWidget());
          await safePumpAndSettle(tester);

          selectionState.selectChat(chat);
          await safePumpAndSettle(tester);

          final controller = getScrollController(tester);
          expect(controller, isNotNull);

          // Wait for initial scroll to bottom
          await tester.pump(const Duration(milliseconds: 200));

          // Scroll up to see older messages (lower pixel values = closer to top)
          controller!.jumpTo(100);
          await safePumpAndSettle(tester);

          // Find the OutputEntryWidget widgets that are visible
          final entryWidgetFinder = find.byType(OutputEntryWidget);
          expect(entryWidgetFinder, findsWidgets);

          // Get the first visible entry widget's position
          final firstVisibleEntry = entryWidgetFinder.first;
          final initialPosition = tester.getTopLeft(firstVisibleEntry);

          // Add a new entry
          chat.conversations.addEntry(
            TextOutputEntry(
              timestamp: DateTime.now(),
              text: 'New streaming content',
              contentType: 'text',
            ),
          );
          await tester.pump();

          // Get the new position of the first visible entry
          final newPosition = tester.getTopLeft(entryWidgetFinder.first);

          // The visible message should stay in the same position
          expect(
            newPosition.dy,
            closeTo(initialPosition.dy, 5.0),
            reason:
                'Content visible to user should NOT shift when new entries arrive while scrolled up',
          );
        },
      );
    });

    group('Issue 2: Tool card expansion state lost on new content', () {
      testWidgets(
        'expanded tool card should remain expanded when new entry arrives',
        (tester) async {
          // Create a chat with tool entries
          final toolChat = createChatWithToolEntries('ToolTest', 5);
          project.primaryWorktree.addChat(toolChat);

          await tester.pumpWidget(buildTestWidget(overrideChat: toolChat));
          await safePumpAndSettle(tester);

          selectionState.selectChat(toolChat);
          await safePumpAndSettle(tester);

          // Find a tool card
          final toolCardFinder = find.byType(ToolCard);
          expect(toolCardFinder, findsWidgets);

          // Find the first tool card and tap to expand it
          final firstToolCard = toolCardFinder.first;
          await tester.tap(firstToolCard);
          await safePumpAndSettle(tester);

          // Verify the tool card is expanded (expanded content should be visible)
          // Look for the "Result:" text which only appears when expanded
          final resultLabelFinder = find.text('Result:');
          expect(
            resultLabelFinder,
            findsWidgets,
            reason: 'Tool card should be expanded and show Result label',
          );

          // Add a new entry (simulating streaming)
          toolChat.conversations.addEntry(
            TextOutputEntry(
              timestamp: DateTime.now(),
              text: 'New message arriving while tool card is expanded',
              contentType: 'text',
            ),
          );
          await tester.pump();

          // EXPECTED: Tool card should still be expanded
          // ACTUAL BUG: Tool card collapses because the widget tree is rebuilt
          expect(
            resultLabelFinder,
            findsWidgets,
            reason:
                'Tool card should remain expanded after new entry arrives - expansion state should be preserved',
          );
        },
      );

      testWidgets(
        'multiple expanded tool cards should all remain expanded when new entry arrives',
        (tester) async {
          final toolChat = createChatWithToolEntries('MultiToolTest', 5);
          project.primaryWorktree.addChat(toolChat);

          await tester.pumpWidget(buildTestWidget(overrideChat: toolChat));
          await safePumpAndSettle(tester);

          selectionState.selectChat(toolChat);
          await safePumpAndSettle(tester);

          // Find all tool cards
          final toolCardFinder = find.byType(ToolCard);
          expect(toolCardFinder, findsWidgets);

          // Expand the first two tool cards
          final toolCards = toolCardFinder.evaluate().take(2).toList();
          for (final element in toolCards) {
            await tester.tap(find.byWidget(element.widget));
            await tester.pump();
          }
          await safePumpAndSettle(tester);

          // Count expanded cards (by counting Result: labels)
          final resultLabels = find.text('Result:');
          final initialExpandedCount = resultLabels.evaluate().length;
          expect(
            initialExpandedCount,
            greaterThanOrEqualTo(2),
            reason: 'At least 2 tool cards should be expanded',
          );

          // Add a new entry
          toolChat.conversations.addEntry(
            TextOutputEntry(
              timestamp: DateTime.now(),
              text: 'New message while multiple cards expanded',
              contentType: 'text',
            ),
          );
          await tester.pump();

          // EXPECTED: Same number of cards should remain expanded
          // ACTUAL BUG: All cards collapse on rebuild
          final finalExpandedCount = resultLabels.evaluate().length;
          expect(
            finalExpandedCount,
            equals(initialExpandedCount),
            reason:
                'All previously expanded tool cards should remain expanded after new entry arrives',
          );
        },
      );
    });
  });
}
