import 'dart:async';

import 'package:cc_insights_v2/models/agent_config.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/user_action.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/services/internal_tools_service.dart';
import 'package:cc_insights_v2/services/log_service.dart';
import 'package:cc_insights_v2/services/macro_executor.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('MacroExecutor', () {
    final resources = TestResources();
    late Future<void> Function() cleanupConfig;
    late WorktreeState worktree;
    late ProjectState project;
    late SelectionState selection;
    late _FakeBackendService backend;
    late _FakeProjectRestoreService restoreService;
    late InternalToolsService internalTools;
    late EventHandler eventHandler;
    late BuildContext testContext;

    setUp(() async {
      cleanupConfig = await setupTestConfig();
      RuntimeConfig.instance.agents = const [
        AgentConfig(
          id: 'codex-default',
          name: 'Codex',
          driver: 'codex',
          defaultModel: '',
          defaultPermissions: 'default',
          codexSandboxMode: 'workspace-write',
          codexApprovalPolicy: 'on-request',
        ),
      ];
      RuntimeConfig.instance.defaultAgentId = 'codex-default';
      ChatModelCatalog.updateCodexModels(const [
        ChatModel(
          id: 'o3-mini',
          label: 'o3-mini',
          backend: sdk.BackendType.codex,
        ),
      ]);

      worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
      );
      project = resources.track(
        ProjectState(
          const ProjectData(name: 'Test Project', repoRoot: '/test/project'),
          worktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      selection = resources.track(SelectionState(project));
      backend = resources.track(_FakeBackendService());
      restoreService = _FakeProjectRestoreService();
      internalTools = resources.track(InternalToolsService());
      eventHandler = EventHandler();
    });

    tearDown(() async {
      LogService.instance.clearBuffer();
      await resources.disposeAll();
      await cleanupConfig();
    });

    Future<void> pumpHarness(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<SelectionState>.value(value: selection),
            ChangeNotifierProvider<BackendService>.value(value: backend),
            Provider<EventHandler>.value(value: eventHandler),
            ChangeNotifierProvider<InternalToolsService>.value(
              value: internalTools,
            ),
            Provider<ProjectRestoreService>.value(value: restoreService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  testContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('creates and starts a chat for start-chat macro', (
      tester,
    ) async {
      await pumpHarness(tester);

      const macro = StartChatMacro(
        name: 'Codex Review',
        agentId: 'codex-default',
        model: 'o3-mini',
        instruction: 'Perform a code review of this branch.',
      );

      await MacroExecutor.executeStartChat(testContext, worktree, macro);
      await tester.pump();

      expect(worktree.chats.length, 1);
      final chat = worktree.chats.first;
      expect(selection.selectedChat, same(chat));
      expect(chat.agentId, 'codex-default');
      expect(chat.model.id, 'o3-mini');
      expect(backend.startedAgents, contains('codex-default'));
      expect(restoreService.addedChats.length, 1);
      expect(chat.hasActiveSession, isTrue);

      final entries = chat.data.primaryConversation.entries;
      expect(entries.length, 1);
      expect(entries.first, isA<UserInputEntry>());
      expect((entries.first as UserInputEntry).text, macro.instruction);

      LogService.instance.clearBuffer();
    });

    testWidgets('shows error and does not create chat for unknown agent', (
      tester,
    ) async {
      await pumpHarness(tester);

      const macro = StartChatMacro(
        name: 'Broken Macro',
        agentId: 'missing-agent',
        instruction: 'Hello',
      );

      await MacroExecutor.executeStartChat(testContext, worktree, macro);
      await tester.pump();

      expect(worktree.chats, isEmpty);
      expect(find.textContaining('was not found'), findsOneWidget);
      expect(backend.startedAgents, isEmpty);

      LogService.instance.clearBuffer();
    });
  });
}

class _FakeBackendService extends BackendService {
  final List<String> startedAgents = [];
  String? _error;

  @override
  Future<void> startAgent(String agentId, {AgentConfig? config}) async {
    startedAgents.add(agentId);
    _error = null;
  }

  @override
  String? errorForAgent(String agentId) => _error;

  @override
  bool isAgentErrorForAgent(String agentId) => false;

  @override
  Future<sdk.EventTransport> createTransportForAgent({
    required String agentId,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    sdk.InternalToolRegistry? registry,
  }) async {
    return _FakeEventTransport();
  }
}

class _FakeEventTransport implements sdk.EventTransport {
  _FakeEventTransport() {
    _statusController.add(sdk.TransportStatus.connected);
  }

  final _eventsController = StreamController<sdk.InsightsEvent>.broadcast();
  final _statusController = StreamController<sdk.TransportStatus>.broadcast();
  final _permissionController =
      StreamController<sdk.PermissionRequest>.broadcast();

  @override
  Stream<sdk.InsightsEvent> get events => _eventsController.stream;

  @override
  Future<void> send(sdk.BackendCommand command) async {}

  @override
  Stream<sdk.TransportStatus> get status => _statusController.stream;

  @override
  String? get sessionId => 'test-session';

  @override
  String? get resolvedSessionId => 'test-session';

  @override
  sdk.BackendCapabilities? get capabilities => const sdk.BackendCapabilities();

  @override
  String? get serverModel => null;

  @override
  String? get serverReasoningEffort => null;

  @override
  Stream<sdk.PermissionRequest> get permissionRequests =>
      _permissionController.stream;

  @override
  Future<void> dispose() async {
    await _eventsController.close();
    await _statusController.close();
    await _permissionController.close();
  }
}

class _FakeProjectRestoreService extends ProjectRestoreService {
  final List<String> addedChats = [];

  @override
  Future<void> addChatToWorktree(
    String projectRoot,
    String worktreePath,
    ChatState chat,
  ) async {
    addedChats.add(worktreePath);
  }
}
