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
  final Map<String, _TerminalSession> _terminals = {};
  int _terminalCounter = 0;
  List<Map<String, dynamic>>? _configOptions;
  bool _streamingActive = false;
  TextKind? _streamingKind;
  int _streamingBlockIndex = 0;

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
    return _sendPrompt([
      {'type': 'text', 'text': message},
    ]);
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) {
    _ensureActive();
    final prompt = content.map((block) => block.toJson()).toList();
    if (prompt.isEmpty) {
      return send('');
    }
    return _sendPrompt(prompt);
  }

  Future<void> _sendPrompt(List<Map<String, dynamic>> prompt) async {
    try {
      final response = await _process.sendRequest('session/prompt', {
        'sessionId': _sessionId,
        'prompt': prompt,
      });
      _maybeEmitTurnComplete(response);
    } on JsonRpcError catch (e) {
      emitError(
        _formatPromptError(e),
        raw: {
          'error': e.toString(),
          if (e.data != null) 'data': e.data,
        },
      );
    }
  }

  void _maybeEmitTurnComplete(Map<String, dynamic> response) {
    final stopReason = response['stopReason'] ?? response['stop_reason'];
    if (stopReason is! String || stopReason.isEmpty) {
      return;
    }
    _endStreamingMessage(response);
    _eventsController.add(TurnCompleteEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: response,
      sessionId: _sessionId,
      isError: false,
      subtype: stopReason,
    ));
  }

  String _formatPromptError(JsonRpcError error) {
    final details = _formatRpcDetails(error.data);
    if (details.isEmpty) {
      return 'Agent error: ${error.message}';
    }
    return 'Agent error: ${error.message} ($details)';
  }

  String _formatRpcDetails(dynamic data) {
    if (data == null) return '';
    if (data is Map) {
      final details = data['details'];
      if (details != null) {
        return details.toString();
      }
    }
    return data.toString();
  }

  void emitError(String message, {Map<String, dynamic>? raw}) {
    if (!_active) return;
    _endStreamingMessage(raw);
    final now = DateTime.now();
    _eventsController.add(TextEvent(
      id: _nextEventId(),
      timestamp: now,
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      text: message,
      kind: TextKind.error,
    ));
    _eventsController.add(TurnCompleteEvent(
      id: _nextEventId(),
      timestamp: now,
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      isError: true,
      errors: [message],
    ));
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
  Future<void> setModel(String? model) async {
    if (!_active) return;
    if (model == null || model.isEmpty) return;
    final configId = _resolveConfigIdForCategory('model') ?? 'model';
    await setConfigOption(configId, model);
  }

  @override
  Future<void> setPermissionMode(String? mode) async {
    _ensureActive();
    if (mode == null || mode.isEmpty) {
      return;
    }
    final response = await _process.sendRequest('session/set_mode', {
      'sessionId': _sessionId,
      'modeId': mode,
    });
    _maybeEmitSessionMode(response, raw: response);
  }

  @override
  Future<void> setConfigOption(String configId, dynamic value) async {
    _ensureActive();
    if (configId.isEmpty) return;
    try {
      final response = await _process.sendRequest('session/set_config_option', {
        'sessionId': _sessionId,
        'configId': configId,
        'value': value,
      });
      _maybeEmitConfigOptions(response, raw: response);
    } catch (e) {
      SdkLogger.instance.warning(
        'ACP setConfigOption failed.',
        sessionId: _sessionId,
        data: {'configId': configId, 'value': value, 'error': e.toString()},
      );
    }
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
      case 'config_option_update':
        _maybeEmitConfigOptions(update, raw: update);
      case 'current_mode_update':
        _maybeEmitSessionMode(update, raw: update);
      case 'available_commands_update':
        _maybeEmitAvailableCommands(update, raw: update);
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
      case 'terminal/create':
        unawaited(_handleTerminalCreate(request, params));
      case 'terminal/output':
        _handleTerminalOutput(request, params);
      case 'terminal/wait_for_exit':
        unawaited(_handleTerminalWait(request, params));
      case 'terminal/kill':
        _handleTerminalKill(request, params);
      case 'terminal/release':
        _handleTerminalRelease(request, params);
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

  Future<void> _handleTerminalCreate(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) async {
    final command = params['command'];
    if (command is! String || command.isEmpty) {
      _process.sendError(request.id, -32602, 'Missing command');
      return;
    }

    final args = (params['args'] as List<dynamic>?)
            ?.map((arg) => arg.toString())
            .toList() ??
        const <String>[];
    final outputByteLimit = (params['outputByteLimit'] as num?)?.toInt();

    final cwdParam = params['cwd'] as String?;
    final cwd = cwdParam == null || cwdParam.isEmpty ? _cwd : cwdParam;
    if (!p.isAbsolute(cwd)) {
      _process.sendError(request.id, -32602, 'cwd must be absolute');
      return;
    }

    final normalized = p.normalize(p.absolute(cwd));
    final allowed = await _ensurePathAccess(
      'Bash',
      normalized,
      {
        'command': command,
        'args': args,
        'cwd': normalized,
      },
    );
    if (!allowed) {
      _process.sendError(request.id, -32000, 'Permission denied');
      return;
    }

    final envRaw = params['env'] as Map<dynamic, dynamic>?;
    final env = envRaw?.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );

    try {
      final process = await Process.start(
        command,
        args,
        workingDirectory: normalized,
        environment: env,
        runInShell: false,
      );
      final terminalId = 'term-${_terminalCounter++}';
      _terminals[terminalId] = _TerminalSession(
        id: terminalId,
        process: process,
        outputByteLimit: outputByteLimit,
      );
      _process.sendResponse(request.id, {'terminalId': terminalId});
    } catch (e) {
      _process.sendError(request.id, -32004, 'Failed to start command: $e');
    }
  }

  void _handleTerminalOutput(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) {
    final terminalId = params['terminalId'] as String?;
    final terminal = terminalId != null ? _terminals[terminalId] : null;
    if (terminal == null) {
      _process.sendError(request.id, -32004, 'Unknown terminal');
      return;
    }

    final output = terminal.readOutput();
    final response = <String, dynamic>{
      'output': output.output,
      'truncated': output.truncated,
    };
    if (terminal.exitCode != null) {
      response['exitStatus'] = terminal.exitCode;
    }
    _process.sendResponse(request.id, response);
  }

  Future<void> _handleTerminalWait(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) async {
    final terminalId = params['terminalId'] as String?;
    final terminal = terminalId != null ? _terminals[terminalId] : null;
    if (terminal == null) {
      _process.sendError(request.id, -32004, 'Unknown terminal');
      return;
    }

    final exitCode = await terminal.process.exitCode;
    terminal.exitCode ??= exitCode;
    _process.sendResponse(request.id, {'exitCode': exitCode});
  }

  void _handleTerminalKill(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) {
    final terminalId = params['terminalId'] as String?;
    final terminal = terminalId != null ? _terminals[terminalId] : null;
    if (terminal == null) {
      _process.sendError(request.id, -32004, 'Unknown terminal');
      return;
    }

    terminal.process.kill();
    _process.sendResponse(request.id, {});
  }

  void _handleTerminalRelease(
    JsonRpcServerRequest request,
    Map<String, dynamic> params,
  ) {
    final terminalId = params['terminalId'] as String?;
    final terminal = terminalId != null ? _terminals.remove(terminalId) : null;
    if (terminal == null) {
      _process.sendError(request.id, -32004, 'Unknown terminal');
      return;
    }
    terminal.dispose();
    _process.sendResponse(request.id, {});
  }

  void _emitTextOrDelta(
    String text,
    TextKind kind,
    Map<String, dynamic>? raw,
  ) {
    _emitStreamingChunk(text, kind, raw);
  }

  void _emitStreamingChunk(
    String text,
    TextKind kind,
    Map<String, dynamic>? raw,
  ) {
    if (!_streamingActive) {
      _startStreamingMessage(raw);
    }

    if (_streamingKind != kind) {
      if (_streamingKind != null) {
        _endStreamingBlock(raw);
        _streamingBlockIndex += 1;
      }
      _startStreamingBlock(kind, raw);
      _streamingKind = kind;
    }

    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: kind == TextKind.thinking
          ? StreamDeltaKind.thinking
          : StreamDeltaKind.text,
      blockIndex: _streamingBlockIndex,
      textDelta: text,
    ));
  }

  void _startStreamingMessage(Map<String, dynamic>? raw) {
    _streamingActive = true;
    _streamingBlockIndex = 0;
    _streamingKind = null;
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.messageStart,
    ));
  }

  void _startStreamingBlock(TextKind kind, Map<String, dynamic>? raw) {
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.blockStart,
      blockIndex: _streamingBlockIndex,
      extensions: kind == TextKind.thinking ? {'block_type': 'thinking'} : null,
    ));
  }

  void _endStreamingBlock(Map<String, dynamic>? raw) {
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.blockStop,
      blockIndex: _streamingBlockIndex,
    ));
  }

  void _endStreamingMessage(Map<String, dynamic>? raw) {
    if (!_streamingActive) return;
    if (_streamingKind != null) {
      _endStreamingBlock(raw);
    }
    _eventsController.add(StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      kind: StreamDeltaKind.messageStop,
    ));
    _streamingActive = false;
    _streamingKind = null;
    _streamingBlockIndex = 0;
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
    final toolName = _deriveToolName(callId, kindRaw, title);
    final toolKind = _mapToolKind(kindRaw);
    final rawInput = toolCall['rawInput'];
    final input = rawInput is Map
        ? Map<String, dynamic>.from(rawInput)
        : <String, dynamic>{};
    if (input.isEmpty && title != null && title.isNotEmpty) {
      input['title'] = title;
    }
    final rawOutput = toolCall['rawOutput'];
    final locations = (toolCall['locations'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();

    final contentRaw = toolCall['content'];
    final contentParse = _parseToolContentAny(contentRaw);

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

  String _deriveToolName(
    String callId,
    String? kindRaw,
    String? title,
  ) {
    final trimmed = callId.trim();
    if (trimmed.isNotEmpty) {
      final dashIndex = trimmed.indexOf('-');
      if (dashIndex > 0) {
        final prefix = trimmed.substring(0, dashIndex);
        if (!_isGenericToolId(prefix)) {
          return prefix;
        }
      } else {
        if (!_isGenericToolId(trimmed)) {
          return trimmed;
        }
      }
    }
    if (title != null && title.isNotEmpty && title != '.') return title;
    if (kindRaw != null && kindRaw.isNotEmpty) return kindRaw;
    return 'tool';
  }

  bool _isGenericToolId(String value) {
    return value == 'call' ||
        value == 'tool' ||
        value == 'tool_call' ||
        value == 'toolcall';
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

  _ToolContentParse? _parseToolContentAny(Object? content) {
    if (content == null) return null;
    if (content is Map) {
      return _parseToolContent(Map<String, dynamic>.from(content));
    }
    if (content is List) {
      final contentBlocks = <ContentBlock>[];
      final outputs = <dynamic>[];
      for (final item in content) {
        if (item is Map) {
          final parsed = _parseToolContent(Map<String, dynamic>.from(item));
          if (parsed.content != null) {
            contentBlocks.addAll(parsed.content!);
          }
          if (parsed.output != null) {
            outputs.add(parsed.output);
          }
        }
      }
      return _ToolContentParse(
        content: contentBlocks.isEmpty ? null : contentBlocks,
        output: outputs.isEmpty
            ? null
            : (outputs.length == 1 ? outputs.first : outputs),
        extensions: {'acp.toolContent': content},
      );
    }
    return null;
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
      _maybeEmitConfigOptions(sessionInfo, raw: sessionInfo);
      _maybeEmitSessionMode(sessionInfo, raw: sessionInfo);
    });
  }

  Future<void> dispose() async {
    _active = false;
    for (final terminal in _terminals.values) {
      terminal.process.kill();
      terminal.dispose();
    }
    _terminals.clear();
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

  void _maybeEmitConfigOptions(
    Map<String, dynamic> payload, {
    Map<String, dynamic>? raw,
  }) {
    final options = _readConfigOptions(payload);
    if (options.isEmpty) return;
    _configOptions = options;
    _eventsController.add(ConfigOptionsEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      configOptions: options,
    ));
  }

  List<Map<String, dynamic>> _readConfigOptions(
    Map<String, dynamic> payload,
  ) {
    final rawOptions = payload['configOptions'] ??
        payload['config_options'] ??
        payload['configOption'] ??
        payload['config_option'] ??
        payload['options'];
    if (rawOptions is List) {
      return rawOptions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (rawOptions is Map) {
      return [Map<String, dynamic>.from(rawOptions)];
    }
    return const [];
  }

  void _maybeEmitSessionMode(
    Map<String, dynamic> payload, {
    Map<String, dynamic>? raw,
  }) {
    final currentModeId = _readCurrentModeId(payload);
    if (currentModeId == null || currentModeId.isEmpty) return;
    final modes = _readAvailableModes(payload);
    _eventsController.add(SessionModeEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      currentModeId: currentModeId,
      availableModes: modes,
    ));
  }

  void _maybeEmitAvailableCommands(
    Map<String, dynamic> payload, {
    Map<String, dynamic>? raw,
  }) {
    final commands = _readAvailableCommands(payload);
    if (commands.isEmpty) return;
    _eventsController.add(AvailableCommandsEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.acp,
      raw: raw,
      sessionId: _sessionId,
      availableCommands: commands,
    ));
  }

  String? _readCurrentModeId(Map<String, dynamic> payload) {
    final current = payload['currentModeId'] ??
        payload['current_mode_id'] ??
        payload['currentMode'] ??
        payload['modeId'];
    return current is String ? current : null;
  }

  List<Map<String, dynamic>> _readAvailableModes(
    Map<String, dynamic> payload,
  ) {
    final rawModes = payload['availableModes'] ??
        payload['modes'] ??
        payload['modeOptions'] ??
        payload['available_modes'];
    if (rawModes is List) {
      return rawModes
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (rawModes is Map) {
      return [Map<String, dynamic>.from(rawModes)];
    }
    return const [];
  }

  List<Map<String, dynamic>> _readAvailableCommands(
    Map<String, dynamic> payload,
  ) {
    final rawCommands = payload['availableCommands'] ??
        payload['available_commands'] ??
        payload['commands'] ??
        payload['availableCommandsUpdate'];
    if (rawCommands is List) {
      return rawCommands
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (rawCommands is Map) {
      return [Map<String, dynamic>.from(rawCommands)];
    }
    return const [];
  }

  String? _resolveConfigIdForCategory(String category) {
    final options = _configOptions;
    if (options == null || options.isEmpty) return null;
    String? fallback;
    for (final option in options) {
      final id = _readConfigOptionId(option);
      if (id == null) continue;
      if (id == category) return id;
      final optionCategory = option['category'] ?? option['group'];
      if (optionCategory is String && optionCategory == category) {
        return id;
      }
      final name = option['name'];
      if (fallback == null && name is String && name.toLowerCase() == category) {
        fallback = id;
      }
    }
    return fallback;
  }

  String? _readConfigOptionId(Map<String, dynamic> option) {
    final id = option['configId'] ?? option['id'];
    return id is String && id.isNotEmpty ? id : null;
  }
}

class _TerminalSession {
  _TerminalSession({
    required this.id,
    required this.process,
    int? outputByteLimit,
  }) : _outputByteLimit = outputByteLimit {
    _stdoutSub = process.stdout.listen(_appendOutput);
    _stderrSub = process.stderr.listen(_appendOutput);
    process.exitCode.then((code) {
      exitCode ??= code;
    });
  }

  final String id;
  final Process process;
  final int? _outputByteLimit;
  final List<int> _buffer = <int>[];
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  int? exitCode;

  void _appendOutput(List<int> data) {
    if (data.isEmpty) return;
    _buffer.addAll(data);
  }

  _TerminalOutput readOutput() {
    if (_buffer.isEmpty) {
      return const _TerminalOutput(output: '', truncated: false);
    }

    final limit = _outputByteLimit;
    if (limit != null && limit <= 0) {
      final hadOutput = _buffer.isNotEmpty;
      _buffer.clear();
      return _TerminalOutput(output: '', truncated: hadOutput);
    }

    if (limit == null || _buffer.length <= limit) {
      final output = utf8.decode(_buffer, allowMalformed: true);
      _buffer.clear();
      return _TerminalOutput(output: output, truncated: false);
    }

    final chunk = _buffer.sublist(0, limit);
    _buffer.removeRange(0, limit);
    final output = utf8.decode(chunk, allowMalformed: true);
    return _TerminalOutput(output: output, truncated: true);
  }

  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
  }
}

class _TerminalOutput {
  const _TerminalOutput({
    required this.output,
    required this.truncated,
  });

  final String output;
  final bool truncated;
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
