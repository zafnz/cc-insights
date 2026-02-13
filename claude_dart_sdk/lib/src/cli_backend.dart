import 'dart:async';

import 'backend_interface.dart';
import 'backend_type.dart';
import 'cli_process.dart';
import 'cli_session.dart';
import 'internal_tool_registry.dart';
import 'sdk_logger.dart';
import 'types/callbacks.dart';
import 'types/content_blocks.dart';
import 'types/errors.dart';
import 'types/insights_events.dart';
import 'types/permission_suggestion.dart';
import 'types/session_options.dart';

/// Diagnostic trace — only prints when [SdkLogger.debugEnabled] is true.
void _t(String tag, String msg) => SdkLogger.instance.trace(tag, msg);

/// Backend that communicates directly with claude-cli.
///
/// This class implements [AgentBackend] and manages the lifecycle of
/// claude-cli processes for each session, spawning a separate
/// claude-cli process for each session.
///
/// Example:
/// ```dart
/// final backend = ClaudeCliBackend();
/// final session = await backend.createSession(
///   prompt: 'Hello!',
///   cwd: '/my/project',
/// );
/// ```
class ClaudeCliBackend implements AgentBackend {
  /// Create a new CLI backend.
  ///
  /// [executablePath] - Path to claude-cli executable.
  ///   Defaults to `CLAUDE_CODE_PATH` environment variable or 'claude'.
  ClaudeCliBackend({String? executablePath}) : _executablePath = executablePath;

  /// Register this backend with the [BackendRegistry].
  ///
  /// Call this once during app initialization to make
  /// [BackendType.directCli] available via [BackendRegistry.create].
  static void register() {
    BackendRegistry.register(
      BackendType.directCli,
      ({
        String? executablePath,
        List<String> arguments = const [],
        String? workingDirectory,
      }) async {
        return ClaudeCliBackend(executablePath: executablePath);
      },
    );
  }

  final String? _executablePath;

  final _sessions = <String, _CliSessionAdapter>{};
  final _errorsController = StreamController<BackendError>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  StreamSubscription<LogEntry>? _loggerSubscription;

  bool _disposed = false;

  /// Access to the SDK logger for programmatic configuration.
  ///
  /// Use this to enable/disable debug logging:
  /// ```dart
  /// backend.logger.debugEnabled = true;
  /// ```
  SdkLogger get logger => SdkLogger.instance;

  @override
  BackendCapabilities get capabilities => const BackendCapabilities(
        supportsPermissionModeChange: true,
        supportsModelChange: true,
      );

  @override
  bool get isRunning => !_disposed;

  @override
  Stream<BackendError> get errors => _errorsController.stream;

  @override
  Stream<String> get logs {
    // Ensure we're forwarding SDK logger entries
    _loggerSubscription ??= SdkLogger.instance.logs.listen((entry) {
      if (!_disposed) {
        _logsController.add(entry.toString());
      }
    });
    return _logsController.stream;
  }

  @override
  Stream<LogEntry> get logEntries => SdkLogger.instance.logs;

