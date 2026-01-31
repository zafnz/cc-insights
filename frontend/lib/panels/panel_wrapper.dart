import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';

/// A generic panel wrapper that provides a header with drag handle.
///
/// When used with [DraggablePaneConfig.dragHandleBuilder], the drag handle
/// from [DragHandleProvider] is placed in the header, making only the
/// drag indicator icon draggable (not the entire panel).
///
/// Supports an optional context menu for panel separation actions.
class PanelWrapper extends StatelessWidget {
  const PanelWrapper({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.contextMenuItems,
  });

  final String title;
  final IconData icon;
  final Widget child;

  /// Optional trailing widget(s) placed between the title and drag handle.
  ///
  /// Useful for action buttons, dropdowns, or other controls specific
  /// to this panel.
  final Widget? trailing;

  /// Optional context menu items shown when right-clicking the header.
  final List<PopupMenuEntry<String>>? contextMenuItems;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get the drag handle from the provider (if available).
    // This will be a Draggable-wrapped widget when editMode is enabled.
    final dragHandle = DragHandleProvider.handleOf(context);

    Widget header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Optional trailing widget(s)
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
          const SizedBox(width: 8),
          // Use the provided drag handle, or fallback to a static icon
          dragHandle ??
              Icon(
                Icons.drag_indicator,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
        ],
      ),
    );

    // Wrap header in context menu if items are provided
    if (contextMenuItems != null && contextMenuItems!.isNotEmpty) {
      header = GestureDetector(
        onSecondaryTapUp: (details) {
          _showContextMenu(context, details.globalPosition);
        },
        child: header,
      );
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          // Panel content
          Expanded(child: child),
        ],
      );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: contextMenuItems!,
    );
  }
}
