import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
import 'package:cc_insights_v2/services/author_service.dart' hide AuthorType;
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:cc_insights_v2/widgets/ticket_comment_input.dart';
import 'package:cc_insights_v2/widgets/ticket_dependency_sections.dart';
import 'package:cc_insights_v2/widgets/ticket_edit_form.dart';
import 'package:cc_insights_v2/widgets/ticket_linked_sections.dart';
import 'package:cc_insights_v2/widgets/ticket_sidebar.dart';
import 'package:cc_insights_v2/widgets/ticket_status_badge.dart';
import 'package:cc_insights_v2/widgets/ticket_tags_section.dart';
import 'package:cc_insights_v2/widgets/ticket_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  late TestResources resources;
  late TicketRepository repo;
  late TicketViewState viewState;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    AuthorService.setForTesting('tester');
    resources = TestResources();
    repo = resources.track(TicketRepository('test-project'));
    viewState = resources.track(TicketViewState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
    AuthorService.resetForTesting();
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
          child: const TicketDetailPanel(),
        ),
      ),
    );
  }

  group('TicketDetailPanel', () {
    testWidgets('shows "select a ticket" when no ticket selected',
        (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Select a ticket to view details'), findsOneWidget);
    });

    testWidgets('shows issue header with correct title and status',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      repo.createTicket(title: 'Fix login bug', body: 'Login fails on retry');
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // TicketIssueHeader renders the title and status badge.
      expect(find.byType(TicketIssueHeader), findsOneWidget);
      // Title is rendered in a Text.rich with the display ID appended.
      expect(find.textContaining('Fix login bug'), findsOneWidget);
      // Open ticket shows the "Open" status badge.
      expect(find.byType(TicketStatusBadge), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('timeline column renders body, events, comments',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      repo.createTicket(title: 'Timeline ticket', body: 'The body text');
      // Add a comment.
      repo.addComment(1, 'First comment', 'tester', AuthorType.user);
      // Add an activity event (tag added).
      repo.addTag(1, 'bug', 'tester', AuthorType.user);
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Timeline widget is present.
      expect(find.byType(TicketTimeline), findsOneWidget);
      // Body text rendered in the timeline.
      expect(find.text('The body text'), findsOneWidget);
      // Comment text rendered.
      expect(find.text('First comment'), findsOneWidget);
    });

    testWidgets('sidebar column renders tags, links, dependencies',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Create a dependency ticket.
      repo.createTicket(title: 'Dependency A');
      // Create the main ticket with tags and a dependency.
      repo.createTicket(
        title: 'Main ticket',
        tags: {'auth', 'security'},
        dependsOn: [1],
      );
      // Link a chat to the main ticket.
      repo.linkChat(2, 'chat-1', 'TKT-002', '/test/repo');
      viewState.selectTicket(2);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Sidebar widget is present.
      expect(find.byType(TicketSidebar), findsOneWidget);
      // Tags section rendered.
      expect(find.byType(TagsSection), findsOneWidget);
      // Dependency section rendered.
      expect(find.byType(DependsOnSection), findsOneWidget);
      // Linked chats section rendered.
      expect(find.byType(LinkedChatsSection), findsOneWidget);
    });

    testWidgets('edit button switches to edit mode', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      repo.createTicket(title: 'Editable ticket', body: 'Some body');
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // The issue header has an Edit button.
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await safePumpAndSettle(tester);

      // After tapping Edit, the mode switches and TicketEditForm appears.
      expect(viewState.detailMode, equals(TicketDetailMode.edit));
      expect(find.byType(TicketEditForm), findsOneWidget);
    });

    testWidgets('create mode shows create form', (tester) async {
      viewState.showCreateForm();

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Create mode shows the create placeholder text.
      expect(find.text('Create ticket'), findsOneWidget);
      // Detail content should not be visible.
      expect(find.byType(TicketIssueHeader), findsNothing);
    });

    testWidgets('comment input is present at bottom of timeline',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      repo.createTicket(title: 'Comment ticket', body: 'Body text');
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // TicketCommentInput is present in the timeline column.
      expect(find.byType(TicketCommentInput), findsOneWidget);
      // The comment input has the "Comment" button.
      expect(find.text('Comment'), findsOneWidget);
    });
  });
}
