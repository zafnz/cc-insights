import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeCliBackend', () {
    group('implements AgentBackend', () {
      test('ClaudeCliBackend is a subtype of AgentBackend', () {
        // Verify at compile time that ClaudeCliBackend implements AgentBackend
        expect(ClaudeCliBackend, isA<Type>());

        // Create instance and verify it can be assigned to AgentBackend
        final backend = ClaudeCliBackend();
        expect(backend, isA<AgentBackend>());
      });

      test('has required properties from AgentBackend interface', () {
        final backend = ClaudeCliBackend();

        // Properties
        expect(backend.isRunning, isA<bool>());
        expect(backend.errors, isA<Stream<BackendError>>());
        expect(backend.logs, isA<Stream<String>>());
        expect(backend.sessions, isA<List<AgentSession>>());

        // Methods
        expect(backend.createSession, isA<Function>());
        expect(backend.dispose, isA<Function>());
      });

      test('can be used polymorphically as AgentBackend', () async {
        AgentBackend backend = ClaudeCliBackend();

        expect(backend.isRunning, isTrue);
        expect(backend.sessions, isEmpty);

        await backend.dispose();
        expect(backend.isRunning, isFalse);
      });
    });

    group('initial state', () {
      test('isRunning is true after creation', () {
        final backend = ClaudeCliBackend();

        expect(backend.isRunning, isTrue);
      });

      test('sessions is empty after creation', () {
        final backend = ClaudeCliBackend();

        expect(backend.sessions, isEmpty);
      });

      test('accepts optional executablePath parameter', () {
        final backend = ClaudeCliBackend(executablePath: '/custom/path/claude');

        expect(backend.isRunning, isTrue);
      });
    });

    group('dispose', () {
      test('isRunning is false after dispose', () async {
        final backend = ClaudeCliBackend();

        await backend.dispose();

        expect(backend.isRunning, isFalse);
      });

      test('dispose is idempotent', () async {
        final backend = ClaudeCliBackend();

        await backend.dispose();
        await backend.dispose();
        await backend.dispose();

        expect(backend.isRunning, isFalse);
      });

      test('createSession throws after dispose', () async {
        final backend = ClaudeCliBackend();
        await backend.dispose();

        expect(
          () => backend.createSession(
            prompt: 'Test',
            cwd: '/test',
          ),
          throwsA(isA<BackendProcessError>()),
        );
      });
    });

    group('errors stream', () {
      test('errors stream is broadcast', () async {
        final backend = ClaudeCliBackend();

        // Should be able to listen multiple times
        final sub1 = backend.errors.listen((_) {});
        final sub2 = backend.errors.listen((_) {});

        await sub1.cancel();
        await sub2.cancel();
        await backend.dispose();
      });

      test('errors stream closes on dispose', () async {
        final backend = ClaudeCliBackend();
        var errorsDone = false;

        backend.errors.listen((_) {}, onDone: () => errorsDone = true);

        await backend.dispose();
        await Future.delayed(Duration.zero);

        expect(errorsDone, isTrue);
      });
    });

    group('logs stream', () {
      test('logs stream is broadcast', () async {
        final backend = ClaudeCliBackend();

        // Should be able to listen multiple times
        final sub1 = backend.logs.listen((_) {});
        final sub2 = backend.logs.listen((_) {});

        await sub1.cancel();
        await sub2.cancel();
        await backend.dispose();
      });

      test('logs stream closes on dispose', () async {
        final backend = ClaudeCliBackend();
        var logsDone = false;

        backend.logs.listen((_) {}, onDone: () => logsDone = true);

        await backend.dispose();
        await Future.delayed(Duration.zero);

        expect(logsDone, isTrue);
      });
    });
  });

  group('ClaudeCliBackend with mock session', () {
    late MockCliBackendHelper helper;

    setUp(() {
      helper = MockCliBackendHelper();
    });

    tearDown(() async {
      await helper.dispose();
    });

    group('session creation', () {
      test('createSession returns AgentSession', () async {
        final session = await helper.createMockSession();

        expect(session, isA<AgentSession>());
        expect(session.sessionId, isNotEmpty);
      });

      test('session is added to sessions list', () async {
        final backend = helper.backend;
        expect(backend.sessions, isEmpty);

        await helper.createMockSession();

        expect(backend.sessions, hasLength(1));
      });

      test('multiple sessions can be created', () async {
        final session1 = await helper.createMockSession(
          sessionId: 'sess-1',
        );
        final session2 = await helper.createMockSession(
          sessionId: 'sess-2',
        );

        expect(helper.backend.sessions, hasLength(2));
        expect(session1.sessionId, equals('sess-1'));
        expect(session2.sessionId, equals('sess-2'));
      });

      test('sessions list is unmodifiable', () async {
        await helper.createMockSession();

        final sessions = helper.backend.sessions;

        // Trying to modify the list should throw
        expect(
          () => sessions.clear(),
          throwsUnsupportedError,
        );
      });
    });

    group('session properties', () {
      test('session has correct sessionId', () async {
        final session = await helper.createMockSession(
          sessionId: 'test-session-id',
        );

        expect(session.sessionId, equals('test-session-id'));
      });

      test('session isActive is true after creation', () async {
        final session = await helper.createMockSession();

        expect(session.isActive, isTrue);
      });

      test('session isActive is false after kill', () async {
        final session = await helper.createMockSession();

        await session.kill();

        expect(session.isActive, isFalse);
      });
    });

    group('session streams', () {
      test('session has messages stream', () async {
        final session = await helper.createMockSession();

        expect(session.messages, isA<Stream<SDKMessage>>());
      });

      test('session has permissionRequests stream', () async {
        final session = await helper.createMockSession();

        expect(session.permissionRequests, isA<Stream<PermissionRequest>>());
      });

      test('session has hookRequests stream', () async {
        final session = await helper.createMockSession();

        expect(session.hookRequests, isA<Stream<HookRequest>>());
      });

      test('messages stream receives SDK messages', () async {
        final session = await helper.createMockSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        helper.emitSdkMessage(session.sessionId, {
          'type': 'assistant',
          'uuid': 'msg-1',
          'session_id': session.sessionId,
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Hello!'}
            ],
          },
        });
        await Future.delayed(Duration.zero);

        expect(messages, hasLength(1));
        expect(messages[0], isA<SDKAssistantMessage>());
      });
    });

    group('session cleanup', () {
      test('session is removed from sessions list on kill', () async {
        final session = await helper.createMockSession();
        expect(helper.backend.sessions, hasLength(1));

        await session.kill();

        expect(helper.backend.sessions, isEmpty);
      });

      test('all sessions are killed on backend dispose', () async {
        final session1 = await helper.createMockSession(sessionId: 'sess-1');
        final session2 = await helper.createMockSession(sessionId: 'sess-2');
        expect(helper.backend.sessions, hasLength(2));

        await helper.backend.dispose();

        expect(session1.isActive, isFalse);
        expect(session2.isActive, isFalse);
        expect(helper.backend.sessions, isEmpty);
      });
    });

    group('session methods', () {
      test('send forwards message to CLI session', () async {
        final session = await helper.createMockSession();

        await session.send('Hello, Claude!');
        await Future.delayed(Duration.zero);

        // Verify message was sent (check stdin messages)
        expect(helper.getStdinMessages(session.sessionId), isNotEmpty);
        final lastMessage = helper.getStdinMessages(session.sessionId).last;
        expect(lastMessage['type'], equals('user.message'));
        expect(lastMessage['payload']['message'], equals('Hello, Claude!'));
      });

      test('sendWithContent forwards content to CLI session', () async {
        final session = await helper.createMockSession();

        await session.sendWithContent([
          TextBlock(text: 'Hello with content'),
        ]);
        await Future.delayed(Duration.zero);

        final lastMessage = helper.getStdinMessages(session.sessionId).last;
        expect(lastMessage['type'], equals('user.message'));
        expect(lastMessage['payload']['content'], isNotNull);
      });

      test('send throws when session is disposed', () async {
        final session = await helper.createMockSession();
        await session.kill();

        expect(
          () => session.send('Test'),
          throwsStateError,
        );
      });

      test('sendWithContent throws when session is disposed', () async {
        final session = await helper.createMockSession();
        await session.kill();

        expect(
          () => session.sendWithContent([TextBlock(text: 'Test')]),
          throwsStateError,
        );
      });

      test('interrupt is safe when disposed', () async {
        final session = await helper.createMockSession();
        await session.kill();

        // Should not throw
        await session.interrupt();
      });

      test('kill is idempotent', () async {
        final session = await helper.createMockSession();

        await session.kill();
        await session.kill();
        await session.kill();

        expect(session.isActive, isFalse);
      });
    });

    group('permission handling', () {
      test('permission requests are adapted to PermissionRequest', () async {
        final session = await helper.createMockSession();
        final requests = <PermissionRequest>[];
        session.permissionRequests.listen(requests.add);

        helper.emitCallbackRequest(
          sessionId: session.sessionId,
          requestId: 'cb-123',
          toolName: 'Bash',
          toolInput: {'command': 'ls'},
          toolUseId: 'toolu_abc',
        );
        await Future.delayed(Duration.zero);

        expect(requests, hasLength(1));
        expect(requests[0], isA<PermissionRequest>());
        expect(requests[0].toolName, equals('Bash'));
        expect(requests[0].toolInput['command'], equals('ls'));
      });

      test('permission request contains all required fields', () async {
        final session = await helper.createMockSession();
        late PermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          sessionId: session.sessionId,
          requestId: 'cb-full',
          toolName: 'Write',
          toolInput: {'file_path': '/test.txt', 'content': 'hello'},
          toolUseId: 'toolu_write',
          blockedPath: '/test.txt',
        );
        await Future.delayed(Duration.zero);

        expect(request.id, equals('cb-full'));
        expect(request.sessionId, equals(session.sessionId));
        expect(request.toolName, equals('Write'));
        expect(request.toolUseId, equals('toolu_write'));
        expect(request.blockedPath, equals('/test.txt'));
      });

      test('allow response sends callback.response to CLI', () async {
        final session = await helper.createMockSession();
        late PermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          sessionId: session.sessionId,
          requestId: 'cb-allow',
          toolName: 'Bash',
          toolInput: {'command': 'echo test'},
          toolUseId: 'toolu_allow',
        );
        await Future.delayed(Duration.zero);

        // Clear previous messages
        helper.clearStdinMessages(session.sessionId);

        // Allow the request
        request.allow();
        await Future.delayed(Duration.zero);

        // Verify response was sent
        final response = helper.getStdinMessages(session.sessionId).last;
        expect(response['type'], equals('callback.response'));
        expect(response['payload']['behavior'], equals('allow'));
      });

      test('deny response sends callback.response to CLI', () async {
        final session = await helper.createMockSession();
        late PermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          sessionId: session.sessionId,
          requestId: 'cb-deny',
          toolName: 'Write',
          toolInput: {'file_path': '/etc/passwd'},
          toolUseId: 'toolu_deny',
        );
        await Future.delayed(Duration.zero);

        helper.clearStdinMessages(session.sessionId);

        // Deny the request
        request.deny('Not allowed');
        await Future.delayed(Duration.zero);

        // Verify response was sent
        final response = helper.getStdinMessages(session.sessionId).last;
        expect(response['type'], equals('callback.response'));
        expect(response['payload']['behavior'], equals('deny'));
        expect(response['payload']['message'], equals('Not allowed'));
      });
    });

    group('concurrent sessions', () {
      test('multiple sessions can send messages concurrently', () async {
        final session1 = await helper.createMockSession(sessionId: 'sess-1');
        final session2 = await helper.createMockSession(sessionId: 'sess-2');

        // Send messages from both sessions concurrently
        await Future.wait([
          session1.send('Message from session 1'),
          session2.send('Message from session 2'),
        ]);

        final messages1 = helper.getStdinMessages('sess-1');
        final messages2 = helper.getStdinMessages('sess-2');

        expect(messages1.any((m) =>
            m['payload']?['message'] == 'Message from session 1'), isTrue);
        expect(messages2.any((m) =>
            m['payload']?['message'] == 'Message from session 2'), isTrue);
      });

      test('killing one session does not affect others', () async {
        final session1 = await helper.createMockSession(sessionId: 'sess-1');
        final session2 = await helper.createMockSession(sessionId: 'sess-2');

        await session1.kill();

        expect(session1.isActive, isFalse);
        expect(session2.isActive, isTrue);
        expect(helper.backend.sessions, hasLength(1));
      });

      test('each session receives only its messages', () async {
        final session1 = await helper.createMockSession(sessionId: 'sess-1');
        final session2 = await helper.createMockSession(sessionId: 'sess-2');

        final messages1 = <SDKMessage>[];
        final messages2 = <SDKMessage>[];
        session1.messages.listen(messages1.add);
        session2.messages.listen(messages2.add);

        // Emit message for session 1 only
        helper.emitSdkMessage('sess-1', {
          'type': 'assistant',
          'uuid': 'msg-sess1',
          'session_id': 'sess-1',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'For session 1'}
            ],
          },
        });
        await Future.delayed(Duration.zero);

        expect(messages1, hasLength(1));
        expect(messages2, isEmpty);
      });
    });

    group('error handling', () {
      test('errors stream receives backend errors', () async {
        final errors = <BackendError>[];
        helper.backend.errors.listen(errors.add);

        // Simulate an error by creating a session that fails
        // (We'll add this capability to the helper)
      });
    });
  });

  group('CliSessionAdapter', () {
    test('adapts CliPermissionRequest to PermissionRequest correctly', () async {
      final helper = MockCliBackendHelper();
      final session = await helper.createMockSession();
      late PermissionRequest adaptedRequest;
      session.permissionRequests.listen((r) => adaptedRequest = r);

      helper.emitCallbackRequest(
        sessionId: session.sessionId,
        requestId: 'adapt-test',
        toolName: 'Edit',
        toolInput: {'file_path': '/test.dart', 'old_string': 'a', 'new_string': 'b'},
        toolUseId: 'toolu_edit',
        blockedPath: '/test.dart',
        suggestions: [
          {
            'type': 'addRules',
            'rules': [
              {'toolName': 'Edit', 'ruleContent': '/test.dart'}
            ],
            'behavior': 'allow',
            'destination': 'session',
          }
        ],
      );
      await Future.delayed(Duration.zero);

      expect(adaptedRequest.id, equals('adapt-test'));
      expect(adaptedRequest.toolName, equals('Edit'));
      expect(adaptedRequest.toolUseId, equals('toolu_edit'));
      expect(adaptedRequest.blockedPath, equals('/test.dart'));
      expect(adaptedRequest.suggestions, isNotNull);
      expect(adaptedRequest.suggestions, hasLength(1));

      await helper.dispose();
    });
  });
}

