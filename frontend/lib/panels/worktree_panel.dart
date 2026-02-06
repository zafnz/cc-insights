import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../models/worktree_tag.dart';
import '../services/ask_ai_service.dart';
import '../services/file_system_service.dart';
import '../services/git_service.dart';
import '../services/persistence_service.dart';
import '../services/project_config_service.dart';
import '../services/project_restore_service.dart';
import '../services/script_execution_service.dart';
import '../services/settings_service.dart';
import '../state/selection_state.dart';
import '../widgets/delete_worktree_dialog.dart';
import '../widgets/styled_popup_menu.dart';
import 'panel_wrapper.dart';

/// Worktree panel - shows the list of worktrees.
class WorktreePanel extends StatelessWidget {
  const WorktreePanel({super.key});

  /// When true, animated indicators (spinners) are replaced with static
  /// widgets so that [WidgetTester.pumpAndSettle] does not hang.
  @visibleForTesting
  static bool disableAnimations = false;

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
class _WorktreeListItem extends StatefulWidget {
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

  @override
  State<_WorktreeListItem> createState() => _WorktreeListItemState();
}

class _WorktreeListItemState extends State<_WorktreeListItem> {
  /// When true, the next tap will be treated as a double-click.
  bool _awaitingSecondClick = false;

  /// Timer for resetting _awaitingSecondClick after the double-click window.
  Timer? _doubleClickTimer;

  /// Duration of the double-click detection window.
  static const _doubleClickDuration = Duration(milliseconds: 300);

  @override
  void dispose() {
    _doubleClickTimer?.cancel();
    super.dispose();
  }

  void _handleTap(BuildContext context) {
    final isPrimary = widget.worktree.data.isPrimary;

    if (isPrimary && _awaitingSecondClick) {
      // This is a double-click on the primary worktree
      _doubleClickTimer?.cancel();
      _awaitingSecondClick = false;
      context.read<SelectionState>().showProjectSettingsPanel();
    } else {
      // First click - always select the worktree
      widget.onTap();

      if (isPrimary) {
        // Start the double-click detection timer for primary worktree
        _awaitingSecondClick = true;
        _doubleClickTimer?.cancel();
        _doubleClickTimer = Timer(_doubleClickDuration, () {
          if (mounted) {
            setState(() {
              _awaitingSecondClick = false;
            });
          }
        });
      }
    }
  }

  WorktreeState get worktree => widget.worktree;
  String get repoRoot => widget.repoRoot;
  bool get isSelected => widget.isSelected;

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

