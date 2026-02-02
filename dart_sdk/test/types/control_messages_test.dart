import 'dart:convert';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('ControlRequest', () {
    group('toJson()', () {
      test('produces correct JSON for session.create', () {
        // Arrange
        final request = ControlRequest(
          type: 'session.create',
          id: 'req-123',
          payload: SessionCreatePayload(
            prompt: 'Hello, Claude!',
            cwd: '/path/to/project',
          ),
        );

        // Act
        final json = request.toJson();

        // Assert
        expect(json['type'], equals('session.create'));
        expect(json['id'], equals('req-123'));
        expect(json['payload']['prompt'], equals('Hello, Claude!'));
        expect(json['payload']['cwd'], equals('/path/to/project'));
      });

      test('produces correct JSON with all session options', () {
        // Arrange
        final request = ControlRequest(
          type: 'session.create',
          id: 'req-456',
          payload: SessionCreatePayload(
            prompt: 'Test prompt',
            cwd: '/test/cwd',
            options: SessionCreateOptions(
              model: 'sonnet',
              permissionMode: 'default',
              systemPrompt: 'You are a helpful assistant',
              maxTurns: 10,
              maxBudgetUsd: 5.0,
              resume: 'session-abc',
            ),
          ),
        );

        // Act
        final json = request.toJson();

        // Assert
        expect(json['payload']['options']['model'], equals('sonnet'));
        expect(
            json['payload']['options']['permission_mode'], equals('default'));
        expect(json['payload']['options']['system_prompt'],
            equals('You are a helpful assistant'));
        expect(json['payload']['options']['max_turns'], equals(10));
        expect(json['payload']['options']['max_budget_usd'], equals(5.0));
        expect(json['payload']['options']['resume'], equals('session-abc'));
      });

      test('omits null options from JSON', () {
        // Arrange
        final request = ControlRequest(
          type: 'session.create',
          id: 'req-789',
          payload: SessionCreatePayload(
            prompt: 'Test',
            cwd: '/test',
            options: SessionCreateOptions(
              model: 'haiku',
              // All other options are null
            ),
          ),
        );

        // Act
        final json = request.toJson();
        final options = json['payload']['options'] as Map<String, dynamic>;

        // Assert
        expect(options.containsKey('model'), isTrue);
        expect(options.containsKey('permission_mode'), isFalse);
        expect(options.containsKey('system_prompt'), isFalse);
        expect(options.containsKey('max_turns'), isFalse);
      });
    });
  });

  group('SessionCreateOptions', () {
    group('fromJson()', () {
      test('parses all fields correctly', () {
        // Arrange
        final json = {
          'model': 'opus',
          'permission_mode': 'acceptEdits',
          'system_prompt': 'Custom prompt',
          'mcp_servers': {'server1': {}},
          'max_turns': 5,
          'max_budget_usd': 2.5,
          'resume': 'prev-session',
        };

        // Act
        final options = SessionCreateOptions.fromJson(json);

        // Assert
        expect(options.model, equals('opus'));
        expect(options.permissionMode, equals('acceptEdits'));
        expect(options.systemPrompt, equals('Custom prompt'));
        expect(options.mcpServers, isNotNull);
        expect(options.maxTurns, equals(5));
        expect(options.maxBudgetUsd, equals(2.5));
        expect(options.resume, equals('prev-session'));
      });

      test('handles missing fields with null values', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final options = SessionCreateOptions.fromJson(json);

        // Assert
        expect(options.model, isNull);
        expect(options.permissionMode, isNull);
        expect(options.systemPrompt, isNull);
        expect(options.mcpServers, isNull);
        expect(options.maxTurns, isNull);
        expect(options.maxBudgetUsd, isNull);
        expect(options.resume, isNull);
      });
    });

    group('round-trip serialization', () {
      test('preserves all data through toJson/fromJson', () {
        // Arrange
        final original = SessionCreateOptions(
          model: 'sonnet',
          permissionMode: 'default',
          systemPrompt: 'Test system prompt',
          maxTurns: 10,
          maxBudgetUsd: 3.14,
          resume: 'session-xyz',
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = SessionCreateOptions.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        expect(restored.model, equals(original.model));
        expect(restored.permissionMode, equals(original.permissionMode));
        expect(restored.systemPrompt, equals(original.systemPrompt));
        expect(restored.maxTurns, equals(original.maxTurns));
        expect(restored.maxBudgetUsd, equals(original.maxBudgetUsd));
        expect(restored.resume, equals(original.resume));
      });
    });
  });

  group('CallbackRequest', () {
    group('fromJson()', () {
      test('parses can_use_tool request correctly', () {
        // Arrange - matches real CLI output format
        final json = {
          'type': 'callback.request',
          'id': 'e3290e54-0000-0000-0000-000000000007',
          'session_id': 'e3290e54-0000-0000-0000-000000000002',
          'payload': {
            'callback_type': 'can_use_tool',
            'tool_name': 'Bash',
            'tool_input': {
              'command': 'ls -l /tmp',
              'description': 'List files in /tmp',
            },
            'suggestions': [
              {
                'type': 'addRules',
                'rules': [
                  {'toolName': 'Read', 'ruleContent': '//private/tmp/**'}
                ],
                'behavior': 'allow',
                'destination': 'session',
              }
            ],
            'blocked_path': '/private/tmp',
            'tool_use_id': 'toolu_014vCGAxGgw2vETEgDKyXyHA',
          },
        };

        // Act
        final request = CallbackRequest.fromJson(json);

        // Assert
        expect(request.type, equals('callback.request'));
        expect(request.id, equals('e3290e54-0000-0000-0000-000000000007'));
        expect(request.sessionId, equals('e3290e54-0000-0000-0000-000000000002'));
        expect(request.payload.callbackType, equals('can_use_tool'));
        expect(request.payload.toolName, equals('Bash'));
        expect(request.payload.toolInput['command'], equals('ls -l /tmp'));
        expect(
            request.payload.toolUseId, equals('toolu_014vCGAxGgw2vETEgDKyXyHA'));
        expect(request.payload.blockedPath, equals('/private/tmp'));
        expect(request.payload.suggestions, isNotNull);
        expect(request.payload.suggestions!.length, equals(1));
        expect(request.payload.suggestions!.first.type, equals('addRules'));
      });

      test('handles missing optional fields', () {
        // Arrange
        final json = {
          'type': 'callback.request',
          'id': 'req-123',
          'session_id': 'sess-456',
          'payload': {
            'callback_type': 'can_use_tool',
            'tool_name': 'Read',
            'tool_input': {'file_path': '/test.txt'},
            'tool_use_id': 'toolu_123',
          },
        };

        // Act
        final request = CallbackRequest.fromJson(json);

        // Assert
        expect(request.payload.suggestions, isNull);
        expect(request.payload.blockedPath, isNull);
      });

      test('handles completely missing payload gracefully', () {
        // Arrange
        final json = {
          'type': 'callback.request',
          'id': 'req-123',
          'session_id': 'sess-456',
        };

        // Act
        final request = CallbackRequest.fromJson(json);

        // Assert
        expect(request.payload.callbackType, equals(''));
        expect(request.payload.toolName, equals(''));
        expect(request.payload.toolInput, isEmpty);
        expect(request.payload.toolUseId, equals(''));
      });
    });

    group('toJson()', () {
      test('produces correct JSON structure', () {
        // Arrange
        final request = CallbackRequest(
          type: 'callback.request',
          id: 'req-abc',
          sessionId: 'sess-xyz',
          payload: CallbackRequestPayload(
            callbackType: 'can_use_tool',
            toolName: 'Write',
            toolInput: {'content': 'hello'},
            toolUseId: 'toolu_456',
            blockedPath: '/blocked',
          ),
        );

        // Act
        final json = request.toJson();

        // Assert
        expect(json['type'], equals('callback.request'));
        expect(json['id'], equals('req-abc'));
        expect(json['session_id'], equals('sess-xyz'));
        expect(json['payload']['callback_type'], equals('can_use_tool'));
        expect(json['payload']['tool_name'], equals('Write'));
        expect(json['payload']['tool_input']['content'], equals('hello'));
        expect(json['payload']['tool_use_id'], equals('toolu_456'));
        expect(json['payload']['blocked_path'], equals('/blocked'));
      });

      test('omits null optional fields', () {
        // Arrange
        final request = CallbackRequest(
          type: 'callback.request',
          id: 'req-123',
          sessionId: 'sess-456',
          payload: CallbackRequestPayload(
            callbackType: 'can_use_tool',
            toolName: 'Read',
            toolInput: {},
            toolUseId: 'toolu_789',
            // suggestions and blockedPath are null
          ),
        );

        // Act
        final json = request.toJson();
        final payload = json['payload'] as Map<String, dynamic>;

        // Assert
        expect(payload.containsKey('suggestions'), isFalse);
        expect(payload.containsKey('blocked_path'), isFalse);
      });
    });

    group('round-trip serialization', () {
      test('preserves all data through toJson/fromJson', () {
        // Arrange
        final original = CallbackRequest(
          type: 'callback.request',
          id: 'req-roundtrip',
          sessionId: 'sess-roundtrip',
          payload: CallbackRequestPayload(
            callbackType: 'can_use_tool',
            toolName: 'Bash',
            toolInput: {'command': 'echo test'},
            toolUseId: 'toolu_roundtrip',
            blockedPath: '/blocked/path',
          ),
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = CallbackRequest.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        expect(restored.type, equals(original.type));
        expect(restored.id, equals(original.id));
        expect(restored.sessionId, equals(original.sessionId));
        expect(restored.payload.callbackType, equals(original.payload.callbackType));
        expect(restored.payload.toolName, equals(original.payload.toolName));
        expect(restored.payload.toolInput, equals(original.payload.toolInput));
        expect(restored.payload.toolUseId, equals(original.payload.toolUseId));
        expect(restored.payload.blockedPath, equals(original.payload.blockedPath));
      });
    });
  });

  group('CallbackResponse', () {
    group('toJson()', () {
      test('produces correct JSON for allow response', () {
        // Arrange
        final response = CallbackResponse.allow(
          requestId: 'req-123',
          sessionId: 'sess-456',
          toolUseId: 'toolu_abc',
          updatedInput: {'command': 'ls -la'},
        );

        // Act
        final json = response.toJson();

        // Assert - CLI expects toolUseID (capital ID)
        expect(json['type'], equals('callback.response'));
        expect(json['id'], equals('req-123'));
        expect(json['session_id'], equals('sess-456'));
        expect(json['payload']['behavior'], equals('allow'));
        expect(json['payload']['toolUseID'], equals('toolu_abc'));
        expect(json['payload']['updatedInput']['command'], equals('ls -la'));
      });

      test('produces correct JSON for deny response', () {
        // Arrange
        final response = CallbackResponse.deny(
          requestId: 'req-789',
          sessionId: 'sess-012',
          toolUseId: 'toolu_xyz',
          message: 'User denied this operation',
        );

        // Act
        final json = response.toJson();

        // Assert - CLI expects toolUseID (capital ID)
        expect(json['type'], equals('callback.response'));
        expect(json['id'], equals('req-789'));
        expect(json['session_id'], equals('sess-012'));
        expect(json['payload']['behavior'], equals('deny'));
        expect(json['payload']['toolUseID'], equals('toolu_xyz'));
        expect(json['payload']['message'], equals('User denied this operation'));
      });

      test('produces correct JSON matching CLI expected format', () {
        // Arrange - format matching the example JSONL
        final response = CallbackResponse(
          type: 'callback.response',
          id: 'e3290e54-0000-0000-0000-000000000007',
          sessionId: 'e3290e54-0000-0000-0000-000000000002',
          payload: CallbackResponsePayload(
            behavior: 'allow',
            toolUseId: 'toolu_014vCGAxGgw2vETEgDKyXyHA',
            updatedInput: {
              'command': 'ls -l /tmp',
              'description': 'List files in /tmp with detailed info',
            },
            updatedPermissions: null,
          ),
        );

        // Act
        final json = response.toJson();

        // Assert - CLI expects toolUseID (capital ID)
        expect(json['type'], equals('callback.response'));
        expect(json['id'], equals('e3290e54-0000-0000-0000-000000000007'));
        expect(json['session_id'], equals('e3290e54-0000-0000-0000-000000000002'));
        expect(json['payload']['behavior'], equals('allow'));
        expect(json['payload']['toolUseID'],
            equals('toolu_014vCGAxGgw2vETEgDKyXyHA'));
        expect(json['payload']['updatedInput']['command'], equals('ls -l /tmp'));
      });

      test('includes required fields even when not explicitly set', () {
        // Arrange - allow without explicit updatedInput
        final allowResponse = CallbackResponse.allow(
          requestId: 'req-123',
          sessionId: 'sess-456',
          toolUseId: 'toolu_abc',
        );

        // Act
        final allowJson = allowResponse.toJson();
        final allowPayload = allowJson['payload'] as Map<String, dynamic>;

        // Assert - CLI requires updatedInput for allow behavior
        expect(allowPayload.containsKey('updatedInput'), isTrue);
        expect(allowPayload['updatedInput'], equals({}));
        // Optional fields should be omitted
        expect(allowPayload.containsKey('updatedPermissions'), isFalse);
        expect(allowPayload.containsKey('message'), isFalse);

        // Arrange - deny without explicit message
        final denyResponse = CallbackResponse.deny(
          requestId: 'req-456',
          sessionId: 'sess-789',
          toolUseId: 'toolu_def',
        );

        // Act
        final denyJson = denyResponse.toJson();
        final denyPayload = denyJson['payload'] as Map<String, dynamic>;

        // Assert - CLI requires message for deny behavior
        expect(denyPayload.containsKey('message'), isTrue);
        expect(denyPayload['message'], equals('User denied permission'));
        // Optional fields should be omitted
        expect(denyPayload.containsKey('updatedInput'), isFalse);
        expect(denyPayload.containsKey('updatedPermissions'), isFalse);
      });
    });

    group('factory constructors', () {
      test('allow() creates correct response structure', () {
        // Arrange & Act
        final response = CallbackResponse.allow(
          requestId: 'req-test',
          sessionId: 'sess-test',
          toolUseId: 'toolu_test',
        );

        // Assert
        expect(response.type, equals('callback.response'));
        expect(response.id, equals('req-test'));
        expect(response.sessionId, equals('sess-test'));
        expect(response.payload.behavior, equals('allow'));
        expect(response.payload.toolUseId, equals('toolu_test'));
      });

      test('deny() creates correct response structure', () {
        // Arrange & Act
        final response = CallbackResponse.deny(
          requestId: 'req-deny',
          sessionId: 'sess-deny',
          toolUseId: 'toolu_deny',
          message: 'Not allowed',
        );

        // Assert
        expect(response.type, equals('callback.response'));
        expect(response.payload.behavior, equals('deny'));
        expect(response.payload.message, equals('Not allowed'));
      });
    });
  });

  group('CallbackResponsePayload', () {
    group('fromJson()', () {
      test('parses allow response correctly', () {
        // Arrange
        final json = {
          'behavior': 'allow',
          'tool_use_id': 'toolu_123',
          'updated_input': {'key': 'value'},
          'updated_permissions': [],
        };

        // Act
        final payload = CallbackResponsePayload.fromJson(json);

        // Assert
        expect(payload.behavior, equals('allow'));
        expect(payload.toolUseId, equals('toolu_123'));
        expect(payload.updatedInput, isNotNull);
        expect(payload.updatedInput!['key'], equals('value'));
        expect(payload.updatedPermissions, isEmpty);
        expect(payload.message, isNull);
      });

      test('parses deny response correctly', () {
        // Arrange
        final json = {
          'behavior': 'deny',
          'tool_use_id': 'toolu_456',
          'message': 'Operation not allowed',
        };

        // Act
        final payload = CallbackResponsePayload.fromJson(json);

        // Assert
        expect(payload.behavior, equals('deny'));
        expect(payload.toolUseId, equals('toolu_456'));
        expect(payload.message, equals('Operation not allowed'));
        expect(payload.updatedInput, isNull);
        expect(payload.updatedPermissions, isNull);
      });

      test('uses default values for missing fields', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final payload = CallbackResponsePayload.fromJson(json);

        // Assert
        expect(payload.behavior, equals('deny'));
        expect(payload.toolUseId, equals(''));
      });
    });

    group('serialization', () {
      test('toJson uses toolUseID (capital ID) for CLI response format', () {
        // Note: CLI sends requests with snake_case but expects responses
        // with toolUseID (capital ID). toJson() produces the response format.
        final payload = CallbackResponsePayload(
          behavior: 'allow',
          toolUseId: 'toolu_roundtrip',
          updatedInput: {'nested': {'data': true}},
        );

        // Act
        final json = payload.toJson();

        // Assert - toJson should use toolUseID (capital ID)
        expect(json['behavior'], equals('allow'));
        expect(json['toolUseID'], equals('toolu_roundtrip'));
        expect(json['updatedInput'], isNotNull);
        expect((json['updatedInput'] as Map)['nested'], isNotNull);
      });

      test('fromJson uses snake_case for CLI request format', () {
        // Note: fromJson parses incoming CLI requests which use snake_case
        final json = {
          'behavior': 'allow',
          'tool_use_id': 'toolu_test',
          'updated_input': {'key': 'value'},
        };

        // Act
        final payload = CallbackResponsePayload.fromJson(json);

        // Assert
        expect(payload.behavior, equals('allow'));
        expect(payload.toolUseId, equals('toolu_test'));
        expect(payload.updatedInput!['key'], equals('value'));
      });
    });
  });

  group('SessionCreatedMessage', () {
    group('fromJson()', () {
      test('parses session.created message correctly', () {
        // Arrange - matches real CLI output format
        final json = {
          'type': 'session.created',
          'id': 'e3290e54-0000-0000-0000-000000000001',
          'session_id': 'e3290e54-0000-0000-0000-000000000002',
          'payload': {},
        };

        // Act
        final message = SessionCreatedMessage.fromJson(json);

        // Assert
        expect(message.type, equals('session.created'));
        expect(message.id, equals('e3290e54-0000-0000-0000-000000000001'));
        expect(message.sessionId, equals('e3290e54-0000-0000-0000-000000000002'));
        expect(message.payload, isEmpty);
      });

      test('handles missing fields with defaults', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final message = SessionCreatedMessage.fromJson(json);

        // Assert
        expect(message.type, equals('session.created'));
        expect(message.id, equals(''));
        expect(message.sessionId, equals(''));
        expect(message.payload, isEmpty);
      });
    });

    group('toJson()', () {
      test('produces correct JSON structure', () {
        // Arrange
        final message = SessionCreatedMessage(
          type: 'session.created',
          id: 'req-123',
          sessionId: 'sess-456',
          payload: {'extra': 'data'},
        );

        // Act
        final json = message.toJson();

        // Assert
        expect(json['type'], equals('session.created'));
        expect(json['id'], equals('req-123'));
        expect(json['session_id'], equals('sess-456'));
        expect(json['payload']['extra'], equals('data'));
      });
    });

    group('round-trip serialization', () {
      test('preserves all data through toJson/fromJson', () {
        // Arrange
        final original = SessionCreatedMessage(
          type: 'session.created',
          id: 'req-roundtrip',
          sessionId: 'sess-roundtrip',
          payload: {'metadata': {'version': '1.0'}},
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = SessionCreatedMessage.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        expect(restored.type, equals(original.type));
        expect(restored.id, equals(original.id));
        expect(restored.sessionId, equals(original.sessionId));
        expect(restored.payload['metadata'], isNotNull);
      });
    });
  });

  group('parseCliMessageType', () {
    test('returns sessionCreated for session.created type', () {
      final json = {'type': 'session.created'};
      expect(parseCliMessageType(json), equals(CliMessageType.sessionCreated));
    });

    test('returns sdkMessage for sdk.message type', () {
      final json = {'type': 'sdk.message'};
      expect(parseCliMessageType(json), equals(CliMessageType.sdkMessage));
    });

    test('returns callbackRequest for callback.request type', () {
      final json = {'type': 'callback.request'};
      expect(parseCliMessageType(json), equals(CliMessageType.callbackRequest));
    });

    test('returns unknown for unrecognized type', () {
      final json = {'type': 'something.else'};
      expect(parseCliMessageType(json), equals(CliMessageType.unknown));
    });

    test('returns unknown for null type', () {
      final json = <String, dynamic>{};
      expect(parseCliMessageType(json), equals(CliMessageType.unknown));
    });
  });

  group('Integration with real CLI message formats', () {
    test('parses complete callback.request from real CLI output', () {
      // This test uses actual JSON structure from the CLI
      final cliJson = {
        'type': 'callback.request',
        'id': 'e3290e54-0000-0000-0000-000000000007',
        'session_id': 'e3290e54-0000-0000-0000-000000000002',
        'payload': {
          'callback_type': 'can_use_tool',
          'tool_name': 'Bash',
          'tool_input': {
            'command': 'ls -l /tmp',
            'description': 'List files in /tmp with detailed info',
          },
          'suggestions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Read', 'ruleContent': '//private/tmp/**'}
              ],
              'behavior': 'allow',
              'destination': 'session',
            }
          ],
          'blocked_path': '/private/tmp',
          'tool_use_id': 'toolu_014vCGAxGgw2vETEgDKyXyHA',
        },
      };

      // Parse the request
      final request = CallbackRequest.fromJson(cliJson);

      // Verify all fields are parsed correctly
      expect(request.type, equals('callback.request'));
      expect(request.id, equals('e3290e54-0000-0000-0000-000000000007'));
      expect(request.sessionId, equals('e3290e54-0000-0000-0000-000000000002'));
      expect(request.payload.callbackType, equals('can_use_tool'));
      expect(request.payload.toolName, equals('Bash'));
      expect(request.payload.toolInput['command'], equals('ls -l /tmp'));
      expect(request.payload.toolUseId, equals('toolu_014vCGAxGgw2vETEgDKyXyHA'));
      expect(request.payload.blockedPath, equals('/private/tmp'));

      // Verify suggestions are parsed
      expect(request.payload.suggestions, isNotNull);
      expect(request.payload.suggestions!.length, equals(1));
      final suggestion = request.payload.suggestions!.first;
      expect(suggestion.type, equals('addRules'));
      expect(suggestion.behavior, equals('allow'));
      expect(suggestion.destination, equals('session'));
    });

    test('produces callback.response matching expected CLI format', () {
      // Create a response in the format the CLI expects
      final response = CallbackResponse(
        type: 'callback.response',
        id: 'e3290e54-0000-0000-0000-000000000007',
        sessionId: 'e3290e54-0000-0000-0000-000000000002',
        payload: CallbackResponsePayload(
          behavior: 'allow',
          toolUseId: 'toolu_014vCGAxGgw2vETEgDKyXyHA',
          updatedInput: {
            'command': 'ls -l /tmp',
            'description': 'List files in /tmp with detailed info',
          },
          updatedPermissions: null,
        ),
      );

      final json = response.toJson();

      // Verify the structure matches what the CLI expects (toolUseID with capital ID)
      expect(json['type'], equals('callback.response'));
      expect(json['id'], equals('e3290e54-0000-0000-0000-000000000007'));
      expect(json['session_id'], equals('e3290e54-0000-0000-0000-000000000002'));
      expect(json['payload']['behavior'], equals('allow'));
      expect(json['payload']['toolUseID'],
          equals('toolu_014vCGAxGgw2vETEgDKyXyHA'));
      expect(json['payload']['updatedInput']['command'], equals('ls -l /tmp'));

      // The response should be valid JSON that can be sent to CLI
      final jsonString = jsonEncode(json);
      expect(jsonString, contains('callback.response'));
      expect(jsonString, contains('allow'));
      expect(jsonString, contains('updatedInput'));
    });

    test('session.create request matches expected CLI format', () {
      // Create a session.create request
      final request = ControlRequest(
        type: 'session.create',
        id: 'e3290e54-0000-0000-0000-000000000001',
        payload: SessionCreatePayload(
          prompt: 'this is a test. please try to run `ls -l /tmp`',
          cwd: '/tmp/cc-insights/flutter_app_v2',
          options: SessionCreateOptions(
            model: 'sonnet',
            permissionMode: 'default',
          ),
        ),
      );

      final json = request.toJson();

      // Verify the structure
      expect(json['type'], equals('session.create'));
      expect(json['id'], equals('e3290e54-0000-0000-0000-000000000001'));
      expect(json['payload']['prompt'],
          equals('this is a test. please try to run `ls -l /tmp`'));
      expect(json['payload']['cwd'], equals('/tmp/cc-insights/flutter_app_v2'));
      expect(json['payload']['options']['model'], equals('sonnet'));
      expect(json['payload']['options']['permission_mode'], equals('default'));

      // Should be valid JSON
      final jsonString = jsonEncode(json);
      expect(jsonString, isNotEmpty);
    });
  });

  group('SessionCreatePayload', () {
    test('toJson produces correct structure without options', () {
      // Arrange
      final payload = SessionCreatePayload(
        prompt: 'Hello',
        cwd: '/test',
      );

      // Act
      final json = payload.toJson();

      // Assert
      expect(json['prompt'], equals('Hello'));
      expect(json['cwd'], equals('/test'));
      expect(json.containsKey('options'), isFalse);
    });

    test('toJson produces correct structure with options', () {
      // Arrange
      final payload = SessionCreatePayload(
        prompt: 'Hello',
        cwd: '/test',
        options: SessionCreateOptions(model: 'haiku'),
      );

      // Act
      final json = payload.toJson();

      // Assert
      expect(json['prompt'], equals('Hello'));
      expect(json['cwd'], equals('/test'));
      expect(json['options'], isNotNull);
      expect(json['options']['model'], equals('haiku'));
    });
  });

  group('CallbackRequestPayload', () {
    test('toJson includes all required fields', () {
      // Arrange
      final payload = CallbackRequestPayload(
        callbackType: 'can_use_tool',
        toolName: 'Bash',
        toolInput: {'command': 'ls'},
        toolUseId: 'toolu_123',
      );

      // Act
      final json = payload.toJson();

      // Assert
      expect(json['callback_type'], equals('can_use_tool'));
      expect(json['tool_name'], equals('Bash'));
      expect(json['tool_input'], equals({'command': 'ls'}));
      expect(json['tool_use_id'], equals('toolu_123'));
    });

    test('toJson includes optional fields when present', () {
      // Arrange
      final payload = CallbackRequestPayload(
        callbackType: 'can_use_tool',
        toolName: 'Bash',
        toolInput: {'command': 'ls'},
        toolUseId: 'toolu_123',
        blockedPath: '/blocked',
        suggestions: [
          PermissionSuggestion.fromJson({
            'type': 'addRules',
            'rules': [
              {'toolName': 'Read', 'ruleContent': '/test/**'}
            ],
            'behavior': 'allow',
            'destination': 'session',
          }),
        ],
      );

      // Act
      final json = payload.toJson();

      // Assert
      expect(json['blocked_path'], equals('/blocked'));
      expect(json['suggestions'], isNotNull);
      expect(json['suggestions'], hasLength(1));
    });
  });

  group('ControlRequestData (legacy)', () {
    group('fromJson()', () {
      test('parses can_use_tool request data correctly', () {
        // Arrange
        final json = {
          'subtype': 'can_use_tool',
          'tool_name': 'Bash',
          'input': {'command': 'ls -la'},
          'tool_use_id': 'toolu_123',
          'blocked_path': '/private/tmp',
          'permission_suggestions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Read', 'ruleContent': '/tmp/**'}
              ],
              'behavior': 'allow',
              'destination': 'session',
            }
          ],
        };

        // Act
        final data = ControlRequestData.fromJson(json);

        // Assert
        expect(data.subtype, equals('can_use_tool'));
        expect(data.toolName, equals('Bash'));
        expect(data.input['command'], equals('ls -la'));
        expect(data.toolUseId, equals('toolu_123'));
        expect(data.blockedPath, equals('/private/tmp'));
        expect(data.permissionSuggestions, isNotNull);
        expect(data.permissionSuggestions!.length, equals(1));
      });

      test('handles missing optional fields', () {
        // Arrange
        final json = {
          'subtype': 'can_use_tool',
          'tool_name': 'Read',
          'input': {'file_path': '/test.txt'},
          'tool_use_id': 'toolu_456',
        };

        // Act
        final data = ControlRequestData.fromJson(json);

        // Assert
        expect(data.blockedPath, isNull);
        expect(data.permissionSuggestions, isNull);
      });

      test('handles empty JSON with defaults', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final data = ControlRequestData.fromJson(json);

        // Assert
        expect(data.subtype, equals(''));
        expect(data.toolName, equals(''));
        expect(data.input, isEmpty);
        expect(data.toolUseId, equals(''));
      });
    });

    group('toJson()', () {
      test('produces correct JSON structure', () {
        // Arrange
        final data = ControlRequestData(
          subtype: 'can_use_tool',
          toolName: 'Write',
          input: {'content': 'test'},
          toolUseId: 'toolu_789',
          blockedPath: '/blocked',
        );

        // Act
        final json = data.toJson();

        // Assert
        expect(json['subtype'], equals('can_use_tool'));
        expect(json['tool_name'], equals('Write'));
        expect(json['input']['content'], equals('test'));
        expect(json['tool_use_id'], equals('toolu_789'));
        expect(json['blocked_path'], equals('/blocked'));
      });

      test('omits null optional fields', () {
        // Arrange
        final data = ControlRequestData(
          subtype: 'can_use_tool',
          toolName: 'Read',
          input: {},
          toolUseId: 'toolu_abc',
        );

        // Act
        final json = data.toJson();

        // Assert
        expect(json.containsKey('blocked_path'), isFalse);
        expect(json.containsKey('permission_suggestions'), isFalse);
      });
    });

    group('round-trip serialization', () {
      test('preserves all data through toJson/fromJson', () {
        // Arrange
        final original = ControlRequestData(
          subtype: 'can_use_tool',
          toolName: 'Bash',
          input: {'command': 'echo test'},
          toolUseId: 'toolu_roundtrip',
          blockedPath: '/test/path',
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = ControlRequestData.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        expect(restored.subtype, equals(original.subtype));
        expect(restored.toolName, equals(original.toolName));
        expect(restored.input, equals(original.input));
        expect(restored.toolUseId, equals(original.toolUseId));
        expect(restored.blockedPath, equals(original.blockedPath));
      });
    });
  });

  group('InitializeResponseData', () {
    group('fromJson()', () {
      test('parses complete response correctly', () {
        // Arrange
        final json = {
          'commands': [
            {
              'name': 'help',
              'description': 'Show help',
              'argumentHint': '',
            },
            {
              'name': 'compact',
              'description': 'Compact context',
              'argumentHint': '[force]',
            },
          ],
          'output_style': 'streaming',
          'available_output_styles': ['streaming', 'plain'],
          'models': [
            {
              'value': 'sonnet',
              'displayName': 'Claude Sonnet',
              'description': 'Best for most tasks',
            },
          ],
          'account': {
            'email': 'test@example.com',
            'organization': 'Test Org',
          },
        };

        // Act
        final data = InitializeResponseData.fromJson(json);

        // Assert
        expect(data.commands.length, equals(2));
        expect(data.commands.first.name, equals('help'));
        expect(data.outputStyle, equals('streaming'));
        expect(data.availableOutputStyles, contains('plain'));
        expect(data.models.length, equals(1));
        expect(data.models.first.value, equals('sonnet'));
        expect(data.account, isNotNull);
        expect(data.account!.email, equals('test@example.com'));
      });

      test('handles empty lists', () {
        // Arrange
        final json = {
          'commands': [],
          'output_style': 'plain',
          'available_output_styles': [],
          'models': [],
        };

        // Act
        final data = InitializeResponseData.fromJson(json);

        // Assert
        expect(data.commands, isEmpty);
        expect(data.availableOutputStyles, isEmpty);
        expect(data.models, isEmpty);
        expect(data.account, isNull);
      });

      test('handles missing fields with defaults', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final data = InitializeResponseData.fromJson(json);

        // Assert
        expect(data.commands, isEmpty);
        expect(data.outputStyle, equals('plain'));
        expect(data.availableOutputStyles, isEmpty);
        expect(data.models, isEmpty);
        expect(data.account, isNull);
      });
    });

    group('toJson()', () {
      test('produces correct JSON structure', () {
        // Arrange
        final data = InitializeResponseData(
          commands: [
            SlashCommand(
              name: 'test',
              description: 'Test command',
              argumentHint: '[arg]',
            ),
          ],
          outputStyle: 'streaming',
          availableOutputStyles: ['streaming', 'plain'],
          models: [
            ModelInfo(
              value: 'haiku',
              displayName: 'Claude Haiku',
              description: 'Fast model',
            ),
          ],
          account: AccountInfo(email: 'user@test.com'),
        );

        // Act
        final json = data.toJson();

        // Assert
        expect(json['commands'], hasLength(1));
        expect(json['output_style'], equals('streaming'));
        expect(json['available_output_styles'], hasLength(2));
        expect(json['models'], hasLength(1));
        expect(json['account'], isNotNull);
      });

      test('omits null account', () {
        // Arrange
        final data = InitializeResponseData(
          commands: [],
          outputStyle: 'plain',
          availableOutputStyles: [],
          models: [],
        );

        // Act
        final json = data.toJson();

        // Assert
        expect(json.containsKey('account'), isFalse);
      });
    });

    group('round-trip serialization', () {
      test('preserves all data through toJson/fromJson', () {
        // Arrange
        final original = InitializeResponseData(
          commands: [
            SlashCommand(
              name: 'compact',
              description: 'Compact the context',
              argumentHint: '',
            ),
          ],
          outputStyle: 'streaming',
          availableOutputStyles: ['streaming', 'plain', 'json'],
          models: [
            ModelInfo(
              value: 'opus',
              displayName: 'Claude Opus',
              description: 'Most capable',
            ),
          ],
          account: AccountInfo(
            email: 'roundtrip@test.com',
            organization: 'Test Org',
          ),
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = InitializeResponseData.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        expect(restored.commands.length, equals(original.commands.length));
        expect(
            restored.commands.first.name, equals(original.commands.first.name));
        expect(restored.outputStyle, equals(original.outputStyle));
        expect(
            restored.availableOutputStyles, equals(original.availableOutputStyles));
        expect(restored.models.length, equals(original.models.length));
        expect(restored.models.first.value, equals(original.models.first.value));
        expect(restored.account?.email, equals(original.account?.email));
        expect(
            restored.account?.organization, equals(original.account?.organization));
      });
    });
  });
}
