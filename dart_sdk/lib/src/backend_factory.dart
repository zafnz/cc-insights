import 'dart:io';

import 'backend_interface.dart';
import 'cli_backend.dart';
import 'core.dart';

/// Backend type selection.
enum BackendType {
  /// Node.js backend (current, legacy)
  nodejs,

  /// Direct claude-cli (new, default)
  directCli,
}

/// Factory for creating agent backends.
///
/// This factory supports both the Node.js backend (legacy) and the direct
/// claude-cli backend (new). The backend type can be specified via the
/// [BackendType] enum or overridden via the `CLAUDE_BACKEND` environment
/// variable.
///
/// Example:
/// ```dart
/// // Use default (direct CLI)
/// final backend = await BackendFactory.create();
///
/// // Explicitly use Node.js backend
/// final nodeBackend = await BackendFactory.create(
///   type: BackendType.nodejs,
///   nodeBackendPath: '/path/to/backend/index.js',
/// );
///
/// // Use environment variable override
/// // Set CLAUDE_BACKEND=nodejs to use Node.js backend
/// // Set CLAUDE_BACKEND=direct to use direct CLI (default)
/// final backend = await BackendFactory.create();
/// ```
class BackendFactory {
  BackendFactory._();

  /// Environment variable name for backend type override.
  static const envVarName = 'CLAUDE_BACKEND';

  /// Create a backend of the specified type.
  ///
  /// [type] - The backend type to create. Defaults to [BackendType.directCli].
  ///   This can be overridden by the `CLAUDE_BACKEND` environment variable.
  /// [executablePath] - Path to claude-cli (for direct CLI backend).
  ///   Defaults to `CLAUDE_CODE_PATH` env var or 'claude'.
  /// [nodeBackendPath] - Path to the Node.js backend script (for Node.js
  ///   backend). Required when using [BackendType.nodejs].
  /// [nodeExecutable] - Path to Node.js executable (for Node.js backend).
  ///   Defaults to 'node'.
  ///
  /// Throws [ArgumentError] if [BackendType.nodejs] is selected but
  /// [nodeBackendPath] is not provided.
  static Future<AgentBackend> create({
    BackendType type = BackendType.directCli,
    String? executablePath,
    String? nodeBackendPath,
    String? nodeExecutable,
  }) async {
    // Check for environment variable override
    final effectiveType = _getEffectiveType(type);

    switch (effectiveType) {
      case BackendType.directCli:
        return ClaudeCliBackend(executablePath: executablePath);

      case BackendType.nodejs:
        if (nodeBackendPath == null) {
          throw ArgumentError(
            'nodeBackendPath is required when using BackendType.nodejs',
          );
        }
        return ClaudeBackend.spawn(
          backendPath: nodeBackendPath,
          nodeExecutable: nodeExecutable,
        );
    }
  }

  /// Parse the environment variable to determine backend type.
  ///
  /// Returns the default [type] if the environment variable is not set
  /// or contains an unrecognized value.
  static BackendType _getEffectiveType(BackendType type) {
    final envValue = Platform.environment[envVarName]?.toLowerCase();

    if (envValue == null || envValue.isEmpty) {
      return type;
    }

    switch (envValue) {
      case 'nodejs':
      case 'node':
        return BackendType.nodejs;
      case 'direct':
      case 'directcli':
      case 'cli':
        return BackendType.directCli;
      default:
        // Unrecognized value, use the default
        return type;
    }
  }

  /// Parse a string to a [BackendType].
  ///
  /// Returns null if the string doesn't match any known backend type.
  static BackendType? parseType(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    switch (value.toLowerCase()) {
      case 'nodejs':
      case 'node':
        return BackendType.nodejs;
      case 'direct':
      case 'directcli':
      case 'cli':
        return BackendType.directCli;
      default:
        return null;
    }
  }

  /// Get the current environment variable value, if set.
  static String? getEnvOverride() {
    return Platform.environment[envVarName];
  }
}
