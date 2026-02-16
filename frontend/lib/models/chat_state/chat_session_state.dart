part of 'package:cc_insights_v2/models/chat.dart';

class ChatSessionState extends ChangeNotifier {
  ChatSessionState._(this._chat);

  final _ChatCore _chat;

  bool get hasActiveSession => _chat.hasActiveSession;
  bool get isWorking => _chat.isWorking;
  bool get isCompacting => _chat.isCompacting;
  Stopwatch? get workingStopwatch => _chat.workingStopwatch;
  String? get lastSessionId => _chat.lastSessionId;
  bool get hasStarted => _chat.hasStarted;
  sdk.BackendCapabilities get capabilities => _chat.capabilities;
  SessionPhase get sessionPhase => _chat.sessionPhase;

  Future<void> start({
    required BackendService backend,
    required EventHandler eventHandler,
    required String prompt,
    List<AttachedImage> images = const [],
    InternalToolsService? internalToolsService,
    String? systemPromptAppend,
  }) {
    return _chat.startSession(
      backend: backend,
      eventHandler: eventHandler,
      prompt: prompt,
      images: images,
      internalToolsService: internalToolsService,
      systemPromptAppend: systemPromptAppend,
    );
  }

  Future<void> sendMessage(
    String text, {
    List<AttachedImage> images = const [],
    DisplayFormat displayFormat = DisplayFormat.plain,
  }) {
    return _chat.sendMessage(
      text,
      images: images,
      displayFormat: displayFormat,
    );
  }

  Future<void> stop() => _chat.stopSession();

  Future<void> interrupt() => _chat.interrupt();

  void setWorking(bool working) => _chat.setWorking(working);

  void setCompacting(bool compacting) => _chat.setCompacting(compacting);

  void pauseStopwatchForPermissionWait() {
    final stopwatch = _chat._workingStopwatch;
    if (stopwatch != null && stopwatch.isRunning) {
      stopwatch.stop();
    }
  }

  void resumeStopwatchAfterPermissionWait() {
    final stopwatch = _chat._workingStopwatch;
    if (_chat._isWorking && stopwatch != null && !stopwatch.isRunning) {
      stopwatch.start();
    }
  }

  void clear() => _chat.clearSession();

  Future<void> reset() => _chat.resetSession();

  @visibleForTesting
  void setSession(sdk.AgentSession? session) => _chat.setSession(session);

  @visibleForTesting
  void setTransport(sdk.EventTransport? transport) {
    _chat.setTransport(transport);
  }

  @visibleForTesting
  void setHasActiveSessionForTesting(bool hasSession) {
    _chat.setHasActiveSessionForTesting(hasSession);
  }

  void setLastSessionIdFromRestore(String? sessionId) {
    _chat.setLastSessionIdFromRestore(sessionId);
  }

  void setHasStartedFromRestore(bool hasStarted) {
    _chat.setHasStartedFromRestore(hasStarted);
  }

  /// Triggers a session-state rebuild when permission queue changes affect the
  /// working indicator but not core session fields.
  void notifyPermissionQueueChanged() => notifyListeners();
}
