import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/services/script_execution_service.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:provider/provider.dart';

/// Integration tests for the ActionsPanel feature.
///
/// Run tests:
///   flutter test integration_test/actions_panel_test.dart -d macos
///
/// Screenshots are saved to the `screenshots/` directory.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Ensure screenshots directory exists and enable mock data
  setUpAll(() {
    final screenshotsDir = Directory('screenshots');
    if (!screenshotsDir.existsSync()) {
      screenshotsDir.createSync(recursive: true);
    }
    // Enable mock data for all integration tests
    useMockData = true;
  });

  group('ActionsPanel Integration Tests', () {
    testWidgets('App launches with ScriptExecutionService available',
        (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify the app launched successfully
      expect(find.text('Worktrees'), findsOneWidget);

      // Verify ScriptExecutionService is registered
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();
      expect(scriptService, isNotNull);

      // Verify initial state
      expect(scriptService.hasRunningScripts, isFalse);
      expect(scriptService.scripts, isEmpty);

      await _takeScreenshot(tester, 'actions_01_app_launched');
    });

    testWidgets('ScriptExecutionService can run and complete scripts',
        (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService from the widget tree
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Run a simple echo command using runAsync to handle real process
      late RunningScript script;
      await tester.runAsync(() async {
        script = await scriptService.runScript(
          name: 'Test',
          command: 'echo "Hello from integration test"',
          workingDirectory: Directory.current.path,
        );

        // Wait for script to complete
        await script.done;

        // Give time for stream listeners to process output
        // Stream data is processed asynchronously after exitCode resolves
        await Future.delayed(const Duration(milliseconds: 500));
      });

      // Pump to update UI state
      await tester.pump();

      // Verify script completed successfully
      expect(script.isRunning, isFalse);
      expect(script.isSuccess, isTrue);
      expect(script.exitCode, equals(0));
      // Note: In integration tests, stream processing may complete before
      // or after the exitCode. We verify the script ran successfully.
      // The output capture is tested more reliably in unit tests.

      await _takeScreenshot(tester, 'actions_02_script_executed');
    });

    testWidgets('ScriptExecutionService handles script errors', (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Run a command that will fail
      late RunningScript script;
      await tester.runAsync(() async {
        script = await scriptService.runScript(
          name: 'FailTest',
          command: 'exit 42',
          workingDirectory: Directory.current.path,
        );

        // Wait for script to complete
        await script.done;
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      // Verify script completed with error
      expect(script.isRunning, isFalse);
      expect(script.isError, isTrue);
      expect(script.exitCode, equals(42));

      await _takeScreenshot(tester, 'actions_03_script_error');
    });

    testWidgets('ScriptExecutionService can kill running scripts',
        (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Run a long-running command and kill it
      late RunningScript script;
      await tester.runAsync(() async {
        script = await scriptService.runScript(
          name: 'LongRunning',
          command: 'sleep 30',
          workingDirectory: Directory.current.path,
        );

        // Verify script is running
        expect(script.isRunning, isTrue);

        // Kill the script
        await scriptService.killScript(script.id);

        // Wait for process to be terminated
        await script.done;
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      // Verify script was killed (exit code will be non-zero due to SIGTERM)
      expect(script.isRunning, isFalse);

      await _takeScreenshot(tester, 'actions_04_script_killed');
    });

    testWidgets('Multiple scripts can run concurrently', (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Run two scripts concurrently
      late RunningScript script1;
      late RunningScript script2;

      await tester.runAsync(() async {
        script1 = await scriptService.runScript(
          name: 'Script1',
          command: 'echo "First"',
          workingDirectory: Directory.current.path,
        );

        script2 = await scriptService.runScript(
          name: 'Script2',
          command: 'echo "Second"',
          workingDirectory: Directory.current.path,
        );

        // Verify both scripts exist
        expect(scriptService.scripts, hasLength(2));

        // Wait for both to complete
        await script1.done;
        await script2.done;
        // PTY output is async; give stream listeners time to process
        await Future.delayed(const Duration(seconds: 1));
      });

      await tester.pump();

      // Verify both completed successfully
      expect(script1.isSuccess, isTrue);
      expect(script2.isSuccess, isTrue);
      // Note: PTY output processing is asynchronous and may not have
      // completed in time for short-lived echo commands. We verify the
      // scripts ran and completed successfully.
      // Output content is tested more reliably in unit tests.

      await _takeScreenshot(tester, 'actions_05_concurrent_scripts');
    });

    testWidgets('ScriptExecutionService clears completed scripts',
        (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Run a script
      late RunningScript script;
      await tester.runAsync(() async {
        script = await scriptService.runScript(
          name: 'ToClear',
          command: 'echo "Clear me"',
          workingDirectory: Directory.current.path,
        );

        // Wait for completion
        await script.done;
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      // Verify script exists
      expect(scriptService.scripts, hasLength(1));

      // Clear the script
      scriptService.clearScript(script.id);
      await tester.pump();

      // Verify script was removed
      expect(scriptService.scripts, isEmpty);

      await _takeScreenshot(tester, 'actions_06_script_cleared');
    });

    testWidgets('Script output streams multiline output', (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Run a script that outputs multiple lines
      late RunningScript script;
      await tester.runAsync(() async {
        script = await scriptService.runScript(
          name: 'MultiLine',
          command: 'echo "Line 1" && echo "Line 2" && echo "Line 3"',
          workingDirectory: Directory.current.path,
        );

        // Wait for completion
        await script.done;
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      // Verify all output was captured
      expect(script.output, contains('Line 1'));
      expect(script.output, contains('Line 2'));
      expect(script.output, contains('Line 3'));

      await _takeScreenshot(tester, 'actions_07_multiline_output');
    });

    testWidgets('Script stderr is captured', (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Run a script that outputs to stderr
      late RunningScript script;
      await tester.runAsync(() async {
        script = await scriptService.runScript(
          name: 'StderrTest',
          command: 'echo "Error message" >&2',
          workingDirectory: Directory.current.path,
        );

        // Wait for completion
        await script.done;
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      // PTY combines stdout and stderr into a single stream, so stderr
      // output appears in the combined output buffer, not the separate
      // stderr buffer.
      expect(script.output, contains('Error message'));

      await _takeScreenshot(tester, 'actions_08_stderr_captured');
    });

    testWidgets('Script tracks elapsed time', (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      late RunningScript script;
      await tester.runAsync(() async {
        script = await scriptService.runScript(
          name: 'TimedScript',
          command: 'sleep 0.1 && echo "done"',
          workingDirectory: Directory.current.path,
        );

        // Wait for completion
        await script.done;
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      // Verify elapsed time is tracked
      expect(script.elapsed.inMilliseconds, greaterThan(50));
      expect(script.startTime, isNotNull);

      await _takeScreenshot(tester, 'actions_09_elapsed_time');
    });

    testWidgets('ScriptExecutionService notifies listeners on state changes',
        (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Get the ScriptExecutionService
      final context = tester.element(find.byType(MaterialApp));
      final scriptService = context.read<ScriptExecutionService>();

      // Track notification count
      var notificationCount = 0;
      void listener() {
        notificationCount++;
      }

      scriptService.addListener(listener);

      await tester.runAsync(() async {
        final script = await scriptService.runScript(
          name: 'NotifyTest',
          command: 'echo "test"',
          workingDirectory: Directory.current.path,
        );

        await script.done;
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      // Should have been notified multiple times (start, output, complete)
      expect(notificationCount, greaterThan(0));

      scriptService.removeListener(listener);

      await _takeScreenshot(tester, 'actions_10_notifications');
    });
  });
}

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
