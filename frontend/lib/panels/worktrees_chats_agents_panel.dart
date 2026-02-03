import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/conversation.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../state/selection_state.dart';
import '../widgets/editable_label.dart';
import '../widgets/styled_popup_menu.dart';
import 'panel_wrapper.dart';
import 'worktree_panel.dart';

/// Combined Worktrees + Chats + Agents panel showing full hierarchy.
///
/// Created when ChatsAgentsPanel is dropped onto Worktrees.
class WorktreesChatsAgentsPanel extends StatelessWidget {
  const WorktreesChatsAgentsPanel({
    super.key,
    required this.onSeparateChats,
  });

  /// Callback to separate chats (and agents) back into separate panels.
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
      child: const _WorktreesChatsAgentsTreeContent(),
    );
  }
}

/// Tree content for WorktreesChatsAgentsPanel - shows full hierarchy.
class _WorktreesChatsAgentsTreeContent extends StatelessWidget {
  const _WorktreesChatsAgentsTreeContent();

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
        return _WorktreeWithChatsTreeItem(
          worktree: worktree,
          selection: selection,
        );
      },
    );
  }
}

/// A worktree item with expandable chats (and their agents) underneath.
class _WorktreeWithChatsTreeItem extends StatefulWidget {
  const _WorktreeWithChatsTreeItem({
    required this.worktree,
    required this.selection,
  });

  final WorktreeState worktree;
  final SelectionState selection;

  @override
  State<_WorktreeWithChatsTreeItem> createState() =>
      _WorktreeWithChatsTreeItemState();
}

class _WorktreeWithChatsTreeItemState
    extends State<_WorktreeWithChatsTreeItem> {
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
        // Chats (nested with indent)
        if (_isExpanded && hasChildren)
          ...chats.map((chat) => _NestedChatWithAgentsItem(
                chat: chat,
                selection: widget.selection,
              )),
      ],
    );
  }
}

/// A nested chat item with its agents (double indented).
class _NestedChatWithAgentsItem extends StatefulWidget {
  const _NestedChatWithAgentsItem({
    required this.chat,
    required this.selection,
  });

  final ChatState chat;
  final SelectionState selection;

  @override
  State<_NestedChatWithAgentsItem> createState() =>
      _NestedChatWithAgentsItemState();
}

class _NestedChatWithAgentsItemState extends State<_NestedChatWithAgentsItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = widget.selection.selectedChat == widget.chat;

    // Listen to ChatState changes (e.g., rename) for immediate UI updates
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (context, _) {
        final data = widget.chat.data;
        final primaryConversation = data.primaryConversation;
        final subagents = data.subagentConversations.values.toList();
        final hasAgents = subagents.isNotEmpty;

        return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chat row (indented under worktree)
        Material(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.2)
              : Colors.transparent,
          child: Padding(
            padding:
                const EdgeInsets.only(left: 28, right: 8, top: 4, bottom: 4),
            child: Row(
              children: [
                // Expand/collapse icon for agents
                GestureDetector(
                  onTap: hasAgents
                      ? () => setState(() => _isExpanded = !_isExpanded)
                      : null,
                  child: SizedBox(
                    width: 14,
                    child: hasAgents
                        ? Icon(
                            _isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 12,
                            color: colorScheme.onSurfaceVariant,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chat_bubble_outline,
                  size: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                // Chat name (single-click to select, double-click to rename)
                Expanded(
                  child: EditableLabel(
                    text: data.name,
                    style: textTheme.bodySmall,
                    onTap: () => widget.selection.selectChat(widget.chat),
                    onSubmit: (newName) => widget.chat.rename(newName),
                  ),
                ),
                  if (hasAgents)
                    Text(
                      '${subagents.length}',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Agents (double indented)
        if (_isExpanded && hasAgents) ...[
          _DeepNestedAgentItem(
            conversation: primaryConversation,
            isSelected:
                widget.selection.selectedConversation == primaryConversation,
            onTap: () =>
                widget.selection.selectConversation(primaryConversation),
            isPrimary: true,
          ),
          ...subagents.map((subagent) => _DeepNestedAgentItem(
                conversation: subagent,
                isSelected:
                    widget.selection.selectedConversation == subagent,
                onTap: () => widget.selection.selectConversation(subagent),
                isPrimary: false,
              )),
        ],
      ],
        );
      },
    );
  }
}

/// Deeply nested agent item (under worktree > chat).
class _DeepNestedAgentItem extends StatelessWidget {
  const _DeepNestedAgentItem({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.isPrimary,
  });

  final ConversationData conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.15)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.only(left: 56, right: 8, top: 3, bottom: 3),
          child: Row(
            children: [
              Icon(
                isPrimary ? Icons.chat_bubble_outline : Icons.smart_toy_outlined,
                size: 10,
                color: isPrimary
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isPrimary ? 'Chat' : (conversation.label ?? 'Agent'),
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: isPrimary ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
