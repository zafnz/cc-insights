import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_graph_view.dart';
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

  setUp(() {
    repo = resources.track(TicketRepository('test-graph-view'));
    viewState = resources.track(TicketViewState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  Widget createTestApp() {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 800,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<TicketRepository>.value(value: repo),
              ChangeNotifierProvider<TicketViewState>.value(value: viewState),
            ],
            child: const TicketGraphView(),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Renders nodes when tickets exist
  // ---------------------------------------------------------------------------
  testWidgets('renders graph nodes when tickets exist', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    repo.createTicket(
      title: 'Setup database',
    );
    repo.createTicket(
      title: 'Build API layer',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Both node keys should be present
    expect(
      find.byKey(TicketGraphViewKeys.nodeKey(1)),
      findsOneWidget,
    );
    expect(
      find.byKey(TicketGraphViewKeys.nodeKey(2)),
      findsOneWidget,
    );

    // Ticket titles should be visible
    expect(find.text('Setup database'), findsOneWidget);
    expect(find.text('Build API layer'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 2. Empty state when no tickets
  // ---------------------------------------------------------------------------
  testWidgets('shows empty state when no tickets exist', (tester) async {
    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(
      find.byKey(TicketGraphViewKeys.emptyState),
      findsOneWidget,
    );
    expect(find.text('No tickets to display'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 3. Node shows ticket info (display ID and title)
  // ---------------------------------------------------------------------------
  testWidgets('node shows ticket display ID and title', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    repo.createTicket(
      title: 'Implement authentication',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Display ID (#1) should be shown
    expect(find.text('#1'), findsOneWidget);
    // Title should be shown
    expect(find.text('Implement authentication'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 4. Node selection calls selectTicket
  // ---------------------------------------------------------------------------
  testWidgets('tapping a node calls selectTicket', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    repo.createTicket(
      title: 'First ticket',
    );
    repo.createTicket(
      title: 'Second ticket',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Initially no ticket is selected
    expect(viewState.selectedTicket, isNull);

    // Tap the first node
    await tester.tap(find.byKey(TicketGraphViewKeys.nodeKey(1)));
    await tester.pump();

    expect(viewState.selectedTicket?.id, equals(1));
    expect(viewState.selectedTicket?.title, equals('First ticket'));
  });

  // ---------------------------------------------------------------------------
  // 5. Selected node has different styling (highlight ring)
  // ---------------------------------------------------------------------------
  testWidgets('selected node has highlight border', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    repo.createTicket(
      title: 'My ticket',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Helper to find the decorated Container inside the node.
    // The node's key is on the GestureDetector; the first child Container
    // has the BoxDecoration with the border.
    Container findNodeContainer() {
      final nodeFinder = find.byKey(TicketGraphViewKeys.nodeKey(1));
      final containers = find.descendant(
        of: nodeFinder,
        matching: find.byType(Container),
      );
      // Find the container that has a BoxDecoration with a Border
      for (final element in containers.evaluate()) {
        final widget = element.widget as Container;
        final decoration = widget.decoration;
        if (decoration is BoxDecoration && decoration.border is Border) {
          return widget;
        }
      }
      fail('Could not find decorated Container in node');
    }

    // Before selection: border width 1.0
    final containerBefore = findNodeContainer();
    final borderBefore =
        (containerBefore.decoration as BoxDecoration).border as Border;
    expect(borderBefore.top.width, equals(1.0));

    // Select the ticket
    viewState.selectTicket(1);
    await tester.pump();

    // After selection: border width 2.0
    final containerAfter = findNodeContainer();
    final borderAfter =
        (containerAfter.decoration as BoxDecoration).border as Border;
    expect(borderAfter.top.width, equals(2.0));
  });

  // ---------------------------------------------------------------------------
  // 6. Zoom buttons change the transform
  // ---------------------------------------------------------------------------
  testWidgets('zoom in and zoom out buttons change the transform', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    repo.createTicket(
      title: 'Some ticket',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Find the InteractiveViewer to read its controller's value
    final interactiveViewer = tester.widget<InteractiveViewer>(
      find.byKey(TicketGraphViewKeys.interactiveViewer),
    );
    final controller = interactiveViewer.transformationController!;
    final initialScale = controller.value.getMaxScaleOnAxis();

    // Tap zoom in
    await tester.tap(find.byKey(TicketGraphViewKeys.zoomIn));
    await tester.pump();

    final scaleAfterZoomIn = controller.value.getMaxScaleOnAxis();
    expect(scaleAfterZoomIn, greaterThan(initialScale));

    // Tap zoom out
    await tester.tap(find.byKey(TicketGraphViewKeys.zoomOut));
    await tester.pump();

    final scaleAfterZoomOut = controller.value.getMaxScaleOnAxis();
    expect(scaleAfterZoomOut, lessThan(scaleAfterZoomIn));
  });

  // ---------------------------------------------------------------------------
  // 7. View toggle: tapping List calls setViewMode(list)
  // ---------------------------------------------------------------------------
  testWidgets('tapping List toggle calls setViewMode(list)', (tester) async {
    // Start in graph mode
    viewState.setViewMode(TicketViewMode.graph);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(viewState.viewMode, equals(TicketViewMode.graph));

    // Tap the List toggle
    await tester.tap(find.byKey(TicketGraphViewKeys.listToggle));
    await tester.pump();

    expect(viewState.viewMode, equals(TicketViewMode.list));
  });

  // ---------------------------------------------------------------------------
  // 8. Ticket count label shows correct count
  // ---------------------------------------------------------------------------
  testWidgets('ticket count label shows correct count', (tester) async {
    repo.createTicket(
      title: 'Ticket A',
    );
    repo.createTicket(
      title: 'Ticket B',
    );
    repo.createTicket(
      title: 'Ticket C',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.text('3 tickets'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 9. Legend is displayed
  // ---------------------------------------------------------------------------
  testWidgets('legend overlay is displayed with status labels', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    repo.createTicket(
      title: 'Some ticket',
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.byKey(TicketGraphViewKeys.legend), findsOneWidget);
    // Legend should show Open/Closed labels
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
  });
}
