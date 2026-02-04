import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:cc_insights_v2/testing/mock_data.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';

/// Integration test for file tree expand performance.
///
/// Clones cc-insights-test-repo (317 files, 177 directories) to a temp directory
/// for realistic performance testing.
///
/// Run with:
///   flutter test integration_test/file_tree_expand_performance_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String mockPath;
  late Directory tempDir;
  late Directory persistenceTempDir;

  setUpAll(() async {
    // Create temp directory for persistence isolation
    persistenceTempDir = await Directory.systemTemp.createTemp('integration_test_');
    PersistenceService.setBaseDir('${persistenceTempDir.path}/.ccinsights');

    // Enable mock data
    useMockData = true;

    // Create a unique temp directory for this test run
    tempDir = Directory.systemTemp.createTempSync('cc-insights-perf-test-');
    mockPath = p.join(tempDir.path, 'cc-insights-test-repo');

    // Clone the test repo
    debugPrint('Cloning test repo to $mockPath...');
    final cloneResult = await Process.run(
      'git',
      ['clone', 'https://github.com/zafnz/cc-insights-test-repo.git', mockPath],
      workingDirectory: tempDir.path,
    );

    if (cloneResult.exitCode != 0) {
      fail('Failed to clone test repo: ${cloneResult.stderr}');
    }

    debugPrint('Test repo cloned successfully');

    // Override the mock data path
    mockDataProjectPath = mockPath;

    // Verify the clone worked
    final files = Directory(mockPath).listSync();
    debugPrint('Test repo has ${files.length} top-level items');
  });

  tearDownAll(() async {
    // Clean up the cloned repo and temp directory
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
      debugPrint('Cleaned up temp directory: ${tempDir.path}');
    }

    // Clean up persistence temp directory
    if (await persistenceTempDir.exists()) {
      await persistenceTempDir.delete(recursive: true);
    }
    // Reset to default
    PersistenceService.setBaseDir(
      '${Platform.environment['HOME']}/.ccinsights',
    );
  });

  group('File tree expand performance', () {
    testWidgets('expanding a folder completes within 100ms', (tester) async {
      // Launch the app with mock data (pointing to real test repo via symlink)
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester, timeout: const Duration(seconds: 10));

      // Navigate to File Manager by clicking the folder icon in nav rail
      final fileManagerButton = find.byIcon(Icons.folder_outlined);
      expect(fileManagerButton, findsWidgets,
          reason: 'File Manager nav button should be visible');

      await tester.tap(fileManagerButton.first);
      await safePumpAndSettle(tester, timeout: const Duration(seconds: 10));

      // Verify we're in the File Manager screen - should see "Files" panel
      expect(find.text('Files'), findsOneWidget,
          reason: 'Files panel should be visible after navigation');

      // Select the worktree (click on "main" branch in the worktree list)
      final mainWorktree = find.text('main');
      expect(mainWorktree, findsWidgets,
          reason: 'main worktree should be visible');

      await tester.tap(mainWorktree.first);

      // Wait for file tree to load - this is the slow part we're testing
      final loadStartTime = DateTime.now();
      await safePumpAndSettle(tester, timeout: const Duration(seconds: 30));
      final loadEndTime = DateTime.now();
      final loadTime = loadEndTime.difference(loadStartTime).inMilliseconds;
      debugPrint('File tree load time: ${loadTime}ms');

      // Wait for chevrons to appear (folders loaded)
      Finder chevrons = find.byIcon(Icons.chevron_right);

      // Poll for up to 30 seconds waiting for folders to appear
      for (var i = 0; i < 60 && chevrons.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        chevrons = find.byIcon(Icons.chevron_right);
        if (i % 10 == 0) {
          debugPrint('Waiting for folders... attempt $i');
        }
      }

      if (chevrons.evaluate().isEmpty) {
        final folders = find.byIcon(Icons.folder);
        debugPrint(
            'No chevrons found. Folder icons: ${folders.evaluate().length}');
        fail('No expandable folders found - file tree may not have loaded');
      }

      debugPrint('Found ${chevrons.evaluate().length} collapsed folders');

      // Measure time to expand by clicking the chevron
      // Pump multiple frames to simulate real rendering (10 frames at 16ms each = 160ms)
      final stopwatch = Stopwatch()..start();
      await tester.tap(chevrons.first);
      // Pump 10 frames to allow rendering to complete
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      stopwatch.stop();

      final expandTime = stopwatch.elapsedMilliseconds;
      debugPrint('First expand time (10 frames): ${expandTime}ms');

      expect(
        expandTime,
        lessThan(500),
        reason: 'Expanding a folder should complete within 500ms, '
            'but took ${expandTime}ms',
      );

      // Test multiple expansions
      debugPrint('Testing multiple expansions...');
      final expandTimes = <int>[];

      for (var i = 0; i < 5; i++) {
        debugPrint('Looking for chevrons for expansion $i...');
        chevrons = find.byIcon(Icons.chevron_right);
        final chevronCount = chevrons.evaluate().length;
        debugPrint('Found $chevronCount collapsed folders');
        if (chevronCount == 0) {
          debugPrint('No more collapsed folders after $i expansions');
          break;
        }

        final sw = Stopwatch()..start();
        await tester.tap(chevrons.first);
        // Pump 10 frames
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        sw.stop();

        expandTimes.add(sw.elapsedMilliseconds);
        debugPrint('Expand $i (10 frames): ${sw.elapsedMilliseconds}ms');
      }

      if (expandTimes.isNotEmpty) {
        final avg = expandTimes.reduce((a, b) => a + b) / expandTimes.length;
        debugPrint('Average expand time: ${avg.toStringAsFixed(1)}ms');

        for (var i = 0; i < expandTimes.length; i++) {
          expect(
            expandTimes[i],
            lessThan(500),
            reason: 'Expand $i took ${expandTimes[i]}ms, should be < 500ms',
          );
        }
      }
    });
  });
}
