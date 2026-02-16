import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import '../models/worktree_tag.dart';
import '../services/ask_ai_service.dart';
import '../services/file_system_service.dart';
import '../services/git_service.dart';
import '../services/log_service.dart';
import '../services/persistence_service.dart';
import '../services/project_config_service.dart';
import '../services/project_restore_service.dart';
import '../services/script_execution_service.dart';
import '../services/menu_action_service.dart';
import '../services/runtime_config.dart';
import '../services/settings_service.dart';
import '../services/worktree_watcher_service.dart';
import '../state/selection_state.dart';
import '../widgets/base_selector_dialog.dart';
import '../widgets/commit_dialog.dart';
import '../widgets/conflict_resolution_dialog.dart';
import '../widgets/delete_worktree_dialog.dart';
import '../widgets/squash_dialog.dart';
import '../widgets/insights_widgets.dart';
import '../widgets/styled_popup_menu.dart';
import 'panel_wrapper.dart';

part 'worktree_panel_tree_model.dart';
part 'worktree_panel_tree_rendering.dart';
part 'worktree_panel_items.dart';
part 'worktree_panel_badges.dart';

// -----------------------------------------------------------------------------
// Worktree panel
// -----------------------------------------------------------------------------

/// Worktree panel - shows the list of worktrees.
class WorktreePanel extends StatefulWidget {
  const WorktreePanel({super.key});

  /// When true, animated indicators (spinners) are replaced with static
  /// widgets so that [WidgetTester.pumpAndSettle] does not hang.
  @visibleForTesting
  static bool disableAnimations = false;

  @override
  State<WorktreePanel> createState() => _WorktreePanelState();
}

class _WorktreePanelState extends State<WorktreePanel> {
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final project = context.watch<ProjectState>();
    final hasHiddenWorktrees = project.allWorktrees.any((w) => w.hidden);

    return PanelWrapper(
      title: 'Worktrees',
      icon: Icons.account_tree,
      trailing: hasHiddenWorktrees
          ? _HiddenToggle(
              showHidden: _showHidden,
              onChanged: (value) => setState(() => _showHidden = value),
            )
          : null,
      contextMenuItems: [
        styledMenuItem(
          value: 'restore',
          onTap: () {
            context.read<MenuActionService>().triggerAction(
              MenuAction.restoreWorktree,
            );
          },
          child: Row(
            children: [
              Icon(Icons.restore, size: 16, color: colorScheme.onSurface),
              const SizedBox(width: 8),
              Text(
                'Restore Worktree...',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ],
      child: _WorktreeListContent(showHidden: _showHidden),
    );
  }
}

/// Compact "Hidden <switch>" toggle for the worktree panel header.
class _HiddenToggle extends StatelessWidget {
  const _HiddenToggle({required this.showHidden, required this.onChanged});

  final bool showHidden;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Hidden',
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 2),
        SizedBox(
          height: 20,
          width: 34,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Switch(
              value: showHidden,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

/// Content of the worktree list panel (without header - that's in PanelWrapper).
class _WorktreeListContent extends StatefulWidget {
  const _WorktreeListContent({required this.showHidden});

  final bool showHidden;

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

  /// Listeners on worktree states for tree-structure changes (baseRef/branch).
  final List<VoidCallback> _worktreeListeners = [];

  /// Cached baseRef/branch per worktree to detect tree-structure changes.
  final Map<String, String?> _prevBaseRefs = {};
  final Map<String, String> _prevBranches = {};

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
        _prevPermissionCounts[chat.data.id] =
            chat.permissions.pendingPermissionCount;

        void listener() {
          final currentCount = chat.permissions.pendingPermissionCount;
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

        chat.permissions.addListener(listener);
        _chatListeners.add(() => chat.permissions.removeListener(listener));
      }
    }
  }

  void _removeChatListeners() {
    for (final removeListener in _chatListeners) {
      removeListener();
    }
    _chatListeners.clear();
  }

  /// Listens to each worktree for baseRef/branch changes that affect tree
  /// structure. Triggers [setState] when the tree needs rebuilding.
  void _setupWorktreeListeners(List<WorktreeState> worktrees) {
    _removeWorktreeListeners();

    for (final wt in worktrees) {
      final key = wt.data.worktreeRoot;
      _prevBaseRefs[key] = wt.data.baseRef;
      _prevBranches[key] = wt.data.branch;

      void listener() {
        final newBaseRef = wt.data.baseRef;
        final newBranch = wt.data.branch;
        final oldBaseRef = _prevBaseRefs[key];
        final oldBranch = _prevBranches[key];

        if (newBaseRef != oldBaseRef || newBranch != oldBranch) {
          _prevBaseRefs[key] = newBaseRef;
          _prevBranches[key] = newBranch;
          if (mounted) setState(() {});
        }
      }

      wt.addListener(listener);
      _worktreeListeners.add(() => wt.removeListener(listener));
    }
  }

  void _removeWorktreeListeners() {
    for (final removeListener in _worktreeListeners) {
      removeListener();
    }
    _worktreeListeners.clear();
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
    _removeWorktreeListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final allWorktrees = project.allWorktrees;
    final worktrees = widget.showHidden
        ? allWorktrees
        : allWorktrees.where((w) => !w.hidden).toList();

    // Ensure keys and listeners are set up (for all worktrees, not just visible)
    _ensureKeysForWorktrees(allWorktrees);
    _setupChatListeners(allWorktrees, selection.selectedWorktree);
    _setupWorktreeListeners(allWorktrees);

    final treeItems = _buildTreeItems(worktrees);

    return Stack(
      children: [
        ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: treeItems.length,
          itemBuilder: (context, index) {
            final item = treeItems[index];
            return switch (item) {
              _WorktreeTreeItem(
                :final worktree,
                :final depth,
                :final isLast,
                :final ancestorIsLast,
              ) =>
                _TreeIndentWrapper(
                  depth: depth,
                  isLast: isLast,
                  ancestorIsLast: ancestorIsLast,
                  child: _WorktreeListItem(
                    key: _worktreeKeys[worktree.data.worktreeRoot],
                    worktree: worktree,
                    repoRoot: project.data.repoRoot,
                    isSelected: selection.selectedWorktree == worktree,
                    onTap: () => selection.selectWorktree(worktree),
                  ),
                ),
              _BaseMarkerTreeItem(:final baseRef) => _BaseMarker(
                baseRef: baseRef,
              ),
              _GhostTreeItem() => const CreateWorktreeCard(),
            };
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
