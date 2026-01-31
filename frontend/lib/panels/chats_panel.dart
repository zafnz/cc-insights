import 'dart:async';

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
class _ChatsListContent extends StatefulWidget {
  const _ChatsListContent();

  @override
  State<_ChatsListContent> createState() => _ChatsListContentState();
}

class _ChatsListContentState extends State<_ChatsListContent> {
  /// Keys for each chat item to get their positions for the bell animation.
  final Map<String, GlobalKey> _chatKeys = {};

  /// The chat ID that triggered the bell animation, if any.
  String? _bellTargetChatId;

  /// Subscription to track permission changes across all chats.
  final List<VoidCallback> _chatListeners = [];

  /// Previous permission counts per chat for detecting new permissions.
  final Map<String, int> _prevPermissionCounts = {};

  Future<void> _closeChat(
    BuildContext context,
    SelectionState selection,
    ChatState chat,
  ) async {
    final restoreService = context.read<ProjectRestoreService>();
    await selection.closeChat(chat, restoreService);
  }

  /// Ensures we have a GlobalKey for each chat.
  void _ensureKeysForChats(List<ChatState> chats) {
    for (final chat in chats) {
      _chatKeys.putIfAbsent(chat.data.id, () => GlobalKey());
    }
  }

  /// Sets up listeners for permission changes on all chats.
  void _setupChatListeners(List<ChatState> chats) {
    // Remove old listeners
    _removeChatListeners();

    for (final chat in chats) {
      // Track initial permission count
      _prevPermissionCounts[chat.data.id] = chat.pendingPermissionCount;

      void listener() {
        final currentCount = chat.pendingPermissionCount;
        final prevCount = _prevPermissionCounts[chat.data.id] ?? 0;

        // Trigger bell if permission count increased
        if (currentCount > prevCount && mounted) {
          setState(() {
            _bellTargetChatId = chat.data.id;
          });
        }

        _prevPermissionCounts[chat.data.id] = currentCount;
      }

      chat.addListener(listener);
      _chatListeners.add(() => chat.removeListener(listener));
    }
  }

  void _removeChatListeners() {
    for (final removeListener in _chatListeners) {
      removeListener();
    }
    _chatListeners.clear();
  }

  /// Called when the bell animation completes.
  void _onBellAnimationComplete() {
    if (mounted) {
      setState(() {
        _bellTargetChatId = null;
      });
    }
  }

  @override
  void dispose() {
    _removeChatListeners();
    super.dispose();
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

    // Ensure keys and listeners are set up
    _ensureKeysForChats(chats);
    _setupChatListeners(chats);

    // +1 for the ghost "New Chat" card
    final itemCount = chats.length + 1;

    return Stack(
      children: [
        ListView.builder(
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
              key: _chatKeys[chat.data.id],
              chat: chat,
              isSelected: isSelected,
              onTap: () => selection.selectChat(chat),
              onClose: () => _closeChat(context, selection, chat),
              onRename: (newName) => chat.rename(newName),
            );
          },
        ),
        // Animated bell overlay
        if (_bellTargetChatId != null)
          _AnimatedBellOverlay(
            targetKey: _chatKeys[_bellTargetChatId],
            onAnimationComplete: _onBellAnimationComplete,
          ),
      ],
    );
  }
}

/// Shows the animated bell overlay using an Overlay so it's not clipped.
///
/// This is a helper widget that manages inserting/removing the overlay entry.
class _AnimatedBellOverlay extends StatefulWidget {
  const _AnimatedBellOverlay({
    required this.targetKey,
    required this.onAnimationComplete,
  });

  /// The GlobalKey of the target chat item to position over.
  final GlobalKey? targetKey;

  /// Called when the animation completes.
  final VoidCallback onAnimationComplete;

  @override
  State<_AnimatedBellOverlay> createState() => _AnimatedBellOverlayState();
}

