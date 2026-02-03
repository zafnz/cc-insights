import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/widgets/delete_worktree_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';
import '../fakes/fake_persistence_service.dart';
import '../fakes/fake_ask_ai_service.dart';
import '../test_helpers.dart';

void main() {
  late FakeGitService gitService;
  late FakePersistenceService persistenceService;
  late FakeAskAiService askAiService;

  const testWorktreePath = '/repo/worktrees/feature';
  const testRepoRoot = '/repo';
  const testBranch = 'feature-branch';
  const testProjectId = 'abc12345';

  setUp(() {
    gitService = FakeGitService();
    persistenceService = FakePersistenceService();
    askAiService = FakeAskAiService();

    // Set up default clean worktree
    gitService.statuses[testWorktreePath] = const GitStatus();
    gitService.mainBranches[testRepoRoot] = 'main';
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await showDeleteWorktreeDialog(
                context: context,
                worktreePath: testWorktreePath,
                repoRoot: testRepoRoot,
                branch: testBranch,
                projectId: testProjectId,
                gitService: gitService,
                persistenceService: persistenceService,
                askAiService: askAiService,
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );
  }

  group('DeleteWorktreeDialog', () {
    testWidgets('shows dialog when opened', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      expect(find.byKey(DeleteWorktreeDialogKeys.dialog), findsOneWidget);
      expect(find.text('Delete Worktree'), findsOneWidget);
    });

    testWidgets('deletes clean worktree with merged branch', (tester) async {
      // Set up: clean worktree, branch merged
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.branchMerged['$testWorktreePath:$testBranch:main'] = true;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for status check
      await pumpUntilGone(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.progressIndicator),
      );

      // Should complete deletion without prompts
      expect(gitService.fetchCalls, contains(testWorktreePath));
      expect(gitService.removeWorktreeCalls.length, 1);
      expect(
        gitService.removeWorktreeCalls.first.worktreePath,
        testWorktreePath,
      );
      expect(gitService.removeWorktreeCalls.first.force, false);
    });

    testWidgets('prompts for uncommitted changes', (tester) async {
      // Set up: worktree with uncommitted changes
      gitService.statuses[testWorktreePath] = const GitStatus(
        unstaged: 3,
        untracked: 2,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for status check
      await pumpUntilFound(tester, find.text('Uncommitted Changes'));

      expect(find.text('Uncommitted Changes'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Commit All'), findsOneWidget);
    });

    testWidgets('stashes changes when Discard is selected', (tester) async {
      // Set up: worktree with uncommitted changes, branch merged
      gitService.statuses[testWorktreePath] = const GitStatus(unstaged: 1);
      gitService.branchMerged['$testWorktreePath:$testBranch:main'] = true;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for uncommitted changes prompt
      await pumpUntilFound(tester, find.text('Discard'));

      // Tap Discard
      await tester.tap(find.text('Discard'));
      await tester.pump();

      // Wait for deletion to complete
      await pumpUntilGone(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.progressIndicator),
      );

      expect(gitService.stashCalls, contains(testWorktreePath));
      expect(gitService.removeWorktreeCalls.length, 1);
    });

    testWidgets('prompts for unmerged branch', (tester) async {
      // Set up: clean worktree, branch NOT merged
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.branchMerged['$testWorktreePath:$testBranch:main'] = false;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for unmerged prompt
      await pumpUntilFound(tester, find.text('Unmerged Branch'));

      expect(find.text('Unmerged Branch'), findsOneWidget);
      expect(find.text('Delete Anyway'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('deletes unmerged branch when Delete Anyway is clicked',
        (tester) async {
      // Set up: clean worktree, branch NOT merged
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.branchMerged['$testWorktreePath:$testBranch:main'] = false;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for unmerged prompt
      await pumpUntilFound(tester, find.text('Delete Anyway'));

      // Tap Delete Anyway
      await tester.tap(find.text('Delete Anyway'));
      await tester.pump();

      // Wait for deletion
      await pumpUntilGone(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.progressIndicator),
      );

      expect(gitService.removeWorktreeCalls.length, 1);
    });

    testWidgets('prompts for force delete on git error', (tester) async {
      // Set up: clean worktree, branch merged, but git remove fails
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.branchMerged['$testWorktreePath:$testBranch:main'] = true;
      gitService.removeWorktreeError = const GitException(
        'worktree is dirty',
        stderr: 'fatal: worktree contains modified files',
      );
      gitService.removeWorktreeOnlyThrowOnNonForce = true;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for force delete prompt
      await pumpUntilFound(tester, find.text('Force Delete'));

      expect(find.text('Worktree Has Changes'), findsOneWidget);
      expect(find.text('Force Delete'), findsOneWidget);
    });

    testWidgets('force deletes when Force Delete is clicked', (tester) async {
      // Set up: clean worktree, branch merged, but git remove fails initially
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.branchMerged['$testWorktreePath:$testBranch:main'] = true;
      gitService.removeWorktreeError = const GitException(
        'worktree is dirty',
        stderr: 'fatal: worktree contains modified files',
      );
      gitService.removeWorktreeOnlyThrowOnNonForce = true;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for force delete prompt
      await pumpUntilFound(tester, find.text('Force Delete'));

      // Tap Force Delete
      await tester.tap(find.text('Force Delete'));
      await tester.pump();

      // Wait for dialog to close
      await pumpUntilGone(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.dialog),
      );

      // Verify force was used
      expect(gitService.removeWorktreeCalls.length, 2);
      expect(gitService.removeWorktreeCalls.last.force, true);
    });

    testWidgets('cancels when Cancel is clicked on uncommitted prompt',
        (tester) async {
      // Set up: worktree with uncommitted changes
      gitService.statuses[testWorktreePath] = const GitStatus(unstaged: 1);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for uncommitted changes prompt (specific text)
      await pumpUntilFound(tester, find.text('Uncommitted Changes'));

      // Tap Cancel using key to avoid ambiguity
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.cancelButton));
      await tester.pump();

      // Wait for dialog to close - pump a few frames to allow navigation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify dialog is closed
      expect(find.byKey(DeleteWorktreeDialogKeys.dialog), findsNothing);

      // No deletion should have occurred
      expect(gitService.removeWorktreeCalls, isEmpty);
    });

    testWidgets('cancels when Cancel is clicked on unmerged prompt',
        (tester) async {
      // Set up: clean worktree, branch NOT merged
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.branchMerged['$testWorktreePath:$testBranch:main'] = false;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for unmerged prompt (specific text)
      await pumpUntilFound(tester, find.text('Unmerged Branch'));

      // Tap Cancel using key to avoid ambiguity
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.cancelButton));
      await tester.pump();

      // Wait for dialog to close - pump a few frames to allow navigation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify dialog is closed
      expect(find.byKey(DeleteWorktreeDialogKeys.dialog), findsNothing);

      // No deletion should have occurred
      expect(gitService.removeWorktreeCalls, isEmpty);
    });
  });
}
