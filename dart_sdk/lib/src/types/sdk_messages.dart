import 'content_blocks.dart';
import 'control_messages.dart';
import 'usage.dart';

/// Base class for all SDK messages.
sealed class SDKMessage {
  const SDKMessage({this.rawJson});

  String get type;
  String get sessionId;
  String get uuid;

  /// The original raw JSON from the backend (for debugging/inspection).
  final Map<String, dynamic>? rawJson;

  /// Parse an SDK message from JSON.
  static SDKMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;

    switch (type) {
      case 'system':
        return SDKSystemMessage.fromJson(json);
      case 'assistant':
        return SDKAssistantMessage.fromJson(json);
      case 'user':
        return SDKUserMessage.fromJson(json);
      case 'result':
        return SDKResultMessage.fromJson(json);
      case 'stream_event':
        return SDKStreamEvent.fromJson(json);
      case 'control_request':
        return SDKControlRequest.fromJson(json);
      case 'control_response':
        return SDKControlResponse.fromJson(json);
      default:
        return SDKUnknownMessage.fromJson(json);
    }
  }
}

/// System message - session initialization, status update, or compact boundary.
class SDKSystemMessage extends SDKMessage {
  const SDKSystemMessage({
    required this.subtype,
    required this.uuid,
    required this.sessionId,
    this.apiKeySource,
    this.cwd,
    this.tools,
    this.mcpServers,
    this.model,
    this.permissionMode,
    this.slashCommands,
    this.outputStyle,
    this.compactMetadata,
    this.status,
    super.rawJson,
  });

