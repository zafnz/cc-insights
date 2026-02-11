import 'security_config.dart';

/// Security capabilities for an agent backend.
sealed class SecurityCapabilities {
  const SecurityCapabilities();
}

/// Security capabilities for Claude backend.
class ClaudeSecurityCapabilities extends SecurityCapabilities {
  const ClaudeSecurityCapabilities({
    this.supportsPermissionModeChange = true,
    this.supportsSuggestions = true,
  });

  /// Whether the backend supports changing permission mode mid-session.
  final bool supportsPermissionModeChange;

  /// Whether the backend supports permission suggestions.
  final bool supportsSuggestions;
}

/// Security capabilities for Codex backend.
class CodexSecurityCapabilities extends SecurityCapabilities {
  const CodexSecurityCapabilities({
    this.allowedSandboxModes,
    this.allowedApprovalPolicies,
    this.supportsMidSessionChange = true,
  });

  /// Allowed sandbox modes (null means all modes are allowed).
  final List<CodexSandboxMode>? allowedSandboxModes;

  /// Allowed approval policies (null means all policies are allowed).
  final List<CodexApprovalPolicy>? allowedApprovalPolicies;

  /// Whether the backend supports changing security config mid-session.
  final bool supportsMidSessionChange;

  /// Check if a sandbox mode is allowed.
  bool isSandboxModeAllowed(CodexSandboxMode mode) {
    return allowedSandboxModes == null || allowedSandboxModes!.contains(mode);
  }

  /// Check if an approval policy is allowed.
  bool isApprovalPolicyAllowed(CodexApprovalPolicy policy) {
    return allowedApprovalPolicies == null ||
        allowedApprovalPolicies!.contains(policy);
  }
}
