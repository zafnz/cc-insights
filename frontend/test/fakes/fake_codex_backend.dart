import 'dart:async';

import 'package:codex_sdk/codex_sdk.dart';

/// Fake implementation of CodexBackend for testing.
class FakeCodexBackend implements CodexBackend {
  CodexSecurityConfig? _securityConfig;
  CodexSecurityCapabilities _capabilities = const CodexSecurityCapabilities();

  void setSecurityConfig(CodexSecurityConfig? config) {
    _securityConfig = config;
  }

  void setCapabilities(CodexSecurityCapabilities capabilities) {
    _capabilities = capabilities;
  }

  @override
  CodexSecurityConfig? get currentSecurityConfig => _securityConfig;

  @override
  CodexSecurityCapabilities get securityCapabilities => _capabilities;

  @override
  CodexConfigWriter get configWriter =>
      throw UnimplementedError('Not needed in tests');

  @override
  Future<void> testReadConfig() async {
    // Not needed for frontend tests
  }

  @override
  BackendCapabilities get capabilities => const BackendCapabilities(
        supportsModelListing: true,
        supportsReasoningEffort: true,
      );

  @override
  bool get isRunning => true;

  @override
  Stream<BackendError> get errors => const Stream.empty();

  @override
  Stream<String> get logs => const Stream.empty();

  @override
  Stream<LogEntry> get logEntries => const Stream.empty();

  @override
  Stream<RateLimitUpdateEvent> get rateLimits => const Stream.empty();

  @override
  List<AgentSession> get sessions => [];

  @override
  Future<List<ModelInfo>> listModels() async => [];

  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    throw UnimplementedError('Not needed in tests');
  }

  @override
  Future<void> dispose() async {}
}
