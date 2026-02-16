import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
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

  group('TicketRepository - splitTicket', () {
    test('creates children with correct titles and kinds', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
        priority: TicketPriority.high,
        effort: TicketEffort.large,
        category: 'Frontend',
      );

      final children = state.splitTicket(parent.id, [
        (title: 'Subtask A', kind: TicketKind.feature),
        (title: 'Subtask B', kind: TicketKind.bugfix),
        (title: 'Subtask C', kind: TicketKind.test),
      ]);

      expect(children.length, 3);
      expect(children[0].title, 'Subtask A');
      expect(children[0].kind, TicketKind.feature);
      expect(children[1].title, 'Subtask B');
      expect(children[1].kind, TicketKind.bugfix);
      expect(children[2].title, 'Subtask C');
      expect(children[2].kind, TicketKind.test);
    });

    test('parent becomes split status and split kind', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
      );

      state.splitTicket(parent.id, [
        (title: 'Sub 1', kind: TicketKind.feature),
      ]);

      final updatedParent = state.getTicket(parent.id)!;
      expect(updatedParent.status, TicketStatus.split);
      expect(updatedParent.kind, TicketKind.split);
    });

    test('children depend on parent', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
      );

      final children = state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
        (title: 'Sub B', kind: TicketKind.bugfix),
      ]);

      for (final child in children) {
        expect(child.dependsOn, [parent.id]);
      }
    });

    test('children inherit category from parent', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
        category: 'Auth & Permissions',
      );

      final children = state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
        (title: 'Sub B', kind: TicketKind.bugfix),
      ]);

      for (final child in children) {
        expect(child.category, 'Auth & Permissions');
      }
    });

    test('children inherit priority and effort from parent', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
        priority: TicketPriority.critical,
        effort: TicketEffort.large,
      );

      final children = state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
      ]);

      expect(children[0].priority, TicketPriority.critical);
      expect(children[0].effort, TicketEffort.large);
    });

    test('empty subtasks throws ArgumentError', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
      );

      expect(
        () => state.splitTicket(parent.id, []),
        throwsArgumentError,
      );
    });

    test('non-existent parent throws ArgumentError', () {
      final state = resources.track(TicketRepository('test-project'));

      expect(
        () => state.splitTicket(999, [
          (title: 'Sub A', kind: TicketKind.feature),
        ]),
        throwsArgumentError,
      );
    });

    test('children have status ready', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
      );

      final children = state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
        (title: 'Sub B', kind: TicketKind.bugfix),
      ]);

      for (final child in children) {
        expect(child.status, TicketStatus.ready);
      }
    });

    test('split ticket is terminal', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
      );

      state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
      ]);

      final updatedParent = state.getTicket(parent.id)!;
      expect(updatedParent.isTerminal, isTrue);
    });

    test('notifies listeners', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
      );

      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
      ]);

      // At least 1 notify: parent update + child create
      expect(notifyCount, greaterThan(0));
    });

    test('children get sequential IDs', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
      );
      // parent has ID 1

      final children = state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
        (title: 'Sub B', kind: TicketKind.bugfix),
      ]);

      expect(children[0].id, 2);
      expect(children[1].id, 3);
    });

    test('parent without category creates children without category', () {
      final state = resources.track(TicketRepository('test-project'));

      final parent = state.createTicket(
        title: 'Big feature',
        kind: TicketKind.feature,
        // No category
      );

      final children = state.splitTicket(parent.id, [
        (title: 'Sub A', kind: TicketKind.feature),
      ]);

      expect(children[0].category, isNull);
    });
  });
}
