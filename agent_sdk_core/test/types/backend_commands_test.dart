import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

void main() {
  group('BackendCommand round-trip serialization', () {
    test('SendMessageCommand with all fields', () {
      final cmd = SendMessageCommand(
        sessionId: 'session-1',
        text: 'Fix the bug',
        content: [
          {'type': 'text', 'text': 'Hello'},
          {'type': 'image', 'source': {'type': 'base64', 'data': 'abc'}},
        ],
      );

      final json = cmd.toJson();
      expect(json['command'], 'send_message');
      expect(json['sessionId'], 'session-1');
      expect(json['text'], 'Fix the bug');
      expect(json['content'], isList);

      final restored = BackendCommand.fromJson(json);
      expect(restored, isA<SendMessageCommand>());
      final r = restored as SendMessageCommand;
      expect(r.sessionId, 'session-1');
      expect(r.text, 'Fix the bug');
      expect(r.content, hasLength(2));
      expect(r.content![0]['type'], 'text');
    });

    test('SendMessageCommand with minimal fields', () {
      final cmd = SendMessageCommand(
        sessionId: 'session-1',
        text: 'Hello',
      );

      final json = cmd.toJson();
      expect(json.containsKey('content'), isFalse);

      final restored = BackendCommand.fromJson(json) as SendMessageCommand;
      expect(restored.sessionId, 'session-1');
      expect(restored.text, 'Hello');
      expect(restored.content, isNull);
    });

    test('PermissionResponseCommand with all fields', () {
      final cmd = PermissionResponseCommand(
        requestId: 'req-42',
        allowed: true,
        message: 'Approved',
        updatedInput: {'command': 'ls -la'},
        updatedPermissions: ['Bash'],
        interrupt: false,
      );

      final json = cmd.toJson();
      expect(json['command'], 'permission_response');
      expect(json['requestId'], 'req-42');
      expect(json['allowed'], true);
      expect(json['message'], 'Approved');
      expect(json['updatedInput'], {'command': 'ls -la'});
      expect(json['updatedPermissions'], ['Bash']);
      expect(json['interrupt'], false);

      final restored =
          BackendCommand.fromJson(json) as PermissionResponseCommand;
      expect(restored.requestId, 'req-42');
      expect(restored.allowed, true);
      expect(restored.message, 'Approved');
      expect(restored.updatedInput, {'command': 'ls -la'});
      expect(restored.updatedPermissions, ['Bash']);
      expect(restored.interrupt, false);
    });

    test('PermissionResponseCommand with minimal fields', () {
      final cmd = PermissionResponseCommand(
        requestId: 'req-1',
        allowed: false,
      );

      final json = cmd.toJson();
      expect(json.containsKey('message'), isFalse);
      expect(json.containsKey('updatedInput'), isFalse);
      expect(json.containsKey('updatedPermissions'), isFalse);
      expect(json.containsKey('interrupt'), isFalse);

      final restored =
          BackendCommand.fromJson(json) as PermissionResponseCommand;
      expect(restored.requestId, 'req-1');
      expect(restored.allowed, false);
      expect(restored.message, isNull);
      expect(restored.updatedInput, isNull);
      expect(restored.updatedPermissions, isNull);
      expect(restored.interrupt, isNull);
    });

    test('InterruptCommand', () {
      final cmd = InterruptCommand(sessionId: 'session-abc');

      final json = cmd.toJson();
      expect(json['command'], 'interrupt');
      expect(json['sessionId'], 'session-abc');

      final restored = BackendCommand.fromJson(json) as InterruptCommand;
      expect(restored.sessionId, 'session-abc');
    });

    test('KillCommand', () {
      final cmd = KillCommand(sessionId: 'session-abc');

      final json = cmd.toJson();
      expect(json['command'], 'kill');
      expect(json['sessionId'], 'session-abc');

      final restored = BackendCommand.fromJson(json) as KillCommand;
      expect(restored.sessionId, 'session-abc');
    });

    test('SetModelCommand', () {
      final cmd = SetModelCommand(
        sessionId: 'session-abc',
        model: 'claude-sonnet-4-5',
      );

      final json = cmd.toJson();
      expect(json['command'], 'set_model');
      expect(json['sessionId'], 'session-abc');
      expect(json['model'], 'claude-sonnet-4-5');

      final restored = BackendCommand.fromJson(json) as SetModelCommand;
      expect(restored.sessionId, 'session-abc');
      expect(restored.model, 'claude-sonnet-4-5');
    });

    test('SetPermissionModeCommand', () {
      final cmd = SetPermissionModeCommand(
        sessionId: 'session-abc',
        mode: 'acceptEdits',
      );

      final json = cmd.toJson();
      expect(json['command'], 'set_permission_mode');
      expect(json['sessionId'], 'session-abc');
      expect(json['mode'], 'acceptEdits');

      final restored =
          BackendCommand.fromJson(json) as SetPermissionModeCommand;
      expect(restored.sessionId, 'session-abc');
      expect(restored.mode, 'acceptEdits');
    });

    test('SetReasoningEffortCommand', () {
      final cmd = SetReasoningEffortCommand(
        sessionId: 'session-abc',
        effort: 'high',
      );

      final json = cmd.toJson();
      expect(json['command'], 'set_reasoning_effort');
      expect(json['sessionId'], 'session-abc');
      expect(json['effort'], 'high');

      final restored =
          BackendCommand.fromJson(json) as SetReasoningEffortCommand;
      expect(restored.sessionId, 'session-abc');
      expect(restored.effort, 'high');
    });

    test('CreateSessionCommand with all fields', () {
      final cmd = CreateSessionCommand(
        cwd: '/home/user/project',
        prompt: 'Fix the bug in auth.dart',
        options: {
          'model': 'claude-sonnet-4-5',
          'permissionMode': 'acceptEdits',
        },
        content: [
          {'type': 'text', 'text': 'See attached screenshot'},
          {'type': 'image', 'source': {'type': 'base64', 'data': 'xyz'}},
        ],
      );

      final json = cmd.toJson();
      expect(json['command'], 'create_session');
      expect(json['cwd'], '/home/user/project');
      expect(json['prompt'], 'Fix the bug in auth.dart');
      expect(json['options'], isA<Map>());
      expect(json['content'], isList);

      final restored = BackendCommand.fromJson(json) as CreateSessionCommand;
      expect(restored.cwd, '/home/user/project');
      expect(restored.prompt, 'Fix the bug in auth.dart');
      expect(restored.options!['model'], 'claude-sonnet-4-5');
      expect(restored.content, hasLength(2));
    });

    test('CreateSessionCommand with minimal fields', () {
      final cmd = CreateSessionCommand(
        cwd: '/home/user/project',
        prompt: 'Hello',
      );

      final json = cmd.toJson();
      expect(json.containsKey('options'), isFalse);
      expect(json.containsKey('content'), isFalse);

      final restored = BackendCommand.fromJson(json) as CreateSessionCommand;
      expect(restored.cwd, '/home/user/project');
      expect(restored.prompt, 'Hello');
      expect(restored.options, isNull);
      expect(restored.content, isNull);
    });
  });

  group('BackendCommand.fromJson error handling', () {
    test('throws ArgumentError for unknown command type', () {
      expect(
        () => BackendCommand.fromJson({'command': 'unknown_command'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
