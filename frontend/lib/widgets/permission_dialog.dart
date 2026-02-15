import 'package:agent_sdk_core/agent_sdk_core.dart' show BackendProvider;
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/fonts.dart';
import 'markdown_style_helper.dart';

part 'permission_dialog_tool_content.dart';
part 'permission_dialog_headers.dart';
part 'permission_dialog_footers.dart';
part 'permission_dialog_plan.dart';

// =============================================================================
// Test Keys for PermissionDialog
// =============================================================================

/// Keys for testing PermissionDialog widgets.
///
/// Use these keys in tests to reliably find widgets without depending on
/// text content which may change with localization or formatting.
class PermissionDialogKeys {
  PermissionDialogKeys._();

  /// The root container of the permission dialog.
  static const dialog = Key('permission_dialog');

  /// The Allow button.
  static const allowButton = Key('permission_dialog_allow');

  /// The Deny button.
  static const denyButton = Key('permission_dialog_deny');

  /// The header showing "Permission Required: `<tool>`".
  static const header = Key('permission_dialog_header');

  /// The content area showing tool-specific details.
  static const content = Key('permission_dialog_content');

  /// The command display for Bash tool.
  static const bashCommand = Key('permission_dialog_bash_command');

  /// The file path display for Write/Edit tools.
  static const filePath = Key('permission_dialog_file_path');

  /// The plan content box for ExitPlanMode tool.
  static const planContent = Key('permission_dialog_plan_content');

  /// The expand button for viewing plan in full markdown (unused, kept for reference).
  static const expandPlanButton = Key('permission_dialog_expand_plan');

  /// The "Reject" button for ExitPlanMode (deny without feedback).
  static const planReject = Key('permission_dialog_plan_reject');

  /// The "Accept edits" button for ExitPlanMode (allow + setMode acceptEdits).
  static const planApproveAcceptEdits =
      Key('permission_dialog_plan_approve_accept');

  /// The "Approve" button for ExitPlanMode (allow with manual approvals).
  static const planApproveManual = Key('permission_dialog_plan_approve_manual');

  /// The text input for plan feedback (deny with message).
  static const planFeedbackInput = Key('permission_dialog_plan_feedback_input');

  /// The send button for plan feedback.
  static const planFeedbackSend = Key('permission_dialog_plan_feedback_send');

  /// The "Clear context + Accept edits" button for ExitPlanMode.
  static const planClearContext =
      Key('permission_dialog_plan_clear_context');

  /// The "Cancel Turn" button (Codex).
  static const cancelTurnButton = Key('permission_dialog_cancel_turn');

  /// The "Accept" button (Codex).
  static const acceptButton = Key('permission_dialog_accept');

  /// The "Decline" button (Codex).
  static const declineButton = Key('permission_dialog_decline');

  /// The command actions display (Codex).
  static const commandActions = Key('permission_dialog_command_actions');

  /// The reason display (Codex).
  static const reason = Key('permission_dialog_reason');
}

// =============================================================================
// Font Size Constants
// =============================================================================

/// Base font sizes for different contexts
class PermissionFontSizes {
  // Tool content area
  static const double description = 12.0;
  static const double commandText = 13.0;
  static const double filePath = 12.0;
  static const double codeContent = 11.0;
  static const double diffContent = 10.0;
  static const double genericContent = 12.0;

  // Footer / suggestions row
  static const double footer = 14.0;
  static const double footerDropdown = 15.0; // footer + 1

  // Badges and small labels
  static const double badge = 10.0;
  static const double smallBadge = 9.0;

  // Questions widget
  static const double questionText = 13.0;
  static const double questionHeader = 14.0;
}

// =============================================================================
// Text Style Helpers
// =============================================================================

/// Get a monospace TextStyle using the app's configured monospace font.
TextStyle monoStyle({
  double fontSize = 12.0,
  Color? color,
  FontWeight fontWeight = FontWeight.normal,
  FontStyle fontStyle = FontStyle.normal,
}) {
  return AppFonts.monoTextStyle(
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
  );
}

/// Get a standard TextStyle with the given properties.
TextStyle textStyle({
  double fontSize = 14.0,
  Color? color,
  FontWeight fontWeight = FontWeight.normal,
  FontStyle fontStyle = FontStyle.normal,
}) {
  return TextStyle(
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
  );
}

// =============================================================================
// File-level pure helper functions
// =============================================================================

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

/// Format mode name for display (e.g., "acceptEdits" -> "Accept Edits").
String _formatModeName(String mode) {
  switch (mode) {
    case 'acceptEdits':
      return 'Accept Edits';
    case 'bypassPermissions':
      return 'Bypass Permissions';
    case 'plan':
      return 'Plan';
    default:
      // Convert camelCase to Title Case
      return mode
          .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (m) => '${m.group(1)} ${m.group(2)}',
          )
          .replaceFirstMapped(
            RegExp(r'^[a-z]'),
            (m) => m.group(0)!.toUpperCase(),
          );
  }
}

