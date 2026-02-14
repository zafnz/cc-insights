import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../services/menu_action_service.dart';
import '../services/runtime_config.dart';
import '../services/settings_service.dart';
import '../state/selection_state.dart';
import '../widgets/delete_worktree_dialog.dart';
import '../widgets/styled_popup_menu.dart';
import 'panel_wrapper.dart';

// -----------------------------------------------------------------------------
// Tree item types for the flattened tree list
// -----------------------------------------------------------------------------

/// Represents one row in the flattened tree list for the ListView.
sealed class _TreeItem {
  const _TreeItem();
}

/// A worktree card in the tree.
class _WorktreeTreeItem extends _TreeItem {
  final WorktreeState worktree;
  final int depth;           // 0=primary, 1=child, 2=grandchild...
  final bool isLast;         // last sibling at this level
  final List<bool> ancestorIsLast; // per ancestor depth, whether it was last

  const _WorktreeTreeItem({
    required this.worktree,
    required this.depth,
    required this.isLast,
    required this.ancestorIsLast,
  });
}

/// A non-worktree base marker (grey bar showing e.g. "origin/main").
class _BaseMarkerTreeItem extends _TreeItem {
  final String baseRef;
  const _BaseMarkerTreeItem({required this.baseRef});
}

/// The ghost "New Worktree" card at the bottom.
class _GhostTreeItem extends _TreeItem {
  const _GhostTreeItem();
}

// -----------------------------------------------------------------------------
// Tree building function
// -----------------------------------------------------------------------------

/// Builds the flat tree item list from the worktree list.
List<_TreeItem> _buildTreeItems(List<WorktreeState> worktrees) {
  if (worktrees.isEmpty) return [const _GhostTreeItem()];

  final primary = worktrees.first;
  final linked = worktrees.skip(1).toList();

  // Build lookup: branch -> worktree (for visible worktrees only)
  final branchToWorktree = <String, WorktreeState>{};
  for (final wt in worktrees) {
    branchToWorktree[wt.data.branch] = wt;
  }

  // Group linked worktrees by parent
  final childrenOf = <String, List<WorktreeState>>{}; // key = worktreeRoot
  final baseMarkerGroups = <String, List<WorktreeState>>{}; // key = baseRef string

  for (final wt in linked) {
    final baseRef = wt.data.baseRef;

    if (baseRef == null || baseRef == primary.data.branch) {
      childrenOf.putIfAbsent(primary.data.worktreeRoot, () => []).add(wt);
    } else if (branchToWorktree.containsKey(baseRef) &&
               branchToWorktree[baseRef] != wt) {
      final parent = branchToWorktree[baseRef]!;
      childrenOf.putIfAbsent(parent.data.worktreeRoot, () => []).add(wt);
    } else {
      baseMarkerGroups.putIfAbsent(baseRef, () => []).add(wt);
    }
  }

  final result = <_TreeItem>[];
  final visited = <String>{}; // circular reference guard

  // 1. Primary worktree
  result.add(_WorktreeTreeItem(
    worktree: primary,
    depth: 0,
    isLast: false,
    ancestorIsLast: const [],
  ));
  visited.add(primary.data.worktreeRoot);

  // 2. Primary's children (DFS)
  _addChildrenDFS(result, primary.data.worktreeRoot, childrenOf, 1, const [], visited);

  // 3. Base marker groups (sorted by baseRef)
  final sortedMarkerKeys = baseMarkerGroups.keys.toList()..sort();
  for (final baseRef in sortedMarkerKeys) {
    result.add(_BaseMarkerTreeItem(baseRef: baseRef));
    final children = baseMarkerGroups[baseRef]!;
    for (int i = 0; i < children.length; i++) {
      final wt = children[i];
      final isLastChild = (i == children.length - 1);
      if (visited.contains(wt.data.worktreeRoot)) continue;
      visited.add(wt.data.worktreeRoot);

      result.add(_WorktreeTreeItem(
        worktree: wt,
        depth: 1,
        isLast: isLastChild,
        ancestorIsLast: const [],
      ));

      // Recurse for grandchildren
      _addChildrenDFS(result, wt.data.worktreeRoot, childrenOf, 2, [isLastChild], visited);
    }
  }

  // 4. Ghost card
  result.add(const _GhostTreeItem());

  return result;
}

