import 'package:cc_insights_v2/models/agent_config.dart';
import 'package:cc_insights_v2/models/chat.dart' as chat_model;
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/panels/conversation_header.dart';
import 'package:cc_insights_v2/panels/compact_dropdown.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/widgets/security_config_group.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:codex_sdk/codex_sdk.dart'
    show CodexSecurityConfig, CodexSecurityCapabilities;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_cli_availability_service.dart';
import '../test_helpers.dart';

// =============================================================================
// FAKE IMPLEMENTATIONS
// =============================================================================

/// Fake implementation of BackendService for testing.
class FakeBackendService extends ChangeNotifier implements BackendService {
  sdk.BackendType? _backendType = sdk.BackendType.directCli;

  @override
  bool get isReady => true;

  @override
  bool get isStarting => false;

  @override
  bool get isAgentError => false;

  @override
  String? get error => null;

  @override
  sdk.BackendType? get backendType => _backendType;

  @override
  bool isReadyFor(sdk.BackendType type) => _backendType == type;

  @override
  bool isStartingFor(sdk.BackendType type) => false;

  @override
  bool isModelListLoadingFor(sdk.BackendType type) => false;

  @override
  String? errorFor(sdk.BackendType type) => null;

  @override
  bool isAgentErrorFor(sdk.BackendType type) => false;

  @override
  sdk.BackendCapabilities get capabilities => const sdk.BackendCapabilities(
    supportsPermissionModeChange: true,
    supportsModelChange: true,
  );

  @override
  sdk.BackendCapabilities capabilitiesFor(sdk.BackendType type) {
    if (type == sdk.BackendType.codex) {
      return const sdk.BackendCapabilities(
        supportsModelListing: true,
        supportsReasoningEffort: true,
      );
    }
    return const sdk.BackendCapabilities(
      supportsPermissionModeChange: true,
      supportsModelChange: true,
      supportsModelListing: true,
    );
  }

  @override
  CodexSecurityConfig? get codexSecurityConfig => null;

  @override
  CodexSecurityCapabilities get codexSecurityCapabilities =>
      const CodexSecurityCapabilities();

  @override
  Stream<sdk.RateLimitUpdateEvent> get rateLimits => const Stream.empty();

  @override
  Future<void> start({
    sdk.BackendType type = sdk.BackendType.directCli,
    String? executablePath,
    String? workingDirectory,
  }) async {
    _backendType = type;
    notifyListeners();
  }

  @override
  Future<void> switchBackend({
    required sdk.BackendType type,
    String? executablePath,
  }) async {
    await start(type: type, executablePath: executablePath);
  }

