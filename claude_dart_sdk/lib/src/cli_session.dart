import 'dart:async';

import 'package:meta/meta.dart';

import 'cli_process.dart';
import 'internal_tool_registry.dart';
import 'sdk_logger.dart';
import 'types/backend_provider.dart';
import 'types/content_blocks.dart';
import 'types/insights_events.dart';
import 'types/permission_suggestion.dart';
import 'types/session_options.dart';
import 'types/tool_kind.dart';
import 'types/usage.dart';

/// Diagnostic trace — only prints when [SdkLogger.debugEnabled] is true.
void _t(String tag, String msg) => SdkLogger.instance.trace(tag, msg);

/// A session communicating directly with claude-cli.
///
/// This class manages the full lifecycle of a CLI session:
/// 1. Spawns the CLI process
/// 2. Sends session.create request
/// 3. Waits for session.created response
/// 4. Waits for system init message
/// 5. Routes messages to appropriate streams
class CliSession {
  CliSession._({
    required CliProcess process,
    required this.sessionId,
    Map<String, dynamic>? controlResponseData,
    InternalToolRegistry? registry,
  })  : _process = process,
        _controlResponseData = controlResponseData,
        _registry = registry {
    _setupMessageRouting();
  }

  /// Create a CliSession for testing, bypassing the initialization flow.
  @visibleForTesting
  static CliSession createForTesting({
    required CliProcess process,
    required String sessionId,
    InternalToolRegistry? registry,
  }) {
    return CliSession._(
      process: process,
      sessionId: sessionId,
      registry: registry,
    );
  }

  final CliProcess _process;
  final String sessionId;
  /// Data from the control_response received during initialization.
  /// Merged into SessionInitEvent when system/init arrives.
  final Map<String, dynamic>? _controlResponseData;
  final InternalToolRegistry? _registry;

  int _eventIdCounter = 0;

  /// Per-step usage from the most recent assistant message in the current turn.
  ///
  /// Each assistant message contains `message.usage` with per-API-call token
  /// counts. We stash the last one so that `_convertResult()` can attach it
  /// to [TurnCompleteEvent] via extensions. This gives the frontend the
  /// actual context window size at the end of the turn, rather than the
  /// cumulative usage across all steps.
  Map<String, dynamic>? _lastAssistantUsage;

  /// Generate a unique event ID for this session.
  String _nextEventId() {
    _eventIdCounter++;
    return 'evt-${sessionId.hashCode.toRadixString(16)}-$_eventIdCounter';
  }

  final _eventsController = StreamController<InsightsEvent>.broadcast();
  final _permissionRequestsController =
      StreamController<CliPermissionRequest>.broadcast();

  bool _disposed = false;

  /// Stream of insights events.
  Stream<InsightsEvent> get events => _eventsController.stream;

  /// Stream of permission requests requiring user response.
  Stream<CliPermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  /// Whether the session is active.
  bool get isActive => !_disposed && _process.isRunning;

  /// The CLI process for advanced operations.
  CliProcess get process => _process;

  void _setupMessageRouting() {
    _t('CliSession', 'Setting up message routing for session $sessionId');
    _process.messages.listen(
      _handleMessage,
      onError: (Object error) {
        _t('CliSession', 'Message stream error: $error (session=$sessionId)');
      },
      onDone: () {
        _t('CliSession', 'Message stream done (session=$sessionId, disposed=$_disposed)');
        if (!_disposed) {
          _dispose();
        }
      },
    );
  }

  void _handleMessage(Map<String, dynamic> json) {
    if (_disposed) {
      _t('CliSession', 'WARNING: Message received on disposed session $sessionId');
      return;
    }

    final type = json['type'] as String?;
    final subtype = json['subtype'] as String? ??
        (json['request'] as Map<String, dynamic>?)?['subtype'] as String?;
    _t('CliSession:route', 'type=$type'
        '${subtype != null ? ' subtype=$subtype' : ''}'
        ' (session=$sessionId)');

    switch (type) {
      case 'control_request':
        // Permission request from CLI (can_use_tool)
        final request = json['request'] as Map<String, dynamic>?;
        final subtype = request?['subtype'] as String?;
        final requestId = json['request_id'] as String? ?? '';

        if (subtype == 'can_use_tool') {
          final toolName = request?['tool_name'] as String? ?? '';
          final toolInput = request?['input'] as Map<String, dynamic>? ?? {};
          final toolUseId = request?['tool_use_id'] as String? ?? '';
          final blockedPath = request?['blocked_path'] as String?;

          // Parse suggestions if present
          // CLI sends as 'permission_suggestions' (snake_case)
          List<PermissionSuggestion>? suggestions;
          final suggestionsJson =
              request?['permission_suggestions'] as List? ??
              request?['suggestions'] as List?;
          if (suggestionsJson != null) {
            suggestions = suggestionsJson
                .whereType<Map<String, dynamic>>()
                .map((s) => PermissionSuggestion.fromJson(s))
                .toList();
          }

          SdkLogger.instance.debug(
            'Permission request received',
            sessionId: sessionId,
            data: {'toolName': toolName, 'requestId': requestId},
          );

          final permRequest = CliPermissionRequest._(
            session: this,
            requestId: requestId,
            toolName: toolName,
            input: toolInput,
            toolUseId: toolUseId,
            suggestions: suggestions,
            blockedPath: blockedPath,
          );
          _permissionRequestsController.add(permRequest);
        } else if (subtype == 'mcp_message') {
          _handleMcpMessage(requestId, request!).catchError((Object e) {
            SdkLogger.instance.error(
              'MCP message handling failed: $e',
              sessionId: sessionId,
            );
            _process.send(_mcpControlResponse(requestId, {
              'jsonrpc': '2.0',
              'id': request?['message']?['id'],
              'error': {
                'code': -32603,
                'message': 'Internal error: $e',
              },
            }));
          });
        }

      case 'control_response':
        // Control response - typically handled during initialization
        // Ignore during normal operation
        break;

      case 'system':
      case 'assistant':
      case 'user':
      case 'result':
      case 'stream_event':
        // These message types are handled via InsightsEvents conversion below
        break;

      default:
        // Unknown message type - log and continue
        SdkLogger.instance.debug('Unknown message type ignored: $type',
            sessionId: sessionId, data: {'type': type});
    }

    // Emit InsightsEvents
    try {
      final insightsEvents = _convertToInsightsEvents(json);
      for (final event in insightsEvents) {
        _eventsController.add(event);
      }
    } catch (e) {
      SdkLogger.instance.error(
        'Failed to convert to InsightsEvent',
        sessionId: sessionId,
        data: {'error': e.toString(), 'type': json['type']},
      );
    }
  }

