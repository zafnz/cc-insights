import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/widgets/tag_colors.dart';
import 'package:cc_insights_v2/widgets/ticket_tag_chip.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('TicketTagChip', () {
    testWidgets('renders tag name', (tester) async {
      await tester.pumpWidget(wrap(const TicketTagChip(tag: 'bug')));
      expect(find.text('bug'), findsOneWidget);
    });

    testWidgets('uses correct colour from tagColor()', (tester) async {
      await tester.pumpWidget(wrap(const TicketTagChip(tag: 'feature')));

      final text = tester.widget<Text>(find.text('feature'));
      final style = text.style!;
      expect(style.color, tagColor('feature'));
    });

    testWidgets('applies background with low opacity', (tester) async {
      await tester.pumpWidget(wrap(const TicketTagChip(tag: 'bug')));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      final expected = tagColor('bug').withValues(alpha: 0.15);
      expect(decoration.color, expected);
    });

    testWidgets('applies pill-shaped border radius', (tester) async {
      await tester.pumpWidget(wrap(const TicketTagChip(tag: 'bug')));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(10));
    });

    testWidgets('respects custom fontSize', (tester) async {
      await tester.pumpWidget(wrap(const TicketTagChip(tag: 'docs', fontSize: 9)));

      final text = tester.widget<Text>(find.text('docs'));
      expect(text.style!.fontSize, 9);
    });

    testWidgets('does not show close icon when removable is false', (tester) async {
      await tester.pumpWidget(wrap(const TicketTagChip(tag: 'bug')));
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows close icon when removable is true', (tester) async {
      await tester.pumpWidget(wrap(
        TicketTagChip(tag: 'bug', removable: true, onRemove: () {}),
      ));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('fires onRemove callback', (tester) async {
      var removed = false;
      await tester.pumpWidget(wrap(
        TicketTagChip(tag: 'bug', removable: true, onRemove: () => removed = true),
      ));

      await tester.tap(find.byIcon(Icons.close));
      expect(removed, isTrue);
    });

    testWidgets('fires onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        TicketTagChip(tag: 'feature', onTap: () => tapped = true),
      ));

      await tester.tap(find.text('feature'));
      expect(tapped, isTrue);
    });

    testWidgets('works with hash-fallback tag colour', (tester) async {
      const tag = 'my-custom-tag';
      await tester.pumpWidget(wrap(const TicketTagChip(tag: tag)));

      final text = tester.widget<Text>(find.text(tag));
      expect(text.style!.color, tagColor(tag));
    });
  });
}