class _AnimatedBellOverlayState extends State<_AnimatedBellOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _sizeAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _shakeAnimation;

  OverlayEntry? _overlayEntry;
  Offset? _targetPosition;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Size animation: small -> big (slow) -> hold -> small (fast)
    _sizeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 10, end: 70)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50, // Grow phase
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(70),
        weight: 25, // Hold at max size while shaking
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 70, end: 10)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 25, // Shrink phase
      ),
    ]).animate(_controller);

    // Shake animation: oscillates during the hold phase
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(0),
        weight: 50, // No shake during growth
      ),
      // Shake sequence during hold
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 0.15),
        weight: 2.5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.15, end: -0.15),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.15, end: 0.12),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.12, end: -0.12),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.12, end: 0.08),
        weight: 4,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.08, end: 0),
        weight: 3.5,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0),
        weight: 25, // No shake during shrink
      ),
    ]).animate(_controller);

    // Opacity: fade in quickly, hold, then fade out
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _removeOverlay();
        widget.onAnimationComplete();
      }
    });

    // Get target position and show overlay after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTargetPosition();
      if (_targetPosition != null) {
        _showOverlay();
        _controller.forward();
      }
    });
  }

  void _updateTargetPosition() {
    final targetKey = widget.targetKey;
    if (targetKey?.currentContext != null) {
      final renderBox =
          targetKey!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null && mounted) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        // Position over the status icon (left side, after chat icon)
        // Chat icon is at x=8, status icon is at x=8+14+6=28, centered
        _targetPosition = Offset(
          position.dx + 33, // 8 (padding) + 14 (icon) + 6 (gap) + 5 (center)
          position.dy + size.height / 2,
        );
      }
    }
  }

  void _showOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (context) => _BellOverlayContent(
        targetPosition: _targetPosition!,
        sizeAnimation: _sizeAnimation,
        opacityAnimation: _opacityAnimation,
        shakeAnimation: _shakeAnimation,
        controller: _controller,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This widget doesn't render anything itself - the overlay does
    return const SizedBox.shrink();
  }
}

/// The actual bell content rendered in the overlay.
class _BellOverlayContent extends StatelessWidget {
  const _BellOverlayContent({
    required this.targetPosition,
    required this.sizeAnimation,
    required this.opacityAnimation,
    required this.shakeAnimation,
    required this.controller,
  });

  final Offset targetPosition;
  final Animation<double> sizeAnimation;
  final Animation<double> opacityAnimation;
  final Animation<double> shakeAnimation;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final size = sizeAnimation.value;
        final opacity = opacityAnimation.value;
        final shake = shakeAnimation.value;

        return Positioned(
          left: targetPosition.dx - size / 2,
          top: targetPosition.dy - size / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: shake,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.4),
                        blurRadius: size / 3,
                        spreadRadius: size / 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.notifications_active,
                      size: size * 0.6,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
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

/// Status indicator for a chat showing its current state.
///
/// Shows one of:
/// - Green filled dot: Finished with unread messages
/// - Open circle: Finished, no unread messages
/// - Spinner: Currently working
/// - Exclamation mark: Permission/question waiting
class _ChatStatusIndicator extends StatelessWidget {
  const _ChatStatusIndicator({required this.chat});

  final ChatState chat;

  @override
  Widget build(BuildContext context) {
    const size = 10.0;

    // Priority order: permission > working > unread > idle
    if (chat.isWaitingForPermission) {
      // Orange bell for pending permission
      return Icon(
        Icons.notifications_active,
        size: size + 4,
        color: Colors.orange,
      );
    }

    if (chat.isWorking) {
      // Spinner for working
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (chat.hasUnreadMessages) {
      // Filled green dot for unread messages
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.green,
        ),
      );
    }

    // Open circle for idle/no unread
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1.5,
        ),
      ),
    );
  }
}

/// A single compact chat entry in the list with close button on hover.
class _ChatListItem extends StatefulWidget {
  const _ChatListItem({
    super.key,
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
            child: InkWell(
              onTap: widget.onTap,
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
                    // Status indicator
                    _ChatStatusIndicator(chat: widget.chat),
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
          ),
        );
      },
    );
  }
}
