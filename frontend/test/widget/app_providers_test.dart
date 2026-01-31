import 'dart:async';

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/sdk_message_handler.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/testing/mock_data.dart';
import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

// =============================================================================
// FAKE BACKEND SERVICE
// =============================================================================

/// Fake implementation of BackendService for testing provider setup.
///
/// This fake avoids spawning the real Node.js backend subprocess.
class FakeBackendService extends BackendService {
  bool _isReady = false;
  bool _isStarting = false;
  String? _error;

  @override
  bool get isReady => _isReady;

  @override
  bool get isStarting => _isStarting;

  @override
  String? get error => _error;

  /// Simulate a successful start.
  void simulateStart() {
    _isReady = true;
    _isStarting = false;
    _error = null;
    notifyListeners();
  }

  /// Simulate an error during start.
  void simulateError(String errorMessage) {
    _isReady = false;
    _isStarting = false;
    _error = errorMessage;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    // No-op in fake - use simulateStart() to control state
  }

  @override
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    if (!_isReady) {
      throw StateError('Backend not started. Call start() first.');
    }
    return _FakeClaudeSession();
  }
}

/// Minimal fake session for testing.
class _FakeClaudeSession implements ClaudeSession {
  @override
  String get sessionId => 'fake-session';

  @override
  String? sdkSessionId = 'fake-sdk-session';

  @override
  Stream<SDKMessage> get messages => const Stream.empty();

  @override
  Stream<PermissionRequest> get permissionRequests => const Stream.empty();

  @override
  Stream<HookRequest> get hookRequests => const Stream.empty();

  @override
  Future<void> send(String message) async {}

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {}

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> kill() async {}

  @override
  Future<List<ModelInfo>> supportedModels() async => [];

  @override
  Future<List<SlashCommand>> supportedCommands() async => [];

  @override
  Future<List<McpServerStatus>> mcpServerStatus() async => [];

  @override
  Future<void> setModel(String? model) async {}

  @override
  Future<void> setPermissionMode(PermissionMode mode) async {}

  // Test-only members
  @override
  final List<String> testSentMessages = [];

  @override
  Future<void> Function(String message)? onTestSend;

  @override
  void emitTestMessage(SDKMessage message) {}

  @override
  Future<PermissionResponse> emitTestPermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) async =>
      PermissionDenyResponse(message: 'Test deny');
}

// =============================================================================
// TEST HELPER
// =============================================================================

/// Creates a test app with the same provider structure as main.dart.
///
/// Use this to test that widgets can correctly access providers.
Widget createTestAppWithProviders({
  BackendService? backendService,
  SdkMessageHandler? messageHandler,
  ProjectState? project,
  Widget? child,
}) {
  // Force mock data mode for tests
  useMockData = true;

  final testProject = project ?? MockDataFactory.createMockProject(
    watchFilesystem: false,
  );
  final testBackend = backendService ?? FakeBackendService();
  final testHandler = messageHandler ?? SdkMessageHandler();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<BackendService>.value(value: testBackend),
      Provider<SdkMessageHandler>.value(value: testHandler),
      ChangeNotifierProvider<ProjectState>.value(value: testProject),
      ChangeNotifierProxyProvider<ProjectState, SelectionState>(
        create: (context) => SelectionState(context.read<ProjectState>()),
        update: (context, project, previous) =>
            previous ?? SelectionState(project),
      ),
    ],
    child: MaterialApp(
      home: child ?? const _ProviderTestWidget(),
    ),
  );
}

/// A test widget that verifies all providers are accessible.
class _ProviderTestWidget extends StatelessWidget {
  const _ProviderTestWidget();

  @override
  Widget build(BuildContext context) {
    // Try to access all providers - will throw if not available
    final backend = context.watch<BackendService>();
    final handler = context.read<SdkMessageHandler>();
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();

    return Scaffold(
      body: Column(
        children: [
          Text('Backend: ${backend.isReady ? "ready" : "not ready"}'),
          Text('Handler: ${handler.hashCode}'),
          Text('Project: ${project.data.name}'),
          Text('Selection: ${selection.hashCode}'),
        ],
      ),
    );
  }
}

