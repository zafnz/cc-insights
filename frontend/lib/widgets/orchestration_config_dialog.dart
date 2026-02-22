import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ticket_dispatch_factory.dart';
import '../services/worktree_service.dart';
import '../services/git_service.dart';
import '../models/ticket.dart';
import '../state/selection_state.dart';
import '../state/ticket_board_state.dart';
import '../models/project.dart';

class OrchestrationConfigDialog extends StatefulWidget {
  const OrchestrationConfigDialog({super.key, required this.ticketIds});

  final List<int> ticketIds;

  @override
  State<OrchestrationConfigDialog> createState() =>
      _OrchestrationConfigDialogState();
}

class _OrchestrationConfigDialogState extends State<OrchestrationConfigDialog> {
  late final TextEditingController _branchController;
  late final TextEditingController _instructionsController;
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    final slug = widget.ticketIds.isEmpty
        ? 'orchestration'
        : 'orchestrate-${widget.ticketIds.first}-${widget.ticketIds.last}';
    _branchController = TextEditingController(text: slug);
    _instructionsController = TextEditingController(
      text:
          'Run tickets ${widget.ticketIds.join(', ')}. Respect dependencies, '
          'use parallel execution where safe, and report progress frequently.',
    );
  }

  @override
  void dispose() {
    _branchController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.watch<TicketRepository>();
    final tickets = widget.ticketIds
        .map(ticketBoard.getTicket)
        .whereType<TicketData>()
        .toList();

    return AlertDialog(
      title: const Text('Run orchestration'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tickets (${tickets.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                shrinkWrap: true,
                children: tickets
                    .map(
                      (t) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${t.displayId}  ${t.title}'),
                        subtitle: Text(t.status.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _branchController,
              decoration: const InputDecoration(
                labelText: 'Feature branch name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instructionsController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Initial instructions',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _launching ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _launching ? null : _launch,
          child: _launching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Launch'),
        ),
      ],
    );
  }

  Future<void> _launch() async {
    setState(() => _launching = true);
    try {
      final project = context.read<ProjectState>();
      final selection = context.read<SelectionState>();
      final gitService = context.read<GitService>();
      final worktreeService = WorktreeService(gitService: gitService);

      final root = await calculateDefaultWorktreeRoot(project.data.repoRoot);
      final base =
          selection.selectedWorktree?.data.branch ??
          project.primaryWorktree.data.branch;
      final created = await worktreeService.createWorktree(
        project: project,
        branch: _branchController.text.trim(),
        worktreeRoot: root,
        base: base,
      );
      project.addLinkedWorktree(created, select: true);

      final dispatch = createTicketDispatchService(context);

      await dispatch.createOrchestratorChat(
        worktreeState: created,
        ticketIds: widget.ticketIds,
        initialInstructions:
            '${_instructionsController.text.trim()}\n\nBase worktree: ${created.data.worktreeRoot}\nBase branch: ${created.data.branch}',
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch orchestration: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _launching = false);
      }
    }
  }
}
