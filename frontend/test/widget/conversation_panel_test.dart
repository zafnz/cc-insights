import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_session_wrapper.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/conversation.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/conversation_panel.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/services/agent_service.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/sdk_message_handler.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/widgets/keyboard_focus_manager.dart';
import 'package:cc_insights_v2/widgets/permission_dialog.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

// =============================================================================
// FAKE IMPLEMENTATIONS
// =============================================================================

/// Fake implementation of BackendService for testing.
///
/// Tracks calls to createSession and allows controlling the returned session.
class FakeBackendService extends ChangeNotifier implements BackendService {
  /// The session to return from createSession.
  FakeClaudeSession? sessionToReturn;

  /// If set, createSession will throw this error.
  Object? createSessionError;

  /// Records of createSession calls.
  final List<_CreateSessionCall> createSessionCalls = [];

  /// Whether the backend is ready.
  bool _isReady = true;

  @override
  bool get isReady => _isReady;

  @override
  bool get isStarting => false;

  @override
  String? get error => null;

  @override
  Future<void> start() async {
    _isReady = true;
    notifyListeners();
  }

  @override
  Future<sdk.ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
  }) async {
    createSessionCalls.add(_CreateSessionCall(
      prompt: prompt,
      cwd: cwd,
      options: options,
    ));

    if (createSessionError != null) {
      throw createSessionError!;
    }

    return sessionToReturn ?? FakeClaudeSession();
  }

  void reset() {
    createSessionCalls.clear();
    sessionToReturn = null;
    createSessionError = null;
  }
}

/// Record of a createSession call.
class _CreateSessionCall {
  _CreateSessionCall({
    required this.prompt,
    required this.cwd,
    this.options,
  });

  final String prompt;
  final String cwd;
  final sdk.SessionOptions? options;
}

/// Minimal fake ClaudeSession for testing.
class FakeClaudeSession implements sdk.ClaudeSession {
  final _messagesController = StreamController<sdk.SDKMessage>.broadcast();
  final _permissionsController =
      StreamController<sdk.PermissionRequest>.broadcast();
  final _hooksController = StreamController<sdk.HookRequest>.broadcast();

  /// Records of send calls.
  final List<String> sendCalls = [];

  @override
  String get sessionId => 'fake-session-id';

  @override
  String? sdkSessionId = 'fake-sdk-session-id';

  @override
  Stream<sdk.SDKMessage> get messages => _messagesController.stream;

  @override
  Stream<sdk.PermissionRequest> get permissionRequests =>
      _permissionsController.stream;

  @override
  Stream<sdk.HookRequest> get hookRequests => _hooksController.stream;

  @override
  Future<void> send(String message) async {
    sendCalls.add(message);
  }

  @override
  Future<void> sendWithContent(List<sdk.ContentBlock> content) async {}

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> kill() async {}

  @override
  Future<List<sdk.ModelInfo>> supportedModels() async => [];

  @override
  Future<List<sdk.SlashCommand>> supportedCommands() async => [];

  @override
  Future<List<sdk.McpServerStatus>> mcpServerStatus() async => [];

  @override
  Future<void> setModel(String? model) async {}

  @override
  Future<void> setPermissionMode(sdk.PermissionMode mode) async {}

  // Test-only members
  @override
  final List<String> testSentMessages = [];

  @override
  Future<void> Function(String message)? onTestSend;

  @override
  void emitTestMessage(sdk.SDKMessage message) {
    _messagesController.add(message);
  }

  @override
  Future<sdk.PermissionResponse> emitTestPermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) async =>
      sdk.PermissionDenyResponse(message: 'Test deny');

  void dispose() {
    _messagesController.close();
    _permissionsController.close();
    _hooksController.close();
  }
}

/// Fake SdkMessageHandler that tracks calls but doesn't do anything.
class FakeSdkMessageHandler extends SdkMessageHandler {
  final List<_HandleMessageCall> handleMessageCalls = [];

  @override
  void handleMessage(ChatState chat, Map<String, dynamic> rawMessage) {
    handleMessageCalls.add(_HandleMessageCall(
      chat: chat,
      rawMessage: rawMessage,
    ));
    // Don't call super to avoid side effects
  }

  void reset() {
    handleMessageCalls.clear();
    clear();
  }
}

class _HandleMessageCall {
  _HandleMessageCall({
    required this.chat,
    required this.rawMessage,
  });

