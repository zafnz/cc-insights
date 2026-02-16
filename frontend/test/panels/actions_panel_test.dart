import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/project_config.dart';
import 'package:cc_insights_v2/models/user_action.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/actions_panel.dart';
import 'package:cc_insights_v2/services/project_config_service.dart';
import 'package:cc_insights_v2/services/script_execution_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_project_config_service.dart';
import '../test_helpers.dart';

void main() {
  group('ActionsPanel', () {
    final resources = TestResources();
    late ProjectState projectState;
    late SelectionState selectionState;
    late FakeProjectConfigService configService;
    late ScriptExecutionService scriptExecutionService;

    setUp(() {
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
      configService = resources.track(FakeProjectConfigService());
      scriptExecutionService = resources.track(ScriptExecutionService());
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    Widget buildTestWidget(ProjectConfig config) {
      configService.configs['/test/project'] = config;

      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ProjectState>.value(value: projectState),
          ChangeNotifierProvider<SelectionState>.value(value: selectionState),
          ChangeNotifierProvider<FakeProjectConfigService>.value(
            value: configService,
          ),
          ChangeNotifierProvider<ScriptExecutionService>.value(
            value: scriptExecutionService,
          ),
          ChangeNotifierProvider<ProjectConfigService>.value(
            value: configService,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 900, height: 300, child: ActionsPanel()),
          ),
        ),
      );
    }

    Future<void> pumpAndLoad(WidgetTester tester, Widget widget) async {
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('renders command and start-chat actions with typed icons', (
      tester,
    ) async {
      await pumpAndLoad(
        tester,
        buildTestWidget(
          const ProjectConfig(
            userActions: [
              CommandAction(name: 'Test', command: './test.sh'),
              StartChatMacro(
                name: 'Codex Review',
                agentId: 'codex-default',
                instruction: 'Review this branch',
              ),
            ],
          ),
        ),
      );

      final commandButton = find.byKey(ActionsPanelKeys.actionButton('Test'));
      final macroButton = find.byKey(
        ActionsPanelKeys.actionButton('Codex Review'),
      );

      expect(commandButton, findsOneWidget);
      expect(macroButton, findsOneWidget);
      expect(
        find.descendant(
          of: commandButton,
          matching: find.byIcon(Icons.play_arrow),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: macroButton,
          matching: find.byIcon(Icons.chat_bubble_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows instruction preview tooltip for start-chat macros', (
      tester,
    ) async {
      await pumpAndLoad(
        tester,
        buildTestWidget(
          const ProjectConfig(
            userActions: [
              StartChatMacro(
                name: 'Codex Review',
                agentId: 'codex-default',
                instruction:
                    'Perform a code review of all changes in this branch since it was created.',
              ),
            ],
          ),
        ),
      );

      final macroButton = find.byKey(
        ActionsPanelKeys.actionButton('Codex Review'),
      );
      await tester.longPress(macroButton);
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('Perform a code review'), findsOneWidget);
    });

    testWidgets('shows add icon for empty command actions', (tester) async {
      await pumpAndLoad(
        tester,
        buildTestWidget(
          const ProjectConfig(
            userActions: [CommandAction(name: 'Prompted', command: '')],
          ),
        ),
      );

      final commandButton = find.byKey(
        ActionsPanelKeys.actionButton('Prompted'),
      );
      expect(commandButton, findsOneWidget);
      expect(
        find.descendant(of: commandButton, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
    });
  });
}
