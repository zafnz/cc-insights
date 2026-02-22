import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Controls when the terminal output window auto-closes after script execution.
enum AutoCloseBehavior {
  /// Always auto-close after script completes (regardless of exit code).
  always,

  /// Auto-close only when the script exits successfully (exit code 0).
  onSuccess,

  /// Never auto-close; user must manually close the terminal tab.
  never;

  /// JSON key used for serialization.
  String toJson() => switch (this) {
        always => 'always',
        onSuccess => 'on-success',
        never => 'never',
      };

  /// Parses from a JSON string value. Defaults to [onSuccess] for unknown values.
  static AutoCloseBehavior fromJson(String? value) => switch (value) {
        'always' => always,
        'on-success' => onSuccess,
        'never' => never,
        _ => onSuccess,
      };

  /// Human-readable label for UI display.
  String get label => switch (this) {
        always => 'Always',
        onSuccess => 'Only on success',
        never => 'Never',
      };
}

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
          autoClose: AutoCloseBehavior.fromJson(
            value['auto-close'] as String?,
          ),
        );
      }
    }

    return CommandAction(name: name, command: '');
  }
}

/// Shell command action.
@immutable
class CommandAction extends UserAction {
  const CommandAction({
    required super.name,
    required this.command,
    this.autoClose = AutoCloseBehavior.onSuccess,
  });

  /// Shell command to execute.
  final String command;

  /// When to auto-close the terminal output window after execution.
  final AutoCloseBehavior autoClose;

  @override
  IconData get icon => Icons.play_arrow;

  @override
  Object toJsonValue() {
    // Use simple string format for backward compat when no extra options are set.
    if (command.trim().isNotEmpty &&
        autoClose == AutoCloseBehavior.onSuccess) {
      return command;
    }
    return {
      'type': 'command',
      'command': command,
      if (autoClose != AutoCloseBehavior.onSuccess)
        'auto-close': autoClose.toJson(),
    };
  }

  CommandAction copyWith({
    String? name,
    String? command,
    AutoCloseBehavior? autoClose,
  }) {
    return CommandAction(
      name: name ?? this.name,
      command: command ?? this.command,
      autoClose: autoClose ?? this.autoClose,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommandAction &&
        other.name == name &&
        other.command == command &&
        other.autoClose == autoClose;
  }

  @override
  int get hashCode => Object.hash(name, command, autoClose);
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