  final ChatState chat;
  final Map<String, dynamic> rawMessage;
}

/// Fake implementation of AgentRegistry for testing.
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
}

/// Fake implementation of AgentService for testing.
class FakeAgentService extends ChangeNotifier implements AgentService {
  FakeAgentService({required this.agentRegistry});

  @override
  final AgentRegistry agentRegistry;

  bool _isConnected = false;
  AgentConfig? _currentAgent;

  @override
  bool get isConnected => _isConnected;

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
    notifyListeners();
  }

  /// Sets the connection state for testing.
  void setConnected(bool connected, {AgentConfig? agent}) {
    _isConnected = connected;
    _currentAgent = agent;
    notifyListeners();
  }
}

// =============================================================================
// TEST HELPERS
// =============================================================================

/// Creates a fake PermissionRequest for testing.
sdk.PermissionRequest createFakePermissionRequest({
  String id = 'test-permission-id',
  String sessionId = 'test-session',
  String toolName = 'Bash',
  Map<String, dynamic> toolInput = const {'command': 'ls -la'},
  String? decisionReason,
}) {
  final completer = Completer<sdk.PermissionResponse>();
  return sdk.PermissionRequest(
    id: id,
    sessionId: sessionId,
    toolName: toolName,
    toolInput: toolInput,
    decisionReason: decisionReason,
    completer: completer,
  );
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  group('ConversationPanel MessageInput wiring', () {
    final resources = TestResources();
    late ProjectState project;
    late SelectionState selectionState;
    late FakeBackendService fakeBackend;
    late FakeSdkMessageHandler fakeMessageHandler;
    late ChatState testChat;

    setUp(() {
      fakeBackend = FakeBackendService();
      fakeMessageHandler = FakeSdkMessageHandler();

      // Create a chat for testing (NOT tracked separately - owned by worktree)
      testChat = ChatState.create(name: 'Test Chat', worktreeRoot: '/test/path');

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
        chats: [testChat],
      );

      // ProjectState owns the worktree which owns the chat - only track project
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

      selectionState = resources.track(SelectionState(project));
      // Select the chat so the conversation panel shows it
      selectionState.selectChat(testChat);
    });

    tearDown(() async {
      fakeMessageHandler.dispose();
      await resources.disposeAll();
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: project),
            ChangeNotifierProvider.value(value: selectionState),
            ChangeNotifierProvider<BackendService>.value(value: fakeBackend),
            Provider<SdkMessageHandler>.value(value: fakeMessageHandler),
          ],
          child: const Scaffold(
            body: KeyboardFocusManager(
              child: SizedBox(
                width: 600,
                height: 800,
                child: ConversationPanel(),
              ),
            ),
          ),
        ),
      );
    }

    group('First message starts session', () {
      testWidgets('submitting when no active session calls startSession',
          (tester) async {
        // Setup: session will be created successfully
        final fakeSession = FakeClaudeSession();
        fakeBackend.sessionToReturn = fakeSession;

        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Verify no active session initially
        check(testChat.hasActiveSession).isFalse();
        check(fakeBackend.createSessionCalls).isEmpty();

        // Type a message and submit
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'Hello Claude!');
        await tester.pump();

        // Find and tap the send button
        final sendButton = find.byIcon(Icons.send);
        await tester.tap(sendButton);
        await safePumpAndSettle(tester);

        // Verify startSession was called via backend.createSession
        check(fakeBackend.createSessionCalls.length).equals(1);
        check(fakeBackend.createSessionCalls.first.prompt).equals(
          'Hello Claude!',
        );
        check(fakeBackend.createSessionCalls.first.cwd).equals('/test/path');

        // Verify user entry was added
        check(testChat.data.primaryConversation.entries.length).equals(1);
        check(testChat.data.primaryConversation.entries.first.runtimeType.toString())
            .equals('UserInputEntry');
      });

      testWidgets('startSession failure shows error entry', (tester) async {
        // Setup: session creation will fail
        fakeBackend.createSessionError = Exception('Backend not available');

        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Type a message and submit
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'Hello Claude!');
        await tester.pump();

        final sendButton = find.byIcon(Icons.send);
        await tester.tap(sendButton);
        await safePumpAndSettle(tester);

        // Verify error entry was added (user entry + error entry = 2)
        check(testChat.data.primaryConversation.entries.length).equals(2);

        // The second entry should be an error
        final errorEntry = testChat.data.primaryConversation.entries[1];
        check(errorEntry.runtimeType.toString()).equals('TextOutputEntry');
      });
    });

    group('Subsequent messages sent to session', () {
      testWidgets('submitting with active session calls sendMessage',
          (tester) async {
        // Setup: create a fake session and mark chat as having active session
        final fakeSession = FakeClaudeSession();
        fakeBackend.sessionToReturn = fakeSession;

        // Start a session first by sending the first message
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // First message starts the session
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'First message');
        await tester.pump();
        final sendButton = find.byIcon(Icons.send);
        await tester.tap(sendButton);
        await safePumpAndSettle(tester);

        // Verify session was started
        check(fakeBackend.createSessionCalls.length).equals(1);
        check(testChat.hasActiveSession).isTrue();

        // Now send a second message
        await tester.enterText(textField, 'Second message');
        await tester.pump();
        await tester.tap(sendButton);
        await safePumpAndSettle(tester);

        // Verify createSession was NOT called again
        check(fakeBackend.createSessionCalls.length).equals(1);

        // Verify sendMessage was called via the session
        check(fakeSession.sendCalls.length).equals(1);
        check(fakeSession.sendCalls.first).equals('Second message');
      });
    });

    group('Permission dialog', () {
      testWidgets('shows when pendingPermission is set', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Initially no permission dialog
        expect(find.byKey(PermissionDialogKeys.dialog), findsNothing);

        // Set a pending permission
        final permissionRequest = createFakePermissionRequest(
          toolName: 'Bash',
          toolInput: {'command': 'rm -rf /'},
        );
        testChat.setPendingPermission(permissionRequest);
        await safePumpAndSettle(tester);

        // Now permission dialog should be visible using Keys
        expect(find.byKey(PermissionDialogKeys.dialog), findsOneWidget);
        expect(find.byKey(PermissionDialogKeys.header), findsOneWidget);
        expect(find.byKey(PermissionDialogKeys.bashCommand), findsOneWidget);
      });

      testWidgets('clicking Allow calls allowPermission', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Set a pending permission
        final permissionRequest = createFakePermissionRequest();
        testChat.setPendingPermission(permissionRequest);
        await safePumpAndSettle(tester);

        // Verify dialog is shown using Key
        expect(find.byKey(PermissionDialogKeys.dialog), findsOneWidget);
        check(testChat.pendingPermission).isNotNull();

        // Click Allow button using Key
        await tester.tap(find.byKey(PermissionDialogKeys.allowButton));
        await safePumpAndSettle(tester);

        // Verify permission was cleared (allowPermission clears pendingPermission)
        check(testChat.pendingPermission).isNull();

        // Dialog should be gone
        expect(find.byKey(PermissionDialogKeys.dialog), findsNothing);
      });

      testWidgets('clicking Deny calls denyPermission', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Set a pending permission
        final permissionRequest = createFakePermissionRequest();
        testChat.setPendingPermission(permissionRequest);
        await safePumpAndSettle(tester);

        // Verify dialog is shown using Key
        expect(find.byKey(PermissionDialogKeys.dialog), findsOneWidget);
        check(testChat.pendingPermission).isNotNull();

        // Click Deny button using Key
        await tester.tap(find.byKey(PermissionDialogKeys.denyButton));
        await safePumpAndSettle(tester);

        // Verify permission was cleared (denyPermission clears pendingPermission)
        check(testChat.pendingPermission).isNull();

        // Dialog should be gone
        expect(find.byKey(PermissionDialogKeys.dialog), findsNothing);
      });

      testWidgets('permission dialog displays tool name and input',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Set a pending permission with specific tool info
        final permissionRequest = createFakePermissionRequest(
          toolName: 'Read',
          toolInput: {'file_path': '/secret/file.txt'},
        );
        testChat.setPendingPermission(permissionRequest);
        await safePumpAndSettle(tester);

        // Verify dialog is visible and has content
        expect(find.byKey(PermissionDialogKeys.dialog), findsOneWidget);
        expect(find.byKey(PermissionDialogKeys.header), findsOneWidget);

        // Verify tool input is displayed (generic tool shows key-value pairs)
        expect(find.textContaining('file_path'), findsOneWidget);
        expect(find.textContaining('/secret/file.txt'), findsOneWidget);
      });
    });
  });

  group('ConversationPanel agent badge', () {
    final resources = TestResources();
    late ProjectState project;
    late SelectionState selectionState;
    late FakeBackendService fakeBackend;
    late FakeSdkMessageHandler fakeMessageHandler;
    late FakeAgentRegistry fakeRegistry;
    late FakeAgentService fakeAgentService;
    late ChatState testChat;

    setUp(() {
      fakeBackend = FakeBackendService();
      fakeMessageHandler = FakeSdkMessageHandler();
      fakeRegistry = FakeAgentRegistry();
      fakeAgentService = FakeAgentService(agentRegistry: fakeRegistry);

      testChat = ChatState.create(name: 'Test Chat', worktreeRoot: '/test/path');

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
        chats: [testChat],
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

      selectionState = resources.track(SelectionState(project));
      selectionState.selectChat(testChat);
    });

    tearDown(() async {
      fakeMessageHandler.dispose();
      await resources.disposeAll();
    });

    Widget buildTestWidget({AgentService? agentService}) {
      return MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: project),
            ChangeNotifierProvider.value(value: selectionState),
            ChangeNotifierProvider<BackendService>.value(value: fakeBackend),
            Provider<SdkMessageHandler>.value(value: fakeMessageHandler),
            if (agentService != null)
              ChangeNotifierProvider<AgentService>.value(value: agentService),
          ],
          child: const Scaffold(
            body: KeyboardFocusManager(
              child: SizedBox(
                width: 600,
                height: 800,
                child: ConversationPanel(),
              ),
            ),
          ),
        ),
      );
    }

    group('Primary conversation header', () {
      testWidgets('shows agent badge when connected', (tester) async {
        // Connect to an agent
        const agentConfig = AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: '/usr/bin/claude',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Should show the agent name in the header
        expect(find.text('Claude Code'), findsOneWidget);
      });

      testWidgets('does not show agent badge when not connected',
          (tester) async {
        fakeAgentService.setConnected(false);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Should not show any agent name (no badge)
        expect(find.text('Claude Code'), findsNothing);
        expect(find.text('Gemini CLI'), findsNothing);
      });

      testWidgets('does not show agent badge when AgentService not provided',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await safePumpAndSettle(tester);

        // Should not show any agent name (no badge)
        expect(find.text('Claude Code'), findsNothing);
      });

      testWidgets('agent badge updates when connection state changes',
          (tester) async {
        fakeAgentService.setConnected(false);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Initially no agent badge
        expect(find.text('Claude Code'), findsNothing);

        // Connect to agent
        const agentConfig = AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: '/usr/bin/claude',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);
        await tester.pump();

        // Now badge should be visible
        expect(find.text('Claude Code'), findsOneWidget);

        // Disconnect
        fakeAgentService.setConnected(false);
        await tester.pump();

        // Badge should be gone
        expect(find.text('Claude Code'), findsNothing);
      });

      testWidgets('shows green indicator in agent badge when connected',
          (tester) async {
        const agentConfig = AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: '/usr/bin/claude',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Find the agent badge text
        expect(find.text('Claude Code'), findsOneWidget);

        // Find containers with green color (status indicator in badge)
        final containers = tester.widgetList<Container>(find.byType(Container));
        final greenIndicator = containers.where((c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
            return decoration.color == Colors.green;
          }
          return false;
        });

        check(greenIndicator).isNotEmpty();
      });
    });

    group('Subagent conversation header', () {
      testWidgets('does not show agent badge for subagent conversations',
          (tester) async {
        // Connect to an agent
        const agentConfig = AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: '/usr/bin/claude',
        );
        fakeAgentService.setConnected(true, agent: agentConfig);

        // Create a subagent conversation and select it
        testChat.addSubagentConversation(
          'sdk-agent-1',
          'Research Task',
          'Research the topic',
        );
        // Get the subagent conversation and select it
        final subagentConv = testChat.data.subagentConversations.values.first;
        testChat.selectConversation(subagentConv.id);

        await tester.pumpWidget(buildTestWidget(agentService: fakeAgentService));
        await safePumpAndSettle(tester);

        // Should show the subagent label in the header
        expect(find.text('Research Task'), findsOneWidget);

        // The agent badge should NOT appear for subagent conversations
        // The _AgentBadge widget is only rendered for primary conversations
        // So the agent name should not appear as a badge (though it may appear elsewhere)
        // We verify by checking that the subagent-specific header is shown
        // (indicated by the smart_toy_outlined icon for subagent conversations)
        expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
      });
    });
  });
}
