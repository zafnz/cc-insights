import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/widgets/tool_card.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('ToolCard Tests', () {
    /// Creates a fake ToolUseOutputEntry for testing.
    ToolUseOutputEntry createToolEntry({
      String toolName = 'Bash',
      String toolUseId = 'test-id',
      Map<String, dynamic> toolInput = const {},
      dynamic result,
      bool isError = false,
      String? model,
    }) {
      return ToolUseOutputEntry(
        timestamp: DateTime.now(),
        toolName: toolName,
        toolUseId: toolUseId,
        toolInput: toolInput,
        result: result,
        isError: isError,
        model: model,
      );
    }

    Widget createTestApp({
      required ToolUseOutputEntry entry,
      VoidCallback? onExpanded,
      String? projectDir,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ToolCard(
              entry: entry,
              onExpanded: onExpanded,
              projectDir: projectDir,
            ),
          ),
        ),
      );
    }

    group('Renders collapsed by default showing tool name and icon', () {
      testWidgets('shows tool name in collapsed state', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls -la'},
          result: 'file1.txt\nfile2.txt',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Verify tool name is displayed
        expect(find.text('Bash'), findsOneWidget);
      });

      testWidgets('shows expand_more icon when collapsed', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'output',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Verify expand_more icon is shown when collapsed
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(find.byIcon(Icons.expand_less), findsNothing);
      });

      testWidgets('does not show tool details when collapsed', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'git status'},
          result: 'On branch main',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // The command should appear in summary but not detailed view
        // Details are shown in expanded content which shouldn't be visible
        expect(find.text('Result:'), findsNothing);
      });
    });

    group('Expands when tapped to show details', () {
      testWidgets('expands card when header is tapped', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'echo hello'},
          result: 'hello',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap the card to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Verify expand_less icon is now shown
        expect(find.byIcon(Icons.expand_less), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsNothing);
      });

      testWidgets('shows result when expanded', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'echo hello'},
          result: 'hello',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Verify result label is shown
        expect(find.text('Result:'), findsOneWidget);
      });

      testWidgets('calls onExpanded callback when expanded', (tester) async {
        var expandedCallCount = 0;
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'files',
        );

        await tester.pumpWidget(createTestApp(
          entry: entry,
          onExpanded: () => expandedCallCount++,
        ));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        check(expandedCallCount).equals(1);

        // Tap again to collapse - should not call onExpanded
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        check(expandedCallCount).equals(1);
      });

      testWidgets('collapses when tapped again', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'output',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.expand_less), findsOneWidget);

        // Tap again to collapse
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(find.text('Result:'), findsNothing);
      });
    });

    group('Shows correct icon for different tool types', () {
      testWidgets('Bash tool shows terminal icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'output',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.terminal), findsOneWidget);
      });

      testWidgets('Read tool shows description icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Read',
          toolInput: {'file_path': '/path/to/file.txt'},
          result: 'file content',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.description), findsOneWidget);
      });

      testWidgets('Write tool shows edit_document icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Write',
          toolInput: {'file_path': '/path/to/file.txt', 'content': 'new content'},
          result: 'written',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.edit_document), findsOneWidget);
      });

      testWidgets('Edit tool shows edit icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Edit',
          toolInput: {
            'file_path': '/path/to/file.txt',
            'old_string': 'old',
            'new_string': 'new',
          },
          result: 'edited',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.edit), findsOneWidget);
      });

      testWidgets('Glob tool shows folder_open icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Glob',
          toolInput: {'pattern': '**/*.dart'},
          result: ['file1.dart', 'file2.dart'],
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.folder_open), findsOneWidget);
      });

      testWidgets('Grep tool shows find_in_page icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Grep',
          toolInput: {'pattern': 'search term'},
          result: 'match found',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.find_in_page), findsOneWidget);
      });

      testWidgets('Task tool shows account_tree icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Task',
          toolInput: {'description': 'Run subtask'},
          result: 'completed',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.account_tree), findsOneWidget);
      });

      testWidgets('WebSearch tool shows travel_explore icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'WebSearch',
          toolInput: {'query': 'flutter testing'},
          result: 'search results',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.travel_explore), findsOneWidget);
      });

      testWidgets('WebFetch tool shows link icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'WebFetch',
          toolInput: {'url': 'https://example.com'},
          result: 'page content',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.link), findsOneWidget);
      });

      testWidgets('Unknown tool shows extension icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'CustomTool',
          toolInput: {'param': 'value'},
          result: 'custom output',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.extension), findsOneWidget);
      });
    });

    group('Bash tool shows command in terminal style', () {
      testWidgets('shows command summary in collapsed state', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'git status'},
          result: 'On branch main',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Command should be shown as summary
        expect(find.textContaining('git status'), findsOneWidget);
      });

      testWidgets('shows command with dollar sign when expanded', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'echo hello'},
          result: 'hello',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Should show the command with terminal-style $ prefix
        expect(find.textContaining(r'$ echo hello'), findsOneWidget);
      });

      testWidgets('shows description when provided', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {
            'command': 'git status',
            'description': 'Check repository status',
          },
          result: 'On branch main',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Description should be shown (may appear in summary and expanded view)
        expect(find.textContaining('Check repository status'), findsWidgets);
      });

      testWidgets('shows result in black container with grey text', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'file1.txt\nfile2.txt',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Result container should have black background
        final containers = tester.widgetList<Container>(find.byType(Container));
        final blackContainers = containers.where((c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration) {
            return decoration.color == Colors.black87;
          }
          return false;
        });
        check(blackContainers).isNotEmpty();
      });
    });

    group('Read tool shows file path', () {
      testWidgets('shows file path in summary', (tester) async {
        final entry = createToolEntry(
          toolName: 'Read',
          toolInput: {'file_path': '/Users/test/project/file.dart'},
          result: 'file content here',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('/Users/test/project/file.dart'), findsOneWidget);
      });

      testWidgets('shows file icon in expanded view', (tester) async {
        final entry = createToolEntry(
          toolName: 'Read',
          toolInput: {'file_path': '/path/to/file.txt'},
          result: 'content',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Should show description icon in the expanded file path widget
        // The header icon is Icons.description, and _FilePathWidget also uses it
        expect(find.byIcon(Icons.description), findsWidgets);
      });

      testWidgets('shows offset and limit info when provided', (tester) async {
        final entry = createToolEntry(
          toolName: 'Read',
          toolInput: {
            'file_path': '/path/to/file.txt',
            'offset': 10,
            'limit': 50,
          },
          result: 'partial content',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Should show offset and limit info
        expect(find.textContaining('from line 10'), findsOneWidget);
        expect(find.textContaining('50 lines'), findsOneWidget);
      });
    });

    group('Edit tool shows DiffView', () {
      testWidgets('shows file path for edit tool', (tester) async {
        final entry = createToolEntry(
          toolName: 'Edit',
          toolInput: {
            'file_path': '/path/to/file.dart',
            'old_string': 'old text',
            'new_string': 'new text',
          },
          result: 'edited successfully',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // File path should appear in summary
        expect(find.textContaining('/path/to/file.dart'), findsOneWidget);
      });

      testWidgets('shows diff view when expanded', (tester) async {
        final entry = createToolEntry(
          toolName: 'Edit',
          toolInput: {
            'file_path': '/path/to/file.dart',
            'old_string': 'hello world',
            'new_string': 'hello flutter',
          },
          result: 'edited',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // DiffView should be present showing the diff
        // The diff view shows removed and added lines
        expect(find.textContaining('hello'), findsWidgets);
      });

      testWidgets('does not show result text for successful edit', (tester) async {
        final entry = createToolEntry(
          toolName: 'Edit',
          toolInput: {
            'file_path': '/path/to/file.dart',
            'old_string': 'old',
            'new_string': 'new',
          },
          result: 'edited',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // For Edit tools, result text is not shown (diff view shows it all)
        expect(find.text('Result:'), findsNothing);
      });
    });

    group('Shows error state correctly (red styling)', () {
      testWidgets('shows error icon when isError is true', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'invalid_command'},
          result: 'command not found',
          isError: true,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Should show error icon instead of check icon
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      });

      testWidgets('error icon is red colored', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'bad_cmd'},
          result: 'error message',
          isError: true,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Find the error icon and verify it's red
        final iconFinder = find.byIcon(Icons.error_outline);
        expect(iconFinder, findsOneWidget);

        final icon = tester.widget<Icon>(iconFinder);
        check(icon.color).equals(Colors.red);
      });

      testWidgets('shows error label in expanded view', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'failing_command'},
          result: 'Permission denied',
          isError: true,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Should show "Error:" label instead of "Result:"
        expect(find.text('Error:'), findsOneWidget);
        expect(find.text('Result:'), findsNothing);
      });

      testWidgets('shows error message in summary for errors', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'bad_cmd'},
          result: '<tool_use_error>Command failed</tool_use_error>',
          isError: true,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Error message should be extracted and shown in summary
        expect(find.textContaining('Command failed'), findsOneWidget);
      });

      testWidgets('success shows green check icon', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'file.txt',
          isError: false,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Should show success check icon
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsNothing);

        // Check icon should be green
        final iconFinder = find.byIcon(Icons.check_circle_outline);
        final icon = tester.widget<Icon>(iconFinder);
        check(icon.color).equals(Colors.green);
      });
    });

    group('Shows loading state when result is null', () {
      testWidgets('shows loading indicator when result is null', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'long_running_command'},
          result: null, // No result yet
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        // Don't use pumpAndSettle here as CircularProgressIndicator animates
        await tester.pump();

        // Should show circular progress indicator
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Should not show success or error icons
        expect(find.byIcon(Icons.check_circle_outline), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      });

      testWidgets('loading indicator has small stroke width', (tester) async {
        final entry = createToolEntry(
          toolName: 'Read',
          toolInput: {'file_path': '/path/to/file.txt'},
          result: null,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await tester.pump();

        final progressIndicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        check(progressIndicator.strokeWidth).equals(2);
      });

      testWidgets('does not show result section when result is null', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'pending_command'},
          result: null,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await tester.pump();

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await tester.pump();

        // Should not show result or error label since result is null
        expect(find.text('Result:'), findsNothing);
        expect(find.text('Error:'), findsNothing);
      });

      testWidgets('loading indicator is contained in 16x16 box', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'command'},
          result: null,
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await tester.pump();

        // Find the SizedBox containing the progress indicator
        final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
        final progressBox = sizedBoxes.where(
          (box) => box.width == 16 && box.height == 16,
        );
        check(progressBox).isNotEmpty();
      });
    });

    group('Additional tool-specific rendering', () {
      testWidgets('Glob shows pattern in summary', (tester) async {
        final entry = createToolEntry(
          toolName: 'Glob',
          toolInput: {'pattern': '**/*.dart', 'path': '/project'},
          result: ['file1.dart', 'file2.dart'],
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('**/*.dart'), findsOneWidget);
      });

      testWidgets('Grep shows pattern in summary', (tester) async {
        final entry = createToolEntry(
          toolName: 'Grep',
          toolInput: {'pattern': 'TODO', 'path': '/project'},
          result: 'matches found',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('TODO'), findsOneWidget);
      });

      testWidgets('WebSearch shows query in summary', (tester) async {
        final entry = createToolEntry(
          toolName: 'WebSearch',
          toolInput: {'query': 'flutter best practices'},
          result: 'search results',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('flutter best practices'), findsOneWidget);
      });

      testWidgets('WebFetch shows URL in summary', (tester) async {
        final entry = createToolEntry(
          toolName: 'WebFetch',
          toolInput: {'url': 'https://flutter.dev', 'prompt': 'Extract docs'},
          result: 'page content',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('https://flutter.dev'), findsOneWidget);
      });

      testWidgets('Task shows description in summary', (tester) async {
        final entry = createToolEntry(
          toolName: 'Task',
          toolInput: {
            'description': 'Analyze code quality',
            'prompt': 'Check for issues',
          },
          result: 'analysis complete',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.textContaining('Analyze code quality'), findsOneWidget);
      });
    });

    group('Card structure', () {
      testWidgets('renders as a Card widget', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'output',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        expect(find.byType(Card), findsOneWidget);
      });

      testWidgets('has divider between header and content when expanded', (tester) async {
        final entry = createToolEntry(
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          result: 'output',
        );

        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Initially no divider
        expect(find.byType(Divider), findsNothing);

        // Tap to expand
        await tester.tap(find.byType(InkWell).first);
        await safePumpAndSettle(tester);

        // Divider should appear
        expect(find.byType(Divider), findsOneWidget);
      });
    });
  });
}
