import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/fonts.dart';
import '../services/runtime_config.dart';

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

  /// The header showing "Permission Required: <tool>".
  static const header = Key('permission_dialog_header');

  /// The content area showing tool-specific details.
  static const content = Key('permission_dialog_content');

  /// The command display for Bash tool.
  static const bashCommand = Key('permission_dialog_bash_command');

  /// The file path display for Write/Edit tools.
  static const filePath = Key('permission_dialog_file_path');

  /// The plan content box for ExitPlanMode tool.
  static const planContent = Key('permission_dialog_plan_content');

  /// The expand button for viewing plan in full markdown.
  static const expandPlanButton = Key('permission_dialog_expand_plan');
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
// Permission Request Widget
// =============================================================================

/// Widget to display a permission request and allow user to approve/deny.
///
/// This is a full-featured permission widget that supports:
/// - Tool-specific content display (Bash, Write, Edit)
/// - Permission suggestions with behavior dropdowns (Ask/Allow/Deny)
/// - Destination dropdown for rule storage location
/// - "Enable Mode" button for setMode suggestions
class PermissionDialog extends StatefulWidget {
  const PermissionDialog({
    super.key,
    required this.request,
    required this.onAllow,
    required this.onDeny,
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
  final void Function(String message) onDeny;

  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<PermissionDialog> {
  // Track behavior choice per suggestion index ('ask', 'allow', 'deny')
  // Default is 'ask' which means don't save any rule
  final Map<int, String> _behaviors = {};

  // Track destination overrides per suggestion index
  final Map<int, sdk.PermissionDestination> _destinations = {};

  // Whether the plan view is expanded (for ExitPlanMode)
  bool _isPlanExpanded = false;

  @override
  Widget build(BuildContext context) {
    final permission = widget.request;

    // If ExitPlanMode is expanded, show the expanded plan view
    if (_isPlanExpanded && permission.toolName == 'ExitPlanMode') {
      return _buildExpandedPlanView(context, permission);
    }

    return _buildCompactView(context, permission);
  }

  /// Builds the compact (default) view of the permission dialog.
  Widget _buildCompactView(
    BuildContext context,
    sdk.PermissionRequest permission,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    // Parse suggestions
    final suggestions = permission.parsedSuggestions;

    // Check for setMode suggestion
    final setModeSuggestion =
        suggestions.where((s) => s.type == 'setMode').toList();
    final hasSetMode = setModeSuggestion.isNotEmpty;
    final modeName = hasSetMode
        ? _formatModeName(setModeSuggestion.first.mode ?? 'unknown')
        : null;

    // Check for non-setMode suggestions
    final otherSuggestions =
        suggestions.where((s) => s.type != 'setMode').toList();

    // Dark purple background for the permission dialog body
    const dialogBackground = Color(0xFF2D1F3D);

    // Use LayoutBuilder to get the available height and limit the content area
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate max content height as roughly half the available space
        // Account for header (~44px) and footer (~56px) = ~100px
        // Use a minimum of 100px and maximum of half available height
        final availableHeight = constraints.maxHeight;
        final maxContentHeight = availableHeight.isFinite
            ? (availableHeight * 0.5).clamp(100.0, 400.0)
            : 300.0;

        return Container(
          key: PermissionDialogKeys.dialog,
          // No margin, no rounded corners, no border - integrated look
          decoration: const BoxDecoration(
            color: dialogBackground,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(context),
              // Content area - tool-specific display with max height constraint
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxContentHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildToolContent(permission),
                ),
              ),
              // Footer with suggestions and buttons
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color:
                      colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  // No rounded corners - integrated look
                ),
                child: Row(
                  children: [
                    // Suggestions on the left (only non-setMode suggestions)
                    if (otherSuggestions.isNotEmpty)
                      Expanded(
                        child: _buildSuggestionsRow(otherSuggestions),
                      )
                    else
                      const Spacer(),
                    // Buttons on the right
                    const SizedBox(width: 14),
                    // Enable mode button (if setMode suggestion exists)
                    if (hasSetMode) ...[
                      OutlinedButton(
                        onPressed: () =>
                            _handleAllowWithMode(setModeSuggestion.first),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text('Enable $modeName'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton(
                      key: PermissionDialogKeys.denyButton,
                      onPressed: _handleDeny,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Deny'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: PermissionDialogKeys.allowButton,
                      onPressed: _handleAllow,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Allow'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the expanded plan view for ExitPlanMode.
  ///
  /// This view takes over the conversation output area, showing the full
  /// plan rendered as markdown with Allow/Deny buttons at the bottom.
  Widget _buildExpandedPlanView(
    BuildContext context,
    sdk.PermissionRequest permission,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final plan = permission.toolInput['plan'] as String? ?? '';

    // Dark purple background for the permission dialog body
    const dialogBackground = Color(0xFF2D1F3D);

    return Container(
      key: PermissionDialogKeys.dialog,
      decoration: const BoxDecoration(
        color: dialogBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with collapse button
          _buildExpandedPlanHeader(context),
          // Expanded markdown content - takes remaining space
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectionArea(
                  child: GptMarkdown(
                    plan,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                    onLinkTap: (url, title) {
                      launchUrl(Uri.parse(url));
                    },
                    highlightBuilder: (context, text, style) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          text,
                          style: GoogleFonts.getFont(
                            RuntimeConfig.instance.monoFontFamily,
                            fontSize: (style.fontSize ?? 13) - 1,
                            color: colorScheme.secondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Footer with Allow/Deny buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: PermissionDialogKeys.denyButton,
                  onPressed: _handleDeny,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Deny'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: PermissionDialogKeys.allowButton,
                  onPressed: _handleAllow,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Allow'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the header for the expanded plan view with a collapse button.
  Widget _buildExpandedPlanHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    const headerPurple = Color(0xFF4A2066);

    return Container(
      key: PermissionDialogKeys.header,
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
              'Permission Required: ${widget.request.toolName}',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          // Collapse button
          IconButton(
            icon: const Icon(Icons.close_fullscreen, size: 18),
            tooltip: 'Collapse plan view',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            onPressed: () {
              setState(() {
                _isPlanExpanded = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Use a rich purple for the header - matches old app style
    const headerPurple = Color(0xFF4A2066);

    return Container(
      key: PermissionDialogKeys.header,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: headerPurple,
        // No rounded corners - integrated look
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
              'Permission Required: ${widget.request.toolName}',
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

  /// Build tool-specific content display.
  Widget _buildToolContent(sdk.PermissionRequest permission) {
    final toolInput = permission.toolInput;

    switch (permission.toolName) {
      case 'Bash':
        return _buildBashContent(toolInput);
      case 'Write':
        return _buildWriteContent(toolInput);
      case 'Edit':
        return _buildEditContent(toolInput);
      case 'ExitPlanMode':
        return _buildExitPlanModeContent(toolInput);
      default:
        return _buildGenericContent(toolInput);
    }
  }

  Widget _buildBashContent(Map<String, dynamic> input) {
    final command = input['command'] as String? ?? '';
    final description = input['description'] as String?;

    return Column(
      key: PermissionDialogKeys.content,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description != null) ...[
          Text(
            description,
            style: textStyle(
              fontSize: PermissionFontSizes.description,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          key: PermissionDialogKeys.bashCommand,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            '\$ $command',
            style: monoStyle(
              fontSize: PermissionFontSizes.commandText,
              color: Colors.greenAccent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWriteContent(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    final content = input['content'] as String? ?? '';
    final lineCount = '\n'.allMatches(content).length + 1;
    final truncatedContent = _truncate(content, 500);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'File: $filePath',
          style: monoStyle(fontSize: PermissionFontSizes.filePath),
        ),
        const SizedBox(height: 4),
        _ScrollableCodeBox(
          content: truncatedContent,
          lineCount: lineCount,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }

  Widget _buildEditContent(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    final oldString = input['old_string'] as String? ?? '';
    final newString = input['new_string'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'File: $filePath',
          style: monoStyle(fontSize: PermissionFontSizes.filePath),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  _truncate(oldString, 200),
                  style: monoStyle(fontSize: PermissionFontSizes.diffContent),
                ),
              ),
            ),
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
                  _truncate(newString, 200),
                  style: monoStyle(fontSize: PermissionFontSizes.diffContent),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExitPlanModeContent(Map<String, dynamic> input) {
    final plan = input['plan'] as String? ?? '';
    final lineCount = '\n'.allMatches(plan).length + 1;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      key: PermissionDialogKeys.content,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with title and expand button
        Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Plan for Approval',
              style: textStyle(
                fontSize: PermissionFontSizes.description,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            // Expand button
            IconButton(
              key: PermissionDialogKeys.expandPlanButton,
              icon: const Icon(Icons.open_in_full, size: 16),
              tooltip: 'View full plan as markdown',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              onPressed: () {
                setState(() {
                  _isPlanExpanded = true;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Scrollable plan content box
        _ScrollableCodeBox(
          key: PermissionDialogKeys.planContent,
          content: plan,
          lineCount: lineCount,
          backgroundColor: colorScheme.surfaceContainerHighest,
          maxHeight: 200,
        ),
      ],
    );
  }

  Widget _buildGenericContent(Map<String, dynamic> input) {
    final details = input.entries
        .map((e) => '${e.key}: ${_truncate(e.value?.toString() ?? '', 100)}')
        .join('\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        details,
        style: monoStyle(fontSize: PermissionFontSizes.genericContent),
      ),
    );
  }

  /// Check if a suggestion type is actionable (user can choose behavior).
  /// Note: setMode is handled separately via the "Enable X" button, not here.
  bool _isActionableSuggestion(sdk.PermissionSuggestion s) {
    // Rule-based types: addRules, replaceRules
    if (s.type == 'addRules' || s.type == 'replaceRules') {
      return true;
    }
    // Directory-based types
    if (s.type == 'addDirectories') {
      return true;
    }
    // Other types not actionable (setMode handled via button)
    return false;
  }

  /// Build inline suggestions row for footer.
  /// Note: This only handles non-setMode suggestions.
  Widget _buildSuggestionsRow(List<sdk.PermissionSuggestion> suggestions) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    // Find actionable suggestions (already filtered to exclude setMode by
    // caller)
    final actionable = suggestions
        .asMap()
        .entries
        .where((e) => _isActionableSuggestion(e.value))
        .toList();

    // Find unknown/unhandled suggestions
    final unknown =
        suggestions.where((s) => !_isActionableSuggestion(s)).toList();

    // If no actionable suggestions, just show raw JSON of unknown ones
    if (actionable.isEmpty && unknown.isNotEmpty) {
      return Flexible(
        child: Text(
          'Unknown suggestion: ${unknown.first.rawJson}',
          style: monoStyle(
            fontSize: PermissionFontSizes.badge,
            color: Colors.orange.shade700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (actionable.isEmpty) return const SizedBox.shrink();

    // Show the first actionable suggestion
    final entry = actionable.first;
    final index = entry.key;
    final suggestion = entry.value;

    return _buildRuleSuggestionRow(index, suggestion);
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

  /// Build UI for rule-based suggestions (addRules, addDirectories, etc.).
  Widget _buildRuleSuggestionRow(int index, sdk.PermissionSuggestion suggestion) {
    final behavior = _behaviors[index] ?? 'ask';
    final destination = _destinations[index] ??
        sdk.PermissionDestination.fromValue(suggestion.destination);
    final displayLabel = suggestion.displayLabel;

    // Build the label text based on suggestion type
    final isDirectoryType = suggestion.type == 'addDirectories';
    final labelPrefix = isDirectoryType ? 'directory access: ' : '';

    return Row(
      children: [
        Text(
          'Always ',
          style: textStyle(fontSize: PermissionFontSizes.footer),
        ),
        // Behavior dropdown (Ask/Allow/Deny)
        DropdownButton<String>(
          value: behavior,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: textStyle(
            fontSize: PermissionFontSizes.footerDropdown,
            fontWeight: FontWeight.w600,
            color: _behaviorColor(behavior),
          ),
          items: const [
            DropdownMenuItem(value: 'ask', child: Text('Ask')),
            DropdownMenuItem(value: 'allow', child: Text('Allow')),
            DropdownMenuItem(value: 'deny', child: Text('Deny')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _behaviors[index] = value;
              });
            }
          },
        ),
        const SizedBox(width: 4),
        Text(
          labelPrefix,
          style: textStyle(fontSize: PermissionFontSizes.footer),
        ),
        Flexible(
          child: Text(
            displayLabel,
            style: monoStyle(
              fontSize: PermissionFontSizes.footer,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Only show location dropdown for allow/deny (not ask)
        if (behavior != 'ask') ...[
          const SizedBox(width: 12),
          Text(
            'in',
            style: textStyle(
              fontSize: PermissionFontSizes.footer,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
          DropdownButton<sdk.PermissionDestination>(
            value: destination,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: textStyle(fontSize: PermissionFontSizes.footerDropdown),
            items: sdk.PermissionDestination.values.map((d) {
              return DropdownMenuItem(
                value: d,
                child: Text(d.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _destinations[index] = value;
                });
              }
            },
          ),
        ],
      ],
    );
  }

  Color _behaviorColor(String behavior) {
    switch (behavior) {
      case 'allow':
        return Colors.green;
      case 'deny':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
    widget.onDeny('User denied permission');
  }

  /// Handle allow with setMode suggestion enabled.
  void _handleAllowWithMode(sdk.PermissionSuggestion modeSuggestion) {
    // Include the setMode suggestion
    final acceptedSuggestions = [modeSuggestion.toJson()];

    widget.onAllow(updatedPermissions: acceptedSuggestions);
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

// =============================================================================
// Scrollable Code Box Widget
// =============================================================================

/// A code display box with visual scroll indicators.
/// Shows a fade gradient at the bottom when content is scrollable,
/// and displays a line count badge.
class _ScrollableCodeBox extends StatefulWidget {
  final String content;
  final int lineCount;
  final Color backgroundColor;
  final double maxHeight;

  const _ScrollableCodeBox({
    super.key,
    required this.content,
    required this.lineCount,
    required this.backgroundColor,
    this.maxHeight = 120,
  });

  @override
  State<_ScrollableCodeBox> createState() => _ScrollableCodeBoxState();
}

class _ScrollableCodeBoxState extends State<_ScrollableCodeBox> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollDown = false;
  bool _canScrollUp = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicators);
    // Check initial state after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicators();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollIndicators() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canDown = position.pixels < position.maxScrollExtent;
    final canUp = position.pixels > position.minScrollExtent;
    if (canDown != _canScrollDown || canUp != _canScrollUp) {
      setState(() {
        _canScrollDown = canDown;
        _canScrollUp = canUp;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          width: double.infinity,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              widget.content,
              style: monoStyle(fontSize: PermissionFontSizes.codeContent),
            ),
          ),
        ),
        // Top fade gradient when scrolled down
        if (_canScrollUp)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    widget.backgroundColor,
                    widget.backgroundColor.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
        // Bottom fade gradient when more content below
        if (_canScrollDown)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    widget.backgroundColor.withOpacity(0),
                    widget.backgroundColor,
                  ],
                ),
              ),
            ),
          ),
        // Line count badge in bottom-right corner
        Positioned(
          bottom: 4,
          right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.5),
              ),
            ),
            child: Text(
              '${widget.lineCount} lines',
              style: textStyle(
                fontSize: PermissionFontSizes.smallBadge,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
