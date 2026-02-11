import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/conversation.dart';
import '../services/project_restore_service.dart';
import '../state/selection_state.dart';
import '../widgets/editable_label.dart';
import '../widgets/styled_popup_menu.dart';
import 'chats_panel.dart' show ChatStatusIndicator, NewChatCard;
import 'panel_wrapper.dart';
import 'shared_tree_widgets.dart';

/// Combined Chats + Agents panel showing chats with nested agents.
///
/// Created when the Agents panel is dropped onto the Chats panel.
/// Shows a tree view with chats as parents and their agents as children.
class ChatsAgentsPanel extends StatelessWidget {
  const ChatsAgentsPanel({
    super.key,
    required this.onSeparateAgents,
  });

  /// Callback to separate agents back into a separate panel.
  final VoidCallback onSeparateAgents;

  @override
  Widget build(BuildContext context) {
    return PanelWrapper(
      title: 'Chats',
      icon: Icons.forum_outlined,
      contextMenuItems: [
        styledMenuItem(
          value: 'separate_agents',
          onTap: onSeparateAgents,
          child: const Row(
            children: [
              Icon(Icons.call_split, size: 16),
              SizedBox(width: 8),
              Text('Separate Agents'),
            ],
          ),
        ),
      ],
      child: const _ChatsAgentsTreeContent(),
    );
  }
}

/// Tree content for ChatsAgentsPanel - shows chats with nested agents.
class _ChatsAgentsTreeContent extends StatelessWidget {
  const _ChatsAgentsTreeContent();

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final selectedWorktree = selection.selectedWorktree;

    if (selectedWorktree == null) {
      return const EmptyPlaceholder(
        message: 'Select a worktree to view chats',
      );
    }

    final chats = selectedWorktree.chats;

    if (chats.isEmpty) {
      return const Column(
        children: [
          Expanded(
            child: EmptyPlaceholder(message: 'No chats in this worktree'),
          ),
          NewChatCard(),
        ],
      );
    }

    // +1 for the ghost "New Chat" card
    final itemCount = chats.length + 1;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == chats.length) {
          return const NewChatCard();
        }
        final chat = chats[index];
        return _ChatWithAgentsTreeItem(
          chat: chat,
          selection: selection,
        );
      },
    );
  }
}

/// A chat item with expandable agents underneath.
class _ChatWithAgentsTreeItem extends StatefulWidget {
  const _ChatWithAgentsTreeItem({
    required this.chat,
    required this.selection,
  });

  final ChatState chat;
  final SelectionState selection;

  @override
  State<_ChatWithAgentsTreeItem> createState() =>
      _ChatWithAgentsTreeItemState();
}

class _ChatWithAgentsTreeItemState extends State<_ChatWithAgentsTreeItem> {
  bool _isExpanded = true;
  bool _isHovered = false;

  Future<void> _closeChat(BuildContext context) async {
    final restoreService = context.read<ProjectRestoreService>();
    await widget.selection.closeChat(widget.chat, restoreService);
  }

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
        final hasChildren = subagents.isNotEmpty;

        return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chat row
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Material(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                : Colors.transparent,
            child: InkWell(
              onTap: () => widget.selection.selectChat(widget.chat),
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
                    // Chat icon
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    // Status indicator
                    ChatStatusIndicator(chat: widget.chat),
                    const SizedBox(width: 6),
                    // Chat name (single-click to select, double-click to rename)
                    Expanded(
                      child: EditableLabel(
                        text: data.name,
                        style: textTheme.bodyMedium,
                        onTap: () => widget.selection.selectChat(widget.chat),
                        onSubmit: (newName) => widget.chat.rename(newName),
                      ),
                    ),
                    // Close button (visible on hover)
                    if (_isHovered)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 14,
                          onPressed: () => _closeChat(context),
                          icon: Icon(
                            Icons.close,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: 'Close chat',
                        ),
                      )
                    // Agent count badge (visible when not hovered)
                    else if (subagents.isNotEmpty)
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
                          '${subagents.length}',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Agents (nested with indent)
        if (_isExpanded && hasChildren) ...[
          // Primary conversation entry
          _NestedAgentItem(
            conversation: primaryConversation,
            isSelected:
                widget.selection.selectedConversation == primaryConversation,
            onTap: () =>
                widget.selection.selectConversation(primaryConversation),
            isPrimary: true,
          ),
          // Subagent entries
          ...subagents.map((subagent) => _NestedAgentItem(
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

/// A nested agent item within a chat (indented).
class _NestedAgentItem extends StatelessWidget {
  const _NestedAgentItem({
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
          ? colorScheme.primaryContainer.withValues(alpha: 0.2)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 36, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Icon(
                isPrimary ? Icons.chat_bubble_outline : Icons.smart_toy_outlined,
                size: 12,
                color: isPrimary
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isPrimary ? 'Chat' : (conversation.label ?? 'Agent'),
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: isPrimary ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Entry count
              Text(
                '${conversation.entries.length}',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
