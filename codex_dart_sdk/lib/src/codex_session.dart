import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:meta/meta.dart';

import 'codex_process.dart';
import 'json_rpc.dart';

/// A session communicating with Codex app-server.
class CodexSession implements AgentSession {
  CodexSession({
    required CodexProcess process,
    required this.threadId,
  })  : _process = process,
        _isTestSession = false {
    _setupStreams();
  }

  /// Creates a test session that is not connected to a real backend.
  CodexSession.forTesting({
    required this.threadId,
  })  : _process = null,
        _isTestSession = true;

  final CodexProcess? _process;
  final bool _isTestSession;

  /// Thread ID from Codex.
  @override
  final String threadId;

  @override
  String get sessionId => threadId;

  @override
  String? get resolvedSessionId => threadId;

  final _messagesController = StreamController<SDKMessage>.broadcast();
  final _permissionController =
      StreamController<PermissionRequest>.broadcast();
  final _hookController = StreamController<HookRequest>.broadcast();

  StreamSubscription<JsonRpcNotification>? _notificationSub;
  StreamSubscription<JsonRpcServerRequest>? _requestSub;

  bool _disposed = false;

  /// Temp image files created during [sendWithContent] that need cleanup.
  final _tempImagePaths = <String>{};

  /// Exposes tracked temp image paths for testing.
  @visibleForTesting
  Set<String> get tempImagePaths => _tempImagePaths;

  Map<String, dynamic>? _latestTokenUsage;
  String? _modelOverride;
  String? _currentTurnId;
  String? _effortOverride;

  @override
  bool get isActive => !_disposed;

  @override
  Stream<SDKMessage> get messages => _messagesController.stream;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionController.stream;

  @override
  Stream<HookRequest> get hookRequests => _hookController.stream;

  void _setupStreams() {
    if (_process == null) return;

    _notificationSub = _process!.notifications.listen(_handleNotification);
    _requestSub = _process!.serverRequests.listen(_handleServerRequest);
  }

  void _handleNotification(JsonRpcNotification notification) {
    if (_disposed) return;
    final params = notification.params ?? const <String, dynamic>{};

    switch (notification.method) {
      case 'thread/started':
        _handleThreadStarted(params);
      case 'thread/tokenUsage/updated':
        _handleTokenUsageUpdated(params);
      case 'turn/started':
        _handleTurnStarted(params);
      case 'item/started':
        _handleItemStarted(params);
      case 'item/completed':
        _handleItemCompleted(params);
      case 'turn/completed':
        _handleTurnCompleted(params);
      default:
        break;
    }
  }

  void _handleServerRequest(JsonRpcServerRequest request) {
    if (_disposed) return;
    final params = request.params ?? const <String, dynamic>{};
    final thread = params['threadId'] as String?;
    if (thread != null && thread != threadId) return;

    switch (request.method) {
      case 'item/commandExecution/requestApproval':
        _emitApprovalRequest(
          request,
          toolName: 'Bash',
          toolInput: {
            'command': params['command'] ?? '',
            'cwd': params['cwd'] ?? '',
          },
          toolUseId: params['itemId'] as String?,
        );
      case 'item/fileChange/requestApproval':
        _emitApprovalRequest(
          request,
          toolName: 'Write',
          toolInput: {
            'file_path': params['grantRoot'] ?? '',
          },
          toolUseId: params['itemId'] as String?,
        );
      case 'item/tool/requestUserInput':
        _emitAskUserQuestion(request, params);
      default:
        _process?.sendError(
          request.id,
          -32601,
          'Unsupported request: ${request.method}',
        );
    }
  }

