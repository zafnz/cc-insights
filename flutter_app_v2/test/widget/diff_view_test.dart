import 'package:cc_insights_v2/widgets/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('DiffView', () {
    /// Wraps a DiffView in a minimal MaterialApp for testing.
    Widget createTestApp({
      required String oldText,
      required String newText,
      double? maxHeight,
      List<Map<String, dynamic>>? structuredPatch,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DiffView(
            oldText: oldText,
            newText: newText,
            maxHeight: maxHeight,
            structuredPatch: structuredPatch,
          ),
        ),
      );
    }

    group('renders with old and new text showing diff', () {
      testWidgets('displays added and removed content', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'Hello World',
          newText: 'Hello Flutter',
        ));
        await safePumpAndSettle(tester);

        // Should render the diff view
        expect(find.byType(DiffView), findsOneWidget);

        // Should show text content from the diff
        // The diff algorithm will compute the differences
        expect(find.byType(ListView), findsOneWidget);
      });

      testWidgets('shows line-level differences', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'line 1\nline 2\nline 3',
          newText: 'line 1\nline 2 modified\nline 3',
        ));
        await safePumpAndSettle(tester);

        // Should render multiple lines in the ListView
        expect(find.byType(DiffView), findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);
      });

      testWidgets('shows complete replacement diff', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'old content',
          newText: 'new content',
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
      });
    });

    group('shows added lines in green', () {
      testWidgets('added lines have green background', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: 'new line',
        ));
        await safePumpAndSettle(tester);

        // Find containers with green background (added lines)
        // Green color with alpha 0.2 is used for added lines
        final containers = tester.widgetList<Container>(find.byType(Container));

        // At least one container should have green-tinted background
        final hasGreenContainer = containers.any((container) {
          final color = container.color;
          if (color != null) {
            return color.green > color.red && color.alpha > 0;
          }
          return false;
        });

        expect(hasGreenContainer, isTrue,
            reason: 'Added lines should have green background');
      });

      testWidgets('added lines show + prefix', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: 'added line',
        ));
        await safePumpAndSettle(tester);

        // The + prefix should be present for added lines
        expect(find.text('+'), findsWidgets);
      });
    });

    group('shows removed lines in red', () {
      testWidgets('removed lines have red background', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'removed line',
          newText: '',
        ));
        await safePumpAndSettle(tester);

        // Find containers with red background (removed lines)
        // Red color with alpha 0.2 is used for removed lines
        final containers = tester.widgetList<Container>(find.byType(Container));

        // At least one container should have red-tinted background
        final hasRedContainer = containers.any((container) {
          final color = container.color;
          if (color != null) {
            return color.red > color.green && color.alpha > 0;
          }
          return false;
        });

        expect(hasRedContainer, isTrue,
            reason: 'Removed lines should have red background');
      });

      testWidgets('removed lines show - prefix', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'removed line',
          newText: '',
        ));
        await safePumpAndSettle(tester);

        // The - prefix should be present for removed lines
        expect(find.text('-'), findsWidgets);
      });
    });

    group('handles empty strings', () {
      testWidgets('handles empty old text', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: 'new content',
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
        // All content should be shown as added
        expect(find.text('+'), findsWidgets);
      });

      testWidgets('handles empty new text', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'old content',
          newText: '',
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
        // All content should be shown as removed
        expect(find.text('-'), findsWidgets);
      });

      testWidgets('handles both empty strings', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: '',
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
        // Should render without errors
        expect(find.byType(ListView), findsOneWidget);
      });
    });

    group('respects maxHeight constraint', () {
      testWidgets('applies maxHeight when specified', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'line 1\nline 2\nline 3\nline 4\nline 5',
          newText: 'line 1\nline 2 modified\nline 3\nline 4\nline 5',
          maxHeight: 100.0,
        ));
        await safePumpAndSettle(tester);

        // Find ConstrainedBox widgets with the specific maxHeight of 100.0
        final constrainedBoxes =
            tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));

        // At least one ConstrainedBox should have our maxHeight
        final hasMaxHeightConstraint = constrainedBoxes.any(
          (box) => box.constraints.maxHeight == 100.0,
        );

        expect(hasMaxHeightConstraint, isTrue,
            reason: 'Should have a ConstrainedBox with maxHeight 100.0');
      });

      testWidgets('scrolls when content exceeds maxHeight', (tester) async {
        // Create content that will exceed 50px height
        const longOldText =
            'line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10';
        const longNewText =
            'line 1\nline 2 mod\nline 3\nline 4 mod\nline 5\nline 6\nline 7 mod\nline 8\nline 9\nline 10';

        await tester.pumpWidget(createTestApp(
          oldText: longOldText,
          newText: longNewText,
          maxHeight: 50.0,
        ));
        await safePumpAndSettle(tester);

        // ListView should be scrollable
        final listView = tester.widget<ListView>(find.byType(ListView));
        expect(listView.shrinkWrap, isTrue);
      });

      testWidgets('renders without constraint when maxHeight is null',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'line 1',
          newText: 'line 2',
          maxHeight: null,
        ));
        await safePumpAndSettle(tester);

        // Should not have a ConstrainedBox wrapping the ListView
        // (ConstrainedBox still exists in the hierarchy but not as maxHeight wrapper)
        expect(find.byType(DiffView), findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);
      });
    });

    group('works with structured patch data', () {
      testWidgets('renders hunks from structuredPatch', (tester) async {
        final structuredPatch = [
          {
            'oldStart': 1,
            'oldLines': 3,
            'newStart': 1,
            'newLines': 3,
            'lines': [
              ' context line',
              '-removed line',
              '+added line',
            ],
          },
        ];

        await tester.pumpWidget(createTestApp(
          oldText: '', // Should be ignored when structuredPatch is provided
          newText: '',
          structuredPatch: structuredPatch,
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);

        // Should show hunk header
        expect(find.textContaining('@@'), findsOneWidget);
      });

      testWidgets('shows hunk header with line numbers', (tester) async {
        final structuredPatch = [
          {
            'oldStart': 119,
            'oldLines': 7,
            'newStart': 119,
            'newLines': 6,
            'lines': [
              ' context',
            ],
          },
        ];

        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: '',
          structuredPatch: structuredPatch,
        ));
        await safePumpAndSettle(tester);

        // Should show formatted hunk header
        expect(find.text('@@ -119,7 +119,6 @@'), findsOneWidget);
      });

      testWidgets('handles multiple hunks', (tester) async {
        final structuredPatch = [
          {
            'oldStart': 1,
            'oldLines': 2,
            'newStart': 1,
            'newLines': 2,
            'lines': [
              ' context 1',
              '-removed 1',
            ],
          },
          {
            'oldStart': 10,
            'oldLines': 2,
            'newStart': 10,
            'newLines': 2,
            'lines': [
              ' context 2',
              '+added 2',
            ],
          },
        ];

        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: '',
          structuredPatch: structuredPatch,
        ));
        await safePumpAndSettle(tester);

        // Should show both hunk headers
        expect(find.textContaining('@@'), findsNWidgets(2));
      });

      testWidgets('falls back to computed diff when structuredPatch is empty',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'old content',
          newText: 'new content',
          structuredPatch: [], // Empty - should fall back to computed diff
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
        // Should show diff without hunk headers since it's computed
        expect(find.textContaining('@@'), findsNothing);
      });

      testWidgets(
          'falls back to computed diff when structuredPatch is null',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'old line',
          newText: 'new line',
          structuredPatch: null,
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
        // Should compute diff from oldText/newText
      });

      testWidgets('handles context lines in structured patch', (tester) async {
        final structuredPatch = [
          {
            'oldStart': 1,
            'oldLines': 3,
            'newStart': 1,
            'newLines': 3,
            'lines': [
              ' unchanged line 1',
              ' unchanged line 2',
              ' unchanged line 3',
            ],
          },
        ];

        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: '',
          structuredPatch: structuredPatch,
        ));
        await safePumpAndSettle(tester);

        expect(find.byType(DiffView), findsOneWidget);
        // Context lines should show space prefix
        expect(find.text(' '), findsWidgets);
      });
    });

    group('line numbers', () {
      testWidgets('displays line numbers for diff lines', (tester) async {
        await tester.pumpWidget(createTestApp(
          oldText: 'line 1\nline 2\nline 3',
          newText: 'line 1\nmodified line 2\nline 3',
        ));
        await safePumpAndSettle(tester);

        // Should display line numbers
        expect(find.text('1'), findsWidgets);
      });

      testWidgets('line numbers adjust based on diff operations',
          (tester) async {
        final structuredPatch = [
          {
            'oldStart': 5,
            'oldLines': 2,
            'newStart': 5,
            'newLines': 2,
            'lines': [
              '-old line at 5',
              '+new line at 5',
            ],
          },
        ];

        await tester.pumpWidget(createTestApp(
          oldText: '',
          newText: '',
          structuredPatch: structuredPatch,
        ));
        await safePumpAndSettle(tester);

        // Should show line number 5 for the patch
        expect(find.text('5'), findsWidgets);
      });
    });
  });
}