  @override
  List<AgentSession> get sessions => List.unmodifiable(_sessions.values);

  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    InternalToolRegistry? registry,
  }) async {
    _t('ClaudeCliBackend', 'createSession called');
    _t('ClaudeCliBackend', '  cwd: $cwd');
    _t('ClaudeCliBackend', '  prompt: ${prompt.length > 80 ? '${prompt.substring(0, 80)}...' : prompt}');
    _t('ClaudeCliBackend', '  model: ${options?.model ?? 'default'}');
    _t('ClaudeCliBackend', '  resume: ${options?.resume ?? 'none'}');
    _t('ClaudeCliBackend', '  disposed: $_disposed');

    if (_disposed) {
      _t('ClaudeCliBackend', 'ERROR: Backend has been disposed');
      throw const BackendProcessError('Backend has been disposed');
    }

    // Validate options and log warnings for unsupported fields
    if (options != null) {
      final validation = options.validateForCli();
      for (final warning in validation.warnings) {
        _t('ClaudeCliBackend', 'WARN: $warning');
        SdkLogger.instance.warning(warning);
      }
    }

    try {
      // Create the CLI session
      _t('ClaudeCliBackend', 'Creating CliSession...');
      final cliSession = await CliSession.create(
        cwd: cwd,
        prompt: prompt,
        options: options,
        content: content,
        registry: registry,
        processConfig: _executablePath != null
            ? CliProcessConfig(
                executablePath: _executablePath,
                cwd: cwd,
                model: options?.model,
                permissionMode: options?.permissionMode,
                settingSources: options?.settingSources
                    ?.map(SettingSource.fromString)
                    .toList(),
                maxTurns: options?.maxTurns,
                maxBudgetUsd: options?.maxBudgetUsd,
                resume: options?.resume,
                includePartialMessages:
                    options?.includePartialMessages ?? false,
              )
            : null,
      );

      _t('ClaudeCliBackend', 'CliSession created, wrapping in adapter (sessionId=${cliSession.sessionId})');

      // Wrap it in an adapter that implements AgentSession
      final adapter = _CliSessionAdapter(
        cliSession: cliSession,
        backend: this,
      );

      _sessions[cliSession.sessionId] = adapter;
      _t('ClaudeCliBackend', 'Session tracked (total sessions: ${_sessions.length})');

      // Monitor for session errors and completion
      _setupSessionMonitoring(adapter);

      return adapter;
    } catch (e) {
      _t('ClaudeCliBackend', 'ERROR creating session: $e');
      final error = e is BackendError
          ? e
          : BackendError(
              'Failed to create session: $e',
              code: 'SESSION_CREATE_ERROR',
            );
      _errorsController.add(error);
      rethrow;
    }
  }

  void _setupSessionMonitoring(_CliSessionAdapter adapter) {
    _t('ClaudeCliBackend', 'Setting up monitoring for session ${adapter.sessionId}');

    // Note: stderr is now logged via SdkLogger in CliProcess
    // We still listen for errors here
    adapter._cliSession.process.stderr.listen(
      (_) {
        // Stderr lines are logged via SdkLogger.logStderr in CliProcess
      },
      onError: (Object error) {
        _t('ClaudeCliBackend', 'stderr stream error: $error (session=${adapter.sessionId})');
        if (!_disposed) {
          SdkLogger.instance.error(
            'stderr stream error: $error',
            sessionId: adapter.sessionId,
          );
        }
      },
    );

    // Monitor for session termination
    adapter._cliSession.process.exitCode.then((exitCode) {
      _t('ClaudeCliBackend', 'Session ${adapter.sessionId} process exited with code $exitCode');
      if (!_disposed) {
        _sessions.remove(adapter.sessionId);
        // Only report as error if:
        // - Exit code is non-zero AND
        // - Session wasn't intentionally killed (disposed)
        // Note: Exit code -15 is SIGTERM, which is expected when kill() is called
        if (exitCode != 0 && !adapter._disposed) {
          _t('ClaudeCliBackend', 'ERROR: Session ${adapter.sessionId} unexpected exit code $exitCode');
          _errorsController.add(BackendError(
            'Session ${adapter.sessionId} exited with code $exitCode',
            code: 'SESSION_EXIT',
          ));
        }
      }
    });
  }

  void _removeSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Kill all sessions
    final sessionsCopy = List<_CliSessionAdapter>.from(_sessions.values);
    for (final session in sessionsCopy) {
      await session.kill();
    }
    _sessions.clear();

    await _loggerSubscription?.cancel();
    await _errorsController.close();
    await _logsController.close();
  }
}

