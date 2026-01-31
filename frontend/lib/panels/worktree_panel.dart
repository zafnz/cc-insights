import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../state/selection_state.dart';
import 'panel_wrapper.dart';

/// Worktree panel - shows the list of worktrees.
class WorktreePanel extends StatelessWidget {
  const WorktreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelWrapper(
      title: 'Worktrees',
      icon: Icons.account_tree,
      child: _WorktreeListContent(),
    );
  }
}

/// Content of the worktree list panel (without header - that's in PanelWrapper).
class _WorktreeListContent extends StatefulWidget {
  const _WorktreeListContent();

  @override
  State<_WorktreeListContent> createState() => _WorktreeListContentState();
}

class _WorktreeListContentState extends State<_WorktreeListContent> {
  /// Keys for each worktree item to get their positions for the bell animation.
  final Map<String, GlobalKey> _worktreeKeys = {};

  /// The worktree path that triggered the bell animation, if any.
  String? _bellTargetWorktreePath;

  /// Listeners for permission changes across all chats in all worktrees.
  final List<VoidCallback> _chatListeners = [];

  /// Previous permission counts per chat for detecting new permissions.
  final Map<String, int> _prevPermissionCounts = {};

  /// Ensures we have a GlobalKey for each worktree.
  void _ensureKeysForWorktrees(List<WorktreeState> worktrees) {
    for (final worktree in worktrees) {
      _worktreeKeys.putIfAbsent(worktree.data.worktreeRoot, () => GlobalKey());
    }
  }

