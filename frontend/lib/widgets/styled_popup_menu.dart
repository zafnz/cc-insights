import 'package:flutter/material.dart';

/// Shows a styled popup menu with a border and rounded corners.
///
/// This is a drop-in replacement for [showMenu] with consistent styling.
/// The menu has:
/// - A border using the primary color at 50% opacity
/// - Rounded corners (6px radius)
/// - A surface container high background color
/// - Compact vertical padding
///
/// Usage:
/// ```dart
/// final result = await showStyledMenu<String>(
///   context: context,
///   position: RelativeRect.fromLTRB(x, y, x + 1, y + 1),
///   items: [
///     styledMenuItem(value: 'edit', child: Text('Edit')),
///     styledMenuItem(value: 'delete', child: Text('Delete')),
///   ],
/// );
/// ```
Future<T?> showStyledMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  String? semanticLabel,
  Clip clipBehavior = Clip.none,
  bool useRootNavigator = false,
  AnimationStyle? popUpAnimationStyle,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return showMenu<T>(
    context: context,
    position: position,
    items: items,
    initialValue: initialValue,
    elevation: elevation ?? 8,
    semanticLabel: semanticLabel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(
        color: colorScheme.primary.withOpacity(0.5),
        width: 1,
      ),
    ),
    color: colorScheme.surfaceContainerHigh,
    clipBehavior: clipBehavior,
    useRootNavigator: useRootNavigator,
    popUpAnimationStyle: popUpAnimationStyle,
    menuPadding: const EdgeInsets.symmetric(vertical: 4),
  );
}

/// Creates a compact popup menu item with reduced height.
///
/// Use this instead of [PopupMenuItem] for consistent compact styling.
PopupMenuItem<T> styledMenuItem<T>({
  required T value,
  required Widget child,
  bool enabled = true,
  VoidCallback? onTap,
}) {
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    onTap: onTap,
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: child,
  );
}

/// Helper to create a RelativeRect from a tap position.
///
/// Usage with GestureDetector:
/// ```dart
/// onSecondaryTapDown: (details) async {
///   final result = await showStyledMenu<String>(
///     context: context,
///     position: menuPositionFromOffset(details.globalPosition),
///     items: [...],
///   );
/// }
/// ```
RelativeRect menuPositionFromOffset(Offset globalPosition) {
  return RelativeRect.fromLTRB(
    globalPosition.dx,
    globalPosition.dy,
    globalPosition.dx + 1,
    globalPosition.dy + 1,
  );
}
