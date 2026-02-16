import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_bulk_review_panel.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/widgets/ticket_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late BulkProposalState bulkState;

  setUp(() {
    repo = resources.track(TicketRepository('test-bulk-review'));
    bulkState = resources.track(BulkProposalState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  /// Helper to create a set of proposals and enter bulk review mode.
  List<TicketData> createProposals() {
    return bulkState.proposeBulk(
      [
        const TicketProposal(
          title: 'Set up auth service',
          kind: TicketKind.feature,
          category: 'Auth',
          description: 'Scaffold the auth service.',
        ),
        const TicketProposal(
          title: 'Implement JWT tokens',
          kind: TicketKind.feature,
          category: 'Auth',
          dependsOnIndices: [0],
          description: 'Issue and validate JWT access tokens.',
        ),
        const TicketProposal(
          title: 'Write auth tests',
          kind: TicketKind.test,
          category: 'Testing',
          dependsOnIndices: [1],
        ),
      ],
      sourceChatId: 'chat-1',
      sourceChatName: 'Planning auth system',
    );
  }

  Widget createTestApp() {
    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<TicketRepository>.value(value: repo),
            ChangeNotifierProvider<BulkProposalState>.value(value: bulkState),
          ],
          child: const TicketBulkReviewPanel(),
        ),
      ),
    );
  }

  /// Sets up a large viewport so the panel layout does not overflow.
  void setLargeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('TicketBulkReviewPanel', () {
    testWidgets('renders all proposed tickets in the table', (tester) async {
      setLargeViewport(tester);
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // All three ticket titles should be visible
      expect(find.text('Set up auth service'), findsOneWidget);
      expect(find.text('Implement JWT tokens'), findsOneWidget);
      expect(find.text('Write auth tests'), findsOneWidget);

      // Header text
      expect(find.text('Review Proposed Tickets'), findsOneWidget);

      // Kind badges
      expect(find.byType(KindBadge), findsNWidgets(3));
    });

    testWidgets('checkbox toggles call toggleProposalChecked', (tester) async {
      setLargeViewport(tester);
      final proposals = createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // All should be checked initially
      expect(bulkState.proposalCheckedIds.length, 3);

      // Find the first checkbox and tap it
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(3));

      await tester.tap(checkboxes.first);
      await safePumpAndSettle(tester);

      // First ticket should now be unchecked
      expect(
        bulkState.proposalCheckedIds.contains(proposals[0].id),
        isFalse,
      );
      expect(bulkState.proposalCheckedIds.length, 2);
    });

    testWidgets('unchecked rows have reduced opacity', (tester) async {
      setLargeViewport(tester);
      final proposals = createProposals();

      // Uncheck the first proposal
      bulkState.toggleProposalChecked(proposals[0].id);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Find all Opacity widgets that wrap row content
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));

      // At least one should have reduced opacity (0.5)
      final reducedOpacity = opacityWidgets.where((o) => o.opacity == 0.5);
      expect(reducedOpacity.isNotEmpty, isTrue);

      // The rest should have full opacity
      final fullOpacity = opacityWidgets.where((o) => o.opacity == 1.0);
      expect(fullOpacity.isNotEmpty, isTrue);
    });

    testWidgets('Select All checks all proposals', (tester) async {
      setLargeViewport(tester);
      createProposals();

      // Uncheck all first
      bulkState.setProposalAllChecked(false);
      expect(bulkState.proposalCheckedIds.length, 0);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap "Select All"
      await tester.tap(find.byKey(TicketBulkReviewKeys.selectAllButton));
      await safePumpAndSettle(tester);

      expect(bulkState.proposalCheckedIds.length, 3);
    });

    testWidgets('Deselect All unchecks all proposals', (tester) async {
      setLargeViewport(tester);
      createProposals();

      // All should be checked initially
      expect(bulkState.proposalCheckedIds.length, 3);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap "Deselect All"
      await tester.tap(find.byKey(TicketBulkReviewKeys.deselectAllButton));
      await safePumpAndSettle(tester);

      expect(bulkState.proposalCheckedIds.length, 0);
    });

    testWidgets('row tap opens inline edit card', (tester) async {
      setLargeViewport(tester);
      createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // No edit card initially
      expect(find.byKey(TicketBulkReviewKeys.editCard), findsNothing);

      // Tap the first row (on the title text)
      await tester.tap(find.text('Set up auth service'));
      await safePumpAndSettle(tester);

      // Edit card should now be visible
      expect(find.byKey(TicketBulkReviewKeys.editCard), findsOneWidget);
    });

    testWidgets('edit card shows selected ticket data', (tester) async {
      setLargeViewport(tester);
      final proposals = createProposals();

      // Set editing to the second proposal
      bulkState.setProposalEditing(proposals[1].id);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Edit card should be visible
      expect(find.byKey(TicketBulkReviewKeys.editCard), findsOneWidget);

      // Should show "Editing: TKT-002"
      expect(find.text('Editing: ${proposals[1].displayId}'), findsOneWidget);

      // Title field should contain the ticket's title
      final titleFields = find.byType(TextField);
      expect(titleFields, findsWidgets);

      // Check that the title text is present in a TextField
      final titleField = tester.widgetList<TextField>(titleFields).firstWhere(
        (tf) => tf.controller?.text == 'Implement JWT tokens',
        orElse: () => throw TestFailure('Title field with correct value not found'),
      );
      expect(titleField.controller?.text, 'Implement JWT tokens');
    });

    testWidgets('approve button shows correct checked count', (tester) async {
      setLargeViewport(tester);
      final proposals = createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // All 3 checked initially
      expect(find.text('Approve 3'), findsOneWidget);

      // Uncheck one
      bulkState.toggleProposalChecked(proposals[0].id);
      await tester.pump();

      // Should now show 2
      expect(find.text('Approve 2'), findsOneWidget);
    });

    testWidgets('tapping Approve calls approveBulk', (tester) async {
      setLargeViewport(tester);
      final proposals = createProposals();

      // Uncheck the last one so we can verify the behavior
      bulkState.toggleProposalChecked(proposals[2].id);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap approve
      await tester.tap(find.byKey(TicketBulkReviewKeys.approveButton));
      await safePumpAndSettle(tester);

      // After approval:
      // - Checked tickets (0 and 1) should be promoted to ready
      // - Unchecked ticket (2) should be deleted
      // - Detail mode should return to detail
      expect(repo.getTicket(proposals[0].id)?.status, TicketStatus.ready);
      expect(repo.getTicket(proposals[1].id)?.status, TicketStatus.ready);
      expect(repo.getTicket(proposals[2].id), isNull);
    });

    testWidgets('tapping Reject All calls rejectAll', (tester) async {
      setLargeViewport(tester);
      final proposals = createProposals();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap reject all
      await tester.tap(find.byKey(TicketBulkReviewKeys.rejectAllButton));
      await safePumpAndSettle(tester);

      // After rejection:
      // - All proposal tickets should be deleted
      // - Detail mode should return to detail
      expect(repo.getTicket(proposals[0].id), isNull);
      expect(repo.getTicket(proposals[1].id), isNull);
      expect(repo.getTicket(proposals[2].id), isNull);
      expect(repo.tickets, isEmpty);
    });
  });
}
