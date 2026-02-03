import 'package:cc_insights_v2/services/file_system_service.dart';
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
  late FakeFileSystemService fileSystemService;

  const testWorktreePath = '/repo/worktrees/feature';
  const testRepoRoot = '/repo';
  const testBranch = 'feature-branch';
  const testProjectId = 'abc12345';

  setUp(() {
    gitService = FakeGitService();
    persistenceService = FakePersistenceService();
    askAiService = FakeAskAiService();
    fileSystemService = FakeFileSystemService();

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
                fileSystemService: fileSystemService,
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
      // Set up: clean worktree
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
      expect(find.byKey(DeleteWorktreeDialogKeys.discardButton), findsOneWidget);
      expect(find.byKey(DeleteWorktreeDialogKeys.commitButton), findsOneWidget);
    });

    testWidgets('stashes changes when Discard is selected', (tester) async {
      // Set up: worktree with uncommitted changes
      gitService.statuses[testWorktreePath] = const GitStatus(unstaged: 1, changedEntries: 1);

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

    testWidgets('shows commits ahead warning', (tester) async {
      // Set up: clean worktree with commits ahead
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.commitsAhead['$testWorktreePath:main'] = [
        (sha: 'abc123', message: 'First commit'),
        (sha: 'def456', message: 'Second commit'),
      ];

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for delete button
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.deleteButton),
      );

      // Should show commits ahead in log
      expect(find.textContaining('2 commits ahead'), findsOneWidget);
    });

    testWidgets('shows unmerged commits error and requires force delete',
        (tester) async {
      // Set up: clean worktree with commits that aren't on main
      gitService.statuses[testWorktreePath] = const GitStatus();
      gitService.commitsAhead['$testWorktreePath:main'] = [
        (sha: 'abc123', message: 'First commit'),
        (sha: 'def456', message: 'Second commit'),
      ];
      gitService.unmergedCommits['$testWorktreePath:$testBranch:main'] = [
        'First commit',
      ];

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();

      // Wait for force delete button (unmerged commits requires force)
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton),
      );

      // Should show error about unmerged commits
      expect(find.textContaining('not yet on main'), findsOneWidget);

      // Should show Abort button instead of Cancel
      expect(find.text('Abort'), findsOneWidget);
      expect(find.byKey(DeleteWorktreeDialogKeys.cancelButton), findsNothing);
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
      gitService.statuses[testWorktreePath] = const GitStatus(unstaged: 1, changedEntries: 1);

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
      gitService.statuses[testWorktreePath] = const GitStatus(unstaged: 1, changedEntries: 1);

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
}
