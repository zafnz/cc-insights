import 'package:flutter/material.dart';

/// Navigation rail with main view button and settings/log icons.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;

  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 48,
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Main view button
          _NavRailButton(
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            tooltip: 'Main View',
            isSelected: selectedIndex == 0,
            onTap: () => onDestinationSelected(0),
          ),
          const SizedBox(height: 4),
          // File Manager button
          _NavRailButton(
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder,
            tooltip: 'File Manager',
            isSelected: selectedIndex == 1,
            onTap: () => onDestinationSelected(1),
          ),
          const Spacer(),
          // Bottom buttons: Logs, Settings
          Divider(
            indent: 8,
            endIndent: 8,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          _NavRailButton(
            icon: Icons.article_outlined,
            selectedIcon: Icons.article,
            tooltip: 'Logs',
            isSelected: selectedIndex == 3,
            onTap: () => onDestinationSelected(3),
          ),
          const SizedBox(height: 4),
          _NavRailButton(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            tooltip: 'Settings',
            isSelected: selectedIndex == 2,
            onTap: () => onDestinationSelected(2),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A navigation rail button (selectable destination).
class _NavRailButton extends StatelessWidget {
  const _NavRailButton({
    required this.icon,
    this.selectedIcon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              isSelected ? (selectedIcon ?? icon) : icon,
              size: 20,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

