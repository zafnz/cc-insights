import 'dart:io';

import '../backend_interface.dart';

/// Backend type selection.
enum BackendType {
  /// Direct claude-cli (default)
  directCli,

  /// Codex app-server backend
  codex,

  /// ACP JSON-RPC backend
  acp,
}

/// Factory function signature for creating agent backends.
///
/// All backend factories must conform to this signature. Parameters that
/// are not relevant to a specific backend may be ignored.
typedef BackendFactoryFn = Future<AgentBackend> Function({
  String? executablePath,
  List<String> arguments,
  String? workingDirectory,
});

/// Registry for backend factories.
///
/// Each backend SDK registers its factory via [register]. The frontend
/// (or any host application) then calls [create] to instantiate backends
/// without needing to know about the concrete implementations.
///
/// Example:
/// ```dart
/// // During app startup, register available backends:
/// ClaudeCliBackend.register();
/// CodexBackend.register();
/// AcpBackend.register();
///
/// // Later, create a backend by type:
/// final backend = await BackendRegistry.create(type: BackendType.codex);
/// ```
class BackendRegistry {
  BackendRegistry._();

  static final Map<BackendType, BackendFactoryFn> _factories = {};

  /// Environment variable name for backend type override.
  static const envVarName = 'CLAUDE_BACKEND';

  /// Register a factory for the given backend type.
  ///
  /// Calling this more than once for the same type replaces the previous
  /// factory.
  static void register(BackendType type, BackendFactoryFn factory) {
    _factories[type] = factory;
  }

  /// Whether a factory is registered for [type].
  static bool isRegistered(BackendType type) => _factories.containsKey(type);

  /// The list of currently registered backend types.
  static List<BackendType> get registeredTypes => _factories.keys.toList();

  /// Create a backend of the specified type.
  ///
  /// The [type] may be overridden by the `CLAUDE_BACKEND` environment
  /// variable. Throws [StateError] if no factory is registered for the
  /// effective type.
  static Future<AgentBackend> create({
    BackendType type = BackendType.directCli,
    String? executablePath,
    List<String> arguments = const [],
    String? workingDirectory,
  }) async {
    final effectiveType = _getEffectiveType(type);
    final factory = _factories[effectiveType];
    if (factory == null) {
      throw StateError(
        'No factory registered for BackendType.${effectiveType.name}. '
        'Call the backend\'s register() method before creating instances.',
      );
    }
    return factory(
      executablePath: executablePath,
      arguments: arguments,
      workingDirectory: workingDirectory,
    );
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
    return parseBackendType(envValue) ?? type;
  }

  /// Get the current environment variable value, if set.
  static String? getEnvOverride() {
    return Platform.environment[envVarName];
  }

  /// Clear all registered factories. Only for use in tests.
  static void resetForTesting() {
    _factories.clear();
  }
}

/// Parse a string to a [BackendType].
///
/// Returns null if the string doesn't match any known backend type.
/// Accepts common aliases (e.g. 'cli', 'claude', 'direct' all map to
/// [BackendType.directCli]).
BackendType? parseBackendType(String? value) {
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
    case 'acp':
      return BackendType.acp;
    default:
      return null;
  }
}
