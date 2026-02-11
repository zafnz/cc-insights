import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:flutter/material.dart';
import 'workspace_settings_panel.dart';

/// Test keys for SecurityConfigGroup widget.
class SecurityConfigGroupKeys {
  static const group = Key('security_config_group');
  static const sandboxDropdown = Key('sandbox_dropdown');
  static const approvalDropdown = Key('approval_dropdown');

  static Key sandboxMenuItem(CodexSandboxMode mode) =>
      Key('sandbox_menu_item_${mode.wireValue}');

  static Key approvalMenuItem(CodexApprovalPolicy policy) =>
      Key('approval_menu_item_${policy.wireValue}');
}

/// Grouped Codex security dropdowns: sandbox mode + approval policy.
///
/// Renders as: [ 🛡 Sandbox Mode ▾ | Ask: Policy ▾ ]
///
/// Visual states:
/// - Normal: outline-variant border
/// - Danger (dangerFullAccess or never): red border, red text
/// - Disabled: reduced opacity, no interaction
class SecurityConfigGroup extends StatelessWidget {
  const SecurityConfigGroup({
    super.key,
    required this.config,
    required this.capabilities,
    required this.onConfigChanged,
    this.isEnabled = true,
  });

  final CodexSecurityConfig config;
  final CodexSecurityCapabilities capabilities;
  final ValueChanged<CodexSecurityConfig> onConfigChanged;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDanger = config.sandboxMode == CodexSandboxMode.dangerFullAccess ||
        config.approvalPolicy == CodexApprovalPolicy.never;

