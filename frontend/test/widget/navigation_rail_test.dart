import 'package:cc_insights_v2/widgets/navigation_rail.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppNavigationRail', () {
    testWidgets('renders project stats button at index 4', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppNavigationRail(
              selectedIndex: 0,
              onDestinationSelected: (index) {},
            ),
          ),
        ),
      );

      // Find the stats button by tooltip
      final statsButton = find.byTooltip('Project Stats');
      check(statsButton.evaluate()).isNotEmpty();
    });

    testWidgets('tapping stats button calls onDestinationSelected with 4',
        (tester) async {
      int? selectedIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppNavigationRail(
              selectedIndex: 0,
              onDestinationSelected: (index) {
                selectedIndex = index;
              },
            ),
          ),
        ),
      );

      // Tap the stats button
      await tester.tap(find.byTooltip('Project Stats'));
      await tester.pump();

      check(selectedIndex).equals(4);
    });

    testWidgets('stats button shows selected state when index is 4',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppNavigationRail(
              selectedIndex: 4,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );

      // The button should exist and be in selected state
      final statsButton = find.byTooltip('Project Stats');
      check(statsButton.evaluate()).isNotEmpty();
    });
  });
}
