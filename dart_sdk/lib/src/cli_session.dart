import 'dart:async';

import 'cli_process.dart';
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

    final messageType = parseCliMessageType(json);

    switch (messageType) {
      case CliMessageType.callbackRequest:
        // Permission request from CLI
        final callbackRequest = CallbackRequest.fromJson(json);
        if (callbackRequest.payload.callbackType == 'can_use_tool') {
          final request = CliPermissionRequest._(
            session: this,
            requestId: callbackRequest.id,
            toolName: callbackRequest.payload.toolName,
            input: callbackRequest.payload.toolInput,
            toolUseId: callbackRequest.payload.toolUseId,
            suggestions: callbackRequest.payload.suggestions,
            blockedPath: callbackRequest.payload.blockedPath,
          );
          _permissionRequestsController.add(request);
        }

      case CliMessageType.sdkMessage:
        // Regular SDK message - parse and emit
        final payload = json['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          final sdkMessage = SDKMessage.fromJson(payload);
          _messagesController.add(sdkMessage);
        }

      case CliMessageType.sessionCreated:
        // Ignore during normal operation - handled in create()
        break;

      case CliMessageType.unknown:
        // Unknown message type - try to parse as SDK message anyway
        // This handles cases where the message doesn't have a wrapper
        try {
          final sdkMessage = SDKMessage.fromJson(json);
          _messagesController.add(sdkMessage);
        } catch (_) {
          // Truly unknown - ignore
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
        );

    // Spawn the CLI process
    final process = await CliProcess.spawn(config);

    try {
      // Generate a unique request ID
      final requestId = _generateRequestId();

      // Send session.create request
      final createRequest = ControlRequest(
        type: 'session.create',
        id: requestId,
        payload: SessionCreatePayload(
          prompt: prompt,
          cwd: cwd,
          options: _convertToSessionCreateOptions(options),
        ),
      );
      process.send(createRequest.toJson());

      // Wait for session.created response
      String? sessionId;
      SDKSystemMessage? systemInit;

      await for (final json in process.messages.timeout(timeout)) {
        final messageType = parseCliMessageType(json);

        if (messageType == CliMessageType.sessionCreated) {
          final created = SessionCreatedMessage.fromJson(json);
          if (created.id == requestId) {
            sessionId = created.sessionId;
          }
        } else if (messageType == CliMessageType.sdkMessage) {
          final payload = json['payload'] as Map<String, dynamic>?;
          if (payload != null) {
            final type = payload['type'] as String?;
            if (type == 'system') {
              final subtype = payload['subtype'] as String?;
              if (subtype == 'init') {
                systemInit = SDKSystemMessage.fromJson(payload);
              }
            }
          }
        }

        // Check if initialization is complete
        if (sessionId != null && systemInit != null) {
          break;
        }
      }

      if (sessionId == null) {
        throw StateError('Session creation timed out: no session.created');
      }
      if (systemInit == null) {
        throw StateError('Session creation timed out: no system init');
      }

      return CliSession._(
        process: process,
        sessionId: sessionId,
        systemInit: systemInit,
      );
    } catch (e) {
      // Clean up on error
      await process.dispose();
      rethrow;
    }
  }

  /// Send a follow-up message to the session.
  Future<void> send(String message) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    final json = {
      'type': 'user.message',
      'session_id': sessionId,
      'payload': {
        'message': message,
      },
    };
    _process.send(json);
  }

  /// Send content blocks (text and images) to the session.
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }

    final json = {
      'type': 'user.message',
      'session_id': sessionId,
      'payload': {
        'content': content.map((c) => c.toJson()).toList(),
      },
    };
    _process.send(json);
  }

  /// Interrupt the current execution.
  Future<void> interrupt() async {
    if (_disposed) return;

    // Send SIGINT to the process
    _process.send({
      'type': 'session.interrupt',
      'session_id': sessionId,
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
  /// [updatedInput] - Optional modified input parameters.
  /// [updatedPermissions] - Optional permission suggestions to apply.
  void allow({
    Map<String, dynamic>? updatedInput,
    List<PermissionSuggestion>? updatedPermissions,
  }) {
    if (_responded) {
      throw StateError('Permission request has already been responded to');
    }
    _responded = true;

    final response = CallbackResponse.allow(
      requestId: requestId,
      sessionId: _session.sessionId,
      toolUseId: toolUseId,
      updatedInput: updatedInput,
      updatedPermissions: updatedPermissions,
    );
    _session._sendCallbackResponse(response);
  }

  /// Deny the tool execution.
  ///
  /// [message] - Optional message explaining the denial.
  void deny([String? message]) {
    if (_responded) {
      throw StateError('Permission request has already been responded to');
    }
    _responded = true;

    final response = CallbackResponse.deny(
      requestId: requestId,
      sessionId: _session.sessionId,
      toolUseId: toolUseId,
      message: message,
    );
    _session._sendCallbackResponse(response);
  }
}
