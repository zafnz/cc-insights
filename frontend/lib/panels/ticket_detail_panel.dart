import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../models/project.dart';
import '../models/ticket.dart';
import '../models/worktree.dart';
import '../services/git_service.dart';
import '../services/ticket_dispatch_service.dart';
import '../services/worktree_service.dart';
import '../state/selection_state.dart';
import '../state/ticket_board_state.dart';
import '../widgets/markdown_renderer.dart';
import '../widgets/ticket_visuals.dart';

/// Test keys for the ticket detail panel.
class TicketDetailPanelKeys {
  TicketDetailPanelKeys._();

  static const Key editButton = Key('ticket-detail-edit');
  static const Key statusPill = Key('ticket-detail-status-pill');
  static const Key descriptionSection = Key('ticket-detail-description');
  static const Key dependsOnSection = Key('ticket-detail-depends-on');
  static const Key blocksSection = Key('ticket-detail-blocks');
  static const Key actionsSection = Key('ticket-detail-actions');
  static const Key costSection = Key('ticket-detail-cost');
  static const Key beginNewWorktreeButton = Key('ticket-detail-begin-new-worktree');
  static const Key beginInWorktreeButton = Key('ticket-detail-begin-in-worktree');
  static const Key openLinkedChatButton = Key('ticket-detail-open-linked-chat');
  static const Key markCompleteButton = Key('ticket-detail-mark-complete');
  static const Key cancelButton = Key('ticket-detail-cancel');
  static const Key splitButton = Key('ticket-detail-split');
}

/// Ticket detail panel showing full detail for the selected ticket.
///
/// Displays header, metadata pills, description, dependencies,
/// linked work placeholder, action buttons, and cost stats.
/// Shows an empty state when no ticket is selected.
class TicketDetailPanel extends StatelessWidget {
  const TicketDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.watch<TicketBoardState>();
    final ticket = ticketBoard.selectedTicket;

    if (ticket == null) {
      return const _EmptyState();
    }

    return _TicketDetailContent(ticket: ticket);
  }
}

/// Empty state shown when no ticket is selected.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Text(
        'Select a ticket to view details',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Full ticket detail content.
class _TicketDetailContent extends StatelessWidget {
  final TicketData ticket;

  const _TicketDetailContent({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderSection(ticket: ticket),
          const SizedBox(height: 16),
          _MetadataPillsRow(ticket: ticket),
          if (ticket.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TagsRow(tags: ticket.tags),
          ],
          const SizedBox(height: 24),
          _SectionDivider(label: 'Description'),
          const SizedBox(height: 8),
          _DescriptionSection(ticket: ticket),
          const SizedBox(height: 24),
          _SectionDivider(label: 'Dependencies'),
          const SizedBox(height: 8),
          _DependenciesSection(ticket: ticket),
          const SizedBox(height: 24),
          _SectionDivider(label: 'Linked Work'),
          const SizedBox(height: 8),
          _LinkedWorkSection(ticket: ticket),
          const SizedBox(height: 24),
          _SectionDivider(label: 'Actions'),
          const SizedBox(height: 8),
          _ActionsSection(ticket: ticket),
          if (ticket.costStats != null) ...[
            const SizedBox(height: 24),
            _SectionDivider(label: 'Cost & Time'),
            const SizedBox(height: 8),
            _CostSection(costStats: ticket.costStats!),
          ],
        ],
      ),
      ),
    );
  }
}

/// Header with status icon, ticket ID, title, and action buttons.
class _HeaderSection extends StatelessWidget {
  final TicketData ticket;

  const _HeaderSection({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TicketStatusIcon(status: ticket.status, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ticket.displayId,
                style: AppFonts.monoTextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ticket.title,
                style: textTheme.headlineSmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: TicketDetailPanelKeys.editButton,
          icon: const Icon(Icons.edit),
          onPressed: () {
            context.read<TicketBoardState>().setDetailMode(TicketDetailMode.edit);
          },
          tooltip: 'Edit',
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {},
          tooltip: 'More options',
        ),
      ],
    );
  }
}

/// Row of metadata pills for status, kind, priority, and category.
class _MetadataPillsRow extends StatelessWidget {
  final TicketData ticket;

