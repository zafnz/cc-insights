import 'permission_suggestion.dart';

// ============================================================================
// Outgoing Control Messages (Dart -> CLI)
// ============================================================================

/// A control request sent from Dart to the CLI.
///
/// Used for initialization and other control operations.
class ControlRequest {
  const ControlRequest({
    required this.type,
    required this.id,
    required this.payload,
  });

  /// Message type (e.g., 'session.create').
  final String type;

  /// Unique request ID for correlation.
  final String id;

  /// Request payload.
  final ControlRequestPayload payload;

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'payload': payload.toJson(),
      };
}

/// Base class for control request payloads.
sealed class ControlRequestPayload {
  const ControlRequestPayload();
  Map<String, dynamic> toJson();
}

/// Payload for creating a new session.
class SessionCreatePayload extends ControlRequestPayload {
  const SessionCreatePayload({
    required this.prompt,
    required this.cwd,
    this.options,
  });

  /// Initial prompt to send.
  final String prompt;

  /// Working directory for the session.
  final String cwd;

  /// Optional session options.
  final SessionCreateOptions? options;

  @override
  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'cwd': cwd,
        if (options != null) 'options': options!.toJson(),
      };
}

/// Options for session creation.
class SessionCreateOptions {
  const SessionCreateOptions({
    this.model,
    this.permissionMode,
    this.systemPrompt,
    this.mcpServers,
    this.maxTurns,
    this.maxBudgetUsd,
    this.resume,
  });

  final String? model;
  final String? permissionMode;
  final String? systemPrompt;
  final Map<String, dynamic>? mcpServers;
  final int? maxTurns;
  final double? maxBudgetUsd;
  final String? resume;

  Map<String, dynamic> toJson() => {
        if (model != null) 'model': model,
        if (permissionMode != null) 'permission_mode': permissionMode,
        if (systemPrompt != null) 'system_prompt': systemPrompt,
        if (mcpServers != null) 'mcp_servers': mcpServers,
        if (maxTurns != null) 'max_turns': maxTurns,
        if (maxBudgetUsd != null) 'max_budget_usd': maxBudgetUsd,
        if (resume != null) 'resume': resume,
      };

  factory SessionCreateOptions.fromJson(Map<String, dynamic> json) {
    return SessionCreateOptions(
      model: json['model'] as String?,
      permissionMode: json['permission_mode'] as String?,
      systemPrompt: json['system_prompt'] as String?,
      mcpServers: json['mcp_servers'] as Map<String, dynamic>?,
      maxTurns: json['max_turns'] as int?,
      maxBudgetUsd: (json['max_budget_usd'] as num?)?.toDouble(),
      resume: json['resume'] as String?,
    );
  }
}

// ============================================================================
// Outgoing Callback Response (Dart -> CLI)
// ============================================================================

/// A callback response sent from Dart to the CLI.
///
/// Used to respond to permission requests (can_use_tool callbacks).
class CallbackResponse {
  const CallbackResponse({
    required this.type,
    required this.id,
    required this.sessionId,
    required this.payload,
  });

  /// Message type (always 'callback.response').
  final String type;

  /// Request ID to match with the original callback.request.
  final String id;

  /// Session ID.
  final String sessionId;

  /// Response payload.
  final CallbackResponsePayload payload;

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'session_id': sessionId,
        'payload': payload.toJson(),
      };

  /// Create an 'allow' response for a permission request.
  factory CallbackResponse.allow({
    required String requestId,
    required String sessionId,
    required String toolUseId,
    Map<String, dynamic>? updatedInput,
    List<PermissionSuggestion>? updatedPermissions,
  }) {
    return CallbackResponse(
      type: 'callback.response',
      id: requestId,
      sessionId: sessionId,
      payload: CallbackResponsePayload(
        behavior: 'allow',
        toolUseId: toolUseId,
        updatedInput: updatedInput,
        updatedPermissions: updatedPermissions,
      ),
    );
  }

  /// Create a 'deny' response for a permission request.
  factory CallbackResponse.deny({
    required String requestId,
    required String sessionId,
    required String toolUseId,
    String? message,
  }) {
    return CallbackResponse(
      type: 'callback.response',
      id: requestId,
      sessionId: sessionId,
      payload: CallbackResponsePayload(
        behavior: 'deny',
        toolUseId: toolUseId,
        message: message,
      ),
    );
  }
}

/// Payload for a callback response.
class CallbackResponsePayload {
  const CallbackResponsePayload({
    required this.behavior,
    required this.toolUseId,
    this.updatedInput,
    this.updatedPermissions,
    this.message,
  });

  /// The behavior: 'allow' or 'deny'.
  final String behavior;

  /// The tool use ID from the original request.
  final String toolUseId;

  /// Updated input parameters (for 'allow' with modifications).
  final Map<String, dynamic>? updatedInput;

  /// Permission suggestions to apply (for 'allow').
  final List<PermissionSuggestion>? updatedPermissions;

  /// Denial message (for 'deny').
  final String? message;

