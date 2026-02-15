import 'dart:io';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  group('TicketBoardState - CRUD', () {
    test('createTicket assigns IDs sequentially', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(
        title: 'First ticket',
        kind: TicketKind.feature,
      );

      final ticket2 = state.createTicket(
        title: 'Second ticket',
        kind: TicketKind.bugfix,
      );

      expect(ticket1.id, 1);
      expect(ticket2.id, 2);
      expect(state.tickets.length, 2);
    });

    test('createTicket sets timestamps', () {
      final state = resources.track(TicketBoardState('test-project'));
      final before = DateTime.now();

      final ticket = state.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
      );

      final after = DateTime.now();

      expect(ticket.createdAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(ticket.createdAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
      expect(ticket.updatedAt, ticket.createdAt);
    });

    test('createTicket defaults status to ready', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
      );

      expect(ticket.status, TicketStatus.ready);
    });

    test('createTicket returns created ticket', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        description: 'Test description',
        priority: TicketPriority.high,
        category: 'Testing',
      );

      expect(ticket.title, 'Test ticket');
      expect(ticket.kind, TicketKind.feature);
      expect(ticket.description, 'Test description');
      expect(ticket.priority, TicketPriority.high);
      expect(ticket.category, 'Testing');
    });

    test('updateTicket modifies ticket and updates timestamp', () async {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Original',
        kind: TicketKind.feature,
      );

      final originalUpdatedAt = ticket.updatedAt;

      // Wait a bit to ensure timestamp changes
      await Future<void>.delayed(const Duration(milliseconds: 10));

      state.updateTicket(ticket.id, (t) => t.copyWith(title: 'Modified'));

      final updated = state.getTicket(ticket.id);
      expect(updated!.title, 'Modified');
      expect(updated.updatedAt.isAfter(originalUpdatedAt), isTrue);
    });

    test('updateTicket with non-existent ID does nothing', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.createTicket(title: 'Test', kind: TicketKind.feature);

      // Should not throw
      state.updateTicket(999, (t) => t.copyWith(title: 'Modified'));

      expect(state.tickets.length, 1);
      expect(state.tickets.first.title, 'Test');
    });

    test('deleteTicket removes ticket', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'To delete',
        kind: TicketKind.feature,
      );

      expect(state.tickets.length, 1);

      state.deleteTicket(ticket.id);

      expect(state.tickets.length, 0);
    });

    test('deleteTicket removes from dependsOn lists', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(
        title: 'Dependency',
        kind: TicketKind.feature,
      );

      final ticket2 = state.createTicket(
        title: 'Dependent',
        kind: TicketKind.feature,
        dependsOn: [ticket1.id],
      );

      expect(state.getTicket(ticket2.id)!.dependsOn, [ticket1.id]);

      state.deleteTicket(ticket1.id);

      expect(state.getTicket(ticket2.id)!.dependsOn, isEmpty);
    });

    test('deleteTicket clears selection if deleted ticket was selected', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'To delete',
        kind: TicketKind.feature,
      );

      state.selectTicket(ticket.id);
      expect(state.selectedTicket, isNotNull);

      state.deleteTicket(ticket.id);

      expect(state.selectedTicket, isNull);
    });

    test('getTicket returns correct ticket', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        kind: TicketKind.feature,
      );

      final found = state.getTicket(ticket.id);
      expect(found, isNotNull);
      expect(found!.id, ticket.id);
      expect(found.title, 'Test');
    });

    test('getTicket returns null for non-existent ID', () {
      final state = resources.track(TicketBoardState('test-project'));

      final found = state.getTicket(999);
      expect(found, isNull);
    });
  });

  group('TicketBoardState - Selection', () {
    test('selectTicket updates selectedTicket', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        kind: TicketKind.feature,
      );

      state.selectTicket(ticket.id);

      expect(state.selectedTicket, isNotNull);
      expect(state.selectedTicket!.id, ticket.id);
    });

    test('selectTicket(null) clears selection', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        kind: TicketKind.feature,
      );

      state.selectTicket(ticket.id);
      expect(state.selectedTicket, isNotNull);

      state.selectTicket(null);
      expect(state.selectedTicket, isNull);
    });

    test('selectTicket sets detail mode to detail', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        kind: TicketKind.feature,
      );

      state.showCreateForm();
      expect(state.detailMode, TicketDetailMode.create);

      state.selectTicket(ticket.id);
      expect(state.detailMode, TicketDetailMode.detail);
    });

    test('showCreateForm sets mode and clears selection', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        kind: TicketKind.feature,
      );

      state.selectTicket(ticket.id);
      expect(state.selectedTicket, isNotNull);

      state.showCreateForm();

      expect(state.detailMode, TicketDetailMode.create);
      expect(state.selectedTicket, isNull);
    });

    test('showDetail sets mode to detail', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.showCreateForm();
      expect(state.detailMode, TicketDetailMode.create);

      state.showDetail();
      expect(state.detailMode, TicketDetailMode.detail);
    });
  });

  group('TicketBoardState - Filtering', () {
    late TicketBoardState state;

    setUp(() {
      state = resources.track(TicketBoardState('test-project'));

      // Create test tickets
      state.createTicket(
        title: 'Feature A',
        kind: TicketKind.feature,
        status: TicketStatus.active,
        priority: TicketPriority.high,
        category: 'Frontend',
      );

      state.createTicket(
        title: 'Bug B',
        kind: TicketKind.bugfix,
        status: TicketStatus.completed,
        priority: TicketPriority.low,
        category: 'Backend',
      );

      state.createTicket(
        title: 'Feature C',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.medium,
        category: 'Frontend',
      );
    });

    test('no filters returns all tickets', () {
      expect(state.filteredTickets.length, 3);
    });

    test('search by title', () {
      state.setSearchQuery('Feature');
      expect(state.filteredTickets.length, 2);
      expect(state.filteredTickets.every((t) => t.title.contains('Feature')), isTrue);
    });

    test('search by displayId', () {
      state.setSearchQuery('TKT-001');
      expect(state.filteredTickets.length, 1);
      expect(state.filteredTickets.first.id, 1);
    });

    test('search is case-insensitive', () {
      state.setSearchQuery('feature');
      expect(state.filteredTickets.length, 2);
    });

    test('status filter', () {
      state.setStatusFilter(TicketStatus.active);
      expect(state.filteredTickets.length, 1);
      expect(state.filteredTickets.first.status, TicketStatus.active);
    });

    test('kind filter', () {
      state.setKindFilter(TicketKind.feature);
      expect(state.filteredTickets.length, 2);
      expect(state.filteredTickets.every((t) => t.kind == TicketKind.feature), isTrue);
    });

    test('priority filter', () {
      state.setPriorityFilter(TicketPriority.high);
      expect(state.filteredTickets.length, 1);
      expect(state.filteredTickets.first.priority, TicketPriority.high);
    });

    test('category filter', () {
      state.setCategoryFilter('Frontend');
      expect(state.filteredTickets.length, 2);
      expect(state.filteredTickets.every((t) => t.category == 'Frontend'), isTrue);
    });

    test('multiple filters AND-combined', () {
      state.setKindFilter(TicketKind.feature);
      state.setCategoryFilter('Frontend');
      expect(state.filteredTickets.length, 2);

      state.setStatusFilter(TicketStatus.active);
      expect(state.filteredTickets.length, 1);
      expect(state.filteredTickets.first.title, 'Feature A');
    });

    test('clearing filters', () {
      state.setStatusFilter(TicketStatus.active);
      expect(state.filteredTickets.length, 1);

      state.setStatusFilter(null);
      expect(state.filteredTickets.length, 3);
    });
  });

  group('TicketBoardState - Grouping', () {
    late TicketBoardState state;

    setUp(() {
      state = resources.track(TicketBoardState('test-project'));

      state.createTicket(
        title: 'A',
        kind: TicketKind.feature,
        priority: TicketPriority.high,
        category: 'Frontend',
      );

      state.createTicket(
        title: 'B',
        kind: TicketKind.bugfix,
        priority: TicketPriority.low,
        category: 'Backend',
      );

      state.createTicket(
        title: 'C',
        kind: TicketKind.feature,
        priority: TicketPriority.medium,
        category: 'Frontend',
      );

      state.createTicket(
        title: 'D',
        kind: TicketKind.feature,
        priority: TicketPriority.critical,
      ); // No category
    });

    test('groupBy category', () {
      state.setGroupBy(TicketGroupBy.category);
      final groups = state.groupedTickets;

      expect(groups.keys.length, 3);
      expect(groups.containsKey('Frontend'), isTrue);
      expect(groups.containsKey('Backend'), isTrue);
      expect(groups.containsKey('Uncategorized'), isTrue);

      expect(groups['Frontend']!.length, 2);
      expect(groups['Backend']!.length, 1);
      expect(groups['Uncategorized']!.length, 1);
    });

    test('groupBy status', () {
      state.setGroupBy(TicketGroupBy.status);
      final groups = state.groupedTickets;

      expect(groups.containsKey('Ready'), isTrue);
      expect(groups['Ready']!.length, 4);
    });

    test('tickets within groups sorted by priority then id', () {
      state.setGroupBy(TicketGroupBy.category);
      final groups = state.groupedTickets;

      final frontend = groups['Frontend']!;
      // High priority (ticket 1) should come before medium (ticket 3)
      expect(frontend[0].priority, TicketPriority.high);
      expect(frontend[1].priority, TicketPriority.medium);
      expect(frontend[0].id, 1);
      expect(frontend[1].id, 3);
    });

    test('uncategorized group for tickets without category', () {
      state.setGroupBy(TicketGroupBy.category);
      final groups = state.groupedTickets;

      expect(groups.containsKey('Uncategorized'), isTrue);
      expect(groups['Uncategorized']!.length, 1);
      expect(groups['Uncategorized']!.first.title, 'D');
    });

    test('allCategories returns unique sorted categories', () {
      final categories = state.allCategories;

      expect(categories, ['Backend', 'Frontend']);
    });
  });

  group('TicketBoardState - Dependencies/DAG', () {
    test('addDependency works', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);

      state.addDependency(ticket2.id, ticket1.id);

      final updated = state.getTicket(ticket2.id);
      expect(updated!.dependsOn, [ticket1.id]);
    });

    test('addDependency self-reference throws', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(title: 'A', kind: TicketKind.feature);

      expect(
        () => state.addDependency(ticket.id, ticket.id),
        throwsArgumentError,
      );
    });

    test('addDependency non-existent target throws', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(title: 'A', kind: TicketKind.feature);

      expect(
        () => state.addDependency(ticket.id, 999),
        throwsArgumentError,
      );
    });

    test('addDependency direct cycle throws', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);

      // A depends on B
      state.addDependency(ticket1.id, ticket2.id);

      // B depends on A would create a cycle
      expect(
        () => state.addDependency(ticket2.id, ticket1.id),
        throwsArgumentError,
      );
    });

    test('addDependency indirect cycle throws', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);
      final ticket3 = state.createTicket(title: 'C', kind: TicketKind.feature);

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
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);

      // A depends on B
      state.addDependency(ticket1.id, ticket2.id);

      // B -> A would create cycle
      expect(state.wouldCreateCycle(ticket2.id, ticket1.id), isTrue);

      // C -> A would not create cycle
      final ticket3 = state.createTicket(title: 'C', kind: TicketKind.feature);
      expect(state.wouldCreateCycle(ticket3.id, ticket1.id), isFalse);
    });

    test('wouldCreateCycle detects indirect cycle', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);
      final ticket3 = state.createTicket(title: 'C', kind: TicketKind.feature);

      // A -> B -> C
      state.addDependency(ticket1.id, ticket2.id);
      state.addDependency(ticket2.id, ticket3.id);

      // C -> A would create cycle
      expect(state.wouldCreateCycle(ticket3.id, ticket1.id), isTrue);

      // C -> B would create cycle
      expect(state.wouldCreateCycle(ticket3.id, ticket2.id), isTrue);
    });

    test('removeDependency removes dependency', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);

      state.addDependency(ticket2.id, ticket1.id);
      expect(state.getTicket(ticket2.id)!.dependsOn, [ticket1.id]);

      state.removeDependency(ticket2.id, ticket1.id);
      expect(state.getTicket(ticket2.id)!.dependsOn, isEmpty);
    });

    test('getBlockedBy returns tickets depending on given ticket', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);
      final ticket3 = state.createTicket(title: 'C', kind: TicketKind.feature);

      // B and C depend on A
      state.addDependency(ticket2.id, ticket1.id);
      state.addDependency(ticket3.id, ticket1.id);

      final blocked = state.getBlockedBy(ticket1.id);
      expect(blocked.length, 2);
      expect(blocked.contains(ticket2.id), isTrue);
      expect(blocked.contains(ticket3.id), isTrue);
    });
  });

  group('TicketBoardState - Progress', () {
    test('categoryProgress calculates correctly', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.createTicket(
        title: 'A',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
        category: 'Frontend',
      );

      state.createTicket(
        title: 'B',
        kind: TicketKind.feature,
        status: TicketStatus.active,
        category: 'Frontend',
      );

      state.createTicket(
        title: 'C',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
        category: 'Backend',
      );

      final progress = state.categoryProgress;

      expect(progress['Frontend']!.completed, 1);
      expect(progress['Frontend']!.total, 2);
      expect(progress['Backend']!.completed, 1);
      expect(progress['Backend']!.total, 1);
    });

    test('activeCount returns count of active tickets', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.createTicket(
        title: 'A',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      state.createTicket(
        title: 'B',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      state.createTicket(
        title: 'C',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );

      expect(state.activeCount, 2);
    });
  });

  group('TicketBoardState - Persistence', () {
    test('save and load round-trip', () async {
      // Use unique project ID to avoid collision with other tests
      final testProjectId = 'test-project-roundtrip-${DateTime.now().millisecondsSinceEpoch}';
      final persistence = PersistenceService();
      final state = resources.track(TicketBoardState(testProjectId, persistence: persistence));

      // Create some tickets
      state.createTicket(
        title: 'Ticket 1',
        kind: TicketKind.feature,
        description: 'First ticket',
        priority: TicketPriority.high,
        category: 'Frontend',
      );

      state.createTicket(
        title: 'Ticket 2',
        kind: TicketKind.bugfix,
        status: TicketStatus.active,
      );

      // Save explicitly (auto-save might not have completed)
      await state.save();

      // Small delay to ensure file system writes complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Create new state and load
      final state2 = resources.track(TicketBoardState(testProjectId, persistence: persistence));
      await state2.load();

      // Verify
      expect(state2.tickets.length, 2);
      expect(state2.tickets[0].title, 'Ticket 1');
      expect(state2.tickets[0].kind, TicketKind.feature);
      expect(state2.tickets[0].priority, TicketPriority.high);
      expect(state2.tickets[0].category, 'Frontend');

      expect(state2.tickets[1].title, 'Ticket 2');
      expect(state2.tickets[1].kind, TicketKind.bugfix);
      expect(state2.tickets[1].status, TicketStatus.active);
    });

    test('load with no file does not throw', () async {
      final state = resources.track(TicketBoardState('test-project'));

      // Should not throw
      await state.load();

      expect(state.tickets, isEmpty);
    });

    test('load with corrupt file does not throw', () async {
      final state = resources.track(TicketBoardState('test-project'));

      // Write corrupt data
      final persistence = PersistenceService();
      await persistence.saveTickets('test-project', {'invalid': 'data'});

      // Should not throw
      await state.load();

      expect(state.tickets, isEmpty);
    });

    test('createTicket triggers auto-save', () async {
      // Use unique project ID to avoid collision with other tests
      final testProjectId = 'test-project-autosave-${DateTime.now().millisecondsSinceEpoch}';
      final persistence = PersistenceService();
      final state = resources.track(TicketBoardState(testProjectId, persistence: persistence));

      state.createTicket(title: 'Test', kind: TicketKind.feature);

      // Wait for auto-save to complete
      await state.save();

      // Small delay to ensure file system writes complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Load in new state
      final state2 = resources.track(TicketBoardState(testProjectId, persistence: persistence));
      await state2.load();

      expect(state2.tickets.length, 1);
      expect(state2.tickets.first.title, 'Test');
    });

    test('nextId is preserved across save/load', () async {
      // Use a unique project ID to avoid collision with other tests
      final testProjectId = 'test-project-nextid-${DateTime.now().millisecondsSinceEpoch}';
      final persistence = PersistenceService();
      final state = resources.track(TicketBoardState(testProjectId, persistence: persistence));

      state.createTicket(title: 'A', kind: TicketKind.feature);
      state.createTicket(title: 'B', kind: TicketKind.feature);
      state.createTicket(title: 'C', kind: TicketKind.feature);

      // Explicitly verify nextId before save
      expect(state.tickets.length, 3);

      // Save and verify it doesn't throw
      try {
        await state.save();
      } catch (e) {
        fail('Save threw exception: $e');
      }

      // Small delay to ensure file system writes complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify the saved data contains nextId
      final savedData = await persistence.loadTickets(testProjectId);
      expect(savedData, isNotNull, reason: 'Saved data should not be null after save');
      expect(savedData!['nextId'], 4, reason: 'nextId should be 4');

      final state2 = resources.track(TicketBoardState(testProjectId, persistence: persistence));
      await state2.load();

      // Verify loaded state
      expect(state2.tickets.length, 3, reason: 'Should have 3 tickets after load');

      final newTicket = state2.createTicket(title: 'D', kind: TicketKind.feature);
      expect(newTicket.id, 4, reason: 'New ticket should have ID 4');
    });
  });

  group('TicketBoardState - Notifications', () {
    test('createTicket notifies listeners', () {
      final state = resources.track(TicketBoardState('test-project'));
      var notified = false;
      state.addListener(() => notified = true);

      state.createTicket(title: 'Test', kind: TicketKind.feature);

      expect(notified, isTrue);
    });

    test('updateTicket notifies listeners', () {
      final state = resources.track(TicketBoardState('test-project'));
      final ticket = state.createTicket(title: 'Test', kind: TicketKind.feature);

      var notified = false;
      state.addListener(() => notified = true);

      state.updateTicket(ticket.id, (t) => t.copyWith(title: 'Modified'));

      expect(notified, isTrue);
    });

    test('deleteTicket notifies listeners', () {
      final state = resources.track(TicketBoardState('test-project'));
      final ticket = state.createTicket(title: 'Test', kind: TicketKind.feature);

      var notified = false;
      state.addListener(() => notified = true);

      state.deleteTicket(ticket.id);

      expect(notified, isTrue);
    });

    test('selectTicket notifies listeners', () {
      final state = resources.track(TicketBoardState('test-project'));
      final ticket = state.createTicket(title: 'Test', kind: TicketKind.feature);

      var notified = false;
      state.addListener(() => notified = true);

      state.selectTicket(ticket.id);

      expect(notified, isTrue);
    });

    test('setSearchQuery notifies listeners', () {
      final state = resources.track(TicketBoardState('test-project'));

      var notified = false;
      state.addListener(() => notified = true);

      state.setSearchQuery('test');

      expect(notified, isTrue);
    });

    test('addDependency notifies listeners', () {
      final state = resources.track(TicketBoardState('test-project'));
      final ticket1 = state.createTicket(title: 'A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'B', kind: TicketKind.feature);

      var notified = false;
      state.addListener(() => notified = true);

      state.addDependency(ticket2.id, ticket1.id);

      expect(notified, isTrue);
    });
  });

  group('TicketBoardState - Status methods', () {
    test('setStatus changes ticket status', () {
      final state = resources.track(TicketBoardState('test-project'));
      final ticket = state.createTicket(title: 'Test', kind: TicketKind.feature);

      state.setStatus(ticket.id, TicketStatus.active);

      expect(state.getTicket(ticket.id)!.status, TicketStatus.active);
    });

    test('markCompleted sets status to completed', () {
      final state = resources.track(TicketBoardState('test-project'));
      final ticket = state.createTicket(title: 'Test', kind: TicketKind.feature);

      state.markCompleted(ticket.id);

      expect(state.getTicket(ticket.id)!.status, TicketStatus.completed);
    });

    test('markCancelled sets status to cancelled', () {
      final state = resources.track(TicketBoardState('test-project'));
      final ticket = state.createTicket(title: 'Test', kind: TicketKind.feature);

      state.markCancelled(ticket.id);

      expect(state.getTicket(ticket.id)!.status, TicketStatus.cancelled);
    });
  });

  group('TicketBoardState - Auto-readiness notifications', () {
    test('onTicketReady fires when blocked ticket becomes ready', () {
      final state = resources.track(TicketBoardState('test-project'));

      // Create dependency chain: ticket2 depends on ticket1
      final ticket1 = state.createTicket(title: 'Dependency', kind: TicketKind.feature);
      final ticket2 = state.createTicket(
        title: 'Dependent',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [ticket1.id],
      );

      // Listen for the ready ticket via stream
      TicketData? readyTicket;
      final sub = state.onTicketReady.listen((ticket) {
        readyTicket = ticket;
      });
      addTearDown(sub.cancel);

      // Complete the dependency
      state.markCompleted(ticket1.id);

      // Verify event was emitted with the correct ticket
      expect(readyTicket, isNotNull);
      expect(readyTicket!.id, ticket2.id);
      expect(readyTicket!.status, TicketStatus.ready);
    });

    test('onTicketReady does not fire for manual status change', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
      );

      // Listen via stream
      var eventFired = false;
      final sub = state.onTicketReady.listen((ticket) {
        eventFired = true;
      });
      addTearDown(sub.cancel);

      // Manually set status to ready
      state.setStatus(ticket.id, TicketStatus.ready);

      // Verify event was NOT emitted
      expect(eventFired, isFalse);
    });

    test('onTicketReady fires for multiple tickets becoming ready', () {
      final state = resources.track(TicketBoardState('test-project'));

      // Create dependency chain: ticket2 and ticket3 both depend on ticket1
      final ticket1 = state.createTicket(title: 'Shared dependency', kind: TicketKind.feature);
      final ticket2 = state.createTicket(
        title: 'Dependent A',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [ticket1.id],
      );
      final ticket3 = state.createTicket(
        title: 'Dependent B',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [ticket1.id],
      );

      // Capture all ready tickets via stream
      final readyTickets = <TicketData>[];
      final sub = state.onTicketReady.listen((ticket) {
        readyTickets.add(ticket);
      });
      addTearDown(sub.cancel);

      // Complete the shared dependency
      state.markCompleted(ticket1.id);

      // Verify events were emitted for both tickets
      expect(readyTickets.length, 2);
      expect(readyTickets.map((t) => t.id).toSet(), {ticket2.id, ticket3.id});
      expect(readyTickets.every((t) => t.status == TicketStatus.ready), isTrue);
    });

    test('onTicketReady does not fire when ticket not blocked', () {
      final state = resources.track(TicketBoardState('test-project'));

      // Create dependency where dependent is already ready
      final ticket1 = state.createTicket(title: 'Dependency', kind: TicketKind.feature);
      final ticket2 = state.createTicket(
        title: 'Dependent',
        kind: TicketKind.feature,
        status: TicketStatus.ready, // Already ready, not blocked
        dependsOn: [ticket1.id],
      );

      // Listen via stream
      var eventFired = false;
      final sub = state.onTicketReady.listen((ticket) {
        eventFired = true;
      });
      addTearDown(sub.cancel);

      // Complete the dependency
      state.markCompleted(ticket1.id);

      // Verify event was NOT emitted (ticket was already ready)
      expect(eventFired, isFalse);
    });

    test('onTicketReady does not fire when dependencies not all complete', () {
      final state = resources.track(TicketBoardState('test-project'));

      // Create dependency chain: ticket3 depends on ticket1 AND ticket2
      final ticket1 = state.createTicket(title: 'Dependency A', kind: TicketKind.feature);
      final ticket2 = state.createTicket(title: 'Dependency B', kind: TicketKind.feature);
      final ticket3 = state.createTicket(
        title: 'Dependent',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [ticket1.id, ticket2.id],
      );

      // Listen via stream
      var eventFired = false;
      final sub = state.onTicketReady.listen((ticket) {
        eventFired = true;
      });
      addTearDown(sub.cancel);

      // Complete only ONE dependency
      state.markCompleted(ticket1.id);

      // Verify event was NOT emitted (not all dependencies complete)
      expect(eventFired, isFalse);
      expect(state.getTicket(ticket3.id)!.status, TicketStatus.blocked);

      // Now complete the other dependency
      state.markCompleted(ticket2.id);

      // NOW event should fire
      expect(eventFired, isTrue);
      expect(state.getTicket(ticket3.id)!.status, TicketStatus.ready);
    });
  });

  group('TicketBoardState - Badge counts', () {
    test('activeCount includes only active tickets', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.createTicket(
        title: 'Ready',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );

      state.createTicket(
        title: 'Active 1',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      state.createTicket(
        title: 'Active 2',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      state.createTicket(
        title: 'Completed',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );

      // Only the two active tickets should be counted
      expect(state.activeCount, 2);
    });

    test('activeCount updates when ticket status changes', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket = state.createTicket(
        title: 'Test',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );

      expect(state.activeCount, 0);

      state.setStatus(ticket.id, TicketStatus.active);
      expect(state.activeCount, 1);

      state.setStatus(ticket.id, TicketStatus.completed);
      expect(state.activeCount, 0);
    });
  });

  group('TicketBoardState - Next Ready Ticket', () {
    test('nextReadyTicket returns null when no tickets are ready', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.createTicket(
        title: 'Active',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      state.createTicket(
        title: 'Completed',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );

      expect(state.nextReadyTicket, isNull);
    });

    test('nextReadyTicket returns highest priority ready ticket', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.createTicket(
        title: 'Low priority',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.low,
      );
      state.createTicket(
        title: 'Medium priority',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.medium,
      );
      final critical = state.createTicket(
        title: 'Critical priority',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.critical,
      );
      state.createTicket(
        title: 'High priority',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
      );

      expect(state.nextReadyTicket?.id, critical.id);
    });

    test('nextReadyTicket breaks ties by ticket ID (lower first)', () {
      final state = resources.track(TicketBoardState('test-project'));

      final ticket1 = state.createTicket(
        title: 'First high',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
      );
      state.createTicket(
        title: 'Second high',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
      );
      state.createTicket(
        title: 'Third high',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
      );

      expect(state.nextReadyTicket?.id, ticket1.id);
    });

    test('nextReadyTicket ignores non-ready tickets', () {
      final state = resources.track(TicketBoardState('test-project'));

      state.createTicket(
        title: 'Active critical',
        kind: TicketKind.feature,
        status: TicketStatus.active,
        priority: TicketPriority.critical,
      );
      final readyMedium = state.createTicket(
        title: 'Ready medium',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.medium,
      );
      state.createTicket(
        title: 'Blocked high',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        priority: TicketPriority.high,
      );

      expect(state.nextReadyTicket?.id, readyMedium.id);
    });

    test('nextReadyTicket priority order is critical > high > medium > low', () {
      final state = resources.track(TicketBoardState('test-project'));

      final low = state.createTicket(
        title: 'Low',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.low,
      );
      final medium = state.createTicket(
        title: 'Medium',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.medium,
      );
      final high = state.createTicket(
        title: 'High',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
      );
      final critical = state.createTicket(
        title: 'Critical',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.critical,
      );

      expect(state.nextReadyTicket?.id, critical.id);

      state.setStatus(critical.id, TicketStatus.active);
      expect(state.nextReadyTicket?.id, high.id);

      state.setStatus(high.id, TicketStatus.completed);
      expect(state.nextReadyTicket?.id, medium.id);

      state.setStatus(medium.id, TicketStatus.cancelled);
      expect(state.nextReadyTicket?.id, low.id);
    });
  });
}
