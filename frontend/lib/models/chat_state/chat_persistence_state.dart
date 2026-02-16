part of 'package:cc_insights_v2/models/chat.dart';

class ChatPersistenceState {
  ChatPersistenceState._(this._chat);

  static const int _maxRetryAttempts = 3;
  static const Duration _baseRetryDelay = Duration(milliseconds: 50);

  final _ChatCore _chat;
  final Map<String, Future<void>> _writeQueues = {};

  Timer? _metaSaveTimer;
  String? _projectRoot;
  String? _projectId;

  String? get projectId => _projectId;

  @visibleForTesting
  PersistenceService get persistenceService => _chat.persistenceService;

  @visibleForTesting
  set persistenceService(PersistenceService service) {
    _chat.persistenceService = service;
  }

  Future<void> initPersistence(String projectId, {String? projectRoot}) async {
    _projectId = projectId;
    _projectRoot = projectRoot;
    await _chat.persistenceService.ensureDirectories(projectId);
  }

  void persistRename(String newName) {
    final projectRoot = _projectRoot;
    final worktreePath = _chat._worktreePath;
    if (projectRoot == null || worktreePath == null) {
      return;
    }

    unawaited(
      _enqueue(
        _indexQueueKey(projectRoot, worktreePath),
        () => _runWithRetry(
          operation: 'rename chat in index',
          action: () => _chat.persistenceService.renameChatInIndex(
            projectRoot: projectRoot,
            worktreePath: worktreePath,
            chatId: _chat._data.id,
            newName: newName,
          ),
        ),
      ).catchError((Object e, StackTrace stack) {
        LogService.instance.logUnhandledException(e, stack);
      }),
    );
  }

  Future<void> persistEntry(OutputEntry entry) async {
    final projectId = _projectId;
    if (projectId == null) return;
    await _appendEntry(
      projectId: projectId,
      entry: entry,
      failureMessage: 'Failed to persist entry',
    );
  }

  void persistStreamingEntry(OutputEntry entry) {
    unawaited(persistEntry(entry));
  }

  void persistToolResult(String toolUseId, dynamic result, bool isError) {
    final projectId = _projectId;
    if (projectId == null) return;

    final entry = ToolResultEntry(
      timestamp: DateTime.now(),
      toolUseId: toolUseId,
      result: result,
      isError: isError,
    );

    unawaited(
      _appendEntry(
        projectId: projectId,
        entry: entry,
        failureMessage: 'Failed to persist tool result',
      ),
    );
  }

  void scheduleMetaSave() {
    if (_projectId == null) return;
    _metaSaveTimer?.cancel();
    _metaSaveTimer = Timer(const Duration(seconds: 1), () {
      unawaited(saveMeta());
    });
  }

  void markStarted() {
    if (_chat._hasStarted) return;
    _chat._hasStarted = true;
    scheduleMetaSave();
  }

  Future<void> saveMeta() async {
    final projectId = _projectId;
    if (projectId == null) return;
    try {
      final meta = ChatMeta(
        model: _chat._model.id,
        backendType: _chat._backendTypeValue,
        hasStarted: _chat._hasStarted,
        permissionMode: _chat._securityConfig is sdk.ClaudeSecurityConfig
            ? (_chat._securityConfig as sdk.ClaudeSecurityConfig)
                  .permissionMode
                  .value
            : 'default',
        createdAt: _chat._data.createdAt ?? DateTime.now(),
        lastActiveAt: DateTime.now(),
        context: ContextInfo(
          currentTokens: _chat._contextTracker.currentTokens,
          maxTokens: _chat._contextTracker.maxTokens,
          autocompactBufferPercent:
              _chat._contextTracker.autocompactBufferPercent,
        ),
        usage: _chat._cumulativeUsage,
        modelUsage: _chat._modelUsage,
        timing: _chat._timingStats,
        codexSandboxMode: _chat._securityConfig is sdk.CodexSecurityConfig
            ? (_chat._securityConfig as sdk.CodexSecurityConfig)
                  .sandboxMode
                  .wireValue
            : null,
        codexApprovalPolicy: _chat._securityConfig is sdk.CodexSecurityConfig
            ? (_chat._securityConfig as sdk.CodexSecurityConfig)
                  .approvalPolicy
                  .wireValue
            : null,
        codexWorkspaceWriteOptions:
            _chat._securityConfig is sdk.CodexSecurityConfig
            ? (_chat._securityConfig as sdk.CodexSecurityConfig)
                  .workspaceWriteOptions
                  ?.toJson()
            : null,
        codexWebSearch: _chat._securityConfig is sdk.CodexSecurityConfig
            ? (_chat._securityConfig as sdk.CodexSecurityConfig)
                  .webSearch
                  ?.wireValue
            : null,
        agentId: _chat._agentId,
        backendName: _chat.agentName,
      );

      await _enqueue(
        _metaQueueKey(projectId),
        () => _runWithRetry(
          operation: 'save chat meta',
          action: () => _chat.persistenceService.saveChatMeta(
            projectId,
            _chat._data.id,
            meta,
          ),
        ),
      );
    } catch (e, stack) {
      LogService.instance.error(
        'ChatPersistenceState',
        'Failed to save chat meta: $e',
        meta: {
          'chatId': _chat._data.id,
          'projectId': projectId,
          'operation': 'saveMeta',
          'stack': stack.toString(),
        },
      );
    }
  }

