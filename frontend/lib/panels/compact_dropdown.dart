import 'package:flutter/material.dart';

/// Compact dropdown using PopupMenuButton for styled menu.
class CompactDropdown extends StatefulWidget {
  const CompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isLoading = false,
    this.tooltip,
    this.isEnabled = true,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final bool isLoading;
  final String? tooltip;
  final bool isEnabled;

  @override
  State<CompactDropdown> createState() => _CompactDropdownState();
}

class _CompactDropdownState extends State<CompactDropdown> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = widget.isEnabled;
    final isHovered = isEnabled && _isHovered;
    final textColor =
        isEnabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    final iconColor = isEnabled
        ? colorScheme.onSurface.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return PopupMenuButton<String>(
      initialValue: widget.value,
      enabled: isEnabled,
      onSelected: isEnabled ? widget.onChanged : null,
      tooltip: widget.tooltip ?? '',
      offset: const Offset(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      itemBuilder: (context) => widget.items.map((item) {
        final isSelected = item == widget.value;
        return PopupMenuItem<String>(
          value: item,
          height: 32,
          child: MouseRegion(
            cursor: isEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Text(
              item,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: isEnabled
            ? (_) => setState(() => _isHovered = true)
            : null,
        onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isEnabled
                ? (isHovered
                    ? colorScheme.primary.withValues(alpha: 0.1)
                    : colorScheme.surfaceContainerHigh)
                : colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.isLoading) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: iconColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
