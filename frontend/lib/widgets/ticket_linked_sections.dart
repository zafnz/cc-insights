import 'package:flutter/material.dart';

import '../models/ticket.dart';

/// Sidebar section displaying chats linked to a ticket.
///
/// Shows an uppercase "LINKED CHATS" header with a bottom border, followed by
/// a list of linked chats. Each entry shows a chat icon, the chat name in
/// primary colour (clickable), and the worktree path as status text.
///
/// Returns [SizedBox.shrink] when [linkedChats] is empty.
class LinkedChatsSection extends StatelessWidget {
  final List<LinkedChat> linkedChats;
  final ValueChanged<LinkedChat> onChatTap;

  const LinkedChatsSection({
    super.key,
    required this.linkedChats,
    required this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    if (linkedChats.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'LINKED CHATS'),
        for (final chat in linkedChats)
          _LinkedItemTile(
            icon: Icons.chat_bubble_outline,
            label: chat.chatName,
            status: chat.worktreeRoot,
            onTap: () => onChatTap(chat),
          ),
      ],
    );
  }
}

/// Sidebar section displaying worktrees linked to a ticket.
///
/// Shows an uppercase "LINKED WORKTREES" header with a bottom border, followed
/// by a list of linked worktrees. Each entry shows a tree icon, the branch name
/// (or worktree path if no branch) in primary colour (clickable), and the
/// worktree path as status text.
///
/// Returns [SizedBox.shrink] when [linkedWorktrees] is empty.
class LinkedWorktreesSection extends StatelessWidget {
  final List<LinkedWorktree> linkedWorktrees;
  final ValueChanged<LinkedWorktree> onWorktreeTap;

  const LinkedWorktreesSection({
    super.key,
    required this.linkedWorktrees,
    required this.onWorktreeTap,
  });

  @override
  Widget build(BuildContext context) {
    if (linkedWorktrees.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'LINKED WORKTREES'),
        for (final wt in linkedWorktrees)
          _LinkedItemTile(
            icon: Icons.account_tree,
            label: wt.branch ?? wt.worktreeRoot,
            status: wt.worktreeRoot,
            onTap: () => onWorktreeTap(wt),
          ),
      ],
    );
  }
}

/// Uppercase section header with a bottom border.
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      margin: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A single linked-item row: icon + clickable label + status text.
class _LinkedItemTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final VoidCallback onTap;

  const _LinkedItemTile({
    required this.icon,
    required this.label,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onTap,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: primary,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
