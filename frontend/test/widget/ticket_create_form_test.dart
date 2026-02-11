import 'dart:ui';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_create_form.dart';
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
    ticketBoardState = resources.track(TicketBoardState('test-create-form'));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  Widget createTestApp() {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<TicketBoardState>.value(
          value: ticketBoardState,
          child: const TicketCreateForm(),
        ),
      ),
    );
  }

  group('TicketCreateForm', () {
    testWidgets('renders all fields', (tester) async {
      // Use a tall surface to avoid off-screen issues
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Header
      expect(find.byIcon(Icons.add_task), findsOneWidget);

      // Title field
      expect(find.byKey(TicketCreateFormKeys.titleField), findsOneWidget);

      // Kind dropdown
      expect(find.byKey(TicketCreateFormKeys.kindDropdown), findsOneWidget);

      // Priority dropdown
      expect(find.byKey(TicketCreateFormKeys.priorityDropdown), findsOneWidget);

      // Category field
      expect(find.byKey(TicketCreateFormKeys.categoryField), findsOneWidget);

      // Description field
      expect(find.byKey(TicketCreateFormKeys.descriptionField), findsOneWidget);

      // Effort selector
      expect(find.byKey(TicketCreateFormKeys.effortSelector), findsOneWidget);

      // Tags area (hint text for tag input)
      expect(find.text('Type to add...'), findsOneWidget);

      // Dependencies area (hint text for dep search)
      expect(find.text('Search tickets...'), findsOneWidget);

      // Action buttons
      expect(find.byKey(TicketCreateFormKeys.cancelButton), findsOneWidget);
      expect(find.byKey(TicketCreateFormKeys.createButton), findsOneWidget);
    });

    testWidgets('title is required - shows error when empty', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap Create without entering a title
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      // Should show validation error
      expect(find.text('Title is required.'), findsOneWidget);

      // No ticket should have been created
      expect(ticketBoardState.tickets, isEmpty);
    });

    testWidgets('kind dropdown shows all values', (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap the kind dropdown to open it
      await tester.tap(find.byKey(TicketCreateFormKeys.kindDropdown));
      await tester.pump();

      // All TicketKind values should be visible in the dropdown
      for (final kind in TicketKind.values) {
        expect(find.text(kind.label), findsWidgets);
      }
    });

    testWidgets('priority dropdown shows all values', (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap the priority dropdown to open it
      await tester.tap(find.byKey(TicketCreateFormKeys.priorityDropdown));
      await tester.pump();

      // All TicketPriority values should be visible in the dropdown
      for (final priority in TicketPriority.values) {
        expect(find.text(priority.label), findsWidgets);
      }
    });

    testWidgets('effort selector works', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap 'small' to change selection
      await tester.tap(find.text('small'));
      await tester.pump();

      // Now tap 'large'
      await tester.tap(find.text('large'));
      await tester.pump();

      // Enter a title so we can create the ticket to verify effort
      await tester.enterText(find.byKey(TicketCreateFormKeys.titleField), 'Test effort');

      // Tap Create
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      expect(ticketBoardState.tickets.length, 1);
      expect(ticketBoardState.tickets.first.effort, TicketEffort.large);
    });

    testWidgets('cancel calls showDetail', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Set mode to create first so we can verify it changes
      ticketBoardState.showCreateForm();
      expect(ticketBoardState.detailMode, TicketDetailMode.create);

      // Tap Cancel
      await tester.tap(find.byKey(TicketCreateFormKeys.cancelButton));
      await tester.pump();

      // Should switch to detail mode
      expect(ticketBoardState.detailMode, TicketDetailMode.detail);
    });

    testWidgets('create ticket with title', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Enter a title
      await tester.enterText(find.byKey(TicketCreateFormKeys.titleField), 'My new ticket');

      // Tap Create
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      // Ticket should be created
      expect(ticketBoardState.tickets.length, 1);
      expect(ticketBoardState.tickets.first.title, 'My new ticket');
      expect(ticketBoardState.tickets.first.kind, TicketKind.feature);
      expect(ticketBoardState.tickets.first.priority, TicketPriority.medium);
      expect(ticketBoardState.tickets.first.effort, TicketEffort.medium);
    });

    testWidgets('created ticket is selected', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Enter a title
      await tester.enterText(find.byKey(TicketCreateFormKeys.titleField), 'Selected ticket');

      // Tap Create
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      // The new ticket should be selected
      expect(ticketBoardState.selectedTicket, isNotNull);
      expect(ticketBoardState.selectedTicket!.title, 'Selected ticket');
      expect(ticketBoardState.detailMode, TicketDetailMode.detail);
    });
  });
}
