import 'package:flutter/material.dart';

/// Navigation rail with main view button, panel toggles, and settings/log icons.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.isChatsSeparate,
    required this.isAgentsSeparate,
    required this.onDestinationSelected,
    required this.onPanelToggle,
  });

  final int selectedIndex;

  /// True if chats panel is separate (not merged into worktrees).
  final bool isChatsSeparate;

  /// True if agents panel is separate (not merged into chats or worktrees).
  final bool isAgentsSeparate;

  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<String> onPanelToggle;

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
          const SizedBox(height: 8),
          Divider(
            indent: 8,
            endIndent: 8,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          // Panel toggle buttons
          // Worktrees is always "active" as it's the root panel
          _NavRailToggleButton(
            icon: Icons.account_tree_outlined,
            tooltip: 'Worktrees',
            isActive: true,
            onTap: () => onPanelToggle('worktrees'),
          ),
          const SizedBox(height: 4),
          // Chats: lit if separate, dark if merged into worktrees
          _NavRailToggleButton(
            icon: Icons.forum_outlined,
            tooltip: isChatsSeparate
                ? 'Chats'
                : 'Chats (merged - tap to split)',
            isActive: isChatsSeparate,
            onTap: () => onPanelToggle('chats'),
          ),
          const SizedBox(height: 4),
          // Agents: lit if separate, dark if merged into chats or worktrees
          _NavRailToggleButton(
            icon: Icons.smart_toy_outlined,
            tooltip: isAgentsSeparate
                ? 'Agents'
                : 'Agents (merged - tap to split)',
            isActive: isAgentsSeparate,
            onTap: () => onPanelToggle('agents'),
          ),
          const SizedBox(height: 4),
          _NavRailToggleButton(
            icon: Icons.chat_bubble_outline,
            tooltip: 'Conversation',
            isActive: true,
            onTap: () => onPanelToggle('conversation'),
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

/// A toggle button for showing/hiding panels.
class _NavRailToggleButton extends StatelessWidget {
  const _NavRailToggleButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: 18,
              color: isActive
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
