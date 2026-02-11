import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_graph_view.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/widgets/ticket_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketBoardState ticketBoard;

  setUp(() {
    ticketBoard = resources.track(TicketBoardState('test-graph-view'));
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  Widget createTestApp({TicketBoardState? state}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 800,
          child: ChangeNotifierProvider<TicketBoardState>.value(
            value: state ?? ticketBoard,
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

    ticketBoard.createTicket(
      title: 'Setup database',
      kind: TicketKind.feature,
    );
    ticketBoard.createTicket(
      title: 'Build API layer',
      kind: TicketKind.feature,
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

    ticketBoard.createTicket(
      title: 'Implement authentication',
      kind: TicketKind.feature,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Display ID (TKT-001) should be shown
    expect(find.text('TKT-001'), findsOneWidget);
    // Title should be shown
    expect(find.text('Implement authentication'), findsOneWidget);
    // Status icon should be present
    expect(find.byType(TicketStatusIcon), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 4. Node selection calls selectTicket
  // ---------------------------------------------------------------------------
  testWidgets('tapping a node calls selectTicket', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    ticketBoard.createTicket(
      title: 'First ticket',
      kind: TicketKind.feature,
    );
    ticketBoard.createTicket(
      title: 'Second ticket',
      kind: TicketKind.bugfix,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    // Initially no ticket is selected
    expect(ticketBoard.selectedTicket, isNull);

    // Tap the first node
    await tester.tap(find.byKey(TicketGraphViewKeys.nodeKey(1)));
    await tester.pump();

    expect(ticketBoard.selectedTicket?.id, equals(1));
    expect(ticketBoard.selectedTicket?.title, equals('First ticket'));
  });

  // ---------------------------------------------------------------------------
  // 5. Selected node has different styling (highlight ring)
  // ---------------------------------------------------------------------------
  testWidgets('selected node has highlight border', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    ticketBoard.createTicket(
      title: 'My ticket',
      kind: TicketKind.feature,
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
    ticketBoard.selectTicket(1);
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

    ticketBoard.createTicket(
      title: 'Some ticket',
      kind: TicketKind.feature,
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
    ticketBoard.setViewMode(TicketViewMode.graph);

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(ticketBoard.viewMode, equals(TicketViewMode.graph));

    // Tap the List toggle
    await tester.tap(find.byKey(TicketGraphViewKeys.listToggle));
    await tester.pump();

    expect(ticketBoard.viewMode, equals(TicketViewMode.list));
  });

  // ---------------------------------------------------------------------------
  // 8. Ticket count label shows correct count
  // ---------------------------------------------------------------------------
  testWidgets('ticket count label shows correct count', (tester) async {
    ticketBoard.createTicket(
      title: 'Ticket A',
      kind: TicketKind.feature,
    );
    ticketBoard.createTicket(
      title: 'Ticket B',
      kind: TicketKind.bugfix,
    );
    ticketBoard.createTicket(
      title: 'Ticket C',
      kind: TicketKind.chore,
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

    ticketBoard.createTicket(
      title: 'Some ticket',
      kind: TicketKind.feature,
    );

    await tester.pumpWidget(createTestApp());
    await safePumpAndSettle(tester);

    expect(find.byKey(TicketGraphViewKeys.legend), findsOneWidget);
    // Legend should show status labels
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
}
