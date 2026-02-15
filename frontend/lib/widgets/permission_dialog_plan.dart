part of 'permission_dialog.dart';

// =============================================================================
// Suggestion Widgets
// =============================================================================

class _SuggestionsRow extends StatelessWidget {
  const _SuggestionsRow({
    required this.suggestions,
    required this.behaviors,
    required this.destinations,
    required this.onBehaviorChanged,
    required this.onDestinationChanged,
  });

  final List<sdk.PermissionSuggestion> suggestions;
  final Map<int, String> behaviors;
  final Map<int, sdk.PermissionDestination> destinations;
  final void Function(int index, String value) onBehaviorChanged;
  final void Function(int index, sdk.PermissionDestination value) onDestinationChanged;

  @override
  Widget build(BuildContext context) {
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
            color: Theme.of(context).colorScheme.tertiary,
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

    return _RuleSuggestionRow(
      index: index,
      suggestion: suggestion,
      behavior: behaviors[index] ?? 'ask',
      destination: destinations[index] ??
          sdk.PermissionDestination.fromValue(suggestion.destination),
      onBehaviorChanged: onBehaviorChanged,
      onDestinationChanged: onDestinationChanged,
    );
  }
}

class _RuleSuggestionRow extends StatelessWidget {
  const _RuleSuggestionRow({
    required this.index,
    required this.suggestion,
    required this.behavior,
    required this.destination,
    required this.onBehaviorChanged,
    required this.onDestinationChanged,
  });

  final int index;
  final sdk.PermissionSuggestion suggestion;
  final String behavior;
  final sdk.PermissionDestination destination;
  final void Function(int index, String value) onBehaviorChanged;
  final void Function(int index, sdk.PermissionDestination value) onDestinationChanged;

  @override
  Widget build(BuildContext context) {
    final displayLabel = suggestion.displayLabel;
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
            color: _behaviorColor(context, behavior),
          ),
          items: const [
            DropdownMenuItem(value: 'ask', child: Text('Ask')),
            DropdownMenuItem(value: 'allow', child: Text('Allow')),
            DropdownMenuItem(value: 'deny', child: Text('Deny')),
          ],
          onChanged: (value) {
            if (value != null) {
              onBehaviorChanged(index, value);
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                onDestinationChanged(index, value);
              }
            },
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Plan View Widgets (ExitPlanMode)
// =============================================================================

class _ExpandedPlanView extends StatelessWidget {
  const _ExpandedPlanView({
    required this.permission,
    required this.projectDir,
    required this.feedbackController,
    required this.onAllow,
    required this.onDeny,
    required this.onAllowWithAcceptEdits,
    required this.onClearContextAndAcceptEdits,
    required this.onDenyWithMessage,
  });

  final sdk.PermissionRequest permission;
  final String? projectDir;
  final TextEditingController feedbackController;
  final VoidCallback onAllow;
  final VoidCallback onDeny;
  final VoidCallback onAllowWithAcceptEdits;
  final void Function(String planText)? onClearContextAndAcceptEdits;
  final void Function(String message, {bool interrupt}) onDenyWithMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plan = permission.toolInput['plan'] as String? ?? '';
    final hasPlan = plan.trim().isNotEmpty;

    final dialogBackground = colorScheme.surfaceContainerLowest;
    final markdownBackground = colorScheme.surfaceContainer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final maxPlanHeight = availableHeight.isFinite
            ? (availableHeight * 0.5).clamp(100.0, 500.0)
            : 300.0;

