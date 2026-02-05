import 'package:cc_insights_v2/models/setting_definition.dart';
import 'package:cc_insights_v2/screens/settings_screen.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:cc_insights_v2/state/theme_state.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  group('SettingsScreen theme settings', () {
    late SettingsService settingsService;
    late MockBackendService mockBackend;

    setUp(() {
      // Use a temp path so we never touch real config.
      settingsService = SettingsService(
        configPath: '/tmp/cc_test_settings.json',
      );
      mockBackend = MockBackendService();
    });

    tearDown(() {
      mockBackend.dispose();
    });

    Widget createTestApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<BackendService>.value(value: mockBackend),
          ChangeNotifierProvider<SettingsService>.value(
            value: settingsService,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SettingsScreen()),
        ),
      );
    }

    testWidgets('displays Accent Color setting',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Accent Color'), findsOneWidget);
    });

    testWidgets('displays Theme Mode setting',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Theme Mode'), findsOneWidget);
    });

    testWidgets('displays preset color swatches',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Two color pickers (Accent Color + Input Text Color)
      // each show all presets.
      for (final preset in ThemePresetColor.values) {
        expect(
          find.byTooltip(preset.label),
          findsNWidgets(2),
        );
      }
    });

    testWidgets('tapping preset updates seed color',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Two "Blue" swatches exist; the first belongs to
      // the Accent Color picker.
      await tester.tap(find.byTooltip('Blue').first);
      await tester.pump();

      final value =
          settingsService.getValue<int>(
            'appearance.seedColor',
          );
      check(value).equals(Colors.blue.value);
    });

    testWidgets('displays custom color button',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Two color pickers each have a custom color button.
      expect(
        find.byTooltip('Custom color'),
        findsNWidgets(2),
      );
    });

    testWidgets('tapping custom color shows hex input',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byTooltip('Custom color').first);
      await tester.pump();

      // There may be other TextFields on the screen
      // (e.g., the number input). Find the one with
      // the hex hint text.
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets(
        'colorPicker type exists in SettingType enum', (_) async {
      // Verify the enum value is accessible.
      check(SettingType.colorPicker.name)
          .equals('colorPicker');
    });
  });
}