void _addChildrenDFS(
  List<_TreeItem> result,
  String parentKey,
  Map<String, List<WorktreeState>> childrenOf,
  int depth,
  List<bool> ancestorIsLast,
  Set<String> visited,
) {
  final children = childrenOf[parentKey];
  if (children == null || children.isEmpty) return;

  for (int i = 0; i < children.length; i++) {
    final wt = children[i];
    if (visited.contains(wt.data.worktreeRoot)) continue;
    visited.add(wt.data.worktreeRoot);

    final isLastChild = (i == children.length - 1);

    result.add(_WorktreeTreeItem(
      worktree: wt,
      depth: depth,
      isLast: isLastChild,
      ancestorIsLast: ancestorIsLast,
    ));

    // Recurse
    _addChildrenDFS(
      result,
      wt.data.worktreeRoot,
      childrenOf,
      depth + 1,
      [...ancestorIsLast, isLastChild],
      visited,
    );
  }
}

// -----------------------------------------------------------------------------
// Tree indent widgets
// -----------------------------------------------------------------------------

class _IndentGuidePainter extends CustomPainter {
  _IndentGuidePainter({
    required this.color,
    required this.hasTick,
    required this.isLast,
    required this.showLine,
  });

  final Color color;
  final bool hasTick;
  final bool isLast;
  final bool showLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showLine && !hasTick) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const lineX = 9.0;

    if (showLine) {
      final bottom = isLast ? size.height / 2 : size.height;
      canvas.drawLine(Offset(lineX, 0), Offset(lineX, bottom), paint);
    }

    if (hasTick) {
      final tickY = size.height / 2;
      canvas.drawLine(Offset(lineX, tickY), Offset(lineX + 8, tickY), paint);
    }
  }

  @override
  bool shouldRepaint(_IndentGuidePainter oldDelegate) =>
      color != oldDelegate.color ||
      hasTick != oldDelegate.hasTick ||
      isLast != oldDelegate.isLast ||
      showLine != oldDelegate.showLine;
}

class _IndentGuide extends StatelessWidget {
  const _IndentGuide({
    this.hasTick = false,
    this.isLast = false,
    this.showLine = true,
  });

  final bool hasTick;
  final bool isLast;
  final bool showLine;

  static const double width = 20.0;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _IndentGuidePainter(
          color: color,
          hasTick: hasTick,
          isLast: isLast,
          showLine: showLine,
        ),
      ),
    );
  }
}

class _TreeIndentWrapper extends StatelessWidget {
  const _TreeIndentWrapper({
    required this.depth,
    required this.isLast,
    required this.ancestorIsLast,
    required this.child,
  });

  final int depth;
  final bool isLast;
  final List<bool> ancestorIsLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (depth == 0) return child;

    Widget result = child;

    // Build inside-out: innermost level first
    for (int i = depth - 1; i >= 0; i--) {
      final isInnermostLevel = (i == depth - 1);
      final isAncestorLast = (i < ancestorIsLast.length) ? ancestorIsLast[i] : false;

      result = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IndentGuide(
            hasTick: isInnermostLevel,
            isLast: isInnermostLevel ? isLast : false,
            showLine: isInnermostLevel || !isAncestorLast,
          ),
          Expanded(child: result),
        ],
      );
    }

    return IntrinsicHeight(child: result);
  }
}

// -----------------------------------------------------------------------------
// Base marker widget
// -----------------------------------------------------------------------------

class _BaseMarker extends StatelessWidget {
  const _BaseMarker({super.key, required this.baseRef});

