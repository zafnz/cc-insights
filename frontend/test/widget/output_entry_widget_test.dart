import 'package:agent_sdk_core/agent_sdk_core.dart' show ToolKind;
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/state/theme_state.dart';
import 'package:cc_insights_v2/widgets/output_entries/output_entry_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  group('OutputEntryWidget', () {
    Widget createTestApp({
      required OutputEntry entry,
      bool isSubagent = false,
      String? projectDir,
    }) {
      return ChangeNotifierProvider(
        create: (_) => ThemeState(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OutputEntryWidget(
                entry: entry,
                isSubagent: isSubagent,
                projectDir: projectDir,
              ),
            ),
          ),
        ),
      );
    }

    group('isSubagent styling', () {
      testWidgets('does not apply subagent styling when isSubagent is false',
          (tester) async {
        final entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'Test message',
          contentType: 'text',
        );

        await tester.pumpWidget(createTestApp(entry: entry, isSubagent: false));
        await safePumpAndSettle(tester);

        // Find containers with left border decoration
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            final border = decoration.border;
            if (border is Border) {
              return border.left.width > 0;
            }
          }
          return false;
        });

        // Should not have any containers with left border styling
        expect(containers.isEmpty, isTrue);
      });

      testWidgets('applies subagent styling when isSubagent is true',
          (tester) async {
        final entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'Subagent output',
          contentType: 'text',
        );

        await tester.pumpWidget(createTestApp(entry: entry, isSubagent: true));
        await safePumpAndSettle(tester);

        // Find containers with left border decoration
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            final border = decoration.border;
            if (border is Border) {
              // The subagent wrapper uses a 3px left border
              return border.left.width == 3;
            }
          }
          return false;
        });

        // Should have a container with the subagent left border
        expect(containers.isNotEmpty, isTrue);
      });

      testWidgets('subagent styling applies to tool entries too',
          (tester) async {
        final entry = ToolUseOutputEntry(
          timestamp: DateTime.now(),
          toolName: 'Bash',
          toolKind: ToolKind.execute,
          toolUseId: 'test-id',
          toolInput: {'command': 'ls'},
          result: 'output',
        );

        await tester.pumpWidget(createTestApp(entry: entry, isSubagent: true));
        await safePumpAndSettle(tester);

        // Find containers with left border decoration
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            final border = decoration.border;
            if (border is Border) {
              return border.left.width == 3;
            }
          }
          return false;
        });

        expect(containers.isNotEmpty, isTrue);
      });

      testWidgets('subagent styling has left padding for content',
          (tester) async {
        final entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'Test message',
          contentType: 'text',
        );

        await tester.pumpWidget(createTestApp(entry: entry, isSubagent: true));
        await safePumpAndSettle(tester);

        // Find the container with left padding
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
          final padding = container.padding;
          if (padding is EdgeInsets) {
            return padding.left == 8;
          }
          return false;
        });

        expect(containers.isNotEmpty, isTrue);
      });
    });

    group('entry type rendering', () {
      testWidgets('renders TextOutputEntry', (tester) async {
        final entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'Hello world',
          contentType: 'text',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('Hello world'), findsOneWidget);
      });

      testWidgets('renders UserInputEntry', (tester) async {
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'User message',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('User message'), findsOneWidget);
      });

      testWidgets('renders ToolUseOutputEntry', (tester) async {
        final entry = ToolUseOutputEntry(
          timestamp: DateTime.now(),
          toolName: 'Read',
          toolKind: ToolKind.read,
          toolUseId: 'test-id',
          toolInput: {'file_path': '/path/to/file.txt'},
          result: 'file content',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.text('Read'), findsOneWidget);
      });

      testWidgets('renders ContextSummaryEntry', (tester) async {
        final entry = ContextSummaryEntry(
          timestamp: DateTime.now(),
          summary: 'Context was compacted',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // The header shows "Context Summary" text, not the actual summary
        // The summary is only visible when expanded
        expect(find.text('Context Summary'), findsOneWidget);
      });

      testWidgets('renders ContextClearedEntry', (tester) async {
        final entry = ContextClearedEntry(timestamp: DateTime.now());

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // The cleared entry shows a visual divider
        expect(find.byType(OutputEntryWidget), findsOneWidget);
      });

      testWidgets('renders SessionMarkerEntry', (tester) async {
        final entry = SessionMarkerEntry(
          timestamp: DateTime.now(),
          markerType: SessionMarkerType.resumed,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byType(OutputEntryWidget), findsOneWidget);
      });

      testWidgets('renders AutoCompactionEntry', (tester) async {
        final entry = AutoCompactionEntry(
          timestamp: DateTime.now(),
          message: 'Was 50K tokens',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Shows the auto-compaction label
        expect(find.text('Context Auto-Compacted'), findsOneWidget);
      });

      testWidgets('renders AutoCompactionEntry with custom message',
          (tester) async {
        final entry = AutoCompactionEntry(
          timestamp: DateTime.now(),
          message: 'Custom compaction message',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.text('Custom compaction message'), findsOneWidget);
      });

      testWidgets('renders AutoCompactionEntry with default message',
          (tester) async {
        final entry = AutoCompactionEntry(timestamp: DateTime.now());

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Default message when none provided
        expect(
          find.text('Conversation was summarized to free up context space.'),
          findsOneWidget,
        );
      });

      testWidgets('renders manual compaction entry with different label',
          (tester) async {
        final entry = AutoCompactionEntry(
          timestamp: DateTime.now(),
          isManual: true,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Shows "Context Compacted" instead of "Context Auto-Compacted"
        expect(find.text('Context Compacted'), findsOneWidget);
        expect(find.text('Context Auto-Compacted'), findsNothing);
        // Shows manual default message
        expect(
          find.text('Conversation was manually compacted.'),
          findsOneWidget,
        );
      });

      testWidgets('renders UnknownMessageEntry', (tester) async {
        final entry = UnknownMessageEntry(
          timestamp: DateTime.now(),
          messageType: 'custom_type',
          rawMessage: {'key': 'value'},
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Shows the unknown message label and type
        expect(find.text('Unknown Message'), findsOneWidget);
        expect(find.text('custom_type'), findsOneWidget);
      });

      testWidgets('UnknownMessageEntry expands to show JSON', (tester) async {
        final entry = UnknownMessageEntry(
          timestamp: DateTime.now(),
          messageType: 'test_type',
          rawMessage: {'test_key': 'test_value'},
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Initially collapsed
        expect(find.text('Show'), findsOneWidget);

        // Tap to expand
        await tester.tap(find.text('Show'));
        await safePumpAndSettle(tester);

        // Now shows Hide and the JSON content
        expect(find.text('Hide'), findsOneWidget);
        expect(find.textContaining('test_key'), findsOneWidget);
        expect(find.textContaining('test_value'), findsOneWidget);
      });

      testWidgets('renders SystemNotificationEntry', (tester) async {
        final entry = SystemNotificationEntry(
          timestamp: DateTime.now(),
          message: 'Unknown skill: clear',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Shows the notification message
        expect(find.text('Unknown skill: clear'), findsOneWidget);
        // Shows the info icon
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
      });
    });
  });
}
