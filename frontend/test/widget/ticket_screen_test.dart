import 'dart:ui';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_create_form.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
import 'package:cc_insights_v2/panels/ticket_list_panel.dart';
import 'package:cc_insights_v2/screens/ticket_screen.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketBoardState ticketBoardState;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    ticketBoardState = resources.track(TicketBoardState('test-ticket-screen'));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  Widget createTestApp() {
    return MaterialApp(
      home: ChangeNotifierProvider<TicketBoardState>.value(
        value: ticketBoardState,
        child: const Scaffold(body: TicketScreen()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Renders without errors
  // ---------------------------------------------------------------------------
  testWidgets('renders without errors when wrapped in providers', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.byType(TicketScreen), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 2. Default view: TicketListPanel on left, TicketDetailPanel on right
  // ---------------------------------------------------------------------------
  testWidgets('default view shows TicketListPanel and TicketDetailPanel', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Left panel: TicketListPanel with 'Tickets' header
    expect(find.byType(TicketListPanel), findsOneWidget);
    expect(find.text('Tickets'), findsOneWidget);

    // Right panel: TicketDetailPanel with empty state
    expect(find.byType(TicketDetailPanel), findsOneWidget);
    expect(find.text('Select a ticket to view details'), findsOneWidget);

    // Create form should NOT be present
    expect(find.byType(TicketCreateForm), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 3. Create mode: right side shows TicketCreateForm
  // ---------------------------------------------------------------------------
  testWidgets('create mode shows TicketCreateForm on the right', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Switch to create mode
    ticketBoardState.showCreateForm();
    await safePumpAndSettle(tester);

    // TicketCreateForm should be visible
    expect(find.byType(TicketCreateForm), findsOneWidget);
    expect(find.text('Create Ticket'), findsWidgets);

    // TicketDetailPanel should NOT be present
    expect(find.byType(TicketDetailPanel), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 4. Back to detail: after cancel, right side shows TicketDetailPanel
  // ---------------------------------------------------------------------------
  testWidgets('cancelling create form returns to detail view', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Switch to create mode
    ticketBoardState.showCreateForm();
    await safePumpAndSettle(tester);

    // Verify we're in create mode
    expect(find.byType(TicketCreateForm), findsOneWidget);

    // Tap Cancel button
    await tester.tap(find.byKey(TicketCreateFormKeys.cancelButton));
    await safePumpAndSettle(tester);

    // Should be back to detail mode
    expect(ticketBoardState.detailMode, equals(TicketDetailMode.detail));
    expect(find.byType(TicketDetailPanel), findsOneWidget);
    expect(find.byType(TicketCreateForm), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 5. End-to-end create flow: (+) -> form -> fill title -> Create -> see in list and detail
  // ---------------------------------------------------------------------------
  testWidgets('end-to-end: click add, fill form, create, see ticket', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Initially: empty list and detail empty state
    expect(find.text('No tickets'), findsOneWidget);
    expect(find.text('Select a ticket to view details'), findsOneWidget);

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
    expect(ticketBoardState.tickets.length, 1);
    expect(ticketBoardState.tickets.first.title, 'Implement dark mode');

    // After creation, selectTicket is called which sets detail mode
    expect(ticketBoardState.detailMode, TicketDetailMode.detail);
    expect(ticketBoardState.selectedTicket, isNotNull);
    expect(ticketBoardState.selectedTicket!.title, 'Implement dark mode');

    // The detail panel should now show the ticket
    expect(find.byType(TicketDetailPanel), findsOneWidget);
    expect(find.byType(TicketCreateForm), findsNothing);

    // The ticket title should appear in both the list and the detail panel
    expect(find.text('Implement dark mode'), findsWidgets);

    // The ticket ID should appear
    expect(find.text('TKT-001'), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 6. Active ticket count (state-only test)
  // ---------------------------------------------------------------------------
  testWidgets('activeCount tracks active tickets correctly', (tester) async {
    ticketBoardState.createTicket(
      title: 'Active Task 1',
      kind: TicketKind.feature,
      status: TicketStatus.active,
    );
    ticketBoardState.createTicket(
      title: 'Active Task 2',
      kind: TicketKind.feature,
      status: TicketStatus.active,
    );
    ticketBoardState.createTicket(
      title: 'Completed Task',
      kind: TicketKind.feature,
      status: TicketStatus.completed,
    );

    expect(ticketBoardState.activeCount, equals(2));
  });

  // ---------------------------------------------------------------------------
  // 7. Selecting a ticket in list shows it in detail panel
  // ---------------------------------------------------------------------------
  testWidgets('selecting a ticket shows its details in the right panel', (tester) async {
    ticketBoardState.createTicket(
      title: 'Auth token refresh',
      kind: TicketKind.feature,
      category: 'Auth',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Initially no ticket selected, detail panel shows empty state
    expect(find.text('Select a ticket to view details'), findsOneWidget);

    // Tap the ticket in the list
    await tester.tap(find.text('Auth token refresh'));
    await safePumpAndSettle(tester);

    // Empty state should be gone
    expect(find.text('Select a ticket to view details'), findsNothing);

    // Ticket details should appear in the right panel
    expect(find.text('TKT-001'), findsWidgets);
  });
}
