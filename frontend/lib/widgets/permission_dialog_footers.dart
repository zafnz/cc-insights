part of 'permission_dialog.dart';

// =============================================================================
// Footer Widgets
// =============================================================================

class _CodexFooter extends StatelessWidget {
  const _CodexFooter({
    required this.onAllow,
    required this.onCancelTurn,
    required this.onDecline,
  });

  final VoidCallback onAllow;
  final VoidCallback onCancelTurn;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          key: PermissionDialogKeys.cancelTurnButton,
          onPressed: onCancelTurn,
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
            side: BorderSide(color: colorScheme.outlineVariant),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Cancel Turn'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: PermissionDialogKeys.declineButton,
          onPressed: onDecline,
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Decline'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: PermissionDialogKeys.acceptButton,
          onPressed: onAllow,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}

class _AcpFooter extends StatelessWidget {
  const _AcpFooter({
    required this.request,
    required this.onAllow,
    required this.onDeny,
  });

  final sdk.PermissionRequest request;
  final void Function({
    Map<String, dynamic>? updatedInput,
    List<dynamic>? updatedPermissions,
  }) onAllow;
  final void Function(String message, {bool interrupt}) onDeny;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = _readAcpOptions(request);

    if (options.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => onDeny('Cancelled'),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => onAllow(),
            child: const Text('Allow'),
          ),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _buildOptionButton(option, colorScheme),
        TextButton(
          onPressed: () => onDeny('Cancelled'),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildOptionButton(
    _AcpPermissionOption option,
    ColorScheme colorScheme,
  ) {
    final isReject = option.kind != null &&
        (option.kind!.startsWith('reject') ||
            option.kind!.startsWith('deny'));
    final onPressed = () => onAllow(
          updatedInput: {'optionId': option.id},
        );
    if (isReject) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.6)),
        ),
        child: Text(option.label),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      child: Text(option.label),
    );
  }
}

class _ClaudeFooter extends StatelessWidget {
  const _ClaudeFooter({
    required this.otherSuggestions,
    required this.hasSetMode,
    required this.setModeSuggestion,
    required this.modeName,
    required this.onAllow,
    required this.onDeny,
    required this.onAllowWithMode,
    required this.behaviors,
    required this.destinations,
    required this.onBehaviorChanged,
    required this.onDestinationChanged,
  });

  final List<sdk.PermissionSuggestion> otherSuggestions;
  final bool hasSetMode;
  final List<sdk.PermissionSuggestion> setModeSuggestion;
  final String? modeName;
  final VoidCallback onAllow;
  final VoidCallback onDeny;
  final void Function(sdk.PermissionSuggestion) onAllowWithMode;
  final Map<int, String> behaviors;
  final Map<int, sdk.PermissionDestination> destinations;
  final void Function(int index, String value) onBehaviorChanged;
  final void Function(int index, sdk.PermissionDestination value) onDestinationChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Suggestions on the left (only non-setMode suggestions)
        if (otherSuggestions.isNotEmpty)
          Expanded(
            child: _SuggestionsRow(
              suggestions: otherSuggestions,
              behaviors: behaviors,
              destinations: destinations,
              onBehaviorChanged: onBehaviorChanged,
              onDestinationChanged: onDestinationChanged,
            ),
          )
        else
          const Spacer(),
        // Buttons on the right
        const SizedBox(width: 14),
        // Enable mode button (if setMode suggestion exists)
        if (hasSetMode) ...[
          OutlinedButton(
            onPressed: () =>
                onAllowWithMode(setModeSuggestion.first),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.tertiary,
              side: BorderSide(color: colorScheme.tertiary.withValues(alpha: 0.5)),
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
          onPressed: onDeny,
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Deny'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: PermissionDialogKeys.allowButton,
          onPressed: onAllow,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Allow'),
        ),
      ],
    );
  }
}
