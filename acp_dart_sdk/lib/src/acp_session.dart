import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:path/path.dart' as p;

import 'acp_process.dart';
import 'json_rpc.dart';

/// Session placeholder for ACP agents.
class AcpSession implements AgentSession {
  AcpSession({
    required AcpProcess process,
    required String sessionId,
    required String cwd,
    bool includePartialMessages = false,
    List<String> allowedDirectories = const [],
  })  : _process = process,
        _sessionId = sessionId,
        _cwd = cwd,
        _includePartialMessages = includePartialMessages,
        _rootDir = p.normalize(p.absolute(cwd)),
        _allowedDirectories = allowedDirectories
            .map((dir) => p.normalize(p.absolute(dir)))
            .toList(growable: false) {
    _notificationSub = _process.notifications.listen(_handleNotification);
    _serverRequestSub = _process.serverRequests.listen(_handleServerRequest);
  }

  final AcpProcess _process;
  final String _sessionId;
  final String _cwd;
  final bool _includePartialMessages;
  final String _rootDir;
  final List<String> _allowedDirectories;

  int _eventIdCounter = 0;
  bool _active = true;
  StreamSubscription<JsonRpcNotification>? _notificationSub;
  StreamSubscription<JsonRpcServerRequest>? _serverRequestSub;
  final Set<String> _emittedToolCalls = {};

  @override
  String get sessionId => _sessionId;

  @override
  String? get resolvedSessionId => _sessionId;

  @override
  bool get isActive => _active;

  final _eventsController = StreamController<InsightsEvent>.broadcast();
  final _permissionController = StreamController<PermissionRequest>.broadcast();
  final _hookController = StreamController<HookRequest>.broadcast();

  @override
  Stream<InsightsEvent> get events => _eventsController.stream;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionController.stream;

  @override
  Stream<HookRequest> get hookRequests => _hookController.stream;

  @override
  Future<void> send(String message) {
    _ensureActive();
    return _process.sendRequest('session/prompt', {
      'sessionId': _sessionId,
      'prompt': [
        {'type': 'text', 'text': message},
      ],
    });
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) {
    _ensureActive();
    final prompt = content.map((block) => block.toJson()).toList();
    if (prompt.isEmpty) {
      return send('');
    }
    return _process.sendRequest('session/prompt', {
      'sessionId': _sessionId,
      'prompt': prompt,
    });
  }

  @override
  Future<void> interrupt() {
    _ensureActive();
    _process.sendNotification('session/cancel', {'sessionId': _sessionId});
    return Future.value();
  }

  @override
  Future<void> kill() {
    if (!_active) return Future.value();
    _process.sendNotification('session/cancel', {'sessionId': _sessionId});
    return dispose();
  }

  @override
  Future<void> setModel(String? model) {
    if (!_active) return Future.value();
    SdkLogger.instance.warning(
      'ACP setModel is not supported yet.',
      sessionId: _sessionId,
      data: {'model': model},
    );
    return Future.value();
  }

  @override
  Future<void> setPermissionMode(String? mode) {
    _ensureActive();
    if (mode == null || mode.isEmpty) {
      return Future.value();
    }
    return _process.sendRequest('session/set_mode', {
      'sessionId': _sessionId,
      'modeId': mode,
    });
  }

  @override
  Future<void> setReasoningEffort(String? effort) {
    if (!_active) return Future.value();
    // ACP does not currently expose reasoning effort.
    return Future.value();
  }

