import '../models/ticket.dart';

/// Builds the initial prompt for an agent working on a ticket.
///
/// Includes the ticket title, body, tags, and dependency context.
/// Closed dependencies are listed with their summaries.
/// Open dependencies are listed as potential blockers.
String buildTicketPrompt(TicketData ticket, List<TicketData> allTickets) {
  final buffer = StringBuffer();

  buffer.writeln('# Ticket ${ticket.displayId}: ${ticket.title}');
  buffer.writeln();

  if (ticket.body.isNotEmpty) {
    buffer.writeln(ticket.body);
    buffer.writeln();
  }

  // Add tags as metadata
  if (ticket.tags.isNotEmpty) {
    buffer.writeln('**Tags:** ${ticket.tags.join(', ')}');
    buffer.writeln();
  }

  // Add dependency context
  if (ticket.dependsOn.isNotEmpty) {
    final closedDeps = <TicketData>[];
    final openDeps = <TicketData>[];

    for (final depId in ticket.dependsOn) {
      final dep = allTickets.where((t) => t.id == depId).firstOrNull;
      if (dep == null) continue;

      if (!dep.isOpen) {
        closedDeps.add(dep);
      } else {
        openDeps.add(dep);
      }
    }

    if (closedDeps.isNotEmpty) {
      buffer.writeln('## Completed Dependencies');
      for (final dep in closedDeps) {
        buffer.writeln('- [x] ${dep.displayId}: ${dep.title}');
      }
      buffer.writeln();
    }

    if (openDeps.isNotEmpty) {
      buffer.writeln('## Incomplete Dependencies (potential blockers)');
      for (final dep in openDeps) {
        buffer.writeln(
          '- [ ] ${dep.displayId}: ${dep.title} (Open)',
        );
      }
      buffer.writeln();
    }
  }

  return buffer.toString().trimRight();
}
