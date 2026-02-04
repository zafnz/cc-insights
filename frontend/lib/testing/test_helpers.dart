import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/persistence_service.dart';
import '../services/runtime_config.dart';

// =============================================================================
// PUMP HELPERS - Avoid indefinite hangs
// =============================================================================

/// Like [WidgetTester.pumpAndSettle] but with a default timeout.
///
/// NEVER use `tester.pumpAndSettle()` directly - it can hang indefinitely.
/// Always use this helper or pass an explicit timeout.
///
/// ```dart
/// await safePumpAndSettle(tester);
/// await safePumpAndSettle(tester, timeout: Duration(seconds: 5));
/// ```
Future<void> safePumpAndSettle(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
  Duration duration = const Duration(milliseconds: 100),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
}) async {
  try {
    await tester.pumpAndSettle(duration, phase, timeout);
  } on FlutterError catch (e) {
    if (e.message.contains('pumpAndSettle timed out')) {
      // Timed out - just continue, don't fail the test
      // This allows tests to proceed even with spinning indicators
      debugPrint('safePumpAndSettle timed out after $timeout - continuing');
      return;
    }
    rethrow;
  }
}

/// Pumps until a condition is true, with timeout.
///
/// Use this when waiting for async state changes to reflect in the UI.
///
/// ```dart
/// await pumpUntil(
///   tester,
///   () => find.text('Loaded').evaluate().isNotEmpty,
///   debugLabel: 'waiting for Loaded text',
/// );
/// ```
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 16),
  String? debugLabel,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(step);
  }
  // Log timeout without dumping widget tree (too verbose for CI)
  debugPrint('pumpUntil timed out${debugLabel != null ? " ($debugLabel)" : ""}');
  throw TestFailure(
    'pumpUntil timed out after $timeout${debugLabel != null ? ": $debugLabel" : ""}',
  );
}

/// Pumps until a finder finds at least one widget.
///
/// Convenience wrapper around [pumpUntil] for the common case.
///
/// ```dart
/// await pumpUntilFound(tester, find.text('Loaded'));
/// await pumpUntilFound(tester, find.byType(MyWidget));
/// ```
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 16),
  String? debugLabel,
}) async {
  await pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    timeout: timeout,
    step: step,
    debugLabel: debugLabel ?? 'waiting for ${finder.description}',
  );
}

/// Pumps until a finder finds no widgets.
///
/// Useful for waiting for loading indicators to disappear.
///
/// ```dart
/// await pumpUntilGone(tester, find.byType(CircularProgressIndicator));
/// ```
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 16),
  String? debugLabel,
}) async {
  await pumpUntil(
    tester,
    () => finder.evaluate().isEmpty,
    timeout: timeout,
    step: step,
    debugLabel: debugLabel ?? 'waiting for ${finder.description} to disappear',
  );
}

// =============================================================================
// RESOURCE TRACKING - Prevent leaks between tests
// =============================================================================

/// Mixin for tracking test resources that need cleanup.
///
/// Use this to ensure ChangeNotifiers, StreamControllers, and other
/// resources are properly disposed between tests.
///
/// ```dart
/// void main() {
///   final resources = TestResources();
///
///   tearDown(() async {
///     await resources.disposeAll();
///   });
///
///   test('example', () {
///     final state = resources.track(MyState());
///     final controller = resources.trackStream<String>();
///     // ... test ...
///     // Resources auto-disposed in tearDown
///   });
/// }
/// ```
class TestResources {
  final List<ChangeNotifier> _notifiers = [];
  final List<StreamController<dynamic>> _controllers = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<Future<void> Function()> _customCleanup = [];

  /// Track a ChangeNotifier for automatic disposal.
  T track<T extends ChangeNotifier>(T notifier) {
    _notifiers.add(notifier);
    return notifier;
  }