/// Check if a suggestion type is actionable (user can choose behavior).
/// Note: setMode is handled separately via the "Enable X" button, not here.
bool _isActionableSuggestion(sdk.PermissionSuggestion s) {
  if (s.type == 'addRules' || s.type == 'replaceRules') return true;
  if (s.type == 'addDirectories') return true;
  return false;
}

Color _behaviorColor(BuildContext context, String behavior) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (behavior) {
    case 'allow':
      return colorScheme.primary;
    case 'deny':
      return colorScheme.error;
    default:
      return colorScheme.onSurfaceVariant;
  }
}

List<_AcpPermissionOption> _readAcpOptions(sdk.PermissionRequest request) {
  final raw = request.rawJson?['options'];
  if (raw is! List) return const [];
  final options = <_AcpPermissionOption>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    final id = map['optionId'] ?? map['id'];
    if (id is! String || id.isEmpty) continue;
    final label =
        map['name'] ?? map['label'] ?? map['title'] ?? id;
    options.add(_AcpPermissionOption(
      id: id,
      label: label.toString(),
      kind: map['kind'] as String?,
    ));
  }
  return options;
}

// =============================================================================
// Permission Request Widget
// =============================================================================

/// Widget to display a permission request and allow user to approve/deny.
///
/// This is a full-featured permission widget that supports:
/// - Tool-specific content display (Bash, Write, Edit)
/// - Permission suggestions with behavior dropdowns (Ask/Allow/Deny)
/// - Destination dropdown for rule storage location
/// - "Enable Mode" button for setMode suggestions
/// - Backend-aware dialogs (Claude vs Codex)
class PermissionDialog extends StatefulWidget {
  const PermissionDialog({
    super.key,
    required this.request,
    required this.onAllow,
    required this.onDeny,
    this.projectDir,
    this.onClearContextAndAcceptEdits,
    this.provider,
  });

  /// The permission request from the SDK.
  final sdk.PermissionRequest request;

  /// Called when the user allows the permission.
  /// Provides optional updated input and permissions to pass back to SDK.
  final void Function({
    Map<String, dynamic>? updatedInput,
    List<dynamic>? updatedPermissions,
  }) onAllow;

  /// Called when the user denies the permission.
  /// The callback receives a denial message explaining why.
  /// For Codex backend, interrupt can be set to true to cancel the entire turn.
  final void Function(String message, {bool interrupt}) onDeny;

  /// Called when the user wants to clear context and restart with the plan.
  /// Only used for ExitPlanMode. Provides the plan text for the new session.
  final void Function(String planText)? onClearContextAndAcceptEdits;

  /// The project directory for resolving relative file paths.
  final String? projectDir;

  /// The backend provider this request came from.
  /// When null, defaults to Claude behavior.
  final BackendProvider? provider;

  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<PermissionDialog> {
  // Track behavior choice per suggestion index ('ask', 'allow', 'deny')
  // Default is 'ask' which means don't save any rule
  final Map<int, String> _behaviors = {};

  // Track destination overrides per suggestion index
  final Map<int, sdk.PermissionDestination> _destinations = {};

  // Controller for the plan feedback text input (ExitPlanMode Option 4)
  final TextEditingController _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permission = widget.request;

    // ExitPlanMode always shows the expanded plan view
    if (permission.toolName == 'ExitPlanMode') {
      return _ExpandedPlanView(
        permission: permission,
        projectDir: widget.projectDir,
        feedbackController: _feedbackController,
        onAllow: _handleAllow,
        onDeny: _handleDeny,
        onAllowWithAcceptEdits: _handleAllowWithAcceptEdits,
        onClearContextAndAcceptEdits: widget.onClearContextAndAcceptEdits,
        onDenyWithMessage: widget.onDeny,
      );
    }

    return _CompactView(
      permission: permission,
      provider: widget.provider,
      onAllow: widget.onAllow,
      onDenyMessage: widget.onDeny,
      onHandleAllow: _handleAllow,
      onHandleDeny: _handleDeny,
      onHandleCancelTurn: _handleCancelTurn,
      onHandleDecline: _handleDecline,
      onHandleAllowWithMode: _handleAllowWithMode,
      behaviors: _behaviors,
      destinations: _destinations,
      onBehaviorChanged: (index, value) {
        setState(() => _behaviors[index] = value);
      },
      onDestinationChanged: (index, value) {
        setState(() => _destinations[index] = value);
      },
    );
  }

  void _handleAllow() {
    final permission = widget.request;

    // Build the list of accepted suggestions with chosen behavior and
    // destination
    List<Map<String, dynamic>>? acceptedSuggestions;

    final suggestions = permission.parsedSuggestions;

    // Collect all selected rule-based suggestions (not setMode - that's handled
    // separately)
    final List<Map<String, dynamic>> selected = [];

    for (final entry in _behaviors.entries) {
      final index = entry.key;
      final behaviorValue = entry.value;
      final original = suggestions[index];

      // Skip setMode - it's handled via the separate "Enable X" button
      if (original.type == 'setMode') continue;

      // For rule-based, include if user chose allow or deny (not ask)
      if (behaviorValue == 'allow' || behaviorValue == 'deny') {
        final destination = _destinations[index] ??
            sdk.PermissionDestination.fromValue(original.destination);
        selected.add(original
            .withBehavior(behaviorValue)
            .withDestination(destination.value)
            .toJson());
      }
    }

    if (selected.isNotEmpty) {
      acceptedSuggestions = selected;
    }

    widget.onAllow(updatedPermissions: acceptedSuggestions);
  }

