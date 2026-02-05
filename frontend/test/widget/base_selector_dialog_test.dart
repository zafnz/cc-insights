import 'package:cc_insights_v2/widgets/base_selector_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  /// Pumps a [MaterialApp] that immediately shows the [BaseSelectorDialog]
  /// via [showDialog]. The dialog result is captured in [result].
  Future<String?> pumpDialog(
    WidgetTester tester, {
    String? currentBaseOverride,
  }) async {
    String? dialogResult;
    bool dialogReturned = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              // Show the dialog on first build via a post-frame callback.
              return ElevatedButton(
                onPressed: () async {
                  final raw = await showDialog<String?>(
                    context: context,
                    builder: (_) => BaseSelectorDialog(
                      currentBaseOverride: currentBaseOverride,
                    ),
                  );
                  // Decode the sentinel to null.
                  if (raw == '__project_default__') {
                    dialogResult = null;
                  } else {
                    dialogResult = raw;
                  }
                  dialogReturned = true;
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

    return dialogResult;
  }

  /// Waits for the dialog to close and returns the result.
  /// This is a helper to pump after tapping Apply/Cancel.
  Future<void> waitForDialogClose(WidgetTester tester) async {
    await safePumpAndSettle(tester);
  }

  group('BaseSelectorDialog', () {
    testWidgets('shows all options', (tester) async {
      await pumpDialog(tester);

      // Verify all option labels are displayed.
      expect(find.text('Use project default'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      expect(find.text('origin/main'), findsOneWidget);
      expect(find.text('Custom...'), findsOneWidget);

      // Verify title and description.
      expect(find.text('Change Base Ref'), findsOneWidget);

      // Verify action buttons.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('pre-selects "Use project default" when value is null',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: null);

      // The project default radio should be selected.
      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.projectDefaultOption),
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

      final radio = tester.widget<RadioListTile<dynamic>>(
        find.byKey(BaseSelectorDialogKeys.customOption),
      );
      check(radio.checked).equals(true);

      // Custom text field should be visible with the value.
      final textField = tester.widget<TextField>(
        find.byKey(BaseSelectorDialogKeys.customField),
      );
      check(textField.controller!.text).equals('develop');
    });

    testWidgets('selecting "main" and applying calls returns "main"',
        (tester) async {
      // Start with project default selected.
      await pumpDialog(tester, currentBaseOverride: null);

      // Tap the "main" radio.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.mainOption));
      await tester.pump();

      // Tap Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await waitForDialogClose(tester);

      // Dialog should be closed.
      expect(find.byKey(BaseSelectorDialogKeys.dialog), findsNothing);
    });

    testWidgets('selecting "Use project default" returns null',
        (tester) async {
      // Start with "main" selected.
      await pumpDialog(tester, currentBaseOverride: 'main');

      // Tap "Use project default".
      await tester.tap(
        find.byKey(BaseSelectorDialogKeys.projectDefaultOption),
      );
      await tester.pump();

      // Tap Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await waitForDialogClose(tester);

      // Dialog should be closed.
      expect(find.byKey(BaseSelectorDialogKeys.dialog), findsNothing);
    });

    testWidgets('selecting "origin/main" and applying closes dialog',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: null);

      await tester.tap(find.byKey(BaseSelectorDialogKeys.originMainOption));
      await tester.pump();

      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await waitForDialogClose(tester);

      expect(find.byKey(BaseSelectorDialogKeys.dialog), findsNothing);
    });

    testWidgets('custom field appears when Custom is selected',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: null);

      // Custom field should not be visible initially.
      expect(find.byKey(BaseSelectorDialogKeys.customField), findsNothing);

      // Tap "Custom...".
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customOption));
      await tester.pump();

      // Custom field should now be visible.
      expect(find.byKey(BaseSelectorDialogKeys.customField), findsOneWidget);
    });

    testWidgets('Apply is disabled when Custom is selected but field is empty',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: null);

      // Tap "Custom...".
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customOption));
      await tester.pump();

      // Apply should be disabled (empty custom field).
      final applyButton = tester.widget<FilledButton>(
        find.byKey(BaseSelectorDialogKeys.applyButton),
      );
      check(applyButton.onPressed).isNull();
    });

    testWidgets('Apply is enabled when Custom has text', (tester) async {
      await pumpDialog(tester, currentBaseOverride: null);

      // Tap "Custom...".
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customOption));
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
      await pumpDialog(tester, currentBaseOverride: null);

      // Tap "Custom...".
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customOption));
      await tester.pump();

      // Type a custom ref.
      await tester.enterText(
        find.byKey(BaseSelectorDialogKeys.customField),
        'origin/develop',
      );
      await tester.pump();

      // Tap Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await waitForDialogClose(tester);

      // Dialog should be closed.
      expect(find.byKey(BaseSelectorDialogKeys.dialog), findsNothing);
    });

    testWidgets('cancel closes dialog without applying', (tester) async {
      await pumpDialog(tester, currentBaseOverride: 'main');

      // Select a different option.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.originMainOption));
      await tester.pump();

      // Tap Cancel.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.cancelButton));
      await waitForDialogClose(tester);

      // Dialog should be closed.
      expect(find.byKey(BaseSelectorDialogKeys.dialog), findsNothing);
    });

    testWidgets('subtitle text is shown for project default option',
        (tester) async {
      await pumpDialog(tester);

      expect(
        find.text('Inherits from project settings'),
        findsOneWidget,
      );
    });

    testWidgets(
        'submitting custom field via keyboard applies when field is valid',
        (tester) async {
      await pumpDialog(tester, currentBaseOverride: null);

      // Tap "Custom...".
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customOption));
      await tester.pump();

      // Type a custom ref and submit via keyboard.
      await tester.enterText(
        find.byKey(BaseSelectorDialogKeys.customField),
        'release/v2',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitForDialogClose(tester);

      // Dialog should be closed.
      expect(find.byKey(BaseSelectorDialogKeys.dialog), findsNothing);
    });
  });

  group('BaseSelectorDialog with onChanged callback', () {
    testWidgets('selecting main calls onChanged with "main"',
        (tester) async {
      String? result;
      bool called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    final raw = await showDialog<String?>(
                      context: context,
                      builder: (_) => const BaseSelectorDialog(
                        currentBaseOverride: null,
                      ),
                    );
                    if (raw == '__project_default__') {
                      result = null;
                    } else {
                      result = raw;
                    }
                    called = true;
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

      // Select main.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.mainOption));
      await tester.pump();

      // Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await safePumpAndSettle(tester);

      check(called).equals(true);
      check(result).equals('main');
    });

    testWidgets('selecting project default calls onChanged with null',
        (tester) async {
      String? result = 'sentinel';
      bool called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    final raw = await showDialog<String?>(
                      context: context,
                      builder: (_) => const BaseSelectorDialog(
                        currentBaseOverride: 'main',
                      ),
                    );
                    if (raw == '__project_default__') {
                      result = null;
                    } else {
                      result = raw;
                    }
                    called = true;
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

      // Select project default.
      await tester.tap(
        find.byKey(BaseSelectorDialogKeys.projectDefaultOption),
      );
      await tester.pump();

      // Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await safePumpAndSettle(tester);

      check(called).equals(true);
      check(result).isNull();
    });

    testWidgets('custom value is returned correctly', (tester) async {
      String? result;
      bool called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    final raw = await showDialog<String?>(
                      context: context,
                      builder: (_) => const BaseSelectorDialog(
                        currentBaseOverride: null,
                      ),
                    );
                    if (raw == '__project_default__') {
                      result = null;
                    } else {
                      result = raw;
                    }
                    called = true;
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

      // Select custom.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.customOption));
      await tester.pump();

      // Enter custom value.
      await tester.enterText(
        find.byKey(BaseSelectorDialogKeys.customField),
        'develop',
      );
      await tester.pump();

      // Apply.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.applyButton));
      await safePumpAndSettle(tester);

      check(called).equals(true);
      check(result).equals('develop');
    });

    testWidgets('cancel does not trigger onChanged', (tester) async {
      bool called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    final raw = await showDialog<String?>(
                      context: context,
                      builder: (_) => const BaseSelectorDialog(
                        currentBaseOverride: 'main',
                      ),
                    );
                    // Cancel returns null (no sentinel), so raw is null.
                    if (raw != null) {
                      called = true;
                    }
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

      // Change selection then cancel.
      await tester.tap(find.byKey(BaseSelectorDialogKeys.originMainOption));
      await tester.pump();

      await tester.tap(find.byKey(BaseSelectorDialogKeys.cancelButton));
      await safePumpAndSettle(tester);

      check(called).equals(false);
    });
  });
}
