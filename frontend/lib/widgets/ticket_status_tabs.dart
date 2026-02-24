import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/ticket_view_state.dart';

/// Open/Closed status tabs for the ticket list panel.
///
/// Displays two tabs with counts that filter tickets by open/closed status.
/// Reads from and writes to [TicketViewState].
class TicketStatusTabs extends StatelessWidget {
  const TicketStatusTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final viewState = context.watch<TicketViewState>();
    final isOpen = viewState.isOpenFilter;
    final openCount = viewState.openCount;
    final closedCount = viewState.closedCount;

    return Row(
      children: [
        _StatusTab(
          icon: Icons.radio_button_checked,
          iconColor: Colors.green,
          label: 'Open',
          count: openCount,
          isActive: isOpen,
          onTap: () => viewState.setIsOpenFilter(true),
        ),
        const SizedBox(width: 16),
        _StatusTab(
          icon: Icons.check_circle,
          iconColor: Colors.purple,
          label: 'Closed',
          count: closedCount,
          isActive: !isOpen,
          onTap: () => viewState.setIsOpenFilter(false),
        ),
      ],
    );
  }
}

class _StatusTab extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _StatusTab({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant;
    final color = isActive ? activeColor : inactiveColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? iconColor : inactiveColor),
            const SizedBox(width: 4),
            Text(
              '$label ($count)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
