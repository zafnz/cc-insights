import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:cc_insights_v2/widgets/directory_validation_dialog.dart';

import 'test_setup.dart';

/// Integration test for directory validation when launching the app.
///
/// This test validates the following scenarios:
/// 1. Opening a directory that is not a git repo
/// 2. Opening a linked worktree (not the primary)
/// 3. Opening a subdirectory inside a git repo
///
/// Run with:
///   flutter test integration_test/directory_validation_test.dart -d macos

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

  setUpAll(() async {
    // Ensure screenshots directory exists
    final screenshotsDir = Directory('screenshots');
    if (!screenshotsDir.existsSync()) {
      screenshotsDir.createSync(recursive: true);
    }

    // Create a unique temp directory for this test run
    // Resolve to canonical path to handle symlinks (e.g., /var -> /private/var on macOS)
    final rawTempDir = await Directory.systemTemp.createTemp('cc_insights_dir_validation_');
    tempDir = Directory(rawTempDir.resolveSymbolicLinksSync());
    debugPrint('Created temp directory: ${tempDir.path}');
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

  group('Directory Validation Tests', () {
    setUp(() {
      // Reset RuntimeConfig between tests so each test can initialize it fresh
      RuntimeConfig.resetForTesting();
    });

    testWidgets('shows dialog when opening non-git directory', (tester) async {
      // Create a non-git directory
      final nonGitDir = Directory(path.join(tempDir.path, 'not-a-git-repo'));
      await nonGitDir.create(recursive: true);

      debugPrint('Testing non-git directory: ${nonGitDir.path}');

      // Initialize RuntimeConfig with the non-git directory
      RuntimeConfig.initialize([nonGitDir.path]);

      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for the validation dialog to appear
      await pumpUntilFound(
        tester,
        find.byKey(DirectoryValidationDialogKeys.dialog),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for validation dialog (non-git)',
      );

      // Screenshot: Non-git repo dialog
      await _takeScreenshot(tester, 'dir_validation_01_not_git_repo');

      // Verify the message is correct
      expect(
        find.textContaining('works best when working inside a git repository'),
        findsOneWidget,
      );

      // Verify the "Open primary worktree root" button is NOT shown (no repo to open)
      expect(
        find.byKey(DirectoryValidationDialogKeys.openPrimaryButton),
        findsNothing,
      );

      // Verify the other buttons are shown
      expect(
        find.byKey(DirectoryValidationDialogKeys.chooseAnotherButton),
        findsOneWidget,
      );
      expect(
        find.byKey(DirectoryValidationDialogKeys.openAnywayButton),
        findsOneWidget,
      );

      debugPrint('Non-git directory test passed.');
    });

    testWidgets('shows dialog when opening linked worktree', (tester) async {
      // Create a git repository
      final repoDir = Directory(path.join(tempDir.path, 'test-repo-worktree'));
      await repoDir.create(recursive: true);

      // Initialize the repo
      var result = await Process.run(
        'git',
        ['init'],
        workingDirectory: repoDir.path,
      );
      expect(result.exitCode, 0, reason: 'git init failed');

      // Configure git user for commits
      await Process.run(
        'git',
        ['config', 'user.email', 'test@test.com'],
        workingDirectory: repoDir.path,
      );
      await Process.run(
        'git',
        ['config', 'user.name', 'Test User'],
        workingDirectory: repoDir.path,
      );

      // Create an initial commit
      final testFile = File(path.join(repoDir.path, 'test.txt'));
      await testFile.writeAsString('Hello, World!');
      await Process.run('git', ['add', '.'], workingDirectory: repoDir.path);
      await Process.run(
        'git',
        ['commit', '-m', 'Initial commit'],
        workingDirectory: repoDir.path,
      );

      // Create a linked worktree
      final worktreePath = path.join(tempDir.path, 'linked-worktree');
      result = await Process.run(
        'git',
        ['worktree', 'add', '-b', 'test-branch', worktreePath],
        workingDirectory: repoDir.path,
      );
      expect(result.exitCode, 0, reason: 'git worktree add failed: ${result.stderr}');

      debugPrint('Testing linked worktree: $worktreePath');

      // Initialize RuntimeConfig with the linked worktree
      RuntimeConfig.initialize([worktreePath]);

      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for the validation dialog to appear
      await pumpUntilFound(
        tester,
        find.byKey(DirectoryValidationDialogKeys.dialog),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for validation dialog (linked worktree)',
      );

      // Screenshot: Linked worktree dialog
      await _takeScreenshot(tester, 'dir_validation_02_linked_worktree');

      // Verify the message is correct
      expect(
        find.textContaining('works best when opening the primary worktree'),
        findsOneWidget,
      );

      // Verify the repo root path is shown
      expect(
        find.byKey(DirectoryValidationDialogKeys.pathText),
        findsOneWidget,
      );

      // Verify the "Open primary worktree root" button IS shown
      expect(
        find.byKey(DirectoryValidationDialogKeys.openPrimaryButton),
        findsOneWidget,
      );
      expect(find.text('Open primary worktree root'), findsOneWidget);

      debugPrint('Linked worktree test passed.');
    });

    testWidgets('shows dialog when opening subdirectory of repo', (tester) async {
      // Create a git repository
      final repoDir = Directory(path.join(tempDir.path, 'test-repo-subdir'));
      await repoDir.create(recursive: true);

      // Initialize the repo
      var result = await Process.run(
        'git',
        ['init'],
        workingDirectory: repoDir.path,
      );
      expect(result.exitCode, 0, reason: 'git init failed');

      // Create a subdirectory
      final subDir = Directory(path.join(repoDir.path, 'src', 'lib'));
      await subDir.create(recursive: true);

      debugPrint('Testing subdirectory: ${subDir.path}');

      // Initialize RuntimeConfig with the subdirectory
      RuntimeConfig.initialize([subDir.path]);

      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for the validation dialog to appear
      await pumpUntilFound(
        tester,
        find.byKey(DirectoryValidationDialogKeys.dialog),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for validation dialog (subdirectory)',
      );

      // Screenshot: Subdirectory dialog
      await _takeScreenshot(tester, 'dir_validation_03_subdirectory');

      // Verify the message is correct
      expect(
        find.textContaining('works best when opening the top of the git repository'),
        findsOneWidget,
      );

      // Verify the repo root path is shown
      expect(
        find.byKey(DirectoryValidationDialogKeys.pathText),
        findsOneWidget,
      );

      // Verify the "Open primary worktree root" button IS shown
      expect(
        find.byKey(DirectoryValidationDialogKeys.openPrimaryButton),
        findsOneWidget,
      );
      expect(find.text('Open primary worktree root'), findsOneWidget);

      debugPrint('Subdirectory test passed.');
    });

    testWidgets('opens directly when primary worktree root', (tester) async {
      // Create a git repository (ideal case)
      final repoDir = Directory(path.join(tempDir.path, 'test-repo-primary'));
      await repoDir.create(recursive: true);

      // Initialize the repo
      var result = await Process.run(
        'git',
        ['init'],
        workingDirectory: repoDir.path,
      );
      expect(result.exitCode, 0, reason: 'git init failed');

      debugPrint('Testing primary worktree root: ${repoDir.path}');

      // Initialize RuntimeConfig with the primary worktree
      RuntimeConfig.initialize([repoDir.path]);

      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // The validation dialog should NOT appear
      expect(
        find.byKey(DirectoryValidationDialogKeys.dialog),
        findsNothing,
      );

      // Screenshot: Direct load (no dialog)
      await _takeScreenshot(tester, 'dir_validation_04_primary_direct');

      debugPrint('Primary worktree root test passed (no dialog shown).');
    });

    testWidgets('Open Anyway button proceeds with problematic directory',
        (tester) async {
      // Create a non-git directory
      final nonGitDir = Directory(path.join(tempDir.path, 'open-anyway-test'));
      await nonGitDir.create(recursive: true);

      debugPrint('Testing Open Anyway: ${nonGitDir.path}');

      // Initialize RuntimeConfig
      RuntimeConfig.initialize([nonGitDir.path]);

      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for the validation dialog to appear
      await pumpUntilFound(
        tester,
        find.byKey(DirectoryValidationDialogKeys.dialog),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for validation dialog',
      );

      // Screenshot: Before clicking Open Anyway
      await _takeScreenshot(tester, 'dir_validation_05_before_open_anyway');

      // Click "Open Anyway"
      await tester.tap(find.byKey(DirectoryValidationDialogKeys.openAnywayButton));
      await safePumpAndSettle(tester);

      // Dialog should be closed
      expect(
        find.byKey(DirectoryValidationDialogKeys.dialog),
        findsNothing,
      );

      // Screenshot: After clicking Open Anyway
      await _takeScreenshot(tester, 'dir_validation_06_after_open_anyway');

      debugPrint('Open Anyway test passed.');
    });

    testWidgets('Choose Different button shows welcome screen', (tester) async {
      // Create a non-git directory
      final nonGitDir = Directory(path.join(tempDir.path, 'choose-different-test'));
      await nonGitDir.create(recursive: true);

      debugPrint('Testing Choose Different: ${nonGitDir.path}');

      // Initialize RuntimeConfig
      RuntimeConfig.initialize([nonGitDir.path]);

      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for the validation dialog to appear
      await pumpUntilFound(
        tester,
        find.byKey(DirectoryValidationDialogKeys.dialog),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for validation dialog',
      );

      // Click "Choose Different"
      await tester.tap(find.byKey(DirectoryValidationDialogKeys.chooseAnotherButton));
      await safePumpAndSettle(tester);

      // Dialog should be closed
      expect(
        find.byKey(DirectoryValidationDialogKeys.dialog),
        findsNothing,
      );

      // Welcome screen should be shown (look for the "Open Project Folder" button)
      expect(find.text('Open Project Folder'), findsOneWidget);

      // Screenshot: Welcome screen after Choose Different
      await _takeScreenshot(tester, 'dir_validation_07_choose_different_welcome');

      debugPrint('Choose Different test passed.');
    });

    testWidgets('Open Repo Root navigates to primary worktree', (tester) async {
      // Create a git repository with a linked worktree
      final repoDir = Directory(path.join(tempDir.path, 'test-repo-nav'));
      await repoDir.create(recursive: true);

      // Initialize the repo
      var result = await Process.run(
        'git',
        ['init'],
        workingDirectory: repoDir.path,
      );
      expect(result.exitCode, 0, reason: 'git init failed');

      // Configure git user for commits
      await Process.run(
        'git',
        ['config', 'user.email', 'test@test.com'],
        workingDirectory: repoDir.path,
      );
      await Process.run(
        'git',
        ['config', 'user.name', 'Test User'],
        workingDirectory: repoDir.path,
      );

      // Create an initial commit
      final testFile = File(path.join(repoDir.path, 'test.txt'));
      await testFile.writeAsString('Hello, World!');
      await Process.run('git', ['add', '.'], workingDirectory: repoDir.path);
      await Process.run(
        'git',
        ['commit', '-m', 'Initial commit'],
        workingDirectory: repoDir.path,
      );

      // Create a linked worktree
      final worktreePath = path.join(tempDir.path, 'linked-nav-test');
      result = await Process.run(
        'git',
        ['worktree', 'add', '-b', 'nav-test-branch', worktreePath],
        workingDirectory: repoDir.path,
      );
      expect(result.exitCode, 0, reason: 'git worktree add failed');

      debugPrint('Testing Open Repo Root navigation: $worktreePath -> ${repoDir.path}');

      // Initialize RuntimeConfig with the linked worktree
      RuntimeConfig.initialize([worktreePath]);

      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for the validation dialog to appear
      await pumpUntilFound(
        tester,
        find.byKey(DirectoryValidationDialogKeys.dialog),
        timeout: const Duration(seconds: 10),
        debugLabel: 'waiting for validation dialog',
      );

      // Screenshot: Before clicking Open Repo Root
      await _takeScreenshot(tester, 'dir_validation_08_before_open_primary');

      // Click "Open Repo Root"
      await tester.tap(find.byKey(DirectoryValidationDialogKeys.openPrimaryButton));
      await safePumpAndSettle(tester);

      // Dialog should be closed and app should be loading
      expect(
        find.byKey(DirectoryValidationDialogKeys.dialog),
        findsNothing,
      );

      // Screenshot: After clicking Open Repo Root
      await _takeScreenshot(tester, 'dir_validation_09_after_open_primary');

      debugPrint('Open Repo Root navigation test passed.');
    });
  });
}