  void _showContextMenu(BuildContext context, Offset position) async {
    final data = worktree.data;
    final colorScheme = Theme.of(context).colorScheme;
    final settings = context.read<SettingsService>();
    final availableTags = settings.availableTags;

    final items = <PopupMenuEntry<String>>[
      // Project Settings (only for primary worktree)
      if (data.isPrimary) ...[
        styledMenuItem(
          value: 'project_settings',
          child: Row(
            children: [
              Icon(
                Icons.settings_outlined,
                size: 16,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Project Settings',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
      ],
      // Tags submenu header with arrow indicator
      styledMenuItem(
        value: 'tags',
        child: Row(
          children: [
            Icon(
              Icons.label_outlined,
              size: 16,
              color: colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tags',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      if (!data.isPrimary) ...[
        const PopupMenuDivider(height: 8),
        styledMenuItem(
          value: 'hide',
          child: Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 16,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Hide Worktree',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
        styledMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: colorScheme.error),
              const SizedBox(width: 8),
              Text(
                'Delete Worktree',
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    ];

    final result = await showStyledMenu<String>(
      context: context,
      position: menuPositionFromOffset(position),
      items: items,
    );

    if (!context.mounted) return;

    switch (result) {
      case 'project_settings':
        context.read<SelectionState>().showProjectSettingsPanel();
      case 'tags':
        // Open the tags submenu to the right of the click position.
        _showTagsSubmenu(context, position, availableTags);
      case 'hide':
        await _handleHide(context);
      case 'delete':
        await _handleDelete(context);
      default:
        break;
    }
  }

  void _showTagsSubmenu(
    BuildContext context,
    Offset position,
    List<WorktreeTag> availableTags,
  ) async {
    final project = context.read<ProjectState>();
    final persistence = context.read<PersistenceService>();
    final colorScheme = Theme.of(context).colorScheme;
    final currentTags = List.of(worktree.tags);

    if (availableTags.isEmpty) return;

    final items = availableTags.map((tag) {
      final isChecked = currentTags.contains(tag.name);
      return styledMenuItem<String>(
        value: tag.name,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: isChecked
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: colorScheme.primary,
                    )
                  : null,
            ),
            const SizedBox(width: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: tag.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tag.name,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }).toList();

    // Position submenu slightly to the right of the original position.
    final submenuPosition = Offset(position.dx + 120, position.dy);
    final result = await showStyledMenu<String>(
      context: context,
      position: menuPositionFromOffset(submenuPosition),
      items: items,
    );

    if (result == null || !context.mounted) return;

    // Toggle the selected tag
    worktree.toggleTag(result);

    // Persist
    persistence.updateWorktreeTags(
      projectRoot: project.data.repoRoot,
      worktreePath: worktree.data.worktreeRoot,
      tags: List.of(worktree.tags),
    );

    // Re-open the submenu so the user can toggle more tags.
    if (context.mounted) {
      final updatedTags =
          context.read<SettingsService>().availableTags;
      _showTagsSubmenu(context, position, updatedTags);
    }
  }

  Future<void> _handleHide(BuildContext context) async {
    final project = context.read<ProjectState>();
    final persistenceService = context.read<PersistenceService>();
    final settings = context.read<SettingsService>();
    final archive = settings.getValue<bool>('behavior.archiveChats');

    // Archive chats before hiding if the setting is enabled
    if (archive) {
      await persistenceService.archiveWorktreeChats(
        projectRoot: project.data.repoRoot,
        worktreePath: worktree.data.worktreeRoot,
      );
    }

    // Hide from projects.json (files stay on disk)
    await persistenceService.hideWorktreeFromIndex(
      projectRoot: project.data.repoRoot,
      worktreePath: worktree.data.worktreeRoot,
    );

    if (!context.mounted) return;

    // Remove the worktree from the project state
    project.removeLinkedWorktree(worktree);
  }

  Future<void> _handleDelete(BuildContext context) async {
    final project = context.read<ProjectState>();
    final gitService = context.read<GitService>();
    final persistenceService = context.read<PersistenceService>();
    final askAiService = context.read<AskAiService>();
    final fileSystemService = context.read<FileSystemService>();
    final restoreService = context.read<ProjectRestoreService>();
    final scriptService = context.read<ScriptExecutionService>();
    final settings = context.read<SettingsService>();
    final archive = settings.getValue<bool>('behavior.archiveChats');

    // Save cost tracking for all chats in this worktree before deletion
    final projectId = PersistenceService.generateProjectId(repoRoot);
    await restoreService.saveWorktreeCostTracking(projectId, worktree);

    // Archive chats before deletion if the setting is enabled.
    // This moves chat references to the archived list so that
    // removeWorktreeFromIndex() won't delete the chat files.
    if (archive) {
      await persistenceService.archiveWorktreeChats(
        projectRoot: project.data.repoRoot,
        worktreePath: worktree.data.worktreeRoot,
      );
    }

    final deleteBranch =
        settings.getValue<bool>('behavior.deleteBranchWithWorktree');

    final result = await showDeleteWorktreeDialog(
      context: context,
      worktreePath: worktree.data.worktreeRoot,
      repoRoot: repoRoot,
      branch: worktree.data.branch,
      base: worktree.data.baseRef ?? 'main',
      projectId: projectId,
      gitService: gitService,
      persistenceService: persistenceService,
      askAiService: askAiService,
      fileSystemService: fileSystemService,
      deleteBranch: deleteBranch,
      configService: ProjectConfigService(),
      scriptService: scriptService,
    );

    if (result == DeleteWorktreeResult.deleted && context.mounted) {
      // Remove the worktree from the project state
      // Note: The filesystem watcher should also detect this, but we do it
      // explicitly to ensure immediate UI update
      project.removeLinkedWorktree(worktree);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Listen to worktree (git status) and all chats (permissions).
    return ListenableBuilder(
      listenable: Listenable.merge([worktree, ...worktree.chats]),
      builder: (context, _) {
        final data = worktree.data;
        final displayPath =
            _getRelativePath(data.worktreeRoot) ??
            data.worktreeRoot;
        // Check if any chat in this worktree has a pending permission
        final hasAnyPermissionPending =
            worktree.chats.any((chat) => chat.isWaitingForPermission);
        final hasAnyActiveChat =
            worktree.chats.any((chat) => chat.isWorking);

        final availableTags =
            context.read<SettingsService>().availableTags;

        return GestureDetector(
          onSecondaryTapUp: (details) {
            _showContextMenu(context, details.globalPosition);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.surfaceContainerHighest,
                  width: 1,
                ),
              ),
            ),
            child: Material(
              color: isSelected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => _handleTap(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: spinner + branch name + permission indicator
                    Row(
                      children: [
                        // Activity spinner
                        if (hasAnyActiveChat)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _WorktreeActivitySpinner(
                              color: colorScheme.primary,
                            ),
                          ),
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
                    // Tag pills
                    if (worktree.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: _TagPills(
                          tagNames: worktree.tags,
                          availableTags: availableTags,
                        ),
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
          ),
          ),
        );
      },
    );
  }
}

/// Displays Base and Sync badges plus uncommitted/conflict indicators.
///
/// - **Base Badge**: integration state vs merge target (local or remote)
/// - **Sync Badge**: publication state vs upstream tracking branch
/// - Uncommitted files and merge conflicts shown as inline text after badges
class InlineStatusIndicators extends StatelessWidget {
  const InlineStatusIndicators({super.key, required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final hasBase = data.commitsAheadOfMain > 0 ||
        data.commitsBehindMain > 0 ||
        data.baseRef != null;
    final hasExtra =
        data.uncommittedFiles > 0 || data.hasMergeConflict;

    if (!hasBase &&
        data.upstreamBranch == null &&
        !hasExtra) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasExtra) _ExtraIndicators(data: data),
          if (hasExtra) const SizedBox(width: 4),
          if (hasBase) _BaseBadge(data: data),
          if (hasBase) const SizedBox(width: 4),
          _SyncBadge(data: data),
        ],
      ),
    );
  }
}

/// Badge showing integration state: how far this branch is from its
/// merge target (local main or origin/main).
class _BaseBadge extends StatelessWidget {
  const _BaseBadge({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.labelSmall;
    final icon = data.isRemoteBase ? '\u{1F310}' : '\u{1F3E0}';
    final refName = data.baseRef ?? 'main';
    final ahead = data.commitsAheadOfMain;
    final behind = data.commitsBehindMain;

    final parts = <TextSpan>[
      TextSpan(text: '$icon ', style: style),
    ];

    if (ahead > 0) {
      parts.add(TextSpan(
        text: '+$ahead',
        style: style?.copyWith(color: Colors.green),
      ));
    }
    if (behind > 0) {
      if (ahead > 0) {
        parts.add(TextSpan(text: ' ', style: style));
      }
      parts.add(TextSpan(
        text: '\u{2212}$behind',
        style: style?.copyWith(color: Colors.orange),
      ));
    }
    if (ahead == 0 && behind == 0) {
      parts.add(TextSpan(
        text: '=',
        style: style?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ));
    }

    final tooltipLines = <String>['Base: $refName'];
    if (ahead > 0) {
      tooltipLines.add(
        '${data.branch} has $ahead commit${ahead == 1 ? '' : 's'}'
        ' not on $refName',
      );
    }
    if (behind > 0) {
      tooltipLines.add(
        '$refName has $behind commit${behind == 1 ? '' : 's'}'
        ' not on ${data.branch}',
      );
    }
    if (ahead > 0 && behind > 0) {
      tooltipLines.add('Branches have diverged');
    } else if (ahead == 0 && behind == 0) {
      tooltipLines.add('Up to date');
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: _BadgeContainer(
        child: RichText(text: TextSpan(children: parts)),
      ),
    );
  }
}

/// Badge showing publication state: how far this branch is from its
/// upstream tracking branch.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.labelSmall;
    final hasUpstream = data.upstreamBranch != null;

    final parts = <TextSpan>[
      TextSpan(text: '\u{2601} ', style: style),
    ];

    final tooltipLines = <String>[];

    if (!hasUpstream) {
      parts.add(TextSpan(
        text: '\u{2014}',
        style: style?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ));
      tooltipLines.add('Sync: no upstream');
      tooltipLines.add(
        '${data.branch} is not tracking a remote branch',
      );
    } else {
      final upstream = data.upstreamBranch!;
      final ahead = data.commitsAhead;
      final behind = data.commitsBehind;
      if (ahead > 0) {
        parts.add(TextSpan(
          text: '\u{2191}$ahead',
          style: style?.copyWith(color: Colors.green),
        ));
      }
      if (behind > 0) {
        if (ahead > 0) {
          parts.add(TextSpan(text: ' ', style: style));
        }
        parts.add(TextSpan(
          text: '\u{2193}$behind',
          style: style?.copyWith(color: Colors.orange),
        ));
      }
      if (ahead == 0 && behind == 0) {
        parts.add(TextSpan(
          text: '=',
          style: style?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ));
      }

      tooltipLines.add('Sync: $upstream');
      if (ahead > 0) {
        tooltipLines.add(
          '${data.branch} has $ahead commit${ahead == 1 ? '' : 's'}'
          ' not on $upstream',
        );
      }
      if (behind > 0) {
        tooltipLines.add(
          '$upstream has $behind commit${behind == 1 ? '' : 's'}'
          ' not on ${data.branch}',
        );
      }
      if (ahead > 0 && behind > 0) {
        tooltipLines.add('Branches have diverged');
      } else if (ahead == 0 && behind == 0) {
        tooltipLines.add('Up to date');
      }
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: _BadgeContainer(
        child: RichText(text: TextSpan(children: parts)),
      ),
    );
  }
}

/// Shared container styling for Base and Sync badges.
class _BadgeContainer extends StatelessWidget {
  const _BadgeContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

/// Compact inline indicators for uncommitted files and merge conflicts.
class _ExtraIndicators extends StatelessWidget {
  const _ExtraIndicators({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final parts = <TextSpan>[];

    if (data.uncommittedFiles > 0) {
      parts.add(TextSpan(
        text: '~${data.uncommittedFiles}',
        style: textTheme.labelSmall?.copyWith(color: Colors.blue),
      ));
    }

    if (data.hasMergeConflict) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(TextSpan(
        text: '!',
        style: textTheme.labelSmall?.copyWith(color: Colors.red),
      ));
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    final tooltipLines = <String>[];
    if (data.uncommittedFiles > 0) {
      final s = data.uncommittedFiles == 1 ? '' : 's';
      tooltipLines.add(
        '~ ${data.uncommittedFiles} uncommitted file$s',
      );
    }
    if (data.hasMergeConflict) {
      tooltipLines.add('! Merge conflict');
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: RichText(text: TextSpan(children: parts)),
    );
  }
}

/// A small spinner shown to the left of the worktree branch name when any
/// chat in the worktree is actively working.
///
/// When [WorktreePanel.disableAnimations] is true (e.g. in tests), renders
/// a static circle icon instead of an animated [CircularProgressIndicator]
/// so that [WidgetTester.pumpAndSettle] does not hang.
class _WorktreeActivitySpinner extends StatelessWidget {
  const _WorktreeActivitySpinner({required this.color});

  final Color color;

  static const double _size = 12.0;

  @override
  Widget build(BuildContext context) {
    if (WorktreePanel.disableAnimations) {
      return SizedBox(
        width: _size,
        height: _size,
        child: Icon(
          Icons.circle,
          size: _size,
          color: color.withValues(alpha: 0.6),
        ),
      );
    }
    return SizedBox(
      width: _size,
      height: _size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tag pills
// -----------------------------------------------------------------------------

/// Displays a row of small colored pill chips for each assigned tag.
class _TagPills extends StatelessWidget {
  const _TagPills({
    required this.tagNames,
    required this.availableTags,
  });

  final List<String> tagNames;
  final List<WorktreeTag> availableTags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: tagNames.map((name) {
        final tagDef = availableTags
            .where((t) => t.name == name)
            .firstOrNull;
        final color = tagDef?.color ?? Colors.grey;
        return _TagChip(name: name, color: color);
      }).toList(),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}




