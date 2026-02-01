import 'package:cc_insights_v2/widgets/click_to_scroll_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('ClickToScrollContainer', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 100,
              child: const Text('Test content'),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.text('Test content'), findsOneWidget);
    });

    testWidgets('shows scroll indicator when content exceeds maxHeight',
        (tester) async {
      // Create content taller than maxHeight
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 50,
              child: const SizedBox(
                height: 200,
                child: Text('Tall content'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should show "click to scroll" indicator
      expect(find.text('click to scroll'), findsOneWidget);
    });

    testWidgets('does not show scroll indicator when content fits',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 200,
              child: const SizedBox(
                height: 50,
                child: Text('Short content'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should NOT show indicator since content fits
      expect(find.text('click to scroll'), findsNothing);
    });

    testWidgets('activates scrolling on tap when content exceeds maxHeight',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 50,
              child: const SizedBox(
                height: 200,
                child: Text('Tall content'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Initially shows indicator
      expect(find.text('click to scroll'), findsOneWidget);

      // Tap to activate
      await tester.tap(find.byType(ClickToScrollContainer));
      await safePumpAndSettle(tester);

      // Indicator should be hidden when active
      expect(find.text('click to scroll'), findsNothing);
    });

    testWidgets('deactivates on tap outside', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(
                  height: 100,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Colors.grey,
                    child: Text('Outside area'),
                  ),
                ),
                ClickToScrollContainer(
                  maxHeight: 50,
                  child: const SizedBox(
                    height: 200,
                    child: Text('Tall content'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Tap to activate
      await tester.tap(find.byType(ClickToScrollContainer));
      await safePumpAndSettle(tester);
      expect(find.text('click to scroll'), findsNothing);

      // Tap outside the container
      await tester.tap(find.text('Outside area'));
      await safePumpAndSettle(tester);

      // Should show indicator again (deactivated)
      expect(find.text('click to scroll'), findsOneWidget);
    });

    testWidgets('deactivates on Escape key', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 50,
              child: const SizedBox(
                height: 200,
                child: Text('Tall content'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Tap to activate
      await tester.tap(find.byType(ClickToScrollContainer));
      await safePumpAndSettle(tester);
      expect(find.text('click to scroll'), findsNothing);

      // Press Escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await safePumpAndSettle(tester);

      // Should show indicator again
      expect(find.text('click to scroll'), findsOneWidget);
    });

    testWidgets('uses NeverScrollableScrollPhysics when inactive',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 50,
              child: const SizedBox(
                height: 200,
                child: Text('Tall content'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Find the SingleChildScrollView
      final scrollView =
          tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('uses ClampingScrollPhysics when active, NeverScrollableScrollPhysics when inactive',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 50,
              child: const SizedBox(
                height: 200,
                child: Text('Tall content'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Initially inactive - should use NeverScrollableScrollPhysics
      var scrollView =
          tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());

      // Tap to activate
      await tester.tap(find.byType(ClickToScrollContainer));
      await safePumpAndSettle(tester);

      // When active - should use ClampingScrollPhysics for native scroll behavior
      scrollView =
          tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scrollView.physics, isA<ClampingScrollPhysics>());
    });

    testWidgets('applies backgroundColor and borderRadius', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 100,
              backgroundColor: Colors.blue,
              borderRadius: BorderRadius.circular(8),
              child: const Text('Content'),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Find the container and verify decoration
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ClickToScrollContainer),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.color, Colors.blue);
      expect(decoration?.borderRadius, BorderRadius.circular(8));
    });

    testWidgets('applies padding to content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 100,
              padding: const EdgeInsets.all(16),
              child: const Text('Padded content'),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Find the Padding widget that wraps the SingleChildScrollView
      final paddingFinder = find.ancestor(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Padding),
      );
      final padding = tester.widget<Padding>(paddingFinder.first);
      expect(padding.padding, const EdgeInsets.all(16));
    });

    testWidgets('does not activate when content fits', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickToScrollContainer(
              maxHeight: 200,
              child: const SizedBox(
                height: 50,
                child: Text('Short content'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Tap - should not activate since content fits
      await tester.tap(find.byType(ClickToScrollContainer));
      await safePumpAndSettle(tester);

      // Should still use NeverScrollableScrollPhysics (no activation)
      final scrollView =
          tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('works inside a ListView (nested scroll scenario)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 100, child: Text('Item 1')),
                ClickToScrollContainer(
                  maxHeight: 50,
                  child: const SizedBox(
                    height: 200,
                    child: Text('Scrollable tool content'),
                  ),
                ),
                const SizedBox(height: 100, child: Text('Item 3')),
              ],
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should render with indicator
      expect(find.text('click to scroll'), findsOneWidget);
      expect(find.text('Scrollable tool content'), findsOneWidget);
    });
  });
}
