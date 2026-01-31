import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/material.dart';

import '../acp/pending_permission.dart';
import '../config/fonts.dart';

// =============================================================================
// Test Keys for AcpPermissionDialog
// =============================================================================

/// Keys for testing AcpPermissionDialog widgets.
class AcpPermissionDialogKeys {
  AcpPermissionDialogKeys._();

  /// The root container of the permission dialog.
  static const dialog = Key('acp_permission_dialog');

  /// The header showing "Permission Required: <tool>".
  static const header = Key('acp_permission_dialog_header');

  /// The content area showing tool-specific details.
  static const content = Key('acp_permission_dialog_content');

  /// The options row containing permission buttons.
  static const optionsRow = Key('acp_permission_dialog_options');

  /// The cancel button.
  static const cancelButton = Key('acp_permission_dialog_cancel');

  /// Prefix for option buttons - full key is 'acp_permission_dialog_option_X'.
  static Key optionButton(String optionId) =>
      Key('acp_permission_dialog_option_$optionId');
}

// =============================================================================
// ACP Permission Dialog Widget
// =============================================================================

/// Widget to display an ACP permission request and allow user to select an
/// option.
///
/// This is a simplified permission widget for ACP-based sessions. It displays:
/// - Tool info from the request
/// - Available permission options as buttons
/// - A cancel button to dismiss
class AcpPermissionDialog extends StatelessWidget {
  const AcpPermissionDialog({
    super.key,
    required this.permission,
    required this.onAllow,
    required this.onCancel,
  });

  /// The pending permission request from the ACP agent.
  final PendingPermission permission;

  /// Called when the user selects a permission option.
  /// Provides the option ID (e.g., 'allow_once', 'allow_always').
  final void Function(String optionId) onAllow;

  /// Called when the user cancels/dismisses the permission request.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final request = permission.request;

    // Dark purple background for the permission dialog body
    const dialogBackground = Color(0xFF2D1F3D);

    return Container(
      key: AcpPermissionDialogKeys.dialog,
      decoration: const BoxDecoration(
        color: dialogBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _AcpPermissionHeader(toolCall: request.toolCall),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _AcpPermissionContent(
              key: AcpPermissionDialogKeys.content,
              toolCall: request.toolCall,
            ),
          ),
          _AcpPermissionFooter(
            options: request.options,
            onAllow: onAllow,
            onCancel: onCancel,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Header Widget
// =============================================================================

class _AcpPermissionHeader extends StatelessWidget {
  const _AcpPermissionHeader({required this.toolCall});

  final ToolCallUpdate toolCall;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Use a rich purple for the header
    const headerPurple = Color(0xFF4A2066);

    final toolTitle = toolCall.title ?? 'Unknown Tool';

    return Container(
      key: AcpPermissionDialogKeys.header,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: headerPurple,
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Permission Required: $toolTitle',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Content Widget
// =============================================================================

class _AcpPermissionContent extends StatelessWidget {
  const _AcpPermissionContent({super.key, required this.toolCall});

  final ToolCallUpdate toolCall;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Try to extract useful info from tool call
    final content = toolCall.content;
    final rawInput = toolCall.rawInput;

    // Build content based on what's available
    final List<Widget> children = [];

    // Show content items if available
    if (content != null && content.isNotEmpty) {
      for (final item in content) {
        if (item is DiffToolCallContent) {
          children.add(_buildDiffContent(context, item));
        } else if (item is ContentToolCallContent) {
          children.add(_buildContentBlock(context, item.content));
        } else if (item is TerminalToolCallContent) {
          children.add(_buildTerminalContent(context, item));
        }
      }
    }

    // If no content, show raw input
    if (children.isEmpty && rawInput != null && rawInput.isNotEmpty) {
      children.add(_buildRawInputContent(context, rawInput));
    }

    // If still no content, show a generic message
    if (children.isEmpty) {
      children.add(
        Text(
          'This tool requires your permission to proceed.',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildDiffContent(BuildContext context, DiffToolCallContent diff) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'File: ${diff.path}',
          style: AppFonts.monoTextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        if (diff.oldText != null || diff.newText.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (diff.oldText != null)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      _truncate(diff.oldText!, 200),
                      style: AppFonts.monoTextStyle(fontSize: 10),
                    ),
                  ),
                ),
              if (diff.oldText != null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16),
                ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    _truncate(diff.newText, 200),
                    style: AppFonts.monoTextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildContentBlock(BuildContext context, ContentBlock block) {
    if (block is TextContentBlock) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          _truncate(block.text, 500),
          style: AppFonts.monoTextStyle(fontSize: 11),
        ),
      );
    }
    // For other content types, show a placeholder
    return Text(
      'Content: ${block.runtimeType}',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
      ),
    );
  }

  Widget _buildTerminalContent(
    BuildContext context,
    TerminalToolCallContent terminal,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            'Terminal: ${terminal.terminalId}',
            style: AppFonts.monoTextStyle(
              fontSize: 12,
              color: Colors.greenAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawInputContent(
    BuildContext context,
    Map<String, dynamic> rawInput,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    final details = rawInput.entries
        .map((e) => '${e.key}: ${_truncate(e.value?.toString() ?? '', 100)}')
        .join('\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        details,
        style: AppFonts.monoTextStyle(fontSize: 12),
      ),
    );
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

// =============================================================================
// Footer Widget with Options
// =============================================================================

class _AcpPermissionFooter extends StatelessWidget {
  const _AcpPermissionFooter({
    required this.options,
    required this.onAllow,
    required this.onCancel,
  });

  final List<PermissionOption> options;
  final void Function(String optionId) onAllow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: AcpPermissionDialogKeys.optionsRow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Cancel button
          OutlinedButton(
            key: AcpPermissionDialogKeys.cancelButton,
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          // Permission option buttons
          ...options.map((option) {
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _OptionButton(
                option: option,
                onPressed: () => onAllow(option.optionId),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// =============================================================================
// Option Button Widget
// =============================================================================

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.option,
    required this.onPressed,
  });

  final PermissionOption option;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (bgColor, fgColor) = _getColorsForKind(option.kind);

    // Use filled button for allow actions, outlined for reject
    final isAllowAction = option.kind == PermissionOptionKind.allowOnce ||
        option.kind == PermissionOptionKind.allowAlways;

    if (isAllowAction) {
      return FilledButton(
        key: AcpPermissionDialogKeys.optionButton(option.optionId),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(option.name),
      );
    } else {
      return OutlinedButton(
        key: AcpPermissionDialogKeys.optionButton(option.optionId),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(option.name),
      );
    }
  }

  /// Returns (background color, foreground color) based on permission kind.
  (Color, Color) _getColorsForKind(PermissionOptionKind kind) {
    return switch (kind) {
      PermissionOptionKind.allowOnce => (Colors.green, Colors.white),
      PermissionOptionKind.allowAlways => (Colors.green.shade700, Colors.white),
      PermissionOptionKind.rejectOnce => (Colors.red, Colors.white),
      PermissionOptionKind.rejectAlways => (Colors.red.shade700, Colors.white),
    };
  }
}