  /// Sets up listeners for permission changes on all chats in all worktrees.
  void _setupChatListeners(
    List<WorktreeState> worktrees,
    WorktreeState? selectedWorktree,
  ) {
    // Remove old listeners
    _removeChatListeners();

    for (final worktree in worktrees) {
      for (final chat in worktree.chats) {
        // Track initial permission count
        _prevPermissionCounts[chat.data.id] = chat.pendingPermissionCount;

        void listener() {
          final currentCount = chat.pendingPermissionCount;
          final prevCount = _prevPermissionCounts[chat.data.id] ?? 0;

          // Trigger bell if permission count increased AND this is not the
          // currently selected worktree
          if (currentCount > prevCount &&
              worktree != selectedWorktree &&
              mounted) {
            setState(() {
              _bellTargetWorktreePath = worktree.data.worktreeRoot;
            });
          }

          _prevPermissionCounts[chat.data.id] = currentCount;
        }

        chat.addListener(listener);
        _chatListeners.add(() => chat.removeListener(listener));
      }
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
        _bellTargetWorktreePath = null;
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
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final worktrees = project.allWorktrees;

    // Ensure keys and listeners are set up
    _ensureKeysForWorktrees(worktrees);
    _setupChatListeners(worktrees, selection.selectedWorktree);

    // +1 for the ghost "Create New Worktree" card
    final itemCount = worktrees.length + 1;

    return Stack(
      children: [
        ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // Last item is the ghost card
            if (index == worktrees.length) {
              return const CreateWorktreeCard();
            }

            final worktree = worktrees[index];
            final isSelected = selection.selectedWorktree == worktree;
            return _WorktreeListItem(
              key: _worktreeKeys[worktree.data.worktreeRoot],
              worktree: worktree,
              repoRoot: project.data.repoRoot,
              isSelected: isSelected,
              onTap: () => selection.selectWorktree(worktree),
            );
          },
        ),
        // Animated bell overlay for non-selected worktrees
        if (_bellTargetWorktreePath != null)
          _AnimatedBellOverlay(
            targetKey: _worktreeKeys[_bellTargetWorktreePath],
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

  /// The GlobalKey of the target worktree item to position over.
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
        // Position over the permission indicator (right side of branch name)
        _targetPosition = Offset(
          position.dx + size.width - 20,
          position.dy + 12, // Near top where branch name is
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

/// Ghost card for creating a new worktree.
///
/// Displays a subtle "New Worktree" action that when clicked
/// will (in the future) open a dialog to create a new git worktree.
class CreateWorktreeCard extends StatelessWidget {
  const CreateWorktreeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.read<SelectionState>().showCreateWorktreePanel();
        },
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'New Worktree',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

/// A single compact worktree entry in the list.
class _WorktreeListItem extends StatelessWidget {
  const _WorktreeListItem({
    super.key,
    required this.worktree,
    required this.repoRoot,
    required this.isSelected,
    required this.onTap,
  });

  final WorktreeState worktree;
  final String repoRoot;
  final bool isSelected;
  final VoidCallback onTap;

  /// Computes a relative path from the repo root to the worktree.
  /// Returns null for the primary worktree (at repo root).
  String? _getRelativePath(String worktreePath) {
    // Primary worktree at repo root - show full path
    if (worktreePath == repoRoot) {
      return null;
    }

    // Split paths into components
    final repoComponents = repoRoot.split('/');
    final worktreeComponents = worktreePath.split('/');

    // Find common prefix length
    int commonLength = 0;
    while (commonLength < repoComponents.length &&
        commonLength < worktreeComponents.length &&
        repoComponents[commonLength] == worktreeComponents[commonLength]) {
      commonLength++;
    }

    // Build relative path: go up from repo, then down to worktree
    final upCount = repoComponents.length - commonLength;
    final downPath = worktreeComponents.skip(commonLength).toList();

    final parts = <String>[];
    for (int i = 0; i < upCount; i++) {
      parts.add('..');
    }
    parts.addAll(downPath);

    return parts.isEmpty ? '.' : parts.join('/');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final data = worktree.data;
    // Show relative path for linked worktrees, full path for primary
    final displayPath =
        _getRelativePath(data.worktreeRoot) ?? data.worktreeRoot;

    // Listen to all chats in this worktree to detect permission changes
    return ListenableBuilder(
      listenable: Listenable.merge(worktree.chats),
      builder: (context, _) {
        // Check if any chat in this worktree has a pending permission
        final hasAnyPermissionPending =
            worktree.chats.any((chat) => chat.isWaitingForPermission);

        return Material(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Branch name + permission indicator
                  Row(
                    children: [
                      // Branch name (normal weight, ~13px)
                      Expanded(
                        child: Text(
                          data.branch,
                          style: textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Permission indicator (orange bell)
                      if (hasAnyPermissionPending)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.notifications_active,
                            size: 14,
                            color: Colors.orange,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Path + status on same line (muted, monospace, ~11px)
                  Row(
                    children: [
                      // Path (full for primary, relative for linked)
                      Expanded(
                        child: Text(
                          displayPath,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Inline status indicators
                      InlineStatusIndicators(data: data),
                    ],
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

/// Compact inline status indicators using arrow format: "↑2 ↓1 ~3"
class InlineStatusIndicators extends StatelessWidget {
  const InlineStatusIndicators({super.key, required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final parts = <TextSpan>[];

    // Commits ahead (green arrow up)
    if (data.commitsAhead > 0) {
      parts.add(
        TextSpan(
          text: '↑${data.commitsAhead}',
          style: textTheme.labelSmall?.copyWith(color: Colors.green),
        ),
      );
    }

    // Commits behind (orange arrow down)
    if (data.commitsBehind > 0) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(
        TextSpan(
          text: '↓${data.commitsBehind}',
          style: textTheme.labelSmall?.copyWith(color: Colors.orange),
        ),
      );
    }

    // Uncommitted changes (blue tilde)
    if (data.uncommittedFiles > 0) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(
        TextSpan(
          text: '~${data.uncommittedFiles}',
          style: textTheme.labelSmall?.copyWith(color: Colors.blue),
        ),
      );
    }

    // Merge conflict (red exclamation)
    if (data.hasMergeConflict) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(
        TextSpan(
          text: '!',
          style: textTheme.labelSmall?.copyWith(color: Colors.red),
        ),
      );
    }

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: RichText(text: TextSpan(children: parts)),
    );
  }
}
