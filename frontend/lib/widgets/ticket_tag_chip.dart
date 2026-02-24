import 'package:flutter/material.dart';

import 'tag_colors.dart';

/// A small pill-shaped chip that displays a ticket tag.
class TicketTagChip extends StatelessWidget {
  const TicketTagChip({
    super.key,
    required this.tag,
    this.removable = false,
    this.onRemove,
    this.onTap,
    this.fontSize = 11,
  });

  final String tag;
  final bool removable;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = tagColor(tag);

    final label = Text(
      tag,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );

    final child = Container(
      padding: EdgeInsets.only(
        left: 8,
        right: removable ? 4 : 8,
        top: 2,
        bottom: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          if (removable)
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(Icons.close, size: fontSize, color: color),
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    return child;
  }
}
