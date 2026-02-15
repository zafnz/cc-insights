import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:codex_sdk/codex_sdk.dart';
import 'package:flutter/foundation.dart';

import '../models/agent_config.dart';
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

  // -------------------------------------------------------------------------
  // Agent-keyed backend state
  // -------------------------------------------------------------------------

  /// Backends keyed by agent ID (e.g. 'claude-default', 'codex-default').
  final Map<String, AgentBackend> _agentBackends = {};

  /// Error subscriptions keyed by agent ID.
  final Map<String, StreamSubscription<BackendError>>
      _agentErrorSubscriptions = {};

  /// Error messages keyed by agent ID.
  final Map<String, String?> _agentErrors = {};

  /// Whether error came from agent response, keyed by agent ID.
  final Map<String, bool> _agentErrorIsAgent = {};

  /// Agent IDs currently in the process of starting.
  final Set<String> _agentStarting = {};

  /// Agent IDs currently loading model lists.
  final Set<String> _agentModelListLoading = {};

  /// The currently active agent ID, if any.
  String? _activeAgentId;

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

  // -------------------------------------------------------------------------
  // Agent-keyed query methods
  // -------------------------------------------------------------------------

  /// The currently active agent ID, if any.
  String? get activeAgentId => _activeAgentId;

  /// Whether a specific agent's backend is ready.
  bool isReadyForAgent(String agentId) {
    return _agentBackends.containsKey(agentId) &&
        _agentErrors[agentId] == null;
  }

  /// Whether a specific agent's backend is currently starting.
  bool isStartingForAgent(String agentId) => _agentStarting.contains(agentId);

  /// Whether model list loading is in progress for an agent.
  bool isModelListLoadingForAgent(String agentId) =>
      _agentModelListLoading.contains(agentId);

  /// Error message for a specific agent, if any.
  String? errorForAgent(String agentId) => _agentErrors[agentId];

  /// Whether a specific agent error came from an agent response.
  bool isAgentErrorForAgent(String agentId) =>
      _agentErrorIsAgent[agentId] ?? false;

  /// Capabilities of a specific agent's backend.
  BackendCapabilities capabilitiesForAgent(String agentId) {
    return _agentBackends[agentId]?.capabilities ?? const BackendCapabilities();
  }

  /// Returns the Codex security config for an agent, if it's a Codex backend.
  CodexSecurityConfig? codexSecurityConfigForAgent(String agentId) {
    final backend = _agentBackends[agentId];
    if (backend is CodexBackend) {
      return backend.currentSecurityConfig;
    }
    return null;
  }

  /// Returns Codex security capabilities for an agent, if it's a Codex backend.
  CodexSecurityCapabilities codexSecurityCapabilitiesForAgent(String agentId) {
    final backend = _agentBackends[agentId];
    if (backend is CodexBackend) {
      return backend.securityCapabilities;
    }
    return const CodexSecurityCapabilities();
  }

  // -------------------------------------------------------------------------
  // Agent-keyed lifecycle methods
  // -------------------------------------------------------------------------

  /// Resolves an [AgentConfig] by ID from the [RuntimeConfig] agent registry.
  AgentConfig? _resolveAgentConfig(String agentId) {
    return RuntimeConfig.instance.agentById(agentId);
  }

  /// Starts a backend for a specific agent configuration.
  ///
  /// Resolves the agent config from the registry, then spawns a backend
  /// using the agent's driver, CLI path, arguments, and environment.
  ///
  /// This is idempotent — calling it when the agent is already started
  /// or starting will return without doing anything extra (but may refresh
  /// models).
  Future<void> startAgent(String agentId, {AgentConfig? config}) async {
    final agentConfig = config ?? _resolveAgentConfig(agentId);
    if (agentConfig == null) {
      _t('BackendService', 'ERROR: No agent config found for $agentId');
      throw StateError('No agent configuration found for "$agentId".');
    }

    final type = agentConfig.backendType;
    final effectivePath =
        agentConfig.cliPath.isEmpty ? null : agentConfig.cliPath;
    final arguments = _parseCliArguments(agentConfig.cliArgs);
    final effectiveCwd =
        _resolveWorkingDirectory(null);
    final argsLabel = arguments.isEmpty ? 'none' : arguments.join(' ');
    _t(
      'BackendService',
      'startAgent() called, agentId=$agentId, driver=${agentConfig.driver}, '
      'executablePath=${effectivePath ?? 'default'}, arguments=$argsLabel, cwd=$effectiveCwd',
    );
    _activeAgentId = agentId;

    final existing = _agentBackends[agentId];
    if (existing != null) {
      _t('BackendService', 'Backend already exists for agent $agentId, refreshing models');
      unawaited(_refreshModelsForAgent(agentId, type, existing));
      notifyListeners();
      return;
    }

    if (_agentStarting.contains(agentId)) {
      _t('BackendService', 'Agent $agentId already starting, skipping');
      return;
    }

    _agentStarting.add(agentId);
    _agentErrors[agentId] = null;
    _agentErrorIsAgent.remove(agentId);
    notifyListeners();

    try {
      _t('BackendService', 'Creating backend for agent $agentId (${type.name})...');
      final backend = await createBackend(
        type: type,
        executablePath: effectivePath,
        arguments: arguments,
        workingDirectory: effectiveCwd,
      );
      _agentBackends[agentId] = backend;
      _t('BackendService', 'Backend created for agent $agentId, capabilities: ${backend.capabilities}');

      // Monitor backend errors
      _agentErrorSubscriptions[agentId] = backend.errors.listen((error) {
        _t('BackendService', 'Backend error (agent $agentId): $error');
        _agentErrors[agentId] = error.toString();
        _agentErrorIsAgent[agentId] = true;
        notifyListeners();
      });

      // Forward Codex rate limit events
      if (type == BackendType.codex && backend is CodexBackend) {
        _rateLimitSub?.cancel();
        _rateLimitSub = backend.rateLimits.listen(
          _rateLimitsController.add,
        );
      }

      unawaited(_refreshModelsForAgent(agentId, type, backend));
    } catch (e) {
      _t('BackendService', 'ERROR starting backend for agent $agentId: $e');
      _agentErrors[agentId] = e.toString();
      _agentErrorIsAgent[agentId] = false;
      _agentBackends.remove(agentId);
    } finally {
      _agentStarting.remove(agentId);
      _t('BackendService', 'startAgent() complete for $agentId, isReady=${isReadyForAgent(agentId)}, error=${_agentErrors[agentId]}');
      notifyListeners();
    }
  }

  /// Creates an [EventTransport] for a specific agent.
  Future<EventTransport> createTransportForAgent({
    required String agentId,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    InternalToolRegistry? registry,
  }) async {
    final session = await createSessionForAgent(
      agentId: agentId,
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
    final caps = capabilitiesForAgent(agentId);
    return InProcessTransport(session: session, capabilities: caps);
  }

  /// Creates a session for a specific agent.
  Future<AgentSession> createSessionForAgent({
    required String agentId,
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    InternalToolRegistry? registry,
  }) async {
    _t('BackendService', 'createSessionForAgent agentId=$agentId cwd=$cwd');
    await startAgent(agentId);
    final backend = _agentBackends[agentId];
    if (backend == null) {
      _t('BackendService', 'ERROR: Backend for agent $agentId not started after startAgent() call');
      throw StateError('Backend not started for agent "$agentId".');
    }
    _t('BackendService', 'Delegating to backend.createSession for agent $agentId...');
    final session = await backend.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
      registry: registry,
    );
    _t('BackendService', 'Session created for agent $agentId: ${session.sessionId}');
    return session;
  }

  /// Disposes a single agent's backend and its associated subscriptions.
  Future<void> disposeAgent(String agentId) async {
    final backend = _agentBackends[agentId];
    if (backend != null && backend is CodexBackend) {
      await _rateLimitSub?.cancel();
      _rateLimitSub = null;
    }
    await _agentErrorSubscriptions.remove(agentId)?.cancel();
    _agentBackends.remove(agentId);
    await backend?.dispose();
    _agentErrors.remove(agentId);
    _agentErrorIsAgent.remove(agentId);
    _agentStarting.remove(agentId);
    if (_activeAgentId == agentId) {
      _activeAgentId = null;
    }
    notifyListeners();
  }

  /// Registers a backend for a specific agent in testing.
  @visibleForTesting
  void registerAgentBackendForTesting(String agentId, AgentBackend backend) {
    _agentBackends[agentId] = backend;
    notifyListeners();
  }

  /// Fetches models from [backend] and updates the [ChatModelCatalog].
  ///
  /// Shared logic used by both [_refreshModelsForAgent] and
  /// [_refreshModelsIfSupported].
  Future<void> _fetchAndUpdateModels(
    BackendType type,
    AgentBackend backend,
  ) async {
    // For Claude, use queryBackendInfo to get both models and account.
    if (type == BackendType.directCli && backend is ClaudeCliBackend) {
      final (models, account) = await backend.queryBackendInfo();
      ChatModelCatalog.updateAccountInfo(account);
      if (models.isNotEmpty) {
        final mapped = models
            .where((m) => m.value.trim().isNotEmpty)
            .map((m) {
          final label = m.displayName.trim().isEmpty
              ? m.value
              : m.displayName.trim();
          return ChatModel(
            id: m.value.trim(),
            label: label,
            backend: BackendType.directCli,
            description: m.description.trim(),
          );
        }).toList();
        if (mapped.isNotEmpty) {
          ChatModelCatalog.updateClaudeModels(mapped);
        }
      }
      return;
    }

    // For other backends, use the generic listModels.
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
          description: model.description.trim(),
        );
      }).toList();

      if (mapped.isNotEmpty) {
        ChatModelCatalog.updateCodexModels(mapped);
      }
    }
  }

  Future<void> _refreshModelsForAgent(
    String agentId,
    BackendType type,
    AgentBackend backend,
  ) async {
    if (backend is! ModelListingBackend) return;

    final didStartLoading = _agentModelListLoading.add(agentId);
    if (didStartLoading) {
      notifyListeners();
    }

    try {
      await _fetchAndUpdateModels(type, backend);
    } catch (e) {
      _t('BackendService', 'Failed to refresh model list for agent $agentId: $e');
      _agentErrors[agentId] = 'Model refresh failed: $e';
      _agentErrorIsAgent[agentId] = false;
    } finally {
      _agentModelListLoading.remove(agentId);
      notifyListeners();
    }
  }

  /// Starts backends and discovers models for all configured agents.
  ///
  /// This is typically called once on app startup to ensure model catalogs
  /// are populated for all agent types (Claude, Codex, etc.), not just the
  /// default agent.
  Future<void> discoverModelsForAllAgents() async {
    final agents = RuntimeConfig.instance.agents;
    final seen = <BackendType>{};

    for (final agent in agents) {
      final type = agent.backendType;
      // Only start one backend per driver type — model discovery is global.
      if (seen.contains(type)) continue;
      seen.add(type);

      // Skip if the backend is already started for this agent.
      if (_agentBackends.containsKey(agent.id)) {
        unawaited(
          _refreshModelsForAgent(agent.id, type, _agentBackends[agent.id]!),
        );
        continue;
      }

      unawaited(startAgent(agent.id));
    }
  }

  /// Creates a backend instance. Override in tests to inject fakes.
  @visibleForTesting
  Future<AgentBackend> createBackend({
    required BackendType type,
    String? executablePath,
    List<String> arguments = const [],
    String? workingDirectory,
  }) {
    return BackendRegistry.create(
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
    final effectiveCwd = _resolveWorkingDirectory(workingDirectory);
    _t(
      'BackendService',
      'start() called, type=${type.name}, executablePath=${executablePath ?? 'default'}, cwd=$effectiveCwd',
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
        executablePath: executablePath,
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
      await _fetchAndUpdateModels(type, backend);
    } catch (e) {
      _t('BackendService', 'Failed to refresh model list for ${type.name}: $e');
      _errors[type] = 'Model refresh failed: $e';
      _errorIsAgent[type] = false;
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
    _t('BackendService', 'createSessionForBackend type=${type.name} cwd=$cwd');
    await start(type: type, executablePath: executablePath);
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

  /// Cancels all stream subscriptions and closes controllers.
  ///
  /// Returns a future that completes when all cancellations finish.
  /// Called by [dispose] to ensure subscriptions are properly cleaned up.
  Future<void> _cancelAllSubscriptions() async {
    await Future.wait<void>([
      if (_rateLimitSub != null) _rateLimitSub!.cancel(),
      _rateLimitsController.close(),
      ..._errorSubscriptions.values.map((sub) => sub.cancel()),
      ..._agentErrorSubscriptions.values.map((sub) => sub.cancel()),
    ]);
  }

  /// Disposes of the backend service and terminates the subprocess.
  ///
  /// This should be called when the app is shutting down to ensure
  /// the backend process is properly terminated.
  @override
  void dispose() {
    unawaited(_cancelAllSubscriptions());
    _errorSubscriptions.clear();
    // Clean up BackendType-keyed state
    for (final backend in _backends.values) {
      backend.dispose();
    }
    _backends.clear();
    _errors.clear();
    _errorIsAgent.clear();
    _starting.clear();
    _backendType = null;
    // Clean up agent-keyed state
    _agentErrorSubscriptions.clear();
    for (final backend in _agentBackends.values) {
      backend.dispose();
    }
    _agentBackends.clear();
    _agentErrors.clear();
    _agentErrorIsAgent.clear();
    _agentStarting.clear();
    _activeAgentId = null;
    super.dispose();
  }
}
