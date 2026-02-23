import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendCapabilities, BackendType, PermissionMode;
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:cc_insights_v2/widgets/model_permission_selector.dart';
import 'package:cc_insights_v2/widgets/orchestration_config_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

/// Test-specific [MockBackendService] that allows overriding capabilities
/// and backend type for dialog rendering tests.
class _TestBackendService extends MockBackendService {
  _TestBackendService({
    BackendCapabilities capabilities = const BackendCapabilities(),
    BackendType? backendType,
  })  : _testCapabilities = capabilities,
        _testBackendType = backendType;

  final BackendCapabilities _testCapabilities;
  final BackendType? _testBackendType;

  @override
  BackendType? get backendType => _testBackendType;

  @override
  BackendCapabilities get capabilities => _testCapabilities;

  @override
  BackendCapabilities capabilitiesFor(BackendType type) => _testCapabilities;
}

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

  /// Creates a [TicketRepository] with tickets and returns the repo and IDs.
  (TicketRepository, List<int>) createRepoWithTickets(
    int count, {
    String prefix = 'Test ticket',
  }) {
    final repo = resources.track(
      TicketRepository(
        'test-orch-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final ids = <int>[];
    for (var i = 0; i < count; i++) {
      final ticket = repo.createTicket(
        title: '$prefix ${i + 1}',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ids.add(ticket.id);
    }
    return (repo, ids);
  }

  ProjectState createTestProject({
    List<WorktreeState>? linkedWorktrees,
  }) {
    final primaryWorktree = WorktreeState(
      const WorktreeData(
        worktreeRoot: '/repo',
        isPrimary: true,
        branch: 'main',
      ),
    );
    return resources.track(ProjectState(
      const ProjectData(name: 'Test Project', repoRoot: '/repo'),
      primaryWorktree,
      linkedWorktrees: linkedWorktrees,
      autoValidate: false,
      watchFilesystem: false,
    ));
  }

  Widget createTestApp({
    int ticketCount = 2,
    BackendCapabilities capabilities = const BackendCapabilities(
      supportsModelChange: true,
      supportsPermissionModeChange: true,
      supportsModelListing: true,
    ),
    BackendType? backendType = BackendType.directCli,
    TicketRepository? repoOverride,
    List<int>? ticketIdsOverride,
    ProjectState? projectOverride,
  }) {
    final TicketRepository repo;
    final List<int> ticketIds;

    if (repoOverride != null && ticketIdsOverride != null) {
      repo = repoOverride;
      ticketIds = ticketIdsOverride;
    } else {
      final result = createRepoWithTickets(ticketCount);
      repo = result.$1;
      ticketIds = result.$2;
    }

    final backend = resources.track(_TestBackendService(
      capabilities: capabilities,
      backendType: backendType,
    ));

    final project = projectOverride ?? createTestProject();

    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<TicketRepository>.value(value: repo),
            ChangeNotifierProvider<BackendService>.value(value: backend),
            ChangeNotifierProvider<ProjectState>.value(value: project),
          ],
          child: Builder(
            builder: (context) => OrchestrationConfigDialog(
              ticketIds: ticketIds,
            ),
          ),
        ),
      ),
    );
  }

  group('OrchestrationConfigDialog', () {
    group('rendering', () {
      testWidgets('renders dialog with all expected fields', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Dialog title
        expect(find.text('Run orchestration'), findsOneWidget);

        // Branch field
        expect(
          find.byKey(OrchestrationConfigDialogKeys.branchField),
          findsOneWidget,
        );

        // Model/permission selector
        expect(
          find.byKey(OrchestrationConfigDialogKeys.modelPermissionSelector),
          findsOneWidget,
        );

        // Instructions field
        expect(
          find.byKey(OrchestrationConfigDialogKeys.instructionsField),
          findsOneWidget,
        );

        // Action buttons
        expect(
          find.byKey(OrchestrationConfigDialogKeys.cancelButton),
          findsOneWidget,
        );
        expect(
          find.byKey(OrchestrationConfigDialogKeys.launchButton),
          findsOneWidget,
        );
      });

      testWidgets('shows ticket list', (tester) async {
        await tester.pumpWidget(createTestApp(ticketCount: 2));
        await safePumpAndSettle(tester);

        expect(find.text('Tickets (2)'), findsOneWidget);
        expect(find.textContaining('Test ticket 1'), findsOneWidget);
        expect(find.textContaining('Test ticket 2'), findsOneWidget);
      });

      testWidgets('populates default branch name from ticket IDs',
          (tester) async {
        final (repo, ids) = createRepoWithTickets(3);
        await tester.pumpWidget(createTestApp(
          repoOverride: repo,
          ticketIdsOverride: ids,
        ));
        await safePumpAndSettle(tester);

        final textField = tester.widget<TextField>(
          find.byKey(OrchestrationConfigDialogKeys.branchField),
        );
        check(textField.controller!.text)
            .equals('orchestrate-${ids.first}-${ids.last}');
      });

      testWidgets('populates default instructions', (tester) async {
        final (repo, ids) = createRepoWithTickets(2);
        await tester.pumpWidget(createTestApp(
          repoOverride: repo,
          ticketIdsOverride: ids,
        ));
        await safePumpAndSettle(tester);

        final textField = tester.widget<TextField>(
          find.byKey(OrchestrationConfigDialogKeys.instructionsField),
        );
        check(textField.controller!.text)
            .contains('Run tickets ${ids.join(', ')}');
      });
    });

    group('ModelPermissionSelector integration', () {
      testWidgets('renders model and permission dropdowns', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
          findsOneWidget,
        );
        expect(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
          findsOneWidget,
        );
      });

      testWidgets('shows available Claude models', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Open model dropdown
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
        );
        await tester.pump();

        // Should show Claude model options
        expect(find.text('Default'), findsWidgets);
        expect(find.text('Haiku'), findsWidgets);
        expect(find.text('Sonnet'), findsWidgets);
        expect(find.text('Opus'), findsWidgets);
      });

      testWidgets('allows changing model selection', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Open model dropdown
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
        );
        await tester.pump();

        // Select Opus
        await tester.tap(find.text('Opus').last);
        await safePumpAndSettle(tester);

        // Verify selection updated
        expect(find.text('Opus'), findsOneWidget);
      });

      testWidgets('shows all permission mode options', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Open permission dropdown
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
        );
        await tester.pump();

        expect(find.text('Default'), findsWidgets);
        expect(find.text('Accept Edits'), findsWidgets);
        expect(find.text('Plan Only'), findsWidgets);
        expect(find.text('Bypass All'), findsWidgets);
      });

      testWidgets('allows changing permission mode', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Open permission dropdown
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
        );
        await tester.pump();

        // Select Accept Edits
        await tester.tap(find.text('Accept Edits').last);
        await safePumpAndSettle(tester);

        // Verify selection updated
        expect(find.text('Accept Edits'), findsOneWidget);
      });

      testWidgets('disables dropdowns when backend lacks capabilities',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          capabilities: const BackendCapabilities(
            supportsModelChange: false,
            supportsPermissionModeChange: false,
          ),
        ));
        await safePumpAndSettle(tester);

        // Both dropdowns should be rendered but disabled (wrapped in Tooltip)
        final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
        final disabledMessages = tooltips
            .map((t) => t.message)
            .where((m) => m?.contains('not supported by this backend') ?? false)
            .toList();
        check(disabledMessages.length).isGreaterOrEqual(2);
      });

      testWidgets('enables dropdowns when backend supports changes',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          capabilities: const BackendCapabilities(
            supportsModelChange: true,
            supportsPermissionModeChange: true,
          ),
        ));
        await safePumpAndSettle(tester);

        // Should not have disabled tooltips for the selectors
        final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
        final disabledMessages = tooltips
            .map((t) => t.message)
            .where((m) => m?.contains('not supported by this backend') ?? false)
            .toList();
        check(disabledMessages).isEmpty();
      });

      testWidgets('uses fallback models when no backend type',
          (tester) async {
        await tester.pumpWidget(createTestApp(backendType: null));
        await safePumpAndSettle(tester);

        // Should still render the selector with fallback Claude models
        expect(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
          findsOneWidget,
        );

        // Open model dropdown to verify fallback models
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
        );
        await tester.pump();

        expect(find.text('Default'), findsWidgets);
      });
    });

    group('cancel button', () {
      testWidgets('closes dialog on cancel', (tester) async {
        final (repo, ids) = createRepoWithTickets(1);
        final backend = resources.track(_TestBackendService(
          capabilities: const BackendCapabilities(
            supportsModelChange: true,
            supportsPermissionModeChange: true,
          ),
          backendType: BackendType.directCli,
        ));
        final project = createTestProject();

        await tester.pumpWidget(MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<TicketRepository>.value(value: repo),
              ChangeNotifierProvider<BackendService>.value(value: backend),
              ChangeNotifierProvider<ProjectState>.value(value: project),
            ],
            child: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => MultiProvider(
                      providers: [
                        ChangeNotifierProvider<TicketRepository>.value(
                          value: repo,
                        ),
                        ChangeNotifierProvider<BackendService>.value(
                          value: backend,
                        ),
                        ChangeNotifierProvider<ProjectState>.value(
                          value: project,
                        ),
                      ],
                      child: OrchestrationConfigDialog(ticketIds: ids),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ));
        await safePumpAndSettle(tester);

        // Open the dialog
        await tester.tap(find.text('Open'));
        await safePumpAndSettle(tester);

        // Verify dialog is shown
        expect(find.text('Run orchestration'), findsOneWidget);

        // Tap cancel
        await tester
            .tap(find.byKey(OrchestrationConfigDialogKeys.cancelButton));
        await safePumpAndSettle(tester);

        // Dialog should be dismissed
        expect(find.text('Run orchestration'), findsNothing);
      });
    });
    group('base worktree selector', () {
      testWidgets('renders base worktree dropdown', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(
          find.byKey(OrchestrationConfigDialogKeys.baseWorktreeDropdown),
          findsOneWidget,
        );
      });

      testWidgets('defaults to primary worktree', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(find.text('main (primary)'), findsOneWidget);
      });

      testWidgets('shows all worktrees in dropdown', (tester) async {
        final linkedWt = WorktreeState(
          const WorktreeData(
            worktreeRoot: '/repo-wt/feature',
            isPrimary: false,
            branch: 'feature-branch',
          ),
        );
        final project = createTestProject(linkedWorktrees: [linkedWt]);

        await tester.pumpWidget(createTestApp(projectOverride: project));
        await safePumpAndSettle(tester);

        // Open the dropdown
        await tester.tap(
          find.byKey(OrchestrationConfigDialogKeys.baseWorktreeDropdown),
        );
        await tester.pump();

        expect(find.text('main (primary)'), findsWidgets);
        expect(find.text('feature-branch'), findsWidgets);
      });

      testWidgets('allows selecting a different worktree', (tester) async {
        final linkedWt = WorktreeState(
          const WorktreeData(
            worktreeRoot: '/repo-wt/develop',
            isPrimary: false,
            branch: 'develop',
          ),
        );
        final project = createTestProject(linkedWorktrees: [linkedWt]);

        await tester.pumpWidget(createTestApp(projectOverride: project));
        await safePumpAndSettle(tester);

        // Open the dropdown
        await tester.tap(
          find.byKey(OrchestrationConfigDialogKeys.baseWorktreeDropdown),
        );
        await tester.pump();

        // Select the linked worktree
        await tester.tap(find.text('develop').last);
        await safePumpAndSettle(tester);

        // Verify selection updated
        expect(find.text('develop'), findsOneWidget);
      });
    });
  });

  group('PermissionMode SDK mapping', () {
    test('all SDK permission mode values are known', () {
      const knownApiNames = {
        'default',
        'acceptEdits',
        'bypassPermissions',
        'plan',
      };
      for (final mode in PermissionMode.values) {
        check(knownApiNames.contains(mode.value)).isTrue();
      }
    });
  });
}
