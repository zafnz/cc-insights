import 'package:cc_insights_v2/widgets/branch_selector_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  /// Test data for branch names.
  const testBranches = [
    'feature-auth',
    'bugfix-header',
    'develop',
    'release/1.0',
  ];

  /// Pumps a [MaterialApp] that shows the [BranchSelectorDialog] when a
  /// button is tapped. Returns after the dialog is open.
  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<String> branches,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await showBranchSelectorDialog(
                    context: context,
                    branches: branches,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await safePumpAndSettle(tester);

    // Tap the button to open the dialog.
    await tester.tap(find.text('Open'));
    await safePumpAndSettle(tester);
  }

  group('BranchSelectorDialog', () {
    testWidgets('shows branch list with all branches', (tester) async {
      await pumpDialog(tester, branches: testBranches);

      // Verify title and icon.
      expect(find.text('Select Branch'), findsOneWidget);
      expect(find.byIcon(Icons.list_alt), findsOneWidget);

      // Verify each branch is displayed.
      for (final branch in testBranches) {
        expect(find.text(branch), findsOneWidget);
      }

      // Verify cancel button and search field.
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.byKey(BranchSelectorDialogKeys.searchField),
        findsOneWidget,
      );
    });

    testWidgets('returns selected branch when item is tapped', (tester) async {
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBranchSelectorDialog(
                      context: context,
                      branches: testBranches,
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      // Tap the second branch item.
      await tester.tap(find.byKey(const Key('branch_selector_item_1')));
      await safePumpAndSettle(tester);

      // Verify the correct branch was returned.
      check(result).isNotNull();
      check(result!).equals(testBranches[1]);
    });

    testWidgets('returns null when cancel is tapped', (tester) async {
      String? result = 'sentinel';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBranchSelectorDialog(
                      context: context,
                      branches: testBranches,
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      // Tap cancel button.
      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      // Verify null was returned.
      check(result).isNull();
    });

    testWidgets('shows empty state when branch list is empty', (tester) async {
      await pumpDialog(tester, branches: const []);

      // Verify empty state message is displayed.
      expect(find.text('No branches available'), findsOneWidget);

      // Verify no branch items are displayed.
      expect(find.byKey(const Key('branch_selector_item_0')), findsNothing);

      // Verify cancel button is still present.
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('filters branches when search text is entered', (tester) async {
      await pumpDialog(tester, branches: testBranches);

      // Enter search text.
      await tester.enterText(
        find.byKey(BranchSelectorDialogKeys.searchField),
        'feature',
      );
      await tester.pump();

      // Only 'feature-auth' should be visible.
      expect(find.text('feature-auth'), findsOneWidget);
      expect(find.text('bugfix-header'), findsNothing);
      expect(find.text('develop'), findsNothing);
      expect(find.text('release/1.0'), findsNothing);
    });

    testWidgets('shows no-match message when filter has no results',
        (tester) async {
      await pumpDialog(tester, branches: testBranches);

      // Enter search text that matches nothing.
      await tester.enterText(
        find.byKey(BranchSelectorDialogKeys.searchField),
        'zzz-nonexistent',
      );
      await tester.pump();

      // Should show no-match message.
      expect(find.text('No branches match filter'), findsOneWidget);
    });

    testWidgets('search is case insensitive', (tester) async {
      await pumpDialog(tester, branches: testBranches);

      // Enter uppercase search text.
      await tester.enterText(
        find.byKey(BranchSelectorDialogKeys.searchField),
        'FEATURE',
      );
      await tester.pump();

      // Should still find the branch.
      expect(find.text('feature-auth'), findsOneWidget);
    });

    testWidgets('all items have proper test keys', (tester) async {
      await pumpDialog(tester, branches: testBranches);

      // Verify each item has the expected key.
      for (int i = 0; i < testBranches.length; i++) {
        expect(
          find.byKey(Key('branch_selector_item_$i')),
          findsOneWidget,
        );
      }
    });
  });
}
