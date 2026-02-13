import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:codex_sdk/codex_sdk.dart';
import 'package:flutter/foundation.dart';

import '../models/chat_model.dart';
import 'runtime_config.dart';

/// Diagnostic trace — only prints when [SdkLogger.debugEnabled] is true.
void _t(String tag, String msg) => SdkLogger.instance.trace(tag, msg);

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
  final Map<BackendType, String?> _errors = {};
  final Map<BackendType, bool> _errorIsAgent = {};
  final Set<BackendType> _starting = {};
  final Set<BackendType> _modelListLoading = {};

  final _rateLimitsController =
      StreamController<RateLimitUpdateEvent>.broadcast();
  StreamSubscription<RateLimitUpdateEvent>? _rateLimitSub;

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

  /// Whether the current error came from an agent response.
  bool get isAgentError {
    final backendType = _backendType;
    if (backendType == null) return false;
    return _errorIsAgent[backendType] ?? false;
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

  /// Whether a specific backend error came from an agent response.
  bool isAgentErrorFor(BackendType type) => _errorIsAgent[type] ?? false;

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

  /// Returns the current security config for the Codex backend.
  CodexSecurityConfig? get codexSecurityConfig {
    final backend = _backends[BackendType.codex];
    if (backend is CodexBackend) {
      return backend.currentSecurityConfig;
    }
    return null;
  }

  /// Stream of account-level rate limit updates from the Codex backend.
  ///
  /// Emits events directly from the backend process, independent of any
  /// active session. Returns an empty stream if no Codex backend is active.
  Stream<RateLimitUpdateEvent> get rateLimits => _rateLimitsController.stream;

  /// Returns security capabilities for the Codex backend.
  CodexSecurityCapabilities get codexSecurityCapabilities {
    final backend = _backends[BackendType.codex];
    if (backend is CodexBackend) {
      return backend.securityCapabilities;
    }
    return const CodexSecurityCapabilities();
  }

  /// Creates a backend instance. Override in tests to inject fakes.
  @visibleForTesting
  Future<AgentBackend> createBackend({
    required BackendType type,
    String? executablePath,
    List<String> arguments = const [],
    String? workingDirectory,
  }) {
    return BackendFactory.create(
      type: type,
      executablePath: executablePath,
      arguments: arguments,
      workingDirectory: workingDirectory,
    );
  }

  /// Registers a backend for testing purposes.
  @visibleForTesting
  void registerBackendForTesting(BackendType type, AgentBackend backend) {
    _backends[type] = backend;
    notifyListeners();
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
  /// Resolves the CLI executable path from RuntimeConfig for the given backend.
  ///
  /// Returns null if no custom path is configured, letting the SDK use its
  /// default resolution (PATH lookup / environment variable).
  String? _resolveExecutablePath(BackendType type) {
    final config = RuntimeConfig.instance;
    return switch (type) {
      BackendType.directCli => config.claudeCliPath.isEmpty
          ? null
          : config.claudeCliPath,
      BackendType.codex => config.codexCliPath.isEmpty
          ? null
          : config.codexCliPath,
      BackendType.acp =>
        config.acpCliPath.isEmpty ? null : config.acpCliPath,
    };
  }

  List<String> _resolveExecutableArguments(BackendType type) {
    final config = RuntimeConfig.instance;
    return switch (type) {
      BackendType.acp => _parseCliArguments(config.acpCliArgs),
      _ => const [],
    };
  }

  String _resolveWorkingDirectory(String? workingDirectory) {
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      return workingDirectory;
    }
    return RuntimeConfig.instance.workingDirectory;
  }

  List<String> _parseCliArguments(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    final args = <String>[];
    var buffer = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var escaped = false;

    void flush() {
      if (buffer.length == 0) return;
      args.add(buffer.toString());
      buffer = StringBuffer();
    }

    for (final rune in trimmed.runes) {
      final char = String.fromCharCode(rune);
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }

      if (char == '\\' && !inSingle) {
        escaped = true;
        continue;
      }

      if (char == '\'' && !inDouble) {
        inSingle = !inSingle;
        continue;
      }

      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }

      final isWhitespace = char.trim().isEmpty;
      if (isWhitespace && !inSingle && !inDouble) {
        flush();
        continue;
      }

      buffer.write(char);
    }

    if (escaped) {
      buffer.write('\\');
    }
    flush();
    return args;
  }

  Future<void> start({
    BackendType type = BackendType.directCli,
    String? executablePath,
    String? workingDirectory,
  }) async {
    final effectivePath = executablePath ?? _resolveExecutablePath(type);
    final arguments = _resolveExecutableArguments(type);
    final effectiveCwd = _resolveWorkingDirectory(workingDirectory);
    final argsLabel = arguments.isEmpty ? 'none' : arguments.join(' ');
    _t(
      'BackendService',
      'start() called, type=${type.name}, executablePath=${effectivePath ?? 'default'}, arguments=$argsLabel, cwd=$effectiveCwd',
    );
    _backendType = type;
    final existing = _backends[type];
    if (existing != null) {
      _t('BackendService', 'Backend already exists for ${type.name}, refreshing models');
      unawaited(_refreshModelsIfSupported(type, existing));
      notifyListeners();
      return;
    }

    if (_starting.contains(type)) {
      _t('BackendService', 'Backend ${type.name} already starting, skipping');
      return;
    }

    _starting.add(type);
    _errors[type] = null;
    _errorIsAgent.remove(type);
    notifyListeners();

    try {
      _t('BackendService', 'Creating backend for ${type.name}...');
      final backend = await createBackend(
        type: type,
        executablePath: effectivePath,
        arguments: arguments,
        workingDirectory: effectiveCwd,
      );
      _backends[type] = backend;
      _t('BackendService', 'Backend created for ${type.name}, capabilities: ${backend.capabilities}');

      // Monitor backend errors
      _errorSubscriptions[type] = backend.errors.listen((error) {
        _t('BackendService', 'Backend error (${type.name}): $error');
        _errors[type] = error.toString();
        _errorIsAgent[type] = true;
        notifyListeners();
      });

      // Forward Codex rate limit events
      if (type == BackendType.codex && backend is CodexBackend) {
        _rateLimitSub?.cancel();
        _rateLimitSub = backend.rateLimits.listen(
          _rateLimitsController.add,
        );
      }

      // Backend log entries (SDK message traces) are NOT forwarded to
      // LogService. They are high-volume chat/session data that belongs
      // in the separate trace log (SdkLogger), not the application log.

      unawaited(_refreshModelsIfSupported(type, backend));
    } catch (e) {
      _t('BackendService', 'ERROR starting backend ${type.name}: $e');
      _errors[type] = e.toString();
      _errorIsAgent[type] = false;
      _backends.remove(type);
    } finally {
      _starting.remove(type);
      _t('BackendService', 'start() complete for ${type.name}, isReady=$isReady, error=${_errors[type]}');
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
    final effectivePath = executablePath ?? _resolveExecutablePath(type);
    // Dispose backends that are not the target type.
    final toRemove = _backends.keys.where((k) => k != type).toList();
    for (final key in toRemove) {
      await _disposeBackend(key);
    }
    await start(type: type, executablePath: effectivePath);
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

  /// Creates an [EventTransport] wrapping an in-process session.
  ///
  /// This is the primary entry point for the transport-based flow.
  /// It creates a session via [createSessionForBackend] and wraps it in
  /// an [InProcessTransport].
  Future<EventTransport> createTransport({
    required BackendType type,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    String? executablePath,
    InternalToolRegistry? registry,
  }) async {
    final session = await createSessionForBackend(
      type: type,
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      executablePath: executablePath,
      registry: registry,
    );
    final caps = capabilitiesFor(type);
    return InProcessTransport(session: session, capabilities: caps);
  }

  /// Creates a session for a specific backend type.
  Future<AgentSession> createSessionForBackend({
    required BackendType type,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    String? executablePath,
    InternalToolRegistry? registry,
  }) async {
    final effectivePath = executablePath ?? _resolveExecutablePath(type);
    _t('BackendService', 'createSessionForBackend type=${type.name} cwd=$cwd');
    await start(type: type, executablePath: effectivePath);
    final backend = _backends[type];
    if (backend == null) {
      _t('BackendService', 'ERROR: Backend ${type.name} not started after start() call');
      throw StateError('Backend not started. Call start() first.');
    }
    _t('BackendService', 'Delegating to backend.createSession...');
    final session = await backend.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
    _t('BackendService', 'Session created: ${session.sessionId}');
    return session;
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
  /// - [registry]: Optional internal tool registry for custom tools.
  ///
  /// Throws [StateError] if the backend is not started.
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    InternalToolRegistry? registry,
  }) async {
    _t('BackendService', 'createSession (default backend) cwd=$cwd');
    final backendType = _backendType;
    if (backendType == null) {
      _t('BackendService', 'ERROR: No backend type set');
      throw StateError('Backend not started. Call start() first.');
    }
    final backend = _backends[backendType];
    if (backend == null) {
      _t('BackendService', 'ERROR: No backend for ${backendType.name}');
      throw StateError('Backend not started. Call start() first.');
    }
    _t('BackendService', 'Delegating to ${backendType.name} backend...');
    return backend.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
  }

  /// Disposes a single backend and its associated subscriptions.
  Future<void> _disposeBackend(BackendType type) async {
    if (type == BackendType.codex) {
      await _rateLimitSub?.cancel();
      _rateLimitSub = null;
    }
    await _errorSubscriptions.remove(type)?.cancel();
    final backend = _backends.remove(type);
    await backend?.dispose();
    _errors.remove(type);
    _errorIsAgent.remove(type);
    _starting.remove(type);
  }

  /// Disposes of the backend service and terminates the subprocess.
  ///
  /// This should be called when the app is shutting down to ensure
  /// the backend process is properly terminated.
  @override
  void dispose() {
    _rateLimitSub?.cancel();
    _rateLimitsController.close();
    for (final sub in _errorSubscriptions.values) {
      sub.cancel();
    }
    _errorSubscriptions.clear();
    for (final backend in _backends.values) {
      backend.dispose();
    }
    _backends.clear();
    _errors.clear();
    _errorIsAgent.clear();
    _starting.clear();
    _backendType = null;
    super.dispose();
  }
}
