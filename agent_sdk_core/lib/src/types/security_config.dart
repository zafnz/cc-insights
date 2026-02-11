import 'package:meta/meta.dart';
import 'session_options.dart';

/// Sandbox mode for Codex backend.
enum CodexSandboxMode {
  readOnly('read-only'),
  workspaceWrite('workspace-write'),
  dangerFullAccess('danger-full-access');

  const CodexSandboxMode(this.wireValue);

  /// The wire value sent to the Codex API.
  final String wireValue;

  /// Parse from wire value, defaulting to workspaceWrite for unknown values.
  static CodexSandboxMode fromWire(String value) {
    for (final mode in values) {
      if (mode.wireValue == value) return mode;
    }
    return workspaceWrite;
  }
}

/// Approval policy for Codex backend.
enum CodexApprovalPolicy {
  untrusted('untrusted'),
  onRequest('on-request'),
  onFailure('on-failure'),
  never('never');

  const CodexApprovalPolicy(this.wireValue);

  /// The wire value sent to the Codex API.
  final String wireValue;

  /// Parse from wire value, defaulting to onRequest for unknown values.
  static CodexApprovalPolicy fromWire(String value) {
    for (final policy in values) {
      if (policy.wireValue == value) return policy;
    }
    return onRequest;
  }
}

/// Web search mode for Codex backend.
enum CodexWebSearchMode {
  disabled('disabled'),
  cached('cached'),
  live('live');

  const CodexWebSearchMode(this.wireValue);

  /// The wire value sent to the Codex API.
  final String wireValue;

  /// Parse from wire value, defaulting to cached for unknown values.
  static CodexWebSearchMode fromWire(String value) {
    for (final mode in values) {
      if (mode.wireValue == value) return mode;
    }
    return cached;
  }
}

/// Options for workspace-write sandbox mode.
@immutable
class CodexWorkspaceWriteOptions {
  const CodexWorkspaceWriteOptions({
    this.networkAccess = false,
    this.writableRoots = const [],
    this.excludeSlashTmp = false,
    this.excludeTmpdirEnvVar = false,
  });

  /// Whether network access is allowed.
  final bool networkAccess;

  /// List of writable root paths.
  final List<String> writableRoots;

  /// Whether to exclude /tmp from writable paths.
  final bool excludeSlashTmp;

  /// Whether to exclude TMPDIR environment variable.
  final bool excludeTmpdirEnvVar;

