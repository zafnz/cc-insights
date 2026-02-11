import 'dart:async';

import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:meta/meta.dart';

import 'codex_config.dart';
import 'codex_config_writer.dart';
import 'codex_process.dart';
import 'codex_session.dart';
import 'json_rpc.dart';

/// Backend that communicates with Codex app-server.
class CodexBackend implements AgentBackend, ModelListingBackend {
  CodexBackend._({required CodexProcess process}) : _process = process {
    _setupRateLimitListener();
  }

  final CodexProcess _process;

  final _sessions = <String, CodexSession>{};
  final _errorsController = StreamController<BackendError>.broadcast();
  final _rateLimitsController =
      StreamController<RateLimitUpdateEvent>.broadcast();
  StreamSubscription<JsonRpcNotification>? _rateLimitSub;

  bool _disposed = false;

  CodexSecurityConfig? _currentConfig;
  CodexSecurityCapabilities? _capabilities;

  /// Current security configuration read from the Codex app-server.
  CodexSecurityConfig? get currentSecurityConfig => _currentConfig;

  /// Security capabilities (enterprise restrictions).
  CodexSecurityCapabilities get securityCapabilities =>
      _capabilities ?? const CodexSecurityCapabilities();

  /// Config writer for mid-session changes.
  CodexConfigWriter get configWriter => CodexConfigWriter(_process);

  @override
  BackendCapabilities get capabilities => const BackendCapabilities(
        supportsModelListing: true,
        supportsReasoningEffort: true,
      );

  /// Stream of account-level rate limit updates.
  ///
  /// Listens directly on the process notification stream so events are
  /// captured regardless of whether any session is active.
  Stream<RateLimitUpdateEvent> get rateLimits => _rateLimitsController.stream;

  void _setupRateLimitListener() {
    _rateLimitSub = _process.notifications.listen((notification) {
      if (notification.method != 'account/rateLimits/updated') return;
      final params = notification.params ?? const <String, dynamic>{};
      final rateLimits = params['rateLimits'] as Map<String, dynamic>?;
      if (rateLimits == null) return;

      final primaryJson = rateLimits['primary'] as Map<String, dynamic>?;
      final secondaryJson = rateLimits['secondary'] as Map<String, dynamic>?;
      final creditsJson = rateLimits['credits'] as Map<String, dynamic>?;

      _rateLimitsController.add(RateLimitUpdateEvent(
        id: 'backend-ratelimit-${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        provider: BackendProvider.codex,
        raw: params,
        sessionId: '',
        primary: primaryJson != null
            ? RateLimitWindow.fromJson(primaryJson)
            : null,
        secondary: secondaryJson != null
            ? RateLimitWindow.fromJson(secondaryJson)
            : null,
        credits: creditsJson != null
            ? RateLimitCredits.fromJson(creditsJson)
            : null,
        planType: rateLimits['planType'] as String?,
      ));
    });
  }

  /// Spawn a Codex app-server backend.
  static Future<CodexBackend> create({String? executablePath}) async {
    final process = await CodexProcess.start(
      CodexProcessConfig(executablePath: executablePath),
    );
    final backend = CodexBackend._(process: process);
    await backend._readInitialConfig();
    return backend;
  }

  Future<void> _readInitialConfig() async {
    try {
      final reader = CodexConfigReader(_process);
      _currentConfig = await reader.readSecurityConfig();
      _capabilities = await reader.readCapabilities();
    } catch (e) {
      // Config read is best-effort; fall back to defaults
      SdkLogger.instance.warning('Failed to read Codex config: $e');
      _currentConfig = CodexSecurityConfig.defaultConfig;
      _capabilities = const CodexSecurityCapabilities();
    }
  }

  /// Create a backend with a mock process for testing.
  @visibleForTesting
  static CodexBackend createForTesting({required CodexProcess process}) {
    return CodexBackend._(process: process);
  }

  /// Exposed for testing: manually trigger config read.
  @visibleForTesting
  Future<void> testReadConfig() async {
    await _readInitialConfig();
  }

  @override
  bool get isRunning => !_disposed;

  @override
  Stream<BackendError> get errors => _errorsController.stream;

  @override
  Stream<String> get logs => _process.logs;

