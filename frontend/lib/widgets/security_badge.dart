import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:flutter/material.dart';

/// Test keys for SecurityBadge widget.
class SecurityBadgeKeys {
  static const badge = Key('security_badge');
}

/// Security badge showing effective security posture.
///
/// Displays a small colored pill badge summarizing the security configuration:
/// - "Read Only" (green): Read-only sandbox
/// - "Sandboxed" (green): Workspace-write with approval
/// - "Auto-approve" (orange): Workspace-write without approval
/// - "Unrestricted" (orange/red): Full access with/without approval
///
/// Only shown for Codex backend.
class SecurityBadge extends StatelessWidget {
  const SecurityBadge({
    super.key,
    required this.config,
  });

  final CodexSecurityConfig config;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color, icon) = _getBadgeInfo();

    return Container(
      key: SecurityBadgeKeys.badge,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns (label, color, icon) for the current security configuration.
  (String, Color, IconData) _getBadgeInfo() {
    final sandbox = config.sandboxMode;
    final approval = config.approvalPolicy;

    // Read-only sandbox → green "Read Only"
    if (sandbox == CodexSandboxMode.readOnly) {
      return ('Read Only', Colors.green, Icons.verified_user);
    }

    // Workspace-write + (untrusted or on-request) → green "Sandboxed"
    if (sandbox == CodexSandboxMode.workspaceWrite &&
        (approval == CodexApprovalPolicy.untrusted ||
            approval == CodexApprovalPolicy.onRequest)) {
      return ('Sandboxed', Colors.green, Icons.verified_user);
    }

    // Workspace-write + (on-failure or never) → orange "Auto-approve"
    if (sandbox == CodexSandboxMode.workspaceWrite &&
        (approval == CodexApprovalPolicy.onFailure ||
            approval == CodexApprovalPolicy.never)) {
      return ('Auto-approve', Colors.orange, Icons.warning);
    }

    // Full access + (untrusted or on-request) → orange "Unrestricted"
    if (sandbox == CodexSandboxMode.dangerFullAccess &&
        (approval == CodexApprovalPolicy.untrusted ||
            approval == CodexApprovalPolicy.onRequest)) {
      return ('Unrestricted', Colors.orange, Icons.warning);
    }

    // Full access + (on-failure or never) → red "Unrestricted"
    if (sandbox == CodexSandboxMode.dangerFullAccess &&
        (approval == CodexApprovalPolicy.onFailure ||
            approval == CodexApprovalPolicy.never)) {
      return ('Unrestricted', Colors.red, Icons.warning);
    }

    // Fallback (should not happen)
    return ('Unknown', Colors.grey, Icons.help_outline);
  }
}
