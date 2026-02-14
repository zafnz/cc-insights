import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

/// User-configured agent that wraps a backend driver with user-specific settings.
///
/// Each AgentConfig represents a user-defined agent instance (e.g., "Claude Opus",
/// "My Codex", "Gemini Flash") with customized CLI paths, arguments, environment,
/// and default settings. The frontend displays a dropdown of configured agents,
/// and users can create multiple agents for the same driver with different settings.
@immutable
class AgentConfig {
  /// Stable unique identifier for this agent configuration.
  ///
  /// Used as the backend key. Generated via [generateId].
  final String id;

  /// Display name shown in the UI (e.g., "Claude", "My Codex", "Gemini").
  final String name;

  /// Driver type: "claude", "codex", or "acp".
  ///
  /// Maps to [BackendType] internally via [backendType].
  final String driver;

  /// Path to the CLI executable.
  ///
  /// Empty string means auto-detect via PATH.
  final String cliPath;

  /// CLI arguments string (e.g., "--verbose --model opus").
  final String cliArgs;

  /// Freeform multiline KEY=VALUE environment variable pairs.
  ///
  /// Parsed into a map via [parsedEnvironment].
  final String environment;

  /// Default model ID (e.g., "opus", "o3", "").
  ///
  /// May be empty if not applicable for this driver.
  final String defaultModel;

  /// Default permission preset (driver-dependent).
  ///
  /// For Claude: "default", "acceptEdits", "plan", "bypassPermissions"
  final String defaultPermissions;

  /// Codex sandbox mode (only used when driver == "codex").
  ///
  /// Null for non-Codex drivers.
  final String? codexSandboxMode;

  /// Codex approval policy (only used when driver == "codex").
  ///
  /// Null for non-Codex drivers.
  final String? codexApprovalPolicy;

  const AgentConfig({
    required this.id,
    required this.name,
    required this.driver,
    this.cliPath = '',
    this.cliArgs = '',
    this.environment = '',
    this.defaultModel = '',
    this.defaultPermissions = 'default',
    this.codexSandboxMode,
    this.codexApprovalPolicy,
  });

  /// The parsed backend type from [driver] string.
  ///
  /// Uses [parseBackendType] to convert driver string to [BackendType] enum.
  /// Defaults to [BackendType.directCli] if parsing fails.
  BackendType get backendType {
    return parseBackendType(driver) ?? BackendType.directCli;
  }

  /// Parsed environment variables as a key-value map.
  ///
  /// Splits [environment] on newlines, then splits each line on the first `=`.
  /// Ignores empty lines and lines without `=`.
  Map<String, String> get parsedEnvironment {
    final result = <String, String>{};
    final lines = environment.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final index = trimmed.indexOf('=');
      if (index == -1) continue;

      final key = trimmed.substring(0, index).trim();
      final value = trimmed.substring(index + 1).trim();

      if (key.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  /// Creates a copy with updated fields.
  AgentConfig copyWith({
    String? id,
    String? name,
    String? driver,
    String? cliPath,
    String? cliArgs,
    String? environment,
    String? defaultModel,
    String? defaultPermissions,
    String? codexSandboxMode,
    String? codexApprovalPolicy,
  }) {
    return AgentConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      driver: driver ?? this.driver,
      cliPath: cliPath ?? this.cliPath,
      cliArgs: cliArgs ?? this.cliArgs,
      environment: environment ?? this.environment,
      defaultModel: defaultModel ?? this.defaultModel,
      defaultPermissions: defaultPermissions ?? this.defaultPermissions,
      codexSandboxMode: codexSandboxMode ?? this.codexSandboxMode,
      codexApprovalPolicy: codexApprovalPolicy ?? this.codexApprovalPolicy,
    );
  }

  /// Creates an AgentConfig from JSON.
  factory AgentConfig.fromJson(Map<String, dynamic> json) {
    return AgentConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      driver: json['driver'] as String,
      cliPath: json['cliPath'] as String? ?? '',
      cliArgs: json['cliArgs'] as String? ?? '',
      environment: json['environment'] as String? ?? '',
      defaultModel: json['defaultModel'] as String? ?? '',
      defaultPermissions: json['defaultPermissions'] as String? ?? 'default',
      codexSandboxMode: json['codexSandboxMode'] as String?,
      codexApprovalPolicy: json['codexApprovalPolicy'] as String?,
    );
  }

  /// Converts to JSON for persistence.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'driver': driver,
      'cliPath': cliPath,
      'cliArgs': cliArgs,
      'environment': environment,
      'defaultModel': defaultModel,
      'defaultPermissions': defaultPermissions,
      if (codexSandboxMode != null) 'codexSandboxMode': codexSandboxMode,
      if (codexApprovalPolicy != null)
        'codexApprovalPolicy': codexApprovalPolicy,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentConfig && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'AgentConfig(id: $id, name: $name, driver: $driver, '
        'cliPath: $cliPath, cliArgs: $cliArgs, defaultModel: $defaultModel, '
        'defaultPermissions: $defaultPermissions)';
  }

  /// Generates a short unique ID for new agent configurations.
  ///
  /// Uses current timestamp in base-36 format for collision-resistant IDs.
  static String generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  /// Default agent configurations provided out-of-the-box.
  static List<AgentConfig> get defaults => [
        const AgentConfig(
          id: 'claude-default',
          name: 'Claude',
          driver: 'claude',
          cliPath: '',
          cliArgs: '',
          environment: '',
          defaultModel: 'opus',
          defaultPermissions: 'default',
        ),
        const AgentConfig(
          id: 'codex-default',
          name: 'Codex',
          driver: 'codex',
          cliPath: '',
          cliArgs: '',
          environment: '',
          defaultModel: '',
          defaultPermissions: 'default',
          codexSandboxMode: 'workspace-write',
          codexApprovalPolicy: 'on-request',
        ),
        const AgentConfig(
          id: 'acp-default',
          name: 'Gemini',
          driver: 'acp',
          cliPath: '',
          cliArgs: '--stdio',
          environment: '',
          defaultModel: '',
          defaultPermissions: 'default',
        ),
      ];
}
