part of 'permission_dialog.dart';

// =============================================================================
// Header Widgets
// =============================================================================

class _PermissionHeader extends StatelessWidget {
  const _PermissionHeader({required this.toolName});

  final String toolName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: PermissionDialogKeys.header,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primary,
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: colorScheme.onPrimary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Permission Required: $toolName',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedPlanHeader extends StatelessWidget {
  const _ExpandedPlanHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: PermissionDialogKeys.header,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: colorScheme.primary),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: colorScheme.onPrimary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Plan for Approval',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
