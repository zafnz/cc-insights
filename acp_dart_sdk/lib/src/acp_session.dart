import 'dart:async';
import 'dart:convert';

import 'package:agent_sdk_core/agent_sdk_core.dart';

import 'acp_process.dart';
import 'json_rpc.dart';

/// Session placeholder for ACP agents.
class AcpSession implements AgentSession {
  AcpSession({
    required AcpProcess process,
    required String sessionId,
    required String cwd,
    bool includePartialMessages = false,
  })  : _process = process,
        _sessionId = sessionId,
        _cwd = cwd,
        _includePartialMessages = includePartialMessages {
    _notificationSub = _process.notifications.listen(_handleNotification);
  }

  final AcpProcess _process;
  final String _sessionId;
  final String _cwd;
  final bool _includePartialMessages;

  int _eventIdCounter = 0;
  bool _active = true;
  StreamSubscription<JsonRpcNotification>? _notificationSub;

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
    }
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
