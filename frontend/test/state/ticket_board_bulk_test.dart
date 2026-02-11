import 'package:cc_insights_v2/models/ticket.dart';
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

  group('TicketBoardState - Bulk Proposals', () {
    test('proposeBulk creates draft tickets', () {
      final state = resources.track(TicketBoardState('test-project'));

      final proposals = [
        const TicketProposal(
          title: 'Ticket A',
          kind: TicketKind.feature,
          priority: TicketPriority.high,
        ),
        const TicketProposal(
          title: 'Ticket B',
          kind: TicketKind.bugfix,
          priority: TicketPriority.medium,
        ),
        const TicketProposal(
          title: 'Ticket C',
          kind: TicketKind.chore,
          priority: TicketPriority.low,
          category: 'Infrastructure',
        ),
      ];

      final created = state.proposeBulk(
        proposals,
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(created.length, 3);
      expect(created.every((t) => t.status == TicketStatus.draft), isTrue);
      expect(created[0].title, 'Ticket A');
      expect(created[1].title, 'Ticket B');
      expect(created[2].title, 'Ticket C');
      expect(created[2].category, 'Infrastructure');
      expect(state.tickets.length, 3);
    });

    test('proposeBulk converts dependency indices to ticket IDs', () {
      final state = resources.track(TicketBoardState('test-project'));

      final proposals = [
        const TicketProposal(
          title: 'Base ticket',
          kind: TicketKind.feature,
        ),
        const TicketProposal(
          title: 'Depends on base',
          kind: TicketKind.feature,
          dependsOnIndices: [0],
        ),
        const TicketProposal(
          title: 'Depends on both',
          kind: TicketKind.feature,
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
      final state = resources.track(TicketBoardState('test-project'));

      final proposals = [
        const TicketProposal(
          title: 'Base ticket',
          kind: TicketKind.feature,
        ),
        const TicketProposal(
          title: 'Has invalid dep',
          kind: TicketKind.feature,
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

    test('proposeBulk sets detailMode to bulkReview', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.proposeBulk(
        [const TicketProposal(title: 'Test', kind: TicketKind.feature)],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(state.detailMode, TicketDetailMode.bulkReview);
    });

    test('toggleProposalChecked flips checked state', () {
      final state = resources.track(TicketBoardState('test-project'));

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'A', kind: TicketKind.feature),
          const TicketProposal(title: 'B', kind: TicketKind.feature),
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
      final state = resources.track(TicketBoardState('test-project'));

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'A', kind: TicketKind.feature),
          const TicketProposal(title: 'B', kind: TicketKind.feature),
          const TicketProposal(title: 'C', kind: TicketKind.feature),
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
      final state = resources.track(TicketBoardState('test-project'));

      state.proposeBulk(
        [
          const TicketProposal(title: 'A', kind: TicketKind.feature),
          const TicketProposal(title: 'B', kind: TicketKind.feature),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // Initially all checked
      expect(state.proposalCheckedIds.length, 2);

      state.setProposalAllChecked(false);
      expect(state.proposalCheckedIds, isEmpty);
    });

    test('approveBulk promotes checked tickets to ready and deletes unchecked', () {
      final state = resources.track(TicketBoardState('test-project'));

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'Keep', kind: TicketKind.feature),
          const TicketProposal(title: 'Delete', kind: TicketKind.bugfix),
          const TicketProposal(title: 'Also Keep', kind: TicketKind.chore),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      // Uncheck the middle ticket
      state.toggleProposalChecked(created[1].id);

      state.approveBulk();

      // Two tickets should remain
      expect(state.tickets.length, 2);

      // Checked tickets should be ready
      final kept1 = state.getTicket(created[0].id);
      expect(kept1, isNotNull);
      expect(kept1!.status, TicketStatus.ready);

      final kept2 = state.getTicket(created[2].id);
      expect(kept2, isNotNull);
      expect(kept2!.status, TicketStatus.ready);

      // Deleted ticket should be gone
      expect(state.getTicket(created[1].id), isNull);
    });

    test('approveBulk returns to detail mode', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.proposeBulk(
        [const TicketProposal(title: 'Test', kind: TicketKind.feature)],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(state.detailMode, TicketDetailMode.bulkReview);

      state.approveBulk();

      expect(state.detailMode, TicketDetailMode.detail);
    });

    test('rejectAll deletes all draft tickets from proposal', () {
      final state = resources.track(TicketBoardState('test-project'));

      // Create a pre-existing ticket
      final preExisting = state.createTicket(
        title: 'Pre-existing',
        kind: TicketKind.feature,
      );

      final created = state.proposeBulk(
        [
          const TicketProposal(title: 'Draft A', kind: TicketKind.feature),
          const TicketProposal(title: 'Draft B', kind: TicketKind.bugfix),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent Chat',
      );

      expect(state.tickets.length, 3); // 1 pre-existing + 2 proposals

      state.rejectAll();

      // Only the pre-existing ticket should remain
      expect(state.tickets.length, 1);
      expect(state.tickets.first.id, preExisting.id);
      expect(state.getTicket(created[0].id), isNull);
      expect(state.getTicket(created[1].id), isNull);
      expect(state.detailMode, TicketDetailMode.detail);
    });

    test('proposalSourceChatName returns the correct chat name', () {
      final state = resources.track(TicketBoardState('test-project'));

      // Before any proposal, should return empty string
      expect(state.proposalSourceChatName, '');

      state.proposeBulk(
        [const TicketProposal(title: 'Test', kind: TicketKind.feature)],
        sourceChatId: 'chat-42',
        sourceChatName: 'My Agent Chat',
      );

      expect(state.proposalSourceChatName, 'My Agent Chat');
      expect(state.proposalSourceChatId, 'chat-42');
    });
  });
}