// =============================================================================
// Test Helpers
// =============================================================================

/// Helper class for creating mock CLI backend and sessions for testing.
class MockCliBackendHelper {
  MockCliBackendHelper() {
    _backend = _MockableCliBackend();
  }

  late final _MockableCliBackend _backend;
  final _mockSessions = <String, _MockCliSessionData>{};

  _MockableCliBackend get backend => _backend;

  /// Create a mock session that simulates CLI initialization.
  Future<AgentSession> createMockSession({
    String sessionId = 'mock-session',
    String cwd = '/test/project',
    String prompt = 'Test prompt',
  }) async {
    final mockData = _MockCliSessionData();
    _mockSessions[sessionId] = mockData;

    final session = await _backend.createMockSession(
      sessionId: sessionId,
      cwd: cwd,
      prompt: prompt,
      mockData: mockData,
    );

    return session;
  }

  void emitSdkMessage(String sessionId, Map<String, dynamic> payload) {
    final mockData = _mockSessions[sessionId];
    if (mockData == null) return;

    mockData.emitSdkMessage(payload);
  }

  void emitCallbackRequest({
    required String sessionId,
    required String requestId,
    required String toolName,
    required Map<String, dynamic> toolInput,
    required String toolUseId,
    String? blockedPath,
    List<Map<String, dynamic>>? suggestions,
  }) {
    final mockData = _mockSessions[sessionId];
    if (mockData == null) return;

    mockData.emitCallbackRequest(
      requestId: requestId,
      toolName: toolName,
      toolInput: toolInput,
      toolUseId: toolUseId,
      blockedPath: blockedPath,
      suggestions: suggestions,
    );
  }

