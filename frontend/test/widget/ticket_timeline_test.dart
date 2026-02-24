import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/widgets/ticket_activity_event.dart';
import 'package:cc_insights_v2/widgets/ticket_comment_block.dart';
import 'package:cc_insights_v2/widgets/ticket_comment_input.dart';
import 'package:cc_insights_v2/widgets/ticket_tag_chip.dart';
import 'package:cc_insights_v2/widgets/ticket_timeline_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to wrap a widget in a MaterialApp with scrollable body.
Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

/// Creates an [ActivityEvent] with defaults.
ActivityEvent _event({
  String id = '1',
  ActivityEventType type = ActivityEventType.tagAdded,
  String actor = 'zaf',
  AuthorType actorType = AuthorType.user,
  required DateTime timestamp,
  Map<String, dynamic> data = const {},
}) {
  return ActivityEvent(
    id: id,
    type: type,
    actor: actor,
    actorType: actorType,
    timestamp: timestamp,
    data: data,
  );
}

/// Creates a minimal [TicketData] for tests.
TicketData _ticket({
  bool isOpen = true,
  List<TicketComment> comments = const [],
  List<ActivityEvent> activityLog = const [],
}) {
  final now = DateTime(2024, 6, 15, 12, 0);
  return TicketData(
    id: 1,
    title: 'Test ticket',
    body: 'Ticket body content',
    author: 'zaf',
    isOpen: isOpen,
    comments: comments,
    activityLog: activityLog,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUp(() {
    RuntimeConfig.resetForTesting();
  });

  // =========================================================================
  // Activity event icon tests
  // =========================================================================
  group('TicketActivityEvent icons', () {
    final ts = DateTime(2024, 6, 15, 14, 30);

    testWidgets('tagAdded shows sell icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.tagAdded, timestamp: ts, data: {'tag': 'bug'}),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.sell), findsOneWidget);
    });

    testWidgets('tagRemoved shows sell icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.tagRemoved, timestamp: ts, data: {'tag': 'wip'}),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.sell), findsOneWidget);
    });

    testWidgets('worktreeLinked shows account_tree icon', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.worktreeLinked,
          timestamp: ts,
          data: {'branch': 'feat-x'},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.account_tree), findsOneWidget);
    });

    testWidgets('worktreeUnlinked shows account_tree icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.worktreeUnlinked, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.account_tree), findsOneWidget);
    });

    testWidgets('chatLinked shows chat_bubble_outline icon', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.chatLinked,
          timestamp: ts,
          data: {'chatName': 'my-chat'},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('chatUnlinked shows chat_bubble_outline icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.chatUnlinked, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('closed shows check_circle icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.closed, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('reopened shows radio_button_checked icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.reopened, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    testWidgets('dependencyAdded shows link icon', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.dependencyAdded,
          timestamp: ts,
          data: {'ticketId': 42},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('dependencyRemoved shows link icon', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.dependencyRemoved,
          timestamp: ts,
          data: {'ticketId': 7},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('titleEdited shows edit icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.titleEdited, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('bodyEdited shows edit icon', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.bodyEdited, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });

  // =========================================================================
  // Tag event chip rendering
  // =========================================================================
  group('TicketActivityEvent tag events', () {
    final ts = DateTime(2024, 6, 15, 14, 30);

    testWidgets('tagAdded shows TicketTagChip with tag name', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.tagAdded, timestamp: ts, data: {'tag': 'bug'}),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byType(TicketTagChip), findsOneWidget);
      expect(find.text('bug'), findsOneWidget);
    });

    testWidgets('tagRemoved shows TicketTagChip with tag name', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.tagRemoved, timestamp: ts, data: {'tag': 'wip'}),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(find.byType(TicketTagChip), findsOneWidget);
      expect(find.text('wip'), findsOneWidget);
    });
  });

  // =========================================================================
  // Actor and timestamp display
  // =========================================================================
  group('TicketActivityEvent actor and timestamp', () {
    testWidgets('displays actor name', (tester) async {
      final ce = CoalescedEvent([
        _event(
          actor: 'alice',
          type: ActivityEventType.closed,
          timestamp: DateTime(2024, 6, 15, 14, 30),
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      // Actor name appears in the Text.rich spans.
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('alice'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays timestamp for different year', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.closed,
          timestamp: DateTime(2024, 6, 22, 14, 30),
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      // Different year → "d MMM yyyy" format.
      expect(find.text('22 Jun 2024'), findsOneWidget);
    });

    testWidgets('shows inline agent badge for agent actors', (tester) async {
      final ce = CoalescedEvent([
        _event(
          actor: 'agent auth-bot',
          actorType: AuthorType.agent,
          type: ActivityEventType.tagAdded,
          timestamp: DateTime(2024, 6, 15),
          data: {'tag': 'bug'},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      // The inline agent badge renders 'agent' text.
      expect(find.text('agent'), findsOneWidget);
    });

    testWidgets('does not show agent badge for user actors', (tester) async {
      final ce = CoalescedEvent([
        _event(
          actor: 'zaf',
          actorType: AuthorType.user,
          type: ActivityEventType.closed,
          timestamp: DateTime(2024, 6, 15),
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      // No 'agent' badge text for user actors.
      expect(find.text('agent'), findsNothing);
    });
  });

  // =========================================================================
  // Event description text
  // =========================================================================
  group('TicketActivityEvent description text', () {
    final ts = DateTime(2024, 6, 15);

    testWidgets('closed event shows "closed this"', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.closed, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('closed this'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('reopened event shows "reopened this"', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.reopened, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('reopened this'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('titleEdited shows "edited the title"', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.titleEdited, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('edited the title'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('bodyEdited shows "edited the body"', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.bodyEdited, timestamp: ts),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('edited the body'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('worktreeLinked shows branch name', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.worktreeLinked,
          timestamp: ts,
          data: {'branch': 'feat-dark-mode'},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('linked worktree') &&
              w.text.toPlainText().contains('feat-dark-mode'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('chatLinked shows chat name', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.chatLinked,
          timestamp: ts,
          data: {'chatName': 'debugging session'},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('linked chat') &&
              w.text.toPlainText().contains('debugging session'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('dependencyAdded shows ticket ID', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.dependencyAdded,
          timestamp: ts,
          data: {'ticketId': 42},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('added dependency') &&
              w.text.toPlainText().contains('#42'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('dependencyRemoved shows ticket ID', (tester) async {
      final ce = CoalescedEvent([
        _event(
          type: ActivityEventType.dependencyRemoved,
          timestamp: ts,
          data: {'ticketId': 7},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('removed dependency') &&
              w.text.toPlainText().contains('#7'),
        ),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // Coalesced event rendering
  // =========================================================================
  group('TicketActivityEvent coalesced events', () {
    final ts = DateTime(2024, 6, 15);

    testWidgets('coalesced event renders descriptions for all events',
        (tester) async {
      final ce = CoalescedEvent([
        _event(
          id: '1',
          type: ActivityEventType.tagAdded,
          timestamp: ts,
          data: {'tag': 'bug'},
        ),
        _event(
          id: '2',
          type: ActivityEventType.tagAdded,
          timestamp: ts.add(const Duration(seconds: 2)),
          data: {'tag': 'urgent'},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      // Both tags should be rendered as chips.
      expect(find.byType(TicketTagChip), findsNWidgets(2));
      expect(find.text('bug'), findsOneWidget);
      expect(find.text('urgent'), findsOneWidget);
    });

    testWidgets('coalesced event shows single actor name', (tester) async {
      final ce = CoalescedEvent([
        _event(
          id: '1',
          actor: 'zaf',
          type: ActivityEventType.tagAdded,
          timestamp: ts,
          data: {'tag': 'a'},
        ),
        _event(
          id: '2',
          actor: 'zaf',
          type: ActivityEventType.tagRemoved,
          timestamp: ts.add(const Duration(seconds: 1)),
          data: {'tag': 'b'},
        ),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      // Actor should appear once in the description text (not duplicated).
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final actorOccurrences = richTexts
          .where((rt) => rt.text.toPlainText().contains('zaf'))
          .length;
      expect(actorOccurrences, 1);
    });
  });

  // =========================================================================
  // Timeline dot presence
  // =========================================================================
  group('TicketActivityEvent timeline dot', () {
    testWidgets('timeline dot is a circle', (tester) async {
      final ce = CoalescedEvent([
        _event(type: ActivityEventType.closed, timestamp: DateTime(2024, 6, 15)),
      ]);
      await tester.pumpWidget(_wrap(TicketActivityEvent(coalescedEvent: ce)));

      // The timeline dot is a 24x24 Container with BoxShape.circle.
      final dot = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 24 &&
              (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
        ),
      );
      expect(dot, isNotNull);
    });
  });

  // =========================================================================
  // Timeline composition (body → events → comments → input)
  // =========================================================================
  group('Timeline composition', () {
    testWidgets('body block renders before activity events', (tester) async {
      final ticket = _ticket(
        activityLog: [
          _event(
            type: ActivityEventType.tagAdded,
            timestamp: DateTime(2024, 6, 15, 13, 0),
            data: {'tag': 'feature'},
          ),
        ],
      );

      // Build a timeline layout: body comment → events → input.
      await tester.pumpWidget(_wrap(Column(
        children: [
          TicketCommentBlock(
            author: ticket.author,
            authorType: AuthorType.user,
            timestamp: ticket.createdAt,
            markdownContent: ticket.body,
          ),
          for (final ce in coalesceEvents(ticket.activityLog))
            TicketActivityEvent(coalescedEvent: ce),
          TicketCommentInput(
            ticket: ticket,
            onComment: (_) {},
            onToggleStatus: () {},
          ),
        ],
      )));

      // Verify body block, activity event, and input all render.
      expect(find.byType(TicketCommentBlock), findsOneWidget);
      expect(find.byType(TicketActivityEvent), findsOneWidget);
      expect(find.byType(TicketCommentInput), findsOneWidget);
    });

    testWidgets('events render between body and comment blocks',
        (tester) async {
      final bodyTs = DateTime(2024, 6, 15, 10, 0);
      final eventTs = DateTime(2024, 6, 15, 11, 0);
      final commentTs = DateTime(2024, 6, 15, 12, 0);

      final events = [
        _event(
          type: ActivityEventType.tagAdded,
          timestamp: eventTs,
          data: {'tag': 'bug'},
        ),
      ];
      final comment = TicketComment(
        id: 'c1',
        text: 'Fixed it',
        author: 'alice',
        authorType: AuthorType.user,
        createdAt: commentTs,
      );

      await tester.pumpWidget(_wrap(Column(
        children: [
          TicketCommentBlock(
            key: const ValueKey('body'),
            author: 'zaf',
            authorType: AuthorType.user,
            timestamp: bodyTs,
            markdownContent: 'Initial description',
          ),
          for (final ce in coalesceEvents(events))
            TicketActivityEvent(key: const ValueKey('event'), coalescedEvent: ce),
          TicketCommentBlock(
            key: const ValueKey('comment'),
            author: comment.author,
            authorType: comment.authorType,
            timestamp: comment.createdAt,
            markdownContent: comment.text,
          ),
        ],
      )));

      // All three should be present.
      expect(find.byType(TicketCommentBlock), findsNWidgets(2));
      expect(find.byType(TicketActivityEvent), findsOneWidget);

      // Verify ordering by checking element positions.
      final bodyPos = tester.getTopLeft(find.byKey(const ValueKey('body')));
      final eventPos = tester.getTopLeft(find.byKey(const ValueKey('event')));
      final commentPos = tester.getTopLeft(find.byKey(const ValueKey('comment')));

      expect(bodyPos.dy, lessThan(eventPos.dy));
      expect(eventPos.dy, lessThan(commentPos.dy));
    });

    testWidgets('chronological order: events sorted by timestamp',
        (tester) async {
      final e1 = _event(
        id: '1',
        actor: 'zaf',
        type: ActivityEventType.tagAdded,
        timestamp: DateTime(2024, 6, 15, 10, 0),
        data: {'tag': 'a'},
      );
      final e2 = _event(
        id: '2',
        actor: 'alice',
        type: ActivityEventType.closed,
        timestamp: DateTime(2024, 6, 15, 11, 0),
      );

      final coalesced = coalesceEvents([e1, e2]);

      await tester.pumpWidget(_wrap(Column(
        children: [
          for (var i = 0; i < coalesced.length; i++)
            TicketActivityEvent(
              key: ValueKey('ev-$i'),
              coalescedEvent: coalesced[i],
            ),
        ],
      )));

      expect(find.byType(TicketActivityEvent), findsNWidgets(2));

      // First event above second.
      final first = tester.getTopLeft(find.byKey(const ValueKey('ev-0')));
      final second = tester.getTopLeft(find.byKey(const ValueKey('ev-1')));
      expect(first.dy, lessThan(second.dy));
    });

    testWidgets('empty timeline shows no activity events', (tester) async {
      final coalesced = coalesceEvents([]);

      await tester.pumpWidget(_wrap(Column(
        children: [
          for (final ce in coalesced)
            TicketActivityEvent(coalescedEvent: ce),
        ],
      )));

      expect(find.byType(TicketActivityEvent), findsNothing);
    });

    testWidgets('coalescing groups same-actor events within 5 seconds',
        (tester) async {
      final base = DateTime(2024, 6, 15, 12, 0, 0);
      final events = [
        _event(
          id: '1',
          actor: 'zaf',
          type: ActivityEventType.tagAdded,
          timestamp: base,
          data: {'tag': 'a'},
        ),
        _event(
          id: '2',
          actor: 'zaf',
          type: ActivityEventType.tagAdded,
          timestamp: base.add(const Duration(seconds: 3)),
          data: {'tag': 'b'},
        ),
        _event(
          id: '3',
          actor: 'alice',
          type: ActivityEventType.closed,
          timestamp: base.add(const Duration(seconds: 10)),
        ),
      ];

      final coalesced = coalesceEvents(events);

      await tester.pumpWidget(_wrap(Column(
        children: [
          for (final ce in coalesced)
            TicketActivityEvent(coalescedEvent: ce),
        ],
      )));

      // First two events coalesce into one, third is separate.
      expect(find.byType(TicketActivityEvent), findsNWidgets(2));

      // Both tags from the coalesced group should appear.
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });
  });
}
