import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/widgets/create_pr_dialog.dart';
import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_ask_ai_service.dart';
import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  late FakeGitService gitService;
  late FakeAskAiService askAiService;

  const testWorktreePath = '/repo/worktrees/feature';
  const testBranch = 'add-new-feature';
  const testMainBranch = 'main';

  final testCommits = [
    (sha: 'abc1234', message: 'Add new widget'),
    (sha: 'def5678', message: 'Fix styling issue'),
    (sha: 'ghi9012', message: 'Update tests'),
  ];

  setUp(() {
    gitService = FakeGitService();
    askAiService = FakeAskAiService();

    // Default: commits available
    final commitKey = '$testWorktreePath:$testMainBranch';
    gitService.commitsAhead[commitKey] = testCommits;
    gitService.branches[testWorktreePath] = testBranch;
  });

  bool? dialogResult;

  Widget createTestWidget() {
    dialogResult = null;
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              dialogResult = await showCreatePrDialog(
                context: context,
                worktreePath: testWorktreePath,
                branch: testBranch,
                mainBranch: testMainBranch,
                gitService: gitService,
                askAiService: askAiService,
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
  }

  group('CreatePrDialog', () {
    testWidgets('shows dialog with correct title and branch info',
        (tester) async {
      await openDialog(tester);

      expect(
        find.byKey(CreatePrDialogKeys.dialog),
        findsOneWidget,
      );
      expect(find.text('Create Pull Request'), findsOneWidget);
      expect(
        find.textContaining('$testBranch \u2192 $testMainBranch'),
        findsOneWidget,
      );
    });

    testWidgets('shows three tabs', (tester) async {
      await openDialog(tester);

      expect(
        find.byKey(CreatePrDialogKeys.customTab),
        findsOneWidget,
      );
      expect(
        find.byKey(CreatePrDialogKeys.changelogTab),
        findsOneWidget,
      );
      expect(
        find.byKey(CreatePrDialogKeys.previewTab),
        findsOneWidget,
      );
    });

    testWidgets('auto-populates title from branch name for '
        'multiple commits', (tester) async {
      await openDialog(tester);
      // Wait for commits to load
      await tester.pump();

      final titleField = tester.widget<TextField>(
        find.byKey(CreatePrDialogKeys.titleField),
      );
      expect(
        titleField.controller!.text,
        'Add new feature',
      );
    });

    testWidgets('auto-populates title from single commit message',
        (tester) async {
      final commitKey = '$testWorktreePath:$testMainBranch';
      gitService.commitsAhead[commitKey] = [
        (sha: 'abc1234', message: 'Add login form'),
      ];

      await openDialog(tester);
      await tester.pump();

      final titleField = tester.widget<TextField>(
        find.byKey(CreatePrDialogKeys.titleField),
      );
      expect(titleField.controller!.text, 'Add login form');
    });

    testWidgets('shows commits in changelog tab', (tester) async {
      await openDialog(tester);
      await tester.pump();

      // Switch to changelog tab
      await tester.tap(find.byKey(CreatePrDialogKeys.changelogTab));
      await safePumpAndSettle(tester);

      expect(find.text('abc1234'), findsOneWidget);
      expect(find.text('Add new widget'), findsOneWidget);
      expect(find.text('def5678'), findsOneWidget);
      expect(find.text('Fix styling issue'), findsOneWidget);
      expect(find.text('ghi9012'), findsOneWidget);
      expect(find.text('Update tests'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog returning false',
        (tester) async {
      await openDialog(tester);

      await tester.tap(find.byKey(CreatePrDialogKeys.cancelButton));
      await tester.pumpAndSettle();

      expect(dialogResult, false);
    });

    testWidgets('Create PR button calls push and createPullRequest',
        (tester) async {
      await openDialog(tester);
      await tester.pump();

      // Set title (should be auto-populated, but let's be explicit)
      await tester.enterText(
        find.byKey(CreatePrDialogKeys.titleField),
        'My PR Title',
      );
      await tester.pump();

      // Type body in custom tab
      await tester.enterText(
        find.byKey(CreatePrDialogKeys.bodyField),
        'PR description body',
      );
      await tester.pump();

      // Tap Create PR
      await tester.tap(find.byKey(CreatePrDialogKeys.createButton));
      await tester.pumpAndSettle();

      // Verify push was called with setUpstream
      expect(gitService.pushCalls, hasLength(1));
      expect(gitService.pushCalls.first.path, testWorktreePath);
      expect(gitService.pushCalls.first.setUpstream, true);

      // Verify createPullRequest was called
      expect(gitService.createPullRequestCalls, hasLength(1));
      final prCall = gitService.createPullRequestCalls.first;
      expect(prCall.path, testWorktreePath);
      expect(prCall.title, 'My PR Title');
      expect(prCall.body, 'PR description body');
      expect(prCall.draft, false);

      expect(dialogResult, true);
    });

    testWidgets('Create as Draft button creates draft PR',
        (tester) async {
      await openDialog(tester);
      await tester.pump();

      await tester.enterText(
        find.byKey(CreatePrDialogKeys.titleField),
        'Draft PR',
      );
      await tester.pump();

      await tester.tap(find.byKey(CreatePrDialogKeys.draftButton));
      await tester.pumpAndSettle();

      expect(gitService.createPullRequestCalls, hasLength(1));
      expect(gitService.createPullRequestCalls.first.draft, true);
      expect(dialogResult, true);
    });

    testWidgets('shows error when push fails', (tester) async {
      gitService.pushError = const GitException(
        'Push failed: no remote configured',
      );

      await openDialog(tester);
      await tester.pump();

      await tester.enterText(
        find.byKey(CreatePrDialogKeys.titleField),
        'My PR',
      );
      await tester.pump();

      await tester.tap(find.byKey(CreatePrDialogKeys.createButton));
      await tester.pump();

      expect(
        find.byKey(CreatePrDialogKeys.errorMessage),
        findsOneWidget,
      );
      expect(
        find.textContaining('no remote configured'),
        findsOneWidget,
      );
      // Dialog should still be open
      expect(
        find.byKey(CreatePrDialogKeys.dialog),
        findsOneWidget,
      );
    });

    testWidgets('shows error when createPullRequest fails',
        (tester) async {
      gitService.createPullRequestError = const GitException(
        'A pull request already exists for this branch',
      );

      await openDialog(tester);
      await tester.pump();

      await tester.enterText(
        find.byKey(CreatePrDialogKeys.titleField),
        'My PR',
      );
      await tester.pump();

      await tester.tap(find.byKey(CreatePrDialogKeys.createButton));
      await tester.pump();

      expect(
        find.byKey(CreatePrDialogKeys.errorMessage),
        findsOneWidget,
      );
      expect(
        find.textContaining('already exists'),
        findsOneWidget,
      );
    });

    testWidgets('Create PR button is disabled when title is empty',
        (tester) async {
      // Use no commits so title won't auto-populate
      final commitKey = '$testWorktreePath:$testMainBranch';
      gitService.commitsAhead[commitKey] = [];

      await openDialog(tester);
      await tester.pump();

      // Clear any title text
      await tester.enterText(
        find.byKey(CreatePrDialogKeys.titleField),
        '',
      );
      await tester.pump();

      // Verify Create PR button is disabled
      final createButton = tester.widget<FilledButton>(
        find.byKey(CreatePrDialogKeys.createButton),
      );
      expect(createButton.onPressed, isNull);

      // Verify Draft button is also disabled
      final draftButton = tester.widget<OutlinedButton>(
        find.byKey(CreatePrDialogKeys.draftButton),
      );
      expect(draftButton.onPressed, isNull);

      // No push should have been attempted
      expect(gitService.pushCalls, isEmpty);
    });

    testWidgets('shows "No commits found" when no commits ahead',
        (tester) async {
      final commitKey = '$testWorktreePath:$testMainBranch';
      gitService.commitsAhead[commitKey] = [];

      await openDialog(tester);
      await tester.pump();

      // Switch to changelog tab
      await tester.tap(find.byKey(CreatePrDialogKeys.changelogTab));
      await safePumpAndSettle(tester);

      expect(find.text('No commits found'), findsOneWidget);
    });

    testWidgets('preview tab shows AI description', (tester) async {
      askAiService.nextResult = const SingleRequestResult(
        result: '===BEGIN===\n## Summary\nAdds new feature\n===END===',
        isError: false,
        durationMs: 100,
        durationApiMs: 80,
        numTurns: 1,
        totalCostUsd: 0.001,
        usage: Usage(inputTokens: 100, outputTokens: 50),
      );

      await openDialog(tester);
      // Wait for commits to load and AI generation to complete
      await safePumpAndSettle(tester);

      // Switch to preview tab
      await tester.tap(find.byKey(CreatePrDialogKeys.previewTab));
      await safePumpAndSettle(tester);

      expect(find.textContaining('Adds new feature'), findsOneWidget);
    });

    testWidgets('AI generation populates body field', (tester) async {
      askAiService.nextResult = const SingleRequestResult(
        result:
            '===BEGIN===\n## Summary\nNew feature body\n===END===',
        isError: false,
        durationMs: 100,
        durationApiMs: 80,
        numTurns: 1,
        totalCostUsd: 0.001,
        usage: Usage(inputTokens: 100, outputTokens: 50),
      );

      await openDialog(tester);
      await safePumpAndSettle(tester);

      final bodyField = tester.widget<TextField>(
        find.byKey(CreatePrDialogKeys.bodyField),
      );
      expect(
        bodyField.controller!.text,
        '## Summary\nNew feature body',
      );
    });

    testWidgets('error bar can be dismissed', (tester) async {
      gitService.pushError = const GitException('Push failed');

      await openDialog(tester);
      await tester.pump();

      await tester.enterText(
        find.byKey(CreatePrDialogKeys.titleField),
        'My PR',
      );
      await tester.pump();

      await tester.tap(find.byKey(CreatePrDialogKeys.createButton));
      await tester.pump();

      // Error should be visible
      expect(
        find.byKey(CreatePrDialogKeys.errorMessage),
        findsOneWidget,
      );

      // Dismiss it
      await tester.tap(find.descendant(
        of: find.byKey(CreatePrDialogKeys.errorMessage),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pump();

      expect(
        find.byKey(CreatePrDialogKeys.errorMessage),
        findsNothing,
      );
    });

    testWidgets('AI generation uses haiku model', (tester) async {
      askAiService.nextResult = const SingleRequestResult(
        result: '===BEGIN===\nTest\n===END===',
        isError: false,
        durationMs: 100,
        durationApiMs: 80,
        numTurns: 1,
        totalCostUsd: 0.001,
        usage: Usage(inputTokens: 100, outputTokens: 50),
      );

      await openDialog(tester);
      await safePumpAndSettle(tester);

      expect(askAiService.askCalls, hasLength(1));
      expect(askAiService.askCalls.first.model, 'haiku');
      expect(
        askAiService.askCalls.first.workingDirectory,
        testWorktreePath,
      );
    });
  });
}
