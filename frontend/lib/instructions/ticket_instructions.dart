import '../models/ticket.dart';

/// Builds the initial prompt for an agent working on a ticket.
///
/// Includes the ticket title, description, and dependency context.
/// Completed dependencies are listed with their summaries.
/// Incomplete dependencies are listed as potential blockers.
String buildTicketPrompt(TicketData ticket, List<TicketData> allTickets) {
  final buffer = StringBuffer();

  buffer.writeln('# Ticket ${ticket.displayId}: ${ticket.title}');
  buffer.writeln();

  if (ticket.description.isNotEmpty) {
    buffer.writeln(ticket.description);
    buffer.writeln();
  }

  // Add metadata
  buffer.writeln('**Kind:** ${ticket.kind.label}');
  buffer.writeln('**Priority:** ${ticket.priority.label}');
  buffer.writeln('**Effort:** ${ticket.effort.label}');
  if (ticket.category != null) {
    buffer.writeln('**Category:** ${ticket.category}');
  }
  if (ticket.tags.isNotEmpty) {
    buffer.writeln('**Tags:** ${ticket.tags.join(', ')}');
  }
  buffer.writeln();

  // Add dependency context
  if (ticket.dependsOn.isNotEmpty) {
    final completedDeps = <TicketData>[];
    final incompleteDeps = <TicketData>[];

    for (final depId in ticket.dependsOn) {
      final dep = allTickets.where((t) => t.id == depId).firstOrNull;
      if (dep == null) continue;

      if (dep.status == TicketStatus.completed) {
        completedDeps.add(dep);
      } else {
        incompleteDeps.add(dep);
      }
    }

    if (completedDeps.isNotEmpty) {
      buffer.writeln('## Completed Dependencies');
      for (final dep in completedDeps) {
        buffer.writeln('- [x] ${dep.displayId}: ${dep.title}');
      }
      buffer.writeln();
    }

    if (incompleteDeps.isNotEmpty) {
      buffer.writeln('## Incomplete Dependencies (potential blockers)');
      for (final dep in incompleteDeps) {
        buffer.writeln(
          '- [ ] ${dep.displayId}: ${dep.title} (${dep.status.label})',
        );
      }
      buffer.writeln();
    }
  }

  return buffer.toString().trimRight();
}
