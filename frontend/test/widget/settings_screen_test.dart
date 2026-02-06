import 'dart:io';

import 'package:cc_insights_v2/screens/settings_screen.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_cli_availability_service.dart';
import '../test_helpers.dart';

void main() {
  late Directory tempDir;
  late SettingsService settingsService;
  late MockBackendService mockBackend;
  late FakeCliAvailabilityService fakeCliAvailability;

  setUp(() {
    RuntimeConfig.resetForTesting();
    RuntimeConfig.initialize([]);
    tempDir = Directory.systemTemp.createTempSync('settings_screen_test_');
    settingsService = SettingsService(
      configPath: '${tempDir.path}/config.json',
    );
    mockBackend = MockBackendService();
    fakeCliAvailability = FakeCliAvailabilityService();
  });

  tearDown(() {
    settingsService.dispose();
    mockBackend.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget createTestApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BackendService>.value(value: mockBackend),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<CliAvailabilityService>.value(
          value: fakeCliAvailability,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SettingsScreen()),
      ),
    );
  }

  group('SettingsScreen', () {
    group('sidebar', () {
      testWidgets('renders all category labels', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // "Appearance" appears in sidebar AND as content header
        expect(find.text('Appearance'), findsWidgets);
        expect(find.text('Behavior'), findsOneWidget);
        expect(find.text('Session'), findsOneWidget);
        expect(find.text('Developer'), findsOneWidget);
      });

      testWidgets('renders Settings header', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets('renders Reset to Defaults button', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(find.text('Reset to Defaults'), findsOneWidget);
      });

      testWidgets('switching category changes content', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Initially shows Appearance content
        expect(find.text('Bash Tool Summary'), findsOneWidget);

        // Tap on Session category
        await tester.tap(find.text('Session'));
        await safePumpAndSettle(tester);

        // Now shows Session content (Claude CLI Path is the first setting)
        expect(find.text('Claude CLI Path'), findsOneWidget);
        // Appearance settings should be gone
        expect(find.text('Bash Tool Summary'), findsNothing);
      });
    });

    group('content', () {
      testWidgets('shows category description', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(
          find.text(
            'Customize how CC Insights looks and displays information',
          ),
          findsOneWidget,
        );
      });

      testWidgets('renders appearance settings', (tester) async {
        await tester.pumpWidget(createTestApp());

        // Use a large enough surface so all settings are visible
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        expect(find.text('Bash Tool Summary'), findsOneWidget);
        expect(find.text('Relative File Paths'), findsOneWidget);
        expect(find.text('Show Timestamps'), findsOneWidget);

        // Scroll down to see the last setting
        await tester.scrollUntilVisible(
          find.text('Timestamp Idle Threshold'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Timestamp Idle Threshold'), findsOneWidget);

        // Reset surface size
        await tester.binding.setSurfaceSize(null);
      });
    });

    group('toggle setting', () {
      testWidgets('renders switch widget', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        final switches = tester.widgetList<Switch>(find.byType(Switch));
        expect(switches.isNotEmpty, isTrue);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('toggling updates value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        expect(
          settingsService.getValue<bool>('appearance.showTimestamps'),
          false,
        );

        // Scroll down to Show Timestamps and tap its switch
        await tester.scrollUntilVisible(
          find.text('Show Timestamps'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        // Find the switch closest to Show Timestamps text.
        // Relative File Paths is the first toggle, Show Timestamps is
        // the second toggle in Appearance.
        final switches = find.byType(Switch);
        // Ensure the switch itself is visible after scrolling to the text
        await tester.ensureVisible(switches.at(1));
        await tester.pumpAndSettle();
        await tester.tap(switches.at(1));
        await safePumpAndSettle(tester);

        expect(
          settingsService.getValue<bool>('appearance.showTimestamps'),
          true,
        );

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('dropdown setting', () {
      testWidgets('renders dropdown with current value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // "Description" appears as both a code span and
        // dropdown label - just verify it exists
        expect(find.text('Description'), findsWidgets);
      });

      testWidgets('changing dropdown updates value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Scroll to Bash Tool Summary dropdown (second dropdown
        // after Theme Mode)
        await tester.scrollUntilVisible(
          find.text('Bash Tool Summary'),
          100,
          scrollable: find.byType(Scrollable).last,
        );

        // Find and tap the second dropdown (Bash Tool Summary;
        // first is Theme Mode)
        final dropdown = find.byType(DropdownButton<String>).at(1);
        await tester.tap(dropdown);
        await safePumpAndSettle(tester);

        // Select "Command" from the dropdown menu
        await tester.tap(find.text('Command').last);
        await safePumpAndSettle(tester);

        expect(
          settingsService.getValue<String>('appearance.bashToolSummary'),
          'command',
        );

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('number setting', () {
      testWidgets('renders text field', (tester) async {
        await tester.pumpWidget(createTestApp());

        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Scroll down to see the number input
        await tester.scrollUntilVisible(
          find.text('Timestamp Idle Threshold'),
          100,
          scrollable: find.byType(Scrollable).last,
        );

        // Find the TextField for the number input
        final textField = find.byType(TextField);
        expect(textField, findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('reset to defaults', () {
      testWidgets('shows confirmation dialog', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Reset to Defaults'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.text('This will reset all settings to their '
              'default values. This cannot be undone.'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);
      });

      testWidgets('cancel closes dialog without resetting',
          (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Change a value directly on the service (not through UI)
        settingsService.setValue('appearance.bashToolSummary', 'command');
        await tester.pump();

        // Open the reset dialog
        await tester.tap(find.text('Reset to Defaults'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Value should still be changed
        expect(
          settingsService.getValue<String>('appearance.bashToolSummary'),
          'command',
        );
      });

      testWidgets('confirm resets all values', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Change a value directly on the service (not through UI)
        settingsService.setValue('appearance.bashToolSummary', 'command');
        await tester.pump();

        // Open the reset dialog
        await tester.tap(find.text('Reset to Defaults'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Confirm reset
        await tester.tap(find.text('Reset'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          settingsService.getValue<String>('appearance.bashToolSummary'),
          'description',
        );
      });
    });

    group('description text', () {
      testWidgets('renders inline code spans', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // The description for Bash Tool Summary contains
        // `Description` and `Command` code spans
        expect(find.text('Description'), findsWidgets);
        expect(find.text('Command'), findsWidgets);
      });
    });

    group('bypass permission warning', () {
      testWidgets('shows warning dialog when selecting Bypass',
          (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Navigate to Session category
        await tester.tap(find.text('Session'));
        await safePumpAndSettle(tester);

        // Scroll to make Permission Mode dropdown visible
        await tester.scrollUntilVisible(
          find.text('Default Permission Mode'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await safePumpAndSettle(tester);

        // Find the permission mode dropdown (third dropdown in Session)
        final dropdowns = find.byType(DropdownButton<String>);
        // There should be 3 dropdowns: Backend, Model, Permission Mode
        expect(dropdowns, findsNWidgets(3));
        await tester.tap(dropdowns.last);
        await safePumpAndSettle(tester);

        // Select Bypass
        await tester.tap(find.text('Bypass').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Warning dialog should appear
        expect(find.text('Enable Bypass Mode?'), findsOneWidget);
        expect(
          find.textContaining('approves all tool operations'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Enable Bypass'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('cancel does not change value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Session'));
        await safePumpAndSettle(tester);

        // Scroll to make Permission Mode dropdown visible
        await tester.scrollUntilVisible(
          find.text('Default Permission Mode'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await safePumpAndSettle(tester);

        final dropdowns = find.byType(DropdownButton<String>);
        await tester.tap(dropdowns.last);
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Bypass').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Cancel the dialog
        await tester.tap(find.text('Cancel'));
        await safePumpAndSettle(tester);

        // Value should still be 'default'
        expect(
          settingsService.getValue<String>(
            'session.defaultPermissionMode',
          ),
          'default',
        );

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('confirm sets bypass value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Session'));
        await safePumpAndSettle(tester);

        // Scroll to make Permission Mode dropdown visible
        await tester.scrollUntilVisible(
          find.text('Default Permission Mode'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await safePumpAndSettle(tester);

        final dropdowns = find.byType(DropdownButton<String>);
        await tester.tap(dropdowns.last);
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Bypass').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Confirm the dialog
        await tester.tap(find.text('Enable Bypass'));
        await safePumpAndSettle(tester);

        // Value should now be 'bypassPermissions'
        expect(
          settingsService.getValue<String>(
            'session.defaultPermissionMode',
          ),
          'bypassPermissions',
        );

        await tester.binding.setSurfaceSize(null);
      });
    });
  });
}
