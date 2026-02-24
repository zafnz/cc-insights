import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/author_service.dart' show AuthorService;
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
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

  TicketRepository createRepo() {
    return resources.track(TicketRepository('test-project'));
  }

  TicketViewState createViewState(TicketRepository repo) {
    return resources.track(TicketViewState(repo));
  }

  group('TicketViewState - defaults', () {
    test('has expected default values', () {
      final repo = createRepo();
      final view = createViewState(repo);

      expect(view.selectedTicketId, isNull);
      expect(view.selectedTicket, isNull);
      expect(view.viewMode, TicketViewMode.list);
      expect(view.detailMode, TicketDetailMode.detail);
      expect(view.searchQuery, '');
      expect(view.isOpenFilter, isTrue);
      expect(view.tagFilters, isEmpty);
      expect(view.sortOrder, TicketSortOrder.newest);
      expect(view.selectedTicketIds, isEmpty);
      expect(view.openCount, 0);
      expect(view.closedCount, 0);
      expect(view.filteredTickets, isEmpty);
    });
  });

  group('TicketViewState - selection', () {
    test('selectTicket sets selectedTicketId and switches to detail mode', () {
      final repo = createRepo();
      repo.createTicket(title: 'Ticket 1');
      final view = createViewState(repo);

      view.selectTicket(1);

      expect(view.selectedTicketId, 1);
      expect(view.selectedTicket, isNotNull);
      expect(view.selectedTicket!.title, 'Ticket 1');
      expect(view.detailMode, TicketDetailMode.detail);
    });

    test('selectTicket(null) clears selection', () {
      final repo = createRepo();
      repo.createTicket(title: 'Ticket 1');
      final view = createViewState(repo);

      view.selectTicket(1);
      view.selectTicket(null);

      expect(view.selectedTicketId, isNull);
      expect(view.selectedTicket, isNull);
    });

    test('selectedTicket returns null for non-existent ID', () {
      final repo = createRepo();
      final view = createViewState(repo);

      view.selectTicket(999);

      expect(view.selectedTicketId, 999);
      expect(view.selectedTicket, isNull);
    });

    test('selectTicket notifies listeners', () {
      final repo = createRepo();
      final view = createViewState(repo);
      var notified = false;
      view.addListener(() => notified = true);

      view.selectTicket(1);

      expect(notified, isTrue);
    });
  });

  group('TicketViewState - view and detail modes', () {
    test('setViewMode updates viewMode', () {
      final repo = createRepo();
      final view = createViewState(repo);

      view.setViewMode(TicketViewMode.graph);

      expect(view.viewMode, TicketViewMode.graph);
    });

    test('setDetailMode updates detailMode', () {
      final repo = createRepo();
      final view = createViewState(repo);

      view.setDetailMode(TicketDetailMode.edit);

      expect(view.detailMode, TicketDetailMode.edit);
    });

    test('showCreateForm sets mode and clears selection', () {
      final repo = createRepo();
      repo.createTicket(title: 'Ticket 1');
      final view = createViewState(repo);

      view.selectTicket(1);
      view.showCreateForm();

      expect(view.detailMode, TicketDetailMode.create);
      expect(view.selectedTicketId, isNull);
    });

    test('showDetail sets mode to detail', () {
      final repo = createRepo();
      final view = createViewState(repo);

      view.setDetailMode(TicketDetailMode.edit);
      view.showDetail();

      expect(view.detailMode, TicketDetailMode.detail);
    });
  });

  group('TicketViewState - openCount and closedCount', () {
    test('counts reflect repository data', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open 1');
      repo.createTicket(title: 'Open 2');
      repo.createTicket(title: 'To close');
      repo.closeTicket(3, 'testuser', AuthorType.user);
      final view = createViewState(repo);

      expect(view.openCount, 2);
      expect(view.closedCount, 1);
    });

    test('counts update when repo changes', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open 1');
      final view = createViewState(repo);

      expect(view.openCount, 1);
      expect(view.closedCount, 0);

      repo.closeTicket(1, 'testuser', AuthorType.user);

      expect(view.openCount, 0);
      expect(view.closedCount, 1);
    });
  });

  group('TicketViewState - isOpenFilter', () {
    test('defaults to showing open tickets', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open ticket');
      repo.createTicket(title: 'Closed ticket');
      repo.closeTicket(2, 'testuser', AuthorType.user);
      final view = createViewState(repo);

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Open ticket');
    });

    test('setIsOpenFilter(false) shows closed tickets', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open ticket');
      repo.createTicket(title: 'Closed ticket');
      repo.closeTicket(2, 'testuser', AuthorType.user);
      final view = createViewState(repo);

      view.setIsOpenFilter(false);

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Closed ticket');
    });

    test('setIsOpenFilter notifies listeners', () {
      final repo = createRepo();
      final view = createViewState(repo);
      var notified = false;
      view.addListener(() => notified = true);

      view.setIsOpenFilter(false);

      expect(notified, isTrue);
    });
  });

  group('TicketViewState - search', () {
    test('search matches title', () {
      final repo = createRepo();
      repo.createTicket(title: 'Auth feature');
      repo.createTicket(title: 'Database migration');
      final view = createViewState(repo);

      view.setSearchQuery('auth');

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Auth feature');
    });

    test('search matches body', () {
      final repo = createRepo();
      repo.createTicket(title: 'Ticket 1', body: 'Fix the login bug');
      repo.createTicket(title: 'Ticket 2', body: 'Add dark mode');
      final view = createViewState(repo);

      view.setSearchQuery('login');

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Ticket 1');
    });

    test('search matches displayId (#id)', () {
      final repo = createRepo();
      repo.createTicket(title: 'First');
      repo.createTicket(title: 'Second');
      repo.createTicket(title: 'Third');
      final view = createViewState(repo);

      view.setSearchQuery('#2');

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Second');
    });

    test('search matches comment text', () {
      final repo = createRepo();
      repo.createTicket(title: 'Ticket 1');
      repo.createTicket(title: 'Ticket 2');
      repo.addComment(1, 'This needs a database index');
      final view = createViewState(repo);

      view.setSearchQuery('database index');

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Ticket 1');
    });

    test('search matches tag names', () {
      final repo = createRepo();
      repo.createTicket(title: 'Ticket 1', tags: {'frontend', 'urgent'});
      repo.createTicket(title: 'Ticket 2', tags: {'backend'});
      final view = createViewState(repo);

      view.setSearchQuery('frontend');

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Ticket 1');
    });

    test('search is case-insensitive', () {
      final repo = createRepo();
      repo.createTicket(title: 'Auth Feature');
      final view = createViewState(repo);

      view.setSearchQuery('AUTH');

      expect(view.filteredTickets.length, 1);
    });

    test('empty search shows all (matching isOpenFilter)', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open 1');
      repo.createTicket(title: 'Open 2');
      final view = createViewState(repo);

      view.setSearchQuery('something');
      expect(view.filteredTickets.length, 0);

      view.setSearchQuery('');
      expect(view.filteredTickets.length, 2);
    });
  });

  group('TicketViewState - tag filters', () {
    test('addTagFilter filters by tag', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1', tags: {'bug', 'frontend'});
      repo.createTicket(title: 'T2', tags: {'feature'});
      repo.createTicket(title: 'T3', tags: {'bug', 'backend'});
      final view = createViewState(repo);

      view.addTagFilter('bug');

      expect(view.filteredTickets.length, 2);
      expect(view.filteredTickets.map((t) => t.title), containsAll(['T1', 'T3']));
    });

    test('multiple tag filters are AND-combined', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1', tags: {'bug', 'frontend'});
      repo.createTicket(title: 'T2', tags: {'bug', 'backend'});
      repo.createTicket(title: 'T3', tags: {'frontend'});
      final view = createViewState(repo);

      view.addTagFilter('bug');
      view.addTagFilter('frontend');

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'T1');
    });

    test('removeTagFilter removes a tag filter', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1', tags: {'bug', 'frontend'});
      repo.createTicket(title: 'T2', tags: {'bug'});
      final view = createViewState(repo);

      view.addTagFilter('bug');
      view.addTagFilter('frontend');
      expect(view.filteredTickets.length, 1);

      view.removeTagFilter('frontend');
      expect(view.filteredTickets.length, 2);
    });

    test('clearTagFilters removes all tag filters', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1', tags: {'bug'});
      repo.createTicket(title: 'T2', tags: {'feature'});
      final view = createViewState(repo);

      view.addTagFilter('bug');
      expect(view.filteredTickets.length, 1);

      view.clearTagFilters();
      expect(view.filteredTickets.length, 2);
    });

    test('addTagFilter is idempotent (no double notification)', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1', tags: {'bug'});
      final view = createViewState(repo);

      view.addTagFilter('bug');
      var notifyCount = 0;
      view.addListener(() => notifyCount++);

      view.addTagFilter('bug');

      expect(notifyCount, 0);
    });

    test('removeTagFilter is idempotent', () {
      final repo = createRepo();
      final view = createViewState(repo);

      var notifyCount = 0;
      view.addListener(() => notifyCount++);

      view.removeTagFilter('nonexistent');

      expect(notifyCount, 0);
    });

    test('clearTagFilters is idempotent when empty', () {
      final repo = createRepo();
      final view = createViewState(repo);

      var notifyCount = 0;
      view.addListener(() => notifyCount++);

      view.clearTagFilters();

      expect(notifyCount, 0);
    });

    test('tagFilters getter returns unmodifiable set', () {
      final repo = createRepo();
      final view = createViewState(repo);

      view.addTagFilter('bug');
      final filters = view.tagFilters;

      expect(() => filters.add('hack'), throwsUnsupportedError);
    });
  });

  group('TicketViewState - sort order', () {
    test('newest sort order (default)', () {
      final repo = createRepo();
      // Create in sequence - IDs 1, 2, 3
      repo.createTicket(title: 'First');
      repo.createTicket(title: 'Second');
      repo.createTicket(title: 'Third');
      final view = createViewState(repo);

      final titles = view.filteredTickets.map((t) => t.title).toList();
      // Newest first: tickets created later have later createdAt
      expect(titles, ['Third', 'Second', 'First']);
    });

    test('oldest sort order', () {
      final repo = createRepo();
      repo.createTicket(title: 'First');
      repo.createTicket(title: 'Second');
      repo.createTicket(title: 'Third');
      final view = createViewState(repo);

      view.setSortOrder(TicketSortOrder.oldest);

      final titles = view.filteredTickets.map((t) => t.title).toList();
      expect(titles, ['First', 'Second', 'Third']);
    });

    test('recentlyUpdated sort order', () {
      final repo = createRepo();
      repo.createTicket(title: 'Old');
      repo.createTicket(title: 'Middle');
      repo.createTicket(title: 'New');
      // Update "Old" to make it most recently updated
      repo.updateTicket(1, title: 'Old (updated)');
      final view = createViewState(repo);

      view.setSortOrder(TicketSortOrder.recentlyUpdated);

      final titles = view.filteredTickets.map((t) => t.title).toList();
      expect(titles.first, 'Old (updated)');
    });

    test('setSortOrder notifies listeners', () {
      final repo = createRepo();
      final view = createViewState(repo);
      var notified = false;
      view.addListener(() => notified = true);

      view.setSortOrder(TicketSortOrder.oldest);

      expect(notified, isTrue);
    });
  });

  group('TicketViewState - combined filters', () {
    test('isOpen + search filters combine correctly', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open auth');
      repo.createTicket(title: 'Open database');
      repo.createTicket(title: 'Closed auth');
      repo.closeTicket(3, 'testuser', AuthorType.user);
      final view = createViewState(repo);

      view.setSearchQuery('auth');

      // Only open tickets matching search
      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Open auth');
    });

    test('isOpen + tags combine correctly', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1', tags: {'bug'});
      repo.createTicket(title: 'T2', tags: {'feature'});
      repo.createTicket(title: 'T3', tags: {'bug'});
      repo.closeTicket(3, 'testuser', AuthorType.user);
      final view = createViewState(repo);

      view.addTagFilter('bug');

      // Only open tickets with 'bug' tag
      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'T1');
    });

    test('all filters combine: isOpen + search + tags', () {
      final repo = createRepo();
      repo.createTicket(title: 'Auth bug', tags: {'bug', 'frontend'});
      repo.createTicket(title: 'Auth feature', tags: {'feature', 'frontend'});
      repo.createTicket(title: 'DB bug', tags: {'bug', 'backend'});
      final view = createViewState(repo);

      view.setSearchQuery('auth');
      view.addTagFilter('bug');

      expect(view.filteredTickets.length, 1);
      expect(view.filteredTickets.first.title, 'Auth bug');
    });
  });

  group('TicketViewState - ticket selection (bulk)', () {
    test('toggleTicketSelected adds and removes', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1');
      repo.createTicket(title: 'T2');
      final view = createViewState(repo);

      view.toggleTicketSelected(1);
      expect(view.selectedTicketIds, {1});

      view.toggleTicketSelected(2);
      expect(view.selectedTicketIds, {1, 2});

      view.toggleTicketSelected(1);
      expect(view.selectedTicketIds, {2});
    });

    test('selectAllFilteredTickets selects all filtered tickets', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open 1');
      repo.createTicket(title: 'Open 2');
      repo.createTicket(title: 'Closed');
      repo.closeTicket(3, 'testuser', AuthorType.user);
      final view = createViewState(repo);

      view.selectAllFilteredTickets();

      // Only open tickets (default filter)
      expect(view.selectedTicketIds, {1, 2});
    });

    test('clearTicketSelection clears all', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1');
      final view = createViewState(repo);

      view.toggleTicketSelected(1);
      expect(view.selectedTicketIds, isNotEmpty);

      view.clearTicketSelection();
      expect(view.selectedTicketIds, isEmpty);
    });

    test('clearTicketSelection is idempotent when empty', () {
      final repo = createRepo();
      final view = createViewState(repo);

      var notifyCount = 0;
      view.addListener(() => notifyCount++);

      view.clearTicketSelection();

      expect(notifyCount, 0);
    });

    test('selectedTicketIds returns unmodifiable set', () {
      final repo = createRepo();
      final view = createViewState(repo);

      view.toggleTicketSelected(1);
      final ids = view.selectedTicketIds;

      expect(() => ids.add(2), throwsUnsupportedError);
    });
  });

  group('TicketViewState - cache invalidation', () {
    test('repo changes invalidate filtered tickets', () {
      final repo = createRepo();
      repo.createTicket(title: 'Open ticket');
      final view = createViewState(repo);

      expect(view.filteredTickets.length, 1);

      repo.createTicket(title: 'Another ticket');

      expect(view.filteredTickets.length, 2);
    });

    test('filter changes invalidate cache', () {
      final repo = createRepo();
      repo.createTicket(title: 'T1', tags: {'bug'});
      repo.createTicket(title: 'T2', tags: {'feature'});
      final view = createViewState(repo);

      expect(view.filteredTickets.length, 2);

      view.addTagFilter('bug');

      expect(view.filteredTickets.length, 1);
    });
  });

  group('TicketViewState - repo listener lifecycle', () {
    test('notifies when repo changes', () {
      final repo = createRepo();
      final view = createViewState(repo);
      var notified = false;
      view.addListener(() => notified = true);

      repo.createTicket(title: 'New ticket');

      expect(notified, isTrue);
    });

    test('dispose removes repo listener', () {
      final repo = createRepo();
      final view = TicketViewState(repo);
      var notified = false;
      view.addListener(() => notified = true);

      view.dispose();
      repo.createTicket(title: 'After dispose');

      expect(notified, isFalse);
    });
  });

  group('TicketDetailMode', () {
    test('label returns expected strings', () {
      expect(TicketDetailMode.detail.label, 'Detail');
      expect(TicketDetailMode.create.label, 'Create');
      expect(TicketDetailMode.edit.label, 'Edit');
    });
  });
}