  factory SDKSystemMessage.fromJson(Map<String, dynamic> json) {
    final subtype = json['subtype'] as String? ?? 'init';

    List<SdkMcpServerInfo>? mcpServers;
    if (json['mcp_servers'] != null) {
      mcpServers = (json['mcp_servers'] as List)
          .map((s) => SdkMcpServerInfo.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    CompactMetadata? compactMetadata;
    if (json['compact_metadata'] != null) {
      compactMetadata =
          CompactMetadata.fromJson(json['compact_metadata'] as Map<String, dynamic>);
    }

    return SDKSystemMessage(
      subtype: subtype,
      uuid: json['uuid'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      apiKeySource: json['apiKeySource'] as String?,
      cwd: json['cwd'] as String?,
      tools: (json['tools'] as List?)?.cast<String>(),
      mcpServers: mcpServers,
      model: json['model'] as String?,
      permissionMode: json['permissionMode'] as String?,
      slashCommands: (json['slash_commands'] as List?)?.cast<String>(),
      outputStyle: json['output_style'] as String?,
      compactMetadata: compactMetadata,
      status: json['status'] as String?,
      rawJson: json,
    );
  }

  @override
  String get type => 'system';

  final String subtype; // 'init', 'status', or 'compact_boundary'
  @override
  final String uuid;
  @override
  final String sessionId;

  // For 'init' subtype:
  final String? apiKeySource;
  final String? cwd;
  final List<String>? tools;
  final List<SdkMcpServerInfo>? mcpServers;
  final String? model;
  final String? permissionMode;
  final List<String>? slashCommands;
  final String? outputStyle;

  // For 'compact_boundary' subtype:
  final CompactMetadata? compactMetadata;

  // For 'status' subtype:
  final String? status; // e.g., 'compacting'
}

/// Assistant response message.
class SDKAssistantMessage extends SDKMessage {
  const SDKAssistantMessage({
    required this.uuid,
    required this.sessionId,
    required this.message,
    this.parentToolUseId,
    super.rawJson,
  });

  factory SDKAssistantMessage.fromJson(Map<String, dynamic> json) {
    return SDKAssistantMessage(
      uuid: json['uuid'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      message: APIAssistantMessage.fromJson(json['message'] as Map<String, dynamic>),
      parentToolUseId: json['parent_tool_use_id'] as String?,
      rawJson: json,
    );
  }

  @override
  String get type => 'assistant';

  @override
  final String uuid;
  @override
  final String sessionId;
  final APIAssistantMessage message;
  final String? parentToolUseId;
}

/// User message (user input or tool results).
class SDKUserMessage extends SDKMessage {
  const SDKUserMessage({
    required this.sessionId,
    required this.message,
    String? uuid,
    this.parentToolUseId,
    this.isSynthetic,
    this.toolUseResult,
    super.rawJson,
  }) : _uuid = uuid;

  factory SDKUserMessage.fromJson(Map<String, dynamic> json) {
    // tool_use_result can be either a Map (structured result) or a String (error message)
    final rawToolUseResult = json['tool_use_result'];
    Map<String, dynamic>? toolUseResult;
    if (rawToolUseResult is Map<String, dynamic>) {
      toolUseResult = rawToolUseResult;
    } else if (rawToolUseResult is String) {
      // Wrap string error in a map for consistency
      toolUseResult = {'error': rawToolUseResult};
    }

    return SDKUserMessage(
      uuid: json['uuid'] as String?,
      sessionId: json['session_id'] as String? ?? '',
      message: APIUserMessage.fromJson(json['message'] as Map<String, dynamic>),
      parentToolUseId: json['parent_tool_use_id'] as String?,
      isSynthetic: json['isSynthetic'] as bool?,
      toolUseResult: toolUseResult,
      rawJson: json,
    );
  }

  @override
  String get type => 'user';

  final String? _uuid;
  @override
  String get uuid => _uuid ?? '';
  @override
  final String sessionId;
  final APIUserMessage message;
  final String? parentToolUseId;
  final bool? isSynthetic;

  /// Structured tool result data (e.g., for TodoWrite with oldTodos/newTodos)
  final Map<String, dynamic>? toolUseResult;
}

/// Result message - turn completion with usage and cost.
class SDKResultMessage extends SDKMessage {
  const SDKResultMessage({
    required this.subtype,
    required this.uuid,
    required this.sessionId,
    required this.durationMs,
    required this.durationApiMs,
    required this.isError,
    required this.numTurns,
    this.totalCostUsd,
    this.usage,
    this.modelUsage,
    this.permissionDenials,
    this.result,
    this.structuredOutput,
    this.errors,
    super.rawJson,
  });

  factory SDKResultMessage.fromJson(Map<String, dynamic> json) {
    Map<String, ModelUsage>? modelUsage;
    if (json['modelUsage'] != null) {
      modelUsage = (json['modelUsage'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, ModelUsage.fromJson(v as Map<String, dynamic>)),
      );
    }

    List<PermissionDenial>? permissionDenials;
    if (json['permission_denials'] != null) {
      permissionDenials = (json['permission_denials'] as List)
          .map((p) => PermissionDenial.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return SDKResultMessage(
      subtype: json['subtype'] as String? ?? 'success',
      uuid: json['uuid'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      durationMs: json['duration_ms'] as int? ?? 0,
      durationApiMs: json['duration_api_ms'] as int? ?? 0,
      isError: json['is_error'] as bool? ?? false,
      numTurns: json['num_turns'] as int? ?? 0,
      totalCostUsd: (json['total_cost_usd'] as num?)?.toDouble(),
      usage: json['usage'] != null
          ? Usage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      modelUsage: modelUsage,
      permissionDenials: permissionDenials,
      result: json['result'] as String?,
      structuredOutput: json['structured_output'],
      errors: (json['errors'] as List?)?.cast<String>(),
      rawJson: json,
    );
  }

  @override
  String get type => 'result';

  final String subtype; // 'success', 'error_max_turns', etc.
  @override
  final String uuid;
  @override
  final String sessionId;
  final int durationMs;
  final int durationApiMs;
  final bool isError;
  final int numTurns;
  final double? totalCostUsd;
  final Usage? usage;
  final Map<String, ModelUsage>? modelUsage;
  final List<PermissionDenial>? permissionDenials;

  // Success fields
  final String? result;
  final dynamic structuredOutput;

  // Error fields
  final List<String>? errors;
}

/// Stream event - partial message for streaming.
class SDKStreamEvent extends SDKMessage {
  const SDKStreamEvent({
    required this.uuid,
    required this.sessionId,
    required this.event,
    this.parentToolUseId,
    super.rawJson,
  });

  factory SDKStreamEvent.fromJson(Map<String, dynamic> json) {
    return SDKStreamEvent(
      uuid: json['uuid'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      event: json['event'] as Map<String, dynamic>? ?? {},
      parentToolUseId: json['parent_tool_use_id'] as String?,
      rawJson: json,
    );
  }

  @override
  String get type => 'stream_event';

  @override
  final String uuid;
  @override
  final String sessionId;
  final Map<String, dynamic> event;
  final String? parentToolUseId;

  /// Get the event type (e.g., 'content_block_delta', 'message_start').
  String get eventType => event['type'] as String? ?? '';

  /// Get text delta from content_block_delta events.
  String? get textDelta {
    if (eventType == 'content_block_delta') {
      final delta = event['delta'] as Map<String, dynamic>?;
      if (delta?['type'] == 'text_delta') {
        return delta?['text'] as String?;
      }
    }
    return null;
  }
}

/// Unknown message type (fallback).
class SDKUnknownMessage extends SDKMessage {
  const SDKUnknownMessage({
    required this.rawType,
    required this.uuid,
    required this.sessionId,
    required this.raw,
  }) : super(rawJson: raw);

  factory SDKUnknownMessage.fromJson(Map<String, dynamic> json) {
    return SDKUnknownMessage(
      rawType: json['type'] as String? ?? 'unknown',
      uuid: json['uuid'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      raw: json,
    );
  }

  final String rawType;
  @override
  String get type => rawType;
  @override
  final String uuid;
  @override
  final String sessionId;
  final Map<String, dynamic> raw;
}

/// Error message from the backend.
class SDKErrorMessage extends SDKMessage {
  const SDKErrorMessage({
    required this.error,
    required this.sessionId,
    this.uuid = '',
    super.rawJson,
  });

  final dynamic error; // BackendError or similar
  @override
  String get type => 'error';
  @override
  final String uuid;
  @override
  final String sessionId;
}

/// Incoming control request (CLI -> Dart) for permissions.
///
/// When the CLI needs permission to use a tool, it sends this message.
/// The Dart side should respond with a [ControlResponse].
class SDKControlRequest extends SDKMessage {
  const SDKControlRequest({
    required this.requestId,
    required this.request,
    required this.sessionId,
    this.uuid = '',
    super.rawJson,
  });

  factory SDKControlRequest.fromJson(Map<String, dynamic> json) {
    return SDKControlRequest(
      requestId: json['request_id'] as String? ?? '',
      request: ControlRequestData.fromJson(
        json['request'] as Map<String, dynamic>? ?? {},
      ),
      sessionId: json['session_id'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      rawJson: json,
    );
  }

  /// The unique request ID for matching responses.
  final String requestId;

  /// The request data containing tool use information.
  final ControlRequestData request;

  @override
  String get type => 'control_request';

  @override
  final String uuid;

  @override
  final String sessionId;

  Map<String, dynamic> toJson() => {
        'type': type,
        'request_id': requestId,
        'request': request.toJson(),
        'session_id': sessionId,
        if (uuid.isNotEmpty) 'uuid': uuid,
      };
}

/// Incoming control response (CLI -> Dart) for initialization.
///
/// Sent by the CLI in response to an initialize request,
/// containing session configuration data.
class SDKControlResponse extends SDKMessage {
  const SDKControlResponse({
    required this.requestId,
    required this.response,
    required this.sessionId,
    this.uuid = '',
    super.rawJson,
  });

  factory SDKControlResponse.fromJson(Map<String, dynamic> json) {
    return SDKControlResponse(
      requestId: json['request_id'] as String? ?? '',
      response: InitializeResponseData.fromJson(
        json['response'] as Map<String, dynamic>? ?? {},
      ),
      sessionId: json['session_id'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      rawJson: json,
    );
  }

  /// The request ID this response corresponds to.
  final String requestId;

  /// The initialization response data.
  final InitializeResponseData response;

  @override
  String get type => 'control_response';

  @override
  final String uuid;

  @override
  final String sessionId;

  Map<String, dynamic> toJson() => {
        'type': type,
        'request_id': requestId,
        'response': response.toJson(),
        'session_id': sessionId,
        if (uuid.isNotEmpty) 'uuid': uuid,
      };
}

/// API assistant message structure.
class APIAssistantMessage {
  const APIAssistantMessage({
    required this.role,
    required this.content,
    this.id,
    this.model,
    this.stopReason,
    this.stopSequence,
    this.usage,
  });

  factory APIAssistantMessage.fromJson(Map<String, dynamic> json) {
    final contentJson = json['content'] as List? ?? [];
    final content = contentJson
        .map((c) => ContentBlock.fromJson(c as Map<String, dynamic>))
        .toList();

    return APIAssistantMessage(
      role: json['role'] as String? ?? 'assistant',
      content: content,
      id: json['id'] as String?,
      model: json['model'] as String?,
      stopReason: json['stop_reason'] as String?,
      stopSequence: json['stop_sequence'] as String?,
      usage: json['usage'] != null
          ? Usage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
    );
  }

  final String role; // always 'assistant'
  final List<ContentBlock> content;
  final String? id;
  final String? model;
  final String? stopReason;
  final String? stopSequence;
  final Usage? usage;
}

/// API user message structure.
class APIUserMessage {
  const APIUserMessage({
    required this.role,
    required this.content,
  });

  factory APIUserMessage.fromJson(Map<String, dynamic> json) {
    final contentJson = json['content'];
    List<ContentBlock> content;

    if (contentJson is String) {
      // Simple string content
      content = [TextBlock(text: contentJson)];
    } else if (contentJson is List) {
      content = contentJson
          .map((c) => ContentBlock.fromJson(c as Map<String, dynamic>))
          .toList();
    } else {
      content = [];
    }

    return APIUserMessage(
      role: json['role'] as String? ?? 'user',
      content: content,
    );
  }

  final String role; // always 'user'
  final List<ContentBlock> content;
}

/// MCP server information (from SDK init message).
class SdkMcpServerInfo {
  const SdkMcpServerInfo({
    required this.name,
    required this.status,
  });

  factory SdkMcpServerInfo.fromJson(Map<String, dynamic> json) {
    return SdkMcpServerInfo(
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  final String name;
  final String status;
}

/// Compact boundary metadata.
class CompactMetadata {
  const CompactMetadata({
    required this.trigger,
    required this.preTokens,
  });

  factory CompactMetadata.fromJson(Map<String, dynamic> json) {
    return CompactMetadata(
      trigger: json['trigger'] as String? ?? 'auto',
      preTokens: json['pre_tokens'] as int? ?? 0,
    );
  }

  final String trigger; // 'manual' or 'auto'
  final int preTokens;
}

/// Permission denial information.
class PermissionDenial {
  const PermissionDenial({
    required this.toolName,
    required this.toolUseId,
    required this.toolInput,
  });

  factory PermissionDenial.fromJson(Map<String, dynamic> json) {
    return PermissionDenial(
      toolName: json['tool_name'] as String? ?? '',
      toolUseId: json['tool_use_id'] as String? ?? '',
      toolInput: json['tool_input'] as Map<String, dynamic>? ?? {},
    );
  }

  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> toolInput;
}
