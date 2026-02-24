import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/author_service.dart' show AuthorService;
import 'package:cc_insights_v2/services/ticket_storage_service.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    AuthorService.setForTesting('testuser');
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
    AuthorService.resetForTesting();
  });

  group('TicketRepository - CRUD', () {
    test('createTicket assigns IDs sequentially', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'First ticket');
      final ticket2 = state.createTicket(title: 'Second ticket');

      expect(ticket1.id, 1);
      expect(ticket2.id, 2);
      expect(state.tickets.length, 2);
    });

    test('createTicket sets timestamps', () {
      final state = resources.track(TicketRepository('test-project'));
      final before = DateTime.now();

      final ticket = state.createTicket(title: 'Test ticket');

      final after = DateTime.now();

      expect(
        ticket.createdAt
            .isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        ticket.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(ticket.updatedAt, ticket.createdAt);
    });

    test('createTicket defaults to isOpen true', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Test ticket');

      expect(ticket.isOpen, isTrue);
    });

    test('createTicket stores tags lowercase', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(
        title: 'Test ticket',
        tags: {'Feature', 'HIGH-PRIORITY', 'bug'},
      );

      expect(ticket.tags, {'feature', 'high-priority', 'bug'});
    });

    test('createTicket uses AuthorService default author', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Test ticket');

      expect(ticket.author, 'testuser');
    });

    test('createTicket accepts explicit author', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(
        title: 'Test ticket',
        author: 'agent auth-refactor',
        authorType: AuthorType.agent,
      );

      expect(ticket.author, 'agent auth-refactor');
    });

    test('createTicket returns created ticket with all fields', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(
        title: 'Test ticket',
        body: 'Test body',
        tags: {'feature'},
        dependsOn: [],
        sourceConversationId: 'conv-123',
      );

      expect(ticket.title, 'Test ticket');
      expect(ticket.body, 'Test body');
      expect(ticket.tags, {'feature'});
      expect(ticket.sourceConversationId, 'conv-123');
      expect(ticket.isOpen, isTrue);
    });

    test('createTicket generates no activity events', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Test ticket');

      expect(ticket.activityLog, isEmpty);
    });

    test('updateTicket modifies title and generates activity event', () async {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Original');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      state.updateTicket(ticket.id, title: 'Modified');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.title, 'Modified');
      expect(updated.updatedAt.isAfter(ticket.updatedAt), isTrue);

      expect(updated.activityLog.length, 1);
      final event = updated.activityLog.first;
      expect(event.type, ActivityEventType.titleEdited);
      expect(event.data['oldTitle'], 'Original');
      expect(event.data['newTitle'], 'Modified');
      expect(event.actor, 'testuser');
      expect(event.actorType, AuthorType.user);
    });

    test('updateTicket modifies body and generates activity event', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        body: 'Original body',
      );

      state.updateTicket(ticket.id, body: 'New body');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.body, 'New body');

      expect(updated.activityLog.length, 1);
      expect(updated.activityLog.first.type, ActivityEventType.bodyEdited);
    });

    test('updateTicket with both title and body generates two events', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Old', body: 'Old body');

      state.updateTicket(ticket.id, title: 'New', body: 'New body');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.activityLog.length, 2);
      expect(
        updated.activityLog.map((e) => e.type).toSet(),
        {ActivityEventType.titleEdited, ActivityEventType.bodyEdited},
      );
    });

    test('updateTicket with unchanged values generates no events', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Same', body: 'Same body');

      state.updateTicket(ticket.id, title: 'Same', body: 'Same body');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.activityLog, isEmpty);
    });

    test('updateTicket with custom actor records correct actor', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Test');

      state.updateTicket(
        ticket.id,
        title: 'Modified',
        actor: 'agent refactor',
        actorType: AuthorType.agent,
      );

      final updated = state.getTicket(ticket.id)!;
      expect(updated.activityLog.first.actor, 'agent refactor');
      expect(updated.activityLog.first.actorType, AuthorType.agent);
    });

    test('updateTicket with non-existent ID does nothing', () {
      final state = resources.track(TicketRepository('test-project'));

      state.createTicket(title: 'Test');

      // Should not throw
      state.updateTicket(999, title: 'Modified');

      expect(state.tickets.length, 1);
      expect(state.tickets.first.title, 'Test');
    });

    test('deleteTicket removes ticket', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'To delete');

      expect(state.tickets.length, 1);

      state.deleteTicket(ticket.id);

      expect(state.tickets.length, 0);
    });

    test('deleteTicket removes from dependsOn lists', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'Dependency');
      final ticket2 = state.createTicket(
        title: 'Dependent',
        dependsOn: [ticket1.id],
      );

      expect(state.getTicket(ticket2.id)!.dependsOn, [ticket1.id]);

      state.deleteTicket(ticket1.id);

      expect(state.getTicket(ticket2.id)!.dependsOn, isEmpty);
    });

    test('getTicket returns correct ticket', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Test');

      final found = state.getTicket(ticket.id);
      expect(found, isNotNull);
      expect(found!.id, ticket.id);
      expect(found.title, 'Test');
    });

    test('getTicket returns null for non-existent ID', () {
      final state = resources.track(TicketRepository('test-project'));

      final found = state.getTicket(999);
      expect(found, isNull);
    });
  });

  group('TicketRepository - Close/Reopen', () {
    test('closeTicket sets isOpen false and closedAt', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.closeTicket(ticket.id, 'testuser', AuthorType.user);

      final closed = state.getTicket(ticket.id)!;
      expect(closed.isOpen, isFalse);
      expect(closed.closedAt, isNotNull);
      expect(closed.updatedAt.isAfter(ticket.updatedAt) || closed.updatedAt == ticket.updatedAt, isTrue);
    });

    test('closeTicket records closed activity event', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.closeTicket(ticket.id, 'testuser', AuthorType.user);

      final closed = state.getTicket(ticket.id)!;
      expect(closed.activityLog.length, 1);

      final event = closed.activityLog.first;
      expect(event.type, ActivityEventType.closed);
      expect(event.actor, 'testuser');
      expect(event.actorType, AuthorType.user);
    });

    test('closeTicket by agent records agent actor', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.closeTicket(
        ticket.id,
        'agent auth-refactor',
        AuthorType.agent,
      );

      final closed = state.getTicket(ticket.id)!;
      final event = closed.activityLog.first;
      expect(event.actor, 'agent auth-refactor');
      expect(event.actorType, AuthorType.agent);
    });

    test('closeTicket with non-existent ID does nothing', () {
      final state = resources.track(TicketRepository('test-project'));
      state.createTicket(title: 'Test');

      // Should not throw
      state.closeTicket(999, 'testuser', AuthorType.user);
      expect(state.tickets.length, 1);
      expect(state.tickets.first.isOpen, isTrue);
    });

    test('reopenTicket sets isOpen true and clears closedAt', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      // Close first
      state.closeTicket(ticket.id, 'testuser', AuthorType.user);
      expect(state.getTicket(ticket.id)!.isOpen, isFalse);
      expect(state.getTicket(ticket.id)!.closedAt, isNotNull);

      // Now reopen
      state.reopenTicket(ticket.id, 'testuser', AuthorType.user);

      final reopened = state.getTicket(ticket.id)!;
      expect(reopened.isOpen, isTrue);
      expect(reopened.closedAt, isNull);
    });

    test('reopenTicket records reopened activity event', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.closeTicket(ticket.id, 'testuser', AuthorType.user);
      state.reopenTicket(ticket.id, 'testuser', AuthorType.user);

      final reopened = state.getTicket(ticket.id)!;
      // Should have closed + reopened events
      expect(reopened.activityLog.length, 2);
      expect(reopened.activityLog[0].type, ActivityEventType.closed);
      expect(reopened.activityLog[1].type, ActivityEventType.reopened);
    });

    test('reopenTicket with non-existent ID does nothing', () {
      final state = resources.track(TicketRepository('test-project'));

      // Should not throw
      state.reopenTicket(999, 'testuser', AuthorType.user);
    });

    test('closeTicket on already-closed ticket is a no-op', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.closeTicket(ticket.id, 'testuser', AuthorType.user);
      final afterFirstClose = state.getTicket(ticket.id)!;
      final closedAt = afterFirstClose.closedAt;
      final eventCount = afterFirstClose.activityLog.length;

      // Close again — should not add event or change closedAt
      state.closeTicket(ticket.id, 'testuser', AuthorType.user);

      final afterSecondClose = state.getTicket(ticket.id)!;
      expect(afterSecondClose.activityLog.length, eventCount);
      expect(afterSecondClose.closedAt, closedAt);
      expect(afterSecondClose.isOpen, isFalse);
    });

    test('reopenTicket on already-open ticket is a no-op', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      // Ticket starts open — reopen should be a no-op
      final before = state.getTicket(ticket.id)!;

      state.reopenTicket(ticket.id, 'testuser', AuthorType.user);

      final after = state.getTicket(ticket.id)!;
      expect(after.activityLog.length, before.activityLog.length);
      expect(after.isOpen, isTrue);
      expect(after.closedAt, isNull);
    });
  });

  group('TicketRepository - Open/Closed counts', () {
    test('openCount and closedCount track ticket states', () {
      final state = resources.track(TicketRepository('test-project'));

      state.createTicket(title: 'Open 1');
      state.createTicket(title: 'Open 2');
      final t3 = state.createTicket(title: 'Will close');

      expect(state.openCount, 3);
      expect(state.closedCount, 0);

      state.closeTicket(t3.id, 'testuser', AuthorType.user);

      expect(state.openCount, 2);
      expect(state.closedCount, 1);
    });

    test('counts update on reopen', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'Test');
      state.closeTicket(ticket.id, 'testuser', AuthorType.user);

      expect(state.openCount, 0);
      expect(state.closedCount, 1);

      state.reopenTicket(ticket.id, 'testuser', AuthorType.user);

      expect(state.openCount, 1);
      expect(state.closedCount, 0);
    });
  });

  group('TicketRepository - Dependencies/DAG', () {
    test('addDependency works', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');

      state.addDependency(ticket2.id, ticket1.id);

      final updated = state.getTicket(ticket2.id);
      expect(updated!.dependsOn, [ticket1.id]);
    });

    test('addDependency self-reference throws', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'A');

      expect(
        () => state.addDependency(ticket.id, ticket.id),
        throwsArgumentError,
      );
    });

    test('addDependency non-existent target throws', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket = state.createTicket(title: 'A');

      expect(
        () => state.addDependency(ticket.id, 999),
        throwsArgumentError,
      );
    });

    test('addDependency direct cycle throws', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');

      // A depends on B
      state.addDependency(ticket1.id, ticket2.id);

      // B depends on A would create a cycle
      expect(
        () => state.addDependency(ticket2.id, ticket1.id),
        throwsArgumentError,
      );
    });

    test('addDependency indirect cycle throws', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');
      final ticket3 = state.createTicket(title: 'C');

      // A -> B -> C
      state.addDependency(ticket1.id, ticket2.id);
      state.addDependency(ticket2.id, ticket3.id);

      // C -> A would create a cycle
      expect(
        () => state.addDependency(ticket3.id, ticket1.id),
        throwsArgumentError,
      );
    });

    test('wouldCreateCycle detects direct cycle', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');

      // A depends on B
      state.addDependency(ticket1.id, ticket2.id);

      // B -> A would create cycle
      expect(state.wouldCreateCycle(ticket2.id, ticket1.id), isTrue);

      // C -> A would not create cycle
      final ticket3 = state.createTicket(title: 'C');
      expect(state.wouldCreateCycle(ticket3.id, ticket1.id), isFalse);
    });

    test('wouldCreateCycle detects indirect cycle', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');
      final ticket3 = state.createTicket(title: 'C');

      // A -> B -> C
      state.addDependency(ticket1.id, ticket2.id);
      state.addDependency(ticket2.id, ticket3.id);

      // C -> A would create cycle
      expect(state.wouldCreateCycle(ticket3.id, ticket1.id), isTrue);

      // C -> B would create cycle
      expect(state.wouldCreateCycle(ticket3.id, ticket2.id), isTrue);
    });

    test('removeDependency removes dependency', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');

      state.addDependency(ticket2.id, ticket1.id);
      expect(state.getTicket(ticket2.id)!.dependsOn, [ticket1.id]);

      state.removeDependency(ticket2.id, ticket1.id);
      expect(state.getTicket(ticket2.id)!.dependsOn, isEmpty);
    });

    test('getBlockedBy returns tickets depending on given ticket', () {
      final state = resources.track(TicketRepository('test-project'));

      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');
      final ticket3 = state.createTicket(title: 'C');

      // B and C depend on A
      state.addDependency(ticket2.id, ticket1.id);
      state.addDependency(ticket3.id, ticket1.id);

      final blocked = state.getBlockedBy(ticket1.id);
      expect(blocked.length, 2);
      expect(blocked.contains(ticket2.id), isTrue);
      expect(blocked.contains(ticket3.id), isTrue);
    });
  });

  group('TicketRepository - Persistence', () {
    test('save and load round-trip', () async {
      final testProjectId =
          'test-project-roundtrip-${DateTime.now().millisecondsSinceEpoch}';
      final storage = TicketStorageService();
      final state = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );

      // Create some tickets
      state.createTicket(
        title: 'Ticket 1',
        body: 'First ticket',
        tags: {'feature', 'high-priority'},
      );

      final t2 = state.createTicket(
        title: 'Ticket 2',
        tags: {'bug'},
      );
      state.closeTicket(t2.id, 'testuser', AuthorType.user);

      // Save explicitly
      await state.save();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Create new state and load
      final state2 = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );
      await state2.load();

      // Verify
      expect(state2.tickets.length, 2);
      expect(state2.tickets[0].title, 'Ticket 1');
      expect(state2.tickets[0].body, 'First ticket');
      expect(state2.tickets[0].tags, {'feature', 'high-priority'});
      expect(state2.tickets[0].isOpen, isTrue);

      expect(state2.tickets[1].title, 'Ticket 2');
      expect(state2.tickets[1].isOpen, isFalse);
      expect(state2.tickets[1].closedAt, isNotNull);
      // Activity log should be preserved
      expect(state2.tickets[1].activityLog.length, 1);
      expect(
        state2.tickets[1].activityLog.first.type,
        ActivityEventType.closed,
      );
    });

    test('load with no file does not throw', () async {
      final state = resources.track(TicketRepository('test-project'));

      // Should not throw
      await state.load();

      expect(state.tickets, isEmpty);
    });

    test('load with corrupt file does not throw', () async {
      final state = resources.track(TicketRepository('test-project'));

      // Write corrupt data
      final storage = TicketStorageService();
      await storage.saveTickets('test-project', {'invalid': 'data'});

      // Should not throw
      await state.load();

      expect(state.tickets, isEmpty);
    });

    test('createTicket triggers auto-save', () async {
      final testProjectId =
          'test-project-autosave-${DateTime.now().millisecondsSinceEpoch}';
      final storage = TicketStorageService();
      final state = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );

      state.createTicket(title: 'Test');

      // Wait for auto-save to complete
      await state.save();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Load in new state
      final state2 = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );
      await state2.load();

      expect(state2.tickets.length, 1);
      expect(state2.tickets.first.title, 'Test');
    });

    test('nextId is preserved across save/load', () async {
      final testProjectId =
          'test-project-nextid-${DateTime.now().millisecondsSinceEpoch}';
      final storage = TicketStorageService();
      final state = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );

      state.createTicket(title: 'A');
      state.createTicket(title: 'B');
      state.createTicket(title: 'C');

      expect(state.tickets.length, 3);

      try {
        await state.save();
      } catch (e) {
        fail('Save threw exception: $e');
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify the saved data contains nextId
      final savedData = await storage.loadTickets(testProjectId);
      expect(savedData, isNotNull,
          reason: 'Saved data should not be null after save');
      expect(savedData!['nextId'], 4, reason: 'nextId should be 4');

      final state2 = resources.track(
        TicketRepository(testProjectId, storage: storage),
      );
      await state2.load();

      expect(state2.tickets.length, 3,
          reason: 'Should have 3 tickets after load');

      final newTicket = state2.createTicket(title: 'D');
      expect(newTicket.id, 4, reason: 'New ticket should have ID 4');
    });
  });

  group('TicketRepository - Notifications', () {
    test('createTicket notifies listeners', () {
      final state = resources.track(TicketRepository('test-project'));
      var notified = false;
      state.addListener(() => notified = true);

      state.createTicket(title: 'Test');

      expect(notified, isTrue);
    });

    test('updateTicket notifies listeners', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      var notified = false;
      state.addListener(() => notified = true);

      state.updateTicket(ticket.id, title: 'Modified');

      expect(notified, isTrue);
    });

    test('deleteTicket notifies listeners', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      var notified = false;
      state.addListener(() => notified = true);

      state.deleteTicket(ticket.id);

      expect(notified, isTrue);
    });

    test('closeTicket notifies listeners', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      var notified = false;
      state.addListener(() => notified = true);

      state.closeTicket(ticket.id, 'testuser', AuthorType.user);

      expect(notified, isTrue);
    });

    test('reopenTicket notifies listeners', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');
      state.closeTicket(ticket.id, 'testuser', AuthorType.user);

      var notified = false;
      state.addListener(() => notified = true);

      state.reopenTicket(ticket.id, 'testuser', AuthorType.user);

      expect(notified, isTrue);
    });

    test('addDependency notifies listeners', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket1 = state.createTicket(title: 'A');
      final ticket2 = state.createTicket(title: 'B');

      var notified = false;
      state.addListener(() => notified = true);

      state.addDependency(ticket2.id, ticket1.id);

      expect(notified, isTrue);
    });
  });

  group('TicketRepository - addComment', () {
    test('adds comment with default author', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.addComment(ticket.id, 'A comment');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.comments.length, 1);
      expect(updated.comments.first.text, 'A comment');
      expect(updated.comments.first.author, 'testuser');
      expect(updated.comments.first.authorType, AuthorType.user);
      expect(updated.comments.first.id, isNotEmpty);
    });

    test('adds comment with explicit author', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.addComment(
        ticket.id,
        'Agent note',
        author: 'agent refactor',
        authorType: AuthorType.agent,
      );

      final updated = state.getTicket(ticket.id)!;
      expect(updated.comments.first.author, 'agent refactor');
      expect(updated.comments.first.authorType, AuthorType.agent);
    });

    test('adds multiple comments in order', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.addComment(ticket.id, 'First');
      state.addComment(ticket.id, 'Second');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.comments.length, 2);
      expect(updated.comments[0].text, 'First');
      expect(updated.comments[1].text, 'Second');
    });

    test('addComment updates updatedAt', () async {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      state.addComment(ticket.id, 'A comment');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.updatedAt.isAfter(ticket.updatedAt), isTrue);
    });

    test('addComment on non-existent ticket does nothing', () {
      final state = resources.track(TicketRepository('test-project'));

      // Should not throw
      state.addComment(999, 'Orphan comment');
      expect(state.tickets, isEmpty);
    });
  });

  group('TicketRepository - linkWorktree', () {
    test('links worktree to ticket', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.linkWorktree(ticket.id, '/path/to/wt', 'feat/branch');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedWorktrees.length, 1);
      expect(updated.linkedWorktrees.first.worktreeRoot, '/path/to/wt');
      expect(updated.linkedWorktrees.first.branch, 'feat/branch');
    });

    test('avoids duplicate worktree links', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.linkWorktree(ticket.id, '/path/to/wt', 'feat/branch');
      state.linkWorktree(ticket.id, '/path/to/wt', 'feat/branch');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedWorktrees.length, 1);
    });

    test('links multiple different worktrees', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.linkWorktree(ticket.id, '/path/a', 'branch-a');
      state.linkWorktree(ticket.id, '/path/b', 'branch-b');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedWorktrees.length, 2);
    });

    test('linkWorktree on non-existent ticket does nothing', () {
      final state = resources.track(TicketRepository('test-project'));

      // Should not throw
      state.linkWorktree(999, '/path/to/wt', 'branch');
    });
  });

  group('TicketRepository - linkChat', () {
    test('links chat to ticket', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.linkChat(ticket.id, 'chat-1', 'auth-refactor', '/path/wt');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedChats.length, 1);
      expect(updated.linkedChats.first.chatId, 'chat-1');
      expect(updated.linkedChats.first.chatName, 'auth-refactor');
      expect(updated.linkedChats.first.worktreeRoot, '/path/wt');
    });

    test('avoids duplicate chat links', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.linkChat(ticket.id, 'chat-1', 'auth-refactor', '/path/wt');
      state.linkChat(ticket.id, 'chat-1', 'auth-refactor', '/path/wt');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedChats.length, 1);
    });

    test('links multiple different chats', () {
      final state = resources.track(TicketRepository('test-project'));
      final ticket = state.createTicket(title: 'Test');

      state.linkChat(ticket.id, 'chat-1', 'auth', '/path/wt');
      state.linkChat(ticket.id, 'chat-2', 'ui', '/path/wt');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedChats.length, 2);
    });

    test('linkChat on non-existent ticket does nothing', () {
      final state = resources.track(TicketRepository('test-project'));

      // Should not throw
      state.linkChat(999, 'chat-1', 'name', '/path');
    });
  });

  group('TicketRepository - getTicketsForChat', () {
    test('returns tickets linked to a chat', () {
      final state = resources.track(TicketRepository('test-project'));

      final t1 = state.createTicket(title: 'Ticket 1');
      final t2 = state.createTicket(title: 'Ticket 2');
      state.createTicket(title: 'Ticket 3');

      state.linkChat(t1.id, 'chat-a', 'auth', '/path');
      state.linkChat(t2.id, 'chat-a', 'auth', '/path');

      final result = state.getTicketsForChat('chat-a');
      expect(result.length, 2);
      expect(result.map((t) => t.id).toSet(), {t1.id, t2.id});
    });

    test('returns empty list when no tickets linked', () {
      final state = resources.track(TicketRepository('test-project'));

      state.createTicket(title: 'Ticket 1');

      final result = state.getTicketsForChat('no-such-chat');
      expect(result, isEmpty);
    });
  });
}