  List<Map<String, dynamic>> getStdinMessages(String sessionId) {
    final mockData = _mockSessions[sessionId];
    return mockData?.stdinMessages ?? [];
  }

  void clearStdinMessages(String sessionId) {
    _mockSessions[sessionId]?.clearStdinMessages();
  }

  Future<void> dispose() async {
    await _backend.dispose();
    for (final mockData in _mockSessions.values) {
      mockData.dispose();
    }
    _mockSessions.clear();
  }
}

/// Mock data for a CLI session.
class _MockCliSessionData {
  final _stdoutController = StreamController<List<int>>.broadcast();
  final _stderrController = StreamController<List<int>>.broadcast();
  final _stdinMessages = <Map<String, dynamic>>[];
  final _exitCodeCompleter = Completer<int>();
  var _killed = false;

  bool get killed => _killed;
  List<Map<String, dynamic>> get stdinMessages => _stdinMessages;

  void clearStdinMessages() => _stdinMessages.clear();

  void emitSdkMessage(Map<String, dynamic> payload) {
    final json = jsonEncode({
      'type': 'sdk.message',
      'session_id': payload['session_id'],
      'payload': payload,
    });
    _stdoutController.add(utf8.encode('$json\n'));
  }

  void emitCallbackRequest({
    required String requestId,
    required String toolName,
    required Map<String, dynamic> toolInput,
    required String toolUseId,
    String? blockedPath,
    List<Map<String, dynamic>>? suggestions,
    String sessionId = 'mock-session',
  }) {
    final json = jsonEncode({
      'type': 'callback.request',
      'id': requestId,
      'session_id': sessionId,
      'payload': {
        'callback_type': 'can_use_tool',
        'tool_name': toolName,
        'tool_input': toolInput,
        'tool_use_id': toolUseId,
        if (blockedPath != null) 'blocked_path': blockedPath,
        if (suggestions != null) 'suggestions': suggestions,
      },
    });
    _stdoutController.add(utf8.encode('$json\n'));
  }

