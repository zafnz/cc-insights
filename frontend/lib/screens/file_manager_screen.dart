import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';

import '../panels/file_manager_worktree_panel.dart';
import '../panels/file_tree_panel.dart';
import '../panels/file_viewer_panel.dart';

/// File Manager screen with drag-split layout for browsing files.
///
/// This screen provides a file browser interface with three main panels:
/// - FileManagerWorktreePanel: Select worktrees
/// - FileTreePanel: Browse file tree
/// - FileViewerPanel: View file contents
///
/// Uses [SplitLayoutController] with edit mode enabled for drag-and-drop
/// panel rearrangement. Initial layout is a two-column horizontal split:
/// - Column 1 (flex 1.0): Vertical split with worktree panel and file tree
/// - Column 2 (flex 2.0): File viewer panel
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  late SplitLayoutController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SplitLayoutController(
      rootNode: _buildInitialLayout(),
    );
    // Enable drag-and-drop
    _controller.editMode = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds the initial two-column layout with panels.
  ///
  /// Layout structure:
  /// - Horizontal split (root)
  ///   - Column 1 (flex 1.0): Vertical split
  ///     - Worktree panel (flex 1.0)
  ///     - File tree panel (flex 2.0)
  ///   - Column 2 (flex 2.0): File viewer panel
  SplitNode _buildInitialLayout() {
    return SplitNode.branch(
      id: 'root',
      axis: SplitAxis.horizontal,
      children: [
        // Column 1: Browser panels
        SplitNode.branch(
          id: 'browser_column',
          axis: SplitAxis.vertical,
          flex: 1.0,
          children: [
            // Worktree panel
            SplitNode.leaf(
              id: 'file_manager_worktrees',
              flex: 1.0,
              widgetBuilder: (context) =>
                  const FileManagerWorktreePanel(),
            ),
            // File tree panel
            SplitNode.leaf(
              id: 'file_tree',
              flex: 2.0,
              widgetBuilder: (context) => const FileTreePanel(),
            ),
          ],
        ),
        // Column 2: File viewer
        SplitNode.leaf(
          id: 'file_viewer',
          flex: 2.0,
          widgetBuilder: (context) => const FileViewerPanel(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: EditableMultiSplitView(
        controller: _controller,
        config: EditableMultiSplitViewConfig(
          dividerThickness: 6.0,
          paneConfig: DraggablePaneConfig(
            dragFeedbackOpacity: 0.8,
            dragFeedbackScale: 0.95,
            useLongPressOnMobile: true,
            previewStyle: DropPreviewStyle(
              splitColor: colorScheme.primary.withValues(alpha: 0.3),
              replaceColor: colorScheme.secondary.withValues(alpha: 0.3),
              borderWidth: 2.0,
              animationDuration: const Duration(milliseconds: 150),
            ),
            dragHandleBuilder: (context) => Icon(
              Icons.drag_indicator,
              size: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
