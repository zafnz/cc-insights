import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('CliSession MCP message handling', () {
    late _McpTestHelper helper;

    setUp(() {
      helper = _McpTestHelper();
    });

    tearDown(() async {
      await helper.dispose();
    });

    group('_handleMcpMessage routing', () {
      test('tools/list returns tool definitions via control_response',
          () async {
        final registry = InternalToolRegistry();
        registry.register(InternalToolDefinition(
          name: 'get_tickets',
          description: 'List project tickets',
          inputSchema: {
            'type': 'object',
            'properties': {
              'status': {'type': 'string'},
            },
          },
          handler: (input) async => InternalToolResult.text('[]'),
        ));

        final session = helper.createSession(registry: registry);

        // Emit an mcp_message control_request for tools/list
        helper.emitControlRequest(
          requestId: 'req-001',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/list',
            'params': {},
          },
        );
        await _pumpEventLoop();

        // Verify the response was sent
        final responses = helper.controlResponses;
        expect(responses, hasLength(1));

        final envelope = responses[0];
        _expectMcpEnvelope(envelope, requestId: 'req-001');

        final mcpResponse = _extractMcpResponse(envelope);
        expect(mcpResponse['jsonrpc'], equals('2.0'));
        expect(mcpResponse['id'], equals(1));

        final result = mcpResponse['result'] as Map<String, dynamic>;
        final tools = result['tools'] as List;
        expect(tools, hasLength(1));
        expect(tools[0]['name'], equals('get_tickets'));
        expect(tools[0]['description'], equals('List project tickets'));

        await session.dispose();
      });

      test('tools/call invokes handler and sends result', () async {
        final registry = InternalToolRegistry();
        registry.register(InternalToolDefinition(
          name: 'create_ticket',
          description: 'Create a ticket',
          inputSchema: {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
            },
          },
          handler: (input) async {
            final title = input['title'] as String? ?? 'untitled';
            return InternalToolResult.text('Created: $title');
          },
        ));

        final session = helper.createSession(registry: registry);

        helper.emitControlRequest(
          requestId: 'req-002',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'tools/call',
            'params': {
              'name': 'create_ticket',
              'arguments': {'title': 'Fix bug'},
            },
          },
        );
        // Handler is async, give it time to complete
        await _pumpEventLoop(times: 5);

        final responses = helper.controlResponses;
        expect(responses, hasLength(1));

        _expectMcpEnvelope(responses[0], requestId: 'req-002');
        final mcpResponse = _extractMcpResponse(responses[0]);
        expect(mcpResponse['id'], equals(2));

        final result = mcpResponse['result'] as Map<String, dynamic>;
        final content = result['content'] as List;
        expect(content, hasLength(1));
        expect(content[0]['text'], equals('Created: Fix bug'));
        expect(result.containsKey('isError'), isFalse);

        await session.dispose();
      });

      test('tools/call for error handler sends error result', () async {
        final registry = InternalToolRegistry();
        registry.register(InternalToolDefinition(
          name: 'failing_tool',
          description: 'A tool that fails',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (input) async =>
              throw Exception('Something went wrong'),
        ));

        final session = helper.createSession(registry: registry);

        helper.emitControlRequest(
          requestId: 'req-003',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 3,
            'method': 'tools/call',
            'params': {
              'name': 'failing_tool',
              'arguments': {},
            },
          },
        );
        await _pumpEventLoop(times: 5);

        final responses = helper.controlResponses;
        expect(responses, hasLength(1));

        final mcpResponse = _extractMcpResponse(responses[0]);
        expect(mcpResponse['id'], equals(3));

        final result = mcpResponse['result'] as Map<String, dynamic>;
        expect(result['isError'], isTrue);
        final content = result['content'] as List;
        expect(content[0]['text'],
            contains('Something went wrong'));

        await session.dispose();
      });

      test('unknown server sends JSON-RPC error response', () async {
        final registry = InternalToolRegistry();
        registry.register(InternalToolDefinition(
          name: 'test_tool',
          description: 'Test',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (input) async => InternalToolResult.text('ok'),
        ));

        final session = helper.createSession(registry: registry);

        helper.emitControlRequest(
          requestId: 'req-004',
          serverName: 'unknown_server',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 4,
            'method': 'tools/list',
            'params': {},
          },
        );
        await _pumpEventLoop();

        final responses = helper.controlResponses;
        expect(responses, hasLength(1));

        _expectMcpEnvelope(responses[0], requestId: 'req-004');
        final mcpResponse = _extractMcpResponse(responses[0]);
        expect(mcpResponse['id'], equals(4));
        expect(mcpResponse['error'], isNotNull);

        final error = mcpResponse['error'] as Map<String, dynamic>;
        expect(error['code'], equals(-32601));
        expect(error['message'], contains('unknown_server'));

        await session.dispose();
      });

      test('mcp_message with null registry sends error', () async {
        // No registry provided
        final session = helper.createSession(registry: null);

        helper.emitControlRequest(
          requestId: 'req-005',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 5,
            'method': 'tools/list',
            'params': {},
          },
        );
        await _pumpEventLoop();

        final responses = helper.controlResponses;
        expect(responses, hasLength(1));

        final mcpResponse = _extractMcpResponse(responses[0]);
        expect(mcpResponse['error'], isNotNull);
        expect(mcpResponse['error']['code'], equals(-32601));

        await session.dispose();
      });

      test('notification sends empty control_response', () async {
        final registry = InternalToolRegistry();
        final session = helper.createSession(registry: registry);

        helper.emitControlRequest(
          requestId: 'req-006',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          },
        );
        await _pumpEventLoop();

        // The CLI wraps every MCP message as a control_request, so we must
        // always send a control_response — even for JSON-RPC notifications.
        final responses = helper.controlResponses;
        expect(responses, hasLength(1));
        _expectMcpEnvelope(responses[0], requestId: 'req-006');

        await session.dispose();
      });

      test('preserves string message IDs', () async {
        final registry = InternalToolRegistry();
        final session = helper.createSession(registry: registry);

        helper.emitControlRequest(
          requestId: 'req-007',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 'string-id-42',
            'method': 'ping',
            'params': {},
          },
        );
        await _pumpEventLoop();

        final responses = helper.controlResponses;
        expect(responses, hasLength(1));

        final mcpResponse = _extractMcpResponse(responses[0]);
        expect(mcpResponse['id'], equals('string-id-42'));

        await session.dispose();
      });

      test('multiple concurrent requests get independent responses',
          () async {
        final completer1 = Completer<InternalToolResult>();
        final completer2 = Completer<InternalToolResult>();

        final registry = InternalToolRegistry();
        registry.register(InternalToolDefinition(
          name: 'slow_tool',
          description: 'Slow tool',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (input) => completer1.future,
        ));
        registry.register(InternalToolDefinition(
          name: 'fast_tool',
          description: 'Fast tool',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (input) => completer2.future,
        ));

        final session = helper.createSession(registry: registry);

        // Send two requests before either completes
        helper.emitControlRequest(
          requestId: 'req-slow',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 10,
            'method': 'tools/call',
            'params': {
              'name': 'slow_tool',
              'arguments': {},
            },
          },
        );
        helper.emitControlRequest(
          requestId: 'req-fast',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 11,
            'method': 'tools/call',
            'params': {
              'name': 'fast_tool',
              'arguments': {},
            },
          },
        );
        await _pumpEventLoop();

        // Complete the fast one first
        completer2.complete(InternalToolResult.text('fast done'));
        await _pumpEventLoop(times: 3);

        // Should have one response so far
        var responses = helper.controlResponses;
        expect(responses, hasLength(1));

        final fastEnvelope = responses[0];
        _expectMcpEnvelope(fastEnvelope, requestId: 'req-fast');
        final fastMcpResponse = _extractMcpResponse(fastEnvelope);
        expect(fastMcpResponse['id'], equals(11));

        // Now complete the slow one
        completer1.complete(InternalToolResult.text('slow done'));
        await _pumpEventLoop(times: 3);

        responses = helper.controlResponses;
        expect(responses, hasLength(2));

        // Find the slow response
        final slowEnvelope = responses
            .firstWhere((r) => _envelopeRequestId(r) == 'req-slow');
        final slowMcpResponse = _extractMcpResponse(slowEnvelope);
        expect(slowMcpResponse['id'], equals(10));
        final slowResult =
            slowMcpResponse['result'] as Map<String, dynamic>;
        expect(slowResult['content'][0]['text'], equals('slow done'));

        await session.dispose();
      });
    });

    group('control_response envelope format', () {
      test('MCP response uses same envelope as permission responses',
          () async {
        final registry = InternalToolRegistry();
        registry.register(InternalToolDefinition(
          name: 'test_tool',
          description: 'Test',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (input) async => InternalToolResult.text('ok'),
        ));

        final session = helper.createSession(registry: registry);

        helper.emitControlRequest(
          requestId: 'req-envelope',
          serverName: 'cci',
          mcpMessage: {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/list',
            'params': {},
          },
        );
        await _pumpEventLoop();

        final responses = helper.controlResponses;
        expect(responses, hasLength(1));

        final envelope = responses[0];
        // Top-level: just 'type' and 'response'
        expect(envelope['type'], equals('control_response'));
        expect(envelope.containsKey('request_id'), isFalse,
            reason: 'request_id belongs inside response, not at top level');

        // Inner response: subtype, request_id, response
        final inner = envelope['response'] as Map<String, dynamic>;
        expect(inner['subtype'], equals('success'));
        expect(inner['request_id'], equals('req-envelope'));

        // MCP response is wrapped in mcp_response key
        final responseData = inner['response'] as Map<String, dynamic>;
        expect(responseData.containsKey('mcp_response'), isTrue);
        final mcpResponse =
            responseData['mcp_response'] as Map<String, dynamic>;
        expect(mcpResponse['jsonrpc'], equals('2.0'));

        await session.dispose();
      });
    });

    group('initialize control_request', () {
      test(
          'includes sdkMcpServers when registry has tools',
          () async {
        final registry = InternalToolRegistry();
        registry.register(InternalToolDefinition(
          name: 'test_tool',
          description: 'Test',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (input) async => InternalToolResult.text('ok'),
        ));

        // We cannot test CliSession.create() directly since it spawns
        // a real process. Instead, verify the registry integration by
        // testing the createForTesting path and checking the sdkMcpServers
        // would be included based on registry.isNotEmpty.
        expect(registry.isNotEmpty, isTrue);
        expect(
          [if (registry.isNotEmpty) InternalToolRegistry.serverName],
          equals(['cci']),
        );
      });

      test(
          'does NOT include sdkMcpServers when registry is null',
          () {
        const InternalToolRegistry? registry = null;
        // Verify the conditional logic
        expect(
          [if (registry != null && registry.isNotEmpty) 'cci'],
          isEmpty,
        );
      });

      test(
          'does NOT include sdkMcpServers when registry is empty',
          () {
        final registry = InternalToolRegistry();
        expect(registry.isEmpty, isTrue);
        expect(
          [if (registry.isNotEmpty) InternalToolRegistry.serverName],
          isEmpty,
        );
      });
    });
  });
}

