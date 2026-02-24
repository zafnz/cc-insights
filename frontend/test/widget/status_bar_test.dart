import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/widgets/status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();

  setUp(() async {
    await setupTestConfig();
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  /// Creates a minimal ProjectState for testing.
  ProjectState createTestProject() {
    final primaryWorktree = WorktreeState(
      const WorktreeData(
        worktreeRoot: '/test/repo',
        isPrimary: true,
        branch: 'main',
      ),
    );
    return resources.track(
      ProjectState(
        const ProjectData(
          name: 'Test Project',
          repoRoot: '/test/repo',
        ),
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      ),
    );
  }

  group('StatusBar - Project Stats', () {
    testWidgets('shows project stats when showTicketStats is false',
        (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: false),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should show "Connected" status
      expect(find.text('Connected'), findsOneWidget);

      // Should show project stats (1 worktree = the primary worktree)
      expect(find.text('1 worktrees'), findsOneWidget);
      expect(find.text('0 chats'), findsOneWidget);
      expect(find.text('0 agents'), findsOneWidget);
      expect(find.textContaining('Total \$'), findsOneWidget);

      // Should NOT show ticket stats
      expect(find.textContaining('ticket'), findsNothing);
    });
  });

  group('StatusBar - Ticket Stats', () {
    testWidgets('shows total ticket count when showTicketStats is true',
        (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      // Create some open tickets
      repo.createTicket(title: 'Ticket 1', tags: {'feature'});
      repo.createTicket(title: 'Ticket 2', tags: {'bugfix'});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: true),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should show "Connected" status
      expect(find.text('Connected'), findsOneWidget);

      // Should show ticket stats
      expect(find.text('2 tickets'), findsOneWidget);
      expect(find.text('2 open'), findsOneWidget);

      // Should NOT show project stats
      expect(find.textContaining('worktrees'), findsNothing);
      expect(find.textContaining('chats'), findsNothing);
      expect(find.textContaining('agents'), findsNothing);
    });

    testWidgets('uses singular "ticket" when count is 1', (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      // Create one ticket
      repo.createTicket(title: 'Ticket 1', tags: {'feature'});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: true),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should use singular "ticket"
      expect(find.text('1 ticket'), findsOneWidget);
    });

    testWidgets('shows zero tickets when no tickets exist', (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: true),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should show zero tickets
      expect(find.text('0 tickets'), findsOneWidget);

      // Should not show open/closed breakdowns
      expect(find.textContaining('open'), findsNothing);
      expect(find.textContaining('closed'), findsNothing);
    });

    testWidgets('updates reactively when ticket is closed',
        (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      // Create an open ticket
      final ticket = repo.createTicket(
        title: 'Ticket 1',
        tags: {'feature'},
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: true),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Initial state: 1 open
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 open'), findsOneWidget);

      // Close the ticket
      repo.closeTicket(ticket.id, 'test', AuthorType.user);
      await tester.pump();

      // Should update to show 1 closed, 0 open
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 closed'), findsOneWidget);
      expect(find.textContaining('open'), findsNothing);
    });

    testWidgets('shows only non-zero open/closed counts', (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      // Create open and closed tickets
      repo.createTicket(title: 'Ticket 1', tags: {'feature'});
      repo.createTicket(title: 'Ticket 2', tags: {'bugfix'});
      final closed1 = repo.createTicket(title: 'Ticket 3', tags: {'chore'});
      final closed2 = repo.createTicket(title: 'Ticket 4', tags: {'feature'});
      repo.closeTicket(closed1.id, 'test', AuthorType.user);
      repo.closeTicket(closed2.id, 'test', AuthorType.user);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: true),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Should show total and both open/closed counts
      expect(find.text('4 tickets'), findsOneWidget);
      expect(find.text('2 open'), findsOneWidget);
      expect(find.text('2 closed'), findsOneWidget);
    });

    testWidgets('updates when tickets are created', (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: true),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Initial state: 0 tickets
      expect(find.text('0 tickets'), findsOneWidget);

      // Create a new ticket
      repo.createTicket(title: 'New Ticket', tags: {'feature'});
      await tester.pump();

      // Should update to show 1 ticket
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 open'), findsOneWidget);
    });

    testWidgets('updates when tickets are deleted', (tester) async {
      final project = createTestProject();
      final repo = resources.track(
        TicketRepository('test-project'),
      );

      // Create tickets
      final ticket1 = repo.createTicket(
        title: 'Ticket 1',
        tags: {'feature'},
      );
      repo.createTicket(title: 'Ticket 2', tags: {'bugfix'});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketRepository>.value(
              value: repo,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StatusBar(showTicketStats: true),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Initial state: 2 tickets
      expect(find.text('2 tickets'), findsOneWidget);
      expect(find.text('2 open'), findsOneWidget);

      // Delete a ticket
      repo.deleteTicket(ticket1.id);
      await tester.pump();

      // Should update to show 1 ticket
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 open'), findsOneWidget);
    });
  });
}