  const _MetadataPillsRow({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        MetadataPill(
          key: TicketDetailPanelKeys.statusPill,
          icon: TicketStatusVisuals.icon(ticket.status),
          label: ticket.status.label.toLowerCase(),
          backgroundColor: TicketStatusVisuals.color(ticket.status, colorScheme)
              .withOpacity(0.15),
          foregroundColor:
              TicketStatusVisuals.color(ticket.status, colorScheme),
        ),
        MetadataPill(
          icon: TicketKindVisuals.icon(ticket.kind),
          label: ticket.kind.label.toLowerCase(),
          backgroundColor: TicketKindVisuals.color(ticket.kind, colorScheme)
              .withOpacity(0.15),
          foregroundColor: TicketKindVisuals.color(ticket.kind, colorScheme),
        ),
        MetadataPill(
          icon: TicketPriorityVisuals.icon(ticket.priority),
          label: ticket.priority.label.toLowerCase(),
          backgroundColor:
              TicketPriorityVisuals.color(ticket.priority, colorScheme)
                  .withOpacity(0.15),
          foregroundColor:
              TicketPriorityVisuals.color(ticket.priority, colorScheme),
        ),
        if (ticket.category != null)
          MetadataPill(
            icon: Icons.category,
            label: ticket.category!,
            backgroundColor: colorScheme.primary.withOpacity(0.15),
            foregroundColor: colorScheme.primary,
          ),
      ],
    );
  }
}

/// Row of tag chips.
class _TagsRow extends StatelessWidget {
  final Set<String> tags;

  const _TagsRow({required this.tags});

  @override
  Widget build(BuildContext context) {
    final sortedTags = tags.toList()..sort();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: sortedTags.map((tag) {
        return Chip(
          label: Text(tag),
          labelStyle: const TextStyle(fontSize: 11),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFF4DB6AC).withOpacity(0.15),
          side: BorderSide(
            color: const Color(0xFF4DB6AC).withOpacity(0.4),
            width: 0.5,
          ),
        );
      }).toList(),
    );
  }
}

/// Section divider with label and horizontal line.
class _SectionDivider extends StatelessWidget {
  final String label;

  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}

/// Description section with markdown content in a card.
class _DescriptionSection extends StatelessWidget {
  final TicketData ticket;

  const _DescriptionSection({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: TicketDetailPanelKeys.descriptionSection,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ticket.description.isEmpty
          ? Text(
              'No description',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
            )
          : MarkdownRenderer(data: ticket.description),
    );
  }
}

/// Dependencies section showing "Depends on" and "Blocks" lists.
class _DependenciesSection extends StatelessWidget {
  final TicketData ticket;

  const _DependenciesSection({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.read<TicketBoardState>();
    final blockedByIds = ticketBoard.getBlockedBy(ticket.id);

    final hasDependsOn = ticket.dependsOn.isNotEmpty;
    final hasBlocks = blockedByIds.isNotEmpty;

    if (!hasDependsOn && !hasBlocks) {
      return Container(
        key: TicketDetailPanelKeys.dependsOnSection,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          'No dependencies',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withOpacity(0.6),
              ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasDependsOn) ...[
            _DependencyRow(
              key: TicketDetailPanelKeys.dependsOnSection,
              label: 'Depends on',
              ticketIds: ticket.dependsOn,
            ),
            if (hasBlocks) const SizedBox(height: 10),
          ],
          if (hasBlocks)
            _DependencyRow(
              key: TicketDetailPanelKeys.blocksSection,
              label: 'Blocks',
              ticketIds: blockedByIds,
            ),
        ],
      ),
    );
  }
}

/// A single row in the dependencies section (either "Depends on" or "Blocks").
class _DependencyRow extends StatelessWidget {
  final String label;
  final List<int> ticketIds;

