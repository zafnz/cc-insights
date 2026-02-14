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
    String? currentBase,
    String? branchName,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await showDialog<BaseSelectorResult?>(
                    context: context,
                    builder: (_) => BaseSelectorDialog(
                      currentBase: currentBase,
                      branchName: branchName,
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

    testWidgets('shows rebase checkbox checked by default', (tester) async {
      await pumpDialog(tester);

      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(BaseSelectorDialogKeys.rebaseCheckbox),
      );
      check(checkbox.value).equals(true);
    });

    testWidgets('rebase checkbox label and info icon are shown',
        (tester) async {
      await pumpDialog(tester);

      expect(find.text('Rebase onto new base'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('pre-selects "main" when value is null', (tester) async {
      await pumpDialog(tester, currentBase: null);

      // The main radio should be selected.
      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.mainOption),
      );
      // ignore: deprecated_member_use
      check(radio.value).equals(radio.groupValue);
    });

    testWidgets('pre-selects "main" when current value is main',
        (tester) async {
      await pumpDialog(tester, currentBase: 'main');

      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.mainOption),
      );
      // ignore: deprecated_member_use
      check(radio.value).equals(radio.groupValue);
    });

    testWidgets('pre-selects "origin/main" when current value is origin/main',
        (tester) async {
      await pumpDialog(tester, currentBase: 'origin/main');

      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.originMainOption),
      );
      // ignore: deprecated_member_use
      check(radio.value).equals(radio.groupValue);
    });

    testWidgets('pre-selects "Custom" with text for non-standard value',
        (tester) async {
      await pumpDialog(tester, currentBase: 'develop');

      // Custom radio should be selected.
      final radio = tester.widget<Radio<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.customOption),
      );
      // ignore: deprecated_member_use
      check(radio.groupValue).equals(radio.value);

      // Custom text field should have the value.
      final textField = tester.widget<TextField>(
        find.byKey(BaseSelectorDialogKeys.customField),
      );
      check(textField.controller!.text).equals('develop');
    });

    testWidgets('selecting "main" and applying returns result with rebase true',
        (tester) async {
      BaseSelectorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBase: 'origin/main',
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

      check(result).isNotNull();
      check(result!.base).equals('main');
      check(result!.rebase).equals(true);
    });

    testWidgets(
        'selecting "origin/main" and applying returns result with rebase true',
        (tester) async {
      BaseSelectorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBase: 'main',
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

      check(result).isNotNull();
      check(result!.base).equals('origin/main');
      check(result!.rebase).equals(true);
    });

    testWidgets('unchecking rebase returns result with rebase false',
        (tester) async {
      BaseSelectorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBase: 'main',
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

      // Uncheck the rebase checkbox.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.rebaseCheckbox));
      await tester.pump();

      // Select origin/main.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.originMainOption));
      await tester.pump();

      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await safePumpAndSettle(tester);

      check(result).isNotNull();
      check(result!.base).equals('origin/main');
      check(result!.rebase).equals(false);
    });

    testWidgets('tapping custom field selects custom option', (tester) async {
      await pumpDialog(tester, currentBase: 'main');

      // Verify main is selected initially.
      final mainRadio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.mainOption),
      );
      // ignore: deprecated_member_use
      check(mainRadio.value).equals(mainRadio.groupValue);

      // Tap the custom text field.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customField));
      await tester.pump();

      // Custom radio should now be selected.
      final customRadio = tester.widget<Radio<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.customOption),
      );
      // ignore: deprecated_member_use
      check(customRadio.groupValue).equals(customRadio.value);
    });

    testWidgets('Apply is disabled when Custom is selected but field is empty',
        (tester) async {
      await pumpDialog(tester, currentBase: 'main');

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
      await pumpDialog(tester, currentBase: 'main');

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
      BaseSelectorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBase: 'main',
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

      check(result).isNotNull();
      check(result!.base).equals('origin/develop');
      check(result!.rebase).equals(true);
    });

    testWidgets('cancel closes dialog and returns null', (tester) async {
      BaseSelectorResult? result = const BaseSelectorResult(
        base: 'sentinel',
        rebase: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBase: 'main',
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
      BaseSelectorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showBaseSelectorDialog(
                      context,
                      currentBase: 'main',
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

      check(result).isNotNull();
      check(result!.base).equals('release/v2');
      check(result!.rebase).equals(true);
    });

    testWidgets('branchName appears in tooltip text', (tester) async {
      await pumpDialog(tester, branchName: 'feat/my-branch');

      // The info icon tooltip should contain the branch name.
      final tooltipFinder = find.byType(Tooltip);
      // Find the tooltip that contains the branch name.
      bool foundBranchTooltip = false;
      for (final element in tooltipFinder.evaluate()) {
        final tooltip = element.widget as Tooltip;
        if (tooltip.message != null &&
            tooltip.message!.contains('feat/my-branch')) {
          foundBranchTooltip = true;
          break;
        }
      }
      check(foundBranchTooltip).equals(true);
    });
  });
}
