import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/project_restore_service.dart';
import '../state/selection_state.dart';
import '../widgets/editable_label.dart';
import 'panel_wrapper.dart';

/// Chats panel - shows the list of chats for the selected worktree.
class ChatsPanel extends StatelessWidget {
  const ChatsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelWrapper(
      title: 'Chats',
      icon: Icons.forum_outlined,
      child: _ChatsListContent(),
    );
  }
}

/// Content of the chats list panel (without header - that's in PanelWrapper).
class _ChatsListContent extends StatelessWidget {
  const _ChatsListContent();

  Future<void> _closeChat(
    BuildContext context,
    SelectionState selection,
    ChatState chat,
  ) async {
    final restoreService = context.read<ProjectRestoreService>();
    await selection.closeChat(chat, restoreService);
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final selectedWorktree = selection.selectedWorktree;

    if (selectedWorktree == null) {
      return const _EmptyChatsPlaceholder(
        message: 'Select a worktree to view chats',
      );
    }

    final chats = selectedWorktree.chats;

    // Show empty state with placeholder message AND New Chat card
    if (chats.isEmpty) {
      return Column(
        children: [
          const Expanded(
            child: _EmptyChatsPlaceholder(
              message: 'No chats in this worktree',
            ),
          ),
          const NewChatCard(),
        ],
      );
    }

    // +1 for the ghost "New Chat" card
    final itemCount = chats.length + 1;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Last item is the ghost card
        if (index == chats.length) {
          return const NewChatCard();
        }

        final chat = chats[index];
        final isSelected = selection.selectedChat == chat;
        return _ChatListItem(
          chat: chat,
          isSelected: isSelected,
          onTap: () => selection.selectChat(chat),
          onClose: () => _closeChat(context, selection, chat),
          onRename: (newName) => chat.rename(newName),
        );
      },
    );
  }
}

/// Ghost card for creating a new chat.
///
/// Displays a subtle "New Chat" action that when clicked
/// creates a new chat in the current worktree.
class NewChatCard extends StatelessWidget {
  const NewChatCard({super.key});

  Future<void> _createNewChat(BuildContext context) async {
    final selection = context.read<SelectionState>();
    final restoreService = context.read<ProjectRestoreService>();

    // Generate a default name based on timestamp
    final now = DateTime.now();
    final name = 'Chat ${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    await selection.createChat(name, restoreService);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _createNewChat(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'New Chat',
                style: textTheme.bodySmall?.copyWith(
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

/// Placeholder when no chats are available.
class _EmptyChatsPlaceholder extends StatelessWidget {
  const _EmptyChatsPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Text(
        message,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// A single compact chat entry in the list with close button on hover.
class _ChatListItem extends StatefulWidget {
  const _ChatListItem({
    required this.chat,
    required this.isSelected,
    required this.onTap,
    required this.onClose,
    this.onRename,
  });

  final ChatState chat;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<String>? onRename;

  @override
  State<_ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<_ChatListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Listen to ChatState changes (e.g., rename) for immediate UI updates
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (context, _) {
        final data = widget.chat.data;

        // Count subagent conversations
        final subagentCount = data.subagentConversations.length;

        return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: widget.isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Chat icon
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              // Chat name (single-click to select, double-click to rename)
              Expanded(
                child: EditableLabel(
                  text: data.name,
                  style: textTheme.bodyMedium,
                  onTap: widget.onTap,
                  onSubmit: (newName) => widget.onRename?.call(newName),
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
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.close,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Close chat',
                    ),
                  )
                // Subagent count indicator (visible when not hovered)
                else if (subagentCount > 0)
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
    });
  }
}