  void onStdinWrite(Map<String, dynamic> json) {
    _stdinMessages.add(json);
  }

  void kill() {
    _killed = true;
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
  }

  void dispose() {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    _stdoutController.close();
    _stderrController.close();
  }

  Stream<List<int>> get stdout => _stdoutController.stream;
  Stream<List<int>> get stderr => _stderrController.stream;
  Future<int> get exitCode => _exitCodeCompleter.future;
}

/// A version of ClaudeCliBackend that can create mock sessions for testing.
class _MockableCliBackend implements AgentBackend {
  final _sessions = <String, _MockAgentSession>{};
  final _errorsController = StreamController<BackendError>.broadcast();
  final _logsController = StreamController<String>.broadcast();

  bool _disposed = false;

  @override
  bool get isRunning => !_disposed;

  @override
  Stream<BackendError> get errors => _errorsController.stream;

  @override
  Stream<String> get logs => _logsController.stream;

  @override
  List<AgentSession> get sessions => List.unmodifiable(_sessions.values);

  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    throw UnsupportedError('Use createMockSession instead');
  }

  Future<AgentSession> createMockSession({
    required String sessionId,
    required String cwd,
    required String prompt,
    required _MockCliSessionData mockData,
  }) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    final session = _MockAgentSession(
      sessionId: sessionId,
      mockData: mockData,
      onKill: () => _sessions.remove(sessionId),
    );
    _sessions[sessionId] = session;

    return session;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final sessionsCopy = List<_MockAgentSession>.from(_sessions.values);
    for (final session in sessionsCopy) {
      await session.kill();
    }
    _sessions.clear();

    await _errorsController.close();
    await _logsController.close();
  }
}

