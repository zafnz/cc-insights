import 'dart:ui';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/widgets/ticket_edit_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late Future<void> Function() cleanupConfig;
  late bool saveCalled;
  late bool cancelCalled;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    repo = resources.track(TicketRepository('test-edit'));
    saveCalled = false;
    cancelCalled = false;
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  Widget createEditTestApp(TicketData ticket) {
    return MaterialApp(
      home: Scaffold(
        body: TicketEditForm(
          ticket: ticket,
          repository: repo,
          onSave: () => saveCalled = true,
          onCancel: () => cancelCalled = true,
        ),
      ),
    );
  }

  group('TicketEditForm', () {
    // -------------------------------------------------------------------------
    // 1. Form pre-populates with current ticket data
    // -------------------------------------------------------------------------
    testWidgets('form pre-populates with current ticket data', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      // Create a ticket with dep so we can test all pre-populated fields
      final dep = repo.createTicket(title: 'Dependency');
      final ticket = repo.createTicket(
        title: 'Pre-populated title',
        body: 'Some **markdown** body',
        tags: {'urgent', 'backend'},
        dependsOn: [dep.id],
      );

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Title is pre-populated
      final titleFields = find.byType(TextField);
      final titleField = tester.widget<TextField>(titleFields.first);
      expect(titleField.controller?.text, 'Pre-populated title');

      // Body is pre-populated
      final bodyField = tester.widget<TextField>(titleFields.at(1));
      expect(bodyField.controller?.text, 'Some **markdown** body');

      // Tags are shown as chips
      expect(find.text('urgent'), findsOneWidget);
      expect(find.text('backend'), findsOneWidget);

      // Dependency is shown as chip
      expect(find.text('#${dep.id}'), findsOneWidget);

      // Action buttons are present
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 2. Changing title generates titleEdited activity event
    // -------------------------------------------------------------------------
    testWidgets('changing title and saving generates titleEdited event',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(title: 'Original title');

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Find title field (first TextField with 'Ticket title' hint)
      final titleField =
          find.widgetWithText(TextField, 'Original title');
      await tester.enterText(titleField, 'Updated title');

      // Tap Save
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // Verify activity event
      final updated = repo.getTicket(ticket.id)!;
      expect(updated.title, 'Updated title');
      expect(
        updated.activityLog
            .any((e) => e.type == ActivityEventType.titleEdited),
        isTrue,
      );
      final event = updated.activityLog
          .firstWhere((e) => e.type == ActivityEventType.titleEdited);
      expect(event.data['oldTitle'], 'Original title');
      expect(event.data['newTitle'], 'Updated title');
      expect(saveCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // 3. Changing body generates bodyEdited activity event
    // -------------------------------------------------------------------------
    testWidgets('changing body and saving generates bodyEdited event',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'Body test',
        body: 'Original body',
      );

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Find body field (second TextField, has 'Markdown body...' hint)
      final bodyField = find.widgetWithText(TextField, 'Original body');
      await tester.enterText(bodyField, 'Updated **markdown** body');

      // Tap Save
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // Verify activity event
      final updated = repo.getTicket(ticket.id)!;
      expect(updated.body, 'Updated **markdown** body');
      expect(
        updated.activityLog
            .any((e) => e.type == ActivityEventType.bodyEdited),
        isTrue,
      );
      expect(saveCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // 4. Adding a tag generates tagAdded event
    // -------------------------------------------------------------------------
    testWidgets('adding a tag generates tagAdded event', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(title: 'Tag test');

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Find the tag input field (has 'Add a tag...' hint)
      final tagInput = find.widgetWithText(TextField, 'Add a tag...');
      await tester.enterText(tagInput, 'newtag');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Tag chip should appear in the form
      expect(find.text('newtag'), findsOneWidget);

      // Tap Save
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // Verify tag and activity event
      final updated = repo.getTicket(ticket.id)!;
      expect(updated.tags, contains('newtag'));
      expect(
        updated.activityLog
            .any((e) => e.type == ActivityEventType.tagAdded),
        isTrue,
      );
      expect(saveCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // 5. Removing a tag generates tagRemoved event
    // -------------------------------------------------------------------------
    testWidgets('removing a tag generates tagRemoved event', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'Remove tag test',
        tags: {'existing'},
      );

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Verify the tag chip is shown
      expect(find.text('existing'), findsOneWidget);

      // Tap the close icon on the tag chip to remove it.
      // TicketTagChip renders a close Icon for removable chips.
      final closeIcons = find.descendant(
        of: find.ancestor(
          of: find.text('existing'),
          matching: find.byType(Row),
        ),
        matching: find.byIcon(Icons.close),
      );
      await tester.tap(closeIcons.first);
      await tester.pump();

      // Tag should be gone from the form
      expect(find.text('existing'), findsNothing);

      // Tap Save
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // Verify
      final updated = repo.getTicket(ticket.id)!;
      expect(updated.tags, isNot(contains('existing')));
      expect(
        updated.activityLog
            .any((e) => e.type == ActivityEventType.tagRemoved),
        isTrue,
      );
      expect(saveCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // 6. Adding a dependency generates dependencyAdded event
    // -------------------------------------------------------------------------
    testWidgets('adding a dependency generates dependencyAdded event',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final dep = repo.createTicket(title: 'Dep ticket');
      final ticket = repo.createTicket(title: 'Dep test');

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Find the dependency input field and type the dep ID
      final depInput =
          find.widgetWithText(TextField, 'Ticket # to depend on...');
      await tester.enterText(depInput, '${dep.id}');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Dependency chip should appear
      expect(find.text('#${dep.id}'), findsOneWidget);

      // Tap Save
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // Verify
      final updated = repo.getTicket(ticket.id)!;
      expect(updated.dependsOn, contains(dep.id));
      expect(
        updated.activityLog
            .any((e) => e.type == ActivityEventType.dependencyAdded),
        isTrue,
      );
      expect(saveCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // 7. Save button applies all changes
    // -------------------------------------------------------------------------
    testWidgets('save button applies all changes', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final dep = repo.createTicket(title: 'A dependency');
      final ticket = repo.createTicket(
        title: 'Multi change',
        body: 'Old body',
        tags: {'oldtag'},
      );

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Change title
      final titleField = find.widgetWithText(TextField, 'Multi change');
      await tester.enterText(titleField, 'New title');

      // Change body
      final bodyField = find.widgetWithText(TextField, 'Old body');
      await tester.enterText(bodyField, 'New body');

      // Add a tag
      final tagInput = find.widgetWithText(TextField, 'Add a tag...');
      await tester.enterText(tagInput, 'newtag');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Add a dependency
      final depInput =
          find.widgetWithText(TextField, 'Ticket # to depend on...');
      await tester.enterText(depInput, '${dep.id}');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Save
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // Verify all changes applied
      final updated = repo.getTicket(ticket.id)!;
      expect(updated.title, 'New title');
      expect(updated.body, 'New body');
      expect(updated.tags, containsAll(['oldtag', 'newtag']));
      expect(updated.dependsOn, contains(dep.id));
      expect(saveCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // 8. Cancel returns without saving
    // -------------------------------------------------------------------------
    testWidgets('cancel returns without changes', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'Unchanged title',
        body: 'Unchanged body',
      );

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Change the title
      final titleField = find.widgetWithText(TextField, 'Unchanged title');
      await tester.enterText(titleField, 'Changed but not saved');

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      // Ticket should NOT be updated
      final unchanged = repo.getTicket(ticket.id)!;
      expect(unchanged.title, 'Unchanged title');
      expect(unchanged.body, 'Unchanged body');
      expect(cancelCalled, isTrue);
      expect(saveCalled, isFalse);
    });

    // -------------------------------------------------------------------------
    // 9. No activity events if nothing changed
    // -------------------------------------------------------------------------
    testWidgets('no activity events generated if nothing changed',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final ticket = repo.createTicket(
        title: 'No changes',
        body: 'Same body',
        tags: {'existing'},
      );
      final initialEventCount = repo.getTicket(ticket.id)!.activityLog.length;

      await tester.pumpWidget(createEditTestApp(ticket));
      await safePumpAndSettle(tester);

      // Tap Save without changing anything
      await tester.tap(find.text('Save'));
      await safePumpAndSettle(tester);

      // No new activity events should be generated
      final updated = repo.getTicket(ticket.id)!;
      expect(updated.activityLog.length, initialEventCount);
      expect(updated.title, 'No changes');
      expect(updated.body, 'Same body');
      expect(updated.tags, {'existing'});
      expect(saveCalled, isTrue);
    });
  });
}
