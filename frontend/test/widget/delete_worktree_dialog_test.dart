import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/widgets/delete_worktree_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';
import '../fakes/fake_persistence_service.dart';
import '../fakes/fake_ask_ai_service.dart';
import '../fakes/fake_project_config_service.dart';
import '../test_helpers.dart';

void main() {
  late FakeGitService gitService;
  late FakePersistenceService persistenceService;
  late FakeAskAiService askAiService;
  late FakeFileSystemService fileSystemService;
  late FakeProjectConfigService configService;

  const testWorktreePath = '/repo/worktrees/feature';
  const testRepoRoot = '/repo';
  const testBranch = 'feature-branch';
  const testBase = 'main';
  const testProjectId = 'abc12345';

  setUp(() {
    gitService = FakeGitService();
    persistenceService = FakePersistenceService();
    askAiService = FakeAskAiService();
    fileSystemService = FakeFileSystemService();
    configService = FakeProjectConfigService();

    // Set up default clean worktree
    gitService.statuses[testWorktreePath] = const GitStatus();
  });

  Widget createTestWidget({String base = testBase}) {
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
                base: base,
                projectId: testProjectId,
                gitService: gitService,
                persistenceService: persistenceService,
                askAiService: askAiService,
                fileSystemService: fileSystemService,
                configService: configService,
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

    testWidgets('shows log list with entries', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      expect(find.byKey(DeleteWorktreeDialogKeys.logList), findsOneWidget);
      // Should show "Checking for uncommitted changes..."
      expect(find.textContaining('Checking'), findsWidgets);
    });

    testWidgets('deletes clean worktree and shows log', (tester) async {
      // Set up: clean worktree, isBranchMerged defaults to true
      gitService.statuses[testWorktreePath] = const GitStatus();

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for "Delete Worktree" button to appear (ready state)
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      // Should show log entries
      expect(find.textContaining('clean'), findsOneWidget);
      expect(find.textContaining('origin'), findsWidgets);

      // Tap delete button
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.deleteButton));
      await tester.pump();

      // Wait for dialog to close
      await pumpUntilGone(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.dialog),
      );

      expect(gitService.removeWorktreeCalls.length, 1);
      expect(
        gitService.removeWorktreeCalls.first.worktreePath,
        testWorktreePath,
      );
    });

    testWidgets('shows uncommitted files warning and action buttons',
        (tester) async {
      // Set up: worktree with uncommitted changes
      gitService.statuses[testWorktreePath] = const GitStatus(
        unstaged: 3,
        changedEntries: 3,
        untracked: 2,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for Discard button to appear
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.discardButton),
      );

      // Should show warning about uncommitted files
      expect(find.textContaining('uncommitted'), findsOneWidget);
      expect(
          find.byKey(DeleteWorktreeDialogKeys.discardButton), findsOneWidget);
      expect(
          find.byKey(DeleteWorktreeDialogKeys.commitButton), findsOneWidget);
    });

    testWidgets('stashes changes when Discard is selected', (tester) async {
      // Set up: worktree with uncommitted changes
      gitService.statuses[testWorktreePath] =
          const GitStatus(unstaged: 1, changedEntries: 1);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for Discard button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.discardButton),
      );

      // Tap Discard
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.discardButton));
      await tester.pump();

      // Wait for delete button (ready state after stash)
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      // Should show stash message in log
      expect(find.textContaining('stashed'), findsOneWidget);
      expect(gitService.stashCalls, contains(testWorktreePath));

      // Tap delete
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.deleteButton));
      await tester.pump();

      // Wait for dialog to close
      await pumpUntilGone(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.dialog),
      );

      expect(gitService.removeWorktreeCalls.length, 1);
    });

    testWidgets('prompts for force delete on git error', (tester) async {
      // Set up: clean worktree, but git remove fails
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.removeWorktreeError = const GitException(
        'worktree is dirty',
        stderr: 'fatal: worktree contains modified files',
      );
      gitService.removeWorktreeOnlyThrowOnNonForce = true;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for delete button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      // Tap delete
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.deleteButton));
      await tester.pump();

      // Wait for force delete button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
      );

      expect(
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
        findsOneWidget,
      );
      expect(find.textContaining('Failed to remove worktree'), findsOneWidget);
    });

    testWidgets('force deletes when Force Delete is clicked', (tester) async {
      // Set up: clean worktree, but git remove fails initially
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.removeWorktreeError = const GitException(
        'worktree is dirty',
        stderr: 'fatal: worktree contains modified files',
      );
      gitService.removeWorktreeOnlyThrowOnNonForce = true;

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for delete button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      // Tap delete
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.deleteButton));
      await tester.pump();

      // Wait for force delete button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
      );

      // Tap Force Delete
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton));
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
      gitService.statuses[testWorktreePath] =
          const GitStatus(unstaged: 1, changedEntries: 1);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for Discard button (indicates uncommitted state)
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.discardButton),
      );

      // Tap Cancel using key
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.cancelButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify dialog is closed
      expect(find.byKey(DeleteWorktreeDialogKeys.dialog), findsNothing);

      // No deletion should have occurred
      expect(gitService.removeWorktreeCalls, isEmpty);
    });

    testWidgets('cancels when Cancel is clicked on ready state',
        (tester) async {
      // Set up: clean worktree
      gitService.statuses[testWorktreePath] = const GitStatus();

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for delete button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      // Tap Cancel using key
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.cancelButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify dialog is closed
      expect(find.byKey(DeleteWorktreeDialogKeys.dialog), findsNothing);

      // No deletion should have occurred
      expect(gitService.removeWorktreeCalls, isEmpty);
    });

    testWidgets('shows stash recovery note after stashing', (tester) async {
      // Set up: worktree with uncommitted changes
      gitService.statuses[testWorktreePath] =
          const GitStatus(unstaged: 1, changedEntries: 1);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for Discard button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.discardButton),
      );

      // Tap Discard
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.discardButton));
      await tester.pump();

      // Wait for ready state
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      // Should show stash recovery note (both in log and footer)
      expect(find.textContaining('git stash pop'), findsWidgets);
    });
  });

  group('Safety check waterfall', () {
    testWidgets('Check 1: branch is ancestor of base -> safe delete',
        (tester) async {
      // isBranchMerged returns true by default in FakeGitService
      gitService.statuses[testWorktreePath] = const GitStatus();

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      expect(find.textContaining('All commits are on main'), findsOneWidget);
      expect(
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
        findsNothing,
      );
    });

    testWidgets('Check 2: squash merge detected -> safe delete',
        (tester) async {
      gitService.statuses[testWorktreePath] = const GitStatus();
      // Check 1 fails: branch is NOT ancestor of base
      gitService
          .branchMerged['$testWorktreePath:$testBranch:$testBase'] = false;
      // Check 2 passes: cherry returns empty (all squash merged)
      // (default is empty in FakeGitService)

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      expect(find.textContaining('squash merged'), findsOneWidget);
      expect(
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
        findsNothing,
      );
    });

    testWidgets('Check 3a: upstream up-to-date -> warning with delete button',
        (tester) async {
      gitService.statuses[testWorktreePath] = const GitStatus();
      // Check 1 fails
      gitService
          .branchMerged['$testWorktreePath:$testBranch:$testBase'] = false;
      // Check 2 fails: unmerged commits exist
      gitService.unmergedCommits['$testWorktreePath:$testBranch:$testBase'] = [
        'Some commit',
      ];
      // Check 3: upstream exists and is up-to-date (ahead == 0)
      gitService.upstreams[testWorktreePath] = 'origin/$testBranch';
      gitService.branchComparisons[
              '$testWorktreePath:$testBranch:origin/$testBranch'] =
          (ahead: 0, behind: 0);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Should show Delete Worktree button (not force), with warning message
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      expect(find.textContaining('up-to-date'), findsOneWidget);
      expect(find.textContaining('recoverable'), findsOneWidget);
      expect(find.text('Abort'), findsOneWidget);
      // Should be a regular delete button, not force
      expect(
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
        findsNothing,
      );
    });

    testWidgets('Check 3b: upstream behind -> force delete required',
        (tester) async {
      gitService.statuses[testWorktreePath] = const GitStatus();
      // Check 1 fails
      gitService
          .branchMerged['$testWorktreePath:$testBranch:$testBase'] = false;
      // Check 2 fails
      gitService.unmergedCommits['$testWorktreePath:$testBranch:$testBase'] = [
        'Some commit',
      ];
      // Check 3: upstream exists but is behind
      gitService.upstreams[testWorktreePath] = 'origin/$testBranch';
      gitService.branchComparisons[
              '$testWorktreePath:$testBranch:origin/$testBranch'] =
          (ahead: 2, behind: 0);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
      );

      expect(find.textContaining('lose work'), findsOneWidget);
      expect(find.text('Abort'), findsOneWidget);
    });

    testWidgets('Check 3c: no upstream -> force delete required',
        (tester) async {
      gitService.statuses[testWorktreePath] = const GitStatus();
      // Check 1 fails
      gitService
          .branchMerged['$testWorktreePath:$testBranch:$testBase'] = false;
      // Check 2 fails
      gitService.unmergedCommits['$testWorktreePath:$testBranch:$testBase'] = [
        'Some commit',
        'Another commit',
      ];
      // No upstream (gitService.upstreams does not have testWorktreePath)

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
      );

      expect(find.textContaining('No upstream'), findsOneWidget);
      expect(find.textContaining('lose work'), findsOneWidget);
      expect(find.text('Abort'), findsOneWidget);
    });

    testWidgets('works with remote base ref (origin/main)', (tester) async {
      gitService.statuses[testWorktreePath] = const GitStatus();
      // isBranchMerged with origin/main as base
      gitService
          .branchMerged['$testWorktreePath:$testBranch:origin/main'] = true;

      await tester.pumpWidget(createTestWidget(base: 'origin/main'));
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      expect(
        find.textContaining('All commits are on origin/main'),
        findsOneWidget,
      );
    });
  });
}