  factory CodexWorkspaceWriteOptions.fromJson(Map<String, dynamic> json) {
    return CodexWorkspaceWriteOptions(
      networkAccess: json['network_access'] as bool? ?? false,
      writableRoots: (json['writable_roots'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      excludeSlashTmp: json['exclude_slash_tmp'] as bool? ?? false,
      excludeTmpdirEnvVar: json['exclude_tmpdir_env_var'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'network_access': networkAccess,
      'writable_roots': writableRoots,
      'exclude_slash_tmp': excludeSlashTmp,
      'exclude_tmpdir_env_var': excludeTmpdirEnvVar,
    };
  }

  CodexWorkspaceWriteOptions copyWith({
    bool? networkAccess,
    List<String>? writableRoots,
    bool? excludeSlashTmp,
    bool? excludeTmpdirEnvVar,
  }) {
    return CodexWorkspaceWriteOptions(
      networkAccess: networkAccess ?? this.networkAccess,
      writableRoots: writableRoots ?? this.writableRoots,
      excludeSlashTmp: excludeSlashTmp ?? this.excludeSlashTmp,
      excludeTmpdirEnvVar: excludeTmpdirEnvVar ?? this.excludeTmpdirEnvVar,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CodexWorkspaceWriteOptions &&
        other.networkAccess == networkAccess &&
        _listEquals(other.writableRoots, writableRoots) &&
        other.excludeSlashTmp == excludeSlashTmp &&
        other.excludeTmpdirEnvVar == excludeTmpdirEnvVar;
  }

  @override
  int get hashCode =>
      Object.hash(networkAccess, Object.hashAll(writableRoots), excludeSlashTmp,
          excludeTmpdirEnvVar);

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Security configuration for an agent session.
sealed class SecurityConfig {
  const SecurityConfig();

  Map<String, dynamic> toJson();

  static SecurityConfig fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'claude':
        return ClaudeSecurityConfig.fromJson(json);
      case 'codex':
        return CodexSecurityConfig.fromJson(json);
      default:
        throw ArgumentError('Unknown security config type: $type');
    }
  }
}

/// Security configuration for Claude backend.
@immutable
class ClaudeSecurityConfig extends SecurityConfig {
  const ClaudeSecurityConfig({
    required this.permissionMode,
  });

  /// Permission mode for the session.
  final PermissionMode permissionMode;

  factory ClaudeSecurityConfig.fromJson(Map<String, dynamic> json) {
    final modeValue = json['permissionMode'] as String?;
    final mode = modeValue != null
        ? PermissionMode.fromString(modeValue)
        : PermissionMode.defaultMode;
    return ClaudeSecurityConfig(permissionMode: mode);
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'claude',
      'permissionMode': permissionMode.value,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClaudeSecurityConfig &&
        other.permissionMode == permissionMode;
  }

  @override
  int get hashCode => permissionMode.hashCode;
}

/// Security configuration for Codex backend.
@immutable
class CodexSecurityConfig extends SecurityConfig {
  const CodexSecurityConfig({
    required this.sandboxMode,
    required this.approvalPolicy,
    this.workspaceWriteOptions,
    this.webSearch,
  });

  /// Sandbox mode for the session.
  final CodexSandboxMode sandboxMode;

  /// Approval policy for tool usage.
  final CodexApprovalPolicy approvalPolicy;

  /// Options for workspace-write sandbox mode.
  final CodexWorkspaceWriteOptions? workspaceWriteOptions;

  /// Web search mode.
  final CodexWebSearchMode? webSearch;

  /// Default configuration for Codex sessions.
  static const defaultConfig = CodexSecurityConfig(
    sandboxMode: CodexSandboxMode.workspaceWrite,
    approvalPolicy: CodexApprovalPolicy.onRequest,
  );

  factory CodexSecurityConfig.fromJson(Map<String, dynamic> json) {
    return CodexSecurityConfig(
      sandboxMode: json['sandboxMode'] != null
          ? CodexSandboxMode.fromWire(json['sandboxMode'] as String)
          : CodexSandboxMode.workspaceWrite,
      approvalPolicy: json['approvalPolicy'] != null
          ? CodexApprovalPolicy.fromWire(json['approvalPolicy'] as String)
          : CodexApprovalPolicy.onRequest,
      workspaceWriteOptions: json['workspaceWriteOptions'] != null
          ? CodexWorkspaceWriteOptions.fromJson(
              json['workspaceWriteOptions'] as Map<String, dynamic>)
          : null,
      webSearch: json['webSearch'] != null
          ? CodexWebSearchMode.fromWire(json['webSearch'] as String)
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'codex',
      'sandboxMode': sandboxMode.wireValue,
      'approvalPolicy': approvalPolicy.wireValue,
      if (workspaceWriteOptions != null)
        'workspaceWriteOptions': workspaceWriteOptions!.toJson(),
      if (webSearch != null) 'webSearch': webSearch!.wireValue,
    };
  }

  CodexSecurityConfig copyWith({
    CodexSandboxMode? sandboxMode,
    CodexApprovalPolicy? approvalPolicy,
    CodexWorkspaceWriteOptions? workspaceWriteOptions,
    CodexWebSearchMode? webSearch,
  }) {
    return CodexSecurityConfig(
      sandboxMode: sandboxMode ?? this.sandboxMode,
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      workspaceWriteOptions:
          workspaceWriteOptions ?? this.workspaceWriteOptions,
      webSearch: webSearch ?? this.webSearch,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CodexSecurityConfig &&
        other.sandboxMode == sandboxMode &&
        other.approvalPolicy == approvalPolicy &&
        other.workspaceWriteOptions == workspaceWriteOptions &&
        other.webSearch == webSearch;
  }

  @override
  int get hashCode => Object.hash(
      sandboxMode, approvalPolicy, workspaceWriteOptions, webSearch);
}
