import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketBoardState ticketBoard;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    ticketBoard = resources.track(TicketBoardState('test-project'));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  Widget createTestApp() {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<TicketBoardState>.value(
          value: ticketBoard,
          child: const TicketDetailPanel(),
        ),
      ),
    );
  }

  group('TicketSplitDialog', () {
    testWidgets('split button shows for non-terminal tickets', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Active ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketDetailPanelKeys.splitButton),
        findsOneWidget,
      );
      expect(find.text('Split into subtasks'), findsOneWidget);
    });

    testWidgets('split button hidden for terminal tickets', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Completed ticket',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketDetailPanelKeys.splitButton),
        findsNothing,
      );
    });

    testWidgets('dialog renders with initial subtask row', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Open the dialog
      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // Dialog should be visible
      expect(find.byKey(TicketSplitDialogKeys.dialog), findsOneWidget);
      expect(find.text('Split TKT-001'), findsOneWidget);

      // Should have one subtask row
      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(0)),
        findsOneWidget,
      );

      // Should have add, cancel, split buttons
      expect(
        find.byKey(TicketSplitDialogKeys.addSubtaskButton),
        findsOneWidget,
      );
      expect(find.byKey(TicketSplitDialogKeys.cancelButton), findsOneWidget);
      expect(find.byKey(TicketSplitDialogKeys.splitButton), findsOneWidget);
    });

    testWidgets('add subtask button adds a new row', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // Initially one row
      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(0)),
        findsOneWidget,
      );
      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(1)),
        findsNothing,
      );

      // Add a subtask row
      await tester.tap(find.byKey(TicketSplitDialogKeys.addSubtaskButton));
      await safePumpAndSettle(tester);

      // Now two rows
      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(0)),
        findsOneWidget,
      );
      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(1)),
        findsOneWidget,
      );
    });

    testWidgets('remove subtask button removes a row', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // Add a second row so we can remove one (can't remove the last one)
      await tester.tap(find.byKey(TicketSplitDialogKeys.addSubtaskButton));
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(1)),
        findsOneWidget,
      );

      // Remove the second row
      await tester.tap(find.byKey(TicketSplitDialogKeys.subtaskRemove(1)));
      await safePumpAndSettle(tester);

      // Only one row remains
      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(0)),
        findsOneWidget,
      );
      expect(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(1)),
        findsNothing,
      );
    });

    testWidgets('remove button disabled when only one row', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // The remove button should be disabled (only one row)
      final removeButton = tester.widget<IconButton>(
        find.byKey(TicketSplitDialogKeys.subtaskRemove(0)),
      );
      expect(removeButton.onPressed, isNull);
    });

    testWidgets('split button disabled when all titles empty', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // Split button should be disabled (no title entered)
      final splitButton = tester.widget<FilledButton>(
        find.byKey(TicketSplitDialogKeys.splitButton),
      );
      expect(splitButton.onPressed, isNull);
    });

    testWidgets('split button creates tickets', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
        category: 'Frontend',
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Open dialog
      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // Enter a title for the first subtask
      await tester.enterText(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(0)),
        'Subtask Alpha',
      );
      await safePumpAndSettle(tester);

      // Add a second subtask
      await tester.tap(find.byKey(TicketSplitDialogKeys.addSubtaskButton));
      await safePumpAndSettle(tester);

      await tester.enterText(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(1)),
        'Subtask Beta',
      );
      await safePumpAndSettle(tester);

      // Tap Split
      await tester.tap(find.byKey(TicketSplitDialogKeys.splitButton));
      await safePumpAndSettle(tester);

      // Dialog should be dismissed
      expect(find.byKey(TicketSplitDialogKeys.dialog), findsNothing);

      // Parent should be split
      final parent = ticketBoard.getTicket(1)!;
      expect(parent.status, TicketStatus.split);
      expect(parent.kind, TicketKind.split);

      // Children should exist
      expect(ticketBoard.tickets.length, 3); // parent + 2 children
      final child1 = ticketBoard.getTicket(2)!;
      final child2 = ticketBoard.getTicket(3)!;

      expect(child1.title, 'Subtask Alpha');
      expect(child1.dependsOn, [1]);
      expect(child1.category, 'Frontend');
      expect(child1.priority, TicketPriority.high);

      expect(child2.title, 'Subtask Beta');
      expect(child2.dependsOn, [1]);
    });

    testWidgets('cancel button closes dialog without changes', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Open dialog
      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // Enter text
      await tester.enterText(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(0)),
        'Some subtask',
      );
      await safePumpAndSettle(tester);

      // Cancel
      await tester.tap(find.byKey(TicketSplitDialogKeys.cancelButton));
      await safePumpAndSettle(tester);

      // Dialog dismissed, no tickets created
      expect(find.byKey(TicketSplitDialogKeys.dialog), findsNothing);
      expect(ticketBoard.tickets.length, 1); // Only the original ticket
      expect(ticketBoard.getTicket(1)!.status, TicketStatus.ready);
    });

    testWidgets('empty title rows are skipped when splitting', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ticketBoard.createTicket(
        title: 'Feature to split',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Open dialog
      await tester.tap(find.byKey(TicketDetailPanelKeys.splitButton));
      await safePumpAndSettle(tester);

      // Add second row
      await tester.tap(find.byKey(TicketSplitDialogKeys.addSubtaskButton));
      await safePumpAndSettle(tester);

      // Only fill the second row, leave first empty
      await tester.enterText(
        find.byKey(TicketSplitDialogKeys.subtaskTitle(1)),
        'Only this subtask',
      );
      await safePumpAndSettle(tester);

      // Tap Split
      await tester.tap(find.byKey(TicketSplitDialogKeys.splitButton));
      await safePumpAndSettle(tester);

      // Only one child should be created (empty row skipped)
      expect(ticketBoard.tickets.length, 2); // parent + 1 child
      final child = ticketBoard.getTicket(2)!;
      expect(child.title, 'Only this subtask');
    });
  });
}
