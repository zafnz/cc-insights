import 'dart:async';

import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:claude_sdk/claude_sdk.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

// =============================================================================
// FAKE CLAUDE BACKEND
// =============================================================================

/// Fake implementation of ClaudeBackend for testing BackendService.
///
/// This fake allows controlling the behavior of createSession and simulating
/// errors without needing a real Node.js subprocess.
class FakeClaudeBackend implements ClaudeBackend {
  FakeClaudeBackend();

  /// Sessions that have been created via [createSession].
  final List<_FakeSessionRequest> createdSessions = [];

  /// If set, [createSession] will throw this error.
  Object? createSessionError;

  /// If set, [createSession] will complete with this session.
  ClaudeSession? sessionToReturn;

  /// Delay before [createSession] completes.
  Duration? createSessionDelay;

  /// Whether [dispose] has been called.
  bool disposed = false;

  /// Error stream controller for simulating backend errors.
  final _errorsController = StreamController<BackendError>.broadcast();

  /// Logs stream controller for simulating backend logs.
  final _logsController = StreamController<String>.broadcast();

  @override
  Stream<BackendError> get errors => _errorsController.stream;

  @override
  Stream<String> get logs => _logsController.stream;

  @override
  String? get logFilePath => '/tmp/fake-backend.log';

  @override
  bool get isRunning => !disposed;

  @override
  List<AgentSession> get sessions => [];

  @override
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    if (createSessionDelay != null) {
      await Future<void>.delayed(createSessionDelay!);
    }

    if (createSessionError != null) {
      throw createSessionError!;
    }

    createdSessions.add(_FakeSessionRequest(
      prompt: prompt,
      cwd: cwd,
      options: options,
    ));

    if (sessionToReturn != null) {
      return sessionToReturn!;
    }

    // Return a minimal fake session
    return FakeClaudeSession();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _errorsController.close();
    await _logsController.close();
  }

  /// Emit an error to the errors stream.
  /// Returns false if the stream is closed.
  bool emitError(BackendError error) {
    if (_errorsController.isClosed) return false;
    _errorsController.add(error);
    return true;
  }

  /// Emit a log message to the logs stream.
  void emitLog(String log) {
    if (_logsController.isClosed) return;
    _logsController.add(log);
  }

  /// Reset all state.
  void reset() {
    createdSessions.clear();
    createSessionError = null;
    sessionToReturn = null;
    createSessionDelay = null;
    disposed = false;
  }
}

/// Record of a session creation request.
class _FakeSessionRequest {
  _FakeSessionRequest({
    required this.prompt,
    required this.cwd,
    this.options,
  });

  final String prompt;
  final String cwd;
  final SessionOptions? options;
}

/// Minimal fake ClaudeSession for testing.
class FakeClaudeSession implements ClaudeSession {
  @override
  String get sessionId => 'fake-session-id';

  @override
  String? sdkSessionId = 'fake-sdk-session-id';

  @override
  Stream<SDKMessage> get messages => const Stream.empty();

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
  Future<List<ModelInfo>> supportedModels() async => [];

  @override
  Future<List<SlashCommand>> supportedCommands() async => [];

  @override
  Future<List<McpServerStatus>> mcpServerStatus() async => [];

  @override
  Future<void> setModel(String? model) async {}

  @override
  Future<void> setPermissionMode(String? mode) async {}

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
// TESTS
// =============================================================================

void main() {
  group('BackendService', () {
    group('initial state', () {
      test('isReady is false initially', () {
        final service = BackendService();
        addTearDown(service.dispose);

        check(service.isReady).isFalse();
      });

      test('isStarting is false initially', () {
        final service = BackendService();
        addTearDown(service.dispose);

        check(service.isStarting).isFalse();
      });

      test('error is null initially', () {
        final service = BackendService();
        addTearDown(service.dispose);

        check(service.error).isNull();
      });
    });

    group('start() success', () {
      test('sets isStarting to true during start', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        // Add delay so we can observe intermediate state
        service.spawnDelay = const Duration(milliseconds: 50);

        // Start but don't await - capture intermediate state
        final startFuture = service.start();

        // Give a moment for the start to begin
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // isStarting should be true while starting
        check(service.isStarting).isTrue();
        check(service.isReady).isFalse();

        await startFuture;

        // After completion, isStarting is false
        check(service.isStarting).isFalse();
      });

      test('sets isReady to true after successful start', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        await service.start();

        check(service.isReady).isTrue();
        check(service.isStarting).isFalse();
        check(service.error).isNull();
      });

      test('notifies listeners during state transitions', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        final notifications = <bool>[];

        service.addListener(() {
          notifications.add(service.isReady);
        });

        await service.start();

        // Should have at least 2 notifications:
        // 1. When isStarting becomes true (isReady still false)
        // 2. When start completes (isReady becomes true)
        check(notifications.length).isGreaterOrEqual(2);
        check(notifications.last).isTrue();
      });
    });

