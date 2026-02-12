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
    String? serverModel,
    String? serverReasoningEffort,
    InternalToolRegistry? registry,
  })  : _process = process,
        _isTestSession = false,
        _serverModel = serverModel,
        _serverReasoningEffort = serverReasoningEffort,
        _registry = registry {
    _setupStreams();
  }

  /// Creates a test session that is not connected to a real backend.
  CodexSession.forTesting({
    required this.threadId,
    String? serverModel,
    String? serverReasoningEffort,
    InternalToolRegistry? registry,
  })  : _process = null,
        _isTestSession = true,
        _serverModel = serverModel,
        _serverReasoningEffort = serverReasoningEffort,
        _registry = registry;

  final CodexProcess? _process;
  final bool _isTestSession;

  /// Thread ID from Codex.
  final String threadId;

  /// Internal tool registry for application-provided tools.
  final InternalToolRegistry? _registry;

  @override
  String get sessionId => threadId;

  @override
  String? get resolvedSessionId => threadId;

  final _eventsController = StreamController<InsightsEvent>.broadcast();
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

  /// Model name reported by the server in the thread/start response.
  final String? _serverModel;

  /// Reasoning effort reported by the server in the thread/start response.
  final String? _serverReasoningEffort;

  @override
  String? get serverModel => _serverModel;

  @override
  String? get serverReasoningEffort => _serverReasoningEffort;

  Map<String, dynamic>? _latestTokenUsage;
  int? _modelContextWindow;
  String? _modelName;
  String? _modelOverride;
  String? _currentTurnId;
  String? _effortOverride;

  /// Tracks fileChange items by itemId so approval requests can be enriched
  /// with file paths and diffs from the earlier item/started event.
  final Map<String, Map<String, dynamic>> _fileChangeItems = {};

  int _eventIdCounter = 0;

  String _nextEventId() {
    _eventIdCounter++;
    return 'evt-codex-${threadId.hashCode.toRadixString(16)}-$_eventIdCounter';
  }

  /// Constructs a Claude-compatible MCP tool name: `mcp__<server>__<tool>`.
  String _mcpToolName(Map<String, dynamic> item) {
    final server = item['server'] as String? ?? '';
    final tool = item['tool'] as String? ?? '';
    if (server.isNotEmpty && tool.isNotEmpty) {
      return 'mcp__${server}__$tool';
    }
    return 'McpTool';
  }

  /// Extract file paths from a Codex item for the `locations` field.
  List<String>? _extractCodexLocations(
      String itemType, Map<String, dynamic> item) {
    switch (itemType) {
      case 'commandExecution':
        // No file location for commands (cwd is not a target)
        return null;
      case 'fileChange':
        final changes = item['changes'] as List<dynamic>? ?? const [];
        final paths = changes
            .whereType<Map<String, dynamic>>()
            .map((c) => c['path'] as String?)
            .whereType<String>()
            .toList();
        return paths.isNotEmpty ? paths : null;
      case 'mcpToolCall':
        // MCP tools don't have standard file paths
        return null;
      default:
        return null;
    }
  }

  @override
  bool get isActive => !_disposed;

  @override
  Stream<InsightsEvent> get events => _eventsController.stream;

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
      case 'config/warning':
        _handleConfigWarning(params);
      case 'account/rateLimits/updated':
        _handleRateLimitsUpdated(params);
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
        _eventsController.add(PermissionRequestEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          sessionId: threadId,
          requestId: request.id.toString(),
          toolName: 'Bash',
          toolKind: ToolKind.execute,
          toolInput: {
            'command': params['command'] ?? '',
            'cwd': params['cwd'] ?? '',
          },
          toolUseId: params['itemId'] as String?,
          reason: params['reason'] as String?,
          extensions: {
            if (params['commandActions'] != null)
              'codex.commandActions': params['commandActions'],
          },
        ));
      case 'item/fileChange/requestApproval':
        final fileItemId = params['itemId'] as String?;
        final trackedItem =
            fileItemId != null ? _fileChangeItems[fileItemId] : null;
        final enrichedInput = trackedItem != null
            ? _fileChangeInput(trackedItem)
            : {'file_path': params['grantRoot'] ?? ''};
        _emitApprovalRequest(
          request,
          toolName: 'FileChange',
          toolInput: enrichedInput,
          toolUseId: fileItemId,
        );
        _eventsController.add(PermissionRequestEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          sessionId: threadId,
          requestId: request.id.toString(),
          toolName: 'FileChange',
          toolKind: ToolKind.edit,
          toolInput: enrichedInput,
          toolUseId: fileItemId,
          extensions: {
            if (params['grantRoot'] != null)
              'codex.grantRoot': params['grantRoot'],
          },
        ));
      case 'item/tool/requestUserInput':
        _emitAskUserQuestion(request, params);
        _eventsController.add(PermissionRequestEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          sessionId: threadId,
          requestId: request.id.toString(),
          toolName: 'AskUserQuestion',
          toolKind: ToolKind.ask,
          toolInput: {
            'questions': params['questions'] ?? const [],
          },
          toolUseId: params['itemId'] as String?,
        ));
      case 'item/tool/call':
        _handleDynamicToolCall(request, params);
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

  void _handleDynamicToolCall(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) {
    final toolName = params['tool'] as String?;
    final arguments =
        (params['arguments'] as Map<dynamic, dynamic>?)
            ?.cast<String, dynamic>() ??
        {};
    final registry = _registry;

    if (registry == null || toolName == null) {
      _process?.sendResponse(request.id, {
        'output': 'No tool registry available or missing tool name',
        'success': false,
      });
      return;
    }

    final tool = registry[toolName];
    if (tool == null) {
      _process?.sendResponse(request.id, {
        'output': 'Unknown tool: $toolName',
        'success': false,
      });
      return;
    }

    tool.handler(arguments).then((result) {
      if (_disposed) return;
      _process?.sendResponse(request.id, {
        'output': result.content,
        'success': !result.isError,
      });
    }).catchError((Object e) {
      if (_disposed) return;
      _process?.sendResponse(request.id, {
        'output': 'Tool error: $e',
        'success': false,
      });
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

    // Use model from notification, falling back to thread/start response
    _modelName = thread?['model'] as String? ?? _serverModel;
    // Use reasoning effort from notification, falling back to thread/start response
    final reasoningEffort =
        params['reasoningEffort'] as String? ?? _serverReasoningEffort;
    _eventsController.add(SessionInitEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.codex,
      raw: params,
      sessionId: threadId,
      model: _modelName,
      reasoningEffort: reasoningEffort,
    ));
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

    // modelContextWindow is a sibling of total/last in tokenUsage
    final contextWindow =
        (_latestTokenUsage?['modelContextWindow'] as num?)?.toInt();
    if (contextWindow != null && contextWindow > 0) {
      _modelContextWindow = contextWindow;
    }

    // Emit intermediate usage update from the "last" per-step field.
    // Uses Claude-compatible field names so ContextTracker.updateFromUsage works.
    final lastUsage = _latestTokenUsage?['last'] as Map<String, dynamic>?;
    final lastInput = (lastUsage?['inputTokens'] as num?)?.toInt() ?? 0;
    final lastOutput = (lastUsage?['outputTokens'] as num?)?.toInt() ?? 0;
    final lastCached = (lastUsage?['cachedInputTokens'] as num?)?.toInt() ?? 0;
    if (lastInput > 0 || lastOutput > 0) {
      _eventsController.add(UsageUpdateEvent(
        id: _nextEventId(),
        timestamp: DateTime.now(),
        provider: BackendProvider.codex,
        sessionId: threadId,
        stepUsage: {
          'input_tokens': lastInput,
          'output_tokens': lastOutput,
          'cache_read_input_tokens': lastCached,
          'cache_creation_input_tokens': 0,
        },
      ));
    }
  }

  void _handleItemStarted(Map<String, dynamic> params) {
    final id = params['threadId'] as String?;
    if (id != threadId) return;

    final item = params['item'] as Map<String, dynamic>?;
    if (item == null) return;

    final type = item['type'] as String?;
    switch (type) {
      case 'commandExecution':
        _eventsController.add(ToolInvocationEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          callId: item['id'] as String? ?? '',
          sessionId: threadId,
          kind: ToolKind.execute,
          toolName: 'Bash',
          input: {
            'command': item['command'] ?? '',
            'cwd': item['cwd'] ?? '',
          },
          extensions: {
            'codex.itemType': 'commandExecution',
          },
        ));
      case 'fileChange':
        final itemId = item['id'] as String? ?? '';
        if (itemId.isNotEmpty) {
          _fileChangeItems[itemId] = item;
        }
        final fileChangePaths = _extractCodexLocations('fileChange', item);
        _eventsController.add(ToolInvocationEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          callId: item['id'] as String? ?? '',
          sessionId: threadId,
          kind: ToolKind.edit,
          toolName: 'FileChange',
          input: _fileChangeInput(item),
          locations: fileChangePaths,
          extensions: {
            'codex.itemType': 'fileChange',
          },
        ));
      case 'mcpToolCall':
        _eventsController.add(ToolInvocationEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          callId: item['id'] as String? ?? '',
          sessionId: threadId,
          kind: ToolKind.mcp,
          toolName: _mcpToolName(item),
          input: {
            'server': item['server'],
            'tool': item['tool'],
            'arguments': item['arguments'],
          },
          extensions: {
            'codex.itemType': 'mcpToolCall',
          },
        ));
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
        _eventsController.add(TextEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          sessionId: threadId,
          text: item['text'] as String? ?? '',
          kind: TextKind.text,
        ));
      case 'reasoning':
        final summary = (item['summary'] as List?)?.join('\n') ?? '';
        final content = (item['content'] as List?)?.join('\n') ?? '';
        final thinking = summary.isNotEmpty ? summary : content;
        if (thinking.isNotEmpty) {
          _eventsController.add(TextEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.codex,
            raw: params,
            sessionId: threadId,
            text: thinking,
            kind: TextKind.thinking,
          ));
        }
      case 'plan':
        _eventsController.add(TextEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          sessionId: threadId,
          text: item['text'] as String? ?? '',
          kind: TextKind.plan,
        ));
      case 'commandExecution':
        final cmdIsError = (item['exitCode'] as int?) != null &&
            (item['exitCode'] as int?) != 0;
        _eventsController.add(ToolCompletionEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          callId: item['id'] as String? ?? '',
          sessionId: threadId,
          status: cmdIsError ? ToolCallStatus.failed : ToolCallStatus.completed,
          output: {
            'stdout': item['aggregatedOutput'] ?? '',
            'stderr': '',
            'exit_code': item['exitCode'],
          },
          isError: cmdIsError,
        ));
      case 'fileChange':
        final completedId = item['id'] as String?;
        if (completedId != null) _fileChangeItems.remove(completedId);
        final fileIsError = (item['status'] as String?) == 'failed';
        final completedPaths = _extractCodexLocations('fileChange', item);
        _eventsController.add(ToolCompletionEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          callId: item['id'] as String? ?? '',
          sessionId: threadId,
          status: fileIsError ? ToolCallStatus.failed : ToolCallStatus.completed,
          output: _fileChangeResult(item),
          isError: fileIsError,
          locations: completedPaths,
        ));
      case 'mcpToolCall':
        final error = item['error'] as Map<String, dynamic>?;
        final result = item['result'] as Map<String, dynamic>?;
        _eventsController.add(ToolCompletionEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.codex,
          raw: params,
          callId: item['id'] as String? ?? '',
          sessionId: threadId,
          status: error != null ? ToolCallStatus.failed : ToolCallStatus.completed,
          output: result ?? error ?? {},
          isError: error != null,
        ));
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

    // Build modelUsage so the frontend can identify the model for cost
    // calculation and context tracking.
    final modelKey = _modelName ?? _serverModel ?? 'codex';
    final modelUsage = <String, ModelTokenUsage>{
      modelKey: ModelTokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheReadTokens: cachedInput > 0 ? cachedInput : null,
        contextWindow: _modelContextWindow,
      ),
    };

    // Build lastStepUsage from the per-API-call "last" field for context tracking.
    // Uses Claude-compatible field names so ContextTracker.updateFromUsage works.
    final lastUsage = _latestTokenUsage?['last'] as Map<String, dynamic>?;
    final lastInput = (lastUsage?['inputTokens'] as num?)?.toInt() ?? 0;
    final lastCached = (lastUsage?['cachedInputTokens'] as num?)?.toInt() ?? 0;
    Map<String, dynamic>? lastStepUsage;
    if (lastInput > 0) {
      lastStepUsage = {
        'input_tokens': lastInput,
        'cache_read_input_tokens': lastCached,
        'cache_creation_input_tokens': 0,
      };
    }

    _eventsController.add(TurnCompleteEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.codex,
      raw: params,
      sessionId: threadId,
      isError: false,
      subtype: 'success',
      usage: TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheReadTokens: cachedInput > 0 ? cachedInput : null,
      ),
      modelUsage: modelUsage,
      extensions: lastStepUsage != null
          ? {'lastStepUsage': lastStepUsage}
          : null,
    ));
  }

  void _handleConfigWarning(Map<String, dynamic> params) {
    final summary = params['summary'] as String? ?? '';
    _eventsController.add(TextEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.codex,
      raw: params,
      sessionId: threadId,
      text: summary,
      kind: TextKind.error,
    ));
  }

  void _handleRateLimitsUpdated(Map<String, dynamic> params) {
    final rateLimits = params['rateLimits'] as Map<String, dynamic>?;
    if (rateLimits == null) return;

    final primaryJson = rateLimits['primary'] as Map<String, dynamic>?;
    final secondaryJson = rateLimits['secondary'] as Map<String, dynamic>?;
    final creditsJson = rateLimits['credits'] as Map<String, dynamic>?;

    _eventsController.add(RateLimitUpdateEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.codex,
      raw: params,
      sessionId: threadId,
      primary:
          primaryJson != null ? RateLimitWindow.fromJson(primaryJson) : null,
      secondary:
          secondaryJson != null ? RateLimitWindow.fromJson(secondaryJson) : null,
      credits:
          creditsJson != null ? RateLimitCredits.fromJson(creditsJson) : null,
      planType: rateLimits['planType'] as String?,
    ));
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
  Future<void> setConfigOption(String configId, dynamic value) async {
    throw UnsupportedError(
      'Codex does not support session config options. '
      'Check backend capabilities before calling.',
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

  /// Injects a notification for testing purposes.
  @visibleForTesting
  void injectNotification(JsonRpcNotification notification) {
    _handleNotification(notification);
  }

  /// Injects a server request for testing purposes.
  @visibleForTesting
  void injectServerRequest(JsonRpcServerRequest request) {
    _handleServerRequest(request);
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _fileChangeItems.clear();
    _deleteTempFiles(Set<String>.of(_tempImagePaths));
    _notificationSub?.cancel();
    _requestSub?.cancel();
    _eventsController.close();
    _permissionController.close();
    _hookController.close();
  }
}
