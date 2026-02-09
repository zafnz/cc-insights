/// Unified command model for frontend → backend communication.
///
/// Each command represents an action the frontend wants the backend to perform.
/// Commands serialize with a `command` type discriminator for wire transport.
sealed class BackendCommand {
  const BackendCommand();

  /// Serialize this command to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserialize a command from a JSON map, dispatching on `json['command']`.
  static BackendCommand fromJson(Map<String, dynamic> json) {
    final command = json['command'] as String;
    return switch (command) {
      'send_message' => SendMessageCommand.fromJson(json),
      'permission_response' => PermissionResponseCommand.fromJson(json),
      'interrupt' => InterruptCommand.fromJson(json),
      'kill' => KillCommand.fromJson(json),
      'set_model' => SetModelCommand.fromJson(json),
      'set_permission_mode' => SetPermissionModeCommand.fromJson(json),
      'set_reasoning_effort' => SetReasoningEffortCommand.fromJson(json),
      'create_session' => CreateSessionCommand.fromJson(json),
      _ => throw ArgumentError('Unknown command type: $command'),
    };
  }
}

/// Send a user message to a session.
class SendMessageCommand extends BackendCommand {
  const SendMessageCommand({
    required this.sessionId,
    required this.text,
    this.content,
  });

  final String sessionId;
  final String text;

  /// Optional content blocks (e.g. for images).
  final List<Map<String, dynamic>>? content;

  factory SendMessageCommand.fromJson(Map<String, dynamic> json) {
    return SendMessageCommand(
      sessionId: json['sessionId'] as String,
      text: json['text'] as String,
      content: (json['content'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'send_message',
        'sessionId': sessionId,
        'text': text,
        if (content != null) 'content': content,
      };
}

/// Respond to a permission request.
class PermissionResponseCommand extends BackendCommand {
  const PermissionResponseCommand({
    required this.requestId,
    required this.allowed,
    this.message,
    this.updatedInput,
    this.updatedPermissions,
    this.interrupt,
  });

  final String requestId;
  final bool allowed;
  final String? message;
  final Map<String, dynamic>? updatedInput;
  final List<dynamic>? updatedPermissions;

  /// Whether to interrupt the session after denying (only relevant when
  /// [allowed] is false).
  final bool? interrupt;

  factory PermissionResponseCommand.fromJson(Map<String, dynamic> json) {
    return PermissionResponseCommand(
      requestId: json['requestId'] as String,
      allowed: json['allowed'] as bool,
      message: json['message'] as String?,
      updatedInput: json['updatedInput'] as Map<String, dynamic>?,
      updatedPermissions: json['updatedPermissions'] as List<dynamic>?,
      interrupt: json['interrupt'] as bool?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'permission_response',
        'requestId': requestId,
        'allowed': allowed,
        if (message != null) 'message': message,
        if (updatedInput != null) 'updatedInput': updatedInput,
        if (updatedPermissions != null)
          'updatedPermissions': updatedPermissions,
        if (interrupt != null) 'interrupt': interrupt,
      };
}

/// Interrupt the current turn in a session.
class InterruptCommand extends BackendCommand {
  const InterruptCommand({required this.sessionId});

  final String sessionId;

  factory InterruptCommand.fromJson(Map<String, dynamic> json) {
    return InterruptCommand(
      sessionId: json['sessionId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'interrupt',
        'sessionId': sessionId,
      };
}

/// Kill a session's backend process.
class KillCommand extends BackendCommand {
  const KillCommand({required this.sessionId});

  final String sessionId;

  factory KillCommand.fromJson(Map<String, dynamic> json) {
    return KillCommand(
      sessionId: json['sessionId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'kill',
        'sessionId': sessionId,
      };
}

/// Change the model for a session.
class SetModelCommand extends BackendCommand {
  const SetModelCommand({
    required this.sessionId,
    required this.model,
  });

  final String sessionId;
  final String model;

  factory SetModelCommand.fromJson(Map<String, dynamic> json) {
    return SetModelCommand(
      sessionId: json['sessionId'] as String,
      model: json['model'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'set_model',
        'sessionId': sessionId,
        'model': model,
      };
}

/// Change the permission mode for a session.
class SetPermissionModeCommand extends BackendCommand {
  const SetPermissionModeCommand({
    required this.sessionId,
    required this.mode,
  });

  final String sessionId;
  final String mode;

  factory SetPermissionModeCommand.fromJson(Map<String, dynamic> json) {
    return SetPermissionModeCommand(
      sessionId: json['sessionId'] as String,
      mode: json['mode'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'set_permission_mode',
        'sessionId': sessionId,
        'mode': mode,
      };
}

/// Change the reasoning effort for a session.
class SetReasoningEffortCommand extends BackendCommand {
  const SetReasoningEffortCommand({
    required this.sessionId,
    required this.effort,
  });

  final String sessionId;
  final String effort;

  factory SetReasoningEffortCommand.fromJson(Map<String, dynamic> json) {
    return SetReasoningEffortCommand(
      sessionId: json['sessionId'] as String,
      effort: json['effort'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'set_reasoning_effort',
        'sessionId': sessionId,
        'effort': effort,
      };
}

/// Create a new session.
class CreateSessionCommand extends BackendCommand {
  const CreateSessionCommand({
    required this.cwd,
    required this.prompt,
    this.options,
    this.content,
  });

  final String cwd;
  final String prompt;

  /// Session options as a JSON map (serialized SessionOptions).
  final Map<String, dynamic>? options;

  /// Optional content blocks (e.g. for images).
  final List<Map<String, dynamic>>? content;

  factory CreateSessionCommand.fromJson(Map<String, dynamic> json) {
    return CreateSessionCommand(
      cwd: json['cwd'] as String,
      prompt: json['prompt'] as String,
      options: json['options'] as Map<String, dynamic>?,
      content: (json['content'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'command': 'create_session',
        'cwd': cwd,
        'prompt': prompt,
        if (options != null) 'options': options,
        if (content != null) 'content': content,
      };
}