  void _handleNotification(JsonRpcNotification notification) {
    if (!_active) return;
    if (notification.method != 'session/update') return;
    final params = notification.params;
    if (params == null) return;

    final sessionId = params['sessionId'] as String?;
    if (sessionId != _sessionId) return;

    final update = params['update'] as Map<String, dynamic>? ??
        params['sessionUpdate'] as Map<String, dynamic>?;
    if (update == null) return;

    final updateType =
        update['sessionUpdate'] as String? ?? update['type'] as String?;
    if (updateType == null || updateType.isEmpty) return;

    switch (updateType) {
      case 'agent_message_chunk':
        _emitTextOrDelta(
          _contentToText(update['content']),
          TextKind.text,
          update,
        );
      case 'agent_thought_chunk':
        _emitTextOrDelta(
          _contentToText(update['content']),
          TextKind.thinking,
          update,
        );
      case 'user_message_chunk':
        _eventsController.add(UserInputEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.acp,
          raw: update,
          sessionId: _sessionId,
          text: _contentToText(update['content']),
          isSynthetic: true,
        ));
      case 'plan':
        final entries = update['entries'] as List<dynamic>? ?? const [];
        final entryMaps = entries
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _eventsController.add(TextEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.acp,
          raw: update,
          extensions: {'acp.planEntries': entryMaps},
          sessionId: _sessionId,
          text: _planEntriesToText(entryMaps),
          kind: TextKind.plan,
        ));
      case 'tool_call':
      case 'tool_call_update':
        final toolCall =
            update['toolCall'] as Map<String, dynamic>? ?? update;
        _handleToolCall(toolCall, raw: update);
    }
  }

  void _handleServerRequest(JsonRpcServerRequest request) {
    if (!_active) return;
    final params = request.params ?? const <String, dynamic>{};

    switch (request.method) {
      case 'session/request_permission':
        _handlePermissionRequest(request, params);
      case 'fs/read_text_file':
        unawaited(_handleReadTextFile(request, params));
      case 'fs/write_text_file':
        unawaited(_handleWriteTextFile(request, params));
      default:
        _process.sendError(
          request.id,
          -32601,
          'Unsupported request: ${request.method}',
        );
    }
  }

  void _handlePermissionRequest(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) {
    final sessionId = params['sessionId'] as String? ?? _sessionId;
    if (sessionId != _sessionId) return;

    final toolCall = params['toolCall'] as Map<String, dynamic>? ?? const {};
    final options = (params['options'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    final toolName =
        toolCall['title'] as String? ?? toolCall['kind'] as String? ?? 'tool';
    final toolKind = _mapToolKind(toolCall['kind'] as String?);
    final toolInputRaw = toolCall['rawInput'];
    final toolInput = toolInputRaw is Map
        ? Map<String, dynamic>.from(toolInputRaw)
        : <String, dynamic>{};
    final toolUseId = toolCall['toolCallId'] as String?;

    _eventsController.add(PermissionRequestEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: params,
      extensions: {
        'acp.options': options,
        'acp.toolCall': toolCall,
      },
      sessionId: _sessionId,
      requestId: request.id.toString(),
      toolName: toolName,
      toolKind: toolKind,
      toolInput: toolInput,
      toolUseId: toolUseId,
    ));

    final completer = Completer<PermissionResponse>();
    final permission = PermissionRequest(
      id: request.id.toString(),
      sessionId: _sessionId,
      toolName: toolName,
      toolInput: toolInput,
      toolUseId: toolUseId,
      rawJson: params,
      completer: completer,
    );

    _permissionController.add(permission);

    completer.future.then((response) {
      if (!_active) return;
      final outcome = _mapPermissionOutcome(response, options);
      _process.sendResponse(request.id, {'outcome': outcome});
    });
  }

  Map<String, dynamic> _mapPermissionOutcome(
    PermissionResponse response,
    List<Map<String, dynamic>> options,
  ) {
    if (response is PermissionAllowResponse) {
      final optionId =
              _extractOptionId(response.updatedInput, options) ??
          _defaultOptionId(options);
      if (optionId != null) {
        return {
          'outcome': 'selected',
          'optionId': optionId,
        };
      }
    }

    return {
      'outcome': 'cancelled',
    };
  }

  String? _extractOptionId(
    Map<String, dynamic>? updatedInput,
    List<Map<String, dynamic>> options,
  ) {
    if (updatedInput == null) return null;
    final optionId = updatedInput['optionId'] ??
        updatedInput['option_id'] ??
        updatedInput['option'];
    if (optionId is String && optionId.isNotEmpty) return optionId;
    if (optionId is Map) {
      final id = optionId['optionId'] ?? optionId['id'];
      if (id is String && id.isNotEmpty) return id;
    }
    final optionIndex = updatedInput['optionIndex'];
    if (optionIndex is int &&
        optionIndex >= 0 &&
        optionIndex < options.length) {
      return _readOptionId(options[optionIndex]);
    }
    return null;
  }

  String? _defaultOptionId(List<Map<String, dynamic>> options) {
    if (options.isEmpty) return null;
    return _readOptionId(options.first);
  }

  String? _readOptionId(Map<String, dynamic> option) {
    final id =
        option['optionId'] ?? option['id'] ?? option['option_id'] ?? '';
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<void> _handleReadTextFile(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) async {
    final path = params['path'];
    if (path is! String || path.isEmpty) {
      _process.sendError(request.id, -32602, 'Missing path');
      return;
    }
    if (!p.isAbsolute(path)) {
      _process.sendError(request.id, -32602, 'Path must be absolute');
      return;
    }

    final normalized = p.normalize(p.absolute(path));
    final allowed = await _ensurePathAccess(
      'Read',
      normalized,
      {'file_path': normalized},
    );
    if (!allowed) {
      _process.sendError(request.id, -32000, 'Permission denied');
      return;
    }

    try {
      final file = File(normalized);
      if (!await file.exists()) {
        _process.sendError(request.id, -32001, 'File not found');
        return;
      }

      var content = await file.readAsString();
      final line = (params['line'] as num?)?.toInt();
      final limit = (params['limit'] as num?)?.toInt();
      if (line != null || limit != null) {
        final lines = content.split('\n');
        var start = (line ?? 1) - 1;
        if (start < 0) start = 0;
        if (start > lines.length) start = lines.length;
        var end = limit != null ? start + limit : lines.length;
        if (end > lines.length) end = lines.length;
        content = lines.sublist(start, end).join('\n');
      }

      _process.sendResponse(request.id, {'content': content});
    } catch (e) {
      _process.sendError(request.id, -32002, 'Failed to read file: $e');
    }
  }

  Future<void> _handleWriteTextFile(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) async {
    final path = params['path'];
    if (path is! String || path.isEmpty) {
      _process.sendError(request.id, -32602, 'Missing path');
      return;
    }
    if (!p.isAbsolute(path)) {
      _process.sendError(request.id, -32602, 'Path must be absolute');
      return;
    }

    final normalized = p.normalize(p.absolute(path));
    final content = params['content'] as String? ?? '';
    final allowed = await _ensurePathAccess(
      'Write',
      normalized,
      {'file_path': normalized, 'content': content},
    );
    if (!allowed) {
      _process.sendError(request.id, -32000, 'Permission denied');
      return;
    }

    try {
      final file = File(normalized);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      _process.sendResponse(request.id, {});
    } catch (e) {
      _process.sendError(request.id, -32003, 'Failed to write file: $e');
    }
  }

  Future<bool> _ensurePathAccess(
    String toolName,
    String path,
    Map<String, dynamic> toolInput,
  ) async {
    if (_isPathAllowed(path)) return true;

    final completer = Completer<PermissionResponse>();
    final permission = PermissionRequest(
      id: _nextEventId(),
      sessionId: _sessionId,
      toolName: toolName,
      toolInput: toolInput,
      completer: completer,
    );
    _permissionController.add(permission);

    final response = await completer.future;
    return response is PermissionAllowResponse;
  }

  bool _isPathAllowed(String path) {
    if (_isWithin(path, _rootDir)) return true;
    for (final allowed in _allowedDirectories) {
      if (_isWithin(path, allowed)) return true;
    }
    return false;
  }

  bool _isWithin(String path, String root) {
    if (path == root) return true;
    return p.isWithin(root, path);
  }

  void _emitTextOrDelta(
    String text,
    TextKind kind,
    Map<String, dynamic>? raw,
  ) {
    if (_includePartialMessages) {
      _emitStreamDelta(text, kind, raw);
      return;
    }
    _eventsController.add(TextEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      text: text,
      kind: kind,
    ));
  }

  void _emitStreamDelta(
    String text,
    TextKind kind,
    Map<String, dynamic>? raw,
  ) {
    const blockIndex = 0;
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.messageStart,
    ));
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.blockStart,
      blockIndex: blockIndex,
      extensions: kind == TextKind.thinking ? {'block_type': 'thinking'} : null,
    ));
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: kind == TextKind.thinking
          ? StreamDeltaKind.thinking
          : StreamDeltaKind.text,
      blockIndex: blockIndex,
      textDelta: text,
    ));
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.blockStop,
      blockIndex: blockIndex,
    ));
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.messageStop,
    ));
  }

  void _handleToolCall(
    Map<String, dynamic> toolCall, {
    Map<String, dynamic>? raw,
  }) {
    final callId = toolCall['toolCallId'] as String? ??
        toolCall['id'] as String? ??
        '';
    if (callId.isEmpty) return;

    final title = toolCall['title'] as String?;
    final kindRaw = toolCall['kind'] as String?;
    final statusRaw = toolCall['status'] as String?;
    final toolName = title ?? kindRaw ?? 'tool';
    final toolKind = _mapToolKind(kindRaw);
    final rawInput = toolCall['rawInput'];
    final input = rawInput is Map
        ? Map<String, dynamic>.from(rawInput)
        : <String, dynamic>{};
    final rawOutput = toolCall['rawOutput'];
    final locations = (toolCall['locations'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();

    final contentRaw = toolCall['content'] as Map<String, dynamic>?;
    final contentParse = contentRaw != null ? _parseToolContent(contentRaw) : null;

    final completionStatus = _mapToolStatus(statusRaw);
    if (completionStatus != null) {
      if (!_emittedToolCalls.contains(callId)) {
        _emitToolInvocation(
          callId,
          toolName,
          toolKind,
          title,
          input,
          locations,
          raw,
        );
      }
      final output = rawOutput ??
          contentParse?.output ??
          (contentRaw != null ? contentRaw : null);
      _eventsController.add(ToolCompletionEvent(
        id: _nextEventId(),
        timestamp: DateTime.now(),
        provider: BackendProvider.acp,
        raw: raw,
        extensions: contentParse?.extensions,
        callId: callId,
        sessionId: _sessionId,
        status: completionStatus,
        output: output,
        isError: completionStatus == ToolCallStatus.failed,
        content: contentParse?.content,
        locations: locations,
      ));
      return;
    }

    if (_emittedToolCalls.contains(callId)) {
      return;
    }

    _emitToolInvocation(
      callId,
      toolName,
      toolKind,
      title,
      input,
      locations,
      raw,
    );
  }

  void _emitToolInvocation(
    String callId,
    String toolName,
    ToolKind kind,
    String? title,
    Map<String, dynamic> input,
    List<String>? locations,
    Map<String, dynamic>? raw,
  ) {
    _emittedToolCalls.add(callId);
    _eventsController.add(ToolInvocationEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      callId: callId,
      sessionId: _sessionId,
      kind: kind,
      toolName: toolName,
      title: title,
      input: input,
      locations: locations,
    ));
  }

  ToolCallStatus? _mapToolStatus(String? status) {
    return switch (status) {
      'completed' => ToolCallStatus.completed,
      'failed' => ToolCallStatus.failed,
      'cancelled' => ToolCallStatus.cancelled,
      'canceled' => ToolCallStatus.cancelled,
      _ => null,
    };
  }

  ToolKind _mapToolKind(String? kind) {
    return switch (kind) {
      'read' => ToolKind.read,
      'edit' => ToolKind.edit,
      'delete' => ToolKind.delete,
      'move' => ToolKind.move,
      'search' => ToolKind.search,
      'execute' => ToolKind.execute,
      'fetch' => ToolKind.fetch,
      'browse' => ToolKind.browse,
      'think' => ToolKind.think,
      'ask' => ToolKind.ask,
      'memory' => ToolKind.memory,
      'mcp' => ToolKind.mcp,
      _ => ToolKind.other,
    };
  }

  _ToolContentParse _parseToolContent(Map<String, dynamic> content) {
    final type = content['type'] as String?;
    final extensions = <String, dynamic>{
      'acp.toolContent': content,
    };

    if (type == 'content') {
      final inner = content['content'];
      final blocks = <ContentBlock>[];
      if (inner is Map) {
        blocks.add(ContentBlock.fromJson(Map<String, dynamic>.from(inner)));
      } else if (inner is List) {
        for (final item in inner) {
          if (item is Map) {
            blocks.add(ContentBlock.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
      return _ToolContentParse(
        content: blocks.isEmpty ? null : blocks,
        output: null,
        extensions: extensions,
      );
    }

    if (type == 'diff' || type == 'terminal') {
      return _ToolContentParse(
        content: null,
        output: content,
        extensions: extensions,
      );
    }

    return _ToolContentParse(
      content: null,
      output: content,
      extensions: extensions,
    );
  }

  String _contentToText(Object? content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is Map) {
      final map = Map<String, dynamic>.from(content);
      final type = map['type'] as String?;
      if (type == 'text') {
        return map['text'] as String? ?? '';
      }
      if (type == 'thinking') {
        return map['thinking'] as String? ?? '';
      }
      if (map['text'] is String) {
        return map['text'] as String;
      }
      return jsonEncode(map);
    }
    return content.toString();
  }

  String _planEntriesToText(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return '';
    final lines = <String>[];
    for (final entry in entries) {
      final text = entry['text'] as String? ??
          entry['title'] as String? ??
          entry['description'] as String?;
      if (text != null && text.isNotEmpty) {
        lines.add(text);
      }
    }
    if (lines.isEmpty) {
      return jsonEncode(entries);
    }
    return lines.join('\n');
  }

  @override
  String? get serverModel => null;

  @override
  String? get serverReasoningEffort => null;

  void emitSessionInit({
    required Map<String, dynamic> sessionInfo,
    AcpInitializeResult? initializeResult,
  }) {
    final extensions = <String, dynamic>{};
    final capabilities = initializeResult?.agentCapabilities;
    if (capabilities != null) {
      extensions['acp.agentCapabilities'] = capabilities;
    }
    final agentInfo = initializeResult?.agentInfo;
    if (agentInfo != null) {
      extensions['acp.agentInfo'] = agentInfo;
    }
    final authMethods = initializeResult?.authMethods;
    if (authMethods != null) {
      extensions['acp.authMethods'] = authMethods;
    }
    final protocolVersion = initializeResult?.protocolVersion;
    if (protocolVersion != null) {
      extensions['acp.protocolVersion'] = protocolVersion;
    }

    final event = SessionInitEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: sessionInfo,
      extensions: extensions.isNotEmpty ? extensions : null,
      sessionId: _sessionId,
      cwd: _cwd,
    );

    Future<void>.delayed(Duration.zero, () {
      if (!_active) return;
      _eventsController.add(event);
    });
  }

  Future<void> dispose() async {
    _active = false;
    await _notificationSub?.cancel();
    await _serverRequestSub?.cancel();
    await _eventsController.close();
    await _permissionController.close();
    await _hookController.close();
  }

  String _nextEventId() {
    _eventIdCounter++;
    return 'evt-acp-${_sessionId.hashCode.toRadixString(16)}-$_eventIdCounter';
  }

  void _ensureActive() {
    if (!_active) {
      throw StateError('Session has been disposed');
    }
  }
}

class _ToolContentParse {
  const _ToolContentParse({
    required this.content,
    required this.output,
    required this.extensions,
  });

  final List<ContentBlock>? content;
  final dynamic output;
  final Map<String, dynamic> extensions;
}
