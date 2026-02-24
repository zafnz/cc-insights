import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../state/orchestrator_state.dart';
import '../state/selection_state.dart';
import '../state/ticket_board_state.dart';

class OrchestrationProgressWidget extends StatefulWidget {
  const OrchestrationProgressWidget({super.key, required this.state});

  final OrchestratorState state;

  @override
  State<OrchestrationProgressWidget> createState() =>
      _OrchestrationProgressWidgetState();
}

class _OrchestrationProgressWidgetState
    extends State<OrchestrationProgressWidget> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = context.watch<TicketRepository>();
    final progress = widget.state.getProgress();
    final percent = progress.total == 0
        ? 0.0
        : progress.completed / progress.total;
    final elapsed = widget.state.getElapsedTime();

    final tickets =
        widget.state.ticketIds
            .map(board.getTicket)
            .whereType<TicketData>()
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Orchestration Progress  ${progress.completed}/${progress.total}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('Agents: ${widget.state.activeAgentCount}'),
                const SizedBox(width: 12),
                Text('Elapsed: ${_formatDuration(elapsed)}'),
                const SizedBox(width: 12),
                Text(
                  'Cost: \$${widget.state.getTotalCost().toStringAsFixed(2)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: percent),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tickets
                  .map(
                    (t) => InkWell(
                      onTap: () => _openLinkedChat(context, t),
                      child: Chip(
                        label: Text(t.displayId),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _colorForOpen(context, t.isOpen),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _colorForOpen(BuildContext context, bool isOpen) {
    final scheme = Theme.of(context).colorScheme;
    return isOpen ? scheme.primaryContainer : Colors.green.withValues(alpha: 0.18);
  }

  void _openLinkedChat(BuildContext context, TicketData ticket) {
    if (ticket.linkedChats.isEmpty) return;
    final linked = ticket.linkedChats.last;
    final selection = context.read<SelectionState>();
    final project = selection.project;
    for (final wt in project.allWorktrees) {
      if (wt.data.worktreeRoot != linked.worktreeRoot) continue;
      selection.selectWorktree(wt);
      final chat = wt.chats.where((c) => c.id == linked.chatId).firstOrNull;
      if (chat != null) {
        selection.selectChat(chat);
      }
      return;
    }
  }
}