  const _DependencyRow({
    super.key,
    required this.label,
    required this.ticketIds,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ticketIds.map((id) {
              return _DependencyChip(ticketId: id);
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// A clickable chip for a dependency ticket.
class _DependencyChip extends StatelessWidget {
  final int ticketId;

  const _DependencyChip({required this.ticketId});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.read<TicketBoardState>();
    final depTicket = ticketBoard.getTicket(ticketId);

    final displayId = 'TKT-${ticketId.toString().padLeft(3, '0')}';

    return InkWell(
      onTap: () => ticketBoard.selectTicket(ticketId),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (depTicket != null)
              TicketStatusIcon(status: depTicket.status, size: 12),
            if (depTicket != null) const SizedBox(width: 4),
            Text(
              displayId,
              style: AppFonts.monoTextStyle(
                fontSize: 10,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linked work section (placeholder for Phase 3).
class _LinkedWorkSection extends StatelessWidget {
  final TicketData ticket;

  const _LinkedWorkSection({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final hasLinkedWork =
        ticket.linkedWorktrees.isNotEmpty || ticket.linkedChats.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: hasLinkedWork
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final wt in ticket.linkedWorktrees)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.account_tree,
                            size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          wt.branch ?? wt.worktreeRoot,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final chat in ticket.linkedChats)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          chat.chatName,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          : Text(
              'No linked work',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
            ),
    );
  }
}

/// Actions section with worktree dispatch and status change buttons.
class _ActionsSection extends StatefulWidget {
  final TicketData ticket;

  const _ActionsSection({required this.ticket});

  @override
  State<_ActionsSection> createState() => _ActionsSectionState();
}

class _ActionsSectionState extends State<_ActionsSection> {
  bool _isDispatching = false;

  /// Whether the ticket can be dispatched to a worktree.
  bool get _canBegin =>
      !_isDispatching &&
      (widget.ticket.status == TicketStatus.ready ||
          widget.ticket.status == TicketStatus.needsInput);

  /// Whether the ticket is in a terminal state (completed or cancelled).
  bool get _isTerminal =>
      widget.ticket.status == TicketStatus.completed ||
      widget.ticket.status == TicketStatus.cancelled;

  /// Creates a [TicketDispatchService] from available providers.
  TicketDispatchService _createDispatchService() {
    return TicketDispatchService(
      ticketBoard: context.read<TicketBoardState>(),
      project: context.read<ProjectState>(),
      selection: context.read<SelectionState>(),
      worktreeService: WorktreeService(
        gitService: context.read<GitService>(),
      ),
    );
  }

  Future<void> _handleBeginNewWorktree() async {
    setState(() => _isDispatching = true);
    try {
      final dispatch = _createDispatchService();
      await dispatch.beginInNewWorktree(widget.ticket.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create worktree: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDispatching = false);
      }
    }
  }

  Future<void> _handleBeginInWorktree() async {
    final project = context.read<ProjectState>();
    final worktrees = project.allWorktrees;

    final selected = await showDialog<WorktreeState>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Select worktree'),
          children: worktrees.map((wt) {
            final label = wt.data.isPrimary
                ? '${wt.data.branch} (primary)'
                : wt.data.branch;
            return SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(wt),
              child: Text(label),
            );
          }).toList(),
        );
      },
    );

    if (selected == null || !mounted) return;

    setState(() => _isDispatching = true);
    try {
      final dispatch = _createDispatchService();
      await dispatch.beginInWorktree(widget.ticket.id, selected);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to dispatch to worktree: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDispatching = false);
      }
    }
  }

  void _handleOpenLinkedChat() {
    final linkedChat = widget.ticket.linkedChats.first;
    final project = context.read<ProjectState>();
    final selection = context.read<SelectionState>();

    // Find the worktree containing this chat
    for (final wt in project.allWorktrees) {
      if (wt.data.worktreeRoot == linkedChat.worktreeRoot) {
        selection.selectWorktree(wt);
        // Find and select the chat within the worktree
        final chat = wt.chats
            .where((c) => c.data.id == linkedChat.chatId)
            .firstOrNull;
        if (chat != null) {
          selection.selectChat(chat);
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.read<TicketBoardState>();
    final hasLinkedChats = widget.ticket.linkedChats.isNotEmpty;

    return Wrap(
      key: TicketDetailPanelKeys.actionsSection,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: TicketDetailPanelKeys.beginNewWorktreeButton,
          onPressed: _canBegin ? _handleBeginNewWorktree : null,
          icon: _isDispatching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 16),
          label: const Text('Begin in new worktree'),
        ),
        OutlinedButton.icon(
          key: TicketDetailPanelKeys.beginInWorktreeButton,
          onPressed: _canBegin ? _handleBeginInWorktree : null,
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('Begin in worktree...'),
        ),
        if (hasLinkedChats)
          OutlinedButton.icon(
            key: TicketDetailPanelKeys.openLinkedChatButton,
            onPressed: _handleOpenLinkedChat,
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('Open linked chat'),
          ),
        if (!_isTerminal)
          OutlinedButton.icon(
            key: TicketDetailPanelKeys.splitButton,
            onPressed: () => _handleSplit(context, ticketBoard),
            icon: const Icon(Icons.call_split, size: 16),
            label: const Text('Split into subtasks'),
          ),
        if (!_isTerminal)
          OutlinedButton.icon(
            key: TicketDetailPanelKeys.markCompleteButton,
            onPressed: () => ticketBoard.markCompleted(widget.ticket.id),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Mark Complete'),
          ),
        if (!_isTerminal)
          OutlinedButton.icon(
            key: TicketDetailPanelKeys.cancelButton,
            onPressed: () => ticketBoard.markCancelled(widget.ticket.id),
            icon: Icon(Icons.cancel_outlined, size: 16,
                color: const Color(0xFFEF5350)),
            label: Text(
              'Cancel',
              style: TextStyle(color: const Color(0xFFEF5350)),
            ),
          ),
      ],
    );
  }

  Future<void> _handleSplit(
    BuildContext context,
    TicketBoardState ticketBoard,
  ) async {
    final result = await showDialog<List<({String title, TicketKind kind})>>(
      context: context,
      builder: (dialogContext) {
        return _TicketSplitDialog(parentTicket: widget.ticket);
      },
    );

    if (result != null && result.isNotEmpty && mounted) {
      ticketBoard.splitTicket(widget.ticket.id, result);
    }
  }
}

