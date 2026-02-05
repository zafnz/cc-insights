import 'dart:async';

import 'package:agent_sdk_core/agent_sdk_core.dart';

import 'codex_process.dart';
import 'codex_session.dart';

/// Backend that communicates with Codex app-server.
class CodexBackend implements AgentBackend, ModelListingBackend {
  CodexBackend._({required CodexProcess process}) : _process = process;

  final CodexProcess _process;

  final _sessions = <String, CodexSession>{};
  final _errorsController = StreamController<BackendError>.broadcast();

  bool _disposed = false;

  @override
  BackendCapabilities get capabilities => const BackendCapabilities(
        supportsModelListing: true,
        supportsReasoningEffort: true,
      );

  /// Spawn a Codex app-server backend.
  static Future<CodexBackend> create({String? executablePath}) async {
    final process = await CodexProcess.start(
      CodexProcessConfig(executablePath: executablePath),
    );
    return CodexBackend._(process: process);
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
      final threadId = await _startThread(cwd, options);
      final session = CodexSession(
        process: _process,
        threadId: threadId,
      );
      _sessions[threadId] = session;

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

  Future<String> _startThread(String cwd, SessionOptions? options) async {
    final model = options?.model?.trim();
    final resume = options?.resume;
    final resolvedModel = model != null && model.isNotEmpty ? model : null;

    Map<String, dynamic> result;
    if (resume != null && resume.isNotEmpty) {
      result = await _process.sendRequest('thread/resume', {
        'threadId': resume,
        'cwd': cwd,
        if (resolvedModel != null) 'model': resolvedModel,
      });
    } else {
      result = await _process.sendRequest('thread/start', {
        'cwd': cwd,
        if (resolvedModel != null) 'model': resolvedModel,
      });
    }

    final thread = result['thread'] as Map<String, dynamic>?;
    final threadId = thread?['id'] as String?;
    if (threadId == null || threadId.isEmpty) {
      throw const BackendProcessError('Invalid thread response');
    }
    return threadId;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final session in _sessions.values) {
      await session.kill();
    }
    _sessions.clear();

    await _errorsController.close();
    await _process.dispose();
  }
}
