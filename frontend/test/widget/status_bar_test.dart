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
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      // Create some tickets
      ticketBoard.createTicket(
        title: 'Ticket 1',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.createTicket(
        title: 'Ticket 2',
        kind: TicketKind.bugfix,
        status: TicketStatus.active,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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
      expect(find.text('1 active'), findsOneWidget);
      expect(find.text('1 ready'), findsOneWidget);

      // Should NOT show project stats
      expect(find.textContaining('worktrees'), findsNothing);
      expect(find.textContaining('chats'), findsNothing);
      expect(find.textContaining('agents'), findsNothing);
    });

    testWidgets('uses singular "ticket" when count is 1', (tester) async {
      final project = createTestProject();
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      // Create one ticket
      ticketBoard.createTicket(
        title: 'Ticket 1',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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

      // Should not show status breakdowns
      expect(find.textContaining('active'), findsNothing);
      expect(find.textContaining('ready'), findsNothing);
      expect(find.textContaining('blocked'), findsNothing);
    });

    testWidgets('updates reactively when ticket status changes',
        (tester) async {
      final project = createTestProject();
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      // Create a ticket in ready state
      final ticket = ticketBoard.createTicket(
        title: 'Ticket 1',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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

      // Initial state: 1 ready, 0 active
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 ready'), findsOneWidget);
      expect(find.textContaining('active'), findsNothing);

      // Change status to active
      ticketBoard.setStatus(ticket.id, TicketStatus.active);
      await tester.pump();

      // Should update to show 1 active, 0 ready
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 active'), findsOneWidget);
      expect(find.textContaining('ready'), findsNothing);
    });

    testWidgets('shows only non-zero status counts', (tester) async {
      final project = createTestProject();
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      // Create tickets with various statuses
      ticketBoard.createTicket(
        title: 'Ticket 1',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.createTicket(
        title: 'Ticket 2',
        kind: TicketKind.bugfix,
        status: TicketStatus.active,
      );
      ticketBoard.createTicket(
        title: 'Ticket 3',
        kind: TicketKind.chore,
        status: TicketStatus.blocked,
      );
      ticketBoard.createTicket(
        title: 'Ticket 4',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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

      // Should show total and non-zero status counts
      expect(find.text('4 tickets'), findsOneWidget);
      expect(find.text('2 active'), findsOneWidget);
      expect(find.text('1 blocked'), findsOneWidget);

      // Should NOT show zero counts
      expect(find.textContaining('ready'), findsNothing);
      expect(find.textContaining('draft'), findsNothing);
      expect(find.textContaining('completed'), findsNothing);
    });

    testWidgets('updates when tickets are created', (tester) async {
      final project = createTestProject();
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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
      ticketBoard.createTicket(
        title: 'New Ticket',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      await tester.pump();

      // Should update to show 1 ticket
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 ready'), findsOneWidget);
    });

    testWidgets('updates when tickets are deleted', (tester) async {
      final project = createTestProject();
      final ticketBoard = resources.track(
        TicketBoardState('test-project'),
      );

      // Create tickets
      final ticket1 = ticketBoard.createTicket(
        title: 'Ticket 1',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.createTicket(
        title: 'Ticket 2',
        kind: TicketKind.bugfix,
        status: TicketStatus.active,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
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
      expect(find.text('1 active'), findsOneWidget);
      expect(find.text('1 ready'), findsOneWidget);

      // Delete a ticket
      ticketBoard.deleteTicket(ticket1.id);
      await tester.pump();

      // Should update to show 1 ticket
      expect(find.text('1 ticket'), findsOneWidget);
      expect(find.text('1 active'), findsOneWidget);
      expect(find.textContaining('ready'), findsNothing);
    });
  });
}
