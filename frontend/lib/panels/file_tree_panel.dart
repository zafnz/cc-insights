import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/file_tree_node.dart';
import '../state/file_manager_state.dart';
import 'panel_wrapper.dart';

/// File tree panel - shows the file tree for the selected worktree.
///
/// This panel displays a hierarchical view of files in the selected worktree.
/// It listens to [FileManagerState] for tree updates and handles various
/// states: no selection, loading, error, and tree available.
class FileTreePanel extends StatelessWidget {
  const FileTreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final fileManagerState = context.watch<FileManagerState>();
    final isLoadingTree = fileManagerState.isLoadingTree;

    return PanelWrapper(
      title: 'Files',
      icon: Icons.folder,
      trailing: _RefreshButton(isLoading: isLoadingTree),
      child: const _FileTreeContent(),
    );
  }
}

/// Refresh button for the file tree panel.
///
/// Disabled while loading with a spinning icon. When enabled,
/// clicking it calls [FileManagerState.refreshFileTree].
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 16),
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 28,
        minHeight: 28,
      ),
      tooltip: 'Refresh file tree',
      onPressed: isLoading
          ? null
          : () {
              final fileManagerState =
                  context.read<FileManagerState>();
              fileManagerState.refreshFileTree();
            },
    );
  }
}

/// Content of the file tree panel (without header - that's in PanelWrapper).
class _FileTreeContent extends StatelessWidget {
  const _FileTreeContent();

  @override
  Widget build(BuildContext context) {
    final fileManagerState = context.watch<FileManagerState>();
    final selectedWorktree = fileManagerState.selectedWorktree;
    final isLoadingTree = fileManagerState.isLoadingTree;
    final error = fileManagerState.error;
    final rootNode = fileManagerState.rootNode;

    // No worktree selected
    if (selectedWorktree == null) {
      return const _NoWorktreeSelected();
    }

    // Loading state
    if (isLoadingTree) {
      return const _LoadingIndicator();
    }

    // Error state
    if (error != null) {
      return _ErrorMessage(message: error);
    }

    // Tree available
    if (rootNode != null) {
      return _FileTreeView(rootNode: rootNode);
    }

    // Fallback to no worktree selected (shouldn't reach here normally)
    return const _NoWorktreeSelected();
  }
}


/// Widget shown when no worktree is selected.
class _NoWorktreeSelected extends StatelessWidget {
  const _NoWorktreeSelected();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No worktree selected',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Select a worktree to browse files',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget shown while the file tree is loading.
class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading file tree...',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget shown when there was an error building the file tree.
class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load file tree',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the file tree using a ListView.
///
/// Flattens the tree into a list (depth-first) respecting expanded state
/// from [FileManagerState.expandedPaths].
/// Uses [ListView.builder] for performance with large trees.
class _FileTreeView extends StatelessWidget {
  const _FileTreeView({required this.rootNode});

  final FileTreeNode rootNode;

  @override
  Widget build(BuildContext context) {
    // Watch only the expandedPaths set, not the entire state
    final expandedPaths = context.select<FileManagerState, Set<String>>(
      (state) => state.expandedPaths,
    );

    final flattenedNodes = _flattenTree(
      rootNode.children,
      depth: 0,
      expandedPaths: expandedPaths,
    );

    if (flattenedNodes.isEmpty) {
      return const _EmptyTreeMessage();
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      itemCount: flattenedNodes.length,
      itemBuilder: (context, index) {
        final (node, depth) = flattenedNodes[index];
        return _FileTreeItem(key: ValueKey(node.path), node: node, depth: depth);
      },
    );
  }

  /// Flattens tree into list of (node, depth) tuples, respecting expandedPaths.
  static List<(FileTreeNode, int)> _flattenTree(
    List<FileTreeNode> nodes, {
    required int depth,
    required Set<String> expandedPaths,
  }) {
    final result = <(FileTreeNode, int)>[];
    for (final node in nodes) {
      result.add((node, depth));
      final isExpanded = expandedPaths.contains(node.path);
      if (node.isDirectory && isExpanded && node.children.isNotEmpty) {
        result.addAll(_flattenTree(
          node.children,
          depth: depth + 1,
          expandedPaths: expandedPaths,
        ));
      }
    }
    return result;
  }
}

/// Message shown when the tree is empty (no files in worktree).
class _EmptyTreeMessage extends StatelessWidget {
  const _EmptyTreeMessage();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No files found',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single item in the file tree (file or directory).
///
/// Displays an icon, name, and optional expand/collapse chevron for folders.
/// Indentation increases with depth (16px per level).
///
/// Click behavior:
/// - Directories: Click on name or expand icon toggles expand/collapse
/// - Files: Click selects the file for viewing
class _FileTreeItem extends StatefulWidget {
  const _FileTreeItem({
    super.key,
    required this.node,
    required this.depth,
  });