  void _emitApprovalRequest(
    JsonRpcServerRequest request, {
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) {
    final completer = Completer<PermissionResponse>();
    final permission = PermissionRequest(
      id: request.id.toString(),
      sessionId: threadId,
      toolName: toolName,
      toolInput: toolInput,
      toolUseId: toolUseId,
      completer: completer,
    );

    _permissionController.add(permission);

    completer.future.then((response) {
      if (_disposed) return;
      final decision = _mapDecision(response);
      _process?.sendResponse(request.id, {'decision': decision});
    });
  }

  void _emitAskUserQuestion(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) {
    final questions = params['questions'] as List<dynamic>? ?? const [];
    final toolUseId = params['itemId'] as String?;

    final completer = Completer<PermissionResponse>();
    final permission = PermissionRequest(
      id: request.id.toString(),
      sessionId: threadId,
      toolName: 'AskUserQuestion',
      toolInput: {'questions': questions},
      toolUseId: toolUseId,
      completer: completer,
    );

    _permissionController.add(permission);

    completer.future.then((response) {
      if (_disposed) return;
      if (response is PermissionAllowResponse) {
        final answers =
            response.updatedInput?['answers'] as Map<String, dynamic>? ?? {};
        _process?.sendResponse(request.id, {'answers': answers});
      } else if (response is PermissionDenyResponse) {
        _process?.sendResponse(request.id, {'answers': {}});
      }
    });
  }

  String _mapDecision(PermissionResponse response) {
    return switch (response) {
      PermissionAllowResponse() => 'accept',
      PermissionDenyResponse(interrupt: true) => 'cancel',
      PermissionDenyResponse() => 'decline',
    };
  }

  void _handleThreadStarted(Map<String, dynamic> params) {
    final thread = params['thread'] as Map<String, dynamic>?;
    final id = thread?['id'] as String?;
    if (id != threadId) return;

    _emitSdkMessage({
      'type': 'system',
      'subtype': 'init',
      'session_id': threadId,
      'uuid': _nextUuid(),
      'model': thread?['model'] as String?,
    });
  }

  void _handleTurnStarted(Map<String, dynamic> params) {
    final id = params['threadId'] as String?;
    if (id != threadId) return;

    final turn = params['turn'] as Map<String, dynamic>?;
    _currentTurnId = turn?['id'] as String?;
  }

  void _handleTokenUsageUpdated(Map<String, dynamic> params) {
    final id = params['threadId'] as String?;
    if (id != threadId) return;
    _latestTokenUsage = params['tokenUsage'] as Map<String, dynamic>?;
  }

  void _handleItemStarted(Map<String, dynamic> params) {
    final id = params['threadId'] as String?;
    if (id != threadId) return;

    final item = params['item'] as Map<String, dynamic>?;
    if (item == null) return;

    final type = item['type'] as String?;
    switch (type) {
      case 'commandExecution':
        _emitToolUse(
          toolUseId: item['id'] as String? ?? '',
          toolName: 'Bash',
          toolInput: {
            'command': item['command'] ?? '',
            'cwd': item['cwd'] ?? '',
          },
        );
      case 'fileChange':
        _emitToolUse(
          toolUseId: item['id'] as String? ?? '',
          toolName: 'Write',
          toolInput: _fileChangeInput(item),
        );
      case 'mcpToolCall':
        _emitToolUse(
          toolUseId: item['id'] as String? ?? '',
          toolName: 'McpTool',
          toolInput: {
            'server': item['server'],
            'tool': item['tool'],
            'arguments': item['arguments'],
          },
        );
      default:
        break;
    }
  }

  void _handleItemCompleted(Map<String, dynamic> params) {
    final id = params['threadId'] as String?;
    if (id != threadId) return;

    final item = params['item'] as Map<String, dynamic>?;
    if (item == null) return;

    final type = item['type'] as String?;
    switch (type) {
      case 'agentMessage':
        _emitAssistantText(item['text'] as String? ?? '');
      case 'reasoning':
        final summary = (item['summary'] as List?)?.join('\n') ?? '';
        final content = (item['content'] as List?)?.join('\n') ?? '';
        final thinking = summary.isNotEmpty ? summary : content;
        if (thinking.isNotEmpty) {
          _emitAssistantThinking(thinking);
        }
      case 'plan':
        _emitAssistantText(item['text'] as String? ?? '');
      case 'commandExecution':
        _emitToolResult(
          toolUseId: item['id'] as String? ?? '',
          result: {
            'stdout': item['aggregatedOutput'] ?? '',
            'stderr': '',
            'exit_code': item['exitCode'],
          },
          isError: (item['exitCode'] as int?) != null &&
              (item['exitCode'] as int?) != 0,
        );
      case 'fileChange':
        _emitToolResult(
          toolUseId: item['id'] as String? ?? '',
          result: _fileChangeResult(item),
          isError: (item['status'] as String?) == 'failed',
        );
      case 'mcpToolCall':
        final error = item['error'] as Map<String, dynamic>?;
        final result = item['result'] as Map<String, dynamic>?;
        _emitToolResult(
          toolUseId: item['id'] as String? ?? '',
          result: result ?? error ?? {},
          isError: error != null,
        );
      default:
        break;
    }
  }

  void _handleTurnCompleted(Map<String, dynamic> params) {
    final id = params['threadId'] as String?;
    if (id != threadId) return;
    _currentTurnId = null;

    final usage = _latestTokenUsage?['total'] as Map<String, dynamic>?;
    final inputTokens = (usage?['inputTokens'] as num?)?.toInt() ?? 0;
    final outputTokens = (usage?['outputTokens'] as num?)?.toInt() ?? 0;
    final cachedInput = (usage?['cachedInputTokens'] as num?)?.toInt() ?? 0;

    _emitSdkMessage({
      'type': 'result',
      'subtype': 'success',
      'uuid': _nextUuid(),
      'session_id': threadId,
      'duration_ms': 0,
      'duration_api_ms': 0,
      'is_error': false,
      'num_turns': 1,
      'total_cost_usd': 0.0,
      'usage': {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'cache_read_input_tokens': cachedInput,
        'cache_creation_input_tokens': 0,
      },
    });
  }

  Map<String, dynamic> _fileChangeInput(Map<String, dynamic> item) {
    final changes = item['changes'] as List<dynamic>? ?? const [];
    final paths = changes
        .whereType<Map<String, dynamic>>()
        .map((c) => c['path'] as String?)
        .whereType<String>()
        .toList();
    final diffs = changes
        .whereType<Map<String, dynamic>>()
        .map((c) => c['diff'] as String?)
        .whereType<String>()
        .toList();

    return {
      'file_path': paths.isNotEmpty ? paths.first : '',
      if (paths.length > 1) 'paths': paths,
      if (diffs.isNotEmpty) 'content': diffs.join('\n\n'),
    };
  }

  Map<String, dynamic> _fileChangeResult(Map<String, dynamic> item) {
    final changes = item['changes'] as List<dynamic>? ?? const [];
    final diffs = changes
        .whereType<Map<String, dynamic>>()
        .map((c) => c['diff'] as String?)
        .whereType<String>()
        .toList();
    return {
      'diff': diffs.join('\n\n'),
    };
  }

  void _emitAssistantText(String text) {
    _emitSdkMessage({
      'type': 'assistant',
      'uuid': _nextUuid(),
      'session_id': threadId,
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text}
        ],
      },
    });
  }

  void _emitAssistantThinking(String text) {
    _emitSdkMessage({
      'type': 'assistant',
      'uuid': _nextUuid(),
      'session_id': threadId,
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': text, 'signature': ''}
        ],
      },
    });
  }

  void _emitToolUse({
    required String toolUseId,
    required String toolName,
    required Map<String, dynamic> toolInput,
  }) {
    _emitSdkMessage({
      'type': 'assistant',
      'uuid': _nextUuid(),
      'session_id': threadId,
      'message': {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': toolUseId,
            'name': toolName,
            'input': toolInput,
          }
        ],
      },
    });
  }

  void _emitToolResult({
    required String toolUseId,
    required dynamic result,
    required bool isError,
  }) {
    _emitSdkMessage({
      'type': 'user',
      'uuid': _nextUuid(),
      'session_id': threadId,
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': toolUseId,
            'content': result,
            'is_error': isError,
          }
        ],
      },
    });
  }

  void _emitSdkMessage(Map<String, dynamic> raw) {
    final message = SDKMessage.fromJson(raw);
    _messagesController.add(message);
  }

  String _nextUuid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'codex-$now-${now.hashCode.toRadixString(16)}';
  }

  @override
  Future<void> send(String message) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    if (_isTestSession) return;

    final result = await _process!.sendRequest('turn/start', {
      'threadId': threadId,
      'input': [
        {'type': 'text', 'text': message}
      ],
      if (_modelOverride != null) 'model': _modelOverride,
      if (_effortOverride != null) 'effort': _effortOverride,
    });
    _extractTurnId(result);
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    if (_isTestSession) return;

    final inputs = await _convertContent(content);
    if (inputs.isEmpty) {
      return send('');
    }

    // Snapshot the temp paths created for this call so we can clean them up.
    final tempPaths = Set<String>.of(_tempImagePaths);

    try {
      final result = await _process!.sendRequest('turn/start', {
        'threadId': threadId,
        'input': inputs,
        if (_modelOverride != null) 'model': _modelOverride,
        if (_effortOverride != null) 'effort': _effortOverride,
      });
      _extractTurnId(result);
    } finally {
      _deleteTempFiles(tempPaths);
    }
  }

  void _extractTurnId(Map<String, dynamic> result) {
    final turn = result['turn'] as Map<String, dynamic>?;
    final turnId = turn?['id'] as String?;
    if (turnId != null) {
      _currentTurnId = turnId;
    }
  }

  Future<List<Map<String, dynamic>>> _convertContent(
    List<ContentBlock> content,
  ) async {
    final inputs = <Map<String, dynamic>>[];

    for (final block in content) {
      if (block is TextBlock) {
        inputs.add({'type': 'text', 'text': block.text});
      } else if (block is ImageBlock) {
        final source = block.source;
        if (source.type == 'url' && source.url != null) {
          inputs.add({'type': 'image', 'url': source.url});
        } else if (source.type == 'base64' && source.data != null) {
          final path = await _writeTempImage(source.data!, source.mediaType);
          inputs.add({'type': 'localImage', 'path': path});
        }
      }
    }

    return inputs;
  }

  Future<String> _writeTempImage(String base64Data, String? mediaType) async {
    final bytes = base64Decode(base64Data);
    final ext = _extensionForMediaType(mediaType);
    final file = await File(
      '${Directory.systemTemp.path}/codex-image-${_nextUuid()}.$ext',
    ).create();
    await file.writeAsBytes(bytes, flush: true);
    _tempImagePaths.add(file.path);
    return file.path;
  }

  String _extensionForMediaType(String? mediaType) {
    return switch (mediaType) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
  }

  @override
  Future<void> interrupt() async {
    if (_disposed || _isTestSession) return;
    final turnId = _currentTurnId;
    if (turnId == null) return;
    await _process!.sendRequest('turn/interrupt', {
      'threadId': threadId,
      'turnId': turnId,
    });
  }

  @override
  Future<void> kill() async {
    if (_disposed) return;
    _dispose();
  }

  @override
  Future<void> setModel(String? model) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    final trimmed = model?.trim();
    _modelOverride = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  Future<void> setPermissionMode(String? mode) async {
    throw UnsupportedError(
      'Codex does not support mid-session permission mode changes. '
      'Check BackendCapabilities.supportsPermissionModeChange before calling.',
    );
  }

  @override
  Future<void> setReasoningEffort(String? effort) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    final trimmed = effort?.trim();
    _effortOverride = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void _deleteTempFiles(Set<String> paths) {
    for (final path in paths) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // Ignore — file may already be deleted.
      }
      _tempImagePaths.remove(path);
    }
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _deleteTempFiles(Set<String>.of(_tempImagePaths));
    _notificationSub?.cancel();
    _requestSub?.cancel();
    _messagesController.close();
    _permissionController.close();
    _hookController.close();
  }
}
