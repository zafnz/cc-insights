import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/output_entry.dart';

/// Displays a session marker divider.
///
/// Shows when a session was resumed or when the app quit while the session
/// was active. The marker includes a locale-aware timestamp.
class SessionMarkerEntryWidget extends StatelessWidget {
  const SessionMarkerEntryWidget({super.key, required this.entry});

  final SessionMarkerEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dividerColor = colorScheme.outline.withValues(alpha: 0.5);

    // Format timestamp with user's locale
    final formattedDate = DateFormat.yMMMd().add_jm().format(entry.timestamp);

    // Determine label and color based on marker type
    final String label;
    final Color accentColor;
    final String subtitle;

    switch (entry.markerType) {
      case SessionMarkerType.resumed:
        label = 'Session Resumed';
        accentColor = Colors.green;
        subtitle = formattedDate;
      case SessionMarkerType.quit:
        label = 'Session Ended';
        accentColor = Colors.orange;
        subtitle = formattedDate;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Divider(color: dividerColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      entry.markerType == SessionMarkerType.resumed
                          ? Icons.play_circle_outline
                          : Icons.stop_circle_outlined,
                      size: 16,
                      color: accentColor.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: Divider(color: dividerColor)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
