import 'dart:async';

import 'cli_process.dart';
import 'sdk_logger.dart';
import 'types/content_blocks.dart';
import 'types/control_messages.dart';
import 'types/permission_suggestion.dart';
import 'types/sdk_messages.dart';
import 'types/session_options.dart';

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
    _t('CliSession', 'Setting up message routing for session $sessionId');
    _process.messages.listen(
      _handleMessage,
      onError: (Object error) {
        _t('CliSession', 'Message stream error: $error (session=$sessionId)');
        if (!_disposed) {
          _messagesController.addError(error);
        }
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
      _t('CliSession', 'Step 3: Waiting for control_response AND system init (timeout=${timeout.inSeconds}s)...');
      String? sessionId;
      SDKSystemMessage? systemInit;
      bool controlResponseReceived = false;
      int messagesReceived = 0;

      await for (final json in process.messages.timeout(timeout)) {
        messagesReceived++;
        final type = json['type'] as String?;
        final subtype = json['subtype'] as String? ??
            (json['request'] as Map<String, dynamic>?)?['subtype'] as String?;
        _t('CliSession', 'Step 3: Message #$messagesReceived: type=$type'
            '${subtype != null ? ' subtype=$subtype' : ''}'
            ' (${stopwatch.elapsedMilliseconds}ms)');

        if (type == 'control_response') {
          controlResponseReceived = true;
          _t('CliSession', 'Step 3: control_response received');
          SdkLogger.instance.debug('Received control_response');
        } else if (type == 'system') {
          final sysSubtype = json['subtype'] as String?;
          if (sysSubtype == 'init') {
            sessionId = json['session_id'] as String?;
            systemInit = SDKSystemMessage.fromJson(json);
            _t('CliSession', 'Step 3: system init received, sessionId=$sessionId');
            SdkLogger.instance.debug('Received system init',
                sessionId: sessionId);
          } else {
            _t('CliSession', 'Step 3: system message with subtype=$sysSubtype (not "init", ignoring for handshake)');
          }
        } else {
          _t('CliSession', 'Step 3: (not a handshake message, continuing wait)');
        }

        // We have everything we need
        if (controlResponseReceived && sessionId != null && systemInit != null) {
          _t('CliSession', 'Step 3: Both handshake messages received!');
          break;
        }

        // Log what we're still waiting for
        final waiting = <String>[];
        if (!controlResponseReceived) waiting.add('control_response');
        if (sessionId == null) waiting.add('system init');
        _t('CliSession', 'Step 3: Still waiting for: ${waiting.join(', ')}');
      }

      if (!controlResponseReceived) {
        _t('CliSession', 'TIMEOUT: No control_response after ${stopwatch.elapsedMilliseconds}ms ($messagesReceived messages received)');
        SdkLogger.instance.error('Session creation timed out: no control_response');
        throw StateError('Session creation timed out: no control_response');
      }
      if (sessionId == null || systemInit == null) {
        _t('CliSession', 'TIMEOUT: No system init after ${stopwatch.elapsedMilliseconds}ms ($messagesReceived messages received)');
        SdkLogger.instance.error('Session creation timed out: no system init');
        throw StateError('Session creation timed out: no system init');
      }

      _t('CliSession', '========== SESSION CREATED (${stopwatch.elapsedMilliseconds}ms) ==========');
      _t('CliSession', 'sessionId: $sessionId');
      SdkLogger.instance.info('Session created successfully',
          sessionId: sessionId);

      return CliSession._(
        process: process,
        sessionId: sessionId,
        systemInit: systemInit,
      );
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
