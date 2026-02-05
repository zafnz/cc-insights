import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/project_config.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/project_settings_panel.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_project_config_service.dart';
import '../test_helpers.dart';

void main() {
  group('ProjectSettingsPanel - Git category', () {
    final resources = TestResources();
    late FakeProjectConfigService fakeConfigService;
    late ProjectState projectState;
    late SelectionState selectionState;

    setUp(() {
      fakeConfigService = FakeProjectConfigService();

      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
      );

      projectState = resources.track(ProjectState(
        const ProjectData(
          name: 'Test Project',
          repoRoot: '/test/project',
        ),
        worktree,
        autoValidate: false,
        watchFilesystem: false,
      ));

      selectionState = resources.track(SelectionState(projectState));
    });

    tearDown(() async {
      await resources.disposeAll();
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

        expect(find.text('Git'), findsOneWidget);
      });

      testWidgets('shows all three categories', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        expect(find.text('Lifecycle Hooks'), findsWidgets);
        expect(find.text('User Actions'), findsWidgets);
        expect(find.text('Git'), findsOneWidget);
      });

      testWidgets('selecting Git shows Git content', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Tap on Git category
        await tester.tap(find.text('Git'));
        await tester.pump();

        // Git header and description should be visible
        expect(find.text('Default branch comparison settings'),
            findsOneWidget);
        expect(find.text('Default base for new worktrees'),
            findsOneWidget);

        // Hooks content should not be visible
        expect(find.text('Pre-Create'), findsNothing);
      });
    });

    group('git settings content', () {
      testWidgets('shows base selector dropdown with auto default',
          (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Navigate to Git category
        await tester.tap(find.text('Git'));
        await tester.pump();

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

        await tester.tap(find.text('Git'));
        await tester.pump();

        expect(
          find.textContaining('Auto-detect checks for an upstream'),
          findsOneWidget,
        );
      });

      testWidgets('does not show custom text field by default',
          (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        await tester.tap(find.text('Git'));
        await tester.pump();

        expect(
          find.byKey(ProjectSettingsPanelKeys.customBaseField),
          findsNothing,
        );
      });

      testWidgets('selecting Custom shows text field', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        await tester.tap(find.text('Git'));
        await tester.pump();

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

      testWidgets('selecting main does not show custom text field',
          (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        await tester.tap(find.text('Git'));
        await tester.pump();

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
          buildTestWidget(
            config: const ProjectConfig(defaultBase: 'main'),
          ),
        );

        await tester.tap(find.text('Git'));
        await tester.pump();

        // Should show "main" as the selected value in the dropdown
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        expect(dropdown.value, 'main');
      });

      testWidgets('loads defaultBase as origin/main from config',
          (tester) async {
        await pumpAndLoad(
          tester,
          buildTestWidget(
            config: const ProjectConfig(defaultBase: 'origin/main'),
          ),
        );

        await tester.tap(find.text('Git'));
        await tester.pump();

        final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        expect(dropdown.value, 'origin/main');
      });

      testWidgets('loads custom defaultBase from config', (tester) async {
        await pumpAndLoad(
          tester,
          buildTestWidget(
            config: const ProjectConfig(defaultBase: 'develop'),
          ),
        );

        await tester.tap(find.text('Git'));
        await tester.pump();

        // Should show "Custom..." selected
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
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
          buildTestWidget(
            config: const ProjectConfig.empty(),
          ),
        );

        await tester.tap(find.text('Git'));
        await tester.pump();

        final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        expect(dropdown.value, 'auto');
      });
    });

    group('saving config', () {
      testWidgets('saves auto as null defaultBase', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        // Navigate to Git category
        await tester.tap(find.text('Git'));
        await tester.pump();

        // Tap Save button
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // Check saved config
        final savedConfig =
            fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, isNull);
      });

      testWidgets('saves main selection as defaultBase', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        await tester.tap(find.text('Git'));
        await tester.pump();

        // Open dropdown and select main
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('main').last);
        await tester.pump();

        // Save
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        final savedConfig =
            fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, 'main');
      });

      testWidgets('saves origin/main selection as defaultBase',
          (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        await tester.tap(find.text('Git'));
        await tester.pump();

        // Open dropdown and select origin/main
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('origin/main').last);
        await tester.pump();

        // Save
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        final savedConfig =
            fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, 'origin/main');
      });

      testWidgets('saves custom value as defaultBase', (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        await tester.tap(find.text('Git'));
        await tester.pump();

        // Open dropdown and select Custom...
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('Custom...').last);
        await tester.pump();

        // Enter custom value
        await tester.enterText(
          find.byKey(ProjectSettingsPanelKeys.customBaseField),
          'develop',
        );
        await tester.pump();

        // Save
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        final savedConfig =
            fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, 'develop');
      });

      testWidgets('saves empty custom value as null defaultBase',
          (tester) async {
        await pumpAndLoad(tester, buildTestWidget());

        await tester.tap(find.text('Git'));
        await tester.pump();

        // Open dropdown and select Custom...
        await tester.tap(
          find.byKey(ProjectSettingsPanelKeys.defaultBaseSelector),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('Custom...').last);
        await tester.pump();

        // Leave the custom text field empty and save
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        final savedConfig =
            fakeConfigService.configs['/test/project'];
        expect(savedConfig, isNotNull);
        expect(savedConfig!.defaultBase, isNull);
      });
    });
  });
}