  /// Handle an MCP message routed from the CLI.
  ///
  /// The CLI sends MCP messages as control_requests with subtype
  /// 'mcp_message'. This method extracts the JSON-RPC message, routes it
  /// to the [InternalToolRegistry], and sends the response back as a
  /// control_response.
  Future<void> _handleMcpMessage(
    String requestId,
    Map<String, dynamic> request,
  ) async {
    final serverName = request['server_name'] as String?;
    final message =
        (request['message'] as Map<dynamic, dynamic>?)
            ?.cast<String, dynamic>();

    if (serverName != InternalToolRegistry.serverName ||
        message == null ||
        _registry == null) {
      _process.send(_mcpControlResponse(requestId, {
        'jsonrpc': '2.0',
        'id': message?['id'],
        'error': {
          'code': -32601,
          'message': 'Unknown server: $serverName',
        },
      }));
      return;
    }

    final response = await _registry!.handleMcpMessage(message);

    // Always send a control_response — even for JSON-RPC notifications
    // (which return null from the registry). The CLI's outer protocol
    // wraps every MCP message as a control_request that expects a
    // control_response, regardless of the inner JSON-RPC semantics.
    _process.send(_mcpControlResponse(
      requestId,
      response ?? {'jsonrpc': '2.0', 'result': {}},
    ));
  }

