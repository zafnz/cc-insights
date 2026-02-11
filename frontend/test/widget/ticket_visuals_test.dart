import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checks/checks.dart';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/widgets/ticket_visuals.dart';

void main() {
  group('TicketStatusVisuals', () {
    test('icon returns correct IconData for each status', () {
      check(TicketStatusVisuals.icon(TicketStatus.draft))
          .equals(Icons.edit_note);
      check(TicketStatusVisuals.icon(TicketStatus.ready))
          .equals(Icons.radio_button_unchecked);
      check(TicketStatusVisuals.icon(TicketStatus.active))
          .equals(Icons.play_circle_outline);
      check(TicketStatusVisuals.icon(TicketStatus.blocked))
          .equals(Icons.block);
      check(TicketStatusVisuals.icon(TicketStatus.needsInput))
          .equals(Icons.help_outline);
      check(TicketStatusVisuals.icon(TicketStatus.inReview))
          .equals(Icons.rate_review_outlined);
      check(TicketStatusVisuals.icon(TicketStatus.completed))
          .equals(Icons.check_circle_outline);
      check(TicketStatusVisuals.icon(TicketStatus.cancelled))
          .equals(Icons.cancel_outlined);
    });

    test('all statuses have distinct icons', () {
      final icons = TicketStatus.values
          .map((s) => TicketStatusVisuals.icon(s))
          .toSet();
      check(icons.length).equals(TicketStatus.values.length);
    });

    test('color returns non-null colors for all statuses', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
      for (final status in TicketStatus.values) {
        final color = TicketStatusVisuals.color(status, colorScheme);
        check(color).isNotNull();
      }
    });

    test('color returns expected colors for specific statuses', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);

      // Green for completed
      check(TicketStatusVisuals.color(TicketStatus.completed, colorScheme))
          .equals(const Color(0xFF4CAF50));

      // Blue for active
      check(TicketStatusVisuals.color(TicketStatus.active, colorScheme))
          .equals(const Color(0xFF42A5F5));

      // Grey for ready/draft
      check(TicketStatusVisuals.color(TicketStatus.ready, colorScheme))
          .equals(const Color(0xFF757575));
      check(TicketStatusVisuals.color(TicketStatus.draft, colorScheme))
          .equals(const Color(0xFF9E9E9E));

      // Orange for blocked/needsInput
      check(TicketStatusVisuals.color(TicketStatus.blocked, colorScheme))
          .equals(const Color(0xFFFFA726));
      check(TicketStatusVisuals.color(TicketStatus.needsInput, colorScheme))
          .equals(const Color(0xFFFFA726));

      // Purple for review
      check(TicketStatusVisuals.color(TicketStatus.inReview, colorScheme))
          .equals(const Color(0xFFCE93D8));

      // Red for cancelled
      check(TicketStatusVisuals.color(TicketStatus.cancelled, colorScheme))
          .equals(const Color(0xFFEF5350));
    });
  });

  group('TicketKindVisuals', () {
    test('icon returns correct IconData for each kind', () {
      check(TicketKindVisuals.icon(TicketKind.feature))
          .equals(Icons.star_outline);
      check(TicketKindVisuals.icon(TicketKind.bugfix))
          .equals(Icons.bug_report_outlined);
      check(TicketKindVisuals.icon(TicketKind.research))
          .equals(Icons.science_outlined);
      check(TicketKindVisuals.icon(TicketKind.split))
          .equals(Icons.call_split);
      check(TicketKindVisuals.icon(TicketKind.question))
          .equals(Icons.help_outline);
      check(TicketKindVisuals.icon(TicketKind.test))
          .equals(Icons.science);
      check(TicketKindVisuals.icon(TicketKind.docs))
          .equals(Icons.description_outlined);
      check(TicketKindVisuals.icon(TicketKind.chore))
          .equals(Icons.handyman_outlined);
    });

    test('color returns non-null colors for all kinds', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
      for (final kind in TicketKind.values) {
        final color = TicketKindVisuals.color(kind, colorScheme);
        check(color).isNotNull();
      }
    });
  });

  group('TicketPriorityVisuals', () {
    test('icon returns correct IconData for each priority', () {
      check(TicketPriorityVisuals.icon(TicketPriority.low))
          .equals(Icons.keyboard_arrow_down);
      check(TicketPriorityVisuals.icon(TicketPriority.medium))
          .equals(Icons.signal_cellular_alt);
      check(TicketPriorityVisuals.icon(TicketPriority.high))
          .equals(Icons.keyboard_arrow_up);
      check(TicketPriorityVisuals.icon(TicketPriority.critical))
          .equals(Icons.priority_high);
    });

    test('color returns non-null colors for all priorities', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
      for (final priority in TicketPriority.values) {
        final color = TicketPriorityVisuals.color(priority, colorScheme);
        check(color).isNotNull();
      }
    });
  });

  group('TicketEffortVisuals', () {
    test('color returns non-null colors for all efforts', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
      for (final effort in TicketEffort.values) {
        final color = TicketEffortVisuals.color(effort, colorScheme);
        check(color).isNotNull();
      }
    });

    test('color returns expected colors for each effort level', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);

      // Green for small
      check(TicketEffortVisuals.color(TicketEffort.small, colorScheme))
          .equals(const Color(0xFF4CAF50));

      // Orange for medium
      check(TicketEffortVisuals.color(TicketEffort.medium, colorScheme))
          .equals(const Color(0xFFFFA726));

      // Red for large
      check(TicketEffortVisuals.color(TicketEffort.large, colorScheme))
          .equals(const Color(0xFFEF5350));
    });

    test('shortLabel returns correct labels', () {
      check(TicketEffortVisuals.shortLabel(TicketEffort.small)).equals('S');
      check(TicketEffortVisuals.shortLabel(TicketEffort.medium)).equals('M');
      check(TicketEffortVisuals.shortLabel(TicketEffort.large)).equals('L');
    });
  });

  group('TicketStatusIcon widget', () {
    testWidgets('renders for each status with correct icon', (tester) async {
      for (final status in TicketStatus.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TicketStatusIcon(status: status),
            ),
          ),
        );

        final iconFinder = find.byIcon(TicketStatusVisuals.icon(status));
        check(iconFinder.evaluate()).isNotEmpty();
      }
    });

    testWidgets('respects custom size parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TicketStatusIcon(
              status: TicketStatus.active,
              size: 24.0,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      check(icon.size).equals(24.0);
    });

    testWidgets('uses default size when not specified', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TicketStatusIcon(status: TicketStatus.active),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      check(icon.size).equals(16.0);
    });
  });

  group('MetadataPill widget', () {
    testWidgets('renders with icon and label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MetadataPill(
              icon: Icons.star,
              label: 'Feature',
              backgroundColor: Color(0xFFBA68C8),
              foregroundColor: Color(0xFFFFFFFF),
            ),
          ),
        ),
      );

      check(find.byIcon(Icons.star).evaluate()).isNotEmpty();
      check(find.text('Feature').evaluate()).isNotEmpty();
    });
  });

  group('EffortBadge widget', () {
    testWidgets('renders for each effort level', (tester) async {
      for (final effort in TicketEffort.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EffortBadge(effort: effort),
            ),
          ),
        );

        final expectedLabel = TicketEffortVisuals.shortLabel(effort);
        check(find.text(expectedLabel).evaluate()).isNotEmpty();
      }
    });

    testWidgets('displays S for small effort', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EffortBadge(effort: TicketEffort.small),
          ),
        ),
      );

      check(find.text('S').evaluate()).isNotEmpty();
    });

    testWidgets('displays M for medium effort', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EffortBadge(effort: TicketEffort.medium),
          ),
        ),
      );

      check(find.text('M').evaluate()).isNotEmpty();
    });

    testWidgets('displays L for large effort', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EffortBadge(effort: TicketEffort.large),
          ),
        ),
      );

      check(find.text('L').evaluate()).isNotEmpty();
    });
  });

  group('KindBadge widget', () {
    testWidgets('renders for each kind', (tester) async {
      for (final kind in TicketKind.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KindBadge(kind: kind),
            ),
          ),
        );

        final expectedLabel = kind.label.toLowerCase();
        check(find.text(expectedLabel).evaluate()).isNotEmpty();
      }
    });

    testWidgets('displays lowercase kind label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KindBadge(kind: TicketKind.feature),
          ),
        ),
      );

      // Should be lowercase "feature", not "Feature"
      check(find.text('feature').evaluate()).isNotEmpty();
      check(find.text('Feature').evaluate()).isEmpty();
    });
  });
}