/// A deeply nested widget that tests provider access from child widgets.
class _DeepChildWidget extends StatelessWidget {
  const _DeepChildWidget();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            return Builder(
              builder: (context) {
                return Builder(
                  builder: (innerContext) {
                    // Access providers from deeply nested context
                    final backend = innerContext.watch<BackendService>();
                    final handler = innerContext.read<SdkMessageHandler>();

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Deep Backend: ${backend.isReady ? "ready" : "not ready"}',
                        ),
                        Text('Deep Handler: ${handler.hashCode}'),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  final resources = TestResources();

  setUp(() {
    useMockData = true;
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  group('App Providers', () {
    group('BackendService provider', () {
      testWidgets('BackendService is provided and accessible', (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);

        await tester.pumpWidget(
          createTestAppWithProviders(backendService: fakeBackend),
        );

        // Widget should render without errors
        expect(find.textContaining('Backend:'), findsOneWidget);
      });

      testWidgets('BackendService can be accessed via Provider.of',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);

        BackendService? capturedBackend;

        await tester.pumpWidget(
          createTestAppWithProviders(
            backendService: fakeBackend,
            child: Builder(
              builder: (context) {
                capturedBackend = Provider.of<BackendService>(context);
                return const Text('Test');
              },
            ),
          ),
        );

        expect(capturedBackend, isNotNull);
        expect(capturedBackend, same(fakeBackend));
      });

      testWidgets('BackendService can be accessed via context.read',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);

        BackendService? capturedBackend;

        await tester.pumpWidget(
          createTestAppWithProviders(
            backendService: fakeBackend,
            child: Builder(
              builder: (context) {
                capturedBackend = context.read<BackendService>();
                return const Text('Test');
              },
            ),
          ),
        );

        expect(capturedBackend, isNotNull);
        expect(capturedBackend, same(fakeBackend));
      });

      testWidgets('BackendService notifies listeners on state change',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);

        await tester.pumpWidget(
          createTestAppWithProviders(backendService: fakeBackend),
        );

        // Initially not ready
        expect(find.text('Backend: not ready'), findsOneWidget);

        // Simulate backend becoming ready
        fakeBackend.simulateStart();
        await tester.pump();

        // Widget should update
        expect(find.text('Backend: ready'), findsOneWidget);
      });
    });

    group('SdkMessageHandler provider', () {
      testWidgets('SdkMessageHandler is provided and accessible',
          (tester) async {
        final handler = SdkMessageHandler();

        await tester.pumpWidget(
          createTestAppWithProviders(messageHandler: handler),
        );

        // Widget should render without errors
        expect(find.textContaining('Handler:'), findsOneWidget);
      });

      testWidgets('SdkMessageHandler can be accessed via Provider.of',
          (tester) async {
        final handler = SdkMessageHandler();

        SdkMessageHandler? capturedHandler;

        await tester.pumpWidget(
          createTestAppWithProviders(
            messageHandler: handler,
            child: Builder(
              builder: (context) {
                capturedHandler =
                    Provider.of<SdkMessageHandler>(context, listen: false);
                return const Text('Test');
              },
            ),
          ),
        );

        expect(capturedHandler, isNotNull);
        expect(capturedHandler, same(handler));
      });

      testWidgets('SdkMessageHandler can be accessed via context.read',
          (tester) async {
        final handler = SdkMessageHandler();

        SdkMessageHandler? capturedHandler;

        await tester.pumpWidget(
          createTestAppWithProviders(
            messageHandler: handler,
            child: Builder(
              builder: (context) {
                capturedHandler = context.read<SdkMessageHandler>();
                return const Text('Test');
              },
            ),
          ),
        );

        expect(capturedHandler, isNotNull);
        expect(capturedHandler, same(handler));
      });

      testWidgets('Same SdkMessageHandler instance is shared', (tester) async {
        final handler = SdkMessageHandler();
        SdkMessageHandler? firstCapture;
        SdkMessageHandler? secondCapture;

        await tester.pumpWidget(
          createTestAppWithProviders(
            messageHandler: handler,
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    firstCapture = context.read<SdkMessageHandler>();
                    return const Text('First');
                  },
                ),
                Builder(
                  builder: (context) {
                    secondCapture = context.read<SdkMessageHandler>();
                    return const Text('Second');
                  },
                ),
              ],
            ),
          ),
        );