  @override
  Future<sdk.AgentBackend> createBackend({
    required sdk.BackendType type,
    String? executablePath,
    List<String> arguments = const [],
    String? workingDirectory,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<sdk.AgentSession> createSession({
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    sdk.InternalToolRegistry? registry,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<sdk.AgentSession> createSessionForBackend({
    required sdk.BackendType type,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    String? executablePath,
    sdk.InternalToolRegistry? registry,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<sdk.EventTransport> createTransport({
    required sdk.BackendType type,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    String? executablePath,
    sdk.InternalToolRegistry? registry,
  }) async {
    throw UnimplementedError();
  }

  @override
  void registerBackendForTesting(
    sdk.BackendType type,
    sdk.AgentBackend backend,
  ) {}

  // Agent-keyed API stubs
  @override
  String? get activeAgentId => null;
  @override
  bool isReadyForAgent(String agentId) => false;
  @override
  bool isStartingForAgent(String agentId) => false;
  @override
  bool isModelListLoadingForAgent(String agentId) => false;
  @override
  String? errorForAgent(String agentId) => null;
  @override
  bool isAgentErrorForAgent(String agentId) => false;
  @override
  sdk.BackendCapabilities capabilitiesForAgent(String agentId) =>
      const sdk.BackendCapabilities();
  @override
  CodexSecurityConfig? codexSecurityConfigForAgent(String agentId) => null;
  @override
  CodexSecurityCapabilities codexSecurityCapabilitiesForAgent(String agentId) =>
      const CodexSecurityCapabilities();
  @override
  Future<void> startAgent(String agentId, {AgentConfig? config}) async {}
  @override
  Future<sdk.EventTransport> createTransportForAgent({
    required String agentId,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    sdk.InternalToolRegistry? registry,
  }) async => throw UnimplementedError();
  @override
  Future<sdk.AgentSession> createSessionForAgent({
    required String agentId,
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
    sdk.InternalToolRegistry? registry,
  }) async => throw UnimplementedError();
  @override
  Future<void> disposeAgent(String agentId) async {}
  @override
  Future<void> discoverModelsForAllAgents() async {}
  @override
  void registerAgentBackendForTesting(
    String agentId,
    sdk.AgentBackend backend,
  ) {}
}

class FakeTransport implements sdk.EventTransport {
  FakeTransport({this.sessionId = 'test-session'});

  final List<sdk.BackendCommand> sentCommands = [];

  @override
  final String? sessionId;

  @override
  String? get resolvedSessionId => sessionId;

  @override
  sdk.BackendCapabilities? get capabilities => null;

  @override
  Stream<sdk.InsightsEvent> get events => const Stream.empty();

  @override
  Stream<sdk.TransportStatus> get status => const Stream.empty();

  @override
  Stream<sdk.PermissionRequest> get permissionRequests => const Stream.empty();

  @override
  String? get serverModel => null;

  @override
  String? get serverReasoningEffort => null;

  @override
  Future<void> send(sdk.BackendCommand command) async {
    sentCommands.add(command);
  }

  @override
  Future<void> dispose() async {}
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  group('ConversationHeader backend-specific security controls', () {
    final resources = TestResources();
    late FakeBackendService fakeBackend;
    late FakeCliAvailabilityService fakeCliAvailability;

    setUp(() {
      RuntimeConfig.resetForTesting();

      // Set up agent registry with default agents
      RuntimeConfig.instance.agents = AgentConfig.defaults;

      fakeBackend = FakeBackendService();
      fakeCliAvailability = FakeCliAvailabilityService();
    });

    tearDown(() async {
      await resources.disposeAll();
      RuntimeConfig.resetForTesting();
    });

    Widget buildTestWidget(chat_model.Chat chat) {
      return MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<BackendService>.value(value: fakeBackend),
            ChangeNotifierProvider<CliAvailabilityService>.value(
              value: fakeCliAvailability,
            ),
          ],
          child: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ConversationHeader(
                conversation: chat.data.primaryConversation,
                chat: chat,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Claude chat shows single permissions dropdown', (
      tester,
    ) async {
      // Setup: Claude chat
      final chat = resources.track(
        chat_model.Chat.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.directCli, null),
      );

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Verify CompactDropdown with tooltip 'Permissions' is present
      final permissionsDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is CompactDropdown && widget.tooltip == 'Permissions',
      );
      check(permissionsDropdown.evaluate()).isNotEmpty();

      // Verify SecurityConfigGroup is NOT present
      check(find.byType(SecurityConfigGroup).evaluate()).isEmpty();
    });

    testWidgets('Codex chat shows SecurityConfigGroup widget', (tester) async {
      // Setup: Codex chat
      final chat = resources.track(
        chat_model.Chat.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.codex, null),
      );
      // Initialize with Codex security config
      chat.settings.setSecurityConfig(
        const sdk.CodexSecurityConfig(
          sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
          approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
        ),
      );

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Verify SecurityConfigGroup is present
      check(find.byType(SecurityConfigGroup).evaluate()).isNotEmpty();

      // Verify standard permissions CompactDropdown is NOT present
      final permissionsDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is CompactDropdown && widget.tooltip == 'Permissions',
      );
      check(permissionsDropdown.evaluate()).isEmpty();
    });

    testWidgets('Claude dropdown changes call setPermissionMode', (
      tester,
    ) async {
      // Setup: Claude chat
      final chat = resources.track(
        chat_model.Chat.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.directCli, null),
      );

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Initial permission mode should be Default
      check(chat.settings.permissionMode).equals(chat_model.PermissionMode.defaultMode);

      // Find the permissions dropdown
      final permissionsDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is CompactDropdown && widget.tooltip == 'Permissions',
      );
      check(permissionsDropdown.evaluate()).isNotEmpty();

      // Tap the dropdown to open it
      await tester.tap(permissionsDropdown);
      await safePumpAndSettle(tester);

      // Select "Accept Edits"
      await tester.tap(find.text('Accept Edits').last);
      await safePumpAndSettle(tester);

      // Verify permission mode changed
      check(chat.settings.permissionMode).equals(chat_model.PermissionMode.acceptEdits);
    });

    testWidgets('ACP config options show model and mode selectors', (
      tester,
    ) async {
      final chat = resources.track(
        chat_model.Chat.create(name: 'ACP Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.acp, null),
      );
      chat.settings.setAcpConfigOptions([
        {
          'id': 'model',
          'name': 'Model',
          'category': 'model',
          'values': [
            {'value': 'model-a', 'label': 'Model A'},
            {'value': 'model-b', 'label': 'Model B'},
          ],
          'value': 'model-a',
        },
        {
          'id': 'mode',
          'name': 'Mode',
          'category': 'mode',
          'values': [
            {'value': 'fast', 'label': 'Fast'},
            {'value': 'accurate', 'label': 'Accurate'},
          ],
          'value': 'fast',
        },
      ]);

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      final modelDropdown = find.byWidgetPredicate(
        (widget) => widget is CompactDropdown && widget.tooltip == 'Model',
      );
      check(modelDropdown.evaluate()).isNotEmpty();

      final modeDropdown = find.byWidgetPredicate(
        (widget) => widget is CompactDropdown && widget.tooltip == 'Mode',
      );
      check(modeDropdown.evaluate()).isNotEmpty();
    });

    testWidgets('ACP config options show overflow menu for other categories', (
      tester,
    ) async {
      final chat = resources.track(
        chat_model.Chat.create(name: 'ACP Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.acp, null),
      );
      chat.settings.setAcpConfigOptions([
        {
          'id': 'temperature',
          'name': 'Temperature',
          'category': 'sampling',
          'values': ['0.2', '0.7'],
          'value': '0.2',
        },
      ]);

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      final overflowDropdown = find.byWidgetPredicate(
        (widget) => widget is CompactDropdown && widget.value == 'More',
      );
      check(overflowDropdown.evaluate()).isNotEmpty();
    });

    testWidgets('ACP dropdown selection sends SetConfigOptionCommand', (
      tester,
    ) async {
      final chat = resources.track(
        chat_model.Chat.create(name: 'ACP Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.acp, null),
      );
      chat.settings.setAcpConfigOptions([
        {
          'id': 'model',
          'name': 'Model',
          'category': 'model',
          'values': [
            {'value': 'model-a', 'label': 'Model A'},
            {'value': 'model-b', 'label': 'Model B'},
          ],
          'value': 'model-a',
        },
      ]);

      final transport = FakeTransport();
      chat.session.setTransport(transport);

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      final modelDropdown = find.byWidgetPredicate(
        (widget) => widget is CompactDropdown && widget.tooltip == 'Model',
      );
      await tester.tap(modelDropdown);
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Model B').last);
      await safePumpAndSettle(tester);

      check(transport.sentCommands).isNotEmpty();
      final command = transport.sentCommands.last;
      check(command).isA<sdk.SetConfigOptionCommand>();
      final setConfig = command as sdk.SetConfigOptionCommand;
      check(setConfig.configId).equals('model');
      check(setConfig.value).equals('model-b');
    });

    testWidgets('Codex group changes call setSecurityConfig', (tester) async {
      // Setup: Codex chat with initial config
      final chat = resources.track(
        chat_model.Chat.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.codex, null),
      );
      // Initialize with Codex security config
      chat.settings.setSecurityConfig(
        const sdk.CodexSecurityConfig(
          sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
          approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
        ),
      );

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Get initial config
      final initialConfig = chat.settings.securityConfig as sdk.CodexSecurityConfig;
      check(
        initialConfig.sandboxMode,
      ).equals(sdk.CodexSandboxMode.workspaceWrite);
      check(
        initialConfig.approvalPolicy,
      ).equals(sdk.CodexApprovalPolicy.onRequest);

      // Open the sandbox popup menu programmatically - a Tooltip overlay from
      // ContextIndicator intercepts taps on the PopupMenuButton in this layout.
      final popupButton = tester.widget<PopupMenuButton>(
        find.byKey(SecurityConfigGroupKeys.sandboxDropdown),
      );
      (tester.state(find.byWidget(popupButton)) as PopupMenuButtonState)
          .showButtonMenu();
      await safePumpAndSettle(tester);

      // Select "Read Only"
      await tester.tap(
        find.byKey(
          SecurityConfigGroupKeys.sandboxMenuItem(
            sdk.CodexSandboxMode.readOnly,
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Verify config changed
      final newConfig = chat.settings.securityConfig as sdk.CodexSecurityConfig;
      check(newConfig.sandboxMode).equals(sdk.CodexSandboxMode.readOnly);
      check(
        newConfig.approvalPolicy,
      ).equals(sdk.CodexApprovalPolicy.onRequest); // unchanged
    });

    testWidgets('Agent dropdown includes agents from registry when available', (
      tester,
    ) async {
      // All agents available by default in fake
      final chat = resources.track(
        chat_model.Chat.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.directCli, null),
      );

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      final agentDropdown = tester.widget<CompactDropdown>(
        find.byWidgetPredicate(
          (widget) => widget is CompactDropdown && widget.tooltip == 'Agent',
        ),
      );

      // Check that dropdown contains agent names from registry
      // (AgentConfig.defaults: 'Claude', 'Codex', 'Gemini')
      check(agentDropdown.items).contains('Claude');
      check(agentDropdown.items).contains('Codex');
      check(
        agentDropdown.items,
      ).contains('Gemini'); // ACP default is named "Gemini"
    });

    testWidgets('Selecting different agent sets chat.agents.agentId', (tester) async {
      // Codex available, ACP not
      fakeCliAvailability.agentAvailability = {
        'claude-default': true,
        'codex-default': true,
        'gemini-default': false,
      };

      final chat = resources.track(
        chat_model.Chat.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.settings.setModel(
        ChatModelCatalog.defaultForBackend(sdk.BackendType.directCli, null),
      );

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Initial agent ID should be null (not set yet)
      check(chat.agents.agentId).isNull();

      // Find the agent dropdown
      final agentDropdown = find.byWidgetPredicate(
        (widget) => widget is CompactDropdown && widget.tooltip == 'Agent',
      );
      check(agentDropdown.evaluate()).isNotEmpty();

      // Tap the dropdown to open it
      await tester.tap(agentDropdown);
      await safePumpAndSettle(tester);

      // Select "Codex"
      await tester.tap(find.text('Codex').last);
      await safePumpAndSettle(tester);

      // Verify agent ID changed to codex-default
      check(chat.agents.agentId).equals('codex-default');
      // Verify backend changed to Codex
      check(chat.settings.model.backend).equals(sdk.BackendType.codex);
    });
  });
}