  void _handleDeny() {
    widget.onDeny('User denied permission', interrupt: false);
  }

  /// Handle Cancel Turn (Codex) - cancels the entire turn.
  void _handleCancelTurn() {
    widget.onDeny('cancelled', interrupt: true);
  }

  /// Handle Decline (Codex) - declines without canceling the turn.
  void _handleDecline() {
    widget.onDeny('User declined permission', interrupt: false);
  }

  /// Handle allow with setMode suggestion enabled.
  void _handleAllowWithMode(sdk.PermissionSuggestion modeSuggestion) {
    // Include the setMode suggestion
    final acceptedSuggestions = [modeSuggestion.toJson()];

    widget.onAllow(updatedPermissions: acceptedSuggestions);
  }

  /// Handles allow with acceptEdits mode change (ExitPlanMode Option 2).
  void _handleAllowWithAcceptEdits() {
    widget.onAllow(
      updatedPermissions: [
        {
          'type': 'setMode',
          'mode': 'acceptEdits',
          'destination': 'session',
        },
      ],
    );
  }
}

// =============================================================================
// Compact View (non-ExitPlanMode permissions)
// =============================================================================

class _CompactView extends StatelessWidget {
  const _CompactView({
    required this.permission,
    required this.provider,
    required this.onAllow,
    required this.onDenyMessage,
    required this.onHandleAllow,
    required this.onHandleDeny,
    required this.onHandleCancelTurn,
    required this.onHandleDecline,
    required this.onHandleAllowWithMode,
    required this.behaviors,
    required this.destinations,
    required this.onBehaviorChanged,
    required this.onDestinationChanged,
  });

  final sdk.PermissionRequest permission;
  final BackendProvider? provider;
  final void Function({
    Map<String, dynamic>? updatedInput,
    List<dynamic>? updatedPermissions,
  }) onAllow;
  final void Function(String message, {bool interrupt}) onDenyMessage;
  final VoidCallback onHandleAllow;
  final VoidCallback onHandleDeny;
  final VoidCallback onHandleCancelTurn;
  final VoidCallback onHandleDecline;
  final void Function(sdk.PermissionSuggestion) onHandleAllowWithMode;
  final Map<int, String> behaviors;
  final Map<int, sdk.PermissionDestination> destinations;
  final void Function(int index, String value) onBehaviorChanged;
  final void Function(int index, sdk.PermissionDestination value) onDestinationChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isCodex = provider == BackendProvider.codex;
    final isAcp = provider == BackendProvider.acp;

    // Parse suggestions (Claude only)
    final suggestions = permission.parsedSuggestions;

    // Check for setMode suggestion (Claude only)
    final setModeSuggestion =
        suggestions.where((s) => s.type == 'setMode').toList();
    final hasSetMode = setModeSuggestion.isNotEmpty;
    final modeName = hasSetMode
        ? _formatModeName(setModeSuggestion.first.mode ?? 'unknown')
        : null;

    // Check for non-setMode suggestions (Claude only)
    final otherSuggestions =
        suggestions.where((s) => s.type != 'setMode').toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final maxContentHeight = availableHeight.isFinite
            ? (availableHeight * 0.5).clamp(100.0, 400.0)
            : 300.0;

        return Container(
          key: PermissionDialogKeys.dialog,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PermissionHeader(toolName: permission.toolName),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxContentHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _ToolContent(
                    permission: permission,
                    provider: provider,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color:
                      colorScheme.surfaceContainer.withValues(alpha: 0.3),
                ),
                child: isCodex
                    ? _CodexFooter(
                        onAllow: onHandleAllow,
                        onCancelTurn: onHandleCancelTurn,
                        onDecline: onHandleDecline,
                      )
                    : isAcp
                        ? _AcpFooter(
                            request: permission,
                            onAllow: onAllow,
                            onDeny: onDenyMessage,
                          )
                    : _ClaudeFooter(
                        otherSuggestions: otherSuggestions,
                        hasSetMode: hasSetMode,
                        setModeSuggestion: setModeSuggestion,
                        modeName: modeName,
                        onAllow: onHandleAllow,
                        onDeny: onHandleDeny,
                        onAllowWithMode: onHandleAllowWithMode,
                        behaviors: behaviors,
                        destinations: destinations,
                        onBehaviorChanged: onBehaviorChanged,
                        onDestinationChanged: onDestinationChanged,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AcpPermissionOption {
  const _AcpPermissionOption({
    required this.id,
    required this.label,
    this.kind,
  });

  final String id;
  final String label;
  final String? kind;
}
