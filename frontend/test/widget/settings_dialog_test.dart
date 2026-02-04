import 'package:cc_insights_v2/state/theme_state.dart';
import 'package:cc_insights_v2/widgets/settings_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  group('SettingsDialog', () {
    late ThemeState themeState;

    setUp(() {
      themeState = ThemeState();
    });

    Widget createTestApp({Widget? home}) {
      return ChangeNotifierProvider<ThemeState>.value(
        value: themeState,
        child: MaterialApp(
          home: home ?? const Scaffold(body: SettingsDialog()),
        ),
      );
    }

    testWidgets('displays Settings title', (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('displays Color section', (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Color'), findsOneWidget);
    });

    testWidgets('displays Appearance section',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('displays theme mode segments',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
    });

    testWidgets('tapping preset changes seed color',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Find the Blue preset tooltip
      final blueFinder = find.byTooltip('Blue');
      expect(blueFinder, findsOneWidget);

      await tester.tap(blueFinder);
      await tester.pump();

      check(themeState.seedColor.value)
          .equals(Colors.blue.value);
    });

    testWidgets('tapping Dark mode changes theme mode',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.text('Dark'));
      await tester.pump();

      check(themeState.themeMode).equals(ThemeMode.dark);
    });

    testWidgets('tapping Light mode changes theme mode',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.text('Light'));
      await tester.pump();

      check(themeState.themeMode).equals(ThemeMode.light);
    });

    testWidgets('Close button dismisses dialog',
        (tester) async {
      await tester.pumpWidget(
        createTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSettingsDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Open the dialog
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      expect(find.text('Settings'), findsOneWidget);

      // Close the dialog
      await tester.tap(find.text('Close'));
      await safePumpAndSettle(tester);

      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('displays custom color button',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(
        find.byTooltip('Custom color'),
        findsOneWidget,
      );
    });

    testWidgets(
        'tapping custom color shows hex input',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byTooltip('Custom color'));
      await tester.pump();

      expect(
        find.byType(TextField),
        findsOneWidget,
      );
      expect(find.text('Apply'), findsOneWidget);
    });
  });
}
