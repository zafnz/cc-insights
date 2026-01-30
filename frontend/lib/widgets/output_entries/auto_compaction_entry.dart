import 'package:flutter/material.dart';

import '../../models/output_entry.dart';

/// Displays a compaction notification entry.
///
/// Shows a banner notification when context is compacted (either automatically
/// or manually via /compact command). Visually distinct from
/// [ContextSummaryEntryWidget] which shows the actual summary content.
class AutoCompactionEntryWidget extends StatelessWidget {
  /// Creates a compaction entry widget.
  const AutoCompactionEntryWidget({super.key, required this.entry});

  /// The entry data to display.
  final AutoCompactionEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dividerColor = Colors.orange.withValues(alpha: 0.5);
    final defaultSubtitle = entry.isManual
        ? 'Conversation was manually compacted.'
        : 'Conversation was summarized to free up context space.';
    final subtitleText = entry.message?.isNotEmpty == true
        ? entry.message!
        : defaultSubtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Divider(color: dividerColor)),
              _CompactionBadge(isManual: entry.isManual),
              Expanded(child: Divider(color: dividerColor)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitleText,
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: colorScheme.outline.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge showing compaction label.
class _CompactionBadge extends StatelessWidget {
  const _CompactionBadge({required this.isManual});

  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final label = isManual ? 'Context Compacted' : 'Context Auto-Compacted';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.compress,
            size: 14,
            color: Colors.orange[700],
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.orange[700],
            ),
          ),
        ],
      ),
    );
  }
}
