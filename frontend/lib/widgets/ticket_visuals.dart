import 'package:flutter/material.dart';
import 'package:cc_insights_v2/models/ticket.dart';

/// Visual utilities for ticket status, kind, priority, and effort.
class TicketStatusVisuals {
  /// Returns the icon for a given ticket status.
  static IconData icon(TicketStatus status) {
    switch (status) {
      case TicketStatus.draft:
        return Icons.edit_note;
      case TicketStatus.ready:
        return Icons.radio_button_unchecked;
      case TicketStatus.active:
        return Icons.play_circle_outline;
      case TicketStatus.blocked:
        return Icons.block;
      case TicketStatus.needsInput:
        return Icons.help_outline;
      case TicketStatus.inReview:
        return Icons.rate_review_outlined;
      case TicketStatus.completed:
        return Icons.check_circle_outline;
      case TicketStatus.cancelled:
        return Icons.cancel_outlined;
      case TicketStatus.split:
        return Icons.call_split;
    }
  }

  /// Returns the color for a given ticket status.
  static Color color(TicketStatus status, ColorScheme colorScheme) {
    switch (status) {
      case TicketStatus.completed:
        return const Color(0xFF4CAF50); // green
      case TicketStatus.active:
        return const Color(0xFF42A5F5); // blue
      case TicketStatus.inReview:
        return const Color(0xFFCE93D8); // purple
      case TicketStatus.blocked:
      case TicketStatus.needsInput:
        return const Color(0xFFFFA726); // orange
      case TicketStatus.cancelled:
        return const Color(0xFFEF5350); // red
      case TicketStatus.ready:
        return const Color(0xFF757575); // grey-dark
      case TicketStatus.draft:
        return const Color(0xFF9E9E9E); // grey
      case TicketStatus.split:
        return const Color(0xFF42A5F5); // blue
    }
  }
}

/// Visual utilities for ticket kind.
class TicketKindVisuals {
  /// Returns the icon for a given ticket kind.
  static IconData icon(TicketKind kind) {
    switch (kind) {
      case TicketKind.feature:
        return Icons.star_outline;
      case TicketKind.bugfix:
        return Icons.bug_report_outlined;
      case TicketKind.research:
        return Icons.science_outlined;
      case TicketKind.split:
        return Icons.call_split;
      case TicketKind.question:
        return Icons.help_outline;
      case TicketKind.test:
        return Icons.science;
      case TicketKind.docs:
        return Icons.description_outlined;
      case TicketKind.chore:
        return Icons.handyman_outlined;
    }
  }

  /// Returns the color for a given ticket kind.
  static Color color(TicketKind kind, ColorScheme colorScheme) {
    switch (kind) {
      case TicketKind.feature:
        return const Color(0xFFBA68C8); // purple variant from mock
      case TicketKind.bugfix:
        return const Color(0xFFEF5350); // red
      case TicketKind.research:
        return const Color(0xFFCE93D8); // purple
      case TicketKind.split:
        return const Color(0xFF42A5F5); // blue
      case TicketKind.question:
        return const Color(0xFFFFCA28); // amber
      case TicketKind.test:
        return const Color(0xFF4DB6AC); // teal
      case TicketKind.docs:
        return const Color(0xFF9E9E9E); // grey
      case TicketKind.chore:
        return const Color(0xFF9E9E9E); // grey
    }
  }
}

/// Visual utilities for ticket priority.
class TicketPriorityVisuals {
  /// Returns the icon for a given ticket priority.
  static IconData icon(TicketPriority priority) {
    switch (priority) {
      case TicketPriority.low:
        return Icons.keyboard_arrow_down;
      case TicketPriority.medium:
        return Icons.signal_cellular_alt;
      case TicketPriority.high:
        return Icons.keyboard_arrow_up;
      case TicketPriority.critical:
        return Icons.priority_high;
    }
  }

  /// Returns the color for a given ticket priority.
  static Color color(TicketPriority priority, ColorScheme colorScheme) {
    switch (priority) {
      case TicketPriority.low:
        return const Color(0xFF9E9E9E); // grey
      case TicketPriority.medium:
        return const Color(0xFFFFA726); // orange
      case TicketPriority.high:
        return const Color(0xFFEF5350); // red
      case TicketPriority.critical:
        return const Color(0xFFEF5350); // red
    }
  }
}

/// Visual utilities for ticket effort.
class TicketEffortVisuals {
  /// Returns the color for a given ticket effort.
  static Color color(TicketEffort effort, ColorScheme colorScheme) {
    switch (effort) {
      case TicketEffort.small:
        return const Color(0xFF4CAF50); // green
      case TicketEffort.medium:
        return const Color(0xFFFFA726); // orange
      case TicketEffort.large:
        return const Color(0xFFEF5350); // red
    }
  }

  /// Returns the short label for a given ticket effort (S/M/L).
  static String shortLabel(TicketEffort effort) {
    switch (effort) {
      case TicketEffort.small:
        return 'S';
      case TicketEffort.medium:
        return 'M';
      case TicketEffort.large:
        return 'L';
    }
  }
}

/// Widget that displays a ticket status icon with appropriate color and size.
class TicketStatusIcon extends StatelessWidget {
  final TicketStatus status;
  final double size;

  const TicketStatusIcon({
    required this.status,
    this.size = 16.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Icon(
      TicketStatusVisuals.icon(status),
      size: size,
      color: TicketStatusVisuals.color(status, colorScheme),
    );
  }
}

/// Widget that displays a metadata pill with icon and label.
class MetadataPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const MetadataPill({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(
          color: foregroundColor.withOpacity(0.4),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: foregroundColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget that displays an effort badge (S/M/L).
class EffortBadge extends StatelessWidget {
  final TicketEffort effort;

  const EffortBadge({
    required this.effort,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = TicketEffortVisuals.color(effort, colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(
          color: color.withOpacity(0.4),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        TicketEffortVisuals.shortLabel(effort),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// Widget that displays a kind badge with colored label.
class KindBadge extends StatelessWidget {
  final TicketKind kind;

  const KindBadge({
    required this.kind,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = TicketKindVisuals.color(kind, colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(
          color: color.withOpacity(0.4),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        kind.label.toLowerCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
