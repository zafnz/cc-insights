import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('CliSession', () {
    late MockCliProcessHelper helper;

    setUp(() {
      helper = MockCliProcessHelper();
    });

    tearDown(() async {
      await helper.dispose();
    });

    group('initialization sequence', () {
      test('sends session.create request with correct format', () async {
        // Arrange
        final process = helper.createMockProcess();
        final sessionFuture = CliSessionForTesting.createWithProcess(
          process: process,
          cwd: '/test/project',
          prompt: 'Hello, Claude!',
        );

        // Wait for the request to be sent
        await Future.delayed(Duration.zero);

        // Assert - verify the session.create request was sent
        expect(helper.stdinMessages, hasLength(1));
        final request = helper.stdinMessages[0];
        expect(request['type'], equals('session.create'));
        expect(request['id'], isNotNull);
        expect(request['payload']['prompt'], equals('Hello, Claude!'));
        expect(request['payload']['cwd'], equals('/test/project'));

        // Complete initialization
        helper.emitSessionCreated(requestId: request['id'] as String);
        helper.emitSystemInit();
        await Future.delayed(Duration.zero);

        final session = await sessionFuture;
        await session.dispose();
      });

      test('includes session options in request', () async {
        // Arrange
        final process = helper.createMockProcess();
        final sessionFuture = CliSessionForTesting.createWithProcess(
          process: process,
          cwd: '/test/project',
          prompt: 'Test prompt',
          options: SessionOptions(
            model: 'sonnet',
            permissionMode: PermissionMode.acceptEdits,
            maxTurns: 10,
            maxBudgetUsd: 5.0,
          ),
        );

        // Wait for the request
        await Future.delayed(Duration.zero);

        // Assert
        final request = helper.stdinMessages[0];
        final options = request['payload']['options'] as Map<String, dynamic>;
        expect(options['model'], equals('sonnet'));
        expect(options['permission_mode'], equals('acceptEdits'));
        expect(options['max_turns'], equals(10));
        expect(options['max_budget_usd'], equals(5.0));

        // Complete initialization
        helper.emitSessionCreated(requestId: request['id'] as String);
        helper.emitSystemInit();
        await Future.delayed(Duration.zero);

        final session = await sessionFuture;
        await session.dispose();
      });

      test('waits for session.created and system init', () async {
        // Arrange
        final process = helper.createMockProcess();
        final sessionFuture = CliSessionForTesting.createWithProcess(
          process: process,
          cwd: '/test/project',
          prompt: 'Test',
        );

        // Wait for request
        await Future.delayed(Duration.zero);
        final requestId = helper.stdinMessages[0]['id'] as String;

        // Verify session is not yet complete
        var completed = false;
        // ignore: unawaited_futures
        sessionFuture.then((_) => completed = true);
        await Future.delayed(Duration.zero);
        expect(completed, isFalse);

        // Send session.created
        helper.emitSessionCreated(
          requestId: requestId,
          sessionId: 'sess-12345',
        );
        await Future.delayed(Duration.zero);
        expect(completed, isFalse);

        // Send system init
        helper.emitSystemInit(sessionId: 'sess-12345');
        await Future.delayed(Duration.zero);

        final session = await sessionFuture;

        // Assert
        expect(session.sessionId, equals('sess-12345'));
        expect(session.systemInit, isNotNull);
        expect(session.systemInit.subtype, equals('init'));

        await session.dispose();
      });

      test('throws on timeout when no session.created received', () async {
        // Arrange
        final process = helper.createMockProcess();

        // Act & Assert
        await expectLater(
          CliSessionForTesting.createWithProcess(
            process: process,
            cwd: '/test',
            prompt: 'Test',
            timeout: Duration(milliseconds: 100),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('throws on timeout when no system init received', () async {
        // Arrange
        final process = helper.createMockProcess();
        final sessionFuture = CliSessionForTesting.createWithProcess(
          process: process,
          cwd: '/test',
          prompt: 'Test',
          timeout: Duration(milliseconds: 100),
        );

        // Send session.created but no system init
        await Future.delayed(Duration.zero);
        final requestId = helper.stdinMessages[0]['id'] as String;
        helper.emitSessionCreated(requestId: requestId);

        // Assert
        await expectLater(sessionFuture, throwsA(isA<TimeoutException>()));
      });

      test('cleans up process on initialization error', () async {
        // Arrange
        final process = helper.createMockProcess();

        // Act - let it timeout
        try {
          await CliSessionForTesting.createWithProcess(
            process: process,
            cwd: '/test',
            prompt: 'Test',
            timeout: Duration(milliseconds: 50),
          );
        } catch (_) {
          // Expected
        }

        // Assert - process should have been killed
        expect(helper.killed, isTrue);
      });
    });

    group('message routing', () {
      test('routes SDK messages to messages stream', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        // Act - emit an assistant message
        helper.emitSdkMessage({
          'type': 'assistant',
          'uuid': 'msg-1',
          'session_id': 'sess-123',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Hello!'}
            ],
          },
        });
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(1));
        expect(messages[0], isA<SDKAssistantMessage>());
        final assistantMsg = messages[0] as SDKAssistantMessage;
        expect(assistantMsg.uuid, equals('msg-1'));

        await session.dispose();
      });

      test('routes callback.request to permissionRequests stream', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final requests = <CliPermissionRequest>[];
        session.permissionRequests.listen(requests.add);

        // Act - emit a permission request
        helper.emitCallbackRequest(
          requestId: 'cb-123',
          toolName: 'Bash',
          toolInput: {'command': 'ls -la'},
          toolUseId: 'toolu_abc',
        );
        await Future.delayed(Duration.zero);

        // Assert
        expect(requests, hasLength(1));
        expect(requests[0].requestId, equals('cb-123'));
        expect(requests[0].toolName, equals('Bash'));
        expect(requests[0].input['command'], equals('ls -la'));
        expect(requests[0].toolUseId, equals('toolu_abc'));

        await session.dispose();
      });

      test('includes permission suggestions in request', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final requests = <CliPermissionRequest>[];
        session.permissionRequests.listen(requests.add);

        // Act
        helper.emitCallbackRequest(
          requestId: 'cb-456',
          toolName: 'Read',
          toolInput: {'file_path': '/private/etc/passwd'},
          toolUseId: 'toolu_xyz',
          blockedPath: '/private/etc',
          suggestions: [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Read', 'ruleContent': '/private/etc/**'}
              ],
              'behavior': 'allow',
              'destination': 'session',
            }
          ],
        );
        await Future.delayed(Duration.zero);

        // Assert
        expect(requests, hasLength(1));
        expect(requests[0].blockedPath, equals('/private/etc'));
        expect(requests[0].suggestions, isNotNull);
        expect(requests[0].suggestions!.length, equals(1));
        expect(requests[0].suggestions!.first.type, equals('addRules'));

        await session.dispose();
      });

      test('routes user messages to messages stream', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        // Act
        helper.emitSdkMessage({
          'type': 'user',
          'session_id': 'sess-123',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'User message'}
            ],
          },
        });
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(1));
        expect(messages[0], isA<SDKUserMessage>());

        await session.dispose();
      });

      test('routes result messages to messages stream', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        // Act
        helper.emitSdkMessage({
          'type': 'result',
          'subtype': 'success',
          'uuid': 'res-1',
          'session_id': 'sess-123',
          'duration_ms': 1000,
          'duration_api_ms': 800,
          'is_error': false,
          'num_turns': 3,
          'result': 'Task completed',
        });
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(1));
        expect(messages[0], isA<SDKResultMessage>());
        final result = messages[0] as SDKResultMessage;
        expect(result.result, equals('Task completed'));
        expect(result.numTurns, equals(3));

        await session.dispose();
      });

      test('routes stream events to messages stream', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        // Act
        helper.emitSdkMessage({
          'type': 'stream_event',
          'uuid': 'stream-1',
          'session_id': 'sess-123',
          'event': {
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'Hello'},
          },
        });
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(1));
        expect(messages[0], isA<SDKStreamEvent>());
        final streamEvent = messages[0] as SDKStreamEvent;
        expect(streamEvent.textDelta, equals('Hello'));

        await session.dispose();
      });

      test('ignores session.created after initialization', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        // Act - emit another session.created (should be ignored)
        helper.emitSessionCreated(requestId: 'late-req');
        await Future.delayed(Duration.zero);

        // Assert - no messages should be emitted
        expect(messages, isEmpty);

        await session.dispose();
      });

    });

    group('permission request/response flow', () {
      test('allow sends control_response with allow behavior', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        late CliPermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          requestId: 'cb-allow-test',
          toolName: 'Bash',
          toolInput: {'command': 'echo test'},
          toolUseId: 'toolu_allow',
        );
        await Future.delayed(Duration.zero);

        // Clear previous messages
        helper.clearStdinMessages();

        // Act
        request.allow();
        await Future.delayed(Duration.zero);

        // Assert - CLI expects control_response format
        // Outer uses request_id (snake_case), inner uses toolUseID (capital ID)
        expect(helper.stdinMessages, hasLength(1));
        final response = helper.stdinMessages[0];
        expect(response['type'], equals('control_response'));
        final innerResponse = response['response'] as Map<String, dynamic>;
        expect(innerResponse['subtype'], equals('success'));
        expect(innerResponse['request_id'], equals('cb-allow-test'));
        final payload = innerResponse['response'] as Map<String, dynamic>;
        expect(payload['behavior'], equals('allow'));
        expect(payload['toolUseID'], equals('toolu_allow'));
        // updatedInput should be original input when not provided
        expect(payload['updatedInput']['command'], equals('echo test'));

        await session.dispose();
      });

      test('allow includes updatedInput when provided', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        late CliPermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          requestId: 'cb-updated',
          toolName: 'Bash',
          toolInput: {'command': 'rm -rf /'},
          toolUseId: 'toolu_updated',
        );
        await Future.delayed(Duration.zero);
        helper.clearStdinMessages();

        // Act - allow with modified input
        request.allow(updatedInput: {'command': 'echo "safe command"'});
        await Future.delayed(Duration.zero);

        // Assert - CLI expects updatedInput in response
        final response = helper.stdinMessages[0];
        final innerResponse = response['response'] as Map<String, dynamic>;
        final payload = innerResponse['response'] as Map<String, dynamic>;
        expect(payload['updatedInput']['command'],
            equals('echo "safe command"'));

        await session.dispose();
      });

      test('deny sends control_response with deny behavior', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        late CliPermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          requestId: 'cb-deny-test',
          toolName: 'Write',
          toolInput: {'file_path': '/etc/passwd'},
          toolUseId: 'toolu_deny',
        );
        await Future.delayed(Duration.zero);
        helper.clearStdinMessages();

        // Act
        request.deny('This operation is not allowed');
        await Future.delayed(Duration.zero);

        // Assert - CLI expects control_response format
        // Outer uses request_id (snake_case), inner uses toolUseID (capital ID)
        expect(helper.stdinMessages, hasLength(1));
        final response = helper.stdinMessages[0];
        expect(response['type'], equals('control_response'));
        final innerResponse = response['response'] as Map<String, dynamic>;
        expect(innerResponse['request_id'], equals('cb-deny-test'));
        final payload = innerResponse['response'] as Map<String, dynamic>;
        expect(payload['behavior'], equals('deny'));
        expect(payload['message'],
            equals('This operation is not allowed'));

        await session.dispose();
      });

      test('throws when responding twice to same request', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        late CliPermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          requestId: 'cb-double',
          toolName: 'Bash',
          toolInput: {},
          toolUseId: 'toolu_double',
        );
        await Future.delayed(Duration.zero);

        // Act
        request.allow();

        // Assert - second response should throw
        expect(() => request.allow(), throwsStateError);
        expect(() => request.deny(), throwsStateError);

        await session.dispose();
      });

      test('responded property tracks response status', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        late CliPermissionRequest request;
        session.permissionRequests.listen((r) => request = r);

        helper.emitCallbackRequest(
          requestId: 'cb-responded',
          toolName: 'Bash',
          toolInput: {},
          toolUseId: 'toolu_responded',
        );
        await Future.delayed(Duration.zero);

        // Assert - not responded initially
        expect(request.responded, isFalse);

        // Act
        request.allow();

        // Assert - responded after allow
        expect(request.responded, isTrue);

        await session.dispose();
      });
    });

    group('send message formatting', () {
      test('send formats user message correctly', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        helper.clearStdinMessages();

        // Act
        await session.send('Hello, follow-up message!');

        // Assert
        expect(helper.stdinMessages, hasLength(1));
        final message = helper.stdinMessages[0];
        expect(message['type'], equals('user.message'));
        expect(message['session_id'], equals('sess-123'));
        expect(message['payload']['message'],
            equals('Hello, follow-up message!'));

        await session.dispose();
      });

      test('sendWithContent formats content blocks correctly', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        helper.clearStdinMessages();

        // Act
        await session.sendWithContent([
          TextBlock(text: 'Text message'),
          ImageBlock(
            source: ImageSource(
              type: 'base64',
              mediaType: 'image/png',
              data: 'base64data',
            ),
          ),
        ]);

        // Assert
        expect(helper.stdinMessages, hasLength(1));
        final message = helper.stdinMessages[0];
        expect(message['type'], equals('user.message'));
        expect(message['session_id'], equals('sess-123'));
        final content = message['payload']['content'] as List;
        expect(content, hasLength(2));
        expect(content[0]['type'], equals('text'));
        expect(content[0]['text'], equals('Text message'));
        expect(content[1]['type'], equals('image'));
        expect(content[1]['source']['type'], equals('base64'));

        await session.dispose();
      });

      test('send throws when disposed', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        await session.dispose();

        // Assert
        expect(() => session.send('Test'), throwsStateError);
      });

      test('sendWithContent throws when disposed', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        await session.dispose();

        // Assert
        expect(
          () => session.sendWithContent([TextBlock(text: 'Test')]),
          throwsStateError,
        );
      });
    });

    group('interrupt and kill', () {
      test('interrupt sends session.interrupt message', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        helper.clearStdinMessages();

        // Act
        await session.interrupt();

        // Assert
        expect(helper.stdinMessages, hasLength(1));
        final message = helper.stdinMessages[0];
        expect(message['type'], equals('session.interrupt'));
        expect(message['session_id'], equals('sess-123'));

        await session.dispose();
      });

      test('interrupt is safe when disposed', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        await session.dispose();

        // Act & Assert - should not throw
        await session.interrupt();
      });

      test('kill terminates the process', () async {
        // Arrange
        final session = await helper.createInitializedSession();

        // Act
        await session.kill();

        // Assert
        expect(helper.killed, isTrue);
        expect(session.isActive, isFalse);
      });

      test('kill closes streams', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        var messagesDone = false;
        var permissionsDone = false;

        session.messages.listen((_) {}, onDone: () => messagesDone = true);
        session.permissionRequests.listen((_) {},
            onDone: () => permissionsDone = true);

        // Act
        await session.kill();
        await Future.delayed(Duration.zero);

        // Assert
        expect(messagesDone, isTrue);
        expect(permissionsDone, isTrue);
      });

      test('kill is safe when already disposed', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        await session.dispose();

        // Act & Assert - should not throw
        await session.kill();
      });

      test('dispose cleans up all resources', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        var messagesDone = false;
        session.messages.listen((_) {}, onDone: () => messagesDone = true);

        // Act
        await session.dispose();
        await Future.delayed(Duration.zero);

        // Assert
        expect(session.isActive, isFalse);
        expect(messagesDone, isTrue);
      });

      test('dispose is idempotent', () async {
        // Arrange
        final session = await helper.createInitializedSession();

        // Act - dispose multiple times
        await session.dispose();
        await session.dispose();
        await session.dispose();

        // Assert - should not throw
        expect(session.isActive, isFalse);
      });
    });

    group('isActive property', () {
      test('isActive is true after initialization', () async {
        // Arrange
        final session = await helper.createInitializedSession();

        // Assert
        expect(session.isActive, isTrue);

        await session.dispose();
      });

      test('isActive is false after dispose', () async {
        // Arrange
        final session = await helper.createInitializedSession();

        // Act
        await session.dispose();

        // Assert
        expect(session.isActive, isFalse);
      });

      test('isActive is false after kill', () async {
        // Arrange
        final session = await helper.createInitializedSession();

        // Act
        await session.kill();

        // Assert
        expect(session.isActive, isFalse);
      });
    });

    group('edge cases', () {
      test('handles malformed SDK messages gracefully', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        // Act - emit a message with missing type
        helper.emitRawStdout('{"invalid": "message", "no_type": true}\n');
        await Future.delayed(Duration.zero);

        // Assert - should not crash, message may be parsed as unknown
        // The important thing is the session is still functional
        expect(session.isActive, isTrue);

        await session.dispose();
      });

      test('does not emit messages after dispose', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final messages = <SDKMessage>[];
        session.messages.listen(messages.add);

        // Act
        await session.dispose();
        helper.emitSdkMessage({
          'type': 'assistant',
          'uuid': 'late-msg',
          'session_id': 'sess-123',
          'message': {
            'role': 'assistant',
            'content': [],
          },
        });
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, isEmpty);
      });

      test('does not emit permission requests after dispose', () async {
        // Arrange
        final session = await helper.createInitializedSession();
        final requests = <CliPermissionRequest>[];
        session.permissionRequests.listen(requests.add);

        // Act
        await session.dispose();
        helper.emitCallbackRequest(
          requestId: 'late-cb',
          toolName: 'Bash',
          toolInput: {},
          toolUseId: 'toolu_late',
        );
        await Future.delayed(Duration.zero);

        // Assert
        expect(requests, isEmpty);
      });

    });
  });

  group('CliPermissionRequest', () {
    late MockCliProcessHelper helper;

    setUp(() {
      helper = MockCliProcessHelper();
    });

    tearDown(() async {
      await helper.dispose();
    });

    test('exposes all properties from callback request', () async {
      // Arrange
      final session = await helper.createInitializedSession();
      late CliPermissionRequest request;
      session.permissionRequests.listen((r) => request = r);

      // Act
      helper.emitCallbackRequest(
        requestId: 'req-properties',
        toolName: 'Edit',
        toolInput: {'file_path': '/test.txt', 'content': 'new content'},
        toolUseId: 'toolu_properties',
        blockedPath: '/test.txt',
        suggestions: [
          {
            'type': 'addRules',
            'rules': [
              {'toolName': 'Edit', 'ruleContent': '/test.txt'}
            ],
            'behavior': 'allow',
            'destination': 'session',
          }
        ],
      );
      await Future.delayed(Duration.zero);

      // Assert
      expect(request.requestId, equals('req-properties'));
      expect(request.toolName, equals('Edit'));
      expect(request.toolUseId, equals('toolu_properties'));
      expect(request.input['file_path'], equals('/test.txt'));
      expect(request.input['content'], equals('new content'));
      expect(request.blockedPath, equals('/test.txt'));
      expect(request.suggestions, isNotNull);
      expect(request.suggestions!.length, equals(1));

      await session.dispose();
    });

    test('handles null optional properties', () async {
      // Arrange
      final session = await helper.createInitializedSession();
      late CliPermissionRequest request;
      session.permissionRequests.listen((r) => request = r);

      // Act - emit without optional properties
      helper.emitCallbackRequest(
        requestId: 'req-minimal',
        toolName: 'Bash',
        toolInput: {'command': 'ls'},
        toolUseId: 'toolu_minimal',
      );
      await Future.delayed(Duration.zero);

      // Assert
      expect(request.blockedPath, isNull);
      expect(request.suggestions, isNull);

      await session.dispose();
    });
  });
}

// =============================================================================
// Test Helpers
// =============================================================================

/// Helper class for creating mock CLI processes for testing CliSession.
class MockCliProcessHelper {
  final _stdoutController = StreamController<List<int>>.broadcast();
  final _stderrController = StreamController<List<int>>.broadcast();
  final _stdinMessages = <Map<String, dynamic>>[];
  final _exitCodeCompleter = Completer<int>();
  var _killed = false;
  MockProcess? _mockProcess;

  bool get killed => _killed;
  List<Map<String, dynamic>> get stdinMessages => _stdinMessages;

  void clearStdinMessages() {
    _stdinMessages.clear();
  }

  MockProcess createMockProcess() {
    _mockProcess = MockProcess(
      stdout: _stdoutController.stream,
      stderr: _stderrController.stream,
      stdin: _MockIOSink((json) => _stdinMessages.add(json)),
      exitCode: _exitCodeCompleter.future,
      onKill: () {
        _killed = true;
        if (!_exitCodeCompleter.isCompleted) {
          _exitCodeCompleter.complete(0);
        }
      },
    );
    return _mockProcess!;
  }

  /// Create an initialized session for testing.
  ///
  /// This sends the necessary session.created and system init messages
  /// automatically.
  Future<CliSession> createInitializedSession({
    String sessionId = 'sess-123',
  }) async {
    final process = createMockProcess();
    final sessionFuture = CliSessionForTesting.createWithProcess(
      process: process,
      cwd: '/test/project',
      prompt: 'Test prompt',
    );

    // Wait for the request to be sent
    await Future.delayed(Duration.zero);
    final requestId = _stdinMessages[0]['id'] as String;

    // Complete initialization
    emitSessionCreated(requestId: requestId, sessionId: sessionId);
    emitSystemInit(sessionId: sessionId);
    await Future.delayed(Duration.zero);

    return sessionFuture;
  }

  void emitSessionCreated({
    required String requestId,
    String sessionId = 'sess-123',
  }) {
    final json = jsonEncode({
      'type': 'session.created',
      'id': requestId,
      'session_id': sessionId,
      'payload': {},
    });
    _stdoutController.add(utf8.encode('$json\n'));
  }

  void emitSystemInit({String sessionId = 'sess-123'}) {
    final json = jsonEncode({
      'type': 'sdk.message',
      'session_id': sessionId,
      'payload': {
        'type': 'system',
        'subtype': 'init',
        'uuid': 'sys-init-1',
        'session_id': sessionId,
        'apiKeySource': 'anthropic',
        'cwd': '/test/project',
        'tools': ['Bash', 'Read', 'Write', 'Edit'],
        'model': 'sonnet',
        'permissionMode': 'default',
      },
    });
    _stdoutController.add(utf8.encode('$json\n'));
  }

  void emitSdkMessage(Map<String, dynamic> payload) {
    final json = jsonEncode({
      'type': 'sdk.message',
      'session_id': payload['session_id'] ?? 'sess-123',
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
    String sessionId = 'sess-123',
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

  void emitRawStdout(String data) {
    _stdoutController.add(utf8.encode(data));
  }

  Future<void> dispose() async {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    await _stdoutController.close();
    await _stderrController.close();
  }
}

/// Mock Process implementation for testing.
class MockProcess implements Process {
  MockProcess({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required IOSink stdin,
    required Future<int> exitCode,
    required VoidCallback onKill,
  })  : _stdout = stdout,
        _stderr = stderr,
        _stdin = stdin,
        _exitCode = exitCode,
        _onKill = onKill;

  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final IOSink _stdin;
  final Future<int> _exitCode;
  final VoidCallback _onKill;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  IOSink get stdin => _stdin;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 12345;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _onKill();
    return true;
  }
}

/// Mock IOSink that parses JSON from writeln calls.
class _MockIOSink implements IOSink {
  _MockIOSink(this._onWriteln);

  final void Function(Map<String, dynamic>) _onWriteln;

  @override
  void writeln([Object? obj = '']) {
    final str = obj.toString();
    try {
      final json = jsonDecode(str) as Map<String, dynamic>;
      _onWriteln(json);
    } catch (_) {
      // Ignore non-JSON
    }
  }

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {}

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future close() async {}

  @override
  Future get done async {}

  @override
  Future flush() async {}

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}
}

typedef VoidCallback = void Function();

/// CliSession extension for testing that allows injecting a mock process.
class CliSessionForTesting {
  /// Create a CliSession with a mock process for testing.
  static Future<CliSession> createWithProcess({
    required Process process,
    required String cwd,
    required String prompt,
    SessionOptions? options,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    // Create a CliProcessForTesting that wraps the mock process
    final cliProcess = CliProcessForTesting(process: process);

    try {
      // Generate a unique request ID
      final requestId = _generateRequestId();

      // Send session.create request
      final createRequest = ControlRequest(
        type: 'session.create',
        id: requestId,
        payload: SessionCreatePayload(
          prompt: prompt,
          cwd: cwd,
          options: _convertToSessionCreateOptions(options),
        ),
      );
      cliProcess.send(createRequest.toJson());

      // Wait for session.created response
      String? sessionId;
      SDKSystemMessage? systemInit;

      await for (final json in cliProcess.messages.timeout(timeout)) {
        final messageType = parseCliMessageType(json);

        if (messageType == CliMessageType.sessionCreated) {
          final created = SessionCreatedMessage.fromJson(json);
          if (created.id == requestId) {
            sessionId = created.sessionId;
          }
        } else if (messageType == CliMessageType.sdkMessage) {
          final payload = json['payload'] as Map<String, dynamic>?;
          if (payload != null) {
            final type = payload['type'] as String?;
            if (type == 'system') {
              final subtype = payload['subtype'] as String?;
              if (subtype == 'init') {
                systemInit = SDKSystemMessage.fromJson(payload);
              }
            }
          }
        }

        // Check if initialization is complete
        if (sessionId != null && systemInit != null) {
          break;
        }
      }

      if (sessionId == null) {
        throw StateError('Session creation timed out: no session.created');
      }
      if (systemInit == null) {
        throw StateError('Session creation timed out: no system init');
      }

      return CliSessionForTestingImpl(
        process: cliProcess,
        sessionId: sessionId,
        systemInit: systemInit,
      );
    } catch (e) {
      await cliProcess.dispose();
      rethrow;
    }
  }

  static String _generateRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'req-$now-${now.hashCode.toRadixString(16)}';
  }

  static SessionCreateOptions? _convertToSessionCreateOptions(
    SessionOptions? options,
  ) {
    if (options == null) return null;

    String? systemPromptString;
    if (options.systemPrompt != null) {
      final json = options.systemPrompt!.toJson();
      if (json is String) {
        systemPromptString = json;
      }
    }

    return SessionCreateOptions(
      model: options.model,
      permissionMode: options.permissionMode?.value,
      systemPrompt: systemPromptString,
      mcpServers: options.mcpServers != null
          ? options.mcpServers!.map((k, v) => MapEntry(k, v.toJson()))
          : null,
      maxTurns: options.maxTurns,
      maxBudgetUsd: options.maxBudgetUsd,
      resume: options.resume,
    );
  }
}

/// Test implementation of CliSession that uses a mock process.
class CliSessionForTestingImpl implements CliSession {
  CliSessionForTestingImpl({
    required CliProcessForTesting process,
    required this.sessionId,
    required this.systemInit,
  }) : _process = process {
    _setupMessageRouting();
  }

  final CliProcessForTesting _process;
  @override
  final String sessionId;
  @override
  final SDKSystemMessage systemInit;

  final _messagesController = StreamController<SDKMessage>.broadcast();
  final _permissionRequestsController =
      StreamController<CliPermissionRequest>.broadcast();

  bool _disposed = false;

  @override
  Stream<SDKMessage> get messages => _messagesController.stream;

  @override
  Stream<CliPermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  @override
  bool get isActive => !_disposed && _process.isRunning;

  @override
  CliProcess get process => throw UnimplementedError(
      'process getter not available for testing implementation');

  void _setupMessageRouting() {
    _process.messages.listen(
      _handleMessage,
      onError: (Object error) {
        if (!_disposed) {
          _messagesController.addError(error);
        }
      },
      onDone: () {
        if (!_disposed) {
          _dispose();
        }
      },
    );
  }

  void _handleMessage(Map<String, dynamic> json) {
    if (_disposed) return;

    final messageType = parseCliMessageType(json);

    switch (messageType) {
      case CliMessageType.callbackRequest:
        final callbackRequest = CallbackRequest.fromJson(json);
        if (callbackRequest.payload.callbackType == 'can_use_tool') {
          final request = _CliPermissionRequestForTesting(
            session: this,
            requestId: callbackRequest.id,
            toolName: callbackRequest.payload.toolName,
            input: callbackRequest.payload.toolInput,
            toolUseId: callbackRequest.payload.toolUseId,
            suggestions: callbackRequest.payload.suggestions,
            blockedPath: callbackRequest.payload.blockedPath,
          );
          _permissionRequestsController.add(request);
        }

      case CliMessageType.sdkMessage:
        final payload = json['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          final sdkMessage = SDKMessage.fromJson(payload);
          _messagesController.add(sdkMessage);
        }

      case CliMessageType.sessionCreated:
        break;

      case CliMessageType.unknown:
        try {
          final sdkMessage = SDKMessage.fromJson(json);
          _messagesController.add(sdkMessage);
        } catch (_) {}
    }
  }

  @override
  Future<void> send(String message) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    final json = {
      'type': 'user.message',
      'session_id': sessionId,
      'payload': {
        'message': message,
      },
    };
    _process.send(json);
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    final json = {
      'type': 'user.message',
      'session_id': sessionId,
      'payload': {
        'content': content.map((c) => c.toJson()).toList(),
      },
    };
    _process.send(json);
  }

  @override
  Future<void> interrupt() async {
    if (_disposed) return;

    _process.send({
      'type': 'session.interrupt',
      'session_id': sessionId,
    });
  }

  @override
  Future<void> kill() async {
    if (_disposed) return;

    await _process.kill();
    _dispose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    await _process.dispose();
    _dispose();
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _messagesController.close();
    _permissionRequestsController.close();
  }

  @override
  Future<void> setModel(String? model) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    // No-op for testing
  }

  @override
  Future<void> setPermissionMode(String? mode) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    // No-op for testing
  }

  void sendCallbackResponse(CallbackResponse response) {
    if (_disposed) return;
    _process.send(response.toJson());
  }

  /// Send a raw JSON response to the process.
  void sendRawJson(Map<String, dynamic> json) {
    if (_disposed) return;
    _process.send(json);
  }
}

/// Test implementation of CliPermissionRequest.
class _CliPermissionRequestForTesting implements CliPermissionRequest {
  _CliPermissionRequestForTesting({
    required CliSessionForTestingImpl session,
    required this.requestId,
    required this.toolName,
    required this.input,
    required this.toolUseId,
    this.suggestions,
    this.blockedPath,
  }) : _session = session;

  final CliSessionForTestingImpl _session;

  @override
  final String requestId;

  @override
  final String toolName;

  @override
  final Map<String, dynamic> input;

  @override
  final String toolUseId;

  @override
  final List<PermissionSuggestion>? suggestions;

  @override
  final String? blockedPath;

  bool _responded = false;

  @override
  bool get responded => _responded;

  @override
  void allow({
    Map<String, dynamic>? updatedInput,
    List<PermissionSuggestion>? updatedPermissions,
  }) {
    if (_responded) {
      throw StateError('Permission request has already been responded to');
    }
    _responded = true;

    // Send control_response in the format the CLI expects
    // Uses request_id (snake_case) in outer response, toolUseID (capital ID) in inner
    final response = {
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': {
          'behavior': 'allow',
          'updatedInput': updatedInput ?? input,
          'toolUseID': toolUseId,
          if (updatedPermissions != null)
            'updatedPermissions':
                updatedPermissions.map((p) => p.toJson()).toList(),
        },
      },
    };
    _session.sendRawJson(response);
  }

  @override
  void deny([String? message]) {
    if (_responded) {
      throw StateError('Permission request has already been responded to');
    }
    _responded = true;

    final denialMessage = message ?? 'User denied permission';

    // Send control_response in the format the CLI expects
    // Uses request_id (snake_case) in outer response, toolUseID (capital ID) in inner
    final response = {
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': {
          'behavior': 'deny',
          'message': denialMessage,
          'toolUseID': toolUseId,
        },
      },
    };
    _session.sendRawJson(response);
  }
}

/// CliProcess wrapper for testing that takes a pre-created process.
class CliProcessForTesting {
  CliProcessForTesting({required Process process}) : _process = process {
    _setupStreams();
  }

  final Process _process;

  final _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _stderrController = StreamController<String>.broadcast();
  final _stderrBuffer = <String>[];

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  String _partialLine = '';
  bool _disposed = false;

  bool get isRunning => !_disposed;
  Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  Stream<String> get stderr => _stderrController.stream;
  List<String> get stderrBuffer => List.unmodifiable(_stderrBuffer);
  Future<int> get exitCode => _process.exitCode;

  void _setupStreams() {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .listen(_handleStdoutChunk);

    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _stderrBuffer.add(line);
      _stderrController.add(line);
    });
  }

  void _handleStdoutChunk(String chunk) {
    final data = _partialLine + chunk;
    _partialLine = '';

    final lines = data.split('\n');

    if (!chunk.endsWith('\n') && lines.isNotEmpty) {
      _partialLine = lines.removeLast();
    }

    for (final line in lines) {
      if (line.isEmpty) continue;

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        _messagesController.add(json);
      } catch (e) {
        _stderrController.add('[cli_process] Failed to parse JSON: $e');
        _stderrController.add('[cli_process] Line: $line');
      }
    }
  }

  void send(Map<String, dynamic> message) {
    if (_disposed) {
      throw StateError('CliProcess has been disposed');
    }

    var json = jsonEncode(message);
    json = json.replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    _process.stdin.writeln(json);
  }

  Future<void> kill() async {
    if (_disposed) return;
    _process.kill();
    await _process.exitCode;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    _process.kill();

    await _messagesController.close();
    await _stderrController.close();
  }
}
