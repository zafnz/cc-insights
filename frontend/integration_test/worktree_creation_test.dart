import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/panels/content_panel.dart';
import 'package:cc_insights_v2/panels/create_worktree_panel.dart';
import 'package:cc_insights_v2/panels/panels.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';

/// Integration tests for the worktree creation flow.
///
/// These tests verify the UI flow for creating git worktrees:
/// - Navigation from worktree panel to create panel
/// - Form validation and error display
/// - Cancel functionality returning to conversation view
///
/// Note: These tests use mock data and do not actually create git worktrees
/// on the filesystem to avoid side effects.
///
/// Run tests:
///   flutter test integration_test/worktree_creation_test.dart -d macos
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

  group('Worktree Creation Navigation Flow', () {
    testWidgets('clicking New Worktree card shows CreateWorktreePanel',
        (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify we start with the Conversation panel visible (default view)
      expect(find.text('Conversation'), findsOneWidget);

      // Find and verify the "New Worktree" card exists in the WorktreePanel
      final newWorktreeCard = find.text('New Worktree');
      expect(newWorktreeCard, findsOneWidget);

      // Tap on "New Worktree" card
      await tester.tap(newWorktreeCard);
      await safePumpAndSettle(tester);

      // Verify CreateWorktreePanel widget is present
      expect(find.byType(CreateWorktreePanel), findsOneWidget);

      // Wait for loading to complete before checking for button
      await pumpUntilGone(
        tester,
        find.byType(CircularProgressIndicator),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for CreateWorktreePanel to load',
      );

      // Verify the "Create Worktree" button label exists - the button is a
      // FilledButton.icon which has the text as a child
      expect(find.text('Create Worktree'), findsWidgets);
    });

    testWidgets('CreateWorktreePanel shows correct UI elements',
        (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Navigate to create worktree panel
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading to complete (branch list loads asynchronously)
      await pumpUntilGone(
        tester,
        find.byType(CircularProgressIndicator),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for CreateWorktreePanel to load',
      );

      // Verify the help card is visible (collapsed by default)
      expect(find.text('What is a Git Worktree?'), findsOneWidget);

      // Verify Branch Name label is visible
      expect(find.text('Branch Name'), findsOneWidget);

      // Verify Worktree Root Directory label is visible
      expect(find.text('Worktree Root Directory'), findsOneWidget);

      // Verify action buttons are present
      // Cancel is a TextButton, Create Worktree is a FilledButton.icon
      expect(find.text('Cancel'), findsOneWidget);
      // "Create Worktree" appears in both the panel header and the button
      expect(find.text('Create Worktree'), findsWidgets);

      // Verify the directory warning note
      expect(
        find.text('This directory must be outside the project repository'),
        findsOneWidget,
      );
    });

    testWidgets('help card expands when tapped', (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Navigate to create worktree panel
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading to complete
      await pumpUntilGone(
        tester,
        find.byType(CircularProgressIndicator),
        timeout: const Duration(seconds: 5),
      );

      // Initially the expanded content should not be visible
      expect(
        find.textContaining(
          'A worktree lets you work on multiple branches simultaneously',
        ),
        findsNothing,
      );

      // Tap on the help card header to expand
      await tester.tap(find.text('What is a Git Worktree?'));
      await safePumpAndSettle(tester);

      // Now the expanded content should be visible
      expect(
        find.textContaining(
          'A worktree lets you work on multiple branches simultaneously',
        ),
        findsOneWidget,
      );

      // Verify bullet points are shown
      expect(
        find.textContaining('Working on a feature'),
        findsOneWidget,
      );
    });

    testWidgets('Cancel button returns to conversation view', (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Navigate to create worktree panel
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading to complete
      await pumpUntilGone(
        tester,
        find.byType(CircularProgressIndicator),
        timeout: const Duration(seconds: 5),
      );

      // Verify we're on the create worktree panel
      expect(find.byType(CreateWorktreePanel), findsOneWidget);

      // Tap Cancel button (use specific finder)
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await safePumpAndSettle(tester);

      // Verify we're back to the conversation view
      expect(find.text('Conversation'), findsOneWidget);

      // CreateWorktreePanel should no longer be visible
      expect(find.byType(CreateWorktreePanel), findsNothing);
    });
  });

  group('Worktree Creation Form Validation', () {
    testWidgets('empty branch name shows validation error', (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Navigate to create worktree panel
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading to complete - the panel will finish loading
      // (possibly with an error if git operations fail in mock mode)
      // Wait for the Branch Name label to appear which indicates loading done
      await pumpUntilFound(
        tester,
        find.text('Branch Name'),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for Branch Name label',
      );

      // The branch name field should be empty by default
      // Find the Create Worktree button by looking for a button that contains
      // the add icon (the FilledButton.icon uses Icons.add)
      // Note: There's also an add icon in the "New Worktree" card, but we need
      // to find the one that's part of the action bar at the bottom
      final allCreateWorktreeTexts = find.text('Create Worktree');
      // The last one should be in the button (first one is panel header)
      expect(allCreateWorktreeTexts, findsWidgets);
      await tester.tap(allCreateWorktreeTexts.last);
      await safePumpAndSettle(tester);

      // Verify error message appears for empty branch name
      expect(find.text('Please enter a branch name.'), findsOneWidget);
    });

    testWidgets('empty root directory shows validation error', (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Navigate to create worktree panel
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading to complete - wait for Branch Name label
      await pumpUntilFound(
        tester,
        find.text('Branch Name'),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for Branch Name label',
      );

      // Find the text fields - branch field uses Autocomplete, root uses TextField
      // The root field should have a TextField descendant
      final textFields = find.byType(TextField);

      // There should be at least 2 text fields (branch autocomplete, root)
      expect(textFields, findsWidgets);

      // Enter a branch name in the first text field (autocomplete field)
      await tester.enterText(textFields.first, 'test-branch');
      await safePumpAndSettle(tester);

      // Clear the root directory field (find the second TextField)
      // The root field is the one with the folder icon
      final rootTextField = find.widgetWithIcon(TextField, Icons.folder_outlined);
      expect(rootTextField, findsOneWidget);

      // Clear the root field by entering empty text
      await tester.enterText(rootTextField, '');
      await safePumpAndSettle(tester);

      // Find and tap the Create Worktree button (use the last text match)
      final allCreateWorktreeTexts = find.text('Create Worktree');
      expect(allCreateWorktreeTexts, findsWidgets);
      await tester.tap(allCreateWorktreeTexts.last);
      await safePumpAndSettle(tester);

      // Verify error message appears for empty root directory
      expect(find.text('Please enter a worktree root directory.'), findsOneWidget);
    });

    testWidgets('form has text fields for branch and root', (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Navigate to create worktree panel
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading to complete - wait for Branch Name label
      await pumpUntilFound(
        tester,
        find.text('Branch Name'),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for Branch Name label',
      );

      // Verify the root directory label exists
      expect(find.text('Worktree Root Directory'), findsOneWidget);

      // Verify text fields exist - at least one for branch, one for root
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);

      // Find the root directory field (has folder icon)
      final rootTextField = find.widgetWithIcon(TextField, Icons.folder_outlined);
      expect(rootTextField, findsOneWidget);

      // Find the branch field (has call_split icon)
      final branchTextField = find.widgetWithIcon(TextField, Icons.call_split);
      expect(branchTextField, findsOneWidget);
    });
  });

  group('Worktree Creation Content Panel Integration', () {
    testWidgets('ContentPanel switches between conversation and create modes',
        (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify ContentPanel exists
      expect(find.byType(ContentPanel), findsOneWidget);

      // Initially shows conversation panel
      expect(find.byType(ConversationPanel), findsOneWidget);
      expect(find.byType(CreateWorktreePanel), findsNothing);

      // Navigate to create worktree
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading
      await pumpUntilGone(
        tester,
        find.byType(CircularProgressIndicator),
        timeout: const Duration(seconds: 5),
      );

      // Now shows create worktree panel
      expect(find.byType(CreateWorktreePanel), findsOneWidget);
      expect(find.byType(ConversationPanel), findsNothing);

      // Navigate back
      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      // Back to conversation panel
      expect(find.byType(ConversationPanel), findsOneWidget);
      expect(find.byType(CreateWorktreePanel), findsNothing);
    });

    testWidgets('worktree panel remains visible during create flow',
        (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Verify worktree panel is visible
      expect(find.byType(WorktreePanel), findsOneWidget);
      expect(find.text('Worktrees'), findsOneWidget);

      // Navigate to create worktree
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Worktree panel should still be visible during create flow
      expect(find.byType(WorktreePanel), findsOneWidget);
      expect(find.text('Worktrees'), findsOneWidget);

      // Existing worktrees should still be listed
      expect(find.text('main'), findsOneWidget);
      expect(find.text('feat-dark-mode'), findsOneWidget);
    });
  });

  group('Worktree Creation Error Display', () {
    testWidgets('error card displays error message with icon', (tester) async {
      // Launch the app
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Navigate to create worktree panel
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // Wait for loading to complete - wait for Branch Name label
      await pumpUntilFound(
        tester,
        find.text('Branch Name'),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for Branch Name label',
      );

      // Find and tap the Create Worktree button to trigger validation error
      final allCreateWorktreeTexts = find.text('Create Worktree');
      expect(allCreateWorktreeTexts, findsWidgets);
      await tester.tap(allCreateWorktreeTexts.last);
      await safePumpAndSettle(tester);

      // Verify error card appears with error icon
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Please enter a branch name.'), findsOneWidget);
    });
  });

  // Note: We do not test actual worktree creation because:
  // 1. It would modify the filesystem
  // 2. It requires a real git repository
  // 3. Integration tests should focus on UI flow validation
  //
  // For testing actual git operations, use unit tests with mocked GitService.
}
