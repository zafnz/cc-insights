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
import 'package:cc_insights_v2/widgets/ticket_edit_form.dart';
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

      // Initially: empty list (both panels show "No tickets")
      expect(find.text('No tickets'), findsWidgets);
      expect(find.text('Select a ticket to view details'), findsNothing);

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

      // Fill in the body
      await tester.enterText(
        find.byKey(TicketCreateFormKeys.bodyField),
        'A test ticket body',
      );

      // Tap Create Ticket button
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await safePumpAndSettle(tester);

      // Ticket should have been created
      expect(repo.tickets.length, 1);
      expect(repo.tickets.first.title, 'Test Ticket');
      expect(repo.tickets.first.body, 'A test ticket body');

      // After creation, selectTicket is called which sets detail mode
      expect(viewState.detailMode, TicketDetailMode.detail);
      expect(viewState.selectedTicket, isNotNull);
      expect(viewState.selectedTicket!.title, 'Test Ticket');

      // The detail panel should now show the ticket
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.byType(TicketCreateForm), findsNothing);

      // The ticket title should appear in the detail panel header
      expect(find.textContaining('Test Ticket'), findsWidgets);

      // The ticket ID should appear in the list subtitle (#1 as plain text)
      expect(find.text('#1'), findsWidgets);
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

      // Create 3 tickets without tags so find.text() can match title text
      repo.createTicket(title: 'Implement auth login');
      repo.createTicket(title: 'Fix database migration');
      repo.createTicket(title: 'Auth token refresh');

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // All 3 tickets should be visible
      expect(find.textContaining('Implement auth login'), findsWidgets);
      expect(find.textContaining('Fix database migration'), findsWidgets);
      expect(find.textContaining('Auth token refresh'), findsWidgets);

      // Type search query
      await tester.enterText(
        find.byKey(TicketListPanelKeys.searchField),
        'auth',
      );
      await safePumpAndSettle(tester);

      // Only matching tickets should be visible
      expect(find.textContaining('Implement auth login'), findsWidgets);
      expect(find.textContaining('Fix database migration'), findsNothing);
      expect(find.textContaining('Auth token refresh'), findsWidgets);

      // Clear search by entering empty text
      await tester.enterText(
        find.byKey(TicketListPanelKeys.searchField),
        '',
      );
      await safePumpAndSettle(tester);

      // All tickets visible again
      expect(find.textContaining('Implement auth login'), findsWidgets);
      expect(find.textContaining('Fix database migration'), findsWidgets);
      expect(find.textContaining('Auth token refresh'), findsWidgets);
    });
  });

  // ===========================================================================
  // 3. Filter flow (open/closed)
  // ===========================================================================
  group('Filter flow', () {
    testWidgets(
        'create open and closed tickets -> filter by isOpen -> verify',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create open and closed tickets (no tags so find.textContaining works)
      repo.createTicket(title: 'Open task');
      repo.createTicket(title: 'Closed task');
      repo.createTicket(title: 'Another open task');

      // Close the second ticket
      repo.closeTicket(2, 'test-user', AuthorType.user);

      // Default filter shows open tickets
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Only open tickets should be visible (default isOpenFilter = true)
      expect(find.textContaining('Open task'), findsWidgets);
      expect(find.textContaining('Closed task'), findsNothing);
      expect(find.textContaining('Another open task'), findsWidgets);

      // Switch to showing closed tickets
      viewState.setIsOpenFilter(false);
      await safePumpAndSettle(tester);

      // Only closed ticket should be visible
      expect(find.textContaining('Open task'), findsNothing);
      expect(find.textContaining('Closed task'), findsWidgets);
      expect(find.textContaining('Another open task'), findsNothing);

      // Switch back to open tickets
      viewState.setIsOpenFilter(true);
      await safePumpAndSettle(tester);

      // Open tasks should be visible again
      expect(find.textContaining('Open task'), findsWidgets);
      expect(find.textContaining('Closed task'), findsNothing);
      expect(find.textContaining('Another open task'), findsWidgets);
    });
  });

  // ===========================================================================
  // 4. Tag filter flow
  // ===========================================================================
  group('Tag filter flow', () {
    testWidgets(
        'create tickets with different tags -> filter by tag -> verify',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      repo.createTicket(title: 'Auth flow', tags: {'auth', 'feature'});
      repo.createTicket(title: 'DB schema', tags: {'data', 'feature'});
      repo.createTicket(title: 'Auth tests', tags: {'auth', 'test'});

      // Apply tag filter programmatically
      viewState.addTagFilter('auth');

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Only auth-tagged tickets should be visible
      expect(find.textContaining('Auth flow'), findsWidgets);
      expect(find.textContaining('DB schema'), findsNothing);
      expect(find.textContaining('Auth tests'), findsWidgets);

      // Clear the tag filter
      viewState.clearTagFilters();
      await safePumpAndSettle(tester);

      // All tasks should be visible again
      expect(find.textContaining('Auth flow'), findsWidgets);
      expect(find.textContaining('DB schema'), findsWidgets);
      expect(find.textContaining('Auth tests'), findsWidgets);
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
      repo.createTicket(title: 'Original Title');
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Detail panel should be showing the ticket
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.textContaining('Original Title'), findsWidgets);

      // Tap the Edit button shown in the issue header
      await tester.tap(find.text('Edit'));
      await safePumpAndSettle(tester);

      // Should now be in edit mode (TicketEditForm is shown inside TicketDetailPanel)
      expect(find.byType(TicketEditForm), findsOneWidget);

      // Change the title (TicketEditForm has no key on the title field;
      // use the first TextField in the form, which is the title input)
      await tester.enterText(
        find.byType(TextField).first,
        'Updated Title',
      );

      // Tap Save to commit changes
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // Should be back in detail mode
      expect(find.byType(TicketDetailPanel), findsOneWidget);
      expect(find.byType(TicketEditForm), findsNothing);

      // Verify the title is updated in the state
      expect(repo.getTicket(1)!.title, 'Updated Title');

      // The updated title should appear in the UI
      expect(find.textContaining('Updated Title'), findsWidgets);
      expect(find.textContaining('Original Title'), findsNothing);
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
      repo.createTicket(title: 'Ticket to delete');
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Verify ticket is visible in the list
      expect(find.textContaining('Ticket to delete'), findsWidgets);
      expect(repo.tickets.length, 1);

      // Delete via state (deleteTicket method)
      repo.deleteTicket(1);
      await safePumpAndSettle(tester);

      // Ticket should be removed from state
      expect(repo.tickets.length, 0);
      expect(viewState.selectedTicket, isNull);

      // Ticket should no longer appear in the list
      expect(find.textContaining('Ticket to delete'), findsNothing);

      // Empty state should be shown
      expect(find.text('No tickets'), findsWidgets);
    });
  });

  // ===========================================================================
  // 7. Dependency management (state-level)
  // ===========================================================================
  group('Dependency management', () {
    testWidgets(
        'create #1 and #2 -> add dependency -> '
        'verify in detail and getBlockedBy', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create two tickets
      repo.createTicket(title: 'Foundation work');
      repo.createTicket(title: 'Feature that depends on foundation');

      // #2 depends on #1
      repo.addDependency(2, 1);

      // Verify #2 has the dependency
      final ticket2 = repo.getTicket(2);
      expect(ticket2!.dependsOn, [1]);

      // Verify #1's getBlockedBy shows #2
      final blockedBy = repo.getBlockedBy(1);
      expect(blockedBy, [2]);

      // Select #2 and render the screen
      viewState.selectTicket(2);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // The detail panel should show the "DEPENDS ON" section header
      expect(find.text('DEPENDS ON'), findsOneWidget);
      // The dependency tile shows '#1' as plain text
      expect(find.text('#1'), findsWidgets);

      // Now select #1 to check its "BLOCKS" section
      viewState.selectTicket(1);
      await safePumpAndSettle(tester);

      // #1's detail should show "BLOCKS" with #2
      expect(find.text('BLOCKS'), findsOneWidget);
      expect(find.text('#2'), findsWidgets);
    });
  });

  // ===========================================================================
  // 8. Cycle prevention (state-only)
  // ===========================================================================
  group('Cycle prevention', () {
    test('A -> B -> C, then C -> A is rejected', () {
      final testRepo = resources.track(TicketRepository('test-cycle'));

      final a = testRepo.createTicket(title: 'A');
      final b = testRepo.createTicket(title: 'B');
      final c = testRepo.createTicket(title: 'C');

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

      final a = testRepo.createTicket(title: 'A');
      final b = testRepo.createTicket(title: 'B');

      testRepo.addDependency(a.id, b.id);

      expect(
        () => testRepo.addDependency(b.id, a.id),
        throwsArgumentError,
      );
    });

    test('self-reference is rejected', () {
      final testRepo = resources.track(TicketRepository('test-cycle-self'));

      final a = testRepo.createTicket(title: 'A');

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
        body: 'Alpha body',
        tags: {'ui', 'critical'},
      );
      testRepo.createTicket(
        title: 'Ticket Beta',
        body: 'Beta body',
        tags: {'backend'},
      );
      testRepo.createTicket(
        title: 'Ticket Gamma',
        tags: {'research'},
      );

      // Close Ticket Beta to verify open/closed state round-trips
      testRepo.closeTicket(2, 'test-user', AuthorType.user);

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
      expect(alpha.body, 'Alpha body');
      expect(alpha.isOpen, isTrue);
      expect(alpha.tags, containsAll(['ui', 'critical']));

      // Verify Ticket Beta
      final beta = testRepo2.getTicket(2);
      expect(beta, isNotNull);
      expect(beta!.title, 'Ticket Beta');
      expect(beta.body, 'Beta body');
      expect(beta.isOpen, isFalse);
      expect(beta.tags, containsAll(['backend']));

      // Verify Ticket Gamma with dependency
      final gamma = testRepo2.getTicket(3);
      expect(gamma, isNotNull);
      expect(gamma!.title, 'Ticket Gamma');
      expect(gamma.tags, containsAll(['research']));
      expect(gamma.dependsOn, [1]);

      // Verify nextId is preserved (next ticket should be ID 4)
      final newTicket = testRepo2.createTicket(title: 'Ticket Delta');
      expect(newTicket.id, 4);
    });
  });
}