  Map<String, dynamic> toJson() {
    // CLI expects camelCase field names with toolUseID (capital ID)
    final json = <String, dynamic>{
      'behavior': behavior,
      'toolUseID': toolUseId,
    };

    if (behavior == 'allow') {
      // CLI requires updatedInput for allow behavior
      json['updatedInput'] = updatedInput ?? {};
      if (updatedPermissions != null) {
        json['updatedPermissions'] =
            updatedPermissions!.map((p) => p.toJson()).toList();
      }
    } else if (behavior == 'deny') {
      // CLI requires message for deny behavior
      json['message'] = message ?? 'User denied permission';
    }

    return json;
  }

  factory CallbackResponsePayload.fromJson(Map<String, dynamic> json) {
    List<PermissionSuggestion>? updatedPermissions;
    if (json['updated_permissions'] != null) {
      updatedPermissions = (json['updated_permissions'] as List)
          .map((p) => PermissionSuggestion.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return CallbackResponsePayload(
      behavior: json['behavior'] as String? ?? 'deny',
      toolUseId: json['tool_use_id'] as String? ?? '',
      updatedInput: json['updated_input'] as Map<String, dynamic>?,
      updatedPermissions: updatedPermissions,
      message: json['message'] as String?,
    );
  }
}

// ============================================================================
// Incoming Callback Request (CLI -> Dart)
// ============================================================================

/// A callback request received from the CLI.
///
/// Used for permission requests (can_use_tool callbacks).
class CallbackRequest {
  const CallbackRequest({
    required this.type,
    required this.id,
    required this.sessionId,
    required this.payload,
  });

  /// Message type (always 'callback.request').
  final String type;

  /// Unique request ID for response correlation.
  final String id;

  /// Session ID.
  final String sessionId;

  /// Request payload.
  final CallbackRequestPayload payload;

  factory CallbackRequest.fromJson(Map<String, dynamic> json) {
    return CallbackRequest(
      type: json['type'] as String? ?? 'callback.request',
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      payload: CallbackRequestPayload.fromJson(
        json['payload'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'session_id': sessionId,
        'payload': payload.toJson(),
      };
}

/// Payload for a callback request.
class CallbackRequestPayload {
  const CallbackRequestPayload({
    required this.callbackType,
    required this.toolName,
    required this.toolInput,
    required this.toolUseId,
    this.suggestions,
    this.blockedPath,
  });

  /// The callback type (e.g., 'can_use_tool').
  final String callbackType;

  /// The name of the tool requesting permission.
  final String toolName;

  /// The input parameters for the tool.
  final Map<String, dynamic> toolInput;

  /// The tool use ID.
  final String toolUseId;

  /// Permission suggestions from the CLI.
  final List<PermissionSuggestion>? suggestions;

  /// The blocked path that triggered the permission request.
  final String? blockedPath;

  factory CallbackRequestPayload.fromJson(Map<String, dynamic> json) {
    List<PermissionSuggestion>? suggestions;
    if (json['suggestions'] != null) {
      suggestions = (json['suggestions'] as List)
          .map((s) => PermissionSuggestion.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return CallbackRequestPayload(
      callbackType: json['callback_type'] as String? ?? '',
      toolName: json['tool_name'] as String? ?? '',
      toolInput: json['tool_input'] as Map<String, dynamic>? ?? {},
      toolUseId: json['tool_use_id'] as String? ?? '',
      suggestions: suggestions,
      blockedPath: json['blocked_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'callback_type': callbackType,
        'tool_name': toolName,
        'tool_input': toolInput,
        'tool_use_id': toolUseId,
        if (suggestions != null)
          'suggestions': suggestions!.map((s) => s.toJson()).toList(),
        if (blockedPath != null) 'blocked_path': blockedPath,
      };
}

// ============================================================================
// Incoming Session Messages (CLI -> Dart)
// ============================================================================

/// A session created response from the CLI.
class SessionCreatedMessage {
  const SessionCreatedMessage({
    required this.type,
    required this.id,
    required this.sessionId,
    required this.payload,
  });

  /// Message type (always 'session.created').
  final String type;

  /// Request ID (matches the session.create request).
  final String id;

  /// The created session ID.
  final String sessionId;

  /// Response payload (usually empty).
  final Map<String, dynamic> payload;

  factory SessionCreatedMessage.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};

    return SessionCreatedMessage(
      type: json['type'] as String? ?? 'session.created',
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      payload: payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'session_id': sessionId,
        'payload': payload,
      };
}

// ============================================================================
// Message Parsing Utilities
// ============================================================================

/// Types of CLI messages.
enum CliMessageType {
  sessionCreated,
  sdkMessage,
  callbackRequest,
  unknown,
}

/// Parse the type of a CLI message.
CliMessageType parseCliMessageType(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  switch (type) {
    case 'session.created':
      return CliMessageType.sessionCreated;
    case 'sdk.message':
      return CliMessageType.sdkMessage;
    case 'callback.request':
      return CliMessageType.callbackRequest;
    default:
      return CliMessageType.unknown;
  }
}