  /// Build a control_response envelope for an MCP message.
  ///
  /// The CLI expects the same envelope format as other control responses:
  /// `{type: control_response, response: {subtype: success, request_id, response: {mcp_response: ...}}}`
  static Map<String, dynamic> _mcpControlResponse(
    String requestId,
    Map<String, dynamic> mcpResponse,
  ) {
    return {
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': {
          'mcp_response': mcpResponse,
        },
      },
    };
  }

  /// Handle an MCP message during session creation (before the session exists).
  ///
  /// The CLI sends MCP discovery messages (initialize, tools/list, etc.)
  /// during the handshake and blocks until they are answered. This static
  /// helper handles them using the raw [CliProcess] and [InternalToolRegistry].
  static Future<void> _handleMcpMessageDuringHandshake(
    CliProcess process,
    Map<String, dynamic> json,
    InternalToolRegistry? registry,
  ) async {
    final requestId = json['request_id'] as String? ?? '';
    final request = json['request'] as Map<String, dynamic>?;
    if (request == null) return;

    final serverName = request['server_name'] as String?;
    final message =
        (request['message'] as Map<dynamic, dynamic>?)
            ?.cast<String, dynamic>();

    if (serverName != InternalToolRegistry.serverName ||
        message == null ||
        registry == null) {
      process.send(_mcpControlResponse(requestId, {
        'jsonrpc': '2.0',
        'id': message?['id'],
        'error': {
          'code': -32601,
          'message': 'Unknown server: $serverName',
        },
      }));
      return;
    }

    try {
      final response = await registry.handleMcpMessage(message);

      // Always send a control_response — see _handleMcpMessage for rationale.
      process.send(_mcpControlResponse(
        requestId,
        response ?? {'jsonrpc': '2.0', 'result': {}},
      ));
      _t('CliSession', 'Step 3: MCP response sent for ${message['method']}');
    } catch (e) {
      _t('CliSession', 'Step 3: MCP handling error: $e');
      process.send(_mcpControlResponse(requestId, {
        'jsonrpc': '2.0',
        'id': message['id'],
        'error': {
          'code': -32603,
          'message': 'Internal error: $e',
        },
      }));
    }
  }

  /// Convert a CLI JSON message into InsightsEvent objects.
  ///
  /// Returns a list because some messages (e.g., assistant with multiple
  /// content blocks) produce multiple events.
  List<InsightsEvent> _convertToInsightsEvents(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final subtype = json['subtype'] as String?;

    return switch (type) {
      'system' => switch (subtype) {
        'init' => [_convertSystemInit(json)],
        'status' => [_convertSystemStatus(json)],
        'compact_boundary' => [_convertCompactBoundary(json)],
        'context_cleared' => [_convertContextCleared(json)],
        _ => <InsightsEvent>[],
      },
      'assistant' => _convertAssistant(json),
      'user' => _convertUser(json),
      'result' => _convertResult(json),
      'control_request' => _convertControlRequest(json),
      'stream_event' => _convertStreamEvent(json),
      _ => <InsightsEvent>[],
    };
  }

  SessionInitEvent _convertSystemInit(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;

    // Parse MCP servers from system/init
    List<McpServerStatus>? mcpServers;
    final mcpList = json['mcp_servers'] as List?;
    if (mcpList != null) {
      mcpServers = mcpList
          .whereType<Map<String, dynamic>>()
          .map((m) => McpServerStatus.fromJson(m))
          .toList();
    }

    // Slash commands: start with simple string list from system/init
    List<SlashCommand>? slashCommands;
    final slashList = json['slash_commands'] as List?;
    if (slashList != null) {
      slashCommands = slashList
          .whereType<String>()
          .map((name) =>
              SlashCommand(name: name, description: '', argumentHint: ''))
          .toList();
    }

    // Merge richer data from control_response
    List<ModelInfo>? availableModels;
    AccountInfo? account;
    if (_controlResponseData != null) {
      // Richer slash commands override the string list
      final commands = _controlResponseData!['commands'] as List?;
      if (commands != null) {
        slashCommands = commands
            .whereType<Map<String, dynamic>>()
            .map((c) => SlashCommand.fromJson(c))
            .toList();
      }

      final models = _controlResponseData!['models'] as List?;
      if (models != null) {
        availableModels = models
            .whereType<Map<String, dynamic>>()
            .map((m) => ModelInfo.fromJson(m))
            .toList();
      }

      final accountJson =
          _controlResponseData!['account'] as Map<String, dynamic>?;
      if (accountJson != null) {
        account = AccountInfo.fromJson(accountJson);
      }
    }

    // Claude-specific extensions
    final extensions = <String, dynamic>{};
    final apiKeySource = json['apiKeySource'] as String?;
    if (apiKeySource != null) extensions['claude.apiKeySource'] = apiKeySource;
    final outputStyle = json['output_style'] as String?;
    if (outputStyle != null) extensions['claude.outputStyle'] = outputStyle;

    return SessionInitEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      extensions: extensions.isNotEmpty ? extensions : null,
      sessionId: sid,
      model: json['model'] as String?,
      cwd: json['cwd'] as String?,
      availableTools: (json['tools'] as List?)?.cast<String>(),
      mcpServers: mcpServers,
      permissionMode: json['permissionMode'] as String?,
      account: account,
      slashCommands: slashCommands,
      availableModels: availableModels,
    );
  }

  SessionStatusEvent _convertSystemStatus(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;
    final statusStr = json['status'] as String?;

    final status = switch (statusStr) {
      'compacting' => SessionStatus.compacting,
      'resuming' => SessionStatus.resuming,
      'interrupted' => SessionStatus.interrupted,
      'ended' => SessionStatus.ended,
      _ => SessionStatus.error,
    };

    return SessionStatusEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      sessionId: sid,
      status: status,
      message: json['message'] as String?,
    );
  }

  ContextCompactionEvent _convertCompactBoundary(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;
    final metadata = json['compact_metadata'] as Map<String, dynamic>?;

    final trigger = switch (metadata?['trigger'] as String?) {
      'manual' => CompactionTrigger.manual,
      _ => CompactionTrigger.auto,
    };

    return ContextCompactionEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      sessionId: sid,
      trigger: trigger,
      preTokens: metadata?['pre_tokens'] as int?,
    );
  }

  ContextCompactionEvent _convertContextCleared(Map<String, dynamic> json) {
    return ContextCompactionEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      sessionId: json['session_id'] as String? ?? sessionId,
      trigger: CompactionTrigger.cleared,
    );
  }

  List<InsightsEvent> _convertAssistant(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;
    final parentToolUseId = json['parent_tool_use_id'] as String?;
    final message = json['message'] as Map<String, dynamic>?;
    final model = message?['model'] as String?;
    final content = message?['content'] as List?;

    // Stash per-step usage from this assistant message. Each assistant message
    // carries usage for a single API call (step). The last one in a turn
    // reflects the actual context window size.
    // Only stash from main agent messages — subagent messages have their own
    // context window and would give misleading values for the main turn.
    final messageUsage = message?['usage'] as Map<String, dynamic>?;
    if (messageUsage != null && parentToolUseId == null) {
      _lastAssistantUsage = messageUsage;
    }

    if (content == null || content.isEmpty) {
      // Even if there's no content, emit usage update if we have usage data.
      // This happens for intermediate assistant messages during tool use.
      if (messageUsage != null) {
        return [
          UsageUpdateEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            sessionId: sid,
            stepUsage: Map<String, dynamic>.from(messageUsage),
            extensions: parentToolUseId != null
                ? {'parent_tool_use_id': parentToolUseId}
                : null,
          ),
        ];
      }
      return [];
    }

    final events = <InsightsEvent>[];

    for (final block in content) {
      if (block is! Map<String, dynamic>) continue;
      final blockType = block['type'] as String?;

      switch (blockType) {
        case 'text':
          events.add(TextEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            sessionId: sid,
            text: block['text'] as String? ?? '',
            kind: TextKind.text,
            parentCallId: parentToolUseId,
            model: model,
          ));

        case 'thinking':
          events.add(TextEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            sessionId: sid,
            text: block['thinking'] as String? ?? '',
            kind: TextKind.thinking,
            parentCallId: parentToolUseId,
            model: model,
          ));

        case 'tool_use':
          final callId = block['id'] as String? ?? _nextEventId();
          final toolName = block['name'] as String? ?? '';
          final input = block['input'] as Map<String, dynamic>? ?? {};

          events.add(ToolInvocationEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            callId: callId,
            parentCallId: parentToolUseId,
            sessionId: sid,
            kind: ToolKind.fromToolName(toolName),
            toolName: toolName,
            input: input,
            locations: _extractLocations(toolName, input),
            model: model,
          ));

          // Task tool → also emit SubagentSpawnEvent
          if (toolName == 'Task') {
            final resume = input['resume'] as String?;
            events.add(SubagentSpawnEvent(
              id: _nextEventId(),
              timestamp: DateTime.now(),
              provider: BackendProvider.claude,
              raw: json,
              sessionId: sid,
              callId: callId,
              agentType:
                  input['subagent_type'] as String? ?? input['name'] as String?,
              description: input['description'] as String?
                  ?? input['prompt'] as String?
                  ?? input['task'] as String?,
              isResume: resume != null,
              resumeAgentId: resume,
            ));
          }
      }
    }

    // Emit intermediate usage update so the frontend can update in real-time.
    if (messageUsage != null) {
      events.add(UsageUpdateEvent(
        id: _nextEventId(),
        timestamp: DateTime.now(),
        provider: BackendProvider.claude,
        sessionId: sid,
        stepUsage: Map<String, dynamic>.from(messageUsage),
        extensions: parentToolUseId != null
            ? {'parent_tool_use_id': parentToolUseId}
            : null,
      ));
    }

    return events;
  }

  /// Extract file/directory locations from tool input parameters.
  List<String>? _extractLocations(String toolName, Map<String, dynamic> input) {
    final locations = <String>[];

    final filePath = input['file_path'] as String?;
    if (filePath != null) locations.add(filePath);

    final path = input['path'] as String?;
    if (path != null) locations.add(path);

    final notebookPath = input['notebook_path'] as String?;
    if (notebookPath != null) locations.add(notebookPath);

    // For Glob, the pattern is the location
    if (toolName == 'Glob') {
      final pattern = input['pattern'] as String?;
      if (pattern != null) locations.add(pattern);
    }

    return locations.isNotEmpty ? locations : null;
  }

  List<InsightsEvent> _convertUser(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;
    final isSynthetic = json['isSynthetic'] as bool? ?? false;
    final isReplay = json['isReplay'] as bool? ?? false;
    final message = json['message'] as Map<String, dynamic>?;
    final content = message?['content'];

    // Handle string content (simple user text)
    if (content is String) {
      return []; // Plain user input — not emitted as InsightsEvent here
    }

    final contentList = content as List?;
    if (contentList == null || contentList.isEmpty) return [];

    final events = <InsightsEvent>[];

    for (final block in contentList) {
      if (block is! Map<String, dynamic>) continue;
      final blockType = block['type'] as String?;

      switch (blockType) {
        case 'tool_result':
          final toolUseId = block['tool_use_id'] as String? ?? _nextEventId();
          final isError = block['is_error'] as bool? ?? false;

          // Prefer structured tool_use_result over content field
          final output = json['tool_use_result'] ?? block['content'];

          events.add(ToolCompletionEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            callId: toolUseId,
            sessionId: sid,
            status:
                isError ? ToolCallStatus.failed : ToolCallStatus.completed,
            output: output,
            isError: isError,
          ));

        case 'text':
          if (isSynthetic || isReplay) {
            final extensions = <String, dynamic>{};
            if (isSynthetic) extensions['claude.isSynthetic'] = true;
            if (isReplay) extensions['claude.isReplay'] = true;

            events.add(TextEvent(
              id: _nextEventId(),
              timestamp: DateTime.now(),
              provider: BackendProvider.claude,
              raw: json,
              extensions: extensions,
              sessionId: sid,
              text: block['text'] as String? ?? '',
              kind: TextKind.text,
            ));
          }
        // Regular user text blocks in non-synthetic messages are not
        // emitted as events (the user's input was already sent by the
        // frontend — we don't echo it back).
      }
    }

    return events;
  }

  List<InsightsEvent> _convertResult(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;

    // Parse aggregate usage
    TokenUsage? usage;
    final usageJson = json['usage'] as Map<String, dynamic>?;
    if (usageJson != null) {
      usage = TokenUsage(
        inputTokens: usageJson['input_tokens'] as int? ?? 0,
        outputTokens: usageJson['output_tokens'] as int? ?? 0,
        cacheReadTokens: usageJson['cache_read_input_tokens'] as int?,
        cacheCreationTokens:
            usageJson['cache_creation_input_tokens'] as int?,
      );
    }

    // Parse per-model usage (camelCase keys on the wire)
    Map<String, ModelTokenUsage>? modelUsage;
    final modelUsageJson = json['modelUsage'] as Map<String, dynamic>?;
    if (modelUsageJson != null) {
      modelUsage = {};
      for (final entry in modelUsageJson.entries) {
        if (entry.value is! Map<String, dynamic>) continue;
        final m = entry.value as Map<String, dynamic>;
        modelUsage[entry.key] = ModelTokenUsage(
          inputTokens: m['inputTokens'] as int? ?? 0,
          outputTokens: m['outputTokens'] as int? ?? 0,
          cacheReadTokens: m['cacheReadInputTokens'] as int?,
          cacheCreationTokens: m['cacheCreationInputTokens'] as int?,
          costUsd: (m['costUSD'] as num?)?.toDouble(),
          contextWindow: m['contextWindow'] as int?,
          webSearchRequests: m['webSearchRequests'] as int?,
        );
      }
    }

    // Parse permission denials
    List<PermissionDenial>? permissionDenials;
    final denialsJson = json['permission_denials'] as List?;
    if (denialsJson != null) {
      permissionDenials = denialsJson
          .whereType<Map<String, dynamic>>()
          .map((d) => PermissionDenial.fromJson(d))
          .toList();
    }

    // Attach the last assistant message's per-step usage as an extension.
    // This is the actual context window size at the end of the turn,
    // as opposed to `usage` which is cumulative across all steps.
    final extensions = <String, dynamic>{};
    if (_lastAssistantUsage != null) {
      extensions['lastStepUsage'] = Map<String, dynamic>.from(_lastAssistantUsage!);
      _lastAssistantUsage = null; // Reset for next turn
    }

    return [
      TurnCompleteEvent(
        id: _nextEventId(),
        timestamp: DateTime.now(),
        provider: BackendProvider.claude,
        raw: json,
        extensions: extensions.isNotEmpty ? extensions : null,
        sessionId: sid,
        isError: json['is_error'] as bool? ?? false,
        subtype: json['subtype'] as String?,
        errors: (json['errors'] as List?)?.cast<String>(),
        result: json['result'] as String?,
        costUsd: (json['total_cost_usd'] as num?)?.toDouble(),
        durationMs: json['duration_ms'] as int?,
        durationApiMs: json['duration_api_ms'] as int?,
        numTurns: json['num_turns'] as int?,
        usage: usage,
        modelUsage: modelUsage,
        permissionDenials: permissionDenials,
      ),
    ];
  }

  List<InsightsEvent> _convertControlRequest(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;
    final request = json['request'] as Map<String, dynamic>?;
    if (request == null) return [];

    // Only convert can_use_tool requests to events
    if (request['subtype'] != 'can_use_tool') return [];

    final toolName = request['tool_name'] as String? ?? '';
    final toolInput = request['input'] as Map<String, dynamic>? ?? {};

    // Parse permission suggestions into data-only form
    List<PermissionSuggestionData>? suggestions;
    final suggestionsJson = request['permission_suggestions'] as List?
        ?? request['suggestions'] as List?;
    if (suggestionsJson != null) {
      suggestions = suggestionsJson
          .whereType<Map<String, dynamic>>()
          .map((s) => PermissionSuggestionData(
                type: s['type'] as String? ?? '',
                toolName: s['tool_name'] as String?,
                directory: s['directory'] as String?,
                mode: s['mode'] as String?,
                description: s['description'] as String? ?? '',
              ))
          .toList();
    }

    return [
      PermissionRequestEvent(
        id: _nextEventId(),
        timestamp: DateTime.now(),
        provider: BackendProvider.claude,
        raw: json,
        sessionId: sid,
        requestId: json['request_id'] as String? ?? _nextEventId(),
        toolName: toolName,
        toolKind: ToolKind.fromToolName(toolName),
        toolInput: toolInput,
        toolUseId: request['tool_use_id'] as String?,
        blockedPath: request['blocked_path'] as String?,
        suggestions: suggestions,
      ),
    ];
  }

  List<InsightsEvent> _convertStreamEvent(Map<String, dynamic> json) {
    final sid = json['session_id'] as String? ?? sessionId;
    final parentToolUseId = json['parent_tool_use_id'] as String?;
    final event = json['event'] as Map<String, dynamic>?;
    if (event == null) return [];

    final eventType = event['type'] as String?;

    StreamDeltaKind? kind;
    String? textDelta;
    String? jsonDelta;
    int? blockIndex;
    String? callId;
    Map<String, dynamic>? extensions;

    switch (eventType) {
      case 'message_start':
        kind = StreamDeltaKind.messageStart;

      case 'content_block_start':
        kind = StreamDeltaKind.blockStart;
        blockIndex = event['index'] as int?;
        final contentBlock = event['content_block'] as Map<String, dynamic>?;
        final blockType = contentBlock?['type'] as String?;
        if (blockType == 'tool_use') {
          callId = contentBlock?['id'] as String?;
          extensions = {
            'tool_name': contentBlock?['name'] as String? ?? '',
          };
        } else if (blockType == 'thinking') {
          extensions = {'block_type': 'thinking'};
        }

      case 'content_block_delta':
        blockIndex = event['index'] as int?;
        final delta = event['delta'] as Map<String, dynamic>?;
        final deltaType = delta?['type'] as String?;

        switch (deltaType) {
          case 'text_delta':
            kind = StreamDeltaKind.text;
            textDelta = delta?['text'] as String?;
          case 'thinking_delta':
            kind = StreamDeltaKind.thinking;
            textDelta = delta?['thinking'] as String?;
          case 'input_json_delta':
            kind = StreamDeltaKind.toolInput;
            jsonDelta = delta?['partial_json'] as String?;
        }

      case 'content_block_stop':
        kind = StreamDeltaKind.blockStop;
        blockIndex = event['index'] as int?;

      case 'message_stop':
        kind = StreamDeltaKind.messageStop;

      case 'message_delta':
        kind = StreamDeltaKind.messageStop;
        final stopReason =
            (event['delta'] as Map<String, dynamic>?)?['stop_reason'] as String?;
        if (stopReason != null) {
          extensions = {'claude.stopReason': stopReason};
        }
    }

    if (kind == null) return [];

    return [
      StreamDeltaEvent(
        id: _nextEventId(),
        timestamp: DateTime.now(),
        provider: BackendProvider.claude,
        raw: json,
        extensions: extensions,
        sessionId: sid,
        parentCallId: parentToolUseId,
        kind: kind,
        textDelta: textDelta,
        jsonDelta: jsonDelta,
        blockIndex: blockIndex,
        callId: callId,
      ),
    ];
  }

  /// Create and initialize a new CLI session.
  ///
  /// This method:
  /// 1. Spawns the CLI process with the given configuration
  /// 2. Sends a session.create request
  /// 3. Waits for session.created response
  /// 4. Waits for the system init message
  /// 5. Returns the initialized session
  static Future<CliSession> create({
    required String cwd,
    required String prompt,
    SessionOptions? options,
    CliProcessConfig? processConfig,
    List<ContentBlock>? content,
    Duration timeout = const Duration(seconds: 60),
    InternalToolRegistry? registry,
  }) async {
    final stopwatch = Stopwatch()..start();

    _t('CliSession', '========== SESSION CREATE START ==========');
    _t('CliSession', 'cwd: $cwd');
    _t('CliSession', 'prompt: ${prompt.length > 80 ? '${prompt.substring(0, 80)}...' : prompt}');
    _t('CliSession', 'model: ${options?.model ?? 'default'}');
    _t('CliSession', 'permissionMode: ${options?.permissionMode?.value ?? 'default'}');
    _t('CliSession', 'resume: ${options?.resume ?? 'none'}');
    _t('CliSession', 'includePartialMessages: ${options?.includePartialMessages ?? false}');
    _t('CliSession', 'timeout: ${timeout.inSeconds}s');
    _t('CliSession', 'hasContent: ${content != null && content.isNotEmpty}');

    // Build CLI process config
    final config = processConfig ??
        CliProcessConfig(
          cwd: cwd,
          model: options?.model,
          permissionMode: options?.permissionMode,
          settingSources: options?.settingSources
              ?.map(SettingSource.fromString)
              .toList(),
          maxTurns: options?.maxTurns,
          maxBudgetUsd: options?.maxBudgetUsd,
          resume: options?.resume,
          includePartialMessages:
              options?.includePartialMessages ?? false,
        );

    // Spawn the CLI process
    SdkLogger.instance.info('Spawning CLI process', data: {
      'cwd': cwd,
      'model': options?.model,
      'permissionMode': options?.permissionMode?.value,
    });
    _t('CliSession', 'Step 0: Spawning CLI process...');
    final process = await CliProcess.spawn(config);
    _t('CliSession', 'Step 0: Process spawned (${stopwatch.elapsedMilliseconds}ms)');

    try {
      // Generate request ID
      final requestId = _generateRequestId();

      // Step 1: Send control_request with initialize subtype
      _t('CliSession', 'Step 1: Sending control_request (initialize), requestId=$requestId');
      final initRequest = {
        'type': 'control_request',
        'request_id': requestId,
        'request': {
          'subtype': 'initialize',
          if (options?.systemPrompt != null)
            'system_prompt': options!.systemPrompt!.toJson(),
          if (options?.includePartialMessages == true)
            'include_partial_messages': true,
          'mcp_servers': options?.mcpServers ?? {},
          if (registry != null && registry.isNotEmpty)
            'sdkMcpServers': [InternalToolRegistry.serverName],
          'agents': {},
          'hooks': {},
        },
      };
      process.send(initRequest);
      _t('CliSession', 'Step 1: control_request sent (${stopwatch.elapsedMilliseconds}ms)');

      // Step 2: Send the initial user message immediately (don't wait for control_response)
      // Use content blocks if provided, otherwise send prompt as plain text
      _t('CliSession', 'Step 2: Sending initial user message...');
      SdkLogger.instance.debug('Sending initial user message');
      final dynamic messageContent = content != null && content.isNotEmpty
          ? content.map((c) => c.toJson()).toList()
          : prompt;
      final userMessage = {
        'type': 'user',
        'message': {
          'role': 'user',
          'content': messageContent,
        },
        'parent_tool_use_id': null,
      };
      process.send(userMessage);
      _t('CliSession', 'Step 2: User message sent (${stopwatch.elapsedMilliseconds}ms)');

      // Step 3: Wait for control_response and system init
      //
      // The CLI may send MCP messages (initialize, tools/list, etc.) during
      // this phase. These MUST be answered inline — the CLI blocks on MCP
      // setup and won't send system/init until it's complete. Other
      // non-handshake messages are buffered for replay after the session's
      // permanent listener is attached.
      //
      // We use a manual subscription + queue instead of `await for` because
      // the broadcast stream drops events while the loop body is suspended
      // in an `await`. The queue ensures no messages are lost while we're
      // handling async MCP requests.
      _t('CliSession', 'Step 3: Waiting for control_response AND system init (timeout=${timeout.inSeconds}s)...');
      String? sessionId;
      bool systemInitReceived = false;
      bool controlResponseReceived = false;
      Map<String, dynamic>? controlResponseData;
      int messagesReceived = 0;
      final bufferedMessages = <Map<String, dynamic>>[];

      // Use a non-broadcast StreamController as a buffer so that messages
      // arriving while we `await` MCP handlers are queued, not dropped.
      final inbox = StreamController<Map<String, dynamic>>();
      final sub = process.messages.listen(
        inbox.add,
        onError: inbox.addError,
        onDone: inbox.close,
      );

      try {
        await for (final json in inbox.stream.timeout(timeout)) {
          messagesReceived++;
          final type = json['type'] as String?;
          final subtype = json['subtype'] as String? ??
              (json['request'] as Map<String, dynamic>?)?['subtype']
                  as String?;
          _t('CliSession', 'Step 3: Message #$messagesReceived: type=$type'
              '${subtype != null ? ' subtype=$subtype' : ''}'
              ' (${stopwatch.elapsedMilliseconds}ms)');

          if (type == 'control_response') {
            controlResponseReceived = true;
            controlResponseData =
                json['response'] as Map<String, dynamic>?;
            _t('CliSession', 'Step 3: control_response received');
            SdkLogger.instance.debug('Received control_response');
          } else if (type == 'system') {
            final sysSubtype = json['subtype'] as String?;
            if (sysSubtype == 'init') {
              sessionId = json['session_id'] as String?;
              systemInitReceived = true;
              _t('CliSession',
                  'Step 3: system init received, sessionId=$sessionId');
              SdkLogger.instance.debug('Received system init',
                  sessionId: sessionId);
            } else {
              _t('CliSession', 'Step 3: system/$sysSubtype buffered');
              bufferedMessages.add(json);
            }
          } else if (type == 'control_request' &&
              subtype == 'mcp_message') {
            // MCP messages arrive during init — the CLI blocks until
            // these are answered. The inbox buffers subsequent messages
            // so nothing is lost during the await.
            await _handleMcpMessageDuringHandshake(
                process, json, registry);
          } else {
            _t('CliSession', 'Step 3: Buffering $type message');
            bufferedMessages.add(json);
          }

          // Check if we have everything we need
          if (controlResponseReceived &&
              sessionId != null &&
              systemInitReceived) {
            _t('CliSession', 'Step 3: Both handshake messages received!');
            break;
          }

          // Log what we're still waiting for
          final waiting = <String>[];
          if (!controlResponseReceived) waiting.add('control_response');
          if (sessionId == null) waiting.add('system init');
          _t('CliSession',
              'Step 3: Still waiting for: ${waiting.join(', ')}');
        }
      } finally {
        await sub.cancel();
        await inbox.close();
      }

      if (!controlResponseReceived) {
        _t('CliSession', 'TIMEOUT: No control_response after ${stopwatch.elapsedMilliseconds}ms ($messagesReceived messages received)');
        SdkLogger.instance.error('Session creation timed out: no control_response');
        throw StateError('Session creation timed out: no control_response');
      }
      if (sessionId == null || !systemInitReceived) {
        _t('CliSession', 'TIMEOUT: No system init after ${stopwatch.elapsedMilliseconds}ms ($messagesReceived messages received)');
        SdkLogger.instance.error('Session creation timed out: no system init');
        throw StateError('Session creation timed out: no system init');
      }

      // Tag the process so trace log entries include the session ID
      process.sessionId = sessionId;

      _t('CliSession', '========== SESSION CREATED (${stopwatch.elapsedMilliseconds}ms) ==========');
      _t('CliSession', 'sessionId: $sessionId');
      if (bufferedMessages.isNotEmpty) {
        _t('CliSession', 'Replaying ${bufferedMessages.length} buffered messages');
      }
      SdkLogger.instance.info('Session created successfully',
          sessionId: sessionId);

      final session = CliSession._(
        process: process,
        sessionId: sessionId,
        controlResponseData: controlResponseData,
        registry: registry,
      );

      // Replay any messages that arrived during the handshake
      for (final msg in bufferedMessages) {
        session._handleMessage(msg);
      }

      return session;
    } catch (e) {
      // Clean up on error
      _t('CliSession', '========== SESSION CREATE FAILED (${stopwatch.elapsedMilliseconds}ms) ==========');
      _t('CliSession', 'Error: $e');
      SdkLogger.instance.error('Session creation failed: $e');
      await process.dispose();
      rethrow;
    }
  }

  /// Send a user message in the correct protocol format.
  void _sendUserMessage(String message) {
    final json = {
      'type': 'user',
      'message': {
        'role': 'user',
        'content': message,
      },
    };
    _process.send(json);
  }

  /// Send content blocks in the correct protocol format.
  void _sendUserContent(List<ContentBlock> content) {
    final json = {
      'type': 'user',
      'message': {
        'role': 'user',
        'content': content.map((c) => c.toJson()).toList(),
      },
    };
    _process.send(json);
  }

  /// Send a follow-up message to the session.
  Future<void> send(String message) async {
    if (_disposed) {
      _t('CliSession', 'ERROR: send() called on disposed session $sessionId');
      throw StateError('Session has been disposed');
    }

    _t('CliSession', 'Sending follow-up message (${message.length} chars, session=$sessionId)');
    _sendUserMessage(message);
  }

  /// Send content blocks (text and images) to the session.
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    _sendUserContent(content);
  }

  /// Interrupt the current execution.
  Future<void> interrupt() async {
    if (_disposed) return;

    final requestId = _generateRequestId();
    SdkLogger.instance.debug(
      'Interrupting session',
      sessionId: sessionId,
      data: {'requestId': requestId},
    );

    // Send control request with interrupt subtype
    _process.send({
      'type': 'control_request',
      'request_id': requestId,
      'request': {
        'subtype': 'interrupt',
      },
    });
  }

  /// Set the model for this session.
  ///
  /// Sends a control request to change the model mid-session.
  /// Note: This is only available in streaming input mode.
  Future<void> setModel(String? model) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    final requestId = _generateRequestId();
    SdkLogger.instance.debug(
      'Setting model',
      sessionId: sessionId,
      data: {'model': model, 'requestId': requestId},
    );

    _process.send({
      'type': 'control_request',
      'request_id': requestId,
      'request': {
        'subtype': 'set_model',
        'model': model,
      },
    });
  }

  /// Set the permission mode for this session.
  ///
  /// Sends a control request to change the permission mode mid-session.
  /// Note: This is only available in streaming input mode.
  Future<void> setPermissionMode(String? mode) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    final requestId = _generateRequestId();
    SdkLogger.instance.debug(
      'Setting permission mode',
      sessionId: sessionId,
      data: {'mode': mode, 'requestId': requestId},
    );

    _process.send({
      'type': 'control_request',
      'request_id': requestId,
      'request': {
        'subtype': 'set_permission_mode',
        'permission_mode': mode,
      },
    });
  }

  /// Set a backend-specific config option.
  ///
  /// Note: Claude CLI does not support ACP config options.
  Future<void> setConfigOption(String configId, dynamic value) async {
    // No-op: Claude CLI does not support config options.
  }

  /// Set the reasoning effort level for this session.
  ///
  /// Note: This is a no-op for Claude CLI sessions. Reasoning effort is only
  /// applicable to Codex backends with reasoning-capable models.
  Future<void> setReasoningEffort(String? effort) async {
    // No-op: Claude CLI does not support reasoning effort levels.
    // This method exists to satisfy the AgentSession interface.
  }

  /// Terminate the session.
  Future<void> kill() async {
    if (_disposed) return;

    await _process.kill();
    _dispose();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    if (_disposed) return;

    await _process.dispose();
    _dispose();
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    SdkLogger.instance.info('Session disposed', sessionId: sessionId);
    _eventsController.close();
    _permissionRequestsController.close();
  }

  static String _generateRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'req-$now-${now.hashCode.toRadixString(16)}';
  }
}

