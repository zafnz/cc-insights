import 'package:cc_insights_v2/models/chat.dart' as chat_model;
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/panels/conversation_header.dart';
import 'package:cc_insights_v2/panels/compact_dropdown.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:cc_insights_v2/widgets/security_config_group.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:codex_sdk/codex_sdk.dart' show CodexSecurityConfig, CodexSecurityCapabilities;
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
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<sdk.AgentSession> createSession({
    required String prompt,
    required String cwd,
    sdk.SessionOptions? options,
    List<sdk.ContentBlock>? content,
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
  }) async {
    throw UnimplementedError();
  }

  @override
  void registerBackendForTesting(sdk.BackendType type, sdk.AgentBackend backend) {}
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
      fakeBackend = FakeBackendService();
      fakeCliAvailability = FakeCliAvailabilityService();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    Widget buildTestWidget(chat_model.ChatState chat) {
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

    testWidgets('Claude chat shows single permissions dropdown', (tester) async {
      // Setup: Claude chat
      final chat = resources.track(
        chat_model.ChatState.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.setModel(ChatModelCatalog.defaultForBackend(sdk.BackendType.directCli, null));

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Verify CompactDropdown with tooltip 'Permissions' is present
      final permissionsDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is CompactDropdown &&
            widget.tooltip == 'Permissions',
      );
      check(permissionsDropdown.evaluate()).isNotEmpty();

      // Verify SecurityConfigGroup is NOT present
      check(find.byType(SecurityConfigGroup).evaluate()).isEmpty();
    });

    testWidgets('Codex chat shows SecurityConfigGroup widget', (tester) async {
      // Setup: Codex chat
      final chat = resources.track(
        chat_model.ChatState.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.setModel(ChatModelCatalog.defaultForBackend(sdk.BackendType.codex, null));
      // Initialize with Codex security config
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Verify SecurityConfigGroup is present
      check(find.byType(SecurityConfigGroup).evaluate()).isNotEmpty();

      // Verify standard permissions CompactDropdown is NOT present
      final permissionsDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is CompactDropdown &&
            widget.tooltip == 'Permissions',
      );
      check(permissionsDropdown.evaluate()).isEmpty();
    });

    testWidgets('Claude dropdown changes call setPermissionMode', (tester) async {
      // Setup: Claude chat
      final chat = resources.track(
        chat_model.ChatState.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.setModel(ChatModelCatalog.defaultForBackend(sdk.BackendType.directCli, null));

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Initial permission mode should be Default
      check(chat.permissionMode).equals(chat_model.PermissionMode.defaultMode);

      // Find the permissions dropdown
      final permissionsDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is CompactDropdown &&
            widget.tooltip == 'Permissions',
      );
      check(permissionsDropdown.evaluate()).isNotEmpty();

      // Tap the dropdown to open it
      await tester.tap(permissionsDropdown);
      await safePumpAndSettle(tester);

      // Select "Accept Edits"
      await tester.tap(find.text('Accept Edits').last);
      await safePumpAndSettle(tester);

      // Verify permission mode changed
      check(chat.permissionMode).equals(chat_model.PermissionMode.acceptEdits);
    });

    testWidgets('Codex group changes call setSecurityConfig', (tester) async {
      // Setup: Codex chat with initial config
      final chat = resources.track(
        chat_model.ChatState.create(name: 'Test Chat', worktreeRoot: '/test/path'),
      );
      chat.setModel(ChatModelCatalog.defaultForBackend(sdk.BackendType.codex, null));
      // Initialize with Codex security config
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));

      await tester.pumpWidget(buildTestWidget(chat));
      await safePumpAndSettle(tester);

      // Get initial config
      final initialConfig = chat.securityConfig as sdk.CodexSecurityConfig;
      check(initialConfig.sandboxMode).equals(sdk.CodexSandboxMode.workspaceWrite);
      check(initialConfig.approvalPolicy).equals(sdk.CodexApprovalPolicy.onRequest);

      // Open the sandbox popup menu programmatically - a Tooltip overlay from
      // ContextIndicator intercepts taps on the PopupMenuButton in this layout.
      final popupButton = tester.widget<PopupMenuButton>(
        find.byKey(SecurityConfigGroupKeys.sandboxDropdown),
      );
      (tester.state(find.byWidget(popupButton)) as PopupMenuButtonState)
          .showButtonMenu();
      await safePumpAndSettle(tester);

      // Select "Read Only"
      await tester.tap(find.byKey(
        SecurityConfigGroupKeys.sandboxMenuItem(sdk.CodexSandboxMode.readOnly),
      ));
      await safePumpAndSettle(tester);

      // Verify config changed
      final newConfig = chat.securityConfig as sdk.CodexSecurityConfig;
      check(newConfig.sandboxMode).equals(sdk.CodexSandboxMode.readOnly);
      check(newConfig.approvalPolicy).equals(sdk.CodexApprovalPolicy.onRequest); // unchanged
    });
  });
}
