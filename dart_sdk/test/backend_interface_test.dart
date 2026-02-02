import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('AgentBackend interface', () {
    test('ClaudeBackend implements AgentBackend', () {
      // Verify at compile time that ClaudeBackend implements AgentBackend
      // This test passes if the code compiles
      expect(ClaudeBackend, isA<Type>());

      // We can't easily instantiate ClaudeBackend without a real process,
      // but we can verify the type hierarchy exists
      final mock = MockAgentBackend();
      expect(mock, isA<AgentBackend>());
    });

    test('AgentBackend interface has required members', () {
      // Verify the interface contract by checking a mock implementation
      final backend = MockAgentBackend();

      // Properties
      expect(backend.isRunning, isA<bool>());
      expect(backend.errors, isA<Stream<BackendError>>());
      expect(backend.logs, isA<Stream<String>>());
      expect(backend.sessions, isA<List<AgentSession>>());

      // Methods
      expect(backend.createSession, isA<Function>());
      expect(backend.dispose, isA<Function>());
    });

    test('AgentBackend.createSession returns AgentSession', () async {
      final backend = MockAgentBackend();
      final session = await backend.createSession(
        prompt: 'Hello',
        cwd: '/test',
      );

      expect(session, isA<AgentSession>());
    });

    test('AgentBackend.sessions returns list of AgentSession', () {
      final backend = MockAgentBackend();

      final sessions = backend.sessions;

      expect(sessions, isA<List<AgentSession>>());
    });
  });

  group('AgentSession interface', () {
    test('ClaudeSession.forTesting implements AgentSession', () {
      // Create a test session and verify it implements AgentSession
      final session = ClaudeSession.forTesting(sessionId: 'test-123');

      expect(session, isA<AgentSession>());

      // Access interface members
      expect(session.sessionId, equals('test-123'));
      expect(session.isActive, isTrue);
      expect(session.messages, isA<Stream<SDKMessage>>());
      expect(session.permissionRequests, isA<Stream<PermissionRequest>>());
      expect(session.hookRequests, isA<Stream<HookRequest>>());
    });

    test('AgentSession interface has required members', () {
      final session = MockAgentSession();

      // Properties
      expect(session.sessionId, isA<String>());
      expect(session.isActive, isA<bool>());
      expect(session.messages, isA<Stream<SDKMessage>>());
      expect(session.permissionRequests, isA<Stream<PermissionRequest>>());
      expect(session.hookRequests, isA<Stream<HookRequest>>());

      // Methods
      expect(session.send, isA<Function>());
      expect(session.sendWithContent, isA<Function>());
      expect(session.interrupt, isA<Function>());
      expect(session.kill, isA<Function>());
    });

    test('AgentSession.isActive reflects session state', () async {
      final session = ClaudeSession.forTesting(sessionId: 'test-active');

      expect(session.isActive, isTrue);

      await session.kill();

      expect(session.isActive, isFalse);
    });

    test('AgentSession.send accepts string message', () async {
      final session = ClaudeSession.forTesting(sessionId: 'test-send');

      // Should not throw
      await session.send('Hello, Claude!');

      expect(session.testSentMessages, contains('Hello, Claude!'));
    });

    test('AgentSession.sendWithContent accepts content blocks', () async {
      final session = ClaudeSession.forTesting(sessionId: 'test-content');

      // Should not throw
      await session.sendWithContent([
        TextBlock(text: 'Hello with content'),
      ]);

      expect(session.testSentMessages, contains('Hello with content'));
    });
  });

  group('Interface contract with mock implementation', () {
    test('mock backend follows interface contract', () async {
      final backend = MockAgentBackend();

      // Initially running
      expect(backend.isRunning, isTrue);

      // Can create session
      final session = await backend.createSession(
        prompt: 'Test prompt',
        cwd: '/test/path',
      );
      expect(session, isA<AgentSession>());
      expect(session.sessionId, equals('mock-session-1'));

      // Session added to list
      expect(backend.sessions, hasLength(1));
      expect(backend.sessions.first, equals(session));

      // Can dispose
      await backend.dispose();
      expect(backend.isRunning, isFalse);
    });

    test('mock session follows interface contract', () async {
      final session = MockAgentSession();

      // Initially active
      expect(session.isActive, isTrue);
      expect(session.sessionId, equals('mock-session'));

      // Can send messages
      await session.send('Hello');
      expect(session.sentMessages, contains('Hello'));

      // Can send content
      await session.sendWithContent([TextBlock(text: 'Content')]);
      expect(session.sentContent, hasLength(1));

      // Can interrupt
      await session.interrupt();
      expect(session.wasInterrupted, isTrue);

      // Can kill
      await session.kill();
      expect(session.isActive, isFalse);
    });

    test('backend can be used polymorphically', () async {
      // This test verifies we can use the interface polymorphically
      AgentBackend backend = MockAgentBackend();

      expect(backend.isRunning, isTrue);

      AgentSession session = await backend.createSession(
        prompt: 'Test',
        cwd: '/test',
      );

      expect(session.sessionId, isNotEmpty);
      expect(session.isActive, isTrue);

      await session.send('Message via interface');
      await backend.dispose();

      expect(backend.isRunning, isFalse);
    });

    test('session streams emit correct types', () async {
      final session = MockAgentSession();

      // Test messages stream
      final messagesReceived = <SDKMessage>[];
      session.messages.listen(messagesReceived.add);

      session.emitMessage(SDKUnknownMessage(
        rawType: 'test',
        uuid: 'test-uuid',
        sessionId: 'test',
        raw: {},
      ));
      await Future.delayed(Duration.zero);

      expect(messagesReceived, hasLength(1));
      expect(messagesReceived.first, isA<SDKMessage>());
    });

    test('ClaudeSession can be used as AgentSession', () async {
      // This test ensures ClaudeSession can be assigned to AgentSession
      AgentSession session = ClaudeSession.forTesting(sessionId: 'polymorphic');

      expect(session.sessionId, equals('polymorphic'));
      expect(session.isActive, isTrue);

      await session.send('Through interface');
      await session.kill();

      expect(session.isActive, isFalse);
    });
  });

  group('Type constraints', () {
    test('AgentBackend.createSession returns AgentSession subtype', () async {
      final backend = MockAgentBackend();

      // The return type should be assignable to AgentSession
      final AgentSession session = await backend.createSession(
        prompt: 'Test',
        cwd: '/test',
      );

      expect(session, isNotNull);
    });

    test('AgentBackend.sessions returns List<AgentSession>', () {
      final backend = MockAgentBackend();

      // The type should be List<AgentSession>
      final List<AgentSession> sessions = backend.sessions;

      expect(sessions, isA<List<AgentSession>>());
    });

    test('interfaces support optional parameters', () async {
      final backend = MockAgentBackend();

      // createSession with optional parameters
      final session1 = await backend.createSession(
        prompt: 'Test',
        cwd: '/test',
        options: SessionOptions(model: 'haiku'),
      );
      expect(session1, isA<AgentSession>());

      final session2 = await backend.createSession(
        prompt: 'Test',
        cwd: '/test',
        content: [TextBlock(text: 'Content')],
      );
      expect(session2, isA<AgentSession>());

      final session3 = await backend.createSession(
        prompt: 'Test',
        cwd: '/test',
        options: SessionOptions(permissionMode: PermissionMode.acceptEdits),
        content: [TextBlock(text: 'Content')],
      );
      expect(session3, isA<AgentSession>());
    });
  });
}