    return Container(
      key: SecurityConfigGroupKeys.group,
      decoration: BoxDecoration(
        border: Border.all(
          color: isDanger
              ? colorScheme.error.withValues(alpha:0.6)
              : colorScheme.outlineVariant.withValues(alpha:0.4),
        ),
        borderRadius: BorderRadius.circular(6),
        color: colorScheme.surface.withValues(alpha:0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shield icon
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(
              Icons.shield,
              size: 14,
              color: isDanger
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          // Sandbox mode dropdown
          Flexible(
            fit: FlexFit.loose,
            child: _SandboxModeDropdown(
              config: config,
              capabilities: capabilities,
              isEnabled: isEnabled,
              onConfigChanged: onConfigChanged,
            ),
          ),
          // Vertical divider
          Container(
            width: 1,
            height: 16,
            color: colorScheme.outlineVariant.withValues(alpha:0.4),
            margin: const EdgeInsets.symmetric(horizontal: 2),
          ),
          // Approval policy dropdown
          Flexible(
            fit: FlexFit.loose,
            child: _ApprovalPolicyDropdown(
              policy: config.approvalPolicy,
              capabilities: capabilities,
              isEnabled: isEnabled,
              onChanged: (policy) {
                onConfigChanged(config.copyWith(approvalPolicy: policy));
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Sandbox mode dropdown.
class _SandboxModeDropdown extends StatefulWidget {
  const _SandboxModeDropdown({
    required this.config,
    required this.capabilities,
    required this.isEnabled,
    required this.onConfigChanged,
  });

  final CodexSecurityConfig config;
  final CodexSecurityCapabilities capabilities;
  final bool isEnabled;
  final ValueChanged<CodexSecurityConfig> onConfigChanged;

  @override
  State<_SandboxModeDropdown> createState() => _SandboxModeDropdownState();
}

class _SandboxModeDropdownState extends State<_SandboxModeDropdown> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDanger = widget.config.sandboxMode == CodexSandboxMode.dangerFullAccess;
    final isEnabled = widget.isEnabled;

    return PopupMenuButton<CodexSandboxMode>(
      key: SecurityConfigGroupKeys.sandboxDropdown,
      enabled: isEnabled,
      onSelected: (mode) {
        widget.onConfigChanged(widget.config.copyWith(sandboxMode: mode));
      },
      tooltip: '',
      offset: const Offset(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: colorScheme.primary.withValues(alpha:0.5),
          width: 1,
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      itemBuilder: (context) => [
        _buildMenuItem(
          context,
          CodexSandboxMode.readOnly,
          Icons.visibility,
          'Read Only',
          'No edits, no commands',
          Colors.green,
        ),
        _buildMenuItem(
          context,
          CodexSandboxMode.workspaceWrite,
          Icons.edit_note,
          'Workspace Write',
          'Edits + commands in workspace',
          Colors.orange,
        ),
        _buildMenuItem(
          context,
          CodexSandboxMode.dangerFullAccess,
          Icons.lock_open,
          'Full Access',
          'No restrictions (dangerous)',
          Colors.red,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<CodexSandboxMode>(
          value: null,
          height: 32,
          onTap: () {
            // Show workspace settings panel
            Future.microtask(() {
              if (!context.mounted) return;
              showWorkspaceSettingsPanel(
                context: context,
                options: widget.config.workspaceWriteOptions ??
                    const CodexWorkspaceWriteOptions(),
                webSearch: widget.config.webSearch,
                onOptionsChanged: (options) {
                  widget.onConfigChanged(
                    widget.config.copyWith(workspaceWriteOptions: options),
                  );
                },
                onWebSearchChanged: (mode) {
                  widget.onConfigChanged(
                    widget.config.copyWith(webSearch: mode),
                  );
                },
              );
            });
          },
          child: Row(
            children: [
              Icon(
                Icons.tune,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Workspace settings...',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: isEnabled ? (_) => setState(() => _isHovered = true) : null,
        onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isEnabled && _isHovered
                ? colorScheme.primary.withValues(alpha:0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _modeLabel(widget.config.sandboxMode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isDanger ? FontWeight.w600 : FontWeight.w500,
                    color: isDanger
                        ? colorScheme.error
                        : (isEnabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: isEnabled
                    ? colorScheme.onSurface.withValues(alpha:0.7)
                    : colorScheme.onSurfaceVariant.withValues(alpha:0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<CodexSandboxMode> _buildMenuItem(
    BuildContext context,
    CodexSandboxMode mode,
    IconData icon,
    String label,
    String description,
    Color iconColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = mode == widget.config.sandboxMode;
    final isLocked = !widget.capabilities.isSandboxModeAllowed(mode);

    return PopupMenuItem<CodexSandboxMode>(
      key: SecurityConfigGroupKeys.sandboxMenuItem(mode),
      value: mode,
      enabled: !isLocked,
      height: 32,
      child: Opacity(
        opacity: isLocked ? 0.35 : 1.0,
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLocked) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha:0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock,
                      size: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _modeLabel(CodexSandboxMode mode) {
    return switch (mode) {
      CodexSandboxMode.readOnly => 'Read Only',
      CodexSandboxMode.workspaceWrite => 'Workspace Write',
      CodexSandboxMode.dangerFullAccess => 'Full Access',
    };
  }
}

/// Approval policy dropdown.
class _ApprovalPolicyDropdown extends StatefulWidget {
  const _ApprovalPolicyDropdown({
    required this.policy,
    required this.capabilities,
    required this.isEnabled,
    required this.onChanged,
  });

  final CodexApprovalPolicy policy;
  final CodexSecurityCapabilities capabilities;
  final bool isEnabled;
  final ValueChanged<CodexApprovalPolicy> onChanged;

  @override
  State<_ApprovalPolicyDropdown> createState() =>
      _ApprovalPolicyDropdownState();
}

class _ApprovalPolicyDropdownState extends State<_ApprovalPolicyDropdown> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDanger = widget.policy == CodexApprovalPolicy.never;
    final isEnabled = widget.isEnabled;

    return PopupMenuButton<CodexApprovalPolicy>(
      key: SecurityConfigGroupKeys.approvalDropdown,
      enabled: isEnabled,
      onSelected: widget.onChanged,
      tooltip: '',
      offset: const Offset(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: colorScheme.primary.withValues(alpha:0.5),
          width: 1,
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      itemBuilder: (context) => [
        _buildMenuItem(
          context,
          CodexApprovalPolicy.untrusted,
          Icons.gpp_good,
          'Untrusted',
          'Prompt before commands',
          Colors.blue,
        ),
        _buildMenuItem(
          context,
          CodexApprovalPolicy.onRequest,
          Icons.front_hand,
          'On Request',
          'Prompt for outside workspace',
          Colors.orange,
        ),
        _buildMenuItem(
          context,
          CodexApprovalPolicy.onFailure,
          Icons.replay,
          'On Failure',
          'Only prompt on failure',
          colorScheme.onSurfaceVariant,
        ),
        _buildMenuItem(
          context,
          CodexApprovalPolicy.never,
          Icons.dangerous,
          'Never',
          'Skip all prompts',
          Colors.red,
        ),
      ],
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: isEnabled ? (_) => setState(() => _isHovered = true) : null,
        onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isEnabled && _isHovered
                ? colorScheme.primary.withValues(alpha:0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _policyLabel(widget.policy),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isDanger ? FontWeight.w600 : FontWeight.w500,
                    color: isDanger
                        ? colorScheme.error
                        : (isEnabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: isEnabled
                    ? colorScheme.onSurface.withValues(alpha:0.7)
                    : colorScheme.onSurfaceVariant.withValues(alpha:0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<CodexApprovalPolicy> _buildMenuItem(
    BuildContext context,
    CodexApprovalPolicy policy,
    IconData icon,
    String label,
    String description,
    Color iconColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = policy == widget.policy;
    final isLocked = !widget.capabilities.isApprovalPolicyAllowed(policy);
    final isDanger = policy == CodexApprovalPolicy.never;

    return PopupMenuItem<CodexApprovalPolicy>(
      key: SecurityConfigGroupKeys.approvalMenuItem(policy),
      value: policy,
      enabled: !isLocked,
      height: 32,
      child: Opacity(
        opacity: isLocked ? 0.35 : 1.0,
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isDanger && !isLocked
                    ? colorScheme.error
                    : (isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLocked) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha:0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock,
                      size: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _policyLabel(CodexApprovalPolicy policy) {
    return switch (policy) {
      CodexApprovalPolicy.untrusted => 'Ask: Untrusted',
      CodexApprovalPolicy.onRequest => 'Ask: On Request',
      CodexApprovalPolicy.onFailure => 'Ask: On Failure',
      CodexApprovalPolicy.never => 'Ask: Never',
    };
  }
}
