import 'package:agent_sdk_core/agent_sdk_core.dart';

import 'codex_process.dart';

/// Result of a Codex configuration write operation.
class CodexConfigWriteResult {
  const CodexConfigWriteResult({
    required this.status,
    this.filePath,
    this.version,
    this.overrideMessage,
    this.effectiveValue,
  });

  /// Status of the write operation (e.g., 'ok', 'okOverridden').
  final String status;

  /// Path to the config file that was written.
  final String? filePath;

  /// Version string of the config file.
  final String? version;

  /// Message explaining why the value was overridden.
  final String? overrideMessage;

  /// The effective value after any overrides were applied.
  final dynamic effectiveValue;

  /// Returns true if the write succeeded but was overridden by server policy.
  bool get wasOverridden => status == 'okOverridden';

  factory CodexConfigWriteResult.fromJson(Map<String, dynamic> json) {
    final overriddenMetadata =
        json['overriddenMetadata'] as Map<String, dynamic>?;

    return CodexConfigWriteResult(
      status: json['status'] as String,
      filePath: json['filePath'] as String?,
      version: json['version'] as String?,
      overrideMessage: overriddenMetadata?['message'] as String?,
      effectiveValue: overriddenMetadata?['effectiveValue'],
    );
  }
}

/// A single edit operation for batch configuration writes.
class CodexConfigEdit {
  const CodexConfigEdit({
    required this.keyPath,
    required this.value,
    this.mergeStrategy = 'replace',
  });

  /// The configuration key path (e.g., 'sandbox_mode').
  final String keyPath;

  /// The value to write.
  final dynamic value;

  /// The merge strategy (default: 'replace').
  final String mergeStrategy;

  Map<String, dynamic> toJson() {
    return {
      'keyPath': keyPath,
      'value': value,
      'mergeStrategy': mergeStrategy,
    };
  }
}

/// Writes security configuration to Codex app-server.
class CodexConfigWriter {
  const CodexConfigWriter(this._process);

  final CodexProcess _process;

  /// Writes a single configuration value.
  ///
  /// Calls the `config/write` JSON-RPC method with the given key path,
  /// value, and merge strategy.
  Future<CodexConfigWriteResult> writeValue({
    required String keyPath,
    required dynamic value,
    String mergeStrategy = 'replace',
  }) async {
    final result = await _process.sendRequest('config/write', {
      'keyPath': keyPath,
      'value': value,
      'mergeStrategy': mergeStrategy,
    });

    return CodexConfigWriteResult.fromJson(result);
  }

  /// Writes multiple configuration values in a single operation.
  ///
  /// Calls the `config/batchWrite` JSON-RPC method with the list of edits.
  Future<CodexConfigWriteResult> batchWrite(List<CodexConfigEdit> edits) async {
    final result = await _process.sendRequest('config/batchWrite', {
      'edits': edits.map((e) => e.toJson()).toList(),
    });

    return CodexConfigWriteResult.fromJson(result);
  }

  /// Sets the sandbox mode configuration.
  Future<CodexConfigWriteResult> setSandboxMode(
    CodexSandboxMode mode,
  ) async {
    return writeValue(
      keyPath: 'sandbox_mode',
      value: mode.wireValue,
    );
  }

  /// Sets the approval policy configuration.
  Future<CodexConfigWriteResult> setApprovalPolicy(
    CodexApprovalPolicy policy,
  ) async {
    return writeValue(
      keyPath: 'approval_policy',
      value: policy.wireValue,
    );
  }

  /// Sets the workspace write options configuration.
  Future<CodexConfigWriteResult> setWorkspaceWriteOptions(
    CodexWorkspaceWriteOptions options,
  ) async {
    return writeValue(
      keyPath: 'sandbox_workspace_write',
      value: options.toJson(),
      mergeStrategy: 'upsert',
    );
  }
}
