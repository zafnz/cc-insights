import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:cc_insights_v2/widgets/ticket_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketRepository repo;
  late TicketViewState viewState;

  setUp(() {
    repo = resources.track(TicketRepository('test-project'));
    viewState = resources.track(TicketViewState(repo));
  });

  tearDown(() async {
    await resources.disposeAll();
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
    testWidgets('shows empty state when no ticket selected', (tester) async {
      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Select a ticket to view details'), findsOneWidget);
    });

    testWidgets('renders header with display ID, title, and status icon',
        (tester) async {
      repo.createTicket(
        title: 'Implement token refresh',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('TKT-001'), findsOneWidget);
      expect(find.text('Implement token refresh'), findsOneWidget);
      expect(find.byType(TicketStatusIcon), findsOneWidget);
    });

    testWidgets('renders metadata pills for status, kind, and priority',
        (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
        priority: TicketPriority.medium,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Status, kind, priority pills show lowercase labels
      expect(find.text('active'), findsOneWidget);
      expect(find.text('feature'), findsOneWidget);
      expect(find.text('medium'), findsOneWidget);

      // Should find MetadataPill widgets
      expect(find.byType(MetadataPill), findsNWidgets(3));
    });

    testWidgets('renders category pill when category is set', (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        category: 'Auth & Permissions',
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // 4 pills: status, kind, priority, category
      expect(find.byType(MetadataPill), findsNWidgets(4));
      expect(find.text('Auth & Permissions'), findsOneWidget);
    });

    testWidgets('does not render category pill when category is null',
        (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // 3 pills: status, kind, priority (no category)
      expect(find.byType(MetadataPill), findsNWidgets(3));
    });

    testWidgets('renders tags when tags exist', (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        tags: {'auth', 'security'},
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.byType(Chip), findsNWidgets(2));
      expect(find.text('auth'), findsOneWidget);
      expect(find.text('security'), findsOneWidget);
    });

    testWidgets('renders description text in card', (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        description: 'This is a detailed description of the ticket.',
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketDetailPanelKeys.descriptionSection),
        findsOneWidget,
      );
      // Markdown renderer receives the description text
      expect(find.text('Description'), findsOneWidget);
    });

    testWidgets('shows "No description" when description is empty',
        (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        description: '',
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('No description'), findsOneWidget);
    });

    testWidgets('renders "Depends on" chips for each dependency',
        (tester) async {
      // Create dependency tickets first
      repo.createTicket(
        title: 'Dependency A',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );
      repo.createTicket(
        title: 'Dependency B',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      // Create the ticket that depends on the others
      repo.createTicket(
        title: 'Main ticket',
        kind: TicketKind.feature,
        dependsOn: [1, 2],
      );
      viewState.selectTicket(3);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Depends on'), findsOneWidget);
      expect(find.text('TKT-001'), findsOneWidget);
      expect(find.text('TKT-002'), findsOneWidget);
    });

    testWidgets('clicking dependency chip selects that ticket', (tester) async {
      repo.createTicket(
        title: 'Dependency ticket',
        kind: TicketKind.feature,
      );
      repo.createTicket(
        title: 'Main ticket',
        kind: TicketKind.feature,
        dependsOn: [1],
      );
      viewState.selectTicket(2);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // Tap the dependency chip
      await tester.tap(find.text('TKT-001'));
      await safePumpAndSettle(tester);

      // Should have selected ticket 1
      expect(viewState.selectedTicket?.id, equals(1));
    });

    testWidgets('renders "Blocks" section with reverse dependencies',
        (tester) async {
      // Create a ticket
      repo.createTicket(
        title: 'Blocker ticket',
        kind: TicketKind.feature,
      );
      // Create tickets that depend on it (blocked by it)
      repo.createTicket(
        title: 'Blocked ticket A',
        kind: TicketKind.feature,
        dependsOn: [1],
      );
      repo.createTicket(
        title: 'Blocked ticket B',
        kind: TicketKind.feature,
        dependsOn: [1],
      );

      // Select the blocker
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.text('Blocks'), findsOneWidget);
      expect(find.text('TKT-002'), findsOneWidget);
      expect(find.text('TKT-003'), findsOneWidget);
    });

    testWidgets('Mark Complete button calls markCompleted', (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.text('Mark Complete'));
      await safePumpAndSettle(tester);

      expect(repo.getTicket(1)?.status, equals(TicketStatus.completed));
    });

    testWidgets('Cancel button calls markCancelled', (tester) async {
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      expect(repo.getTicket(1)?.status, equals(TicketStatus.cancelled));
    });

    testWidgets('cost stats render when costStats is present', (tester) async {
      final now = DateTime.now();
      // We need to create a ticket with costStats, which requires using
      // updateTicket since createTicket doesn't accept costStats
      repo.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
      );
      repo.updateTicket(1, (t) => t.copyWith(
        costStats: const TicketCostStats(
          totalTokens: 45200,
          totalCost: 0.42,
          agentTimeMs: 202000, // 3m 22s
          waitingTimeMs: 65000, // 1m 05s
        ),
      ));
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      expect(find.byKey(TicketDetailPanelKeys.costSection), findsOneWidget);
      expect(find.text('Tokens'), findsOneWidget);
      expect(find.text('Cost'), findsOneWidget);
      expect(find.text('Agent Time'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);

      // Check formatted values
      expect(find.text('45.2k'), findsOneWidget);
      expect(find.text('\$0.42'), findsOneWidget);
      expect(find.text('3m 22s'), findsOneWidget);
      expect(find.text('1m 05s'), findsOneWidget);
    });
  });

  group('TicketDetailPanel - dispatch actions', () {
    late ProjectState project;
    late SelectionState selection;

    setUp(() {
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final linkedWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo-wt/feature-branch',
          isPrimary: false,
          branch: 'feature-branch',
        ),
      );
      project = resources.track(ProjectState(
        const ProjectData(name: 'Test Project', repoRoot: '/test/repo'),
        primaryWorktree,
        linkedWorktrees: [linkedWorktree],
        autoValidate: false,
        watchFilesystem: false,
      ));
      selection = resources.track(SelectionState(project));
    });

    Widget createTestAppWithProviders() {
      return MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<TicketRepository>.value(value: repo),
              ChangeNotifierProvider<TicketViewState>.value(value: viewState),
              ChangeNotifierProvider<ProjectState>.value(value: project),
              ChangeNotifierProvider<SelectionState>.value(value: selection),
              Provider<GitService>.value(value: const RealGitService()),
            ],
            child: const TicketDetailPanel(),
          ),
        ),
      );
    }

    testWidgets('Begin buttons enabled when ticket is ready', (tester) async {
      repo.createTicket(
        title: 'Ready ticket',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      // Find the Begin buttons by key
      final beginNewWt = tester.widget<FilledButton>(
        find.byKey(TicketDetailPanelKeys.beginNewWorktreeButton),
      );
      final beginInWt = tester.widget<OutlinedButton>(
        find.byKey(TicketDetailPanelKeys.beginInWorktreeButton),
      );

      expect(beginNewWt.onPressed, isNotNull);
      expect(beginInWt.onPressed, isNotNull);
    });

    testWidgets('Begin buttons enabled when ticket needs input', (tester) async {
      repo.createTicket(
        title: 'Needs input ticket',
        kind: TicketKind.feature,
        status: TicketStatus.needsInput,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      final beginNewWt = tester.widget<FilledButton>(
        find.byKey(TicketDetailPanelKeys.beginNewWorktreeButton),
      );
      final beginInWt = tester.widget<OutlinedButton>(
        find.byKey(TicketDetailPanelKeys.beginInWorktreeButton),
      );

      expect(beginNewWt.onPressed, isNotNull);
      expect(beginInWt.onPressed, isNotNull);
    });

    testWidgets('Begin buttons disabled when ticket is active', (tester) async {
      repo.createTicket(
        title: 'Active ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      final beginNewWt = tester.widget<FilledButton>(
        find.byKey(TicketDetailPanelKeys.beginNewWorktreeButton),
      );
      final beginInWt = tester.widget<OutlinedButton>(
        find.byKey(TicketDetailPanelKeys.beginInWorktreeButton),
      );

      expect(beginNewWt.onPressed, isNull);
      expect(beginInWt.onPressed, isNull);
    });

    testWidgets('Open linked chat button shown when linked chats exist',
        (tester) async {
      repo.createTicket(
        title: 'Linked ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      repo.linkChat(1, 'chat-1', 'TKT-001', '/test/repo');
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketDetailPanelKeys.openLinkedChatButton),
        findsOneWidget,
      );
      expect(find.text('Open linked chat'), findsOneWidget);
    });

    testWidgets('Open linked chat button hidden when no linked chats',
        (tester) async {
      repo.createTicket(
        title: 'No links ticket',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketDetailPanelKeys.openLinkedChatButton),
        findsNothing,
      );
    });

    testWidgets('Mark Complete and Cancel hidden when ticket is completed',
        (tester) async {
      repo.createTicket(
        title: 'Completed ticket',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketDetailPanelKeys.markCompleteButton),
        findsNothing,
      );
      expect(
        find.byKey(TicketDetailPanelKeys.cancelButton),
        findsNothing,
      );
    });

    testWidgets('Mark Complete and Cancel hidden when ticket is cancelled',
        (tester) async {
      repo.createTicket(
        title: 'Cancelled ticket',
        kind: TicketKind.feature,
        status: TicketStatus.cancelled,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      expect(
        find.byKey(TicketDetailPanelKeys.markCompleteButton),
        findsNothing,
      );
      expect(
        find.byKey(TicketDetailPanelKeys.cancelButton),
        findsNothing,
      );
    });

    testWidgets('Begin in worktree... opens dialog with worktree options',
        (tester) async {
      repo.createTicket(
        title: 'Ready ticket',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      viewState.selectTicket(1);

      await tester.pumpWidget(createTestAppWithProviders());
      await safePumpAndSettle(tester);

      // Tap "Begin in worktree..."
      await tester.tap(
        find.byKey(TicketDetailPanelKeys.beginInWorktreeButton),
      );
      await safePumpAndSettle(tester);

      // Dialog should appear with worktree options
      expect(find.text('Select worktree'), findsOneWidget);
      expect(find.text('main (primary)'), findsOneWidget);
      expect(find.text('feature-branch'), findsOneWidget);
    });
  });
}