/// Cost and time statistics section with 4-column grid.
class _CostSection extends StatelessWidget {
  final TicketCostStats costStats;

  const _CostSection({required this.costStats});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: TicketDetailPanelKeys.costSection,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _StatCell(label: 'Tokens', value: _formatTokens(costStats.totalTokens))),
          Expanded(child: _StatCell(label: 'Cost', value: _formatCost(costStats.totalCost))),
          Expanded(child: _StatCell(label: 'Agent Time', value: _formatDuration(costStats.agentTimeMs))),
          Expanded(child: _StatCell(label: 'Waiting', value: _formatDuration(costStats.waitingTimeMs))),
        ],
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}k';
    }
    return tokens.toString();
  }

  String _formatCost(double cost) {
    return '\$${cost.toStringAsFixed(2)}';
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${seconds}s';
  }
}

/// A single stat cell in the cost grid.
class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Keys for testing the [_TicketSplitDialog].
class TicketSplitDialogKeys {
  TicketSplitDialogKeys._();

  static const Key dialog = Key('ticket-split-dialog');
  static const Key addSubtaskButton = Key('ticket-split-add-subtask');
  static const Key cancelButton = Key('ticket-split-cancel');
  static const Key splitButton = Key('ticket-split-submit');

  /// Key for a subtask title field at the given index.
  static Key subtaskTitle(int index) => Key('ticket-split-title-$index');

  /// Key for a subtask kind dropdown at the given index.
  static Key subtaskKind(int index) => Key('ticket-split-kind-$index');

  /// Key for a subtask remove button at the given index.
  static Key subtaskRemove(int index) => Key('ticket-split-remove-$index');
}

/// Dialog for splitting a ticket into subtasks.
///
/// Presents a dynamic list of subtask rows, each with a title text field,
/// kind dropdown, and remove button. Returns a list of subtask records
/// on submit, or null if cancelled.
class _TicketSplitDialog extends StatefulWidget {
  final TicketData parentTicket;

  const _TicketSplitDialog({required this.parentTicket});

  @override
  State<_TicketSplitDialog> createState() => _TicketSplitDialogState();
}

class _TicketSplitDialogState extends State<_TicketSplitDialog> {
  final List<TextEditingController> _titleControllers = [];
  final List<TicketKind> _kinds = [];

  @override
  void initState() {
    super.initState();
    // Start with one empty subtask row
    _addSubtask();
  }

  @override
  void dispose() {
    for (final controller in _titleControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addSubtask() {
    setState(() {
      _titleControllers.add(TextEditingController());
      _kinds.add(TicketKind.feature);
    });
  }

  void _removeSubtask(int index) {
    setState(() {
      _titleControllers[index].dispose();
      _titleControllers.removeAt(index);
      _kinds.removeAt(index);
    });
  }

  bool get _canSubmit {
    if (_titleControllers.isEmpty) return false;
    return _titleControllers.any((c) => c.text.trim().isNotEmpty);
  }

  void _handleSubmit() {
    final subtasks = <({String title, TicketKind kind})>[];
    for (var i = 0; i < _titleControllers.length; i++) {
      final title = _titleControllers[i].text.trim();
      if (title.isNotEmpty) {
        subtasks.add((title: title, kind: _kinds[i]));
      }
    }
    Navigator.of(context).pop(subtasks);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      key: TicketSplitDialogKeys.dialog,
      title: Text('Split ${widget.parentTicket.displayId}'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create subtasks for "${widget.parentTicket.title}"',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // Subtask rows
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _titleControllers.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: TicketSplitDialogKeys.subtaskTitle(index),
                            controller: _titleControllers[index],
                            decoration: InputDecoration(
                              hintText: 'Subtask title',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<TicketKind>(
                            key: TicketSplitDialogKeys.subtaskKind(index),
                            value: _kinds[index],
                            isDense: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: TicketKind.values
                                .where((k) => k != TicketKind.split)
                                .map((kind) {
                              return DropdownMenuItem(
                                value: kind,
                                child: Text(
                                  kind.label,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _kinds[index] = value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          key: TicketSplitDialogKeys.subtaskRemove(index),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _titleControllers.length > 1
                              ? () => _removeSubtask(index)
                              : null,
                          tooltip: 'Remove subtask',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: TicketSplitDialogKeys.addSubtaskButton,
              onPressed: _addSubtask,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add subtask'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: TicketSplitDialogKeys.cancelButton,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: TicketSplitDialogKeys.splitButton,
          onPressed: _canSubmit ? _handleSubmit : null,
          child: const Text('Split'),
        ),
      ],
    );
  }
}
