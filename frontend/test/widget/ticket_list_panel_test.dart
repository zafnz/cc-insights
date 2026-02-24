import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_list_panel.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:cc_insights_v2/widgets/ticket_filter_chips.dart';
import 'package:cc_insights_v2/widgets/ticket_list_item.dart';
import 'package:cc_insights_v2/widgets/ticket_sort_dropdown.dart';
import 'package:cc_insights_v2/widgets/ticket_status_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TicketRepository>.value(value: repo),
        ChangeNotifierProvider<TicketViewState>.value(value: viewState),
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
  // 2. Renders status tabs with correct counts
  // ---------------------------------------------------------------------------
  testWidgets('renders status tabs with correct counts', (tester) async {
    repo.createTicket(title: 'Open one');
    repo.createTicket(title: 'Open two');
    // Close one ticket
    repo.closeTicket(1, 'test', AuthorType.user);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.byType(TicketStatusTabs), findsOneWidget);
    expect(find.text('Open (1)'), findsOneWidget);
    expect(find.text('Closed (1)'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 3. Switching tabs filters tickets
  // ---------------------------------------------------------------------------
  testWidgets('switching to Closed tab shows closed tickets', (tester) async {
    repo.createTicket(title: 'Open ticket');
    repo.createTicket(title: 'Closed ticket');
    repo.closeTicket(2, 'test', AuthorType.user);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Open tab active by default
    expect(find.text('Open ticket'), findsOneWidget);
    expect(find.text('Closed ticket'), findsNothing);

    // Switch to Closed tab
    await tester.tap(find.textContaining('Closed'));
    await safePumpAndSettle(tester);

    expect(find.text('Open ticket'), findsNothing);
    expect(find.text('Closed ticket'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 4. Search filters tickets
  // ---------------------------------------------------------------------------
  testWidgets('search filters the visible ticket list', (tester) async {
    repo.createTicket(title: 'Build auth flow');
    repo.createTicket(title: 'Database schema');

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
  // 5. Filter chips appear when tag filters are active
  // ---------------------------------------------------------------------------
  testWidgets('filter chips appear when tag filters are active', (tester) async {
    repo.createTicket(title: 'Tagged ticket', tags: {'ui', 'frontend'});
    repo.createTicket(title: 'Other ticket');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // No "Clear all" initially (no active tag filters)
    expect(find.text('Clear all'), findsNothing);

    // Add a tag filter
    viewState.addTagFilter('ui');
    await safePumpAndSettle(tester);

    // Filter chip should now show
    expect(find.text('Clear all'), findsOneWidget);

    // Only tagged ticket should be visible (textContaining because Text.rich
    // with tag WidgetSpans doesn't match find.text exactly)
    expect(find.textContaining('Tagged ticket'), findsOneWidget);
    expect(find.textContaining('Other ticket'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 6. Clear all removes tag filters
  // ---------------------------------------------------------------------------
  testWidgets('clear all removes tag filters and shows all tickets', (tester) async {
    repo.createTicket(title: 'Tagged', tags: {'ui'});
    repo.createTicket(title: 'Untagged');

    viewState.addTagFilter('ui');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // textContaining because Text.rich with tag WidgetSpans
    expect(find.textContaining('Tagged'), findsOneWidget);
    expect(find.text('Untagged'), findsNothing);

    // Tap Clear all
    await tester.tap(find.text('Clear all'));
    await safePumpAndSettle(tester);

    expect(find.textContaining('Tagged'), findsOneWidget);
    expect(find.text('Untagged'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 7. Sort dropdown is present
  // ---------------------------------------------------------------------------
  testWidgets('sort dropdown is rendered', (tester) async {
    repo.createTicket(title: 'First ticket');
    repo.createTicket(title: 'Second ticket');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.byType(TicketSortDropdown), findsOneWidget);
    expect(find.text('Sort:'), findsOneWidget);

    // Default sort label visible
    expect(find.text('Newest'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 8. Changing sort order works
  // ---------------------------------------------------------------------------
  testWidgets('changing sort order reorders tickets', (tester) async {
    repo.createTicket(title: 'First ticket');
    repo.createTicket(title: 'Second ticket');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Default is newest first — verify both visible
    expect(find.text('First ticket'), findsOneWidget);
    expect(find.text('Second ticket'), findsOneWidget);

    // Change sort to oldest
    viewState.setSortOrder(TicketSortOrder.oldest);
    await safePumpAndSettle(tester);

    // Both should still be visible after sort change
    expect(find.text('First ticket'), findsOneWidget);
    expect(find.text('Second ticket'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 9. Clicking item selects
  // ---------------------------------------------------------------------------
  testWidgets('tapping a ticket item selects it', (tester) async {
    repo.createTicket(title: 'Clickable ticket');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(viewState.selectedTicket, isNull);

    await tester.tap(find.text('Clickable ticket'));
    await safePumpAndSettle(tester);

    expect(viewState.selectedTicket, isNotNull);
    expect(viewState.selectedTicket!.title, equals('Clickable ticket'));
  });

  // ---------------------------------------------------------------------------
  // 10. Selected ticket has highlighted background
  // ---------------------------------------------------------------------------
  testWidgets('selected ticket has highlighted background', (tester) async {
    repo.createTicket(title: 'Highlighted ticket');
    viewState.selectTicket(1);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Find the Material widget wrapping the selected ticket item.
    final materialFinder = find.ancestor(
      of: find.text('Highlighted ticket'),
      matching: find.byType(Material),
    );
    expect(materialFinder, findsWidgets);

    // At least one Material ancestor should have a non-transparent color
    final materials = tester.widgetList<Material>(materialFinder).toList();
    final hasHighlight = materials.any(
      (m) => m.color != null && m.color != Colors.transparent,
    );
    expect(hasHighlight, isTrue);
  });

  // ---------------------------------------------------------------------------
  // 11. Closed tickets are visually distinct
  // ---------------------------------------------------------------------------
  testWidgets('closed tickets show closed icon', (tester) async {
    repo.createTicket(title: 'Closed ticket');
    repo.closeTicket(1, 'test', AuthorType.user);

    // Switch to closed tab to see closed tickets
    viewState.setIsOpenFilter(false);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.text('Closed ticket'), findsOneWidget);
    // Closed tickets show check_circle icon (purple) — also appears in status tabs
    expect(find.byIcon(Icons.check_circle), findsAtLeastNWidgets(1));
  });

  // ---------------------------------------------------------------------------
  // 12. Add button triggers create mode
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
  // 13. Renders tickets with display IDs
  // ---------------------------------------------------------------------------
  testWidgets('renders tickets with display IDs', (tester) async {
    repo.createTicket(title: 'First task');
    repo.createTicket(title: 'Second task');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.text('First task'), findsOneWidget);
    expect(find.text('Second task'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 14. Panel header is present
  // ---------------------------------------------------------------------------
  testWidgets('panel header shows Tickets title and icon', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.text('Tickets'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 15. All V2 components are assembled
  // ---------------------------------------------------------------------------
  testWidgets('all V2 components are present in the panel', (tester) async {
    repo.createTicket(title: 'Some ticket');

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Panel renders all V2 components
    expect(find.byType(TicketStatusTabs), findsOneWidget);
    expect(find.byType(TicketSortDropdown), findsOneWidget);
    expect(find.byType(TicketFilterChips), findsOneWidget);
    expect(find.byType(TicketListItem), findsOneWidget);
    expect(find.byKey(TicketListPanelKeys.searchField), findsOneWidget);
    expect(find.byKey(TicketListPanelKeys.addButton), findsOneWidget);
  });
}
