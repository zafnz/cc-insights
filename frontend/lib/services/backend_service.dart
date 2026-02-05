import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

import '../models/chat_model.dart';
import 'log_service.dart' as app_log;

/// Service for managing the Claude backend lifecycle.
///
/// This service handles spawning and disposing the Claude CLI backend process,
/// and provides session creation capabilities for chats.
///
/// The backend communicates directly with the Claude CLI using the stream-json
/// protocol. Requires the `claude` CLI to be installed and available in PATH,
/// or configured via the `CLAUDE_CODE_PATH` environment variable.
///
/// Usage:
/// ```dart
/// final backendService = BackendService();
/// await backendService.start();
///
/// // Check if ready
/// if (backendService.isReady) {
///   final session = await backendService.createSession(
///     prompt: 'Hello',
///     cwd: '/path/to/project',
///   );
/// }
///
/// // Dispose when done
/// backendService.dispose();
/// ```
class BackendService extends ChangeNotifier {
  final Map<BackendType, AgentBackend> _backends = {};
  final Map<BackendType, StreamSubscription<BackendError>>
      _errorSubscriptions = {};
  final Map<BackendType, StreamSubscription<LogEntry>> _logSubscriptions = {};
  final Map<BackendType, String?> _errors = {};
  final Set<BackendType> _starting = {};
  final Set<BackendType> _modelListLoading = {};

  BackendType? _backendType;

  /// Whether the backend is ready to accept session creation requests.
  bool get isReady {
    final backendType = _backendType;
    if (backendType == null) return false;
    return _backends.containsKey(backendType) &&
        _errors[backendType] == null;
  }

  /// Whether the backend is currently starting up.
  bool get isStarting {
    final backendType = _backendType;
    if (backendType == null) return false;
    return _starting.contains(backendType);
  }

  /// The current error message, if any.
  String? get error {
    final backendType = _backendType;
    if (backendType == null) return null;
    return _errors[backendType];
  }

  /// The currently active backend type, if any.
  BackendType? get backendType => _backendType;

  /// Whether a specific backend is ready.
  bool isReadyFor(BackendType type) {
    return _backends.containsKey(type) && _errors[type] == null;
  }

  /// Whether a specific backend is currently starting.
  bool isStartingFor(BackendType type) => _starting.contains(type);

  /// Whether model list loading is in progress for a backend.
  bool isModelListLoadingFor(BackendType type) =>
      _modelListLoading.contains(type);

  /// Error message for a specific backend, if any.
  String? errorFor(BackendType type) => _errors[type];

  /// Capabilities of the currently active backend.
  ///
  /// Returns an empty [BackendCapabilities] (all false) if no backend is started.
  BackendCapabilities get capabilities {
    final bt = _backendType;
    if (bt == null) return const BackendCapabilities();
    return _backends[bt]?.capabilities ?? const BackendCapabilities();
  }

  /// Capabilities of a specific backend type.
  ///
  /// Returns an empty [BackendCapabilities] (all false) if that backend is not started.
  BackendCapabilities capabilitiesFor(BackendType type) {
    return _backends[type]?.capabilities ?? const BackendCapabilities();
  }

  /// Creates a backend instance. Override in tests to inject fakes.
  @visibleForTesting
  Future<AgentBackend> createBackend({
    required BackendType type,
    String? executablePath,
  }) {
    return BackendFactory.create(type: type, executablePath: executablePath);
  }

  /// Starts the backend.
  ///
  /// This spawns a direct connection to the Claude CLI using the stream-json
  /// protocol. The CLI path can be configured via the `CLAUDE_CODE_PATH`
  /// environment variable, otherwise it defaults to `claude` in PATH.
  ///
  /// This method is idempotent - calling it while already started or starting
  /// will return immediately without doing anything.
  ///
  /// After calling this method, check [isReady] to verify the backend started
  /// successfully, or [error] to see what went wrong.
  Future<void> start({
    BackendType type = BackendType.directCli,
    String? executablePath,
  }) async {
    _backendType = type;
    final existing = _backends[type];
    if (existing != null) {
      unawaited(_refreshModelsIfSupported(type, existing));
      notifyListeners();
      return;
    }

    if (_starting.contains(type)) {
      return;
    }

    _starting.add(type);
    _errors[type] = null;
    notifyListeners();

    try {
      final backend = await createBackend(type: type, executablePath: executablePath);
      _backends[type] = backend;

      // Monitor backend errors
      _errorSubscriptions[type] = backend.errors.listen((error) {
        _errors[type] = error.toString();
        notifyListeners();
      });

      // Forward backend log entries to LogService
      _logSubscriptions[type] = backend.logEntries.listen((entry) {
        // Map SDK log level to app log level
        final level = switch (entry.level) {
          LogLevel.debug => app_log.LogLevel.debug,
          LogLevel.info => app_log.LogLevel.info,
          LogLevel.warning => app_log.LogLevel.warn,
          LogLevel.error => app_log.LogLevel.error,
        };

        // Determine log type based on direction
        final logType = switch (entry.direction) {
          LogDirection.stdin => 'send',
          LogDirection.stdout => 'recv',
          LogDirection.stderr => 'stderr',
          LogDirection.internal => 'internal',
          null => 'message',
        };

        // Build the message payload with structured data
        final message = <String, dynamic>{
          'backend': type.name,
        };
        if (entry.direction != null) {
          message['direction'] = entry.direction!.name;
        }
        if (entry.data != null) {
          message['content'] = entry.data;
        } else if (entry.text != null) {
          message['text'] = entry.text;
        } else {
          message['text'] = entry.message;
        }

        app_log.LogService.instance.log(
          service: type == BackendType.codex ? 'Codex' : 'ClaudeCLI',
          level: level,
          type: logType,
          message: message,
        );
      });

      unawaited(_refreshModelsIfSupported(type, backend));
    } catch (e) {
      _errors[type] = e.toString();
      _backends.remove(type);
    } finally {
      _starting.remove(type);
      notifyListeners();
    }
  }

