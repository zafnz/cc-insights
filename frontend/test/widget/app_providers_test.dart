import 'dart:async';

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
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
/// This fake avoids spawning a real backend subprocess.
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
  Future<void> start({
    BackendType type = BackendType.directCli,
    String? executablePath,
  }) async {
    // No-op in fake - use simulateStart() to control state
  }

  @override
  Future<void> switchBackend({
    required BackendType type,
    String? executablePath,
  }) async {
    // No-op in fake.
  }

  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    if (!_isReady) {
      throw StateError('Backend not started. Call start() first.');
    }
    return _FakeTestSession();
  }

  @override
  Future<AgentSession> createSessionForBackend({
    required BackendType type,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    String? executablePath,
  }) async {
    return createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
    );
  }
}

/// Minimal fake session for testing.
class _FakeTestSession implements TestSession {
  @override
  String get sessionId => 'fake-session';

  @override
  String? sdkSessionId = 'fake-sdk-session';

  @override
  String? get resolvedSessionId => sdkSessionId ?? sessionId;

  @override

  @override
  Stream<InsightsEvent> get events => const Stream.empty();

  @override
  Stream<PermissionRequest> get permissionRequests => const Stream.empty();

  @override
  Stream<HookRequest> get hookRequests => const Stream.empty();

  @override
  bool get isActive => true;

  @override
  Future<void> send(String message) async {}

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {}

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

  // Test-only members
  @override
  final List<String> testSentMessages = [];

  @override
  Future<void> Function(String message)? onTestSend;

  @override

  @override
  void emitTestEvent(InsightsEvent event) {}

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
  EventHandler? eventHandler,
  ProjectState? project,
  Widget? child,
}) {
  // Force mock data mode for tests
  useMockData = true;

  final testProject = project ?? MockDataFactory.createMockProject(
    watchFilesystem: false,
  );
  final testBackend = backendService ?? FakeBackendService();
  final testEventHandler = eventHandler ?? EventHandler();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<BackendService>.value(value: testBackend),
      Provider<EventHandler>.value(value: testEventHandler),
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
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();

    return Scaffold(
      body: Column(
        children: [
          Text('Backend: ${backend.isReady ? "ready" : "not ready"}'),
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

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Deep Backend: ${backend.isReady ? "ready" : "not ready"}',
                        ),
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

    group('Provider accessibility from child widgets', () {
      testWidgets('Providers are accessible from deeply nested widgets',
          (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);

        await tester.pumpWidget(
          createTestAppWithProviders(
            backendService: fakeBackend,
            child: const _DeepChildWidget(),
          ),
        );

        // Deeply nested widget should be able to access providers
        expect(find.text('Deep Backend: not ready'), findsOneWidget);
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

    });

    group('Provider order and dependencies', () {
      testWidgets('All providers are accessible together', (tester) async {
        final fakeBackend = FakeBackendService();
        resources.track(fakeBackend);
        final project = MockDataFactory.createMockProject();
        resources.track(project);

        BackendService? backend;
        ProjectState? projectState;
        SelectionState? selection;

        await tester.pumpWidget(
          createTestAppWithProviders(
            backendService: fakeBackend,
            project: project,
            child: Builder(
              builder: (context) {
                backend = context.read<BackendService>();
                projectState = context.read<ProjectState>();
                selection = context.read<SelectionState>();
                return const Text('All Providers');
              },
            ),
          ),
        );

        expect(backend, isNotNull);
        expect(projectState, isNotNull);
        expect(selection, isNotNull);

        expect(backend, same(fakeBackend));
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
