import 'dart:async';

import 'permission_suggestion.dart';

/// Permission request from the backend.
class PermissionRequest {
  PermissionRequest({
    required this.id,
    required this.sessionId,
    required this.toolName,
    required this.toolInput,
    this.suggestions,
    this.toolUseId,
    this.agentId,
    this.blockedPath,
    this.decisionReason,
    this.rawJson,
    required Completer<PermissionResponse> completer,
  }) : _completer = completer;

  final String id;
  final String sessionId;
  final String toolName;
  final Map<String, dynamic> toolInput;
  final List<dynamic>? suggestions;
  // Context from SDK for routing and display
  final String? toolUseId;
  final String? agentId;
  final String? blockedPath;
  final String? decisionReason;
  // Original callback request JSON for debugging
  final Map<String, dynamic>? rawJson;
  final Completer<PermissionResponse> _completer;

  bool _responded = false;

  /// Parse the raw suggestions into typed [PermissionSuggestion] objects.
  List<PermissionSuggestion> get parsedSuggestions {
    if (suggestions == null) return [];
    return suggestions!
        .whereType<Map<String, dynamic>>()
        .map((s) => PermissionSuggestion.fromJson(s))
        .toList();
  }

  /// Allow the tool use.
  /// If no updated input is provided, pass through the original tool input.
  void allow({Map<String, dynamic>? updatedInput, List<dynamic>? updatedPermissions}) {
    if (_responded) return;
    _responded = true;
    _completer.complete(PermissionAllowResponse(
      updatedInput: updatedInput ?? toolInput,
      updatedPermissions: updatedPermissions,
      hasSuggestions: suggestions != null && suggestions!.isNotEmpty,
    ));
  }

  /// Deny the tool use.
  void deny(String message, {bool interrupt = false}) {
    if (_responded) return;
    _responded = true;
    _completer.complete(PermissionDenyResponse(
      message: message,
      interrupt: interrupt,
    ));
  }
}

/// Response to a permission request.
sealed class PermissionResponse {
  const PermissionResponse();

  Map<String, dynamic> toJson();
}

/// Allow permission response.
class PermissionAllowResponse extends PermissionResponse {
  const PermissionAllowResponse({
    this.updatedInput,
    this.updatedPermissions,
    this.hasSuggestions = false,
  });

  final Map<String, dynamic>? updatedInput;
  final List<dynamic>? updatedPermissions;
  final bool hasSuggestions;

  @override
  Map<String, dynamic> toJson() => {
        'behavior': 'allow',
        // SDK expects the full tool input when allowing.
        'updated_input': updatedInput ?? {},
        // SDK requires updatedPermissions when there were suggestions
        // Send empty array if suggestions exist but none were accepted
        if (hasSuggestions || updatedPermissions != null)
          'updated_permissions': updatedPermissions ?? [],
      };
}

/// Deny permission response.
class PermissionDenyResponse extends PermissionResponse {
  const PermissionDenyResponse({
    required this.message,
    this.interrupt = false,
  });

  final String message;
  final bool interrupt;

  @override
  Map<String, dynamic> toJson() => {
        'behavior': 'deny',
        'message': message,
        if (interrupt) 'interrupt': true,
      };
}

/// Hook request from the backend.
class HookRequest {
  HookRequest({
    required this.id,
    required this.sessionId,
    required this.event,
    required this.input,
    this.toolUseId,
    required Completer<HookResponse> completer,
  }) : _completer = completer;

  final String id;
  final String sessionId;
  final String event;
  final dynamic input;
  final String? toolUseId;
  final Completer<HookResponse> _completer;

  bool _responded = false;

  /// Respond to the hook.
  void respond(HookResponse response) {
    if (_responded) return;
    _responded = true;
    _completer.complete(response);
  }
}

/// Response to a hook request.
class HookResponse {
  const HookResponse({
    this.continueExecution,
    this.suppressOutput,
    this.stopReason,
    this.decision,
    this.systemMessage,
    this.reason,
    this.hookSpecificOutput,
  });

  final bool? continueExecution;
  final bool? suppressOutput;
  final String? stopReason;
  final HookDecision? decision;
  final String? systemMessage;
  final String? reason;
  final Map<String, dynamic>? hookSpecificOutput;

  Map<String, dynamic> toJson() => {
        if (continueExecution != null) 'continue': continueExecution,
        if (suppressOutput != null) 'suppressOutput': suppressOutput,
        if (stopReason != null) 'stopReason': stopReason,
        if (decision != null) 'decision': decision!.value,
        if (systemMessage != null) 'system_message': systemMessage,
        if (reason != null) 'reason': reason,
        if (hookSpecificOutput != null) 'hook_specific_output': hookSpecificOutput,
      };
}

/// Hook decision.
enum HookDecision {
  approve('approve'),
  block('block');

  const HookDecision(this.value);
  final String value;
}