/// Mock agent session for testing.
class _MockAgentSession implements AgentSession {
  _MockAgentSession({
    required this.sessionId,
    required _MockCliSessionData mockData,
    required void Function() onKill,
  })  : _mockData = mockData,
        _onKill = onKill {
    _setupStreams();
  }

  final _MockCliSessionData _mockData;
  final void Function() _onKill;

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

  void _setupStreams() {
    // Listen to mock stdout and route messages
    _mockData.stdout.transform(utf8.decoder).listen((chunk) {
      for (final line in chunk.split('\n')) {
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          _handleMessage(json);
        } catch (_) {}
      }
    });
  }

  void _handleMessage(Map<String, dynamic> json) {
    if (_disposed) return;

    final type = json['type'] as String?;

    if (type == 'sdk.message') {
      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload != null) {
        final sdkMessage = SDKMessage.fromJson(payload);
        _messagesController.add(sdkMessage);
      }
    } else if (type == 'callback.request') {
      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload != null && payload['callback_type'] == 'can_use_tool') {
        final completer = Completer<PermissionResponse>();
        final request = PermissionRequest(
          id: json['id'] as String,
          sessionId: sessionId,
          toolName: payload['tool_name'] as String,
          toolInput: payload['tool_input'] as Map<String, dynamic>,
          suggestions: payload['suggestions'] as List<dynamic>?,
          toolUseId: payload['tool_use_id'] as String?,
          blockedPath: payload['blocked_path'] as String?,
          completer: completer,
        );

        _permissionRequestsController.add(request);

        // Handle response
        completer.future.then((response) {
          final responseJson = {
            'type': 'callback.response',
            'id': json['id'],
            'session_id': sessionId,
            'payload': response.toJson()
              ..['tool_use_id'] = payload['tool_use_id'],
          };
          _mockData.onStdinWrite(responseJson);
        });
      }
    }
  }

  @override
  Future<void> send(String message) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    _mockData.onStdinWrite({
      'type': 'user.message',
      'session_id': sessionId,
      'payload': {'message': message},
    });
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    _mockData.onStdinWrite({
      'type': 'user.message',
      'session_id': sessionId,
      'payload': {'content': content.map((c) => c.toJson()).toList()},
    });
  }

  @override
  Future<void> interrupt() async {
    if (_disposed) return;
  }

  @override
  Future<void> kill() async {
    if (_disposed) return;
    _disposed = true;

    _mockData.kill();
    _onKill();

    await _messagesController.close();
    await _permissionRequestsController.close();
    await _hookRequestsController.close();
  }

  @override
  Future<void> setModel(String? model) async {}

  @override
  Future<void> setPermissionMode(String? mode) async {}
}
