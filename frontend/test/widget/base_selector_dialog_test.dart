import 'package:cc_insights_v2/widgets/base_selector_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  /// Pumps a [MaterialApp] that shows the [BaseSelectorDialog] when a button
  /// is tapped. Returns after the dialog is open.
  Future<void> pumpDialog(
    WidgetTester tester, {
    String? currentBaseOverride,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await showDialog<String?>(
                    context: context,
                    builder: (_) => BaseSelectorDialog(
                      currentBaseOverride: currentBaseOverride,
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await safePumpAndSettle(tester);

    // Tap the button to open the dialog.
    await tester.tap(find.text('Open'));
    await safePumpAndSettle(tester);
  }

  group('BaseSelectorDialog', () {
    testWidgets('shows all options', (tester) async {
      await pumpDialog(tester);

      // Verify radio options are displayed.
      expect(find.text('main'), findsOneWidget);
      expect(find.text('origin/main'), findsOneWidget);

      // Custom text field should always be visible with hint.
      expect(find.byKey(BaseSelectorDialogKeys.customField), findsOneWidget);

      // Verify title.
      expect(find.text('Change Base Ref'), findsOneWidget);

      // Verify action buttons.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('pre-selects "main" when value is null', (tester) async {
      await pumpDialog(tester, currentBaseOverride: null);

      // The main radio should be selected.
      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.mainOption),
      );
      check(radio.checked).equals(true);
    });

    testWidgets('pre-selects "main" when current value is main',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: 'main');

      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.mainOption),
      );
      check(radio.checked).equals(true);
    });

    testWidgets('pre-selects "origin/main" when current value is origin/main',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: 'origin/main');

      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.originMainOption),
      );
      check(radio.checked).equals(true);
    });

    testWidgets('pre-selects "Custom" with text for non-standard value',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: 'develop');

      // Custom radio should be selected.
      final radio = tester.widget<Radio<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.customOption),
      );
      check(radio.groupValue).equals(radio.value);

      // Custom text field should have the value.
      final textField = tester.widget<TextField>(
        find.byKey(BaseSelectorDialogKeys.customField),
      );
      check(textField.controller!.text).equals('develop');
    });

    testWidgets('selecting "main" and applying returns "main"',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBaseOverride: 'origin/main',
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      // Tap the "main" radio.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.mainOption));
      await tester.pump();

      // Tap Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await safePumpAndSettle(tester);

      check(result).equals('main');
    });

    testWidgets('selecting "origin/main" and applying returns "origin/main"',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBaseOverride: 'main',
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(BaseSelectorDialogKeys.originMainOption));
      await tester.pump();

      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await safePumpAndSettle(tester);

      check(result).equals('origin/main');
    });

    testWidgets('tapping custom field selects custom option', (tester) async {
      await pumpDialog(tester, currentBaseOverride: 'main');

      // Verify main is selected initially.
      var mainRadio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.mainOption),
      );
      check(mainRadio.checked).equals(true);

      // Tap the custom text field.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customField));
      await tester.pump();

      // Custom radio should now be selected.
      final customRadio = tester.widget<Radio<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.customOption),
      );
      check(customRadio.groupValue).equals(customRadio.value);
    });

    testWidgets('Apply is disabled when Custom is selected but field is empty',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: 'main');

      // Tap the custom text field to select custom option.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customField));
      await tester.pump();

      // Clear any text.
      await tester.enterText(
        find.byKey(BaseSelectorDialogKeys.customField),
        '',
      );
      await tester.pump();

      // Apply should be disabled.
      final applyButton = tester.widget<FilledButton>(
        find.byKey(BaseSelectorDialogKeys.applyButton),
      );
      check(applyButton.onPressed).isNull();
    });

    testWidgets('Apply is enabled when Custom has text', (tester) async {
      await pumpDialog(tester, currentBaseOverride: 'main');

      // Tap the custom text field.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customField));
      await tester.pump();

      // Type a custom ref.
      await tester.enterText(
        find.byKey(BaseSelectorDialogKeys.customField),
        'develop',
      );
      await tester.pump();

      // Apply should be enabled.
      final applyButton = tester.widget<FilledButton>(
        find.byKey(BaseSelectorDialogKeys.applyButton),
      );
      check(applyButton.onPressed).isNotNull();
    });

    testWidgets('custom field value is returned when applying',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBaseOverride: 'main',
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      // Tap custom field.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customField));
      await tester.pump();

      // Type a custom ref.
      await tester.enterText(
        find.byKey(BaseSelectorDialogKeys.customField),
        'origin/develop',
      );
      await tester.pump();

      // Tap Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await safePumpAndSettle(tester);

      check(result).equals('origin/develop');
    });

    testWidgets('cancel closes dialog and returns null', (tester) async {
      String? result = 'sentinel';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBaseOverride: 'main',
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      // Select a different option.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.originMainOption));
      await tester.pump();

      // Tap Cancel.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.cancelButton));
      await safePumpAndSettle(tester);

      // Dialog should be closed.
      expect(find.byKey(BaseSelectorDialogKeys.dialog), findsNothing);
      // Result should be null (unchanged).
      check(result).isNull();
    });

    testWidgets('submitting custom field via keyboard applies',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBaseOverride: 'main',
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Open'));
      await safePumpAndSettle(tester);

      // Tap custom field.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customField));
      await tester.pump();

      // Type a custom ref and submit via keyboard.
      await tester.enterText(
        find.byKey(BaseSelectorDialogKeys.customField),
        'release/v2',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await safePumpAndSettle(tester);

      check(result).equals('release/v2');
    });
  });
}
