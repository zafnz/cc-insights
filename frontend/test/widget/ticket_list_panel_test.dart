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
import 'package:cc_insights_v2/widgets/ticket_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late TicketViewState viewState;
  late ProjectState project;
  late SelectionState selection;
  late FakeGitService fakeGit;
  late TicketDispatchService dispatch;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    repo = resources.track(TicketRepository('test-project'));
    viewState = resources.track(TicketViewState(repo));
    fakeGit = FakeGitService();

    final primaryWorktree = WorktreeState(
      const WorktreeData(
        worktreeRoot: '/test/repo',
        isPrimary: true,
        branch: 'main',
      ),
    );

    project = resources.track(ProjectState(
      const ProjectData(name: 'test-project', repoRoot: '/test/repo'),
      primaryWorktree,
      autoValidate: false,
      watchFilesystem: false,
    ));

    selection = resources.track(SelectionState(project));

    final worktreeService = WorktreeService(
      gitService: fakeGit,
      configService: null,
    );

    dispatch = TicketDispatchService(
      ticketBoard: repo,
      project: project,
      selection: selection,
      worktreeService: worktreeService,
      restoreService: ProjectRestoreService(),
    );
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  Widget createTestApp({double width = 320}) {
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

  // ---------------------------------------------------------------------------
  // 1. Renders empty state
  // ---------------------------------------------------------------------------
  testWidgets('renders empty state when no tickets exist', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.text('No tickets'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 2. Renders tickets
  // ---------------------------------------------------------------------------
  testWidgets('renders tickets when they exist', (tester) async {
    repo.createTicket(
      title: 'Design auth model',
      kind: TicketKind.feature,
      category: 'Auth',
    );
    repo.createTicket(
      title: 'Implement login',
      kind: TicketKind.feature,
      category: 'Auth',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.text('Design auth model'), findsOneWidget);
    expect(find.text('Implement login'), findsOneWidget);
    expect(find.text('TKT-001'), findsOneWidget);
    expect(find.text('TKT-002'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 3. Search filters tickets
  // ---------------------------------------------------------------------------
  testWidgets('search filters the visible ticket list', (tester) async {
    repo.createTicket(
      title: 'Build auth flow',
      kind: TicketKind.feature,
      category: 'Auth',
    );
    repo.createTicket(
      title: 'Database schema',
      kind: TicketKind.feature,
      category: 'Data',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Both visible initially
    expect(find.text('Build auth flow'), findsOneWidget);
    expect(find.text('Database schema'), findsOneWidget);

    // Type in search field
    await tester.enterText(
      find.byKey(TicketListPanelKeys.searchField),
      'auth',
    );
    await safePumpAndSettle(tester);

    // Only matching ticket visible
    expect(find.text('Build auth flow'), findsOneWidget);
    expect(find.text('Database schema'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 4. Group headers show with correct counts
  // ---------------------------------------------------------------------------
  testWidgets('group headers show with correct counts', (tester) async {
    repo.createTicket(
      title: 'Task A',
      kind: TicketKind.feature,
      category: 'Auth',
      status: TicketStatus.completed,
    );
    repo.createTicket(
      title: 'Task B',
      kind: TicketKind.feature,
      category: 'Auth',
    );
    repo.createTicket(
      title: 'Task C',
      kind: TicketKind.feature,
      category: 'Data',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Group headers (uppercase)
    expect(find.text('AUTH'), findsOneWidget);
    expect(find.text('DATA'), findsOneWidget);

    // Counts: Auth has 1 completed / 2 total, Data has 0 / 1
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 5. Tapping a ticket toggles checkbox and selects for detail view
  // ---------------------------------------------------------------------------
  testWidgets('tapping a ticket item toggles its selection', (tester) async {
    repo.createTicket(
      title: 'Clickable ticket',
      kind: TicketKind.feature,
      category: 'Test',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(viewState.selectedTicketIds, isEmpty);
    expect(viewState.selectedTicket, isNull);

    await tester.tap(find.text('Clickable ticket'));
    await safePumpAndSettle(tester);

    expect(viewState.selectedTicketIds, contains(repo.tickets.first.id));
    expect(viewState.selectedTicket, isNotNull);
    expect(viewState.selectedTicket!.title, equals('Clickable ticket'));
  });

  // ---------------------------------------------------------------------------
  // 6. Selected ticket highlighting
  // ---------------------------------------------------------------------------
  testWidgets('selected ticket has highlighted background', (tester) async {
    repo.createTicket(
      title: 'Highlighted ticket',
      kind: TicketKind.feature,
      category: 'Test',
    );
    viewState.selectTicket(1);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Find the Material widget wrapping the selected ticket item.
    // The selected item should have primaryContainer background.
    final materialFinder = find.ancestor(
      of: find.text('Highlighted ticket'),
      matching: find.byType(Material),
    );
    expect(materialFinder, findsWidgets);

    // At least one Material ancestor should have a non-transparent color
    // (the selection highlight)
    final materials = tester.widgetList<Material>(materialFinder).toList();
    final hasHighlight = materials.any((m) =>
        m.color != null && m.color != Colors.transparent);
    expect(hasHighlight, isTrue);
  });

  // ---------------------------------------------------------------------------
  // 7. Add button calls showCreateForm
  // ---------------------------------------------------------------------------
  testWidgets('tapping add button switches to create mode', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(viewState.detailMode, equals(TicketDetailMode.detail));

    await tester.tap(find.byKey(TicketListPanelKeys.addButton));
    await safePumpAndSettle(tester);

    expect(viewState.detailMode, equals(TicketDetailMode.create));
  });

  // ---------------------------------------------------------------------------
  // 8. View toggle calls setViewMode
  // ---------------------------------------------------------------------------
  testWidgets('tapping graph toggle sets view mode to graph', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(viewState.viewMode, equals(TicketViewMode.list));

    await tester.tap(find.byKey(TicketListPanelKeys.graphViewToggle));
    await safePumpAndSettle(tester);

    expect(viewState.viewMode, equals(TicketViewMode.graph));
  });

  // ---------------------------------------------------------------------------
  // 9. Completed tickets are dimmed
  // ---------------------------------------------------------------------------
  testWidgets('completed tickets render with reduced opacity', (tester) async {
    repo.createTicket(
      title: 'Done task',
      kind: TicketKind.feature,
      category: 'Test',
      status: TicketStatus.completed,
    );
    repo.createTicket(
      title: 'Active task',
      kind: TicketKind.feature,
      category: 'Test',
      status: TicketStatus.active,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Find Opacity widgets wrapping each ticket
    final doneOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Done task'),
        matching: find.byType(Opacity),
      ).first,
    );
    final activeOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Active task'),
        matching: find.byType(Opacity),
      ).first,
    );

    expect(doneOpacity.opacity, equals(0.5));
    expect(activeOpacity.opacity, equals(1.0));
  });

  // ---------------------------------------------------------------------------
  // 10. Status icons correct
  // ---------------------------------------------------------------------------
  testWidgets('each status shows the correct icon', (tester) async {
    repo.createTicket(
      title: 'Ready ticket',
      kind: TicketKind.feature,
      category: 'Test',
      status: TicketStatus.ready,
    );
    repo.createTicket(
      title: 'Active ticket',
      kind: TicketKind.feature,
      category: 'Test',
      status: TicketStatus.active,
    );
    repo.createTicket(
      title: 'Completed ticket',
      kind: TicketKind.feature,
      category: 'Test',
      status: TicketStatus.completed,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Verify that the correct icons are present
    expect(
      find.byIcon(TicketStatusVisuals.icon(TicketStatus.ready)),
      findsWidgets,
    );
    expect(
      find.byIcon(TicketStatusVisuals.icon(TicketStatus.active)),
      findsWidgets,
    );
    expect(
      find.byIcon(TicketStatusVisuals.icon(TicketStatus.completed)),
      findsWidgets,
    );

    // Specifically: radio_button_unchecked for ready, play_circle_outline for
    // active, check_circle_outline for completed
    expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);
    expect(find.byIcon(Icons.play_circle_outline), findsWidgets);
    expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // Start Next Button Tests
  // ---------------------------------------------------------------------------
  testWidgets('start next button is disabled when no ready tickets exist', (tester) async {
    repo.createTicket(
      title: 'Active ticket',
      kind: TicketKind.feature,
      status: TicketStatus.active,
    );
    repo.createTicket(
      title: 'Completed ticket',
      kind: TicketKind.feature,
      status: TicketStatus.completed,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    final button = tester.widget<IconButton>(
      find.byKey(TicketListPanelKeys.startNextButton),
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('start next button is enabled when ready tickets exist', (tester) async {
    repo.createTicket(
      title: 'Ready ticket',
      kind: TicketKind.feature,
      status: TicketStatus.ready,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    final button = tester.widget<IconButton>(
      find.byKey(TicketListPanelKeys.startNextButton),
    );

    expect(button.onPressed, isNotNull);
  });

  testWidgets('start next button shows correct tooltip when disabled', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    final button = tester.widget<IconButton>(
      find.byKey(TicketListPanelKeys.startNextButton),
    );

    expect(button.tooltip, 'No ready tickets');
  });

  testWidgets('start next button shows next ticket ID in tooltip', (tester) async {
    repo.createTicket(
      title: 'Low priority',
      kind: TicketKind.feature,
      status: TicketStatus.ready,
      priority: TicketPriority.low,
    );
    final critical = repo.createTicket(
      title: 'Critical priority',
      kind: TicketKind.feature,
      status: TicketStatus.ready,
      priority: TicketPriority.critical,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    final button = tester.widget<IconButton>(
      find.byKey(TicketListPanelKeys.startNextButton),
    );

    expect(button.tooltip, 'Start next: ${critical.displayId}');
  });

  testWidgets('start next button picks highest priority ticket', (tester) async {
    repo.createTicket(
      title: 'Low priority',
      kind: TicketKind.feature,
      status: TicketStatus.ready,
      priority: TicketPriority.low,
    );
    repo.createTicket(
      title: 'Medium priority',
      kind: TicketKind.feature,
      status: TicketStatus.ready,
      priority: TicketPriority.medium,
    );
    final critical = repo.createTicket(
      title: 'Critical priority',
      kind: TicketKind.feature,
      status: TicketStatus.ready,
      priority: TicketPriority.critical,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    final button = tester.widget<IconButton>(
      find.byKey(TicketListPanelKeys.startNextButton),
    );

    // Verify tooltip shows the critical ticket
    expect(button.tooltip, 'Start next: ${critical.displayId}');
  });

  // ---------------------------------------------------------------------------
  // Bulk Change Button Tests
  // ---------------------------------------------------------------------------
  testWidgets('bulk change button is hidden when no tickets are selected', (tester) async {
    repo.createTicket(
      title: 'Some ticket',
      kind: TicketKind.feature,
    );


    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    expect(find.byKey(TicketListPanelKeys.bulkChangeButton), findsNothing);
  });

  testWidgets('bulk change button appears when tickets are selected', (tester) async {
    repo.createTicket(
      title: 'Task A',
      kind: TicketKind.feature,
    );

    viewState.toggleTicketSelected(1);

    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    expect(find.byKey(TicketListPanelKeys.bulkChangeButton), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('bulk change button opens popup with all menu items', (tester) async {
    repo.createTicket(
      title: 'Task A',
      kind: TicketKind.feature,
    );
    repo.createTicket(
      title: 'Task B',
      kind: TicketKind.bugfix,
    );

    viewState.toggleTicketSelected(1);
    viewState.toggleTicketSelected(2);

    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    // Tap the Change button to open the popup menu
    await tester.tap(find.byKey(TicketListPanelKeys.bulkChangeButton));
    await safePumpAndSettle(tester);

    // Verify all menu items are shown.
    // "Category" also appears in the group-by dropdown label, so expect 2.
    expect(find.text('Category'), findsNWidgets(2));
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Kind'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('bulk change button disappears when selection is cleared', (tester) async {
    repo.createTicket(
      title: 'Task A',
      kind: TicketKind.feature,
    );

    viewState.toggleTicketSelected(1);

    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    expect(find.byKey(TicketListPanelKeys.bulkChangeButton), findsOneWidget);

    // Deselect the ticket
    viewState.toggleTicketSelected(1);
    await safePumpAndSettle(tester);

    expect(find.byKey(TicketListPanelKeys.bulkChangeButton), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Bulk Delete Tests
  // ---------------------------------------------------------------------------
  testWidgets('bulk delete shows confirmation dialog', (tester) async {
    repo.createTicket(title: 'Task A', kind: TicketKind.feature);
    repo.createTicket(title: 'Task B', kind: TicketKind.bugfix);
    viewState.setMultiSelectEnabled(true);
    viewState.toggleTicketSelected(1);
    viewState.toggleTicketSelected(2);

    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    // Open the Change menu
    await tester.tap(find.byKey(TicketListPanelKeys.bulkChangeButton));
    await safePumpAndSettle(tester);

    // Tap Delete
    await tester.tap(find.text('Delete'));
    await safePumpAndSettle(tester);

    // Confirmation dialog should appear
    expect(find.text('Delete tickets'), findsOneWidget);
    expect(
      find.text('Are you sure you want to delete 2 tickets?'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    // 'Delete' appears in the dialog button
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('bulk delete confirmation deletes selected tickets', (tester) async {
    repo.createTicket(title: 'Task A', kind: TicketKind.feature);
    repo.createTicket(title: 'Task B', kind: TicketKind.bugfix);
    repo.createTicket(title: 'Task C', kind: TicketKind.feature);
    viewState.setMultiSelectEnabled(true);
    viewState.toggleTicketSelected(1);
    viewState.toggleTicketSelected(2);

    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    expect(repo.tickets.length, 3);

    // Open menu and tap Delete
    await tester.tap(find.byKey(TicketListPanelKeys.bulkChangeButton));
    await safePumpAndSettle(tester);
    await tester.tap(find.text('Delete'));
    await safePumpAndSettle(tester);

    // Confirm deletion
    await tester.tap(find.text('Delete'));
    await safePumpAndSettle(tester);

    // Only unselected ticket remains
    expect(repo.tickets.length, 1);
    expect(repo.tickets.first.title, 'Task C');

    // Selection should be cleared
    expect(viewState.selectedTicketIds, isEmpty);
  });

  testWidgets('bulk delete cancel preserves tickets', (tester) async {
    repo.createTicket(title: 'Task A', kind: TicketKind.feature);
    repo.createTicket(title: 'Task B', kind: TicketKind.bugfix);
    viewState.setMultiSelectEnabled(true);
    viewState.toggleTicketSelected(1);
    viewState.toggleTicketSelected(2);

    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    // Open menu and tap Delete
    await tester.tap(find.byKey(TicketListPanelKeys.bulkChangeButton));
    await safePumpAndSettle(tester);
    await tester.tap(find.text('Delete'));
    await safePumpAndSettle(tester);

    // Cancel
    await tester.tap(find.text('Cancel'));
    await safePumpAndSettle(tester);

    // All tickets still exist
    expect(repo.tickets.length, 2);

    // Selection still intact
    expect(viewState.selectedTicketIds, {1, 2});
  });

  testWidgets('bulk delete clears dependsOn references', (tester) async {
    final t1 = repo.createTicket(title: 'Dep', kind: TicketKind.feature);
    repo.createTicket(
      title: 'Dependent',
      kind: TicketKind.feature,
      dependsOn: [t1.id],
    );
    viewState.setMultiSelectEnabled(true);
    viewState.toggleTicketSelected(t1.id);

    await tester.pumpWidget(createTestApp(width: 500));
    await safePumpAndSettle(tester);

    // Open menu and tap Delete
    await tester.tap(find.byKey(TicketListPanelKeys.bulkChangeButton));
    await safePumpAndSettle(tester);
    await tester.tap(find.text('Delete'));
    await safePumpAndSettle(tester);

    // Confirm
    await tester.tap(find.text('Delete'));
    await safePumpAndSettle(tester);

    // Remaining ticket should have empty dependsOn
    expect(repo.tickets.length, 1);
    expect(repo.tickets.first.title, 'Dependent');
    expect(repo.tickets.first.dependsOn, isEmpty);
  });
}