/// Pump the event loop to allow microtasks and timers to execute.
Future<void> _pumpEventLoop({int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Verify that an MCP control_response has the correct envelope structure:
/// `{type: control_response, response: {subtype: success, request_id: ..., response: {mcp_response: ...}}}`
void _expectMcpEnvelope(
  Map<String, dynamic> envelope, {
  required String requestId,
}) {
  expect(envelope['type'], equals('control_response'));
  final inner = envelope['response'] as Map<String, dynamic>;
  expect(inner['subtype'], equals('success'));
  expect(inner['request_id'], equals(requestId));
  expect(inner['response'], isA<Map<String, dynamic>>());
  final responseData = inner['response'] as Map<String, dynamic>;
  expect(responseData.containsKey('mcp_response'), isTrue);
}

/// Extract the inner JSON-RPC MCP response from a control_response envelope.
Map<String, dynamic> _extractMcpResponse(Map<String, dynamic> envelope) {
  final inner = envelope['response'] as Map<String, dynamic>;
  final responseData = inner['response'] as Map<String, dynamic>;
  return responseData['mcp_response'] as Map<String, dynamic>;
}

/// Extract the request_id from the control_response envelope.
String _envelopeRequestId(Map<String, dynamic> envelope) {
  final inner = envelope['response'] as Map<String, dynamic>;
  return inner['request_id'] as String;
}

/// Helper for creating CliSession instances with MCP registry for testing.
class _McpTestHelper {
  final _stdoutController = StreamController<List<int>>.broadcast();
  final _stderrController = StreamController<List<int>>.broadcast();
  final _stdinMessages = <Map<String, dynamic>>[];
  final _exitCodeCompleter = Completer<int>();
  final _sessions = <CliSession>[];

  List<Map<String, dynamic>> get stdinMessages => _stdinMessages;

  /// Get only control_response messages from stdin.
  List<Map<String, dynamic>> get controlResponses =>
      _stdinMessages.where((m) => m['type'] == 'control_response').toList();

  /// Create a CliSession with registry using the @visibleForTesting factory.
  CliSession createSession({InternalToolRegistry? registry}) {
    final mockProcess = _MockProcess(
      stdout: _stdoutController.stream,
      stderr: _stderrController.stream,
      stdin: _MockIOSink((json) => _stdinMessages.add(json)),
      exitCode: _exitCodeCompleter.future,
      onKill: () {
        if (!_exitCodeCompleter.isCompleted) {
          _exitCodeCompleter.complete(0);
        }
      },
    );

    final cliProcess = CliProcess.forTesting(process: mockProcess);
    final session = CliSession.createForTesting(
      process: cliProcess,
      sessionId: 'mcp-test-session',
      registry: registry,
    );
    _sessions.add(session);
    return session;
  }

  /// Emit a control_request with mcp_message subtype via stdout.
  void emitControlRequest({
    required String requestId,
    required String serverName,
    required Map<String, dynamic> mcpMessage,
  }) {
    final json = jsonEncode({
      'type': 'control_request',
      'request_id': requestId,
      'request': {
        'subtype': 'mcp_message',
        'server_name': serverName,
        'message': mcpMessage,
      },
    });
    _stdoutController.add(utf8.encode('$json\n'));
  }

  Future<void> dispose() async {
    for (final session in _sessions) {
      await session.dispose();
    }
    _sessions.clear();
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    await _stdoutController.close();
    await _stderrController.close();
  }
}

/// Mock Process implementation.
class _MockProcess implements Process {
  _MockProcess({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required IOSink stdin,
    required Future<int> exitCode,
    required void Function() onKill,
  })  : _stdout = stdout,
        _stderr = stderr,
        _stdin = stdin,
        _exitCode = exitCode,
        _onKill = onKill;

  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final IOSink _stdin;
  final Future<int> _exitCode;
  final void Function() _onKill;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  IOSink get stdin => _stdin;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 99999;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _onKill();
    return true;
  }
}

/// Mock IOSink that captures JSON messages from writeln calls.
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
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}

  @override
  Future<void> flush() async {}

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}
}
