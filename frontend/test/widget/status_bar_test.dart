import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_errors.dart';
import 'package:cc_insights_v2/acp/acp_session_wrapper.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/services/agent_service.dart';
import 'package:cc_insights_v2/widgets/status_bar.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

// =============================================================================
// FAKE IMPLEMENTATIONS
// =============================================================================

/// Fake implementation of AgentRegistry for testing.
///
/// Provides controllable agent discovery without filesystem access.
class FakeAgentRegistry extends ChangeNotifier implements AgentRegistry {
  final List<AgentConfig> _agents = [];

  @override
  List<AgentConfig> get agents => List.unmodifiable(_agents);

  @override
  List<AgentConfig> get discoveredAgents => _agents;

  @override
  List<AgentConfig> get customAgents => const [];

  @override
  bool get hasDiscovered => true;

  @override
  String? get configDir => null;

  @override
  Future<void> discover() async {}

  @override
  Future<void> load() async {}

  @override
  Future<void> save() async {}

  @override
  AgentConfig? getAgent(String id) =>
      _agents.where((a) => a.id == id).firstOrNull;

  @override
  bool hasAgent(String id) => getAgent(id) != null;

  @override
  void addCustomAgent(AgentConfig config) {
    _agents.add(config);
    notifyListeners();
  }

  @override
  void removeAgent(String id) {
    _agents.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void addAgent(AgentConfig config) {
    _agents.add(config);
    notifyListeners();
  }
}

/// Fake implementation of AgentService for testing.
///
/// Provides controllable connection state without spawning processes.
class FakeAgentService extends ChangeNotifier implements AgentService {
  FakeAgentService({required this.agentRegistry});

  @override
  final AgentRegistry agentRegistry;

  bool _isConnected = false;
  AgentConfig? _currentAgent;
  ACPConnectionState _connectionState = ACPConnectionState.disconnected;
  ACPError? _lastError;

  @override
  bool get isConnected => _isConnected;

  @override
  ACPConnectionState get connectionState => _connectionState;

  @override
  ACPError? get lastError => _lastError;

  @override
  AgentConfig? get currentAgent => _currentAgent;

  @override
  AgentCapabilities? get capabilities => null;

  @override
  AgentInfo? get agentInfo => null;

  @override
  Stream<SessionNotification>? get updates => null;

  @override
  Stream<PendingPermission>? get permissionRequests => null;

  @override
  Future<void> connect(AgentConfig config) async {
    _currentAgent = config;
    _isConnected = true;
    _connectionState = ACPConnectionState.connected;
    notifyListeners();
  }

  @override
  Future<ACPSessionWrapper> createSession({
    required String cwd,
    List<McpServerBase>? mcpServers,
  }) async {
    throw StateError('FakeAgentService does not support createSession');
  }

  @override
  Future<void> disconnect() async {
    _currentAgent = null;
    _isConnected = false;
    _connectionState = ACPConnectionState.disconnected;
    _lastError = null;
    notifyListeners();
  }

  @override
  Future<bool> reconnect() async => false;

