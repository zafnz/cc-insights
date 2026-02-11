import 'package:cc_insights_v2/widgets/editable_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  group('EditableLabel', () {
    late String? submittedValue;
    late int tapCount;

    setUp(() {
      submittedValue = null;
      tapCount = 0;
    });

    Widget buildTestWidget({
      String text = 'Test Label',
      TextStyle? style,
      String? Function(String)? validator,
      VoidCallback? onTap,
    }) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: EditableLabel(
                text: text,
                style: style,
                onTap: onTap ?? () => tapCount++,
                onSubmit: (value) => submittedValue = value,
                validator: validator,
              ),
            ),
          ),
        ),
      );
    }

    /// Helper to perform a double-click on a finder.
    /// Two taps within 300ms threshold to enter edit mode.
    Future<void> doubleClick(WidgetTester tester, Finder finder) async {
      // First tap (triggers onTap callback)
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 50));
      // Second tap within 300ms (enters edit mode)
      await tester.tap(finder);
      await tester.pump();
    }

    /// Helper to perform a single tap on a finder.
    Future<void> singleTap(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pump();
    }

    group('display mode', () {
      testWidgets('renders text', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.text('Test Label'), findsOneWidget);
      });

      testWidgets('single tap triggers onTap callback', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await singleTap(tester, find.text('Test Label'));

        // onTap was called
        expect(tapCount, 1);
        // Should NOT enter edit mode
        expect(find.byKey(EditableLabelKeys.textField), findsNothing);
      });

      testWidgets('single tap does not enter edit mode', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await singleTap(tester, find.text('Test Label'));

        // Wait beyond double-click threshold
        await tester.pump(const Duration(milliseconds: 400));

        // Should still be in display mode
        expect(find.text('Test Label'), findsOneWidget);
        expect(find.byKey(EditableLabelKeys.textField), findsNothing);
      });

      testWidgets('applies provided text style', (tester) async {
        const style = TextStyle(fontSize: 20, color: Colors.red);
        await tester.pumpWidget(buildTestWidget(style: style));

        final textWidget = tester.widget<Text>(
          find.text('Test Label'),
        );

        expect(textWidget.style?.fontSize, 20);
        expect(textWidget.style?.color, Colors.red);
      });

      testWidgets('does not show text field in display mode', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.byKey(EditableLabelKeys.textField), findsNothing);
      });
    });

    group('edit mode', () {
      testWidgets('double-click (within 300ms) enters edit mode',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await doubleClick(tester, find.text('Test Label'));

        // TextField should be visible, Text widget should not
        expect(find.byKey(EditableLabelKeys.textField), findsOneWidget);
        expect(find.byType(Text), findsNothing);
      });

      testWidgets('double-click calls onTap on first tap only', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await doubleClick(tester, find.text('Test Label'));

        // onTap was called once (first tap only, second tap enters edit mode)
        expect(tapCount, 1);
      });

      testWidgets('text field has focus after entering edit mode',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await doubleClick(tester, find.text('Test Label'));

        // Let post-frame callback run
        await tester.pump();

        final textField = tester.widget<TextField>(
          find.byKey(EditableLabelKeys.textField),
        );
        expect(textField.focusNode?.hasFocus, isTrue);
      });

      testWidgets('text is selected after entering edit mode', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Hello'));

        await doubleClick(tester, find.text('Hello'));
        await tester.pump(); // Post-frame callback

        final textField = tester.widget<TextField>(
          find.byKey(EditableLabelKeys.textField),
        );
        final selection = textField.controller?.selection;
        expect(selection?.baseOffset, 0);
        expect(selection?.extentOffset, 5);
      });

      testWidgets('pressing Enter submits and exits edit mode',
          (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Original'));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Type new text
        await tester.enterText(
            find.byKey(EditableLabelKeys.textField), 'New Name');
        await tester.pump();

        // Press Enter
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        // onSubmit was called with new name
        expect(submittedValue, 'New Name');
        // Exit edit mode - TextField gone, Text widget shows original
        // (parent would rebuild with new text in real usage)
        expect(find.byKey(EditableLabelKeys.textField), findsNothing);
        expect(find.byType(Text), findsOneWidget);
      });

      testWidgets('pressing Escape cancels and exits edit mode',
          (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Original'));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Type new text
        await tester.enterText(
            find.byKey(EditableLabelKeys.textField), 'New Name');
        await tester.pump();

        // Press Escape
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        // Should NOT submit
        expect(submittedValue, isNull);
        // Should exit edit mode and show original text
        expect(find.text('Original'), findsOneWidget);
      });

      testWidgets('does not submit if text unchanged', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Original'));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Press Enter without changing text
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        // Should NOT call onSubmit since text didn't change
        expect(submittedValue, isNull);
      });

      testWidgets('rejects empty text and restores original', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Original'));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Clear the text
        await tester.enterText(find.byKey(EditableLabelKeys.textField), '');
        await tester.pump();

        // Press Enter
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        // Should NOT submit empty text
        expect(submittedValue, isNull);
        // Should show original text
        expect(find.text('Original'), findsOneWidget);
      });

      testWidgets('trims whitespace before submitting', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Original'));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Enter text with whitespace
        await tester.enterText(
            find.byKey(EditableLabelKeys.textField), '  New Name  ');
        await tester.pump();

        // Press Enter
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(submittedValue, 'New Name');
      });

      testWidgets('rejects whitespace-only text', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Original'));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Enter only whitespace
        await tester.enterText(
            find.byKey(EditableLabelKeys.textField), '   ');
        await tester.pump();

        // Press Enter
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        // Should NOT submit whitespace-only text
        expect(submittedValue, isNull);
        expect(find.text('Original'), findsOneWidget);
      });
    });

    group('validation', () {
      testWidgets('rejects text that fails validation', (tester) async {
        await tester.pumpWidget(buildTestWidget(
          text: 'Original',
          validator: (value) =>
              value.contains('bad') ? 'Contains bad word' : null,
        ));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Enter invalid text
        await tester.enterText(
            find.byKey(EditableLabelKeys.textField), 'bad name');
        await tester.pump();

        // Press Enter
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        // Should NOT submit and should restore original
        expect(submittedValue, isNull);
        expect(find.text('Original'), findsOneWidget);
      });

      testWidgets('accepts text that passes validation', (tester) async {
        await tester.pumpWidget(buildTestWidget(
          text: 'Original',
          validator: (value) =>
              value.contains('bad') ? 'Contains bad word' : null,
        ));

        await doubleClick(tester, find.text('Original'));
        await tester.pump();

        // Enter valid text
        await tester.enterText(
            find.byKey(EditableLabelKeys.textField), 'good name');
        await tester.pump();

        // Press Enter
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(submittedValue, 'good name');
      });
    });

    group('external updates', () {
      testWidgets('updates display when text prop changes while not editing',
          (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'First'));

        expect(find.text('First'), findsOneWidget);

        // Rebuild with new text
        await tester.pumpWidget(buildTestWidget(text: 'Second'));

        expect(find.text('Second'), findsOneWidget);
      });
    });
  });
}
