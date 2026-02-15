import 'dart:async';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/internal_tools_service.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  group('InternalToolsService', () {
    test('creates with empty registry', () {
      final service = resources.track(InternalToolsService());

      expect(service.registry.isEmpty, isTrue);
      expect(service.registry.tools, isEmpty);
    });

    test('registerTicketTools adds create_ticket to registry', () {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));

      service.registerTicketTools(board);

      expect(service.registry.isNotEmpty, isTrue);
      expect(service.registry['create_ticket'], isNotNull);
      expect(service.registry['create_ticket']!.name, 'create_ticket');
    });

    test('registry is accessible via getter', () {
      final service = resources.track(InternalToolsService());

      final registry = service.registry;

      expect(registry, isA<InternalToolRegistry>());
    });

    test('unregisterTicketTools removes create_ticket from registry', () {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));

      service.registerTicketTools(board);
      expect(service.registry['create_ticket'], isNotNull);

      service.unregisterTicketTools();
      expect(service.registry['create_ticket'], isNull);
      expect(service.registry.isEmpty, isTrue);
    });
  });

  group('InternalToolsService - create_ticket handler', () {
    test('returns error for missing tickets field', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or invalid "tickets"'));
    });

    test('returns error for non-array tickets field', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({'tickets': 'not-an-array'});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or invalid "tickets"'));
    });

    test('returns error for empty tickets array', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({'tickets': []});

      expect(result.isError, isTrue);
      expect(result.content, contains('Empty tickets array'));
    });

    test('returns error for too many proposals', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tooMany = List.generate(
        InternalToolsService.maxProposalCount + 1,
        (i) => {
          'title': 'Ticket $i',
          'description': 'Desc $i',
          'kind': 'feature',
        },
      );

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({'tickets': tooMany});

      expect(result.isError, isTrue);
      expect(result.content, contains('Too many proposals'));
      expect(result.content, contains('> ${InternalToolsService.maxProposalCount}'));
    });

    test('returns error for ticket missing title', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'description': 'A desc', 'kind': 'feature'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"title"'));
    });

    test('returns error for ticket missing description', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': 'A title', 'kind': 'feature'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"description"'));
    });

    test('returns error for ticket missing kind', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': 'A title', 'description': 'A desc'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"kind"'));
    });

    test('returns error for non-object ticket entry', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': ['not-an-object'],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('not a valid object'));
    });

    test('stages valid proposals in board and waits for review', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;

      // Start the handler (it will return a Future that waits for review)
      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Add dark mode',
            'description': 'Implement dark mode toggle',
            'kind': 'feature',
            'priority': 'high',
          },
        ],
      });

      // The board should have the staged proposals
      expect(board.tickets.length, 1);
      expect(board.tickets.first.title, 'Add dark mode');
      expect(board.tickets.first.status, TicketStatus.draft);
      expect(board.detailMode, TicketDetailMode.bulkReview);

      // The future should not have completed yet
      var completed = false;
      unawaited(resultFuture.then((_) => completed = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(completed, isFalse);

      // Simulate the user approving all tickets
      board.approveBulk();

      // Now the future should complete
      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('approved'));
    });

    test('returns appropriate text when all approved', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'bugfix',
          },
        ],
      });

      // All tickets are auto-checked, so approveBulk approves all
      board.approveBulk();

      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('All 2'));
      expect(result.content, contains('approved and created'));
    });

    test('returns appropriate text when all rejected', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'bugfix',
          },
        ],
      });

      // Reject all tickets
      board.rejectAll();

      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('All 2'));
      expect(result.content, contains('rejected'));
    });

    test('returns appropriate text for mixed approval', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'bugfix',
          },
          {
            'title': 'Ticket C',
            'description': 'Desc C',
            'kind': 'chore',
          },
        ],
      });

      // Uncheck one ticket before approving
      final proposedTickets = board.proposedTickets;
      expect(proposedTickets.length, 3);

      board.toggleProposalChecked(proposedTickets[1].id);
      board.approveBulk();

      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('2 of 3'));
      expect(result.content, contains('approved and created'));
      expect(result.content, contains('1 were rejected'));
    });

    test('stream-based review supports sequential tool calls', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;

      // First call
      final resultFuture1 = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
        ],
      });

      board.approveBulk();
      final result1 = await resultFuture1;
      expect(result1.isError, isFalse);

      // Second call should also work (no stale callback issues)
      final resultFuture2 = tool.handler({
        'tickets': [
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'feature',
          },
        ],
      });

      board.approveBulk();
      final result2 = await resultFuture2;
      expect(result2.isError, isFalse);
    });

    test('parses optional fields correctly', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Complex ticket',
            'description': 'Detailed work description',
            'kind': 'feature',
            'priority': 'critical',
            'effort': 'large',
            'category': 'Backend',
            'tags': ['api', 'database'],
          },
        ],
      });

      final ticket = board.tickets.first;
      expect(ticket.title, 'Complex ticket');
      expect(ticket.description, 'Detailed work description');
      expect(ticket.kind, TicketKind.feature);
      expect(ticket.priority, TicketPriority.critical);
      expect(ticket.effort, TicketEffort.large);
      expect(ticket.category, 'Backend');
      expect(ticket.tags, containsAll(['api', 'database']));

      // Clean up by completing the review
      board.approveBulk();
      await resultFuture;
    });

    test('returns error for ticket with empty title', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': '', 'description': 'A desc', 'kind': 'feature'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"title"'));
    });

    test('returns error for ticket with empty kind', () async {
      final service = resources.track(InternalToolsService());
      final board = resources.track(TicketBoardState('test-project'));
      service.registerTicketTools(board);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': 'Test', 'description': 'A desc', 'kind': ''},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"kind"'));
    });
  });
}
