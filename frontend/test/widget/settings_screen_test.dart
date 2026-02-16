import 'dart:io';

import 'package:cc_insights_v2/models/agent_config.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/screens/settings_screen.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:cc_insights_v2/services/internal_tools_service.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:cc_insights_v2/widgets/security_config_group.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_cli_availability_service.dart';
import '../test_helpers.dart';

void main() {
  late Directory tempDir;
  late SettingsService settingsService;
  late MockBackendService mockBackend;
  late FakeCliAvailabilityService fakeCliAvailability;
  late InternalToolsService internalToolsService;
  late TicketRepository repo;
  late BulkProposalState bulkState;
  late ProjectState projectState;

  setUp(() {
    RuntimeConfig.resetForTesting();
    RuntimeConfig.initialize([]);
    tempDir = Directory.systemTemp.createTempSync('settings_screen_test_');
    settingsService = SettingsService(
      configPath: '${tempDir.path}/config.json',
    );
    mockBackend = MockBackendService();
    fakeCliAvailability = FakeCliAvailabilityService();
    internalToolsService = InternalToolsService();
    repo = TicketRepository('test-project');
    bulkState = BulkProposalState(repo);
    projectState = ProjectState(
      const ProjectData(name: 'Test', repoRoot: '/test'),
      WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test',
          isPrimary: true,
          branch: 'main',
          uncommittedFiles: 0,
          stagedFiles: 0,
          commitsAhead: 0,
          commitsBehind: 0,
          hasMergeConflict: false,
        ),
      ),
      autoValidate: false,
      watchFilesystem: false,
    );
  });

  tearDown(() {
    settingsService.dispose();
    mockBackend.dispose();
    internalToolsService.dispose();
    repo.dispose();
    bulkState.dispose();
    projectState.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget createTestApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BackendService>.value(value: mockBackend),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<CliAvailabilityService>.value(
          value: fakeCliAvailability,
        ),
        ChangeNotifierProvider<InternalToolsService>.value(
          value: internalToolsService,
        ),
        ChangeNotifierProvider<TicketRepository>.value(
          value: repo,
        ),
        ChangeNotifierProvider<BulkProposalState>.value(
          value: bulkState,
        ),
        ChangeNotifierProvider<ProjectState>.value(value: projectState),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SettingsScreen()),
      ),
    );
  }

  group('SettingsScreen', () {
    group('sidebar', () {
      testWidgets('renders all category labels', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // "Appearance" appears in sidebar AND as content header
        expect(find.text('Appearance'), findsWidgets);
        expect(find.text('Behavior'), findsOneWidget);
        expect(find.text('Session'), findsOneWidget);
        expect(find.text('Developer'), findsOneWidget);
        expect(find.text('Project Mgmt'), findsOneWidget);
      });

      testWidgets('renders Settings header', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets('renders Reset to Defaults button', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(find.text('Reset to Defaults'), findsOneWidget);
      });

      testWidgets('switching category changes content', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Initially shows Appearance content
        expect(find.text('Bash Tool Summary'), findsOneWidget);

        // Tap on Session category
        await tester.tap(find.text('Session'));
        await safePumpAndSettle(tester);

        // Now shows Session content
        expect(find.text('Show Stream of Thought'), findsOneWidget);
        // Appearance settings should be gone
        expect(find.text('Bash Tool Summary'), findsNothing);
      });
    });

    group('content', () {
      testWidgets('shows category description', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(
          find.text(
            'Customize how CC Insights looks and displays information',
          ),
          findsOneWidget,
        );
      });

      testWidgets('renders appearance settings', (tester) async {
        await tester.pumpWidget(createTestApp());

        // Use a large enough surface so all settings are visible
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        expect(find.text('Bash Tool Summary'), findsOneWidget);
        expect(find.text('Relative File Paths'), findsOneWidget);
        expect(find.text('Show Timestamps'), findsOneWidget);

        // Scroll down to see the last setting
        await tester.scrollUntilVisible(
          find.text('Timestamp Idle Threshold'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Timestamp Idle Threshold'), findsOneWidget);

        // Reset surface size
        await tester.binding.setSurfaceSize(null);
      });
    });

    group('toggle setting', () {
      testWidgets('renders switch widget', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        final switches = tester.widgetList<Switch>(find.byType(Switch));
        expect(switches.isNotEmpty, isTrue);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('toggling updates value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        expect(
          settingsService.getValue<bool>('appearance.showTimestamps'),
          false,
        );

        // Scroll down to Show Timestamps and tap its switch
        await tester.scrollUntilVisible(
          find.text('Show Timestamps'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        // Find the switch closest to Show Timestamps text.
        // Relative File Paths is the first toggle, Show Timestamps is
        // the second toggle in Appearance.
        final switches = find.byType(Switch);
        // Ensure the switch itself is visible after scrolling to the text
        await tester.ensureVisible(switches.at(1));
        await tester.pumpAndSettle();
        await tester.tap(switches.at(1));
        await safePumpAndSettle(tester);

        expect(
          settingsService.getValue<bool>('appearance.showTimestamps'),
          true,
        );

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('dropdown setting', () {
      testWidgets('renders dropdown with current value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // "Description" appears as both a code span and
        // dropdown label - just verify it exists
        expect(find.text('Description'), findsWidgets);
      });

      testWidgets('changing dropdown updates value', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Scroll to Bash Tool Summary dropdown (second dropdown
        // after Theme Mode)
        await tester.scrollUntilVisible(
          find.text('Bash Tool Summary'),
          100,
          scrollable: find.byType(Scrollable).last,
        );

        // Find and tap the second dropdown (Bash Tool Summary;
        // first is Theme Mode)
        final dropdown = find.byType(DropdownButton<String>).at(1);
        await tester.tap(dropdown);
        await safePumpAndSettle(tester);

        // Select "Command" from the dropdown menu
        await tester.tap(find.text('Command').last);
        await safePumpAndSettle(tester);

        expect(
          settingsService.getValue<String>('appearance.bashToolSummary'),
          'command',
        );

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('number setting', () {
      testWidgets('renders text field', (tester) async {
        await tester.pumpWidget(createTestApp());

        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Scroll down to see the number input
        await tester.scrollUntilVisible(
          find.text('Timestamp Idle Threshold'),
          100,
          scrollable: find.byType(Scrollable).last,
        );

        // Find the TextField for the number input
        final textField = find.byType(TextField);
        expect(textField, findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('reset to defaults', () {
      testWidgets('shows confirmation dialog', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Reset to Defaults'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.text('This will reset all settings to their '
              'default values. This cannot be undone.'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);
      });

      testWidgets('cancel closes dialog without resetting',
          (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Change a value directly on the service (not through UI)
        settingsService.setValue('appearance.bashToolSummary', 'command');
        await tester.pump();

        // Open the reset dialog
        await tester.tap(find.text('Reset to Defaults'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Value should still be changed
        expect(
          settingsService.getValue<String>('appearance.bashToolSummary'),
          'command',
        );
      });

      testWidgets('confirm resets all values', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Change a value directly on the service (not through UI)
        settingsService.setValue('appearance.bashToolSummary', 'command');
        await tester.pump();

        // Open the reset dialog
        await tester.tap(find.text('Reset to Defaults'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Confirm reset
        await tester.tap(find.text('Reset'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          settingsService.getValue<String>('appearance.bashToolSummary'),
          'description',
        );
      });
    });

    group('project mgmt category', () {
      testWidgets('shows Agent Ticket Tools toggle', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Navigate to Project Mgmt category
        await tester.tap(find.text('Project Mgmt'));
        await safePumpAndSettle(tester);

        expect(find.text('Agent Ticket Tools'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('toggling off unregisters ticket tools', (tester) async {
        // Register tools first
        internalToolsService.registerTicketTools(bulkState);
        expect(internalToolsService.registry['create_ticket'], isNotNull);

        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Navigate to Project Mgmt category
        await tester.tap(find.text('Project Mgmt'));
        await safePumpAndSettle(tester);

        // Toggle off - find the switch and tap it
        final switches = find.byType(Switch);
        expect(switches, findsOneWidget);
        await tester.tap(switches.first);
        await safePumpAndSettle(tester);

        expect(
          settingsService.getValue<bool>('projectMgmt.agentTicketTools'),
          false,
        );
        expect(internalToolsService.registry['create_ticket'], isNull);

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('agents category', () {
      testWidgets('renders agent list with default agents', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Navigate to Agents category
        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Should show the header
        expect(find.text('Agents'), findsWidgets); // sidebar + header
        expect(
          find.text('Configure AI agents and their backend drivers'),
          findsOneWidget,
        );

        // Should show the 3 default agents (Claude also appears in the
        // name text field since it's auto-selected, so use findsWidgets)
        expect(find.text('Claude'), findsWidgets);
        expect(find.text('Codex'), findsOneWidget);
        expect(find.text('Gemini'), findsOneWidget);

        // Should show driver badges
        expect(find.text('claude'), findsOneWidget);
        expect(find.text('codex'), findsOneWidget);
        expect(find.text('acp'), findsOneWidget);

        // Should show Add Agent button
        expect(find.text('Add Agent'), findsOneWidget);

        // Verify 3 agents via the service
        expect(settingsService.availableAgents.length, 3);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('selecting an agent shows detail form', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // First agent is auto-selected, so detail form should be visible
        expect(find.text('Agent Configuration'), findsOneWidget);
        expect(find.text('Name'), findsOneWidget);
        expect(find.text('Driver'), findsOneWidget);
        expect(find.text('CLI Path'), findsOneWidget);
        expect(find.text('CLI Arguments'), findsOneWidget);
        expect(find.text('Default Model'), findsOneWidget);
        expect(find.text('Environment'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('selecting a different agent loads its config',
          (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Tap on Codex agent
        await tester.tap(find.text('Codex'));
        await safePumpAndSettle(tester);

        // Detail form should show Codex security config group
        expect(find.text('Security'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('claude driver shows Default Permissions, not Codex fields',
          (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Claude is auto-selected
        expect(find.text('Default Permissions'), findsOneWidget);
        expect(find.byType(SecurityConfigGroup), findsNothing);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('add agent creates new agent and selects it',
          (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Should have 3 default agents
        expect(settingsService.availableAgents.length, 3);

        // Tap Add Agent
        await tester.tap(find.text('Add Agent'));
        await safePumpAndSettle(tester);

        // Should now have 4 agents
        expect(settingsService.availableAgents.length, 4);

        // New agent appears in agent row and in name text field
        expect(find.text('New Agent'), findsWidgets);

        // Detail form should be showing for the new agent
        expect(find.text('Agent Configuration'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('remove agent shows confirmation dialog', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Scroll to and tap Remove Agent button
        final removeBtn = find.text('Remove Agent');
        await tester.scrollUntilVisible(
          removeBtn,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(removeBtn);
        await safePumpAndSettle(tester);

        await tester.tap(removeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Confirmation dialog should appear
        expect(find.textContaining('Are you sure'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('cancel remove does not delete agent', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        final agentCount = settingsService.availableAgents.length;

        final removeBtn = find.text('Remove Agent');
        await tester.scrollUntilVisible(
          removeBtn,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(removeBtn);
        await safePumpAndSettle(tester);

        await tester.tap(removeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Cancel
        await tester.tap(find.text('Cancel'));
        await safePumpAndSettle(tester);

        expect(settingsService.availableAgents.length, agentCount);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('confirm remove deletes agent', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        final agentCount = settingsService.availableAgents.length;

        final removeBtn = find.text('Remove Agent');
        await tester.scrollUntilVisible(
          removeBtn,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(removeBtn);
        await safePumpAndSettle(tester);

        await tester.tap(removeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Find the Remove button in the dialog
        final dialogRemove = find.widgetWithText(FilledButton, 'Remove');
        await tester.tap(dialogRemove);
        await safePumpAndSettle(tester);

        expect(settingsService.availableAgents.length, agentCount - 1);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('set as default marks agent as default', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Select Codex (not the default)
        await tester.tap(find.text('Codex'));
        await safePumpAndSettle(tester);

        // Scroll to Set as Default button
        final setDefaultBtn = find.text('Set as Default');
        await tester.scrollUntilVisible(
          setDefaultBtn,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(setDefaultBtn);
        await safePumpAndSettle(tester);

        await tester.tap(setDefaultBtn);
        await safePumpAndSettle(tester);

        expect(settingsService.defaultAgentId, 'codex-default');

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('editing name saves to settings service', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // The first agent (Claude) is auto-selected. Find the Name text field.
        // Name uses InsightsTextField which wraps a TextField.
        // Find the TextField that currently contains 'Claude'.
        final nameField = find.widgetWithText(TextField, 'Claude');
        expect(nameField, findsOneWidget);

        // Clear and type new name
        await tester.tap(nameField);
        await safePumpAndSettle(tester);
        await tester.enterText(nameField, 'My Claude');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await safePumpAndSettle(tester);

        // Verify the agent was updated
        final agent = settingsService.agentById('claude-default');
        expect(agent, isNotNull);
        expect(agent!.name, 'My Claude');

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('default agent shows star icon', (tester) async {
        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Default agent (Claude) should have a star icon
        expect(find.byIcon(Icons.star), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('removing agent terminates affected chats', (tester) async {
        // Create a chat with agentId matching 'claude-default' and add
        // it to the projectState's primary worktree.
        final chat = ChatState.create(
          name: 'Test Chat',
          worktreeRoot: '/test',
          agentId: 'claude-default',
        );
        projectState.primaryWorktree.addChat(chat);

        await tester.pumpWidget(createTestApp());
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await safePumpAndSettle(tester);

        // Verify chat is not terminated yet
        expect(chat.agentRemoved, false);

        // Navigate to Agents category
        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Claude is auto-selected. Scroll to Remove Agent and tap it.
        final removeBtn = find.text('Remove Agent');
        await tester.scrollUntilVisible(
          removeBtn,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(removeBtn);
        await safePumpAndSettle(tester);

        await tester.tap(removeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Confirm removal in dialog
        final dialogRemove = find.widgetWithText(FilledButton, 'Remove');
        await tester.tap(dialogRemove);
        await safePumpAndSettle(tester);

        // The chat should now be terminated
        expect(chat.agentRemoved, true);
        expect(chat.isInputEnabled, false);

        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('remove button hidden when only one agent', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Agents'));
        await safePumpAndSettle(tester);

        // Remove agents through the UI until only one remains.
        // Start with 3 default agents, remove 2.
        for (var i = 0; i < 2; i++) {
          // After a removal the selection is cleared, so re-select
          // the first visible agent to show the detail form again.
          final agentName = settingsService.availableAgents.first.name;
          await tester.tap(find.text(agentName).first);
          await safePumpAndSettle(tester);

          final removeBtn = find.text('Remove Agent');
          await tester.scrollUntilVisible(
            removeBtn,
            100,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.ensureVisible(removeBtn);
          await safePumpAndSettle(tester);

          await tester.tap(removeBtn);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // Confirm removal in dialog
          final dialogRemove = find.widgetWithText(FilledButton, 'Remove');
          await tester.tap(dialogRemove);
          await safePumpAndSettle(tester);
        }

        expect(settingsService.availableAgents.length, 1);

        // Select the last remaining agent
        final lastName = settingsService.availableAgents.first.name;
        await tester.tap(find.text(lastName).first);
        await safePumpAndSettle(tester);

        // Remove Agent button should not be shown when only one agent
        expect(find.text('Remove Agent'), findsNothing);

        await tester.binding.setSurfaceSize(null);
      });
    });

    group('description text', () {
      testWidgets('renders inline code spans', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // The description for Bash Tool Summary contains
        // `Description` and `Command` code spans
        expect(find.text('Description'), findsWidgets);
        expect(find.text('Command'), findsWidgets);
      });
    });

  });
}
