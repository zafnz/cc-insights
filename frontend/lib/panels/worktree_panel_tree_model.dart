part of 'worktree_panel.dart';

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
