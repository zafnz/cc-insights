import 'package:agent_sdk_core/agent_sdk_core.dart';

import 'codex_process.dart';

/// Reads security configuration from Codex app-server.
class CodexConfigReader {
  const CodexConfigReader(this._process);

  final CodexProcess _process;

  /// Reads the current security configuration from the Codex server.
  ///
  /// Calls the `config/read` JSON-RPC method and parses the response into
  /// a [CodexSecurityConfig].
  Future<CodexSecurityConfig> readSecurityConfig() async {
    final result = await _process.sendRequest('config/read', {});
    final configRaw = result['config'];
    final config = configRaw is Map ? Map<String, dynamic>.from(configRaw) : null;

    if (config == null) {
      return CodexSecurityConfig.defaultConfig;
    }

    final sandboxMode = config['sandbox_mode'] as String?;
    final approvalPolicy = config['approval_policy'] as String?;
    final workspaceWriteRaw = config['sandbox_workspace_write'];
    final workspaceWrite = workspaceWriteRaw is Map
        ? Map<String, dynamic>.from(workspaceWriteRaw)
        : null;
    final webSearch = config['web_search'] as String?;

    return CodexSecurityConfig(
      sandboxMode: sandboxMode != null
          ? CodexSandboxMode.fromWire(sandboxMode)
          : CodexSandboxMode.workspaceWrite,
      approvalPolicy: approvalPolicy != null
          ? CodexApprovalPolicy.fromWire(approvalPolicy)
          : CodexApprovalPolicy.onRequest,
      workspaceWriteOptions: workspaceWrite != null
          ? CodexWorkspaceWriteOptions.fromJson(workspaceWrite)
          : null,
      webSearch:
          webSearch != null ? CodexWebSearchMode.fromWire(webSearch) : null,
    );
  }

  /// Reads security capabilities from the Codex server.
  ///
  /// Calls the `config/requirementsRead` JSON-RPC method and parses the
  /// response into a [CodexSecurityCapabilities].
  Future<CodexSecurityCapabilities> readCapabilities() async {
    final result = await _process.sendRequest('config/requirementsRead', {});
    final requirementsRaw = result['requirements'];
    final requirements = requirementsRaw is Map
        ? Map<String, dynamic>.from(requirementsRaw)
        : null;

    if (requirements == null || requirements.isEmpty) {
      return const CodexSecurityCapabilities();
    }

    final allowedSandboxModes =
        requirements['allowedSandboxModes'] as List<dynamic>?;
    final allowedApprovalPolicies =
        requirements['allowedApprovalPolicies'] as List<dynamic>?;

    return CodexSecurityCapabilities(
      allowedSandboxModes: allowedSandboxModes
          ?.map((mode) => CodexSandboxMode.fromWire(mode as String))
          .toList(),
      allowedApprovalPolicies: allowedApprovalPolicies
          ?.map((policy) => CodexApprovalPolicy.fromWire(policy as String))
          .toList(),
    );
  }
}
