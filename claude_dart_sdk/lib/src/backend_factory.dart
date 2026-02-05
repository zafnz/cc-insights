import 'dart:io';

import 'package:codex_sdk/codex_sdk.dart' as codex;

import 'backend_interface.dart';
import 'cli_backend.dart';

/// Backend type selection.
enum BackendType {
  /// Direct claude-cli (default)
  directCli,

  /// Codex app-server backend
  codex,
}

/// Factory for creating agent backends.
///
/// This factory supports the direct claude-cli backend (default) and the
/// Codex backend. The backend type can be specified via the [BackendType]
/// enum or overridden via the `CLAUDE_BACKEND` environment variable.
///
/// Example:
/// ```dart
/// // Use default (direct CLI)
/// final backend = await BackendFactory.create();
///
/// // Use environment variable override
/// // Set CLAUDE_BACKEND=direct to use direct CLI (default)
/// // Set CLAUDE_BACKEND=codex to use Codex backend
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
  /// [executablePath] - Path to claude-cli or codex (depending on backend).
  ///   Defaults to `CLAUDE_CODE_PATH` env var or 'claude' for Claude, and
  ///   'codex' for Codex.
  static Future<AgentBackend> create({
    BackendType type = BackendType.directCli,
    String? executablePath,
  }) async {
    // Check for environment variable override
    final effectiveType = _getEffectiveType(type);

    switch (effectiveType) {
      case BackendType.directCli:
        return ClaudeCliBackend(executablePath: executablePath);

      case BackendType.codex:
        return codex.CodexBackend.create(executablePath: executablePath);
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
      case 'direct':
      case 'directcli':
      case 'cli':
      case 'claude':
        return BackendType.directCli;
      case 'codex':
        return BackendType.codex;
      default:
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
      case 'direct':
      case 'directcli':
      case 'cli':
      case 'claude':
        return BackendType.directCli;
      case 'codex':
        return BackendType.codex;
      default:
        return null;
    }
  }

  /// Get the current environment variable value, if set.
  static String? getEnvOverride() {
    return Platform.environment[envVarName];
  }
}