  final FileTreeNode node;
  final int depth;

  @override
  State<_FileTreeItem> createState() => _FileTreeItemState();
}

class _FileTreeItemState extends State<_FileTreeItem> {
  bool _isHovered = false;

  static const double _indentPerLevel = 12.0;
  static const double _itemHeight = 24.0;
  static const double _iconSize = 18.0;

  void _handleTap() {
    if (widget.node.isDirectory) {
      _toggleExpanded();
    } else {
      // File selection (Task 2.4)
      _selectFile();
    }
  }

  void _selectFile() {
    final fileManagerState = context.read<FileManagerState>();
    fileManagerState.selectFile(widget.node.path);
  }

  void _toggleExpanded() {
    final fileManagerState = context.read<FileManagerState>();
    fileManagerState.toggleExpanded(widget.node.path);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Select only what this item needs - file selection and this node's expanded state
    final selectedFilePath = context.select<FileManagerState, String?>(
      (state) => state.selectedFilePath,
    );
    // Only directories need to watch expanded state
    final isExpanded = widget.node.isDirectory
        ? context.select<FileManagerState, bool>(
            (state) => state.isExpanded(widget.node.path),
          )
        : false;

    final leftPadding = widget.depth * _indentPerLevel + 8.0;
    final isSelected =
        widget.node.isFile && selectedFilePath == widget.node.path;

    // Determine background color based on state
    Color backgroundColor;
    if (isSelected) {
      backgroundColor = colorScheme.primaryContainer.withValues(alpha: 0.6);
    } else if (_isHovered) {
      backgroundColor =
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    } else {
      backgroundColor = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          height: _itemHeight,
          color: backgroundColor,
          child: Padding(
            padding: EdgeInsets.only(left: leftPadding, right: 8),
            child: Row(
              children: [
                // Expand/collapse chevron (only for directories)
                _buildExpandIcon(colorScheme, isExpanded),
                const SizedBox(width: 4),
                // File/folder icon
                _buildNodeIcon(colorScheme, isExpanded),
                const SizedBox(width: 6),
                // File/folder name
                Expanded(
                  child: Text(
                    widget.node.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the expand/collapse chevron icon for directories.
  ///
  /// Shows chevron_right when collapsed, expand_more when expanded.
  /// For files, returns empty space to maintain alignment.
  Widget _buildExpandIcon(ColorScheme colorScheme, bool isExpanded) {
    if (!widget.node.isDirectory) {
      // Empty space to maintain alignment for files
      return const SizedBox(width: _iconSize);
    }

    // Clickable chevron for directories (icon changes based on expanded state)
    return GestureDetector(
      onTap: _toggleExpanded,
      child: Icon(
        isExpanded ? Icons.expand_more : Icons.chevron_right,
        size: _iconSize,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// Builds the file or folder icon based on node type.
  Widget _buildNodeIcon(ColorScheme colorScheme, bool isExpanded) {
    if (widget.node.isDirectory) {
      return Icon(
        isExpanded ? Icons.folder_open : Icons.folder,
        size: _iconSize,
        color: colorScheme.primary,
      );
    }

    // File icon - could be enhanced to show different icons by file type
    return Icon(
      _getFileIcon(),
      size: _iconSize,
      color: colorScheme.onSurfaceVariant,
    );
  }

  /// Returns an appropriate icon for the file based on its extension.
  IconData _getFileIcon() {
    final name = widget.node.name.toLowerCase();

    // Common file types
    if (name.endsWith('.dart')) return Icons.code;
    if (name.endsWith('.json')) return Icons.data_object;
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.settings;
    if (name.endsWith('.md')) return Icons.description;
    if (name.endsWith('.txt')) return Icons.text_snippet;
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return Icons.image;
    }
    if (name.endsWith('.html') || name.endsWith('.htm')) return Icons.language;
    if (name.endsWith('.css')) return Icons.style;
    if (name.endsWith('.js') || name.endsWith('.ts')) return Icons.javascript;
    if (name.endsWith('.py')) return Icons.code;
    if (name.endsWith('.sh') || name.endsWith('.bash')) return Icons.terminal;
    if (name.endsWith('.lock')) return Icons.lock;
    if (name.startsWith('.')) return Icons.visibility_off; // Hidden files

    // Default file icon
    return Icons.insert_drive_file;
  }
}
