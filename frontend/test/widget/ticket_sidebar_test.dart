import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/widgets/ticket_sidebar.dart';
import 'package:cc_insights_v2/widgets/ticket_tags_section.dart';
import 'package:cc_insights_v2/widgets/ticket_linked_sections.dart';
import 'package:cc_insights_v2/widgets/ticket_dependency_sections.dart';

import '../test_helpers.dart';

void main() {
  late TestResources resources;
  late TicketRepository repo;

  final now = DateTime(2025, 1, 1);

  TicketData makeTicket({
    int id = 1,
    String title = 'Test ticket',
    Set<String> tags = const {},
    List<int> dependsOn = const [],
    List<LinkedChat> linkedChats = const [],
    List<LinkedWorktree> linkedWorktrees = const [],
    bool isOpen = true,
  }) {
    return TicketData(
      id: id,
      title: title,
      body: '',
      author: 'tester',
      isOpen: isOpen,
      tags: tags,
      dependsOn: dependsOn,
      linkedChats: linkedChats,
      linkedWorktrees: linkedWorktrees,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    resources = TestResources();
    repo = resources.track(TicketRepository('test-sidebar'));
  });

  tearDown(() async => await resources.disposeAll());

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('TicketSidebar', () {
    testWidgets('renders all sections', (tester) async {
      final ticket = makeTicket(
        tags: {'bug', 'ui'},
        linkedChats: [
          const LinkedChat(
            chatId: 'c1',
            chatName: 'Fix login',
            worktreeRoot: '/repo',
          ),
        ],
        linkedWorktrees: [
          const LinkedWorktree(worktreeRoot: '/repo/wt', branch: 'feat-x'),
        ],
        dependsOn: [2],
      );
      final dep = makeTicket(id: 2, title: 'Dep ticket');
      final blocker = makeTicket(id: 3, title: 'Blocked', dependsOn: [1]);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket, dep, blocker],
          repo: repo,
        ),
      ));

      // Tags section
      expect(find.text('TAGS'), findsOneWidget);
      expect(find.text('bug'), findsOneWidget);
      expect(find.text('ui'), findsOneWidget);

      // Linked sections
      expect(find.text('LINKED CHATS'), findsOneWidget);
      expect(find.text('Fix login'), findsOneWidget);
      expect(find.text('LINKED WORKTREES'), findsOneWidget);
      expect(find.text('feat-x'), findsOneWidget);

      // Dependency sections
      expect(find.text('DEPENDS ON'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('BLOCKS'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
    });

    testWidgets('has fixed 200px width', (tester) async {
      final ticket = makeTicket();

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      final sizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(TicketSidebar),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(sizedBox.width, 200);
    });

    testWidgets('is independently scrollable', (tester) async {
      final ticket = makeTicket();

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(
        find.descendant(
          of: find.byType(TicketSidebar),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });

    // --- Tags ---

    testWidgets('displays tags sorted alphabetically', (tester) async {
      final ticket = makeTicket(tags: {'zeta', 'alpha', 'mid'});

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('mid'), findsOneWidget);
      expect(find.text('zeta'), findsOneWidget);
    });

    testWidgets('shows TAGS header even when empty', (tester) async {
      final ticket = makeTicket();

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('TAGS'), findsOneWidget);
    });

    testWidgets('tag removal calls repo.removeTag', (tester) async {
      // Create a ticket in the repo so removeTag can find it.
      final created = repo.createTicket(title: 'Tagged ticket');
      repo.addTag(created.id, 'removeme', 'user', AuthorType.user);
      final ticket = repo.tickets.firstWhere((t) => t.id == created.id);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: repo.tickets,
          repo: repo,
        ),
      ));

      // Tap the close icon on the tag chip
      await tester.tap(find.byIcon(Icons.close).first);

      // The tag should be removed from the repo
      final updated = repo.tickets.firstWhere((t) => t.id == created.id);
      expect(updated.tags.contains('removeme'), isFalse);
    });

    // --- Linked Chats ---

    testWidgets('shows linked chats with names', (tester) async {
      final ticket = makeTicket(
        linkedChats: [
          const LinkedChat(
            chatId: 'c1',
            chatName: 'Chat Alpha',
            worktreeRoot: '/repo',
          ),
          const LinkedChat(
            chatId: 'c2',
            chatName: 'Chat Beta',
            worktreeRoot: '/repo2',
          ),
        ],
      );

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('Chat Alpha'), findsOneWidget);
      expect(find.text('Chat Beta'), findsOneWidget);
    });

    testWidgets('hides linked chats section when empty', (tester) async {
      final ticket = makeTicket();

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('LINKED CHATS'), findsNothing);
    });

    testWidgets('fires onChatTap callback', (tester) async {
      LinkedChat? tappedChat;
      final chat = const LinkedChat(
        chatId: 'c1',
        chatName: 'My Chat',
        worktreeRoot: '/repo',
      );
      final ticket = makeTicket(linkedChats: [chat]);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
          onChatTap: (c) => tappedChat = c,
        ),
      ));

      await tester.tap(find.text('My Chat'));
      expect(tappedChat, chat);
    });

    // --- Linked Worktrees ---

    testWidgets('shows linked worktrees with branch names', (tester) async {
      final ticket = makeTicket(
        linkedWorktrees: [
          const LinkedWorktree(
            worktreeRoot: '/repo/wt1',
            branch: 'feature-a',
          ),
        ],
      );

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('LINKED WORKTREES'), findsOneWidget);
      expect(find.text('feature-a'), findsOneWidget);
    });

    testWidgets('hides linked worktrees section when empty', (tester) async {
      final ticket = makeTicket();

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('LINKED WORKTREES'), findsNothing);
    });

    testWidgets('fires onWorktreeTap callback', (tester) async {
      LinkedWorktree? tappedWt;
      const wt = LinkedWorktree(worktreeRoot: '/wt', branch: 'br');
      final ticket = makeTicket(linkedWorktrees: [wt]);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
          onWorktreeTap: (w) => tappedWt = w,
        ),
      ));

      await tester.tap(find.text('br'));
      expect(tappedWt, wt);
    });

    // --- Dependencies ---

    testWidgets('shows depends-on tickets with status icons', (tester) async {
      final openDep = makeTicket(id: 2, title: 'Open dep', isOpen: true);
      final closedDep = makeTicket(id: 3, title: 'Closed dep', isOpen: false);
      final ticket = makeTicket(dependsOn: [2, 3]);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket, openDep, closedDep],
          repo: repo,
        ),
      ));

      expect(find.text('DEPENDS ON'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);

      // Open dep has circle_outlined, closed dep has check_circle
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('hides depends-on section when empty', (tester) async {
      final ticket = makeTicket();

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('DEPENDS ON'), findsNothing);
    });

    testWidgets('fires onTicketTap when dependency tapped', (tester) async {
      int? tappedId;
      final dep = makeTicket(id: 5, title: 'Dep');
      final ticket = makeTicket(dependsOn: [5]);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket, dep],
          repo: repo,
          onTicketTap: (id) => tappedId = id,
        ),
      ));

      await tester.tap(find.text('#5'));
      expect(tappedId, 5);
    });

    // --- Blocks (reverse deps) ---

    testWidgets('shows reverse dependencies in Blocks section',
        (tester) async {
      final ticket = makeTicket(id: 10, title: 'Base');
      final blocked1 =
          makeTicket(id: 11, title: 'Blocked A', dependsOn: [10]);
      final blocked2 =
          makeTicket(id: 12, title: 'Blocked B', dependsOn: [10]);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket, blocked1, blocked2],
          repo: repo,
        ),
      ));

      expect(find.text('BLOCKS'), findsOneWidget);
      expect(find.text('#11'), findsOneWidget);
      expect(find.text('#12'), findsOneWidget);
    });

    testWidgets('hides blocks section when no reverse deps', (tester) async {
      final ticket = makeTicket(id: 10);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      expect(find.text('BLOCKS'), findsNothing);
    });

    testWidgets('fires onTicketTap when blocked ticket tapped',
        (tester) async {
      int? tappedId;
      final ticket = makeTicket(id: 10);
      final blocked = makeTicket(id: 20, title: 'Blocked', dependsOn: [10]);

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket, blocked],
          repo: repo,
          onTicketTap: (id) => tappedId = id,
        ),
      ));

      await tester.tap(find.text('#20'));
      expect(tappedId, 20);
    });

    // --- Combined empty state ---

    testWidgets('renders minimal sidebar when ticket has no linked data',
        (tester) async {
      final ticket = makeTicket();

      await tester.pumpWidget(wrap(
        TicketSidebar(
          ticket: ticket,
          allTickets: [ticket],
          repo: repo,
        ),
      ));

      // Only TAGS header should be visible
      expect(find.text('TAGS'), findsOneWidget);
      expect(find.text('LINKED CHATS'), findsNothing);
      expect(find.text('LINKED WORKTREES'), findsNothing);
      expect(find.text('DEPENDS ON'), findsNothing);
      expect(find.text('BLOCKS'), findsNothing);
    });
  });
}
