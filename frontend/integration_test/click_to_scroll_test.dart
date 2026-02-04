import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/panels/conversation_panel.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:cc_insights_v2/widgets/click_to_scroll_container.dart';
import 'package:cc_insights_v2/widgets/tool_card.dart';

/// Integration tests for ClickToScrollContainer within the actual app.
///
/// Run tests:
///   flutter test integration_test/click_to_scroll_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    // Enable mock data
    useMockData = true;

    // Create temp directory for test isolation
    tempDir = await Directory.systemTemp.createTemp('integration_test_');
    PersistenceService.setBaseDir('${tempDir.path}/.ccinsights');

    final screenshotsDir = Directory('screenshots');
    if (!screenshotsDir.existsSync()) {
      screenshotsDir.createSync(recursive: true);
    }
  });

  tearDownAll(() async {
    // Clean up temp directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    // Reset to default
    PersistenceService.setBaseDir(
      '${Platform.environment['HOME']}/.ccinsights',
    );
  });

  group('ClickToScrollContainer in App', () {
    testWidgets('tool card with scrollable content can be activated and scrolled',
        (tester) async {
      // Launch the real app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Select the Log Replay chat which has tool entries
      await tester.tap(find.text('Log Replay'));
      await safePumpAndSettle(tester);

      // Find the conversation panel's scrollable
      final conversationScrollables = find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byWidgetPredicate((widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down),
      );
      expect(conversationScrollables, findsWidgets);

      // Find the Read tool (has pubspec.yaml content - guaranteed to be long)
      final readToolFinder = find.text('Read');
      await tester.scrollUntilVisible(
        readToolFinder,
        -200,
        scrollable: conversationScrollables.first,
      );
      await safePumpAndSettle(tester);

      // Expand the Read tool card by tapping on it
      await tester.tap(readToolFinder.first);
      await safePumpAndSettle(tester);

      // Find the ClickToScrollContainer inside the expanded ToolCard
      final clickToScrollFinder = find.descendant(
        of: find.byType(ToolCard),
        matching: find.byType(ClickToScrollContainer),
      );

      // Skip if no ClickToScrollContainer found (tool might not use it)
      if (clickToScrollFinder.evaluate().isEmpty) {
        debugPrint('SKIP: No ClickToScrollContainer found in expanded tool');
        return;
      }

      // Check if the content is scrollable (indicator visible)
      final indicatorFinder = find.text('click to scroll');
      if (indicatorFinder.evaluate().isEmpty) {
        debugPrint('SKIP: Content fits in container, no scroll needed');
        return;
      }

      debugPrint('FOUND: Scrollable ClickToScrollContainer with indicator');

      // Ensure the container is visible
      final container = clickToScrollFinder.first;
      await tester.ensureVisible(container);
      await safePumpAndSettle(tester);

      // Verify indicator is visible before activation
      expect(find.text('click to scroll'), findsOneWidget);

      // Get the internal scroll view and its controller
      final scrollViewFinder = find.descendant(
        of: container,
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollViewFinder, findsOneWidget);
      final scrollView = tester.widget<SingleChildScrollView>(scrollViewFinder);
      final controller = scrollView.controller!;
      final initialOffset = controller.offset;

      debugPrint('Before activation: offset=$initialOffset');

      // TAP TO ACTIVATE
      await tester.tap(container);
      await safePumpAndSettle(tester);

      // Verify indicator is now hidden (activated)
      expect(
        find.text('click to scroll'),
        findsNothing,
        reason: 'Indicator should hide after clicking to activate',
      );

      debugPrint('After activation: indicator hidden');

      // SEND SCROLL EVENT
      final center = tester.getCenter(container);
      final scrollEvent = PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 100),
      );
      await tester.sendEventToBinding(scrollEvent);
      await safePumpAndSettle(tester);

      final newOffset = controller.offset;
      debugPrint('After scroll: offset=$newOffset');

      // VERIFY SCROLL HAPPENED
      expect(
        newOffset,
        greaterThan(initialOffset),
        reason: 'Content should scroll after activation. '
            'Initial: $initialOffset, After: $newOffset',
      );

      debugPrint('SUCCESS: Scroll worked! $initialOffset -> $newOffset');
    });

    testWidgets('scroll is blocked before activation in tool card',
        (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Select the Log Replay chat
      await tester.tap(find.text('Log Replay'));
      await safePumpAndSettle(tester);

      // Find conversation scrollable
      final conversationScrollables = find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byWidgetPredicate((widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down),
      );

      // Find and expand Read tool
      final readToolFinder = find.text('Read');
      await tester.scrollUntilVisible(
        readToolFinder,
        -200,
        scrollable: conversationScrollables.first,
      );
      await safePumpAndSettle(tester);

      await tester.tap(readToolFinder.first);
      await safePumpAndSettle(tester);

      // Find ClickToScrollContainer
      final clickToScrollFinder = find.descendant(
        of: find.byType(ToolCard),
        matching: find.byType(ClickToScrollContainer),
      );

      if (clickToScrollFinder.evaluate().isEmpty) {
        debugPrint('SKIP: No ClickToScrollContainer found');
        return;
      }

      final indicatorFinder = find.text('click to scroll');
      if (indicatorFinder.evaluate().isEmpty) {
        debugPrint('SKIP: Content fits, no scroll needed');
        return;
      }

      debugPrint('Testing scroll blocking before activation...');

      final container = clickToScrollFinder.first;
      await tester.ensureVisible(container);
      await safePumpAndSettle(tester);

      // Get scroll controller
      final scrollViewFinder = find.descendant(
        of: container,
        matching: find.byType(SingleChildScrollView),
      );
      final scrollView = tester.widget<SingleChildScrollView>(scrollViewFinder);
      final controller = scrollView.controller!;
      final initialOffset = controller.offset;

      // DO NOT ACTIVATE - just send scroll event directly
      final center = tester.getCenter(container);
      final scrollEvent = PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 100),
      );
      await tester.sendEventToBinding(scrollEvent);
      await safePumpAndSettle(tester);

      // Verify scroll was BLOCKED
      expect(
        controller.offset,
        equals(initialOffset),
        reason: 'Scroll should be blocked when not activated',
      );

      // Indicator should still be visible
      expect(find.text('click to scroll'), findsOneWidget);

      debugPrint('SUCCESS: Scroll blocked before activation');
    });
  });
}