  /// Switches the backend type if possible.
  ///
  /// Disposes any previously active backend that is not the target [type].
  Future<void> switchBackend({
    required BackendType type,
    String? executablePath,
  }) async {
    // Dispose backends that are not the target type.
    final toRemove = _backends.keys.where((k) => k != type).toList();
    for (final key in toRemove) {
      await _disposeBackend(key);
    }
    await start(type: type, executablePath: executablePath);
  }

  Future<void> _refreshModelsIfSupported(
    BackendType type,
    AgentBackend backend,
  ) async {
    if (backend is! ModelListingBackend) return;

    final didStartLoading = _modelListLoading.add(type);
    if (didStartLoading) {
      notifyListeners();
    }

    try {
      final modelBackend = backend as ModelListingBackend;
      final models = await modelBackend.listModels();
      if (models.isEmpty) return;

      if (type == BackendType.codex) {
        final mapped = models
            .where((model) => model.value.trim().isNotEmpty)
            .map((model) {
          final label = model.displayName.trim().isEmpty
              ? model.value
              : model.displayName.trim();
          return ChatModel(
            id: model.value.trim(),
            label: label,
            backend: BackendType.codex,
          );
        }).toList();

        if (mapped.isNotEmpty) {
          ChatModelCatalog.updateCodexModels(mapped);
        }
      }
    } catch (e) {
      debugPrint('Failed to refresh model list: $e');
    } finally {
      _modelListLoading.remove(type);
      notifyListeners();
    }
  }

  /// Creates a session for a specific backend type.
  Future<AgentSession> createSessionForBackend({
    required BackendType type,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    String? executablePath,
  }) async {
    await start(type: type, executablePath: executablePath);
    final backend = _backends[type];
    if (backend == null) {
      throw StateError('Backend not started. Call start() first.');
    }
    return backend.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
    );
  }

  /// Creates a new Claude session.
  ///
  /// The backend must be started and ready before calling this method.
  ///
  /// Parameters:
  /// - [prompt]: The initial prompt to start the session with.
  /// - [cwd]: The working directory for the session (typically the worktree root).
  /// - [options]: Optional session configuration (model, permission mode, etc.).
  /// - [content]: Optional content blocks (text + images) for the initial message.
  ///   If provided, this takes precedence over [prompt].
  ///
  /// Throws [StateError] if the backend is not started.
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    final backendType = _backendType;
    if (backendType == null) {
      throw StateError('Backend not started. Call start() first.');
    }
    final backend = _backends[backendType];
    if (backend == null) {
      throw StateError('Backend not started. Call start() first.');
    }
    return backend.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
    );
  }

  /// Disposes a single backend and its associated subscriptions.
  Future<void> _disposeBackend(BackendType type) async {
    await _errorSubscriptions.remove(type)?.cancel();
    await _logSubscriptions.remove(type)?.cancel();
    final backend = _backends.remove(type);
    await backend?.dispose();
    _errors.remove(type);
    _starting.remove(type);
  }

  /// Disposes of the backend service and terminates the subprocess.
  ///
  /// This should be called when the app is shutting down to ensure
  /// the backend process is properly terminated.
  @override
  void dispose() {
    for (final sub in _errorSubscriptions.values) {
      sub.cancel();
    }
    _errorSubscriptions.clear();
    for (final sub in _logSubscriptions.values) {
      sub.cancel();
    }
    _logSubscriptions.clear();
    for (final backend in _backends.values) {
      backend.dispose();
    }
    _backends.clear();
    _errors.clear();
    _starting.clear();
    _backendType = null;
    super.dispose();
  }
}