  void persistSessionId(String? sessionId) {
    final projectRoot = _projectRoot;
    final worktreePath = _chat._worktreePath;
    if (projectRoot == null || worktreePath == null) {
      developer.log(
        'Cannot persist session ID: projectRoot or worktreePath is null',
        name: 'Chat',
        level: 900,
      );
      return;
    }

    unawaited(
      _enqueue(
        _indexQueueKey(projectRoot, worktreePath),
        () => _runWithRetry(
          operation: 'update chat session ID in index',
          action: () => _chat.persistenceService.updateChatSessionId(
            projectRoot: projectRoot,
            worktreePath: worktreePath,
            chatId: _chat._data.id,
            sessionId: sessionId,
          ),
        ),
      ).catchError((Object e, StackTrace stack) {
        LogService.instance.logUnhandledException(e, stack);
      }),
    );
  }

  void dispose() {
    _metaSaveTimer?.cancel();
    _metaSaveTimer = null;
  }

  Future<void> _appendEntry({
    required String projectId,
    required OutputEntry entry,
    required String failureMessage,
  }) async {
    try {
      await _enqueue(
        _entryQueueKey(projectId),
        () => _runWithRetry(
          operation: 'append chat entry',
          action: () => _chat.persistenceService.appendChatEntry(
            projectId,
            _chat._data.id,
            entry,
          ),
        ),
      );
    } catch (e, stack) {
      LogService.instance.error(
        'ChatPersistenceState',
        '$failureMessage: $e',
        meta: {
          'chatId': _chat._data.id,
          'projectId': projectId,
          'operation': 'appendEntry',
          'stack': stack.toString(),
        },
      );
    }
  }

  Future<void> _enqueue(String queueKey, Future<void> Function() write) {
    final previous = _writeQueues[queueKey] ?? Future<void>.value();
    final current = previous.then((_) => write());
    _writeQueues[queueKey] = current.catchError((Object e, StackTrace stack) {
      developer.log(
        'Persistence queue error for $queueKey (continuing chain)',
        name: 'ChatPersistenceState',
        error: e,
        stackTrace: stack,
        level: 1000,
      );
    });
    return current;
  }

  Future<void> _runWithRetry({
    required String operation,
    required Future<void> Function() action,
  }) async {
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
      try {
        await action();
        return;
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;
        if (attempt >= _maxRetryAttempts) {
          break;
        }
        developer.log(
          'Persistence $operation failed (attempt $attempt/$_maxRetryAttempts), retrying',
          name: 'ChatPersistenceState',
          error: e,
          stackTrace: stack,
          level: 900,
        );
        await Future<void>.delayed(
          Duration(milliseconds: _baseRetryDelay.inMilliseconds * attempt),
        );
      }
    }

    if (lastError != null && lastStack != null) {
      Error.throwWithStackTrace(lastError, lastStack);
    }
  }

  String _entryQueueKey(String projectId) =>
      'entry:$projectId:${_chat._data.id}';

  String _metaQueueKey(String projectId) => 'meta:$projectId:${_chat._data.id}';

  String _indexQueueKey(String projectRoot, String worktreePath) =>
      'index:$projectRoot:$worktreePath:${_chat._data.id}';
}
