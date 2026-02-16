import 'dart:ui';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_create_form.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
import 'package:cc_insights_v2/panels/ticket_list_panel.dart';
import 'package:cc_insights_v2/screens/ticket_screen.dart';
import 'package:cc_insights_v2/services/ticket_storage_service.dart';
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
    repo = resources.track(TicketRepository('test-integration'));
    viewState = resources.track(TicketViewState(repo));
    bulkState = resources.track(BulkProposalState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  /// Creates a test app with the full TicketScreen layout.
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

  // ===========================================================================
  // 1. Full creation flow
  // ===========================================================================
  group('Full creation flow', () {
    testWidgets(
        'navigate to tickets -> click (+) -> fill form -> create -> '
        'verify in list and detail', (tester) async {
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
        'Test Ticket',
      );

      // Fill in the description
      await tester.enterText(
        find.byKey(TicketCreateFormKeys.descriptionField),
        'A test ticket description',
      );

      // Change kind to bugfix by tapping the dropdown
      await tester.tap(find.byKey(TicketCreateFormKeys.kindDropdown));
      await tester.pump();
      await tester.tap(find.text('Bug Fix').last);
      await safePumpAndSettle(tester);

      // Tap Create Ticket button
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await safePumpAndSettle(tester);

      // Ticket should have been created
      expect(repo.tickets.length, 1);
      expect(repo.tickets.first.title, 'Test Ticket');
      expect(repo.tickets.first.kind, TicketKind.bugfix);
      expect(repo.tickets.first.description,
          'A test ticket description');

      // After creation, selectTicket is called which sets detail mode
      expect(viewState.detailMode, TicketDetailMode.detail);
      expect(viewState.selectedTicket, isNotNull);
      expect(viewState.selectedTicket!.title, 'Test Ticket');

      // The detail panel should now show the ticket
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.byType(TicketCreateForm), findsNothing);

      // The ticket title should appear in both the list and the detail panel
      expect(find.text('Test Ticket'), findsWidgets);

      // The ticket ID should appear
      expect(find.text('TKT-001'), findsWidgets);
    });
  });

  // ===========================================================================
  // 2. Search flow
  // ===========================================================================
  group('Search flow', () {
    testWidgets(
        'create 3 tickets -> search -> verify filtering -> clear -> all visible',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create 3 tickets with different titles
      repo.createTicket(
        title: 'Implement auth login',
        kind: TicketKind.feature,
        category: 'Auth',
      );
      repo.createTicket(
        title: 'Fix database migration',
        kind: TicketKind.bugfix,
        category: 'Data',
      );
      repo.createTicket(
        title: 'Auth token refresh',
        kind: TicketKind.feature,
        category: 'Auth',
      );

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // All 3 tickets should be visible
      expect(find.text('Implement auth login'), findsOneWidget);
      expect(find.text('Fix database migration'), findsOneWidget);
      expect(find.text('Auth token refresh'), findsOneWidget);

      // Type search query
      await tester.enterText(
        find.byKey(TicketListPanelKeys.searchField),
        'auth',
      );
      await safePumpAndSettle(tester);

      // Only matching tickets should be visible
      expect(find.text('Implement auth login'), findsOneWidget);
      expect(find.text('Fix database migration'), findsNothing);
      expect(find.text('Auth token refresh'), findsOneWidget);

      // Clear search by entering empty text
      await tester.enterText(
        find.byKey(TicketListPanelKeys.searchField),
        '',
      );
      await safePumpAndSettle(tester);

      // All tickets visible again
      expect(find.text('Implement auth login'), findsOneWidget);
      expect(find.text('Fix database migration'), findsOneWidget);
      expect(find.text('Auth token refresh'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 3. Filter flow
  // ===========================================================================
  group('Filter flow', () {
    testWidgets(
        'create tickets with different statuses -> filter by status -> verify',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create tickets with different statuses
      repo.createTicket(
        title: 'Active task',
        kind: TicketKind.feature,
        status: TicketStatus.active,
        category: 'Work',
      );
      repo.createTicket(
        title: 'Completed task',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
        category: 'Work',
      );
      repo.createTicket(
        title: 'Ready task',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        category: 'Work',
      );

      // Apply status filter programmatically (UI filter via popup menu is
      // complex to test; we verify state integration instead)
      viewState.setStatusFilter(TicketStatus.active);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Only the active task should be visible
      expect(find.text('Active task'), findsOneWidget);
      expect(find.text('Completed task'), findsNothing);
      expect(find.text('Ready task'), findsNothing);

      // Clear the filter
      viewState.setStatusFilter(null);
      await safePumpAndSettle(tester);

      // All tasks should be visible again
      expect(find.text('Active task'), findsOneWidget);
      expect(find.text('Completed task'), findsOneWidget);
      expect(find.text('Ready task'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. Group-by switching
  // ===========================================================================
  group('Group-by switching', () {
    testWidgets(
        'create tickets in different categories -> verify category groups -> '
        'switch to status -> verify groups change', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create tickets in different categories
      repo.createTicket(
        title: 'Auth flow',
        kind: TicketKind.feature,
        category: 'Auth',
        status: TicketStatus.active,
      );
      repo.createTicket(
        title: 'DB schema',
        kind: TicketKind.feature,
        category: 'Data',
        status: TicketStatus.ready,
      );
      repo.createTicket(
        title: 'Auth tests',
        kind: TicketKind.test,
        category: 'Auth',
        status: TicketStatus.ready,
      );

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Default groupBy is category - verify category group headers (uppercase)
      expect(find.text('AUTH'), findsOneWidget);
      expect(find.text('DATA'), findsOneWidget);

      // Switch group-by to status programmatically
      viewState.setGroupBy(TicketGroupBy.status);
      await safePumpAndSettle(tester);

      // Category headers should be gone, status headers should appear
      expect(find.text('AUTH'), findsNothing);
      expect(find.text('DATA'), findsNothing);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 5. Edit flow
  // ===========================================================================
  group('Edit flow', () {
    testWidgets(
        'create ticket -> select -> edit -> change title -> save -> '
        'verify updated in list and detail', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create a ticket
      repo.createTicket(
        title: 'Original Title',
        kind: TicketKind.feature,
        category: 'Frontend',
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Detail panel should be showing the ticket
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.text('Original Title'), findsWidgets);

      // Tap the edit button
      await tester.tap(find.byKey(TicketDetailPanelKeys.editButton));
      await safePumpAndSettle(tester);

      // Should now be in edit mode
      expect(find.byType(TicketCreateForm), findsOneWidget);
      expect(find.text('Edit Ticket'), findsOneWidget);

      // Change the title
      await tester.enterText(
        find.byKey(TicketCreateFormKeys.titleField),
        'Updated Title',
      );

      // Tap Save Changes
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await safePumpAndSettle(tester);

      // Should be back in detail mode
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.byType(TicketCreateForm), findsNothing);

      // Verify the title is updated in the state
      expect(repo.getTicket(1)!.title, 'Updated Title');

      // The updated title should appear in the UI
      expect(find.text('Updated Title'), findsWidgets);
      expect(find.text('Original Title'), findsNothing);
    });
  });

  // ===========================================================================
  // 6. Delete flow
  // ===========================================================================
  group('Delete flow', () {
    testWidgets('create ticket -> select -> delete -> verify removed',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create a ticket
      repo.createTicket(
        title: 'Ticket to delete',
        kind: TicketKind.feature,
        category: 'Cleanup',
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Verify ticket is visible in the list
      expect(find.text('Ticket to delete'), findsWidgets);
      expect(repo.tickets.length, 1);

      // Delete via state (deleteTicket method)
      repo.deleteTicket(1);
      await safePumpAndSettle(tester);

      // Ticket should be removed from state
      expect(repo.tickets.length, 0);
      expect(viewState.selectedTicket, isNull);

      // Ticket should no longer appear in the list
      expect(find.text('Ticket to delete'), findsNothing);

      // Empty state should be shown
      expect(find.text('No tickets'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 7. Dependency management (state-level)
  // ===========================================================================
  group('Dependency management', () {
    testWidgets(
        'create TKT-001 and TKT-002 -> add dependency -> '
        'verify in detail and getBlockedBy', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create two tickets
      repo.createTicket(
        title: 'Foundation work',
        kind: TicketKind.feature,
        category: 'Core',
      );
      repo.createTicket(
        title: 'Feature that depends on foundation',
        kind: TicketKind.feature,
        category: 'Core',
      );

      // TKT-002 depends on TKT-001
      repo.addDependency(2, 1);

      // Verify TKT-002 has the dependency
      final ticket2 = repo.getTicket(2);
      expect(ticket2!.dependsOn, [1]);

      // Verify TKT-001's getBlockedBy shows TKT-002
      final blockedBy = repo.getBlockedBy(1);
      expect(blockedBy, [2]);

      // Select TKT-002 and render the screen
      viewState.selectTicket(2);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // The detail panel should show the dependency section with TKT-001
      expect(find.text('Depends on'), findsOneWidget);
      expect(find.text('TKT-001'), findsWidgets);

      // Now select TKT-001 to check its "Blocks" section
      viewState.selectTicket(1);
      await safePumpAndSettle(tester);

      // TKT-001's detail should show "Blocks" with TKT-002
      expect(find.text('Blocks'), findsOneWidget);
      expect(find.text('TKT-002'), findsWidgets);
    });
  });

  // ===========================================================================
  // 8. Cycle prevention (state-only)
  // ===========================================================================
  group('Cycle prevention', () {
    test('A -> B -> C, then C -> A is rejected', () {
      final testRepo = resources.track(TicketRepository('test-cycle'));

      final a = testRepo.createTicket(title: 'A', kind: TicketKind.feature);
      final b = testRepo.createTicket(title: 'B', kind: TicketKind.feature);
      final c = testRepo.createTicket(title: 'C', kind: TicketKind.feature);

      // A depends on B
      testRepo.addDependency(a.id, b.id);
      // B depends on C
      testRepo.addDependency(b.id, c.id);

      // C depends on A should create a cycle and be rejected
      expect(
        () => testRepo.addDependency(c.id, a.id),
        throwsArgumentError,
      );

      // Verify C has no dependencies (the cycle was prevented)
      expect(testRepo.getTicket(c.id)!.dependsOn, isEmpty);
    });

    test('direct cycle A -> B, B -> A is rejected', () {
      final testRepo = resources.track(TicketRepository('test-cycle-direct'));

      final a = testRepo.createTicket(title: 'A', kind: TicketKind.feature);
      final b = testRepo.createTicket(title: 'B', kind: TicketKind.feature);

      testRepo.addDependency(a.id, b.id);

      expect(
        () => testRepo.addDependency(b.id, a.id),
        throwsArgumentError,
      );
    });

    test('self-reference is rejected', () {
      final testRepo = resources.track(TicketRepository('test-cycle-self'));

      final a = testRepo.createTicket(title: 'A', kind: TicketKind.feature);

      expect(
        () => testRepo.addDependency(a.id, a.id),
        throwsArgumentError,
      );
    });
  });

  // ===========================================================================
  // 9. Persistence round-trip
  // ===========================================================================
  group('Persistence round-trip', () {
    test('create tickets -> save -> reload -> all restored', () async {
      final testProjectId =
          'test-integration-persist-${DateTime.now().millisecondsSinceEpoch}';
      final storage = TicketStorageService();
      final testRepo = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );

      // Create tickets with varying fields
      testRepo.createTicket(
        title: 'Ticket Alpha',
        kind: TicketKind.feature,
        priority: TicketPriority.high,
        effort: TicketEffort.large,
        category: 'Frontend',
        description: 'Alpha description',
        tags: {'ui', 'critical'},
      );
      testRepo.createTicket(
        title: 'Ticket Beta',
        kind: TicketKind.bugfix,
        status: TicketStatus.active,
        priority: TicketPriority.low,
        effort: TicketEffort.small,
        category: 'Backend',
        description: 'Beta description',
      );
      testRepo.createTicket(
        title: 'Ticket Gamma',
        kind: TicketKind.research,
        priority: TicketPriority.medium,
        effort: TicketEffort.medium,
      );

      // Add a dependency: Gamma depends on Alpha
      testRepo.addDependency(3, 1);

      // Explicitly save
      await testRepo.save();

      // Small delay to ensure file system writes complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Create a new state instance and load from storage
      final testRepo2 = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );
      await testRepo2.load();

      // Verify all tickets were restored
      expect(testRepo2.tickets.length, 3);

      // Verify Ticket Alpha
      final alpha = testRepo2.getTicket(1);
      expect(alpha, isNotNull);
      expect(alpha!.title, 'Ticket Alpha');
      expect(alpha.kind, TicketKind.feature);
      expect(alpha.priority, TicketPriority.high);
      expect(alpha.effort, TicketEffort.large);
      expect(alpha.category, 'Frontend');
      expect(alpha.description, 'Alpha description');
      expect(alpha.tags, containsAll(['ui', 'critical']));

      // Verify Ticket Beta
      final beta = testRepo2.getTicket(2);
      expect(beta, isNotNull);
      expect(beta!.title, 'Ticket Beta');
      expect(beta.kind, TicketKind.bugfix);
      expect(beta.status, TicketStatus.active);
      expect(beta.priority, TicketPriority.low);
      expect(beta.effort, TicketEffort.small);
      expect(beta.category, 'Backend');

      // Verify Ticket Gamma with dependency
      final gamma = testRepo2.getTicket(3);
      expect(gamma, isNotNull);
      expect(gamma!.title, 'Ticket Gamma');
      expect(gamma.kind, TicketKind.research);
      expect(gamma.dependsOn, [1]);

      // Verify nextId is preserved (next ticket should be ID 4)
      final newTicket = testRepo2.createTicket(
        title: 'Ticket Delta',
        kind: TicketKind.feature,
      );
      expect(newTicket.id, 4);
    });
  });
}
