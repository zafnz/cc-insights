import 'dart:async';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/conversation_panel.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/services/internal_tools_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/theme_state.dart';
import 'package:cc_insights_v2/widgets/keyboard_focus_manager.dart';
import 'package:cc_insights_v2/widgets/permission_dialog.dart';
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
///
/// Tracks calls to createSession and allows controlling the returned session.
class FakeBackendService extends ChangeNotifier implements BackendService {
  /// The session to return from createSession.
  FakeTestSession? sessionToReturn;

  /// If set, createSession will throw this error.
  Object? createSessionError;

  /// Records of createSession calls.
  final List<_CreateSessionCall> createSessionCalls = []; // ignore: library_private_types_in_public_api

  /// Whether the backend is ready.
  bool _isReady = true;
  sdk.BackendType? _backendType = sdk.BackendType.directCli;

  @override
  bool get isReady => _isReady;

  @override
  bool get isStarting => false;

  @override
  String? get error => null;

  @override
  sdk.BackendType? get backendType => _backendType;

  @override
  bool isReadyFor(sdk.BackendType type) {
    return _isReady && _backendType == type;
  }

  @override
  bool isStartingFor(sdk.BackendType type) => false;

  @override
  bool isModelListLoadingFor(sdk.BackendType type) => false;

  @override
  String? errorFor(sdk.BackendType type) => null;

  @override
  sdk.BackendCapabilities get capabilities =>
      const sdk.BackendCapabilities(
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
  Future<void> start({
    sdk.BackendType type = sdk.BackendType.directCli,
    String? executablePath,
  }) async {
    _isReady = true;
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
    sdk.InternalToolRegistry? registry,
  }) async {
    createSessionCalls.add(_CreateSessionCall(
      prompt: prompt,
      cwd: cwd,
      options: options,
    ));

    if (createSessionError != null) {
      throw createSessionError!;
    }

    return sessionToReturn ?? FakeTestSession();
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
    return createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
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
    final session = await createSessionForBackend(
      type: type,
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
    return sdk.InProcessTransport(
      session: session,
      capabilities: capabilitiesFor(type),
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
  void registerBackendForTesting(sdk.BackendType type, sdk.AgentBackend backend) {
    // Not needed in these tests
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

/// Minimal fake TestSession for testing.
class FakeTestSession implements sdk.TestSession {
  final _eventsController = StreamController<sdk.InsightsEvent>.broadcast();
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
  String? get resolvedSessionId => sdkSessionId ?? sessionId;

  @override
  Stream<sdk.InsightsEvent> get events => _eventsController.stream;

  @override
  Stream<sdk.PermissionRequest> get permissionRequests =>
      _permissionsController.stream;

  @override
  Stream<sdk.HookRequest> get hookRequests => _hooksController.stream;

  @override
  bool get isActive => true;

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
  Future<void> setModel(String? model) async {}

  @override
  Future<void> setPermissionMode(String? mode) async {}

  @override
  Future<void> setReasoningEffort(String? effort) async {}

  @override
  String? get serverModel => null;

  @override
  String? get serverReasoningEffort => null;

  // Test-only members
  @override
  final List<String> testSentMessages = [];

  @override
  Future<void> Function(String message)? onTestSend;

  @override
  void emitTestEvent(sdk.InsightsEvent event) {
    _eventsController.add(event);
  }

  @override
  Future<sdk.PermissionResponse> emitTestPermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) async =>
      const sdk.PermissionDenyResponse(message: 'Test deny');

  void dispose() {
    _eventsController.close();
    _permissionsController.close();
    _hooksController.close();
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
    late FakeCliAvailabilityService fakeCliAvailability;
    late EventHandler fakeEventHandler;
    late ChatState testChat;

    setUp(() {
      fakeBackend = FakeBackendService();
      fakeCliAvailability = FakeCliAvailabilityService();
      fakeEventHandler = EventHandler();

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
      fakeEventHandler.dispose();
      await resources.disposeAll();
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: project),
            ChangeNotifierProvider.value(value: selectionState),
            ChangeNotifierProvider<BackendService>.value(value: fakeBackend),
            ChangeNotifierProvider<CliAvailabilityService>.value(
              value: fakeCliAvailability,
            ),
            Provider<EventHandler>.value(value: fakeEventHandler),
            ChangeNotifierProvider<InternalToolsService>(
              create: (_) => InternalToolsService(),
            ),
            ChangeNotifierProvider(create: (_) => ThemeState()),
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
        final fakeSession = FakeTestSession();
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
        final fakeSession = FakeTestSession();
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
}
