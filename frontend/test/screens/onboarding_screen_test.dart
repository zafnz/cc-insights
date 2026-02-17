import 'dart:async';

import 'package:cc_insights_v2/screens/onboarding_screen.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_cli_availability_service.dart';
import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late FakeCliAvailabilityService fakeCliAvailability;
  late SettingsService settingsService;
  bool completeCalled = false;
  bool cancelCalled = false;

  setUp(() {
    fakeCliAvailability = resources.track(FakeCliAvailabilityService());
    settingsService = resources.track(
      SettingsService(persistToDisk: false),
    );
    completeCalled = false;
    cancelCalled = false;
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  Widget createTestApp({
    (bool, String?) probeResult = (false, null),
    Map<String, (bool, String?)>? probeResults,
    Completer<void>? probeCompleter,
  }) {
    fakeCliAvailability.probeResult = probeResult;
    if (probeResults != null) {
      fakeCliAvailability.probeResults = probeResults;
    }
    fakeCliAvailability.probeCompleter = probeCompleter;
    return MaterialApp(
      home: OnboardingScreen(
        cliAvailability: fakeCliAvailability,
        settingsService: settingsService,
        onComplete: () => completeCalled = true,
        onCancel: () => cancelCalled = true,
      ),
    );
  }

  group('Scanning phase', () {
    testWidgets('shows scanning header and title', (tester) async {
      // Block probes so scanning phase stays visible
      final completer = Completer<void>();
      await tester.pumpWidget(createTestApp(probeCompleter: completer));
      await tester.pump();

      expect(find.text('Setting up for the first time'), findsOneWidget);
      expect(
        find.text('Looking for AI agents on your system...'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.search), findsOneWidget);

      // Release probes so test can clean up
      completer.complete();
      await safePumpAndSettle(tester);
    });

    testWidgets('shows agent names during scanning', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(createTestApp(probeCompleter: completer));
      await tester.pump();

      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('Gemini CLI'), findsOneWidget);

      completer.complete();
      await safePumpAndSettle(tester);
    });

    testWidgets('shows Cancel button during scanning', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(createTestApp(probeCompleter: completer));
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);

      completer.complete();
      await safePumpAndSettle(tester);
    });

    testWidgets('cancel button triggers onCancel callback', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(createTestApp(probeCompleter: completer));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelCalled, isTrue);

      completer.complete();
      await safePumpAndSettle(tester);
    });
  });

  group('Results phase - None found', () {
    testWidgets('shows "No AI agents found" when none detected',
        (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      // Wait for scanning to finish and results to appear
      await pumpUntilFound(tester, find.text('No AI agents found'));

      expect(find.text('Select one or more to set up:'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('Continue button is disabled when no agents found',
        (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('Continue'));

      final continueButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(continueButton.onPressed, isNull);
    });

    testWidgets('shows all 4 agent rows including ACP Compatible',
        (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('No AI agents found'));

      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('Gemini CLI'), findsOneWidget);
      expect(find.text('ACP Compatible'), findsOneWidget);
    });

    testWidgets(
        'shows "Not found" for scan targets and "Not configured" for ACP',
        (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('No AI agents found'));

      expect(find.text('Not found'), findsNWidgets(3));
      expect(find.text('Not configured'), findsOneWidget);
    });

    testWidgets('shows chevron arrows on not-found agents', (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('No AI agents found'));

      // 4 agents not found/not configured = 4 chevrons
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
    });

    testWidgets('shows Advanced button', (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('Advanced...'));

      expect(find.text('Advanced...'), findsOneWidget);
    });
  });

  group('Results phase - All found', () {
    testWidgets('shows green check_circle icon when all found',
        (tester) async {
      await tester.pumpWidget(
        createTestApp(probeResult: (true, '/usr/local/bin/test')),
      );
      await pumpUntilFound(tester, find.text('Found some AI agents'));

      expect(
        find.text('All known agents were found on your system.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle), findsAtLeastNWidgets(1));
    });

    testWidgets('Continue button is enabled when agents found',
        (tester) async {
      await tester.pumpWidget(
        createTestApp(probeResult: (true, '/usr/local/bin/test')),
      );
      await pumpUntilFound(tester, find.text('Continue'));

      final continueButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(continueButton.onPressed, isNotNull);
    });

    testWidgets('shows "Found at" paths for detected agents', (tester) async {
      await tester.pumpWidget(
        createTestApp(probeResult: (true, '/usr/local/bin/test')),
      );
      await pumpUntilFound(
        tester,
        find.text('Found at /usr/local/bin/test'),
      );

      expect(
        find.text('Found at /usr/local/bin/test'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('no warning banner when Claude is found', (tester) async {
      await tester.pumpWidget(
        createTestApp(probeResult: (true, '/usr/local/bin/test')),
      );
      await pumpUntilFound(tester, find.text('Found some AI agents'));

      expect(find.byIcon(Icons.warning_amber), findsNothing);
    });

    testWidgets('Continue calls onComplete callback', (tester) async {
      await tester.pumpWidget(
        createTestApp(probeResult: (true, '/usr/local/bin/test')),
      );
      await pumpUntilFound(tester, find.text('Continue'));

      await tester.tap(find.text('Continue'));
      await pumpUntil(
        tester,
        () => completeCalled,
        debugLabel: 'waiting for onComplete',
      );

      expect(completeCalled, isTrue);
    });
  });

  group('Agent setup screen', () {
    // Helper: pump past scanning into results, then tap Claude row.
    Future<void> navigateToClaudeSetup(WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      // Wait for results phase (not just 'Claude' which also appears in scanning)
      await pumpUntilFound(tester, find.text('No AI agents found'));

      await tester.tap(find.text('Claude'));
      await pumpUntilFound(tester, find.text('Set Up Claude'));
    }

    testWidgets('navigates to setup when clicking not-found agent',
        (tester) async {
      await navigateToClaudeSetup(tester);

      expect(find.text('Set Up Claude'), findsOneWidget);
      expect(find.text('Back to agent selection'), findsOneWidget);
    });

    testWidgets('shows install instructions for Claude', (tester) async {
      await navigateToClaudeSetup(tester);

      expect(find.text('brew install --cask claude-code'), findsOneWidget);
      expect(
        find.text('curl -fsSL https://claude.ai/install.sh | bash'),
        findsOneWidget,
      );
    });

    testWidgets('shows path input field and action buttons', (tester) async {
      await navigateToClaudeSetup(tester);

      expect(find.text('Or specify the path manually'), findsOneWidget);
      expect(find.text('Retry Detection'), findsOneWidget);
      expect(find.text('Verify & Continue'), findsOneWidget);
    });

    testWidgets('back button returns to results', (tester) async {
      await navigateToClaudeSetup(tester);

      await tester.tap(find.text('Back to agent selection'));
      await pumpUntilFound(tester, find.text('No AI agents found'));

      expect(find.text('No AI agents found'), findsOneWidget);
    });

    testWidgets('shows error when path is empty and verify clicked',
        (tester) async {
      await navigateToClaudeSetup(tester);

      // Button is below the fold — scroll it into view first
      await tester.ensureVisible(find.text('Verify & Continue'));
      await tester.pump();
      await tester.tap(find.text('Verify & Continue'));
      await tester.pump();

      expect(
        find.textContaining('Please enter a path'),
        findsOneWidget,
      );
    });
  });

  group('Advanced setup screen', () {
    testWidgets('opens when clicking Advanced button', (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('Advanced...'));

      await tester.tap(find.text('Advanced...'));
      await pumpUntilFound(tester, find.text('Done'));

      expect(find.text('Agents'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Add New'), findsOneWidget);
    });

    testWidgets('shows default agents in sidebar', (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('Advanced...'));

      await tester.tap(find.text('Advanced...'));
      await pumpUntilFound(tester, find.text('Done'));

      expect(find.text('Claude'), findsAtLeastNWidgets(1));
      expect(find.text('Codex'), findsAtLeastNWidgets(1));
      expect(find.text('Gemini'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows agent config form fields', (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('Advanced...'));

      await tester.tap(find.text('Advanced...'));
      await pumpUntilFound(tester, find.text('Done'));

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.text('CLI Path'), findsOneWidget);
      expect(find.text('Args'), findsOneWidget);
      expect(find.text('Environment'), findsOneWidget);
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('Permissions'), findsOneWidget);
    });

    testWidgets('Done button returns to results', (tester) async {
      await tester.pumpWidget(createTestApp(probeResult: (false, null)));
      await pumpUntilFound(tester, find.text('Advanced...'));

      await tester.tap(find.text('Advanced...'));
      await pumpUntilFound(tester, find.text('Done'));

      await tester.tap(find.text('Done'));
      await pumpUntilFound(tester, find.text('No AI agents found'));

      expect(find.text('No AI agents found'), findsOneWidget);
    });
  });

  group('Agent seeding - partial find', () {
    testWidgets('only codex found: Continue saves only Codex agent',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        probeResults: {
          'claude': (false, null),
          'codex': (true, '/usr/local/bin/codex'),
          'gemini': (false, null),
        },
      ));
      await pumpUntilFound(tester, find.text('Found some AI agents'));

      // Codex should be found, Claude and Gemini should not
      expect(find.text('Found at /usr/local/bin/codex'), findsOneWidget);

      await tester.ensureVisible(find.text('Continue'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await pumpUntil(
        tester,
        () => settingsService.hasCompletedOnboarding,
        debugLabel: 'waiting for onboarding.completed flag',
      );

      // Only Codex should be in the agent list
      final agents = settingsService.availableAgents;
      expect(agents.length, 1);
      expect(agents.first.driver, 'codex');
      expect(agents.first.name, 'Codex');
    });

    testWidgets('only claude found: Continue saves only Claude agent',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        probeResults: {
          'claude': (true, '/usr/local/bin/claude'),
          'codex': (false, null),
          'gemini': (false, null),
        },
      ));
      await pumpUntilFound(tester, find.text('Found some AI agents'));

      await tester.ensureVisible(find.text('Continue'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await pumpUntil(
        tester,
        () => settingsService.hasCompletedOnboarding,
        debugLabel: 'waiting for onboarding.completed flag',
      );

      final agents = settingsService.availableAgents;
      expect(agents.length, 1);
      expect(agents.first.driver, 'claude');
    });

    testWidgets(
        'Advanced setup does not persist unfound agents when user clicks Done',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        probeResults: {
          'claude': (false, null),
          'codex': (true, '/usr/local/bin/codex'),
          'gemini': (false, null),
        },
      ));
      await pumpUntilFound(tester, find.text('Found some AI agents'));

      // Go to Advanced
      await tester.ensureVisible(find.text('Advanced...'));
      await tester.pump();
      await tester.tap(find.text('Advanced...'));
      await pumpUntilFound(tester, find.text('Done'));

      // Click Done without changing anything
      await tester.tap(find.text('Done'));
      await pumpUntilFound(tester, find.text('Found some AI agents'));

      // Now click Continue
      await tester.ensureVisible(find.text('Continue'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await pumpUntil(
        tester,
        () => settingsService.hasCompletedOnboarding,
        debugLabel: 'waiting for onboarding.completed flag',
      );

      // Should still only have Codex since that's the only one found
      final agents = settingsService.availableAgents;
      expect(agents.length, 1);
      expect(agents.first.driver, 'codex');
    });
  });

  group('Onboarding gate conditions', () {
    testWidgets('hasCompletedOnboarding defaults to false', (tester) async {
      expect(settingsService.hasCompletedOnboarding, isFalse);
    });

    testWidgets('hasExplicitlyConfiguredAgents defaults to false',
        (tester) async {
      expect(settingsService.hasExplicitlyConfiguredAgents, isFalse);
    });

    testWidgets('setOnboardingCompleted persists the flag', (tester) async {
      await settingsService.setOnboardingCompleted(true);
      expect(settingsService.hasCompletedOnboarding, isTrue);
    });

    testWidgets('Continue sets onboarding completed', (tester) async {
      await tester.pumpWidget(
        createTestApp(probeResult: (true, '/usr/bin/test')),
      );
      await pumpUntilFound(tester, find.text('Continue'));

      await tester.tap(find.text('Continue'));
      await pumpUntil(
        tester,
        () => settingsService.hasCompletedOnboarding,
        debugLabel: 'waiting for onboarding.completed flag',
      );

      expect(settingsService.hasCompletedOnboarding, isTrue);
    });
  });
}
