import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Base type for a user-defined action shown in the Actions panel.
@immutable
sealed class UserAction {
  const UserAction({required this.name});

  /// Display name shown on the action button.
  final String name;

  /// Icon used in the Actions panel.
  IconData get icon;

  /// JSON value stored under this action's key in `user-actions`.
  Object toJsonValue();

  /// Parses a user action from a `user-actions` entry.
  ///
  /// Backward compatible behavior:
  /// - String value => [CommandAction]
  /// - Object with `type: "start-chat"` => [StartChatMacro]
  /// - Object with `type: "command"` => [CommandAction]
  factory UserAction.fromJson(String name, Object? value) {
    if (value is String) {
      return CommandAction(name: name, command: value);
    }

    if (value is Map) {
      final type = value['type'] as String?;
      if (type == 'start-chat') {
        final modelRaw = value['model'];
        final model = modelRaw is String && modelRaw.trim().isNotEmpty
            ? modelRaw.trim()
            : null;
        return StartChatMacro(
          name: name,
          agentId: value['agent-id'] as String? ?? 'claude-default',
          model: model,
          instruction: value['instruction'] as String? ?? '',
        );
      }

      if (type == 'command') {
        return CommandAction(
          name: name,
          command: value['command'] as String? ?? '',
        );
      }
    }

    return CommandAction(name: name, command: '');
  }
}

/// Shell command action.
@immutable
class CommandAction extends UserAction {
  const CommandAction({required super.name, required this.command});

  /// Shell command to execute.
  final String command;

  @override
  IconData get icon => Icons.play_arrow;

  @override
  Object toJsonValue() {
    if (command.trim().isNotEmpty) {
      return command;
    }
    return {'type': 'command', 'command': command};
  }

  CommandAction copyWith({String? name, String? command}) {
    return CommandAction(
      name: name ?? this.name,
      command: command ?? this.command,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommandAction &&
        other.name == name &&
        other.command == command;
  }

  @override
  int get hashCode => Object.hash(name, command);
}

/// Macro action that creates and starts a new chat.
@immutable
class StartChatMacro extends UserAction {
  const StartChatMacro({
    required super.name,
    required this.agentId,
    this.model,
    required this.instruction,
  });

  /// Agent config ID used to start the chat.
  final String agentId;

  /// Optional model override. Null uses the agent default model.
  final String? model;

  /// Initial instruction sent as the first user message.
  final String instruction;

  @override
  IconData get icon => Icons.chat_bubble_outline;

  @override
  Object toJsonValue() {
    return {
      'type': 'start-chat',
      'agent-id': agentId,
      if (model != null && model!.trim().isNotEmpty) 'model': model,
      'instruction': instruction,
    };
  }

  StartChatMacro copyWith({
    String? name,
    String? agentId,
    String? model,
    bool clearModel = false,
    String? instruction,
  }) {
    return StartChatMacro(
      name: name ?? this.name,
      agentId: agentId ?? this.agentId,
      model: clearModel ? null : (model ?? this.model),
      instruction: instruction ?? this.instruction,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StartChatMacro &&
        other.name == name &&
        other.agentId == agentId &&
        other.model == model &&
        other.instruction == instruction;
  }

  @override
  int get hashCode => Object.hash(name, agentId, model, instruction);
}
