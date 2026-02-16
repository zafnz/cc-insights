import 'package:cc_insights_v2/models/user_action.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserAction', () {
    test('parses legacy string value as CommandAction', () {
      final action = UserAction.fromJson('Test', './test.sh');

      check(action).isA<CommandAction>();
      final command = action as CommandAction;
      check(command.name).equals('Test');
      check(command.command).equals('./test.sh');
    });

    test('parses start-chat object as StartChatMacro', () {
      final action = UserAction.fromJson('Codex Review', {
        'type': 'start-chat',
        'agent-id': 'codex-default',
        'model': 'o3-mini',
        'instruction': 'Review this branch',
      });

      check(action).isA<StartChatMacro>();
      final macro = action as StartChatMacro;
      check(macro.name).equals('Codex Review');
      check(macro.agentId).equals('codex-default');
      check(macro.model).equals('o3-mini');
      check(macro.instruction).equals('Review this branch');
    });

    test('command serializes to string when configured', () {
      const action = CommandAction(name: 'Test', command: './test.sh');

      final jsonValue = action.toJsonValue();

      check(jsonValue).equals('./test.sh');
    });

    test('empty command serializes to typed command object', () {
      const action = CommandAction(name: 'Prompt', command: '');

      final jsonValue = action.toJsonValue();

      check(
        jsonValue as Map<String, dynamic>,
      ).deepEquals({'type': 'command', 'command': ''});
    });

    test('icons match action type', () {
      const command = CommandAction(name: 'Test', command: './test.sh');
      const macro = StartChatMacro(
        name: 'Review',
        agentId: 'codex-default',
        instruction: 'Review changes',
      );

      check(command.icon).equals(Icons.play_arrow);
      check(macro.icon).equals(Icons.chat_bubble_outline);
    });
  });
}
