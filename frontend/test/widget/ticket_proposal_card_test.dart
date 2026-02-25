import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/menu_action_service.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/widgets/ticket_proposal_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late BulkProposalState bulkState;
  late MenuActionService menuService;

  setUp(() {
    repo = resources.track(TicketRepository('test-proposal-card'));
    bulkState = resources.track(BulkProposalState(repo));
    menuService = resources.track(MenuActionService());
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  Widget createTestApp() {
    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<TicketRepository>.value(value: repo),
            ChangeNotifierProvider<BulkProposalState>.value(value: bulkState),
            ChangeNotifierProvider<MenuActionService>.value(
                value: menuService),
          ],
          child: const TicketProposalCard(),
        ),
      ),
    );
  }

  /// Creates proposals and enters bulk review mode.
  void createProposals({int count = 3}) {
    final proposals = <TicketProposal>[];
    for (var i = 0; i < count; i++) {
      proposals.add(TicketProposal(
        title: 'Ticket ${i + 1}',
        body: 'Description for ticket ${i + 1}.',
      ));
    }
    bulkState.proposeBulk(
      proposals,
      sourceChatId: 'chat-1',
      sourceChatName: 'My Chat',
    );
  }

  group('TicketProposalCard', () {
    testWidgets('renders nothing when no active proposal', (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.byKey(TicketProposalCardKeys.card), findsNothing);
    });

    testWidgets('shows header with ticket count and chat name',
        (tester) async {
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.byKey(TicketProposalCardKeys.card), findsOneWidget);
      expect(find.byKey(TicketProposalCardKeys.header), findsOneWidget);
      expect(
        find.text('3 tickets proposed by "My Chat"'),
        findsOneWidget,
      );
    });

    testWidgets('shows singular "ticket" for single proposal',
        (tester) async {
      createProposals(count: 1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(
        find.text('1 ticket proposed by "My Chat"'),
        findsOneWidget,
      );
    });

    testWidgets('shows ticket titles up to max visible', (tester) async {
      createProposals(count: 3);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Ticket 1'), findsOneWidget);
      expect(find.text('Ticket 2'), findsOneWidget);
      expect(find.text('Ticket 3'), findsOneWidget);
      expect(find.byKey(TicketProposalCardKeys.overflowText), findsNothing);
    });

    testWidgets('shows exactly 4 tickets with no overflow at boundary',
        (tester) async {
      createProposals(count: 4);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Ticket 1'), findsOneWidget);
      expect(find.text('Ticket 2'), findsOneWidget);
      expect(find.text('Ticket 3'), findsOneWidget);
      expect(find.text('Ticket 4'), findsOneWidget);
      expect(find.byKey(TicketProposalCardKeys.overflowText), findsNothing);
      expect(find.byKey(TicketProposalCardKeys.ticketList), findsOneWidget);
    });

    testWidgets('shows overflow text when more than 4 tickets',
        (tester) async {
      createProposals(count: 6);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // First 4 visible
      expect(find.text('Ticket 1'), findsOneWidget);
      expect(find.text('Ticket 2'), findsOneWidget);
      expect(find.text('Ticket 3'), findsOneWidget);
      expect(find.text('Ticket 4'), findsOneWidget);
      // 5 and 6 hidden
      expect(find.text('Ticket 5'), findsNothing);
      expect(find.text('Ticket 6'), findsNothing);
      // Overflow text
      expect(find.byKey(TicketProposalCardKeys.overflowText), findsOneWidget);
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('approve button calls approveBulk', (tester) async {
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(TicketProposalCardKeys.approveButton));
      await tester.pump();

      // After approval, proposal is cleared
      expect(bulkState.hasActiveProposal, isFalse);
      // Approved tickets remain open in the repository
      final tickets = repo.tickets;
      expect(tickets, isNotEmpty);
      expect(tickets.every((t) => t.isOpen), isTrue);
    });

    testWidgets('reject button calls rejectAll', (tester) async {
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(TicketProposalCardKeys.rejectButton));
      await tester.pump();

      // After rejection, proposal is cleared
      expect(bulkState.hasActiveProposal, isFalse);
      // Tickets should be deleted
      expect(repo.tickets, isEmpty);
    });

    testWidgets('expand button triggers showTickets menu action',
        (tester) async {
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(TicketProposalCardKeys.expandButton));
      await tester.pump();

      expect(menuService.lastAction, MenuAction.showTickets);
    });

    testWidgets('card disappears after approval', (tester) async {
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);
      expect(find.byKey(TicketProposalCardKeys.card), findsOneWidget);

      await tester.tap(find.byKey(TicketProposalCardKeys.approveButton));
      await safePumpAndSettle(tester);

      expect(find.byKey(TicketProposalCardKeys.card), findsNothing);
    });

    testWidgets('card disappears after rejection', (tester) async {
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);
      expect(find.byKey(TicketProposalCardKeys.card), findsOneWidget);

      await tester.tap(find.byKey(TicketProposalCardKeys.rejectButton));
      await safePumpAndSettle(tester);

      expect(find.byKey(TicketProposalCardKeys.card), findsNothing);
    });
  });
}