  /// Sets the connection state for testing.
  void setConnected(bool connected, {AgentConfig? agent}) {
    _isConnected = connected;
    _currentAgent = agent;
    _connectionState = connected
        ? ACPConnectionState.connected
        : ACPConnectionState.disconnected;
    notifyListeners();
  }
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  group('StatusBar', () {
    final resources = TestResources();
    late ProjectState project;
    late FakeAgentRegistry fakeRegistry;
    late FakeAgentService fakeAgentService;

    setUp(() {
      fakeRegistry = FakeAgentRegistry();
      fakeAgentService = FakeAgentService(agentRegistry: fakeRegistry);

      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/path',
          isPrimary: true,
          branch: 'main',
          uncommittedFiles: 0,
          stagedFiles: 0,
          commitsAhead: 0,
          commitsBehind: 0,
          hasMergeConflict: false,
        ),
        chats: [],
      );

      project = resources.track(ProjectState(
        const ProjectData(
          name: 'Test Project',
          repoRoot: '/test/path',
        ),
        worktree,
        linkedWorktrees: [],
        autoValidate: false,
        watchFilesystem: false,
      ));
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    Widget buildTestWidget({AgentService? agentService}) {
      return MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: project),
            if (agentService != null)
              ChangeNotifierProvider<AgentService>.value(value: agentService),
          ],
          child: const Scaffold(
            body: StatusBar(),
          ),
        ),
      );
    }

    group('Connection status display', () {
      testWidgets('shows "Not connected" when AgentService is not provided',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Should show "Not connected" text
        expect(find.text('Not connected'), findsOneWidget);
      });

      testWidgets(
          'shows "Not connected" when AgentService has no connected agent',
          (tester) async {
        // Agent service exists but is not connected
        fakeAgentService.setConnected(false);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Should show "Not connected" text
        expect(find.text('Not connected'), findsOneWidget);
      });

      testWidgets('shows agent name when connected', (tester) async {
        // Connect to an agent
        final agentConfig = const AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: '/usr/bin/claude',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Should show agent name
        expect(find.text('Claude Code'), findsOneWidget);
        expect(find.text('Not connected'), findsNothing);
      });

      testWidgets('updates display when connection state changes',
          (tester) async {
        // Start disconnected
        fakeAgentService.setConnected(false);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        expect(find.text('Not connected'), findsOneWidget);

        // Connect to agent
        final agentConfig = const AgentConfig(
          id: 'gemini-cli',
          name: 'Gemini CLI',
          command: '/usr/bin/gemini',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);
        await tester.pump();

        expect(find.text('Gemini CLI'), findsOneWidget);
        expect(find.text('Not connected'), findsNothing);

        // Disconnect
        fakeAgentService.setConnected(false);
        await tester.pump();

        expect(find.text('Not connected'), findsOneWidget);
      });
    });

    group('Status indicator color', () {
      testWidgets('shows grey indicator when not connected', (tester) async {
        fakeAgentService.setConnected(false);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Find the status indicator container
        final containers = tester.widgetList<Container>(find.byType(Container));
        final statusIndicator = containers.where((c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
            return decoration.color == Colors.grey;
          }
          return false;
        });

        check(statusIndicator).isNotEmpty();
      });

      testWidgets('shows green indicator when connected', (tester) async {
        final agentConfig = const AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: '/usr/bin/claude',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Find the status indicator container
        final containers = tester.widgetList<Container>(find.byType(Container));
        final statusIndicator = containers.where((c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
            return decoration.color == Colors.green;
          }
          return false;
        });

        check(statusIndicator).isNotEmpty();
      });

      testWidgets('indicator color changes with connection state',
          (tester) async {
        fakeAgentService.setConnected(false);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Initially grey
        var containers = tester.widgetList<Container>(find.byType(Container));
        var greyIndicator = containers.where((c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
            return decoration.color == Colors.grey;
          }
          return false;
        });
        check(greyIndicator).isNotEmpty();

        // Connect
        final agentConfig = const AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: '/usr/bin/claude',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);
        await tester.pump();

        // Now green
        containers = tester.widgetList<Container>(find.byType(Container));
        var greenIndicator = containers.where((c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
            return decoration.color == Colors.green;
          }
          return false;
        });
        check(greenIndicator).isNotEmpty();
      });
    });

    group('Statistics display', () {
      testWidgets('shows worktree count', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Should show "1 worktrees" (we have 1 primary worktree)
        expect(find.text('1 worktrees'), findsOneWidget);
      });

      testWidgets('shows chat count', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Should show "0 chats" (no chats created)
        expect(find.text('0 chats'), findsOneWidget);
      });

      testWidgets('shows agent count', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Should show "0 agents" (no subagent conversations)
        expect(find.text('0 agents'), findsOneWidget);
      });

      testWidgets('shows total cost', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Should show "Total $0.00" (no usage)
        expect(find.text(r'Total $0.00'), findsOneWidget);
      });
    });
  });
}
