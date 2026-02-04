import 'dart:async';

import 'cli_process.dart';
import 'sdk_logger.dart';
import 'types/content_blocks.dart';
import 'types/control_messages.dart';
import 'types/permission_suggestion.dart';
import 'types/sdk_messages.dart';
import 'types/session_options.dart';

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
    required this.systemInit,
  }) : _process = process {
    _setupMessageRouting();
  }

  final CliProcess _process;
  final String sessionId;
  final SDKSystemMessage systemInit;

  final _messagesController = StreamController<SDKMessage>.broadcast();
  final _permissionRequestsController =
      StreamController<CliPermissionRequest>.broadcast();

  bool _disposed = false;

  /// Stream of SDK messages (assistant, user, result, stream_event, etc.).
  Stream<SDKMessage> get messages => _messagesController.stream;

  /// Stream of permission requests requiring user response.
  Stream<CliPermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  /// Whether the session is active.
  bool get isActive => !_disposed && _process.isRunning;

  /// The CLI process for advanced operations.
  CliProcess get process => _process;

  void _setupMessageRouting() {
    _process.messages.listen(
      _handleMessage,
      onError: (Object error) {
        if (!_disposed) {
          _messagesController.addError(error);
        }
      },
      onDone: () {
        if (!_disposed) {
          _dispose();
        }
      },
    );
  }

  void _handleMessage(Map<String, dynamic> json) {
    if (_disposed) return;

    final type = json['type'] as String?;

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
        }

      case 'control_response':
        // Control response - typically handled during initialization
        // Ignore during normal operation
        break;

      case 'system':
        // System message - parse and emit
        final sdkMessage = SDKMessage.fromJson(json);
        _messagesController.add(sdkMessage);

      case 'assistant':
      case 'user':
      case 'result':
      case 'stream_event':
        // SDK messages - parse and emit
        try {
          final sdkMessage = SDKMessage.fromJson(json);
          _messagesController.add(sdkMessage);
        } catch (e) {
          SdkLogger.instance.error('Failed to parse SDK message',
              sessionId: sessionId, data: {'error': e.toString(), 'json': json});
        }

      default:
        // Unknown message type - try to parse as SDK message anyway
        try {
          final sdkMessage = SDKMessage.fromJson(json);
          _messagesController.add(sdkMessage);
        } catch (_) {
          SdkLogger.instance.debug('Unknown message type ignored',
              sessionId: sessionId, data: {'type': type});
        }
    }
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
  }) async {
    // Build CLI process config
    final config = processConfig ??
        CliProcessConfig(
          cwd: cwd,
          model: options?.model,
          permissionMode: options?.permissionMode,
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
    final process = await CliProcess.spawn(config);

    try {
      // Generate request ID
      final requestId = _generateRequestId();

      // Step 1: Send control_request with initialize subtype
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
          'agents': {},
          'hooks': {},
        },
      };
      process.send(initRequest);

      // Step 2: Send the initial user message immediately (don't wait for control_response)
      // Use content blocks if provided, otherwise send prompt as plain text
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

      // Step 3: Wait for control_response and system init
      String? sessionId;
      SDKSystemMessage? systemInit;
      bool controlResponseReceived = false;

      await for (final json in process.messages.timeout(timeout)) {
        final type = json['type'] as String?;

        if (type == 'control_response') {
          controlResponseReceived = true;
          SdkLogger.instance.debug('Received control_response');
        } else if (type == 'system') {
          final subtype = json['subtype'] as String?;
          if (subtype == 'init') {
            sessionId = json['session_id'] as String?;
            systemInit = SDKSystemMessage.fromJson(json);
            SdkLogger.instance.debug('Received system init',
                sessionId: sessionId);
          }
        }

        // We have everything we need
        if (controlResponseReceived && sessionId != null && systemInit != null) {
          break;
        }
      }

      if (!controlResponseReceived) {
        SdkLogger.instance.error('Session creation timed out: no control_response');
        throw StateError('Session creation timed out: no control_response');
      }
      if (sessionId == null || systemInit == null) {
        SdkLogger.instance.error('Session creation timed out: no system init');
        throw StateError('Session creation timed out: no system init');
      }

      SdkLogger.instance.info('Session created successfully',
          sessionId: sessionId);

      return CliSession._(
        process: process,
        sessionId: sessionId,
        systemInit: systemInit,
      );
    } catch (e) {
      // Clean up on error
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
      throw StateError('Session has been disposed');
    }

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
    _messagesController.close();
    _permissionRequestsController.close();
  }

  /// Send a callback response (for permission requests).
  void _sendCallbackResponse(CallbackResponse response) {
    if (_disposed) return;
    _process.send(response.toJson());
  }

  static String _generateRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'req-$now-${now.hashCode.toRadixString(16)}';
  }

  static SessionCreateOptions? _convertToSessionCreateOptions(
    SessionOptions? options,
  ) {
    if (options == null) return null;

    String? systemPromptString;
    if (options.systemPrompt != null) {
      final json = options.systemPrompt!.toJson();
      if (json is String) {
        systemPromptString = json;
      }
    }

    return SessionCreateOptions(
      model: options.model,
      permissionMode: options.permissionMode?.value,
      systemPrompt: systemPromptString,
      mcpServers: options.mcpServers != null
          ? options.mcpServers!.map((k, v) => MapEntry(k, v.toJson()))
          : null,
      maxTurns: options.maxTurns,
      maxBudgetUsd: options.maxBudgetUsd,
      resume: options.resume,
    );
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
