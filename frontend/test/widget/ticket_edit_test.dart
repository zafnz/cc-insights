import 'dart:ui';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_create_form.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
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
    repo = resources.track(TicketRepository('test-edit'));
    viewState = resources.track(TicketViewState(repo));
    bulkState = resources.track(BulkProposalState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  /// Creates a test app with the full TicketScreen for end-to-end edit flows.
  Widget createScreenTestApp() {
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

  /// Creates a test app with just the TicketCreateForm for isolated edit tests.
  Widget createEditFormTestApp(TicketData ticket) {
    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<TicketRepository>.value(value: repo),
            ChangeNotifierProvider<TicketViewState>.value(value: viewState),
          ],
          child: TicketCreateForm(editingTicket: ticket),
        ),
      ),
    );
  }

  group('Ticket Editing', () {
    // -------------------------------------------------------------------------
    // 1. Edit button switches to edit mode
    // -------------------------------------------------------------------------
    testWidgets('edit button switches to edit mode', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      repo.createTicket(
        title: 'Test ticket for editing',
        kind: TicketKind.feature,
        priority: TicketPriority.high,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createScreenTestApp());
      await safePumpAndSettle(tester);

      // Detail panel should be showing
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.text('Test ticket for editing'), findsWidgets);

      // Tap the edit button
      await tester.tap(find.byKey(TicketDetailPanelKeys.editButton));
      await safePumpAndSettle(tester);

      // Should switch to edit mode, showing the form
      expect(viewState.detailMode, TicketDetailMode.edit);
      expect(find.byType(TicketCreateForm), findsOneWidget);
      expect(find.text('Edit Ticket'), findsOneWidget);

      // Detail panel should no longer be visible
      expect(find.byType(TicketDetailPanel), findsNothing);
    });

    // -------------------------------------------------------------------------
    // 2. Fields are pre-populated
    // -------------------------------------------------------------------------
    testWidgets('fields are pre-populated with ticket values', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'Pre-populated title',
        kind: TicketKind.bugfix,
        priority: TicketPriority.critical,
        effort: TicketEffort.large,
        category: 'Backend',
        description: 'A detailed description of the bug.',
        tags: {'urgent', 'backend'},
      );

      await tester.pumpWidget(createEditFormTestApp(ticket));
      await safePumpAndSettle(tester);

      // Title
      final titleField = tester.widget<TextField>(find.byKey(TicketCreateFormKeys.titleField));
      expect(titleField.controller?.text, 'Pre-populated title');

      // Description
      final descField = tester.widget<TextField>(find.byKey(TicketCreateFormKeys.descriptionField));
      expect(descField.controller?.text, 'A detailed description of the bug.');

      // Kind dropdown shows Bug Fix
      expect(find.text('Bug Fix'), findsOneWidget);

      // Priority dropdown shows Critical
      expect(find.text('Critical'), findsOneWidget);

      // Status dropdown is visible in edit mode
      expect(find.byKey(TicketCreateFormKeys.statusDropdown), findsOneWidget);

      // Tags are shown as chips
      expect(find.text('urgent'), findsOneWidget);
      expect(find.text('backend'), findsOneWidget);

      // Header says Edit Ticket
      expect(find.text('Edit Ticket'), findsOneWidget);

      // Button says Save Changes
      expect(find.text('Save Changes'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 3. Save applies changes
    // -------------------------------------------------------------------------
    testWidgets('save applies changes to the ticket', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'Original title',
        kind: TicketKind.feature,
        priority: TicketPriority.medium,
        description: 'Original description',
      );

      await tester.pumpWidget(createEditFormTestApp(ticket));
      await safePumpAndSettle(tester);

      // Clear and change the title
      await tester.enterText(
        find.byKey(TicketCreateFormKeys.titleField),
        'Updated title',
      );

      // Clear and change the description
      await tester.enterText(
        find.byKey(TicketCreateFormKeys.descriptionField),
        'Updated description',
      );

      // Tap Save Changes
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await safePumpAndSettle(tester);

      // Verify the ticket was updated
      final updated = repo.getTicket(ticket.id);
      expect(updated, isNotNull);
      expect(updated!.title, 'Updated title');
      expect(updated.description, 'Updated description');

      // Should have selected the ticket and returned to detail mode
      expect(viewState.selectedTicket?.id, ticket.id);
      expect(viewState.detailMode, TicketDetailMode.detail);
    });

    // -------------------------------------------------------------------------
    // 4. Cancel reverts without saving
    // -------------------------------------------------------------------------
    testWidgets('cancel returns to detail mode without saving', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'Unchanged title',
        kind: TicketKind.feature,
        priority: TicketPriority.medium,
      );

      // Switch to edit mode so we can verify the cancel reverts
      viewState.selectTicket(ticket.id);
      viewState.setDetailMode(TicketDetailMode.edit);

      await tester.pumpWidget(createEditFormTestApp(ticket));
      await safePumpAndSettle(tester);

      // Change the title in the form
      await tester.enterText(
        find.byKey(TicketCreateFormKeys.titleField),
        'Changed but not saved',
      );

      // Tap Cancel
      await tester.tap(find.byKey(TicketCreateFormKeys.cancelButton));
      await safePumpAndSettle(tester);

      // Detail mode should be restored
      expect(viewState.detailMode, TicketDetailMode.detail);

      // Ticket should NOT have been updated
      final unchanged = repo.getTicket(ticket.id);
      expect(unchanged!.title, 'Unchanged title');
    });

    // -------------------------------------------------------------------------
    // 5. Status change persists
    // -------------------------------------------------------------------------
    testWidgets('changing status in edit mode persists', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'Status change test',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );

      await tester.pumpWidget(createEditFormTestApp(ticket));
      await safePumpAndSettle(tester);

      // Status dropdown should show Ready
      expect(find.text('Ready'), findsOneWidget);

      // Tap the status dropdown
      await tester.tap(find.byKey(TicketCreateFormKeys.statusDropdown));
      await tester.pump();

      // Select Active
      await tester.tap(find.text('Active').last);
      await safePumpAndSettle(tester);

      // Tap Save Changes
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await safePumpAndSettle(tester);

      // Verify the status was updated
      final updated = repo.getTicket(ticket.id);
      expect(updated!.status, TicketStatus.active);
    });

    // -------------------------------------------------------------------------
    // 6. End-to-end: detail -> edit -> save -> detail
    // -------------------------------------------------------------------------
    testWidgets('end-to-end: detail to edit to save to detail', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      repo.createTicket(
        title: 'E2E edit test',
        kind: TicketKind.feature,
        priority: TicketPriority.low,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createScreenTestApp());
      await safePumpAndSettle(tester);

      // Start in detail mode
      expect(find.byType(TicketDetailPanel), findsOneWidget);

      // Tap Edit button
      await tester.tap(find.byKey(TicketDetailPanelKeys.editButton));
      await safePumpAndSettle(tester);

      // Should be in edit mode
      expect(find.byType(TicketCreateForm), findsOneWidget);
      expect(find.text('Edit Ticket'), findsOneWidget);

      // Change the title
      await tester.enterText(
        find.byKey(TicketCreateFormKeys.titleField),
        'E2E edit updated',
      );

      // Tap Save Changes
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await safePumpAndSettle(tester);

      // Should be back in detail mode
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.byType(TicketCreateForm), findsNothing);

      // The updated title should show in the detail panel
      expect(find.text('E2E edit updated'), findsWidgets);

      // Verify state
      expect(repo.getTicket(1)!.title, 'E2E edit updated');
    });

    // -------------------------------------------------------------------------
    // 7. Status dropdown is NOT visible in create mode
    // -------------------------------------------------------------------------
    testWidgets('status dropdown not visible in create mode', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<TicketRepository>.value(value: repo),
              ChangeNotifierProvider<TicketViewState>.value(value: viewState),
            ],
            child: const TicketCreateForm(),
          ),
        ),
      ));
      await safePumpAndSettle(tester);

      // Status dropdown should NOT be visible
      expect(find.byKey(TicketCreateFormKeys.statusDropdown), findsNothing);

      // Create Ticket header and button
      expect(find.text('Create Ticket'), findsWidgets);
      expect(find.text('Save Changes'), findsNothing);
    });
  });
}
