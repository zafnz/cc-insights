import 'dart:async';

import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:meta/meta.dart';

import 'acp_process.dart';
import 'acp_session.dart';

/// Backend that communicates with ACP-compatible agents.
class AcpBackend implements AgentBackend {
  AcpBackend._({required AcpProcess process}) : _process = process;

  final AcpProcess _process;
  final _sessions = <String, AcpSession>{};
  final _errorsController = StreamController<BackendError>.broadcast();
  bool _disposed = false;

  @override
  BackendCapabilities get capabilities => const BackendCapabilities();

  @override
  bool get isRunning => !_disposed;

  @override
  Stream<BackendError> get errors => _errorsController.stream;

  @override
  Stream<String> get logs => _process.logs;

  @override
  Stream<LogEntry> get logEntries => _process.logEntries;

  @override
  List<AgentSession> get sessions => _sessions.values.toList(growable: false);

  /// Spawn an ACP backend.
  static Future<AcpBackend> create({
    String? executablePath,
    List<String> arguments = const [],
  }) async {
    final process = await AcpProcess.start(
      AcpProcessConfig(
        executablePath: executablePath,
        arguments: arguments,
      ),
    );
    return AcpBackend._(process: process);
  }

  /// Create a backend with a mock process for testing.
  @visibleForTesting
  static AcpBackend createForTesting({required AcpProcess process}) {
    return AcpBackend._(process: process);
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

    try {
      final mcpServers = _buildMcpServers(options?.mcpServers);
      final resume = options?.resume;
      final canLoad = _process.agentCapabilities?['loadSession'] == true;
      final response = await _process.sendRequest(
        resume != null && resume.isNotEmpty && canLoad
            ? 'session/load'
            : 'session/new',
        {
          if (resume != null && resume.isNotEmpty && canLoad)
            'sessionId': resume,
          'cwd': cwd,
          'mcpServers': mcpServers,
        },
      );

      final sessionId = response['sessionId'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        throw const BackendError(
          'ACP session creation failed: missing sessionId',
          code: 'SESSION_CREATE_ERROR',
        );
      }

      final session = AcpSession(
        process: _process,
        sessionId: sessionId,
        cwd: cwd,
        includePartialMessages: options?.includePartialMessages ?? false,
        allowedDirectories: options?.additionalDirectories ?? const [],
      );
      _sessions[sessionId] = session;
      session.emitSessionInit(
        sessionInfo: response,
        initializeResult: _process.initializeResult,
      );

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

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _errorsController.close();
    _sessions.clear();
    await _process.dispose();
  }

  List<Map<String, dynamic>> _buildMcpServers(
    Map<String, McpServerConfig>? servers,
  ) {
    if (servers == null || servers.isEmpty) return const [];
    return servers.entries
        .map((entry) => {
              'name': entry.key,
              ...entry.value.toJson(),
            })
        .toList(growable: false);
  }
}
