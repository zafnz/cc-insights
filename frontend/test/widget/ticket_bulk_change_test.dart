import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/ticket_list_panel.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:cc_insights_v2/services/ticket_dispatch_service.dart';
import 'package:cc_insights_v2/services/worktree_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late TicketViewState viewState;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    repo = resources.track(TicketRepository('test-project'));
    viewState = resources.track(TicketViewState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  Widget createTestApp({double width = 500}) {
    final fakeGit = FakeGitService();
    final primaryWorktree = WorktreeState(
      const WorktreeData(
        worktreeRoot: '/test/repo',
        isPrimary: true,
        branch: 'main',
      ),
    );
    final project = resources.track(ProjectState(
      const ProjectData(name: 'test-project', repoRoot: '/test/repo'),
      primaryWorktree,
      autoValidate: false,
      watchFilesystem: false,
    ));
    final selection = resources.track(SelectionState(project));
    final worktreeService = WorktreeService(
      gitService: fakeGit,
      configService: null,
    );
    final dispatch = TicketDispatchService(
      ticketBoard: repo,
      project: project,
      selection: selection,
      worktreeService: worktreeService,
      restoreService: ProjectRestoreService(),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TicketRepository>.value(value: repo),
        ChangeNotifierProvider<TicketViewState>.value(value: viewState),
        Provider<TicketDispatchService>.value(value: dispatch),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 600,
            child: const TicketListPanel(),
          ),
        ),
      ),
    );
  }

  /// Helper: set up two tickets and select them for bulk operations.
  void setupSelectedTickets() {
    repo.createTicket(
      title: 'Task A',
      kind: TicketKind.feature,
      priority: TicketPriority.low,
      category: 'Backend',
    );
    repo.createTicket(
      title: 'Task B',
      kind: TicketKind.bugfix,
      priority: TicketPriority.medium,
      category: 'Frontend',
    );
    viewState.setMultiSelectEnabled(true);
    viewState.toggleTicketSelected(1);
    viewState.toggleTicketSelected(2);
  }

  /// Helper: open the bulk change popup and tap a menu item.
  Future<void> openBulkChangeAndTap(
    WidgetTester tester,
    String menuItemText,
  ) async {
    await tester.tap(find.byKey(TicketListPanelKeys.bulkChangeButton));
    await safePumpAndSettle(tester);
    // The menu item text may appear multiple times (e.g. "Category" in group-by).
    // Tap the last occurrence which is the popup menu item.
    await tester.tap(find.text(menuItemText).last);
    await safePumpAndSettle(tester);
  }

  // ---------------------------------------------------------------------------
  // Bulk change status
  // ---------------------------------------------------------------------------
  group('bulk change status', () {
    testWidgets('applies status change to all selected tickets', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Open Change menu and tap Status
      await openBulkChangeAndTap(tester, 'Status');

      // Status picker dialog should appear with all status values
      expect(find.text('Change status'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Pick "Completed"
      await tester.tap(find.text('Completed'));
      await safePumpAndSettle(tester);

      // Confirmation dialog should appear
      expect(find.text('Confirm bulk change'), findsOneWidget);
      expect(
        find.textContaining('change status to Completed for 2 tickets'),
        findsOneWidget,
      );

      // Confirm (use widgetWithText to avoid ambiguity with toolbar "Change")
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await safePumpAndSettle(tester);

      // Verify both tickets have status updated
      expect(repo.getTicket(1)!.status, equals(TicketStatus.completed));
      expect(repo.getTicket(2)!.status, equals(TicketStatus.completed));
    });

    testWidgets('cancelling confirmation does not apply status change', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Status');

      // Pick "Active"
      await tester.tap(find.text('Active'));
      await safePumpAndSettle(tester);

      // Cancel the confirmation
      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      // Verify status is unchanged (both should still be ready)
      expect(repo.getTicket(1)!.status, equals(TicketStatus.ready));
      expect(repo.getTicket(2)!.status, equals(TicketStatus.ready));
    });
  });

  // ---------------------------------------------------------------------------
  // Bulk change kind
  // ---------------------------------------------------------------------------
  group('bulk change kind', () {
    testWidgets('applies kind change to all selected tickets', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Kind');

      // Kind picker should appear
      expect(find.text('Change kind'), findsOneWidget);

      // Pick "Research"
      await tester.tap(find.text('Research'));
      await safePumpAndSettle(tester);

      // Confirm
      expect(
        find.textContaining('change kind to Research for 2 tickets'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await safePumpAndSettle(tester);

      expect(repo.getTicket(1)!.kind, equals(TicketKind.research));
      expect(repo.getTicket(2)!.kind, equals(TicketKind.research));
    });
  });

  // ---------------------------------------------------------------------------
  // Bulk change priority
  // ---------------------------------------------------------------------------
  group('bulk change priority', () {
    testWidgets('applies priority change to all selected tickets', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Priority');

      // Priority picker should appear
      expect(find.text('Change priority'), findsOneWidget);

      // Pick "Critical"
      await tester.tap(find.text('Critical'));
      await safePumpAndSettle(tester);

      // Confirm
      expect(
        find.textContaining('change priority to Critical for 2 tickets'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await safePumpAndSettle(tester);

      expect(repo.getTicket(1)!.priority, equals(TicketPriority.critical));
      expect(repo.getTicket(2)!.priority, equals(TicketPriority.critical));
    });
  });

  // ---------------------------------------------------------------------------
  // Bulk change category
  // ---------------------------------------------------------------------------
  group('bulk change category', () {
    testWidgets('applies existing category to all selected tickets', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Category');

      // Category picker should show existing categories
      expect(find.text('Change category'), findsOneWidget);
      expect(find.text('Backend'), findsOneWidget);
      expect(find.text('Frontend'), findsOneWidget);

      // Pick "Backend"
      await tester.tap(find.text('Backend'));
      await safePumpAndSettle(tester);

      // Confirm
      expect(
        find.textContaining('change category to Backend for 2 tickets'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await safePumpAndSettle(tester);

      expect(repo.getTicket(1)!.category, equals('Backend'));
      expect(repo.getTicket(2)!.category, equals('Backend'));
    });

    testWidgets('applies new custom category via text field', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Category');

      // Enter a new category in the text field
      await tester.enterText(find.byType(TextField).last, 'DevOps');
      await safePumpAndSettle(tester);

      // Tap OK to submit
      await tester.tap(find.text('OK'));
      await safePumpAndSettle(tester);

      // Confirm
      expect(
        find.textContaining('change category to DevOps for 2 tickets'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await safePumpAndSettle(tester);

      expect(repo.getTicket(1)!.category, equals('DevOps'));
      expect(repo.getTicket(2)!.category, equals('DevOps'));
    });
  });

  // ---------------------------------------------------------------------------
  // Bulk delete
  // ---------------------------------------------------------------------------
  group('bulk delete', () {
    testWidgets('deletes all selected tickets after confirmation', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Delete');

      // Confirm dialog should appear
      expect(find.text('Confirm bulk delete'), findsOneWidget);
      expect(
        find.textContaining('delete 2 tickets'),
        findsOneWidget,
      );

      // Confirm
      await tester.tap(find.text('Delete'));
      await safePumpAndSettle(tester);

      // Verify tickets are deleted
      expect(repo.getTicket(1), isNull);
      expect(repo.getTicket(2), isNull);
      expect(repo.tickets, isEmpty);
      expect(viewState.selectedTicketIds, isEmpty);
    });

    testWidgets('cancelling delete confirmation preserves tickets', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Delete');

      // Cancel
      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      // Tickets should still exist
      expect(repo.getTicket(1), isNotNull);
      expect(repo.getTicket(2), isNotNull);
      expect(repo.tickets.length, equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Dismissing picker dialog
  // ---------------------------------------------------------------------------
  group('dismissing picker dialog', () {
    testWidgets('dismissing status picker does not change tickets', (tester) async {
      setupSelectedTickets();
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await openBulkChangeAndTap(tester, 'Status');

      // Dismiss by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await safePumpAndSettle(tester);

      // Tickets unchanged
      expect(repo.getTicket(1)!.status, equals(TicketStatus.ready));
      expect(repo.getTicket(2)!.status, equals(TicketStatus.ready));
    });
  });
}
