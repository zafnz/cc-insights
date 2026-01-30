import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/main.dart';

import '../test_helpers.dart';

void main() {
  group('App Launch Tests', () {
    setUp(() {
      // Use mock data to avoid async project loading and timeouts
      useMockData = true;
    });

    tearDown(() {
      useMockData = false;
    });

    testWidgets('app launches and displays worktree list UI', (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify "Worktrees" header is displayed in the left panel
      expect(find.text('Worktrees'), findsOneWidget);

      // Verify at least one worktree entry is visible (e.g., "main" branch)
      expect(find.text('main'), findsAtLeastNWidgets(1));
    });

    testWidgets('app renders without visual errors', (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify no red error boxes are shown (Flutter error widgets)
      expect(find.byType(ErrorWidget), findsNothing);

      // Verify the scaffold is present (no AppBar - desktop app uses native)
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('app displays worktree with ghost card', (tester) async {
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify RichText widgets are rendered (used for status indicators)
      expect(find.byType(RichText), findsWidgets);

      // Verify the primary worktree is visible with 'main' branch
      // (default branch when no git info is available)
      expect(find.text('main'), findsOneWidget);

      // Verify the "New Worktree" ghost card is visible
      expect(find.text('New Worktree'), findsOneWidget);

      // Verify the "New Chat" ghost card is visible in the Chats panel
      // (also appears in WelcomeCard header, so we expect at least one)
      expect(find.text('New Chat'), findsWidgets);
    });
  });
}