        expect(firstCapture, isNotNull);
        expect(secondCapture, isNotNull);
        expect(firstCapture, same(secondCapture));
        expect(firstCapture, same(handler));
      });
    });

    group('Provider accessibility from child widgets', () {
      testWidgets('Providers are accessible from deeply nested widgets',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);
        final handler = SdkMessageHandler();

        await tester.pumpWidget(
          createTestAppWithProviders(
            backendService: fakeBackend,
            messageHandler: handler,
            child: const _DeepChildWidget(),
          ),
        );

        // Deeply nested widget should be able to access providers
        expect(find.text('Deep Backend: not ready'), findsOneWidget);
        expect(find.textContaining('Deep Handler:'), findsOneWidget);
      });

      testWidgets('Child widgets rebuild when BackendService changes',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);

        await tester.pumpWidget(
          createTestAppWithProviders(
            backendService: fakeBackend,
            child: const _DeepChildWidget(),
          ),
        );

        // Initially not ready
        expect(find.text('Deep Backend: not ready'), findsOneWidget);

        // Simulate state change
        fakeBackend.simulateStart();
        await tester.pump();

        // Child should rebuild with new state
        expect(find.text('Deep Backend: ready'), findsOneWidget);
      });
    });

    group('CCInsightsApp with injected services', () {
      testWidgets('CCInsightsApp accepts injected BackendService',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);

        await tester.pumpWidget(
          CCInsightsApp(
            backendService: fakeBackend,
          ),
        );
        await safePumpAndSettle(tester);

        // App should render without errors
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      testWidgets('CCInsightsApp accepts injected SdkMessageHandler',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);
        final handler = SdkMessageHandler();

        await tester.pumpWidget(
          CCInsightsApp(
            backendService: fakeBackend,
            messageHandler: handler,
          ),
        );
        await safePumpAndSettle(tester);

        // App should render without errors
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      testWidgets(
          'Injected services are accessible from app widget tree',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);
        final handler = SdkMessageHandler();

        BackendService? capturedBackend;
        SdkMessageHandler? capturedHandler;

        await tester.pumpWidget(
          CCInsightsApp(
            backendService: fakeBackend,
            messageHandler: handler,
          ),
        );
        await safePumpAndSettle(tester);

        // Navigate to find the widget tree and capture providers
        final context = tester.element(find.byType(MaterialApp));
        capturedBackend = Provider.of<BackendService>(context, listen: false);
        capturedHandler =
            Provider.of<SdkMessageHandler>(context, listen: false);

        expect(capturedBackend, same(fakeBackend));
        expect(capturedHandler, same(handler));
      });
    });

    group('Provider order and dependencies', () {
      testWidgets('All four providers are accessible together', (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);
        final handler = SdkMessageHandler();
        final project = MockDataFactory.createMockProject();
        resources.track(project);

        BackendService? backend;
        SdkMessageHandler? sdkHandler;
        ProjectState? projectState;
        SelectionState? selection;

        await tester.pumpWidget(
          createTestAppWithProviders(
            backendService: fakeBackend,
            messageHandler: handler,
            project: project,
            child: Builder(
              builder: (context) {
                backend = context.read<BackendService>();
                sdkHandler = context.read<SdkMessageHandler>();
                projectState = context.read<ProjectState>();
                selection = context.read<SelectionState>();
                return const Text('All Providers');
              },
            ),
          ),
        );

        expect(backend, isNotNull);
        expect(sdkHandler, isNotNull);
        expect(projectState, isNotNull);
        expect(selection, isNotNull);

        expect(backend, same(fakeBackend));
        expect(sdkHandler, same(handler));
        expect(projectState, same(project));
      });

      testWidgets('SelectionState depends on ProjectState', (tester) async {
        final project = MockDataFactory.createMockProject();
        resources.track(project);

        SelectionState? selection;
        ProjectState? selectionProject;

        await tester.pumpWidget(
          createTestAppWithProviders(
            project: project,
            child: Builder(
              builder: (context) {
                selection = context.read<SelectionState>();
                selectionProject = context.read<ProjectState>();
                return const Text('Dependency Test');
              },
            ),
          ),
        );

        expect(selection, isNotNull);
        expect(selectionProject, isNotNull);
        // SelectionState is created with access to the project state
        expect(selectionProject, same(project));
      });
    });
  });
}
