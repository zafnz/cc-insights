import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/widgets/conflict_resolution_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  late FakeGitService gitService;

  const testWorktreePath = '/repo/worktrees/feature';
  const testBranch = 'feature-branch';
  const testMainBranch = 'main';

  setUp(() {
    gitService = FakeGitService();
    // Default: clean worktree
    gitService.statuses[testWorktreePath] = const GitStatus();
  });

  Widget createTestWidget({
    MergeOperationType operation = MergeOperationType.merge,
    ConflictResolutionResult? capturedResult,
    bool fetchFirst = false,
  }) {
    ConflictResolutionResult? result;
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              ElevatedButton(
                onPressed: () async {
                  result = await showConflictResolutionDialog(
                    context: context,
                    worktreePath: testWorktreePath,
                    branch: testBranch,
                    mainBranch: testMainBranch,
                    operation: operation,
                    gitService: gitService,
                    fetchFirst: fetchFirst,
                  );
                },
                child: const Text('Open Dialog'),
              ),
              // Display result for verification
              Builder(
                builder: (_) => Text(
                  'result:${result?.name ?? 'none'}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('ConflictResolutionDialog', () {
    testWidgets('shows dialog when opened', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      expect(
        find.byKey(ConflictResolutionDialogKeys.dialog),
        findsOneWidget,
      );
      expect(find.textContaining('Merge from main'), findsOneWidget);
    });

    testWidgets('shows Rebase header for rebase operation',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(operation: MergeOperationType.rebase),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      expect(
        find.textContaining('Rebase from main'),
        findsOneWidget,
      );
    });

    testWidgets(
        'auto-closes with success when no conflicts',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for dialog to process and auto-close
      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      // Verify merge was called
      expect(gitService.mergeCalls.length, 1);
      expect(gitService.mergeCalls.first.$2, testMainBranch);
    });

    testWidgets(
        'shows conflict buttons when conflicts detected',
        (tester) async {
      gitService.mergeResults[testWorktreePath] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.merge,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for conflict buttons to appear
      await pumpUntilFound(
        tester,
        find.byKey(ConflictResolutionDialogKeys.resolveWithClaudeButton),
      );

      expect(
        find.byKey(ConflictResolutionDialogKeys.resolveWithClaudeButton),
        findsOneWidget,
      );
      expect(
        find.byKey(ConflictResolutionDialogKeys.resolveManuallyButton),
        findsOneWidget,
      );
      expect(
        find.byKey(ConflictResolutionDialogKeys.abortButton),
        findsOneWidget,
      );

      // Merge was called once (the real operation that found conflicts)
      expect(gitService.mergeCalls.length, 1);
    });

    testWidgets('abort aborts the operation and closes dialog',
        (tester) async {
      gitService.mergeResults[testWorktreePath] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.merge,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(ConflictResolutionDialogKeys.abortButton),
      );

      await tester.tap(
        find.byKey(ConflictResolutionDialogKeys.abortButton),
      );

      // Wait for dialog to close
      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      expect(
        find.byKey(ConflictResolutionDialogKeys.dialog),
        findsNothing,
      );

      // Merge was called once, then abort was called
      expect(gitService.mergeCalls.length, 1);
      expect(gitService.mergeAbortCalls.length, 1);
    });

    testWidgets('resolve with Claude closes with resolveWithClaude',
        (tester) async {
      gitService.mergeResults[testWorktreePath] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.merge,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(ConflictResolutionDialogKeys.resolveWithClaudeButton),
      );

      await tester.tap(
        find.byKey(ConflictResolutionDialogKeys.resolveWithClaudeButton),
      );
      await tester.pump();

      // Wait for dialog to close
      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      // Merge was called once (conflicts already on disk)
      expect(gitService.mergeCalls.length, 1);
    });

    testWidgets('resolve manually closes with resolveManually',
        (tester) async {
      gitService.mergeResults[testWorktreePath] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.merge,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(ConflictResolutionDialogKeys.resolveManuallyButton),
      );

      await tester.tap(
        find.byKey(ConflictResolutionDialogKeys.resolveManuallyButton),
      );
      await tester.pump();

      // Wait for dialog to close
      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      // Merge was called once (conflicts already on disk)
      expect(gitService.mergeCalls.length, 1);
    });

    testWidgets('shows error when working tree is dirty',
        (tester) async {
      // Set up dirty working tree
      gitService.statuses[testWorktreePath] = const GitStatus(
        unstaged: 3,
        changedEntries: 3,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for the error message
      await pumpUntilFound(
        tester,
        find.textContaining('uncommitted'),
      );

      expect(find.textContaining('uncommitted'), findsOneWidget);

      // No merge should have been called
      expect(gitService.mergeCalls.length, 0);
    });

    testWidgets('rebase operation calls rebase', (tester) async {
      await tester.pumpWidget(
        createTestWidget(operation: MergeOperationType.rebase),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for dialog to process and auto-close
      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      // Rebase should have been called (not merge)
      expect(gitService.rebaseCalls.length, 1);
      expect(gitService.mergeCalls.length, 0);
    });

    testWidgets('rebase abort calls rebaseAbort', (tester) async {
      gitService.rebaseResults[testWorktreePath] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.rebase,
      );

      await tester.pumpWidget(
        createTestWidget(operation: MergeOperationType.rebase),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(ConflictResolutionDialogKeys.abortButton),
      );

      await tester.tap(
        find.byKey(ConflictResolutionDialogKeys.abortButton),
      );

      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      expect(gitService.rebaseCalls.length, 1);
      expect(gitService.rebaseAbortCalls.length, 1);
      expect(gitService.mergeAbortCalls.length, 0);
    });

    testWidgets('shows log entries during processing',
        (tester) async {
      gitService.mergeResults[testWorktreePath] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.merge,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for the conflict buttons to appear (workflow complete)
      await pumpUntilFound(
        tester,
        find.byKey(ConflictResolutionDialogKeys.resolveWithClaudeButton),
      );

      // Should show log list
      expect(
        find.byKey(ConflictResolutionDialogKeys.logList),
        findsOneWidget,
      );

      // Should show completed log messages (clean + conflicts)
      expect(find.textContaining('clean'), findsOneWidget);
      expect(find.textContaining('Conflicts'), findsOneWidget);
    });

    testWidgets('fetchFirst fetches before performing operation',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(fetchFirst: true),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for dialog to process and auto-close
      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      // Fetch should have been called
      expect(gitService.fetchCalls.length, 1);
      expect(gitService.fetchCalls.first, testWorktreePath);

      // Merge should still have been called
      expect(gitService.mergeCalls.length, 1);
    });

    testWidgets('fetchFirst shows fetch log entry', (tester) async {
      gitService.mergeResults[testWorktreePath] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.merge,
      );

      await tester.pumpWidget(
        createTestWidget(fetchFirst: true),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for conflict buttons (workflow done)
      await pumpUntilFound(
        tester,
        find.byKey(ConflictResolutionDialogKeys.resolveWithClaudeButton),
      );

      // Should show fetch log entry
      expect(
        find.textContaining('Fetched latest changes'),
        findsOneWidget,
      );
    });

    testWidgets('fetchFirst failure stops workflow', (tester) async {
      gitService.fetchError = const GitException('network error');

      await tester.pumpWidget(
        createTestWidget(fetchFirst: true),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for the error message
      await pumpUntilFound(
        tester,
        find.textContaining('Fetch failed'),
      );

      expect(find.textContaining('Fetch failed'), findsOneWidget);

      // No merge should have been called
      expect(gitService.mergeCalls.length, 0);
    });

    testWidgets('without fetchFirst does not call fetch',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for dialog to process and auto-close
      await pumpUntilGone(
        tester,
        find.byKey(ConflictResolutionDialogKeys.dialog),
      );

      // Fetch should NOT have been called
      expect(gitService.fetchCalls.length, 0);
    });
  });
}
