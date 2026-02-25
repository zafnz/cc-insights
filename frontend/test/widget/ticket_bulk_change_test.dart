// Test file: frontend/test/widget/ticket_bulk_change_test.dart
// Tests V2 ticket multi-selection operations

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late TicketViewState viewState;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    repo = resources.track(TicketRepository('test-bulk'));
    viewState = resources.track(TicketViewState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  group('multi-select toggle', () {
    test('toggleTicketSelected adds and removes ticket IDs', () {
      repo.createTicket(title: 'Task A');
      repo.createTicket(title: 'Task B');

      viewState.toggleTicketSelected(1);
      expect(viewState.selectedTicketIds, {1});

      viewState.toggleTicketSelected(2);
      expect(viewState.selectedTicketIds, {1, 2});

      viewState.toggleTicketSelected(1);
      expect(viewState.selectedTicketIds, {2});
    });
  });

  group('select all filtered', () {
    test('selectAllFilteredTickets selects all visible tickets', () {
      repo.createTicket(title: 'Open 1');
      repo.createTicket(title: 'Open 2');
      repo.createTicket(title: 'Closed 1');
      repo.closeTicket(3, 'test', AuthorType.user);

      // Default filter is isOpen=true → 2 visible
      viewState.selectAllFilteredTickets();
      expect(viewState.selectedTicketIds, {1, 2});
    });
  });

  group('clear selection', () {
    test('clearTicketSelection empties the set', () {
      repo.createTicket(title: 'Task A');
      repo.createTicket(title: 'Task B');

      viewState.toggleTicketSelected(1);
      viewState.toggleTicketSelected(2);
      expect(viewState.selectedTicketIds, {1, 2});

      viewState.clearTicketSelection();
      expect(viewState.selectedTicketIds, isEmpty);
    });

    test('clearTicketSelection is idempotent when empty', () {
      viewState.clearTicketSelection();
      expect(viewState.selectedTicketIds, isEmpty);
    });
  });

  group('bulk delete', () {
    test('deleting selected tickets removes them from repo', () {
      repo.createTicket(title: 'A');
      repo.createTicket(title: 'B');
      repo.createTicket(title: 'C');

      viewState.toggleTicketSelected(1);
      viewState.toggleTicketSelected(2);

      // Perform bulk delete
      for (final id in viewState.selectedTicketIds.toList()) {
        repo.deleteTicket(id);
      }
      viewState.clearTicketSelection();

      expect(repo.tickets.length, 1);
      expect(repo.tickets.first.title, 'C');
      expect(viewState.selectedTicketIds, isEmpty);
    });
  });

  group('bulk close', () {
    test('closing selected tickets sets isOpen to false', () {
      repo.createTicket(title: 'Task A');
      repo.createTicket(title: 'Task B');

      viewState.toggleTicketSelected(1);
      viewState.toggleTicketSelected(2);

      for (final id in viewState.selectedTicketIds.toList()) {
        repo.closeTicket(id, 'test', AuthorType.user);
      }

      expect(repo.getTicket(1)!.isOpen, false);
      expect(repo.getTicket(2)!.isOpen, false);
    });
  });

  group('bulk tag', () {
    test('adding a tag to selected tickets applies it to all', () {
      repo.createTicket(title: 'Task A');
      repo.createTicket(title: 'Task B');

      viewState.toggleTicketSelected(1);
      viewState.toggleTicketSelected(2);

      for (final id in viewState.selectedTicketIds.toList()) {
        repo.addTag(id, 'urgent', 'test', AuthorType.user);
      }

      expect(repo.getTicket(1)!.tags, contains('urgent'));
      expect(repo.getTicket(2)!.tags, contains('urgent'));
    });
  });
}
