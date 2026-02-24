import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
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

  group('BulkProposalState - Bulk Proposals', () {
    test('proposeBulk creates tickets', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      final proposals = [
        const TicketProposal(title: 'Ticket A'),
        const TicketProposal(title: 'Ticket B'),
        const TicketProposal(
          title: 'Ticket C',
          body: 'Description of C',
        ),
      ];

      final created = state.proposeBulk(
        proposals,
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(created.length, 3);
      expect(created.every((t) => t.isOpen), isTrue);
      expect(created[0].title, 'Ticket A');
      expect(created[1].title, 'Ticket B');
      expect(created[2].title, 'Ticket C');
      expect(created[2].body, 'Description of C');
      expect(repo.tickets.length, 3);
    });

    test('proposeBulk converts dependency indices to ticket IDs', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      final proposals = [
        const TicketProposal(title: 'Base ticket'),
        const TicketProposal(
          title: 'Depends on base',
          dependsOnIndices: [0],
        ),
        const TicketProposal(
          title: 'Depends on both',
          dependsOnIndices: [0, 1],
        ),
      ];

      final created = state.proposeBulk(
        proposals,
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // Index 0 maps to the first created ticket's ID
      expect(created[1].dependsOn, [created[0].id]);
      expect(created[2].dependsOn, [created[0].id, created[1].id]);
    });

    test('proposeBulk silently drops invalid dependency indices', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      final proposals = [
        const TicketProposal(title: 'Base ticket'),
        const TicketProposal(
          title: 'Has invalid dep',
          dependsOnIndices: [0, 5, -1, 99],
        ),
      ];

      final created = state.proposeBulk(
        proposals,
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // Only index 0 is valid; 5, -1, 99 are out of range
      expect(created[1].dependsOn, [created[0].id]);
    });

    test('proposeBulk sets hasActiveProposal', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      state.proposeBulk(
        [const TicketProposal(title: 'Test')],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(state.hasActiveProposal, isTrue);
    });

    test('toggleProposalChecked flips checked state', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'A'),
          const TicketProposal(title: 'B'),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // All should be checked initially
      expect(state.proposalCheckedIds.contains(created[0].id), isTrue);

      // Toggle off
      state.toggleProposalChecked(created[0].id);
      expect(state.proposalCheckedIds.contains(created[0].id), isFalse);

      // Toggle back on
      state.toggleProposalChecked(created[0].id);
      expect(state.proposalCheckedIds.contains(created[0].id), isTrue);
    });

    test('setProposalAllChecked(true) checks all proposed tickets', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'A'),
          const TicketProposal(title: 'B'),
          const TicketProposal(title: 'C'),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // Uncheck all first
      state.setProposalAllChecked(false);
      expect(state.proposalCheckedIds, isEmpty);

      // Check all
      state.setProposalAllChecked(true);
      expect(state.proposalCheckedIds.length, 3);
      for (final ticket in created) {
        expect(state.proposalCheckedIds.contains(ticket.id), isTrue);
      }
    });

    test('setProposalAllChecked(false) unchecks all proposed tickets', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      state.proposeBulk(
        [
          const TicketProposal(title: 'A'),
          const TicketProposal(title: 'B'),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // Initially all checked
      expect(state.proposalCheckedIds.length, 2);

      state.setProposalAllChecked(false);
      expect(state.proposalCheckedIds, isEmpty);
    });

    test('approveBulk keeps checked tickets and deletes unchecked', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'Keep'),
          const TicketProposal(title: 'Delete'),
          const TicketProposal(title: 'Also Keep'),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // Uncheck the middle ticket
      state.toggleProposalChecked(created[1].id);

      state.approveBulk();

      // Two tickets should remain
      expect(repo.tickets.length, 2);

      // Checked tickets should still exist and be open
      final kept1 = repo.getTicket(created[0].id);
      expect(kept1, isNotNull);
      expect(kept1!.isOpen, isTrue);

      final kept2 = repo.getTicket(created[2].id);
      expect(kept2, isNotNull);
      expect(kept2!.isOpen, isTrue);

      // Deleted ticket should be gone
      expect(repo.getTicket(created[1].id), isNull);
    });

    test('approveBulk clears active proposal', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      state.proposeBulk(
        [const TicketProposal(title: 'Test')],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(state.hasActiveProposal, isTrue);

      state.approveBulk();

      expect(state.hasActiveProposal, isFalse);
    });

    test('rejectAll deletes all tickets from proposal', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      // Create a pre-existing ticket
      final preExisting = repo.createTicket(title: 'Pre-existing');

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'Draft A'),
          const TicketProposal(title: 'Draft B'),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(repo.tickets.length, 3); // 1 pre-existing + 2 proposals

      state.rejectAll();

      // Only the pre-existing ticket should remain
      expect(repo.tickets.length, 1);
      expect(repo.tickets.first.id, preExisting.id);
      expect(repo.getTicket(created[0].id), isNull);
      expect(repo.getTicket(created[1].id), isNull);
      expect(state.hasActiveProposal, isFalse);
    });

    test('proposalSourceChatName returns the correct chat name', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      // Before any proposal, should return empty string
      expect(state.proposalSourceChatName, '');

      state.proposeBulk(
        [const TicketProposal(title: 'Test')],
        sourceChatId: 'chat-42',
        sourceChatName: 'My Agent Chat',
      );

      expect(state.proposalSourceChatName, 'My Agent Chat');
      expect(state.proposalSourceChatId, 'chat-42');
    });

    test('proposeBulk with tags passes them through', () {
      final repo = resources.track(TicketRepository('test-project'));
      final state = resources.track(BulkProposalState(repo));

      final created = state.proposeBulk(
        [
          const TicketProposal(
            title: 'Tagged',
            tags: {'feature', 'urgent'},
          ),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(created[0].tags, {'feature', 'urgent'});
    });

    test('TicketProposal.fromJson parses correctly', () {
      final proposal = TicketProposal.fromJson({
        'title': 'Test Title',
        'body': 'Test body',
        'tags': ['feature', 'bug'],
        'dependsOnIndices': [0, 1],
      });

      expect(proposal.title, 'Test Title');
      expect(proposal.body, 'Test body');
      expect(proposal.tags, {'feature', 'bug'});
      expect(proposal.dependsOnIndices, [0, 1]);
    });

    test('TicketProposal.fromJson accepts description as body alias', () {
      final proposal = TicketProposal.fromJson({
        'title': 'Test',
        'description': 'Described body',
      });

      expect(proposal.body, 'Described body');
    });
  });
}
