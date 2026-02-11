import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendProvider, ToolInvocationEvent, ToolKind;
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// Event ID counter for generating unique event IDs.
int _idCounter = 0;

/// Generates a unique event ID.
String _nextId() => 'evt-ticket-${_idCounter++}';

/// Helper to create ToolInvocationEvent for create_tickets.
ToolInvocationEvent makeCreateTicketsEvent({
  String? callId,
  Map<String, dynamic> input = const {},
  String? parentCallId,
}) {
  return ToolInvocationEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    callId: callId ?? 'call-${_nextId()}',
    sessionId: 'test-session',
    kind: ToolKind.execute,
    toolName: 'create_tickets',
    input: input,
    parentCallId: parentCallId,
  );
}

/// Creates a valid ticket proposal JSON map.
Map<String, dynamic> makeProposalJson({
  String title = 'Test Ticket',
  String description = 'Test description',
  String kind = 'feature',
  String priority = 'medium',
  String effort = 'medium',
  String? category,
}) {
  return {
    'title': title,
    'description': description,
    'kind': kind,
    'priority': priority,
    'effort': effort,
    if (category != null) 'category': category,
  };
}

void main() {
  final resources = TestResources();

  late ChatState chat;
  late EventHandler handler;
  late TicketBoardState ticketBoard;

  setUp(() {
    chat = resources.track(
      ChatState.create(name: 'Test Chat', worktreeRoot: '/tmp/test'),
    );
    ticketBoard = resources.track(TicketBoardState('test-project'));
    handler = EventHandler(ticketBoard: ticketBoard);
    _idCounter = 0;
  });

  tearDown(() async {
    handler.dispose();
    await resources.disposeAll();
  });

  group('EventHandler - create_tickets tool detection', () {
    test('recognizes create_tickets tool invocation', () {
      final event = makeCreateTicketsEvent(
        callId: 'ticket-call-1',
        input: {
          'tickets': [
            makeProposalJson(title: 'First ticket'),
          ],
        },
      );

      handler.handleEvent(chat, event);

      // Verify proposals were staged in ticket board
      check(ticketBoard.proposedTickets.length).equals(1);
      check(ticketBoard.proposedTickets.first.title).equals('First ticket');
    });

    test('does not intercept create_tickets when ticketBoard is null', () {
      final handlerWithoutBoard = EventHandler();

      final event = makeCreateTicketsEvent(
        callId: 'ticket-call-no-board',
        input: {
          'tickets': [makeProposalJson()],
        },
      );

      handlerWithoutBoard.handleEvent(chat, event);

      // Should be processed as a normal tool invocation
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(1);
      check(entries.first).isA<ToolUseOutputEntry>();
      final toolEntry = entries.first as ToolUseOutputEntry;
      check(toolEntry.toolName).equals('create_tickets');

      // Ticket board should have no proposals (it wasn't wired up)
      check(ticketBoard.proposedTickets).isEmpty();

      handlerWithoutBoard.dispose();
    });

    test('does not intercept other tool names', () {
      final event = ToolInvocationEvent(
        id: _nextId(),
        timestamp: DateTime.now(),
        provider: BackendProvider.claude,
        callId: 'call-other',
        sessionId: 'test-session',
        kind: ToolKind.execute,
        toolName: 'Bash',
        input: {'command': 'ls'},
      );

      handler.handleEvent(chat, event);

      // Should be a normal tool entry, not intercepted
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(1);
      check((entries.first as ToolUseOutputEntry).toolName).equals('Bash');
      check(ticketBoard.proposedTickets).isEmpty();
    });
  });

  group('EventHandler - create_tickets proposal parsing', () {
    test('parses valid proposals correctly', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [
            makeProposalJson(
              title: 'Implement auth',
              description: 'Add OAuth2 login',
              kind: 'feature',
              priority: 'high',
              category: 'Backend',
            ),
            makeProposalJson(
              title: 'Fix login bug',
              description: 'Fix redirect issue',
              kind: 'bugfix',
              priority: 'critical',
            ),
          ],
        },
      );

      handler.handleEvent(chat, event);

      final proposed = ticketBoard.proposedTickets;
      check(proposed.length).equals(2);

      check(proposed[0].title).equals('Implement auth');
      check(proposed[0].description).equals('Add OAuth2 login');
      check(proposed[0].kind).equals(TicketKind.feature);
      check(proposed[0].priority).equals(TicketPriority.high);
      check(proposed[0].category).equals('Backend');
      check(proposed[0].status).equals(TicketStatus.draft);

      check(proposed[1].title).equals('Fix login bug');
      check(proposed[1].kind).equals(TicketKind.bugfix);
      check(proposed[1].priority).equals(TicketPriority.critical);
    });

    test('creates tool entry for display', () {
      final event = makeCreateTicketsEvent(
        callId: 'display-call',
        input: {
          'tickets': [makeProposalJson()],
        },
      );

      handler.handleEvent(chat, event);

      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(1);
      check(entries.first).isA<ToolUseOutputEntry>();
      final toolEntry = entries.first as ToolUseOutputEntry;
      check(toolEntry.toolName).equals('create_tickets');
      check(toolEntry.toolUseId).equals('display-call');
    });
  });

  group('EventHandler - create_tickets invalid input handling', () {
    test('missing required title field does not crash', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [
            {
              'description': 'No title here',
              'kind': 'feature',
            },
          ],
        },
      );

      // Should not throw
      handler.handleEvent(chat, event);

      // No proposals should be staged
      check(ticketBoard.proposedTickets).isEmpty();
      check(ticketBoard.detailMode).equals(TicketDetailMode.detail);
    });

    test('missing required description field does not crash', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [
            {
              'title': 'Has title',
              'kind': 'feature',
            },
          ],
        },
      );

      handler.handleEvent(chat, event);

      // Should not crash but the description defaults to '' in fromJson,
      // and the validation checks for null (not empty). Since the key is
      // missing, it will be null. So no proposals.
      check(ticketBoard.proposedTickets).isEmpty();
    });

    test('missing required kind field does not crash', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [
            {
              'title': 'Has title',
              'description': 'Has desc',
            },
          ],
        },
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposedTickets).isEmpty();
    });

    test('empty title string does not crash', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [
            makeProposalJson(title: ''),
          ],
        },
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposedTickets).isEmpty();
    });

    test('non-list tickets field does not crash', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': 'not a list',
        },
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposedTickets).isEmpty();
    });

    test('missing tickets field entirely does not crash', () {
      final event = makeCreateTicketsEvent(
        input: {},
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposedTickets).isEmpty();
    });
  });

  group('EventHandler - create_tickets count limits', () {
    test('more than 50 proposals are rejected', () {
      final proposals = List.generate(
        51,
        (i) => makeProposalJson(title: 'Ticket $i'),
      );

      final event = makeCreateTicketsEvent(
        input: {'tickets': proposals},
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposedTickets).isEmpty();
      check(ticketBoard.detailMode).equals(TicketDetailMode.detail);
    });

    test('exactly 50 proposals are accepted', () {
      final proposals = List.generate(
        50,
        (i) => makeProposalJson(title: 'Ticket $i'),
      );

      final event = makeCreateTicketsEvent(
        input: {'tickets': proposals},
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposedTickets.length).equals(50);
    });
  });

  group('EventHandler - create_tickets empty proposals', () {
    test('empty array is rejected', () {
      final event = makeCreateTicketsEvent(
        input: {'tickets': <Map<String, dynamic>>[]},
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposedTickets).isEmpty();
      check(ticketBoard.detailMode).equals(TicketDetailMode.detail);
    });
  });

  group('EventHandler - create_tickets staging and mode', () {
    test('proposals are staged as draft tickets', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [
            makeProposalJson(title: 'Draft ticket 1'),
            makeProposalJson(title: 'Draft ticket 2'),
          ],
        },
      );

      handler.handleEvent(chat, event);

      final proposed = ticketBoard.proposedTickets;
      check(proposed.length).equals(2);

      // All should be draft status
      for (final ticket in proposed) {
        check(ticket.status).equals(TicketStatus.draft);
      }
    });

    test('detail mode is set to bulkReview after proposals', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [makeProposalJson()],
        },
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.detailMode).equals(TicketDetailMode.bulkReview);
    });

    test('proposal source chat info is set', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [makeProposalJson()],
        },
      );

      handler.handleEvent(chat, event);

      check(ticketBoard.proposalSourceChatName).equals('Test Chat');
      check(ticketBoard.proposalSourceChatId).equals(chat.data.id);
    });

    test('all proposed tickets are auto-checked for approval', () {
      final event = makeCreateTicketsEvent(
        input: {
          'tickets': [
            makeProposalJson(title: 'Check me 1'),
            makeProposalJson(title: 'Check me 2'),
            makeProposalJson(title: 'Check me 3'),
          ],
        },
      );

      handler.handleEvent(chat, event);

      final proposed = ticketBoard.proposedTickets;
      check(proposed.length).equals(3);
      // All should be checked
      for (final ticket in proposed) {
        check(ticketBoard.proposalCheckedIds.contains(ticket.id)).isTrue();
      }
    });
  });

  group('EventHandler - create_tickets review callback', () {
    test('completeTicketReview sends tool result after approve', () {
      final event = makeCreateTicketsEvent(
        callId: 'review-call-1',
        input: {
          'tickets': [
            makeProposalJson(title: 'Approve me'),
            makeProposalJson(title: 'Approve me too'),
          ],
        },
      );

      handler.handleEvent(chat, event);
      check(handler.hasPendingTicketReview).isTrue();

      // Approve all (both are auto-checked)
      ticketBoard.approveBulk();

      // The callback should have fired, completing the review
      check(handler.hasPendingTicketReview).isFalse();

      // The tool entry should have a result
      final entries = chat.data.primaryConversation.entries;
      final toolEntry = entries.first as ToolUseOutputEntry;
      check(toolEntry.result).isNotNull();
      check(toolEntry.result!.toString())
          .contains('2 ticket proposals were approved');
    });

    test('completeTicketReview sends rejection result after rejectAll', () {
      final event = makeCreateTicketsEvent(
        callId: 'reject-call-1',
        input: {
          'tickets': [
            makeProposalJson(title: 'Reject me'),
            makeProposalJson(title: 'Reject me too'),
          ],
        },
      );

      handler.handleEvent(chat, event);
      check(handler.hasPendingTicketReview).isTrue();

      // Reject all
      ticketBoard.rejectAll();

      check(handler.hasPendingTicketReview).isFalse();

      // The tool entry should have a rejection result
      final entries = chat.data.primaryConversation.entries;
      final toolEntry = entries.first as ToolUseOutputEntry;
      check(toolEntry.result).isNotNull();
      check(toolEntry.result!.toString())
          .contains('rejected by the user');
    });

    test('completeTicketReview with partial approval', () {
      final event = makeCreateTicketsEvent(
        callId: 'partial-call-1',
        input: {
          'tickets': [
            makeProposalJson(title: 'Keep this'),
            makeProposalJson(title: 'Reject this'),
            makeProposalJson(title: 'Keep this too'),
          ],
        },
      );

      handler.handleEvent(chat, event);

      // Uncheck the second proposal
      final proposed = ticketBoard.proposedTickets;
      ticketBoard.toggleProposalChecked(proposed[1].id);

      // Approve bulk (2 checked, 1 unchecked)
      ticketBoard.approveBulk();

      check(handler.hasPendingTicketReview).isFalse();

      final entries = chat.data.primaryConversation.entries;
      final toolEntry = entries.first as ToolUseOutputEntry;
      check(toolEntry.result).isNotNull();
      check(toolEntry.result!.toString()).contains('2 of 3');
      check(toolEntry.result!.toString()).contains('1 were rejected');
    });
  });
}
