import 'package:flutter/material.dart';

import '../../models/output_entry.dart';

/// Displays a system notification entry.
///
/// Shows feedback from the SDK that doesn't come through normal assistant
/// messages, such as "Unknown skill: clear" for unrecognized slash commands.
class SystemNotificationEntryWidget extends StatelessWidget {
  /// Creates a system notification entry widget.
  const SystemNotificationEntryWidget({super.key, required this.entry});

  /// The entry data to display.
  final SystemNotificationEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
