import 'dart:async';
import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

void main() {
  group('InternalToolRegistry', () {
    late InternalToolRegistry registry;

    setUp(() {
      registry = InternalToolRegistry();
    });

    // Helper to create a test tool
    InternalToolDefinition createTestTool({
      String name = 'test_tool',
      String description = 'A test tool',
      Map<String, dynamic>? inputSchema,
      Future<InternalToolResult> Function(Map<String, dynamic>)?
          handler,
    }) {
      return InternalToolDefinition(
        name: name,
        description: description,
        inputSchema: inputSchema ??
            {
              'type': 'object',
              'properties': {
                'input': {'type': 'string'},
              },
            },
        handler: handler ??
            (args) async => InternalToolResult.text('Success'),
      );
    }

    group('registration', () {
      test('register adds tool to registry', () {
        final tool = createTestTool(name: 'my_tool');
        registry.register(tool);

        expect(registry['my_tool'], same(tool));
      });

      test('unregister removes tool from registry', () {
        final tool = createTestTool(name: 'my_tool');
        registry.register(tool);
        registry.unregister('my_tool');

        expect(registry['my_tool'], isNull);
      });

      test('operator [] returns tool by name', () {
        final tool1 = createTestTool(name: 'tool1');
        final tool2 = createTestTool(name: 'tool2');
        registry.register(tool1);
        registry.register(tool2);

        expect(registry['tool1'], same(tool1));
        expect(registry['tool2'], same(tool2));
      });

      test('operator [] returns null for unknown tool', () {
        expect(registry['unknown_tool'], isNull);
      });

      test('tools getter returns all registered tools', () {
        final tool1 = createTestTool(name: 'tool1');
        final tool2 = createTestTool(name: 'tool2');
        registry.register(tool1);
        registry.register(tool2);

        final tools = registry.tools;
        expect(tools, hasLength(2));
        expect(tools, containsAll([tool1, tool2]));
      });

      test('isEmpty returns true when no tools registered', () {
        expect(registry.isEmpty, isTrue);
        expect(registry.isNotEmpty, isFalse);
      });

      test('isNotEmpty returns true when tools are registered', () {
        registry.register(createTestTool());
        expect(registry.isEmpty, isFalse);
        expect(registry.isNotEmpty, isTrue);
      });
    });

    group('handleMcpMessage - initialize', () {
      test('returns server info and echoes client protocol version', () async {
        final message = {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-11-25',
          },
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'protocolVersion': '2025-11-25',
            'serverInfo': {
              'name': InternalToolRegistry.serverName,
              'version': '1.0.0',
            },
            'capabilities': {
              'tools': {'listChanged': false},
            },
          },
        });
      });

      test('defaults to 2024-11-05 when no version provided', () async {
        final message = {
          'jsonrpc': '2.0',
          'id': 'init-123',
          'method': 'initialize',
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 'init-123',
          'result': {
            'protocolVersion': '2024-11-05',
            'serverInfo': {
              'name': InternalToolRegistry.serverName,
              'version': '1.0.0',
            },
            'capabilities': {
              'tools': {'listChanged': false},
            },
          },
        });
      });
    });

    group('handleMcpMessage - notifications/initialized', () {
      test('returns null for notification', () async {
        final message = {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, isNull);
      });
    });

    group('handleMcpMessage - tools/list', () {
      test('returns empty list when no tools registered', () async {
        final message = {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 2,
          'result': {
            'tools': <dynamic>[],
          },
        });
      });

      test('returns tool definitions in MCP format', () async {
        final tool1 = createTestTool(
          name: 'create_ticket',
          description: 'Create a new ticket',
          inputSchema: {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'description': {'type': 'string'},
            },
            'required': ['title'],
          },
        );

        final tool2 = createTestTool(
          name: 'list_tickets',
          description: 'List all tickets',
          inputSchema: {
            'type': 'object',
            'properties': {},
          },
        );

        registry.register(tool1);
        registry.register(tool2);

        final message = {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/list',
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 3,
          'result': {
            'tools': [
              {
                'name': 'create_ticket',
                'description': 'Create a new ticket',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'title': {'type': 'string'},
                    'description': {'type': 'string'},
                  },
                  'required': ['title'],
                },
              },
              {
                'name': 'list_tickets',
                'description': 'List all tickets',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
            ],
          },
        });
      });
    });

    group('handleMcpMessage - tools/call', () {
      test('calls handler and returns content result for known tool',
          () async {
        final tool = createTestTool(
          name: 'echo_tool',
          handler: (args) async {
            final message = args['message'] as String? ?? 'no message';
            return InternalToolResult.text('Echo: $message');
          },
        );

        registry.register(tool);

        final message = {
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'tools/call',
          'params': {
            'name': 'echo_tool',
            'arguments': {'message': 'hello'},
          },
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 4,
          'result': {
            'content': [
              {'type': 'text', 'text': 'Echo: hello'},
            ],
          },
        });
      });

      test('returns error result for unknown tool', () async {
        final message = {
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'tools/call',
          'params': {
            'name': 'unknown_tool',
            'arguments': {},
          },
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 5,
          'result': {
            'content': [
              {'type': 'text', 'text': 'Unknown tool: unknown_tool'},
            ],
            'isError': true,
          },
        });
      });

      test('returns error result when handler throws', () async {
        final tool = createTestTool(
          name: 'failing_tool',
          handler: (args) async {
            throw Exception('Handler failed');
          },
        );

        registry.register(tool);

        final message = {
          'jsonrpc': '2.0',
          'id': 6,
          'method': 'tools/call',
          'params': {
            'name': 'failing_tool',
            'arguments': {},
          },
        };

        final response = await registry.handleMcpMessage(message);

        expect(response?['jsonrpc'], '2.0');
        expect(response?['id'], 6);
        expect(response?['result'], isA<Map<String, dynamic>>());

        final result = response?['result'] as Map<String, dynamic>;
        expect(result['isError'], isTrue);
        expect(result['content'], isA<List>());

        final content = result['content'] as List;
        expect(content[0]['type'], 'text');
        expect(content[0]['text'], contains('Tool error'));
        expect(content[0]['text'], contains('Handler failed'));
      });

      test('returns error result when handler returns error', () async {
        final tool = createTestTool(
          name: 'error_tool',
          handler: (args) async {
            return InternalToolResult.error('Tool failed: invalid input');
          },
        );

        registry.register(tool);

        final message = {
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'tools/call',
          'params': {
            'name': 'error_tool',
            'arguments': {},
          },
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 7,
          'result': {
            'content': [
              {'type': 'text', 'text': 'Tool failed: invalid input'},
            ],
            'isError': true,
          },
        });
      });

      test('waits for async handler completion', () async {
        final completer = Completer<InternalToolResult>();

        final tool = createTestTool(
          name: 'async_tool',
          handler: (args) => completer.future,
        );

        registry.register(tool);

        final message = {
          'jsonrpc': '2.0',
          'id': 8,
          'method': 'tools/call',
          'params': {
            'name': 'async_tool',
            'arguments': {},
          },
        };

        // Start the message handling
        final responseFuture = registry.handleMcpMessage(message);

        // Give it a moment to ensure it's waiting
        await Future.delayed(Duration(milliseconds: 10));

        // Complete the handler
        completer.complete(InternalToolResult.text('Async complete'));

        // Wait for response
        final response = await responseFuture;

        expect(response, {
          'jsonrpc': '2.0',
          'id': 8,
          'result': {
            'content': [
              {'type': 'text', 'text': 'Async complete'},
            ],
          },
        });
      });

      test('handles missing arguments gracefully', () async {
        final tool = createTestTool(
          name: 'my_tool',
          handler: (args) async {
            return InternalToolResult.text('Args: ${args.isEmpty}');
          },
        );

        registry.register(tool);

        final message = {
          'jsonrpc': '2.0',
          'id': 9,
          'method': 'tools/call',
          'params': {
            'name': 'my_tool',
            // No 'arguments' field
          },
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 9,
          'result': {
            'content': [
              {'type': 'text', 'text': 'Args: true'},
            ],
          },
        });
      });
    });

    group('handleMcpMessage - ping', () {
      test('returns empty result', () async {
        final message = {
          'jsonrpc': '2.0',
          'id': 10,
          'method': 'ping',
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 10,
          'result': {},
        });
      });
    });

    group('handleMcpMessage - unknown method', () {
      test('returns JSON-RPC error -32601', () async {
        final message = {
          'jsonrpc': '2.0',
          'id': 11,
          'method': 'unknown_method',
        };

        final response = await registry.handleMcpMessage(message);

        expect(response, {
          'jsonrpc': '2.0',
          'id': 11,
          'error': {
            'code': -32601,
            'message': 'Unknown method: unknown_method',
          },
        });
      });
    });

    group('handleMcpMessage - id preservation', () {
      test('preserves int id in all responses', () async {
        final messages = [
          {'jsonrpc': '2.0', 'id': 100, 'method': 'initialize'},
          {'jsonrpc': '2.0', 'id': 200, 'method': 'tools/list'},
          {'jsonrpc': '2.0', 'id': 300, 'method': 'ping'},
        ];

        for (final message in messages) {
          final response = await registry.handleMcpMessage(message);
          expect(response?['id'], message['id']);
        }
      });

      test('preserves string id in all responses', () async {
        final messages = [
          {'jsonrpc': '2.0', 'id': 'req-1', 'method': 'initialize'},
          {'jsonrpc': '2.0', 'id': 'req-2', 'method': 'tools/list'},
          {'jsonrpc': '2.0', 'id': 'req-3', 'method': 'ping'},
        ];

        for (final message in messages) {
          final response = await registry.handleMcpMessage(message);
          expect(response?['id'], message['id']);
        }
      });
    });
  });
}
