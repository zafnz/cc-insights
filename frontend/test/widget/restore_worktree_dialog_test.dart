import 'package:cc_insights_v2/services/git_service.dart' show WorktreeInfo;
import 'package:cc_insights_v2/widgets/restore_worktree_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  /// Test data for restorable worktrees.
  const testWorktrees = [
    WorktreeInfo(
        path: '/path/to/worktree1', isPrimary: false, branch: 'feature-a'),
    WorktreeInfo(
        path: '/path/to/worktree2', isPrimary: false, branch: 'bugfix-b'),
    WorktreeInfo(
        path: '/very/long/path/to/some/deeply/nested/directory/worktree3',
        isPrimary: false,
        branch: 'feature-c'),
  ];

  /// Pumps a [MaterialApp] that shows the [RestoreWorktreeDialog] when a
  /// button is tapped. Returns after the dialog is open.
  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<WorktreeInfo> worktrees,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await showRestoreWorktreeDialog(
                    context: context,
                    restorableWorktrees: worktrees,
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

  group('RestoreWorktreeDialog', () {
    testWidgets('shows worktree list with branches and paths',
        (tester) async {
      await pumpDialog(tester, worktrees: testWorktrees);

      // Verify title and icon.
      expect(find.text('Restore Worktree'), findsOneWidget);
      expect(find.byIcon(Icons.restore), findsOneWidget);

      // Verify each worktree is displayed with branch and path.
      for (final worktree in testWorktrees) {
        expect(find.text(worktree.branch!), findsOneWidget);
        expect(find.text(worktree.path), findsOneWidget);
      }

      // Verify cancel button.
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('returns selected worktree when item is tapped',
        (tester) async {
      WorktreeInfo? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showRestoreWorktreeDialog(
                      context: context,
                      restorableWorktrees: testWorktrees,
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

      // Tap the second worktree item.
      await tester.tap(find.byKey(const Key('restore_worktree_item_1')));
      await safePumpAndSettle(tester);

      // Verify the correct worktree was returned.
      check(result).isNotNull();
      check(result!.path).equals(testWorktrees[1].path);
      check(result!.branch).equals(testWorktrees[1].branch);
    });

    testWidgets('returns null when cancel is tapped', (tester) async {
      WorktreeInfo? result = const WorktreeInfo(
          path: '/sentinel', isPrimary: false, branch: 'sentinel');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showRestoreWorktreeDialog(
                      context: context,
                      restorableWorktrees: testWorktrees,
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

    testWidgets('shows empty state when worktree list is empty',
        (tester) async {
      await pumpDialog(tester, worktrees: const []);

      // Verify empty state message is displayed.
      expect(
        find.text('No worktrees available to restore'),
        findsOneWidget,
      );

      // Verify no worktree items are displayed (check for test keys).
      expect(find.byKey(const Key('restore_worktree_item_0')), findsNothing);

      // Verify cancel button is still present.
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows detached HEAD for worktrees without branch',
        (tester) async {
      const detachedWorktrees = [
        WorktreeInfo(
            path: '/path/to/detached', isPrimary: false, branch: null),
      ];

      await pumpDialog(tester, worktrees: detachedWorktrees);

      // Verify detached HEAD message is displayed.
      expect(find.text('(detached HEAD)'), findsOneWidget);
      expect(find.text('/path/to/detached'), findsOneWidget);
    });

    testWidgets('all items have proper test keys', (tester) async {
      await pumpDialog(tester, worktrees: testWorktrees);

      // Verify each item has the expected key.
      for (int i = 0; i < testWorktrees.length; i++) {
        expect(
          find.byKey(Key('restore_worktree_item_$i')),
          findsOneWidget,
        );
      }
    });

    testWidgets('long paths are properly displayed with ellipsis',
        (tester) async {
      await pumpDialog(tester, worktrees: testWorktrees);

      // Find the Text widget with the long path.
      final pathTextFinder = find.text(testWorktrees[2].path);
      expect(pathTextFinder, findsOneWidget);

      // Verify the Text widget has overflow set to ellipsis.
      final pathText = tester.widget<Text>(pathTextFinder);
      check(pathText.overflow).equals(TextOverflow.ellipsis);
      check(pathText.maxLines).equals(1);
    });

    testWidgets('shows warning icon for prunable worktrees', (tester) async {
      const prunableWorktrees = [
        WorktreeInfo(
          path: '/path/to/healthy',
          isPrimary: false,
          branch: 'healthy-branch',
        ),
        WorktreeInfo(
          path: '/path/to/stale',
          isPrimary: false,
          branch: 'stale-branch',
          isPrunable: true,
        ),
      ];

      await pumpDialog(tester, worktrees: prunableWorktrees);

      // Verify warning icon is shown for the prunable worktree
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);

      // Both worktrees should be listed
      expect(find.text('healthy-branch'), findsOneWidget);
      expect(find.text('stale-branch'), findsOneWidget);
    });

    testWidgets('does not show warning icon for non-prunable worktrees',
        (tester) async {
      await pumpDialog(tester, worktrees: testWorktrees);

      // No warning icons should be present (none are prunable)
      expect(find.byIcon(Icons.warning_amber), findsNothing);
    });
  });
}
