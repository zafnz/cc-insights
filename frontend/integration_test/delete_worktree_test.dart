import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/panels/create_worktree_panel.dart';
import 'package:cc_insights_v2/panels/panels.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:cc_insights_v2/widgets/delete_worktree_dialog.dart';

import 'test_setup.dart';

/// Integration test for the delete worktree workflow.
///
/// This test:
/// 1. Clones a test repo from GitHub into a temporary directory
/// 2. Opens the app with that repo
/// 3. Creates a new worktree
/// 4. Writes a file in the worktree to create uncommitted changes
/// 5. Deletes the worktree, going through the full workflow
///
/// Run with:
///   flutter test integration_test/delete_worktree_test.dart -d macos
// Relative path to screenshots directory (relative to frontend/)
const _screenshotsDir = 'screenshots';

/// Takes a screenshot of the current widget tree and saves it to screenshots/.
Future<void> _takeScreenshot(WidgetTester tester, String name) async {
  // Find the root render object
  final element = tester.binding.rootElement!;
  RenderObject? renderObject = element.renderObject;

  // Walk up to find the repaint boundary
  while (renderObject != null && renderObject is! RenderRepaintBoundary) {
    renderObject = renderObject.parent;
  }

  if (renderObject == null) {
    // Fallback: find the first RenderRepaintBoundary in the tree
    void visitor(Element element) {
      if (renderObject != null) return;
      if (element.renderObject is RenderRepaintBoundary) {
        renderObject = element.renderObject;
        return;
      }
      element.visitChildren(visitor);
    }
    element.visitChildren(visitor);
  }

  if (renderObject is! RenderRepaintBoundary) {
    debugPrint('Warning: Could not find RenderRepaintBoundary for screenshot');
    return;
  }

  final boundary = renderObject as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  if (byteData != null) {
    final file = File('$_screenshotsDir/$name.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    debugPrint('Screenshot saved: $_screenshotsDir/$name.png');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupIntegrationTestIsolation();

  late Directory tempDir;
  late String repoPath;
  const testRepoUrl = 'https://github.com/zafnz/cc-insights-test-repo.git';

  setUpAll(() async {
    // Ensure screenshots directory exists
    final screenshotsDir = Directory('screenshots');
    if (!screenshotsDir.existsSync()) {
      screenshotsDir.createSync(recursive: true);
    }
    // Create a unique temp directory for this test run
    tempDir = await Directory.systemTemp.createTemp('cc_insights_test_');
    repoPath = path.join(tempDir.path, 'test-repo');

    // Clone the test repo
    debugPrint('Cloning test repo to $repoPath...');
    final cloneResult = await Process.run(
      'git',
      ['clone', testRepoUrl, repoPath],
      workingDirectory: tempDir.path,
    );
    if (cloneResult.exitCode != 0) {
      throw Exception(
        'Failed to clone test repo: ${cloneResult.stderr}',
      );
    }
    debugPrint('Clone complete.');

    // Initialize RuntimeConfig with the cloned repo path
    // This simulates launching the app from CLI with the repo path
    RuntimeConfig.initialize([repoPath]);
  });

  tearDownAll(() async {
    // Clean up temp directory
    debugPrint('Cleaning up temp directory: ${tempDir.path}');
    try {
      await tempDir.delete(recursive: true);
    } catch (e) {
      debugPrint('Warning: Failed to delete temp directory: $e');
    }
  });

  group('Delete Worktree Integration Tests', () {
    testWidgets('full workflow: create worktree, make changes, delete',
        (tester) async {
      // Launch the app - RuntimeConfig is already initialized with the repo path
      debugPrint('Launching app with repo: $repoPath');
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify the app launched with the worktree panel visible
      expect(find.byType(WorktreePanel), findsOneWidget);
      expect(find.text('Worktrees'), findsOneWidget);

      // Verify the main branch is visible (test-repo has 'main' as default)
      await pumpUntilFound(
        tester,
        find.text('main'),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for main branch',
      );

      // Screenshot: App launched
      await _takeScreenshot(tester, 'delete_wt_01_app_launched');

      // ===== STEP 1: Create a new worktree =====
      debugPrint('Step 1: Creating new worktree...');

      // Tap on "New Worktree" to open the create worktree panel
      final newWorktreeButton = find.text('New Worktree');
      expect(newWorktreeButton, findsOneWidget);
      await tester.tap(newWorktreeButton);
      await safePumpAndSettle(tester);

      // Wait for the CreateWorktreePanel to appear
      await pumpUntilFound(
        tester,
        find.byType(CreateWorktreePanel),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for CreateWorktreePanel',
      );

      // Wait for the panel to finish loading (it fetches branches)
      // The Autocomplete widget only appears after loading is complete
      await pumpUntilFound(
        tester,
        find.byType(Autocomplete<String>),
        timeout: const Duration(seconds: 30),
        debugLabel: 'waiting for branch name field to load',
      );

      // Enter a branch name - create a new branch for this test
      final branchNameField = find.byType(Autocomplete<String>);
      expect(branchNameField, findsOneWidget);

      // Find the TextField within the Autocomplete
      final textField = find.descendant(
        of: branchNameField,
        matching: find.byType(TextField),
      );
      expect(textField, findsOneWidget);

      // Generate unique branch name
      final testBranch = 'test-delete-${DateTime.now().millisecondsSinceEpoch}';
      await tester.tap(textField);
      await safePumpAndSettle(tester);
      await tester.enterText(textField, testBranch);
      await safePumpAndSettle(tester);

      // Find and tap the "Create Worktree" button
      final createButton = find.byKey(CreateWorktreePanelKeys.createButton);
      expect(createButton, findsOneWidget);
      await tester.tap(createButton);

      // Wait for worktree creation to complete
      // The branch name should appear in the WorktreePanel (not the create panel)
      await pumpUntilFound(
        tester,
        find.descendant(
          of: find.byType(WorktreePanel),
          matching: find.text(testBranch),
        ),
        timeout: const Duration(seconds: 60),
        debugLabel: 'waiting for new worktree to appear in WorktreePanel',
      );

      debugPrint('Worktree created: $testBranch');

      // Screenshot: Worktree created
      await _takeScreenshot(tester, 'delete_wt_02_worktree_created');

      // ===== STEP 2: Write a file in the new worktree =====
      debugPrint('Step 2: Writing test file to create uncommitted changes...');

      // Find the worktree path by running `git worktree list`
      final worktreeListResult = await Process.run(
        'git',
        ['worktree', 'list', '--porcelain'],
        workingDirectory: repoPath,
      );
      final worktreeListOutput = worktreeListResult.stdout as String;
      debugPrint('Worktree list output:\n$worktreeListOutput');

      // Parse the worktree list to find our branch
      String? worktreeRoot;
      final lines = worktreeListOutput.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('worktree ')) {
          final wtPath = lines[i].substring('worktree '.length);
          // Check the following lines for the branch
          for (int j = i + 1; j < lines.length && !lines[j].startsWith('worktree '); j++) {
            if (lines[j] == 'branch refs/heads/$testBranch') {
              worktreeRoot = wtPath;
              break;
            }
          }
          if (worktreeRoot != null) break;
        }
      }

      expect(
        worktreeRoot,
        isNotNull,
        reason: 'Should find worktree for branch $testBranch',
      );
      debugPrint('Found worktree at: $worktreeRoot');

      // Write a test file
      final testFile = File(path.join(worktreeRoot!, 'test-file.txt'));
      await testFile.writeAsString(
        'This is a test file created by the delete worktree integration test.\n'
        'Created at: ${DateTime.now()}\n',
      );

      debugPrint('Test file written to: ${testFile.path}');

      // Give the filesystem watcher time to detect the change
      await tester.pump(const Duration(seconds: 2));
      await safePumpAndSettle(tester);

      // ===== STEP 3: Delete the worktree =====
      debugPrint('Step 3: Deleting worktree...');

      // Find the worktree item in the WorktreePanel and right-click to open context menu
      final worktreeItemInPanel = find.descendant(
        of: find.byType(WorktreePanel),
        matching: find.text(testBranch),
      );
      expect(worktreeItemInPanel, findsOneWidget);

      // Simulate right-click (secondary tap)
      final worktreeItemCenter = tester.getCenter(worktreeItemInPanel);
      await tester.tapAt(worktreeItemCenter, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Wait for context menu to appear and tap "Delete Worktree"
      await pumpUntilFound(
        tester,
        find.text('Delete Worktree'),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for context menu',
      );

      // Screenshot: Context menu open
      await _takeScreenshot(tester, 'delete_wt_03_context_menu');

      await tester.tap(find.text('Delete Worktree'));
      await safePumpAndSettle(tester);

      // ===== STEP 4: Handle the delete dialog workflow =====
      debugPrint('Step 4: Handling delete dialog workflow...');

      // Wait for the delete dialog to appear
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.dialog),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for delete dialog',
      );

      // Wait for the Discard button to appear (indicates uncommitted changes detected)
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.discardButton),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for Discard button',
      );

      // Screenshot: Delete dialog showing uncommitted changes
      await _takeScreenshot(tester, 'delete_wt_04_uncommitted_changes');

      debugPrint('Uncommitted changes detected, clicking Discard...');

      // Click "Discard" to stash changes and continue
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.discardButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Screenshot: After clicking Discard
      await _takeScreenshot(tester, 'delete_wt_05_after_discard');

      // Wait for the dialog to reach a decision point (delete button, force delete, or closed)
      debugPrint('Waiting for workflow to complete...');

      var foundNextStep = false;
      final startTime = DateTime.now();
      const maxWait = Duration(seconds: 30);

      while (!foundNextStep &&
          DateTime.now().difference(startTime) < maxWait) {
        await tester.pump(const Duration(milliseconds: 500));

        // Check if dialog closed (auto-complete case)
        if (find.byKey(DeleteWorktreeDialogKeys.dialog).evaluate().isEmpty) {
          debugPrint('Dialog closed - deletion completed successfully');
          foundNextStep = true;
          break;
        }

        // Check for Delete Worktree button (ready to delete)
        if (find.byKey(DeleteWorktreeDialogKeys.deleteButton).evaluate().isNotEmpty) {
          debugPrint('Ready to delete, clicking Delete Worktree...');

          // Screenshot: Ready to delete
          await _takeScreenshot(tester, 'delete_wt_07_ready_to_delete');

          await tester.tap(find.byKey(DeleteWorktreeDialogKeys.deleteButton));

          // Use runAsync to allow the git command to complete
          await tester.runAsync(() async {
            // Wait for the git worktree remove command to complete
            await Future.delayed(const Duration(seconds: 1));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Screenshot: After clicking Delete
          await _takeScreenshot(tester, 'delete_wt_08_after_delete');

          // Don't break - deletion might fail and require Force Delete
          // Continue the loop to check for that case
          continue;
        }

        // Check for Force Delete button (git error case)
        if (find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton).evaluate().isNotEmpty) {
          debugPrint('Force delete needed, clicking Force Delete...');

          // Screenshot: Force delete prompt
          await _takeScreenshot(tester, 'delete_wt_07b_force_delete');

          await tester.tap(find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton));

          // Use runAsync to allow the git command to complete
          await tester.runAsync(() async {
            await Future.delayed(const Duration(seconds: 1));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Force delete should succeed - now break
          foundNextStep = true;
          break;
        }

        debugPrint('Still processing...');
      }

      if (!foundNextStep) {
        // Take a final screenshot to see the stuck state
        await _takeScreenshot(tester, 'delete_wt_06_stuck_state');
        fail('Timed out waiting for workflow to complete');
      }

      // Screenshot: Before waiting for dialog to close
      await _takeScreenshot(tester, 'delete_wt_09_before_close_wait');

      // Wait for dialog to close - pump a few frames for the route transition
      debugPrint('Waiting for dialog to close...');
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byKey(DeleteWorktreeDialogKeys.dialog).evaluate().isEmpty) {
          debugPrint('Dialog closed after ${i + 1} pumps');
          break;
        }
      }

      debugPrint('Delete dialog closed.');

      // Screenshot: Dialog closed
      await _takeScreenshot(tester, 'delete_wt_10_dialog_closed');

      // ===== STEP 5: Verify worktree is deleted =====
      debugPrint('Step 5: Verifying worktree deletion...');

      // Give the UI time to refresh after the deletion
      // The project state needs to update and rebuild the widget tree
      await tester.pump(const Duration(seconds: 1));
      await safePumpAndSettle(tester);

      // Wait for the branch name to disappear from the WorktreePanel
      // (it may still briefly appear while state is updating)
      await pumpUntilGone(
        tester,
        find.descendant(
          of: find.byType(WorktreePanel),
          matching: find.text(testBranch),
        ),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for deleted worktree to disappear from UI',
      );

      // Screenshot: After worktree removed from UI
      await _takeScreenshot(tester, 'delete_wt_11_worktree_gone');

      expect(
        find.descendant(
          of: find.byType(WorktreePanel),
          matching: find.text(testBranch),
        ),
        findsNothing,
        reason: 'Deleted worktree should not appear in the list',
      );

      // Verify the worktree directory no longer exists
      final worktreeDir = Directory(worktreeRoot!);
      expect(
        worktreeDir.existsSync(),
        isFalse,
        reason: 'Worktree directory should be deleted',
      );

      // Screenshot: Test complete
      await _takeScreenshot(tester, 'delete_wt_12_test_complete');

      debugPrint('Test completed successfully!');
    });

    testWidgets('cancel delete workflow', (tester) async {
      // Launch the app - RuntimeConfig is already initialized with the repo path
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Wait for app to load
      await pumpUntilFound(
        tester,
        find.text('main'),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for main branch',
      );

      // ===== Create a worktree =====
      final newWorktreeButton = find.text('New Worktree');
      await tester.tap(newWorktreeButton);
      await safePumpAndSettle(tester);

      await pumpUntilFound(
        tester,
        find.byType(CreateWorktreePanel),
        timeout: const Duration(seconds: 5),
      );

      // Wait for the panel to finish loading branches
      await pumpUntilFound(
        tester,
        find.byType(Autocomplete<String>),
        timeout: const Duration(seconds: 30),
        debugLabel: 'waiting for branch name field to load',
      );

      final branchNameField = find.byType(Autocomplete<String>);
      final textField = find.descendant(
        of: branchNameField,
        matching: find.byType(TextField),
      );

      final testBranch = 'test-cancel-${DateTime.now().millisecondsSinceEpoch}';
      await tester.tap(textField);
      await safePumpAndSettle(tester);
      await tester.enterText(textField, testBranch);
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(CreateWorktreePanelKeys.createButton));

      // Wait for worktree creation to complete
      await pumpUntilFound(
        tester,
        find.descendant(
          of: find.byType(WorktreePanel),
          matching: find.text(testBranch),
        ),
        timeout: const Duration(seconds: 60),
        debugLabel: 'waiting for new worktree to appear in WorktreePanel',
      );

      // Find the worktree path by running `git worktree list`
      final worktreeListResult = await Process.run(
        'git',
        ['worktree', 'list', '--porcelain'],
        workingDirectory: repoPath,
      );
      final worktreeListOutput = worktreeListResult.stdout as String;

      // Parse the worktree list to find our branch
      String? worktreeRoot;
      final lines = worktreeListOutput.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('worktree ')) {
          final wtPath = lines[i].substring('worktree '.length);
          for (int j = i + 1; j < lines.length && !lines[j].startsWith('worktree '); j++) {
            if (lines[j] == 'branch refs/heads/$testBranch') {
              worktreeRoot = wtPath;
              break;
            }
          }
          if (worktreeRoot != null) break;
        }
      }
      expect(worktreeRoot, isNotNull);

      // Write a file to create uncommitted changes
      final testFile = File(path.join(worktreeRoot!, 'test-file.txt'));
      await testFile.writeAsString('Test content');
      await tester.pump(const Duration(seconds: 2));
      await safePumpAndSettle(tester);

      // ===== Open delete dialog and cancel =====
      final worktreeItemInPanel = find.descendant(
        of: find.byType(WorktreePanel),
        matching: find.text(testBranch),
      );
      final worktreeItemCenter = tester.getCenter(worktreeItemInPanel);
      await tester.tapAt(worktreeItemCenter, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await pumpUntilFound(
        tester,
        find.text('Delete Worktree'),
        timeout: const Duration(seconds: 10),
      );
      // Let the popup menu animation complete before tapping
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Delete Worktree'));
      await safePumpAndSettle(tester);

      // Wait for Discard button (indicates uncommitted changes detected)
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.discardButton),
        timeout: const Duration(seconds: 10),
      );

      // Click Cancel
      final cancelButton = find.byKey(DeleteWorktreeDialogKeys.cancelButton);
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      await safePumpAndSettle(tester);

      // Verify dialog closed
      await pumpUntilGone(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.dialog),
        timeout: const Duration(seconds: 5),
      );

      // Verify worktree still exists in UI
      expect(find.text(testBranch), findsWidgets);

      // Verify worktree directory still exists
      final worktreeDir = Directory(worktreeRoot!);
      expect(worktreeDir.existsSync(), isTrue);

      // Clean up: delete the worktree we created
      // Re-open delete dialog
      final worktreeItemFinal = find.descendant(
        of: find.byType(WorktreePanel),
        matching: find.text(testBranch),
      );
      final itemCenter = tester.getCenter(worktreeItemFinal);
      await tester.tapAt(itemCenter, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await pumpUntilFound(
        tester,
        find.text('Delete Worktree'),
        timeout: const Duration(seconds: 10),
      );
      // Let the popup menu animation complete before tapping
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Delete Worktree'));
      await safePumpAndSettle(tester);

      // Wait for Discard button (indicates uncommitted changes detected)
      await pumpUntilFound(
        tester,
        find.byKey(DeleteWorktreeDialogKeys.discardButton),
        timeout: const Duration(seconds: 10),
      );
      await tester.tap(find.byKey(DeleteWorktreeDialogKeys.discardButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Use the same polling logic as the first test
      var foundNextStep = false;
      final startTime = DateTime.now();
      const maxWait = Duration(seconds: 30);

      while (!foundNextStep &&
          DateTime.now().difference(startTime) < maxWait) {
        await tester.pump(const Duration(milliseconds: 500));

        // Check if dialog closed (success case)
        if (find.byKey(DeleteWorktreeDialogKeys.dialog).evaluate().isEmpty) {
          debugPrint('Cleanup: Dialog closed - deletion completed');
          foundNextStep = true;
          break;
        }

        // Check for Delete Worktree button (ready to delete)
        if (find.byKey(DeleteWorktreeDialogKeys.deleteButton).evaluate().isNotEmpty) {
          debugPrint('Cleanup: Ready to delete');
          await tester.tap(find.byKey(DeleteWorktreeDialogKeys.deleteButton));

          // Use runAsync to allow the git command to complete
          await tester.runAsync(() async {
            await Future.delayed(const Duration(seconds: 1));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Don't break - might need Force Delete
          continue;
        }

        // Check for Force Delete button (git error case)
        if (find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton).evaluate().isNotEmpty) {
          debugPrint('Cleanup: Force delete prompt detected');
          await tester.tap(find.byKey(DeleteWorktreeDialogKeys.forceDeleteButton));

          // Use runAsync to allow the git command to complete
          await tester.runAsync(() async {
            await Future.delayed(const Duration(seconds: 1));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          foundNextStep = true;
          break;
        }
      }

      // Wait for dialog to close after handling - give more time for async operations
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(DeleteWorktreeDialogKeys.dialog).evaluate().isEmpty) {
          debugPrint('Cleanup: Dialog closed');
          break;
        }
      }
    });
  });
}
