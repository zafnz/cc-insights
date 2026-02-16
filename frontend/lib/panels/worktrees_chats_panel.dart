import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../state/selection_state.dart';
import '../widgets/styled_popup_menu.dart';
import 'panel_wrapper.dart';
import 'worktree_panel.dart';

/// Combined Worktrees + Chats panel (without agents).
///
/// Created when the Chats panel is dropped onto Worktrees while
/// agents are still in a separate panel.
class WorktreesChatsPanel extends StatelessWidget {
  const WorktreesChatsPanel({super.key, required this.onSeparateChats});

  /// Callback to separate chats back into a separate panel.
  final VoidCallback onSeparateChats;

  @override
  Widget build(BuildContext context) {
    return PanelWrapper(
      title: 'Worktrees',
      icon: Icons.account_tree,
      contextMenuItems: [
        styledMenuItem(
          value: 'separate_chats',
          onTap: onSeparateChats,
          child: const Row(
            children: [
              Icon(Icons.call_split, size: 16),
              SizedBox(width: 8),
              Text('Separate Chats'),
            ],
          ),
        ),
      ],
      child: const _WorktreesChatsTreeContent(),
    );
  }
}

/// Tree content for WorktreesChatsPanel - shows worktrees with nested chats (no agents).
class _WorktreesChatsTreeContent extends StatelessWidget {
  const _WorktreesChatsTreeContent();

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final worktrees = project.allWorktrees;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: worktrees.length,
      itemBuilder: (context, index) {
        final worktree = worktrees[index];
        return _WorktreeWithChatsOnlyTreeItem(
          worktree: worktree,
          selection: selection,
        );
      },
    );
  }
}

/// A worktree item with expandable chats (no agents) underneath.
class _WorktreeWithChatsOnlyTreeItem extends StatefulWidget {
  const _WorktreeWithChatsOnlyTreeItem({
    required this.worktree,
    required this.selection,
  });

  final WorktreeState worktree;
  final SelectionState selection;

  @override
  State<_WorktreeWithChatsOnlyTreeItem> createState() =>
      _WorktreeWithChatsOnlyTreeItemState();
}

class _WorktreeWithChatsOnlyTreeItemState
    extends State<_WorktreeWithChatsOnlyTreeItem> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final data = widget.worktree.data;
    final isSelected = widget.selection.selectedWorktree == widget.worktree;
    final chats = widget.worktree.chats;
    final hasChildren = chats.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Worktree row
        Material(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          child: InkWell(
            onTap: () => widget.selection.selectWorktree(widget.worktree),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // Expand/collapse icon
                  GestureDetector(
                    onTap: hasChildren
                        ? () => setState(() => _isExpanded = !_isExpanded)
                        : null,
                    child: SizedBox(
                      width: 16,
                      child: hasChildren
                          ? Icon(
                              _isExpanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Worktree icon
                  Icon(
                    Icons.account_tree,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  // Branch name
                  Expanded(
                    child: Text(
                      data.branch,
                      style: textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Status indicators
                  InlineStatusIndicators(data: data),
                ],
              ),
            ),
          ),
        ),
        // Chats (nested with indent, no agents)
        if (_isExpanded && hasChildren)
          ...chats.map(
            (chat) =>
                _NestedChatOnlyItem(chat: chat, selection: widget.selection),
          ),
      ],
    );
  }
}

/// A nested chat item (without agent expansion).
class _NestedChatOnlyItem extends StatelessWidget {
  const _NestedChatOnlyItem({required this.chat, required this.selection});

  final Chat chat;
  final SelectionState selection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = selection.selectedChat == chat;
    return ListenableBuilder(
      listenable: Listenable.merge([chat.conversations]),
      builder: (context, _) {
        final data = chat.data;
        final subagentCount = data.subagentConversations.length;
        return Material(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.2)
              : Colors.transparent,
          child: InkWell(
            onTap: () => selection.selectChat(chat),
            child: Padding(
              padding: const EdgeInsets.only(
                left: 28,
                right: 8,
                top: 4,
                bottom: 4,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      data.name,
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Show agent count badge if there are subagents
                  if (subagentCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$subagentCount',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