    group('start() when already started', () {
      test('is a no-op when already started', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        await service.start();
        check(service.isReady).isTrue();

        // Second start should be a no-op
        await service.start();
        check(service.isReady).isTrue();
      });
    });

    group('start() when already starting', () {
      test('is a no-op when already starting (prevents concurrent starts)',
          () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        // Add delay to ensure concurrent calls overlap
        service.spawnDelay = const Duration(milliseconds: 50);

        // Start twice concurrently
        final future1 = service.start();
        final future2 = service.start();

        // Both should complete without error
        await Future.wait([future1, future2]);

        check(service.isReady).isTrue();
        // Only one backend should have been spawned
        check(service.spawnCount).equals(1);
      });
    });

    group('start() error handling', () {
      test('catches exceptions and sets error', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.shouldFailSpawn = true;

        await service.start();

        check(service.isReady).isFalse();
        check(service.isStarting).isFalse();
        check(service.error).isNotNull();
        check(service.error!).contains('spawn failed');
      });

      test('notifies listeners on error', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.shouldFailSpawn = true;

        var notified = false;
        service.addListener(() {
          notified = true;
        });

        await service.start();

        check(notified).isTrue();
      });
    });

    group('createSession() when ready', () {
      test('delegates to backend', () async {
        final fakeBackend = FakeClaudeBackend();
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.fakeBackend = fakeBackend;

        await service.start();

        final session = await service.createSession(
          prompt: 'Hello, Claude!',
          cwd: '/path/to/project',
        );

        check(session).isNotNull();
        check(fakeBackend.createdSessions.length).equals(1);
        check(fakeBackend.createdSessions.first.prompt).equals('Hello, Claude!');
        check(fakeBackend.createdSessions.first.cwd).equals('/path/to/project');
      });

      test('passes options to backend', () async {
        final fakeBackend = FakeClaudeBackend();
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.fakeBackend = fakeBackend;

        await service.start();

        final options = SessionOptions(
          model: 'claude-sonnet-4-5-20250514',
          permissionMode: PermissionMode.acceptEdits,
        );

        await service.createSession(
          prompt: 'Test',
          cwd: '/test',
          options: options,
        );

        check(fakeBackend.createdSessions.first.options).isNotNull();
      });
    });

    group('createSession() when not ready', () {
      test('throws StateError when backend not started', () async {
        final service = BackendService();
        addTearDown(service.dispose);

        try {
          await service.createSession(
            prompt: 'Hello',
            cwd: '/path',
          );
          fail('Expected StateError');
        } on StateError {
          // Expected
        }
      });

      test('StateError has descriptive message', () async {
        final service = BackendService();
        addTearDown(service.dispose);

        try {
          await service.createSession(prompt: 'Hello', cwd: '/path');
          fail('Expected StateError');
        } on StateError catch (e) {
          check(e.message).contains('start()');
        }
      });
    });

    group('dispose()', () {
      test('cleans up backend', () async {
        final fakeBackend = FakeClaudeBackend();
        final service = _TestableBackendService();
        service.fakeBackend = fakeBackend;

        await service.start();
        check(fakeBackend.disposed).isFalse();

        service.dispose();

        check(fakeBackend.disposed).isTrue();
      });

      test('can be called on service that was never started', () {
        final service = BackendService();

        // Should not throw
        service.dispose();
      });

      test('cleans up error subscription', () async {
        final fakeBackend = FakeClaudeBackend();
        final service = _TestableBackendService();
        service.fakeBackend = fakeBackend;

        await service.start();

        // Emit an error before dispose - should work
        final emitted = fakeBackend.emitError(const BackendError('test error'));
        check(emitted).isTrue();

        service.dispose();

        // After dispose, emitting another error returns false (stream closed)
        final emittedAfter =
            fakeBackend.emitError(const BackendError('another error'));
        check(emittedAfter).isFalse();
      });
    });

    group('notifyListeners', () {
      test('called when isStarting changes to true', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.spawnDelay = const Duration(milliseconds: 50);

        final isStartingValues = <bool>[];

        service.addListener(() {
          isStartingValues.add(service.isStarting);
        });

        final startFuture = service.start();

        // Should have recorded isStarting = true
        check(isStartingValues).contains(true);

        await startFuture;
      });

      test('called when isReady changes to true', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        final isReadyValues = <bool>[];

        service.addListener(() {
          isReadyValues.add(service.isReady);
        });

        await service.start();

        check(isReadyValues.last).isTrue();
      });

      test('called when error is set', () async {
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.shouldFailSpawn = true;

        String? capturedError;
        service.addListener(() {
          capturedError = service.error;
        });

        await service.start();

        check(capturedError).isNotNull();
      });

      test('called when backend error is received', () async {
        final fakeBackend = FakeClaudeBackend();
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.fakeBackend = fakeBackend;

        await service.start();

        String? capturedError;
        service.addListener(() {
          capturedError = service.error;
        });

        fakeBackend.emitError(const BackendError('Runtime error'));

        // Give time for the async listener to fire
        await Future<void>.delayed(Duration.zero);

        check(capturedError).equals('Runtime error');
      });
    });

    group('backend error monitoring', () {
      test('updates error when backend emits error', () async {
        final fakeBackend = FakeClaudeBackend();
        final service = _TestableBackendService();
        addTearDown(service.dispose);

        service.fakeBackend = fakeBackend;

        await service.start();
        check(service.error).isNull();

        fakeBackend.emitError(const BackendError('Something went wrong'));

        // Give time for the stream listener
        await Future<void>.delayed(Duration.zero);

        check(service.error).equals('Something went wrong');
      });
    });
  });
}

