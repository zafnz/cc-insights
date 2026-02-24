import 'dart:ui';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_create_form.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
import 'package:cc_insights_v2/panels/ticket_list_panel.dart';
import 'package:cc_insights_v2/screens/ticket_screen.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late TicketViewState viewState;
  late BulkProposalState bulkState;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    repo = resources.track(TicketRepository('test-ticket-screen'));
    viewState = resources.track(TicketViewState(repo));
    bulkState = resources.track(BulkProposalState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  void setViewport(WidgetTester tester, {double width = 1200, double height = 900}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
  }

  Widget createTestApp() {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<TicketRepository>.value(value: repo),
          ChangeNotifierProvider<TicketViewState>.value(value: viewState),
          ChangeNotifierProvider<BulkProposalState>.value(value: bulkState),
        ],
        child: const Scaffold(body: TicketScreen()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Renders without errors
  // ---------------------------------------------------------------------------
  testWidgets('renders without errors when wrapped in providers', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.byType(TicketScreen), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 2. List panel and detail panel are present
  // ---------------------------------------------------------------------------
  testWidgets('default view shows TicketListPanel and detail content panel', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.byType(TicketListPanel), findsOneWidget);
    expect(find.text('Tickets'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 3. Status bar shows correct ticket counts
  // ---------------------------------------------------------------------------
  testWidgets('status bar shows correct ticket counts', (tester) async {
    setViewport(tester);
    repo.createTicket(title: 'Open 1');
    repo.createTicket(title: 'Open 2');
    repo.createTicket(title: 'Closed 1');
    repo.closeTicket(3, 'test', AuthorType.user);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // "3 tickets – 2 open – 1 closed" (en-dash U+2013)
    expect(
      find.text('3 tickets \u2013 2 open \u2013 1 closed'),
      findsOneWidget,
    );
  });

  // ---------------------------------------------------------------------------
  // 4. Empty state when no tickets
  // ---------------------------------------------------------------------------
  testWidgets('empty state when no tickets shows icon and create link', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Detail panel shows "No tickets" empty state with create link
    expect(find.text('Create your first ticket'), findsOneWidget);
    // Status bar shows zero counts
    expect(
      find.text('0 tickets \u2013 0 open \u2013 0 closed'),
      findsOneWidget,
    );
  });

  // ---------------------------------------------------------------------------
  // 5. Empty state when no selection
  // ---------------------------------------------------------------------------
  testWidgets('empty state when no selection shows select prompt', (tester) async {
    setViewport(tester);
    repo.createTicket(title: 'Some ticket');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Tickets exist but none selected → detail panel shows select prompt
    expect(find.text('Select a ticket to view details'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 6. Create mode: right side shows TicketCreateForm
  // ---------------------------------------------------------------------------
  testWidgets('create mode shows TicketCreateForm on the right', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Switch to create mode
    viewState.showCreateForm();
    await safePumpAndSettle(tester);

    // TicketCreateForm should be visible
    expect(find.byType(TicketCreateForm), findsOneWidget);
    expect(find.text('Create Ticket'), findsWidgets);

    // TicketDetailPanel should NOT be present
    expect(find.byType(TicketDetailPanel), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 7. Back to detail: after cancel, right side shows TicketDetailPanel
  // ---------------------------------------------------------------------------
  testWidgets('cancelling create form returns to detail view', (tester) async {
    setViewport(tester, height: 1200);
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Switch to create mode
    viewState.showCreateForm();
    await safePumpAndSettle(tester);

    // Verify we're in create mode
    expect(find.byType(TicketCreateForm), findsOneWidget);

    // Tap Cancel button
    await tester.tap(find.byKey(TicketCreateFormKeys.cancelButton));
    await safePumpAndSettle(tester);

    // Should be back to detail mode
    expect(viewState.detailMode, equals(TicketDetailMode.detail));
    expect(find.byType(TicketCreateForm), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 8. End-to-end create flow
  // ---------------------------------------------------------------------------
  testWidgets('end-to-end: click add, fill form, create, see ticket', (tester) async {
    setViewport(tester, height: 1200);
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Initially: empty list and detail empty state
    expect(find.text('No tickets'), findsWidgets);
    expect(find.text('Create your first ticket'), findsOneWidget);

    // Click (+) add button in list panel
    await tester.tap(find.byKey(TicketListPanelKeys.addButton));
    await safePumpAndSettle(tester);

    // Create form should be visible
    expect(find.byType(TicketCreateForm), findsOneWidget);

    // Fill in the title
    await tester.enterText(
      find.byKey(TicketCreateFormKeys.titleField),
      'Implement dark mode',
    );

    // Tap Create Ticket button
    await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
    await safePumpAndSettle(tester);

    // The ticket should have been created
    expect(repo.tickets.length, 1);
    expect(repo.tickets.first.title, 'Implement dark mode');

    // After creation, selectTicket is called which sets detail mode
    expect(viewState.detailMode, TicketDetailMode.detail);
    expect(viewState.selectedTicket, isNotNull);
    expect(viewState.selectedTicket!.title, 'Implement dark mode');

    // The detail panel should now show the ticket
    expect(find.byType(TicketDetailPanel), findsOneWidget);
    expect(find.byType(TicketCreateForm), findsNothing);

    // The ticket title should appear in both the list and the detail panel
    expect(find.text('Implement dark mode'), findsWidgets);

    // The ticket ID should appear
    expect(find.text('#1'), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 9. Open/closed counts track correctly (state-only test)
  // ---------------------------------------------------------------------------
  testWidgets('openCount and closedCount track tickets correctly', (tester) async {
    repo.createTicket(title: 'Open Task 1');
    repo.createTicket(title: 'Open Task 2');
    repo.createTicket(title: 'Will Close');
    repo.closeTicket(3, 'test', AuthorType.user);

    expect(viewState.openCount, equals(2));
    expect(viewState.closedCount, equals(1));
  });

  // ---------------------------------------------------------------------------
  // 10. Tapping a ticket shows detail panel
  // ---------------------------------------------------------------------------
  testWidgets('selecting a ticket shows its details in the right panel', (tester) async {
    setViewport(tester);
    repo.createTicket(title: 'Auth token refresh');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Initially no ticket selected, detail panel shows empty state
    expect(find.text('Select a ticket to view details'), findsOneWidget);

    // Tap the ticket in the list (not the checkbox)
    await tester.tap(find.text('Auth token refresh'));
    await safePumpAndSettle(tester);

    // Detail panel should show but checkbox should NOT be toggled
    expect(find.text('Select a ticket to view details'), findsNothing);
    expect(find.text('#1'), findsWidgets);
    expect(viewState.selectedTicketIds, isEmpty);
  });
}