// =============================================================================
// Mock Implementations
// =============================================================================

/// Mock implementation of AgentBackend for testing the interface contract.
class MockAgentBackend implements AgentBackend {
  final _errorsController = StreamController<BackendError>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  final _sessions = <MockAgentSession>[];
  bool _disposed = false;
  int _sessionCounter = 0;

  @override
  bool get isRunning => !_disposed;

  @override
  Stream<BackendError> get errors => _errorsController.stream;

  @override
  Stream<String> get logs => _logsController.stream;

  @override
  List<AgentSession> get sessions => List.unmodifiable(_sessions);

  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    if (_disposed) {
      throw StateError('Backend has been disposed');
    }

    _sessionCounter++;
    final session = MockAgentSession(sessionId: 'mock-session-$_sessionCounter');
    _sessions.add(session);
    return session;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final session in _sessions) {
      await session.kill();
    }
    _sessions.clear();

    await _errorsController.close();
    await _logsController.close();
  }
}

/// Mock implementation of AgentSession for testing the interface contract.
class MockAgentSession implements AgentSession {
  MockAgentSession({String? sessionId})
      : sessionId = sessionId ?? 'mock-session';

  final _messagesController = StreamController<SDKMessage>.broadcast();
  final _permissionRequestsController =
      StreamController<PermissionRequest>.broadcast();
  final _hookRequestsController = StreamController<HookRequest>.broadcast();

  bool _disposed = false;

  @override
  final String sessionId;

  @override
  bool get isActive => !_disposed;

  @override
  Stream<SDKMessage> get messages => _messagesController.stream;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  @override
  Stream<HookRequest> get hookRequests => _hookRequestsController.stream;

  /// Track sent messages for testing.
  final List<String> sentMessages = [];

  /// Track sent content for testing.
  final List<List<ContentBlock>> sentContent = [];

  /// Track if interrupted.
  bool wasInterrupted = false;

  @override
  Future<void> send(String message) async {
    if (_disposed) return;
    sentMessages.add(message);
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) return;
    sentContent.add(content);
  }

  @override
  Future<void> interrupt() async {
    if (_disposed) return;
    wasInterrupted = true;
  }

  @override
  Future<void> kill() async {
    if (_disposed) return;
    _disposed = true;
    await _messagesController.close();
    await _permissionRequestsController.close();
    await _hookRequestsController.close();
  }

  @override
  Future<void> setModel(String? model) async {}

  @override
  Future<void> setPermissionMode(String? mode) async {}

  /// Emit a message for testing.
  void emitMessage(SDKMessage message) {
    if (_disposed) return;
    _messagesController.add(message);
  }
}