/// Adapter that wraps [CliSession] to implement [AgentSession].
///
/// This class adapts the CLI-specific types (like [CliPermissionRequest])
/// to the SDK-generic types (like [PermissionRequest]).
class _CliSessionAdapter implements AgentSession {
  _CliSessionAdapter({
    required CliSession cliSession,
    required ClaudeCliBackend backend,
  })  : _cliSession = cliSession,
        _backend = backend {
    _setupStreams();
  }

  final CliSession _cliSession;
  final ClaudeCliBackend _backend;

  final _permissionRequestsController =
      StreamController<PermissionRequest>.broadcast();
  final _hookRequestsController = StreamController<HookRequest>.broadcast();

  bool _disposed = false;

  @override
  String get sessionId => _cliSession.sessionId;

  @override
  String? get resolvedSessionId => _cliSession.sessionId;

  @override
  bool get isActive => !_disposed && _cliSession.isActive;

  @override
  Stream<InsightsEvent> get events => _cliSession.events;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  @override
  Stream<HookRequest> get hookRequests => _hookRequestsController.stream;

  void _setupStreams() {
    _t('CliSessionAdapter', 'Setting up permission/message stream adapters for session $sessionId');

    // Adapt CliPermissionRequest to PermissionRequest
    _cliSession.permissionRequests.listen(
      (cliRequest) {
        if (_disposed) return;
        _t('CliSessionAdapter', 'Permission request: tool=${cliRequest.toolName} requestId=${cliRequest.requestId}');

        final completer = Completer<PermissionResponse>();
        final request = PermissionRequest(
          id: cliRequest.requestId,
          sessionId: sessionId,
          toolName: cliRequest.toolName,
          toolInput: cliRequest.input,
          suggestions: cliRequest.suggestions
              ?.map((s) => s.toJson())
              .toList(),
          toolUseId: cliRequest.toolUseId,
          blockedPath: cliRequest.blockedPath,
          completer: completer,
        );

        _permissionRequestsController.add(request);

        // Handle the response
        completer.future.then((response) {
          if (cliRequest.responded) return;

          switch (response) {
            case PermissionAllowResponse():
              // Convert List<dynamic>? to List<PermissionSuggestion>?
              List<PermissionSuggestion>? permissions;
              if (response.updatedPermissions != null) {
                permissions = response.updatedPermissions!
                    .whereType<Map<String, dynamic>>()
                    .map((json) => PermissionSuggestion.fromJson(json))
                    .toList();
              }
              cliRequest.allow(
                updatedInput: response.updatedInput,
                updatedPermissions: permissions,
              );
            case PermissionDenyResponse():
              cliRequest.deny(response.message);
          }
        });
      },
      onError: (Object error) {
        if (!_disposed) {
          _permissionRequestsController.addError(error);
        }
      },
      onDone: () {
        if (!_disposed) {
          _permissionRequestsController.close();
        }
      },
    );
  }

  @override
  Future<void> send(String message) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    await _cliSession.send(message);
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    await _cliSession.sendWithContent(content);
  }

  @override
  Future<void> interrupt() async {
    if (_disposed) return;
    await _cliSession.interrupt();
  }

  @override
  Future<void> kill() async {
    if (_disposed) return;
    _disposed = true;

    await _cliSession.kill();
    _backend._removeSession(sessionId);

    await _permissionRequestsController.close();
    await _hookRequestsController.close();
  }

  @override
  Future<void> setModel(String? model) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    await _cliSession.setModel(model);
  }

  @override
  Future<void> setPermissionMode(String? mode) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    await _cliSession.setPermissionMode(mode);
  }

  @override
  Future<void> setConfigOption(String configId, dynamic value) async {
    if (_disposed) {
      throw StateError('Session has been disposed');
    }
    await _cliSession.setConfigOption(configId, value);
  }

  @override
  Future<void> setReasoningEffort(String? effort) async {
    throw UnsupportedError(
      'Claude CLI does not support reasoning effort. '
      'Check BackendCapabilities.supportsReasoningEffort before calling.',
    );
  }

  @override
  String? get serverModel => null;

  @override
  String? get serverReasoningEffort => null;
}
