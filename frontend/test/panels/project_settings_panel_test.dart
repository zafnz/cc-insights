import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/project_config.dart';
import 'package:cc_insights_v2/models/user_action.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/project_settings_panel.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_persistence_service.dart';
import '../fakes/fake_project_config_service.dart';
import '../test_helpers.dart';

void main() {
  group('ProjectSettingsPanel - Git category', () {
    final resources = TestResources();
    late FakeProjectConfigService fakeConfigService;
    late FakePersistenceService fakePersistenceService;
    late ProjectState projectState;
    late SelectionState selectionState;
    late Future<void> Function() cleanupConfig;

    setUp(() async {
      cleanupConfig = await setupTestConfig();
      fakeConfigService = FakeProjectConfigService();
      fakePersistenceService = FakePersistenceService();

      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
      );

      projectState = resources.track(
        ProjectState(
          const ProjectData(name: 'Test Project', repoRoot: '/test/project'),
          worktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );

      selectionState = resources.track(SelectionState(projectState));
    });

    tearDown(() async {
      await resources.disposeAll();
      await cleanupConfig();
    });

    Widget buildTestWidget({ProjectConfig? config}) {
      if (config != null) {
        fakeConfigService.configs['/test/project'] = config;
      }

      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: projectState),
          ChangeNotifierProvider.value(value: selectionState),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: ProjectSettingsPanel(
                configService: fakeConfigService,
                persistenceService: fakePersistenceService,
                worktreeRootCalculator: (_) async => '/test/.project-wt',
              ),
            ),
          ),
        ),
      );
    }

    /// Pumps the widget and waits for async config load to complete.
    Future<void> pumpAndLoad(WidgetTester tester, Widget widget) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.runAsync(() async {
        await tester.pumpWidget(widget);
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    group('sidebar', () {
      testWidgets('shows Git category in sidebar', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is shown in sidebar and as header (since it's selected by default)
        expect(find.text('Git'), findsNWidgets(2));
      });

      testWidgets('shows all three categories', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        expect(find.text('Lifecycle Hooks'), findsWidgets);
        expect(find.text('User Actions'), findsWidgets);
        // Git is shown in sidebar and as header (since it's selected by default)
        expect(find.text('Git'), findsNWidgets(2));
      });

      testWidgets('selecting Git shows Git content', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is already selected by default, so content should be visible
        // Git header and description should be visible
        expect(
          find.text('Default branch and worktree settings'),
          findsOneWidget,
        );
        expect(find.text('Default base for new worktrees'), findsOneWidget);

        // Hooks content should not be visible
        expect(find.text('Pre-Create'), findsNothing);
      });
    });

    group('git settings content', () {
      testWidgets('shows base selector dropdown with auto default', (
        tester,
      ) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default, so content should be visible
        // Dropdown should be present
        expect(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
          findsOneWidget,
        );

        // Default value should be "Auto (detect upstream)"
        expect(find.text('Auto (detect upstream)'), findsOneWidget);
      });

      testWidgets('shows description text', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default
        expect(
          find.textContaining('Auto-detect checks for an upstream'),
          findsOneWidget,
        );
      });

      testWidgets('does not show custom text field by default', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default
        expect(
          find.byKey(ProjectSettingsPanelKeys.customBaseField),
          findsNothing,
        );
      });

      testWidgets('selecting Custom shows text field', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default
        // Open the dropdown
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Select Custom...
        await tester.tap(find.text('Custom...').last);
        await tester.pump();

        // Custom text field should now be visible
        expect(
          find.byKey(ProjectSettingsPanelKeys.customBaseField),
          findsOneWidget,
        );
      });

      testWidgets('selecting main does not show custom text field', (
        tester,
      ) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default
        // Open the dropdown
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Select main - need to use .last because dropdown shows both
        // the selected item and the menu item
        await tester.tap(find.text('main').last);
        await tester.pump();

        // Custom text field should not be visible
        expect(
          find.byKey(ProjectSettingsPanelKeys.customBaseField),
          findsNothing,
        );
      });
    });

    group('loading persisted config', () {
      testWidgets('loads defaultBase as main from config', (tester) async {
        await pumpAndLoad(
          tester,
          buildTestWidget(config: const ProjectConfig(defaultBase: 'main')),
        );

        // Git is selected by default
        // Should show "main" as the selected value in the dropdown
        final dropdown = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(dropdown.value, 'main');
      });

      testWidgets('loads defaultBase as origin/main from config', (
        tester,
      ) async {
        await pumpAndLoad(
          tester,
          buildTestWidget(
            config: const ProjectConfig(defaultBase: 'origin/main'),
          ),
        );

        // Git is selected by default
        final dropdown = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(dropdown.value, 'origin/main');
      });

      testWidgets('loads custom defaultBase from config', (tester) async {
        await pumpAndLoad(
          tester,
          buildTestWidget(config: const ProjectConfig(defaultBase: 'develop')),
        );

        // Git is selected by default
        // Should show "Custom..." selected
        final dropdown = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(dropdown.value, 'custom');

        // Custom text field should be visible with the value
        expect(
          find.byKey(ProjectSettingsPanelKeys.customBaseField),
          findsOneWidget,
        );

        final textField = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(ProjectSettingsPanelKeys.customBaseField),
            matching: find.byType(TextField),
          ),
        );
        expect(textField.controller?.text, 'develop');
      });

      testWidgets('loads null defaultBase as auto', (tester) async {
        await pumpAndLoad(
          tester,
          buildTestWidget(config: const ProjectConfig.empty()),
        );

        // Git is selected by default
        final dropdown = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(dropdown.value, 'auto');
      });
    });

    group('auto-save config', () {
      testWidgets('auto-saves main selection on dropdown change', (
        tester,
      ) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default
        // Open dropdown and select main
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('main').last);
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // Config should be auto-saved
        final savedConfig = fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, 'main');
      });

      testWidgets('auto-saves origin/main selection on dropdown change', (
        tester,
      ) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default
        // Open dropdown and select origin/main
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('origin/main').last);
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // Config should be auto-saved
        final savedConfig = fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, 'origin/main');
      });

      testWidgets('auto-saves custom on dropdown change then blur', (
        tester,
      ) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Git is selected by default
        // Open dropdown and select Custom...
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('Custom...').last);
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // Config should be auto-saved with null (no custom value yet)
        var savedConfig = fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, isNull);

        // Enter custom value
        await tester.enterText(
          find.byKey(ProjectSettingsPanelKeys.customBaseField),
          'develop',
        );
        await tester.pump();

        // Tap on the dropdown to blur the text field and trigger save
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        // Close the dropdown by tapping elsewhere
        await tester.tapAt(Offset.zero);
        await tester.pump();

        // Config should be updated with custom value
        savedConfig = fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, 'develop');
      });

      testWidgets('auto-saves auto selection (null defaultBase)', (
        tester,
      ) async {
        // Start with a config that has a non-null defaultBase
        await pumpAndLoad(
          tester,
          buildTestWidget(config: const ProjectConfig(defaultBase: 'main')),
        );

        // Git is selected by default
        // Open dropdown and select auto
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('Auto (detect upstream)').last);
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // Config should be auto-saved with null defaultBase
        final savedConfig = fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, isNull);
      });
    });

    group('actions category', () {
      Future<void> selectActionsCategory(WidgetTester tester) async {
        await tester.tap(find.text('User Actions').first);
        await tester.pump();
      }

      testWidgets('shows action type selector and add-action menu', (
        tester,
      ) async {
        await pumpAndLoad(tester, buildTestWidget());
        await selectActionsCategory(tester);

        expect(find.text('Action Type'), findsWidgets);
        expect(
          find.byKey(ProjectSettingsPanelKeys.addActionButton),
          findsOneWidget,
        );
      });

      testWidgets('loads start-chat macro fields from config', (tester) async {
        await pumpAndLoad(
          tester,
          buildTestWidget(
            config: const ProjectConfig(
              userActions: [
                StartChatMacro(
                  name: 'Codex Review',
                  agentId: 'codex-default',
                  model: 'o3-mini',
                  instruction: 'Review this branch',
                ),
              ],
            ),
          ),
        );
        await selectActionsCategory(tester);

        expect(find.text('Start Chat'), findsWidgets);
        expect(find.text('Agent'), findsOneWidget);
        expect(find.text('Model (optional)'), findsOneWidget);
        expect(find.text('Instruction'), findsOneWidget);
      });

      testWidgets('add-action menu includes start-chat macro option', (
        tester,
      ) async {
        await pumpAndLoad(tester, buildTestWidget());
        await selectActionsCategory(tester);

        await tester.tap(find.byKey(ProjectSettingsPanelKeys.addActionButton));
        await tester.pump();

        expect(
          find.byKey(ProjectSettingsPanelKeys.addStartChatMacroItem),
          findsOneWidget,
        );
      });
    });
  });
}
