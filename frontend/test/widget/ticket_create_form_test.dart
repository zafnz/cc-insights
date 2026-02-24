import 'dart:ui';

import 'package:cc_insights_v2/panels/ticket_create_form.dart';
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
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    repo = resources.track(TicketRepository('test-create-form'));
    viewState = resources.track(TicketViewState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  Widget createTestApp() {
    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<TicketRepository>.value(value: repo),
            ChangeNotifierProvider<TicketViewState>.value(value: viewState),
          ],
          child: const TicketCreateForm(),
        ),
      ),
    );
  }

  group('TicketCreateForm', () {
    testWidgets('renders all V2 fields', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Header
      expect(find.byIcon(Icons.add_task), findsOneWidget);
      expect(find.text('Create Ticket'), findsOneWidget);

      // Title field
      expect(find.byKey(TicketCreateFormKeys.titleField), findsOneWidget);

      // Body field
      expect(find.byKey(TicketCreateFormKeys.bodyField), findsOneWidget);

      // Tags section (TagPicker hint)
      expect(find.text('Type tag name...'), findsOneWidget);

      // Dependencies section
      expect(find.text('Search tickets...'), findsOneWidget);

      // Images section
      expect(find.text('Attach images...'), findsOneWidget);

      // Action buttons
      expect(find.byKey(TicketCreateFormKeys.cancelButton), findsOneWidget);
      expect(find.byKey(TicketCreateFormKeys.createButton), findsOneWidget);

      // V1 fields should NOT be present
      expect(find.text('Kind'), findsNothing);
      expect(find.text('Priority'), findsNothing);
      expect(find.text('Estimated effort'), findsNothing);
      expect(find.text('Category'), findsNothing);
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
      expect(repo.tickets, isEmpty);
    });

    testWidgets('cancel calls showDetail', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Set mode to create first so we can verify it changes
      viewState.showCreateForm();
      expect(viewState.detailMode, TicketDetailMode.create);

      // Tap Cancel
      await tester.tap(find.byKey(TicketCreateFormKeys.cancelButton));
      await tester.pump();

      // Should switch to detail mode
      expect(viewState.detailMode, TicketDetailMode.detail);
    });

    testWidgets('create ticket with title and body', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Enter title
      await tester.enterText(
          find.byKey(TicketCreateFormKeys.titleField), 'My new ticket');

      // Enter body
      await tester.enterText(
          find.byKey(TicketCreateFormKeys.bodyField), 'Some **markdown** body');

      // Tap Create
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      // Ticket should be created with V2 fields
      expect(repo.tickets.length, 1);
      final ticket = repo.tickets.first;
      expect(ticket.title, 'My new ticket');
      expect(ticket.body, 'Some **markdown** body');
      expect(ticket.isOpen, isTrue);
      expect(ticket.tags, isEmpty);
      expect(ticket.dependsOn, isEmpty);
    });

    testWidgets('created ticket is selected', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Enter a title
      await tester.enterText(
          find.byKey(TicketCreateFormKeys.titleField), 'Selected ticket');

      // Tap Create
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      // The new ticket should be selected
      expect(viewState.selectedTicket, isNotNull);
      expect(viewState.selectedTicket!.title, 'Selected ticket');
      expect(viewState.detailMode, TicketDetailMode.detail);
    });

    testWidgets('create ticket with tags via TagPicker', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Enter a title
      await tester.enterText(
          find.byKey(TicketCreateFormKeys.titleField), 'Tagged ticket');

      // Find the TagPicker TextField inside the tags section
      final tagTextField = find.descendant(
        of: find.byKey(TicketCreateFormKeys.tagPicker),
        matching: find.byType(TextField),
      );
      expect(tagTextField, findsOneWidget);

      // Type a tag and submit
      await tester.enterText(tagTextField, 'bugfix');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Tag chip should appear
      expect(find.text('bugfix'), findsOneWidget);

      // Add another tag
      await tester.enterText(tagTextField, 'frontend');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('frontend'), findsOneWidget);

      // Tap Create
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      // Ticket should have both tags
      expect(repo.tickets.length, 1);
      expect(repo.tickets.first.tags, containsAll(['bugfix', 'frontend']));
    });

    testWidgets('create ticket with dependencies', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create a dependency ticket first
      repo.createTicket(title: 'Dependency ticket');

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Enter a title
      await tester.enterText(
          find.byKey(TicketCreateFormKeys.titleField), 'Dependent ticket');

      // Find the dependency search TextField inside the Autocomplete
      final depTextField = find.widgetWithText(TextField, 'Search tickets...');
      await tester.enterText(depTextField, 'Dependency');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Select it from autocomplete
      final option = find.text('#1 - Dependency ticket');
      if (option.evaluate().isNotEmpty) {
        await tester.tap(option);
        await tester.pump();
      }

      // Tap Create
      await tester.tap(find.byKey(TicketCreateFormKeys.createButton));
      await tester.pump();

      // Should have 2 tickets total (dependency + new one)
      expect(repo.tickets.length, 2);
      final created = repo.tickets.last;
      expect(created.title, 'Dependent ticket');
      expect(created.dependsOn, contains(1));
    });
  });
}