  final String baseRef;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.surfaceContainerHighest,
            width: 1,
          ),
        ),
      ),
      child: Text(
        baseRef,
        style: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}

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
    final hasHiddenWorktrees =
        project.allWorktrees.any((w) => w.hidden);

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
              Icon(
                Icons.restore,
                size: 16,
                color: colorScheme.onSurface,
              ),
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
  const _HiddenToggle({
    required this.showHidden,
    required this.onChanged,
  });

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
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
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
              _WorktreeTreeItem(:final worktree, :final depth, :final isLast, :final ancestorIsLast) =>
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
              _BaseMarkerTreeItem(:final baseRef) =>
                _BaseMarker(baseRef: baseRef),
              _GhostTreeItem() =>
                const CreateWorktreeCard(),
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
        if (worktree.hidden)
          styledMenuItem(
            value: 'unhide',
            child: Row(
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                Text(
                  'Unhide Worktree',
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ],
            ),
          )
        else
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
      case 'unhide':
        await _handleUnhide(context);
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

    // Set hidden flag in projects.json
    await persistenceService.hideWorktreeFromIndex(
      projectRoot: project.data.repoRoot,
      worktreePath: worktree.data.worktreeRoot,
    );

    if (!context.mounted) return;

    // Update in-memory state and notify project so the panel header rebuilds
    worktree.setHidden(true);
    project.notifyListeners();
  }

  Future<void> _handleUnhide(BuildContext context) async {
    final project = context.read<ProjectState>();
    final persistenceService = context.read<PersistenceService>();

    // Clear hidden flag in projects.json
    await persistenceService.unhideWorktreeFromIndex(
      projectRoot: project.data.repoRoot,
      worktreePath: worktree.data.worktreeRoot,
    );

    if (!context.mounted) return;

    // Update in-memory state and notify project so the panel header rebuilds
    worktree.setHidden(false);
    project.notifyListeners();
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
    final archive = settings.getEffectiveValue<bool>('behavior.archiveChats');

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
        settings.getEffectiveValue<bool>('behavior.deleteBranchWithWorktree');

    if (!context.mounted) return;
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
        // Check if any chat in this worktree has a pending permission
        final hasAnyPermissionPending =
            worktree.chats.any((chat) => chat.isWaitingForPermission);
        final hasAnyActiveChat =
            worktree.chats.any((chat) => chat.isWorking);

        final availableTags =
            context.read<SettingsService>().availableTags;

        Widget item = GestureDetector(
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
                        // Hidden indicator
                        if (worktree.hidden)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.visibility_off,
                              size: 12,
                              color: colorScheme.onSurfaceVariant,
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
                    // Primary worktree: show full path trimmed from the start.
                    // Linked worktrees: cost/token summary instead of path.
                    Row(
                      children: [
                        if (data.isPrimary)
                          Expanded(
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: Text(
                                data.worktreeRoot,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: RuntimeConfig.instance.showWorktreeCost
                                ? _WorktreeCostSummary(worktree: worktree)
                                : const SizedBox.shrink(),
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

        if (worktree.hidden) {
          item = Opacity(opacity: 0.5, child: item);
        }

        return item;
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

// -----------------------------------------------------------------------------
// Cost/token summary for linked worktrees
// -----------------------------------------------------------------------------

/// Displays aggregated cost and token usage per backend for a linked worktree.
///
/// Shows total cost followed by per-backend token counts, e.g.:
/// `$5.20 - Claude 🪙5M Codex 🪙2.7M`
///
/// Only renders when there is usage data. Hidden for primary worktrees.
class _WorktreeCostSummary extends StatelessWidget {
  const _WorktreeCostSummary({required this.worktree});

  final WorktreeState worktree;

  @override
  Widget build(BuildContext context) {
    final costPerBackend = worktree.costPerBackend;
    if (costPerBackend.isEmpty) return const SizedBox.shrink();

    final totalCost = costPerBackend.values.fold(
      0.0,
      (sum, v) => sum + v.costUsd,
    );
    final hasAnyCost = costPerBackend.values.any((v) => v.costUsd > 0);

    final textStyle = TextStyle(fontSize: 11, color: Colors.grey[600]);

    return ClipRect(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAnyCost) ...[
            Text(
              '\$${_formatCost(totalCost)}',
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '-',
                style: textStyle,
              ),
            ),
          ],
          // Per-backend token summaries
          ...costPerBackend.entries.expand((entry) {
            final label = switch (entry.key) {
              'codex' => 'Codex',
              'acp' => 'ACP',
              _ => 'Claude',
            };
            return [
              Flexible(
                child: Text(
                  label,
                  style: textStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.token,
                size: 12,
                color: Colors.grey[600],
              ),
              Flexible(
                child: Text(
                  _formatTokenCount(entry.value.totalTokens),
                  style: textStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
            ];
          }),
        ],
      ),
    );
  }

  static String _formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}k';
    }
    return count.toString();
  }

  static String _formatCost(double cost) {
    if (cost >= 0.01 || cost == 0) {
      return cost.toStringAsFixed(2);
    }
    return cost.toStringAsFixed(4);
  }
}
