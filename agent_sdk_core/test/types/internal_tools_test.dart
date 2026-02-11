import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

void main() {
  group('InternalToolDefinition', () {
    test('stores name, description, inputSchema, and handler', () {
      final handler = (Map<String, dynamic> input) async =>
          InternalToolResult.text('success');
      final schema = {
        'type': 'object',
        'properties': {
          'message': {'type': 'string'}
        }
      };

      final tool = InternalToolDefinition(
        name: 'test_tool',
        description: 'A test tool',
        inputSchema: schema,
        handler: handler,
      );

      expect(tool.name, 'test_tool');
      expect(tool.description, 'A test tool');
      expect(tool.inputSchema, schema);
      expect(tool.handler, handler);
    });

    test('handler function can be invoked and returns Future<InternalToolResult>',
        () async {
      var capturedInput = <String, dynamic>{};
      final tool = InternalToolDefinition(
        name: 'echo_tool',
        description: 'Echoes input',
        inputSchema: {},
        handler: (input) async {
          capturedInput = input;
          return InternalToolResult.text('Echo: ${input['message']}');
        },
      );

      final input = {'message': 'hello world'};
      final result = await tool.handler(input);

      expect(capturedInput, input);
      expect(result.content, 'Echo: hello world');
      expect(result.isError, isFalse);
    });

    test('handler can return error result', () async {
      final tool = InternalToolDefinition(
        name: 'failing_tool',
        description: 'Always fails',
        inputSchema: {},
        handler: (input) async {
          return InternalToolResult.error('Tool failed');
        },
      );

      final result = await tool.handler({});

      expect(result.content, 'Tool failed');
      expect(result.isError, isTrue);
    });

    test('can be created with complex inputSchema', () {
      final complexSchema = {
        'type': 'object',
        'required': ['title', 'priority'],
        'properties': {
          'title': {'type': 'string'},
          'description': {'type': 'string'},
          'priority': {
            'type': 'string',
            'enum': ['low', 'medium', 'high']
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'}
          }
        }
      };

      final tool = InternalToolDefinition(
        name: 'create_ticket',
        description: 'Creates a new ticket',
        inputSchema: complexSchema,
        handler: (input) async => InternalToolResult.text('Ticket created'),
      );

      expect(tool.inputSchema, complexSchema);
      expect(tool.inputSchema['required'], ['title', 'priority']);
      expect(tool.inputSchema['properties']['priority']['enum'],
          ['low', 'medium', 'high']);
    });
  });

  group('InternalToolResult', () {
    group('text() factory', () {
      test('creates non-error result with content', () {
        final result = InternalToolResult.text('Success message');

        expect(result.content, 'Success message');
        expect(result.isError, isFalse);
      });

      test('can create result with empty string', () {
        final result = InternalToolResult.text('');

        expect(result.content, isEmpty);
        expect(result.isError, isFalse);
      });

      test('can create result with multiline content', () {
        final content = '''Line 1
Line 2
Line 3''';
        final result = InternalToolResult.text(content);

        expect(result.content, content);
        expect(result.isError, isFalse);
      });

      test('can create result with JSON content', () {
        final jsonContent = '{"status": "ok", "id": 123}';
        final result = InternalToolResult.text(jsonContent);

        expect(result.content, jsonContent);
        expect(result.isError, isFalse);
      });
    });

    group('error() factory', () {
      test('creates error result with isError=true', () {
        final result = InternalToolResult.error('Something went wrong');

        expect(result.content, 'Something went wrong');
        expect(result.isError, isTrue);
      });

      test('can create error with empty message', () {
        final result = InternalToolResult.error('');

        expect(result.content, isEmpty);
        expect(result.isError, isTrue);
      });

      test('can create error with detailed message', () {
        final errorMsg =
            'Failed to create ticket: validation error - title is required';
        final result = InternalToolResult.error(errorMsg);

        expect(result.content, errorMsg);
        expect(result.isError, isTrue);
      });
    });

    test('text and error results have different isError flags', () {
      final success = InternalToolResult.text('OK');
      final failure = InternalToolResult.error('Failed');

      expect(success.isError, isFalse);
      expect(failure.isError, isTrue);
    });
  });

  group('InternalToolDefinition integration', () {
    test('can create tool that returns different results based on input',
        () async {
      final tool = InternalToolDefinition(
        name: 'validate_input',
        description: 'Validates input and returns result',
        inputSchema: {
          'type': 'object',
          'properties': {
            'value': {'type': 'number'}
          }
        },
        handler: (input) async {
          final value = input['value'] as num?;
          if (value == null) {
            return InternalToolResult.error('Missing value');
          }
          if (value < 0) {
            return InternalToolResult.error('Value must be non-negative');
          }
          return InternalToolResult.text('Valid: $value');
        },
      );

      // Test success case
      final successResult = await tool.handler({'value': 42});
      expect(successResult.content, 'Valid: 42');
      expect(successResult.isError, isFalse);

      // Test error cases
      final nullResult = await tool.handler({});
      expect(nullResult.content, 'Missing value');
      expect(nullResult.isError, isTrue);

      final negativeResult = await tool.handler({'value': -5});
      expect(negativeResult.content, 'Value must be non-negative');
      expect(negativeResult.isError, isTrue);
    });

    test('handler can be async and complete asynchronously', () async {
      var completed = false;
      final tool = InternalToolDefinition(
        name: 'async_tool',
        description: 'Completes after delay',
        inputSchema: {},
        handler: (input) async {
          await Future.delayed(Duration.zero);
          completed = true;
          return InternalToolResult.text('Completed');
        },
      );

      expect(completed, isFalse);
      final result = await tool.handler({});
      expect(completed, isTrue);
      expect(result.content, 'Completed');
    });

    test('multiple tools can have different handlers', () async {
      final tool1 = InternalToolDefinition(
        name: 'tool1',
        description: 'Tool 1',
        inputSchema: {},
        handler: (input) async => InternalToolResult.text('Tool 1 result'),
      );

      final tool2 = InternalToolDefinition(
        name: 'tool2',
        description: 'Tool 2',
        inputSchema: {},
        handler: (input) async => InternalToolResult.text('Tool 2 result'),
      );

      final result1 = await tool1.handler({});
      final result2 = await tool2.handler({});

      expect(result1.content, 'Tool 1 result');
      expect(result2.content, 'Tool 2 result');
    });
  });
}
