import 'package:flutter/material.dart';

import '../../models/output_entry.dart';

/// Displays a system instruction entry.
///
/// Shows instructions sent by the orchestrator or system to a worker agent.
/// Styled with a neutral surface background, similar to user input entries
/// but visually distinct.
class SystemInstructionEntryWidget extends StatelessWidget {
  const SystemInstructionEntryWidget({super.key, required this.entry});

  final SystemInstructionEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final icon = entry.source == InstructionSource.orchestrator
        ? Icons.hub
        : Icons.smart_toy;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              entry.text,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
