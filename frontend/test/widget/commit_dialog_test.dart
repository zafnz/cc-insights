import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/widgets/commit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_ask_ai_service.dart';
import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  late FakeGitService gitService;
  late FakeAskAiService askAiService;
  late FakeFileSystemService fileSystemService;

  const testWorktreePath = '/repo';

  setUp(() {
    gitService = FakeGitService();
    askAiService = FakeAskAiService();
    fileSystemService = FakeFileSystemService();
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await showCommitDialog(
                context: context,
                worktreePath: testWorktreePath,
                gitService: gitService,
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

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    // Wait for files to load
    await tester.pump();
  }

  group('CommitDialog', () {
    testWidgets('shows dialog with commit message selected by default',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/main.dart',
          status: GitFileStatus.modified,
          isStaged: false,
        ),
      ];

      await openDialog(tester);

      // Dialog is visible
      expect(
          find.byKey(CommitDialogKeys.dialog), findsOneWidget);

      // Commit Message item is visible and selected
      expect(find.byKey(CommitDialogKeys.commitMessageItem),
          findsOneWidget);
      expect(find.text('Commit Message'), findsOneWidget);

      // Message editor is shown (Edit/Preview tabs)
      expect(find.byKey(CommitDialogKeys.editTab), findsOneWidget);
      expect(
          find.byKey(CommitDialogKeys.previewTab), findsOneWidget);

      // File is listed
      expect(find.text('lib/main.dart'), findsOneWidget);

      // Files count label
      expect(find.text('Files (1)'), findsOneWidget);
    });

    testWidgets('clicking a file shows file content',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/main.dart',
          status: GitFileStatus.modified,
          isStaged: false,
        ),
      ];
      fileSystemService.addTextFile(
        '$testWorktreePath/lib/main.dart',
        'void main() {}',
      );
      gitService.fileAtRefContents[
          '$testWorktreePath:lib/main.dart:HEAD'] = 'void main() {\n}';

      await openDialog(tester);

      // Tap the file item
      await tester.tap(find.text('lib/main.dart'));
      await tester.pump();
      // Wait for file content to load
      await tester.pump();

      // Message editor should be gone
      expect(find.byKey(CommitDialogKeys.editTab), findsNothing);

      // File toolbar should show the file path
      // (one in left panel, one in toolbar)
      expect(find.text('lib/main.dart'), findsNWidgets(2));

      // Diff toggle button should be visible
      expect(
          find.byKey(CommitDialogKeys.diffToggle), findsOneWidget);
    });

    testWidgets(
        'clicking commit message returns to message editor',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/main.dart',
          status: GitFileStatus.modified,
          isStaged: false,
        ),
      ];
      fileSystemService.addTextFile(
        '$testWorktreePath/lib/main.dart',
        'void main() {}',
      );
      gitService.fileAtRefContents[
          '$testWorktreePath:lib/main.dart:HEAD'] = 'void main() {\n}';

      await openDialog(tester);

      // Click file
      await tester.tap(find.text('lib/main.dart'));
      await tester.pump();
      await tester.pump();

      // Verify file viewer is shown
      expect(find.byKey(CommitDialogKeys.editTab), findsNothing);

      // Click commit message
      await tester.tap(find.text('Commit Message'));
      await tester.pump();

      // Message editor should be back
      expect(find.byKey(CommitDialogKeys.editTab), findsOneWidget);
      expect(
          find.byKey(CommitDialogKeys.previewTab), findsOneWidget);
    });

    testWidgets('defaults to diff view, toggle switches to file view',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/main.dart',
          status: GitFileStatus.modified,
          isStaged: false,
        ),
      ];
      fileSystemService.addTextFile(
        '$testWorktreePath/lib/main.dart',
        'void main() { print("hello"); }',
      );
      gitService.fileAtRefContents[
              '$testWorktreePath:lib/main.dart:HEAD'] =
          'void main() {}';

      await openDialog(tester);

      // Click the file
      await tester.tap(find.text('lib/main.dart'));
      await tester.pump();
      await tester.pump();

      // Diff view should be shown by default
      expect(
          find.byKey(CommitDialogKeys.diffView), findsOneWidget);

      // Click the diff toggle to switch to file view
      await tester.tap(find.byKey(CommitDialogKeys.diffToggle));
      await tester.pump();

      // Diff view should be gone, code line view (file mode) shown
      expect(find.byKey(CommitDialogKeys.diffView), findsNothing);
      expect(find.byKey(CommitDialogKeys.codeLineView),
          findsOneWidget);
    });

    testWidgets('untracked file shows diff view by default',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/new_file.dart',
          status: GitFileStatus.untracked,
          isStaged: false,
        ),
      ];
      fileSystemService.addTextFile(
        '$testWorktreePath/lib/new_file.dart',
        'class NewFile {}',
      );
      // No HEAD version for untracked files

      await openDialog(tester);

      // Click the file
      await tester.tap(find.text('lib/new_file.dart'));
      await tester.pump();
      await tester.pump();

      // Diff toggle should be visible
      expect(
          find.byKey(CommitDialogKeys.diffToggle), findsOneWidget);

      // Diff view should be shown by default
      expect(
          find.byKey(CommitDialogKeys.diffView), findsOneWidget);
    });

    testWidgets('deleted file shows diff view by default',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/old_file.dart',
          status: GitFileStatus.deleted,
          isStaged: false,
        ),
      ];
      gitService.fileAtRefContents[
              '$testWorktreePath:lib/old_file.dart:HEAD'] =
          'class OldFile {}';

      await openDialog(tester);

      // Click the deleted file
      await tester.tap(find.text('lib/old_file.dart'));
      await tester.pump();
      await tester.pump();

      // Should auto-show diff for deleted files
      expect(
          find.byKey(CommitDialogKeys.diffView), findsOneWidget);
    });

    testWidgets('resizable divider exists', (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/main.dart',
          status: GitFileStatus.modified,
          isStaged: false,
        ),
      ];

      await openDialog(tester);

      // Resizable divider should exist
      expect(find.byKey(CommitDialogKeys.resizeDivider),
          findsOneWidget);
    });

    testWidgets('commit still works after viewing files',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/main.dart',
          status: GitFileStatus.modified,
          isStaged: false,
        ),
      ];
      fileSystemService.addTextFile(
        '$testWorktreePath/lib/main.dart',
        'void main() {}',
      );
      gitService.fileAtRefContents[
          '$testWorktreePath:lib/main.dart:HEAD'] = 'void main() {\n}';

      await openDialog(tester);

      // View a file first
      await tester.tap(find.text('lib/main.dart'));
      await tester.pump();
      await tester.pump();

      // Go back to commit message
      await tester.tap(find.text('Commit Message'));
      await tester.pump();

      // Type a commit message
      await tester.enterText(
        find.byKey(CommitDialogKeys.messageField),
        'Test commit message',
      );
      await tester.pump();

      // Click commit
      await tester.tap(find.byKey(CommitDialogKeys.commitButton));
      await tester.pump();
      await tester.pump();

      // Verify commit was called
      expect(gitService.commitCalls, hasLength(1));
      expect(gitService.commitCalls.first.$2, 'Test commit message');
    });

    testWidgets('multiple files listed with correct count',
        (tester) async {
      gitService.changedFiles[testWorktreePath] = [
        const GitFileChange(
          path: 'lib/main.dart',
          status: GitFileStatus.modified,
          isStaged: false,
        ),
        const GitFileChange(
          path: 'lib/utils.dart',
          status: GitFileStatus.added,
          isStaged: true,
        ),
        const GitFileChange(
          path: 'test/main_test.dart',
          status: GitFileStatus.untracked,
          isStaged: false,
        ),
      ];

      await openDialog(tester);

      expect(find.text('Files (3)'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('lib/utils.dart'), findsOneWidget);
      expect(find.text('test/main_test.dart'), findsOneWidget);

      // Status badges
      expect(find.text('M'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });
  });
}