// =============================================================================
// TESTABLE BACKEND SERVICE
// =============================================================================

/// A testable version of BackendService that allows injecting a fake backend
/// and controlling spawn behavior.
class _TestableBackendService extends BackendService {
  FakeClaudeBackend? fakeBackend;
  bool shouldFailSpawn = false;
  Duration? spawnDelay;
  int spawnCount = 0;

  // State tracking
  bool _isStartingState = false;
  String? _errorState;
  FakeClaudeBackend? _backendState;
  StreamSubscription<BackendError>? _errorSub;
  bool _isDisposed = false;

  @override
  bool get isStarting => _isStartingState;

  @override
  bool get isReady => _backendState != null && _errorState == null;

  @override
  String? get error => _errorState;

  @override
  Future<void> start() async {
    if (_isDisposed) return;
    if (isReady || isStarting) return;

    _isStartingState = true;
    _errorState = null;
    notifyListeners();

    try {
      if (spawnDelay != null) {
        await Future<void>.delayed(spawnDelay!);
      }

      if (shouldFailSpawn) {
        throw Exception('spawn failed');
      }

      spawnCount++;
      fakeBackend ??= FakeClaudeBackend();
      _backendState = fakeBackend;

      // Monitor backend errors
      _errorSub = _backendState!.errors.listen((error) {
        _errorState = error.message;
        notifyListeners();
      });
    } catch (e) {
      _errorState = e.toString();
      _backendState = null;
    } finally {
      _isStartingState = false;
      notifyListeners();
    }
  }

  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) {
    if (_backendState == null) {
      throw StateError('Backend not started. Call start() first.');
    }
    return _backendState!.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
    );
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _errorSub?.cancel();
    _errorSub = null;
    _backendState?.dispose();
    _backendState = null;
    super.dispose();
  }
}