  /// Track a StreamController for automatic closing.
  ///
  /// If no controller is provided, creates a new one.
  StreamController<T> trackStream<T>([StreamController<T>? controller]) {
    final c = controller ?? StreamController<T>();
    _controllers.add(c);
    return c;
  }

  /// Track a broadcast StreamController for automatic closing.
  StreamController<T> trackBroadcastStream<T>(
      [StreamController<T>? controller]) {
    final c = controller ?? StreamController<T>.broadcast();
    _controllers.add(c);
    return c;
  }

  /// Track a StreamSubscription for automatic cancellation.
  StreamSubscription<T> trackSubscription<T>(
      StreamSubscription<T> subscription) {
    _subscriptions.add(subscription);
    return subscription;
  }

  /// Add a custom cleanup function to run during disposal.
  void onCleanup(Future<void> Function() cleanup) {
    _customCleanup.add(cleanup);
  }

  /// Dispose all tracked resources.
  ///
  /// Call this in tearDown().
  Future<void> disposeAll() async {
    // Cancel subscriptions first (they may reference other resources)
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();

    // Close stream controllers
    for (final c in _controllers) {
      await c.close();
    }
    _controllers.clear();

    // Dispose notifiers
    for (final n in _notifiers) {
      n.dispose();
    }
    _notifiers.clear();

    // Run custom cleanup
    for (final cleanup in _customCleanup) {
      await cleanup();
    }
    _customCleanup.clear();
  }

  /// Check if any resources are still tracked (useful for debugging).
  bool get hasTrackedResources =>
      _notifiers.isNotEmpty ||
      _controllers.isNotEmpty ||
      _subscriptions.isNotEmpty ||
      _customCleanup.isNotEmpty;

  /// Get count of tracked resources (useful for debugging).
  Map<String, int> get trackedCounts => {
        'notifiers': _notifiers.length,
        'controllers': _controllers.length,
        'subscriptions': _subscriptions.length,
        'customCleanup': _customCleanup.length,
      };
}

// =============================================================================
// ASSERTION HELPERS
// =============================================================================

/// Asserts that a finder finds exactly one widget.
void expectOne(Finder finder, {String? reason}) {
  expect(finder, findsOneWidget, reason: reason);
}

/// Asserts that a finder finds no widgets.
void expectNone(Finder finder, {String? reason}) {
  expect(finder, findsNothing, reason: reason);
}

/// Asserts that a finder finds at least one widget.
void expectFound(Finder finder, {String? reason}) {
  expect(finder, findsWidgets, reason: reason);
}

/// Asserts that a finder finds exactly N widgets.
void expectN(Finder finder, int count, {String? reason}) {
  expect(finder, findsNWidgets(count), reason: reason);
}

// =============================================================================
// TEST ISOLATION HELPERS - Prevent tests from affecting real data
// =============================================================================

/// Sets up a temporary config directory for test isolation.
///
/// Call this in `setUp()` to ensure tests don't write to ~/.ccinsights.
/// Returns a cleanup function that should be called in `tearDown()`.
///
/// ```dart
/// void main() {
///   late Future<void> Function() cleanupConfig;
///
///   setUp(() async {
///     cleanupConfig = await setupTestConfig();
///   });
///
///   tearDown(() async {
///     await cleanupConfig();
///   });
///
///   test('my test', () {
///     // Test code here - will use temp directory
///   });
/// }
/// ```
Future<Future<void> Function()> setupTestConfig() async {
  // Create temp directory
  final tempDir = await Directory.systemTemp.createTemp('cc_insights_test_');

  // Set it as the config directory
  PersistenceService.setBaseDir('${tempDir.path}/.ccinsights');

  // Reset RuntimeConfig to ensure clean state
  RuntimeConfig.resetForTesting();

  // Return cleanup function
  return () async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    // Reset persistence service to default
    PersistenceService.setBaseDir(
      '${Platform.environment['HOME']}/.ccinsights',
    );
    RuntimeConfig.resetForTesting();
  };
}
