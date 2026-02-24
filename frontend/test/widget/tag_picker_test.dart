import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/widgets/tag_colors.dart';
import 'package:cc_insights_v2/widgets/tag_picker.dart';

void main() {
  final knownTags = [
    TagDefinition(name: 'bug'),
    TagDefinition(name: 'feature'),
    TagDefinition(name: 'docs'),
    TagDefinition(name: 'testing'),
  ];

  Widget wrap({
    Set<String> currentTags = const {},
    List<TagDefinition>? allKnownTags,
    void Function(String)? onAddTag,
    void Function(String)? onRemoveTag,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TagPicker(
          currentTags: currentTags,
          allKnownTags: allKnownTags ?? knownTags,
          onAddTag: onAddTag ?? (_) {},
          onRemoveTag: onRemoveTag ?? (_) {},
        ),
      ),
    );
  }

  group('TagPicker', () {
    testWidgets('renders text input', (tester) async {
      await tester.pumpWidget(wrap());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows all known tags initially', (tester) async {
      await tester.pumpWidget(wrap());
      for (final tag in knownTags) {
        expect(find.text(tag.name), findsOneWidget);
      }
    });

    testWidgets('typing filters suggestions case-insensitively',
        (tester) async {
      await tester.pumpWidget(wrap());

      await tester.enterText(find.byType(TextField), 'BUG');
      await tester.pump();

      expect(find.text('bug'), findsOneWidget);
      expect(find.text('feature'), findsNothing);
      expect(find.text('docs'), findsNothing);
      expect(find.text('testing'), findsNothing);
    });

    testWidgets('typing partial text filters matching suggestions',
        (tester) async {
      await tester.pumpWidget(wrap());

      await tester.enterText(find.byType(TextField), 'tur');
      await tester.pump();

      // "tur" matches "feature" only
      expect(find.text('feature'), findsOneWidget);
      expect(find.text('bug'), findsNothing);
      expect(find.text('docs'), findsNothing);
      expect(find.text('testing'), findsNothing);
    });

    testWidgets('clicking suggestion calls onAddTag', (tester) async {
      String? addedTag;
      await tester.pumpWidget(wrap(
        onAddTag: (tag) => addedTag = tag,
      ));

      await tester.tap(find.text('feature'));
      expect(addedTag, 'feature');
    });

    testWidgets('current tags show checkmark', (tester) async {
      await tester.pumpWidget(wrap(
        currentTags: {'bug', 'docs'},
      ));

      expect(find.byIcon(Icons.check), findsNWidgets(2));
    });

    testWidgets('clicking checked tag calls onRemoveTag', (tester) async {
      String? removedTag;
      await tester.pumpWidget(wrap(
        currentTags: {'bug'},
        onRemoveTag: (tag) => removedTag = tag,
      ));

      await tester.tap(find.text('bug'));
      expect(removedTag, 'bug');
    });

    testWidgets('pressing Enter submits custom tag as lowercase',
        (tester) async {
      String? addedTag;
      await tester.pumpWidget(wrap(
        onAddTag: (tag) => addedTag = tag,
      ));

      await tester.enterText(find.byType(TextField), 'MyCustomTag');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(addedTag, 'mycustomtag');
    });

    testWidgets('Enter with empty text does not call onAddTag',
        (tester) async {
      var called = false;
      await tester.pumpWidget(wrap(
        onAddTag: (_) => called = true,
      ));

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(called, isFalse);
    });

    testWidgets('suggestion shows coloured dot', (tester) async {
      await tester.pumpWidget(wrap());

      // Find the coloured dot containers (circle-shaped, 10x10)
      final dotFinder = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        return decoration.shape == BoxShape.circle && decoration.color != null;
      });

      expect(dotFinder, findsNWidgets(knownTags.length));
    });

    testWidgets('coloured dot uses tagColor for known tag', (tester) async {
      await tester.pumpWidget(wrap(
        allKnownTags: [TagDefinition(name: 'bug')],
      ));

      final dotFinder = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        return decoration.shape == BoxShape.circle;
      });

      final container = tester.widget<Container>(dotFinder);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, tagColor('bug'));
    });

    testWidgets('coloured dot uses custom hex colour from TagDefinition',
        (tester) async {
      await tester.pumpWidget(wrap(
        allKnownTags: [TagDefinition(name: 'custom', color: '#00ff00')],
      ));

      final dotFinder = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        return decoration.shape == BoxShape.circle;
      });

      final container = tester.widget<Container>(dotFinder);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, tagColor('custom', customHex: '#00ff00'));
    });

    testWidgets('input clears after submitting custom tag', (tester) async {
      await tester.pumpWidget(wrap());

      await tester.enterText(find.byType(TextField), 'newtag');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);
    });

    testWidgets('filter resets after submitting custom tag', (tester) async {
      await tester.pumpWidget(wrap());

      // Type to filter
      await tester.enterText(find.byType(TextField), 'bug');
      await tester.pump();
      expect(find.text('feature'), findsNothing);

      // Submit
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // All tags visible again
      for (final tag in knownTags) {
        expect(find.text(tag.name), findsOneWidget);
      }
    });
  });
}