/// A permission request from the CLI.
///
/// When the CLI needs permission to use a tool, it sends a callback request.
/// The user must respond by calling [allow] or [deny].
class CliPermissionRequest {
  CliPermissionRequest._({
    required CliSession session,
    required this.requestId,
    required this.toolName,
    required this.input,
    required this.toolUseId,
    this.suggestions,
    this.blockedPath,
  }) : _session = session;

  final CliSession _session;

  /// The unique request ID for response correlation.
  final String requestId;

  /// The name of the tool requesting permission.
  final String toolName;

  /// The input parameters for the tool.
  final Map<String, dynamic> input;

  /// The tool use ID.
  final String toolUseId;

  /// Permission suggestions from the CLI.
  final List<PermissionSuggestion>? suggestions;

  /// The blocked path that triggered the permission request.
  final String? blockedPath;

  bool _responded = false;

  /// Whether this request has been responded to.
  bool get responded => _responded;

  /// Allow the tool execution.
  ///
  /// [updatedInput] - Modified input parameters. If null, original input is used.
  /// [updatedPermissions] - Optional permission suggestions to apply.
  void allow({
    Map<String, dynamic>? updatedInput,
    List<PermissionSuggestion>? updatedPermissions,
  }) {
    if (_responded) {
      throw StateError('Permission request has already been responded to');
    }
    _responded = true;

    SdkLogger.instance.debug(
      'Permission allowed',
      sessionId: _session.sessionId,
      data: {'toolName': toolName, 'requestId': requestId},
    );

    // Send control_response in the correct format
    // Note: updatedInput is REQUIRED by the CLI - use original input if not modified
    // CLI expects camelCase field names with toolUseID (capital ID)
    final response = {
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': {
          'behavior': 'allow',
          'updatedInput': updatedInput ?? input,
          'toolUseID': toolUseId,
          if (updatedPermissions != null)
            'updatedPermissions':
                updatedPermissions.map((p) => p.toJson()).toList(),
        },
      },
    };
    _session._process.send(response);
  }

  /// Deny the tool execution.
  ///
  /// [message] - Message explaining the denial. Defaults to "User denied permission".
  void deny([String? message]) {
    if (_responded) {
      throw StateError('Permission request has already been responded to');
    }
    _responded = true;

    final denialMessage = message ?? 'User denied permission';

    SdkLogger.instance.debug(
      'Permission denied',
      sessionId: _session.sessionId,
      data: {
        'toolName': toolName,
        'requestId': requestId,
        'message': denialMessage
      },
    );

    // Send control_response in the correct format
    // Note: message is REQUIRED by the CLI - use default if not provided
    // CLI expects camelCase field names with toolUseID (capital ID)
    final response = {
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': {
          'behavior': 'deny',
          'message': denialMessage,
          'toolUseID': toolUseId,
        },
      },
    };
    _session._process.send(response);
  }
}