  @override
  Stream<LogEntry> get logEntries => _process.logEntries;

  @override
  List<AgentSession> get sessions => List.unmodifiable(_sessions.values);

  @override
  Future<List<ModelInfo>> listModels() async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    final models = <ModelInfo>[];
    final seen = <String>{};
    String? cursor;

    do {
      final params = <String, dynamic>{};
      if (cursor != null && cursor.isNotEmpty) {
        params['cursor'] = cursor;
      }

      final result = await _process.sendRequest(
        'model/list',
        params,
      );

      final data = result['data'] as List<dynamic>? ?? const [];
      for (final entry in data) {
        if (entry is! Map<String, dynamic>) continue;
        final model =
            (entry['model'] as String?)?.trim() ??
            (entry['id'] as String?)?.trim() ??
            '';
        if (model.isEmpty || seen.contains(model)) continue;
        seen.add(model);
        final displayName =
            (entry['displayName'] as String?)?.trim() ?? model;
        final description = (entry['description'] as String?)?.trim() ?? '';
        models.add(ModelInfo(
          value: model,
          displayName: displayName.isEmpty ? model : displayName,
          description: description,
        ));
      }

      cursor = result['nextCursor'] as String?;
      if (cursor != null && cursor.isEmpty) {
        cursor = null;
      }
    } while (cursor != null);

    return models;
  }

  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
    InternalToolRegistry? registry,
  }) async {
    if (_disposed) {
      throw const BackendProcessError('Backend has been disposed');
    }

    // Validate options and log warnings for unsupported fields
    if (options != null) {
      final validation = options.validateForCodex();
      for (final warning in validation.warnings) {
        SdkLogger.instance.warning(warning);
      }
    }

    try {
      final threadResult = await _startThread(cwd, options);
      final session = CodexSession(
        process: _process,
        threadId: threadResult.threadId,
        serverModel: threadResult.model,
        serverReasoningEffort: threadResult.reasoningEffort,
        registry: registry,
      );
      _sessions[threadResult.threadId] = session;

      if (content != null && content.isNotEmpty) {
        await session.sendWithContent(content);
      } else if (prompt.isNotEmpty) {
        await session.send(prompt);
      }

      return session;
    } catch (e) {
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

  Future<_ThreadStartResult> _startThread(
    String cwd,
    SessionOptions? options,
  ) async {
    final model = options?.model?.trim();
    final resume = options?.resume;
    final resolvedModel = model != null && model.isNotEmpty ? model : null;
    final securityConfig = options?.codexSecurityConfig;

    Map<String, dynamic> result;
    if (resume != null && resume.isNotEmpty) {
      result = await _process.sendRequest('thread/resume', {
        'threadId': resume,
        'cwd': cwd,
        if (resolvedModel != null) 'model': resolvedModel,
        if (securityConfig != null) ...{
          'sandbox': securityConfig.sandboxMode.wireValue,
          'approvalPolicy': securityConfig.approvalPolicy.wireValue,
        },
      });
    } else {
      result = await _process.sendRequest('thread/start', {
        'cwd': cwd,
        if (resolvedModel != null) 'model': resolvedModel,
        if (securityConfig != null) ...{
          'sandbox': securityConfig.sandboxMode.wireValue,
          'approvalPolicy': securityConfig.approvalPolicy.wireValue,
        },
      });
    }

    final thread = result['thread'] as Map<String, dynamic>?;
    final threadId = thread?['id'] as String?;
    if (threadId == null || threadId.isEmpty) {
      throw const BackendProcessError('Invalid thread response');
    }
    return _ThreadStartResult(
      threadId: threadId,
      model: result['model'] as String?,
      reasoningEffort: result['reasoningEffort'] as String?,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final session in _sessions.values) {
      await session.kill();
    }
    _sessions.clear();

    await _rateLimitSub?.cancel();
    await _rateLimitsController.close();
    await _errorsController.close();
    await _process.dispose();
  }
}

/// Result from thread/start or thread/resume, capturing server-reported values.
class _ThreadStartResult {
  const _ThreadStartResult({
    required this.threadId,
    this.model,
    this.reasoningEffort,
  });

  final String threadId;
  final String? model;
  final String? reasoningEffort;
}