        return Container(
          key: PermissionDialogKeys.dialog,
          decoration: BoxDecoration(color: dialogBackground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ExpandedPlanHeader(),
              if (hasPlan)
                ConstrainedBox(
                  key: PermissionDialogKeys.planContent,
                  constraints: BoxConstraints(maxHeight: maxPlanHeight),
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: markdownBackground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: SelectionArea(
                        child: MarkdownBody(
                          data: plan,
                          styleSheet: buildMarkdownStyleSheet(
                            context,
                            fontSize: 13,
                          ),
                          builders: buildMarkdownBuilders(
                            projectDir: projectDir,
                          ),
                          onTapLink: (text, href, title) {
                            if (href != null) launchUrl(Uri.parse(href));
                          },
                        ),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  key: PermissionDialogKeys.planContent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    'No plan provided.',
                    style: textStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              _PlanApprovalFooter(
                plan: plan,
                feedbackController: feedbackController,
                onAllow: onAllow,
                onDeny: onDeny,
                onAllowWithAcceptEdits: onAllowWithAcceptEdits,
                onClearContextAndAcceptEdits: onClearContextAndAcceptEdits,
                onDenyWithMessage: onDenyWithMessage,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlanApprovalFooter extends StatelessWidget {
  const _PlanApprovalFooter({
    required this.plan,
    required this.feedbackController,
    required this.onAllow,
    required this.onDeny,
    required this.onAllowWithAcceptEdits,
    required this.onClearContextAndAcceptEdits,
    required this.onDenyWithMessage,
  });

  final String plan;
  final TextEditingController feedbackController;
  final VoidCallback onAllow;
  final VoidCallback onDeny;
  final VoidCallback onAllowWithAcceptEdits;
  final void Function(String planText)? onClearContextAndAcceptEdits;
  final void Function(String message, {bool interrupt}) onDenyWithMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Feedback text input row
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: PermissionDialogKeys.planFeedbackInput,
                    controller: feedbackController,
                    style: textStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Tell Claude what to change...',
                      hintStyle: textStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.35),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                    ),
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        onDenyWithMessage(text.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                ListenableBuilder(
                  listenable: feedbackController,
                  builder: (context, _) {
                    final hasText =
                        feedbackController.text.trim().isNotEmpty;
                    return IconButton(
                      key: PermissionDialogKeys.planFeedbackSend,
                      onPressed: hasText
                          ? () =>
                              onDenyWithMessage(feedbackController.text.trim())
                          : null,
                      icon: Icon(
                        Icons.send_rounded,
                        size: 16,
                        color: hasText
                            ? colorScheme.tertiary
                            : colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                      tooltip: 'Send feedback',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Buttons row
          Row(
            children: [
              _PlanButton(
                key: PermissionDialogKeys.planReject,
                label: 'Reject',
                icon: Icons.close,
                color: colorScheme.error,
                onPressed: onDeny,
              ),
              const Spacer(),
              if (onClearContextAndAcceptEdits != null) ...[
                Flexible(
                  child: _PlanButton(
                    key: PermissionDialogKeys.planClearContext,
                    label: 'Clear context, approve & allow edits',
                    icon: Icons.restart_alt,
                    color: colorScheme.tertiary,
                    onPressed: () =>
                        onClearContextAndAcceptEdits!(plan),
                    outlined: true,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: _PlanButton(
                  key: PermissionDialogKeys.planApproveAcceptEdits,
                  label: 'Approve & allow edits',
                  icon: Icons.edit_note,
                  color: colorScheme.tertiary,
                  onPressed: onAllowWithAcceptEdits,
                  outlined: true,
                ),
              ),
              const SizedBox(width: 6),
              _PlanButton(
                key: PermissionDialogKeys.planApproveManual,
                label: 'Approve',
                icon: Icons.check,
                color: colorScheme.primary,
                onPressed: onAllow,
                filled: true,
              ),
            ],
          ),
        ],
      ),
    );
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
  final double maxHeight = 300;

  const _ScrollableCodeBox({
    required this.content,
    required this.lineCount,
    required this.backgroundColor,
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
                    widget.backgroundColor.withValues(alpha: 0),
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
                    widget.backgroundColor.withValues(alpha: 0),
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
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              '${widget.lineCount} lines',
              style: textStyle(
                fontSize: PermissionFontSizes.smallBadge,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Plan Approval Button
// =============================================================================

/// A compact icon+label button used in the plan approval footer.
/// Supports outlined and filled variants with tooltips for longer labels.
class _PlanButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool outlined;
  final bool filled;

  const _PlanButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.outlined = false,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    );

    const buttonStyle = ButtonStyle(
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      visualDensity: VisualDensity.compact,
      minimumSize: WidgetStatePropertyAll(Size(0, 32)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    if (filled) {
      return Tooltip(
        message: label,
        child: FilledButton(
          onPressed: onPressed,
          style: buttonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(color),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          child: content,
        ),
      );
    }

    return Tooltip(
      message: label,
      child: OutlinedButton(
        onPressed: onPressed,
        style: buttonStyle.copyWith(
          foregroundColor: WidgetStatePropertyAll(color),
          side: outlined
              ? WidgetStatePropertyAll(
                  BorderSide(color: color.withValues(alpha: 0.4)))
              : null,
        ),
        child: content,
      ),
    );
  }
}
