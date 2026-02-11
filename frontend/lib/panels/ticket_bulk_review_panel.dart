import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';
import '../state/ticket_board_state.dart';
import '../widgets/ticket_visuals.dart';

/// Test keys for the ticket bulk review panel.
class TicketBulkReviewKeys {
  TicketBulkReviewKeys._();

  static const Key selectAllButton = Key('bulk-review-select-all');
  static const Key deselectAllButton = Key('bulk-review-deselect-all');
  static const Key rejectAllButton = Key('bulk-review-reject-all');
  static const Key approveButton = Key('bulk-review-approve');
  static const Key editCard = Key('bulk-review-edit-card');
}

/// Panel for reviewing bulk-proposed tickets from an agent.
///
/// Displays a table of proposed tickets with checkboxes, an inline edit
/// card for the selected proposal, and approve/reject action buttons.
class TicketBulkReviewPanel extends StatelessWidget {
  const TicketBulkReviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.watch<TicketBoardState>();
    final proposals = ticketBoard.proposedTickets;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReviewHeader(
            ticketCount: proposals.length,
            chatName: ticketBoard.proposalSourceChatName,
          ),
          const SizedBox(height: 24),
          _ProposalTable(
            proposals: proposals,
            checkedIds: ticketBoard.proposalCheckedIds,
            editingId: ticketBoard.proposalEditingId,
          ),
          if (ticketBoard.proposalEditingId != null) ...[
            const SizedBox(height: 16),
            _InlineEditCard(
              ticketId: ticketBoard.proposalEditingId!,
            ),
          ],
          const SizedBox(height: 24),
          _ActionBar(
            checkedCount: ticketBoard.proposalCheckedIds.length,
          ),
        ],
      ),
    );
  }
}

/// Header with icon, title, and subtitle.
class _ReviewHeader extends StatelessWidget {
  final int ticketCount;
  final String chatName;

  const _ReviewHeader({
    required this.ticketCount,
    required this.chatName,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.playlist_add_check,
              size: 28,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              'Review Proposed Tickets',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            children: [
              const TextSpan(text: 'Agent proposed '),
              TextSpan(
                text: '$ticketCount tickets',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: ' from chat '),
              TextSpan(
                text: '"$chatName"',
                style: TextStyle(color: colorScheme.primary),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Table showing all proposed tickets with checkboxes.
class _ProposalTable extends StatelessWidget {
  final List<TicketData> proposals;
  final Set<int> checkedIds;
  final int? editingId;

  const _ProposalTable({
    required this.proposals,
    required this.checkedIds,
    required this.editingId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _TableHeader(),
          ...proposals.map((ticket) {
            final isChecked = checkedIds.contains(ticket.id);
            final isSelected = ticket.id == editingId;
            return _TableRow(
              ticket: ticket,
              isChecked: isChecked,
              isSelected: isSelected,
            );
          }),
        ],
      ),
    );
  }
}

/// Header row for the proposals table.
class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const SizedBox(width: 32),
          SizedBox(
            width: 72,
            child: _headerText('ID', colorScheme),
          ),
          Expanded(
            flex: 3,
            child: _headerText('Title', colorScheme),
          ),
          SizedBox(
            width: 80,
            child: _headerText('Kind', colorScheme),
          ),
          SizedBox(
            width: 100,
            child: _headerText('Category', colorScheme),
          ),
          SizedBox(
            width: 80,
            child: _headerText('Depends', colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _headerText(String text, ColorScheme colorScheme) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// A single row in the proposals table.
class _TableRow extends StatelessWidget {
  final TicketData ticket;
  final bool isChecked;
  final bool isSelected;

  const _TableRow({
    required this.ticket,
    required this.isChecked,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.read<TicketBoardState>();

    final backgroundColor = isSelected
        ? colorScheme.primaryContainer.withValues(alpha: 0.2)
        : !isChecked
            ? colorScheme.surfaceContainerLow.withValues(alpha: 0.5)
            : null;

    return GestureDetector(
      onTap: () => ticketBoard.setProposalEditing(ticket.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: Opacity(
          opacity: isChecked ? 1.0 : 0.5,
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: isChecked,
                  onChanged: (_) => ticketBoard.toggleProposalChecked(ticket.id),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  ticket.displayId,
                  style: AppFonts.monoTextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  ticket.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 80,
                child: KindBadge(kind: ticket.kind),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  ticket.category ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                child: _DependsCell(dependsOn: ticket.dependsOn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cell showing dependency IDs or a dash placeholder.
class _DependsCell extends StatelessWidget {
  final List<int> dependsOn;

  const _DependsCell({required this.dependsOn});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (dependsOn.isEmpty) {
      return Text(
        '--',
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      );
    }

    return Text(
      dependsOn.map((id) => 'TKT-${id.toString().padLeft(3, '0')}').join(', '),
      style: AppFonts.monoTextStyle(
        fontSize: 10,
        color: colorScheme.primary,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Inline edit card for modifying a proposed ticket.
class _InlineEditCard extends StatefulWidget {
  final int ticketId;

  const _InlineEditCard({required this.ticketId});

  @override
  State<_InlineEditCard> createState() => _InlineEditCardState();
}

class _InlineEditCardState extends State<_InlineEditCard> {
  late TextEditingController _titleController;
  late TextEditingController _categoryController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    final ticketBoard = context.read<TicketBoardState>();
    final ticket = ticketBoard.getTicket(widget.ticketId);
    _titleController = TextEditingController(text: ticket?.title ?? '');
    _categoryController = TextEditingController(text: ticket?.category ?? '');
    _descriptionController = TextEditingController(text: ticket?.description ?? '');
  }

  @override
  void didUpdateWidget(covariant _InlineEditCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticketId != widget.ticketId) {
      final ticketBoard = context.read<TicketBoardState>();
      final ticket = ticketBoard.getTicket(widget.ticketId);
      _titleController.text = ticket?.title ?? '';
      _categoryController.text = ticket?.category ?? '';
      _descriptionController.text = ticket?.description ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _updateTitle(String value) {
    context.read<TicketBoardState>().updateTicket(
      widget.ticketId,
      (t) => t.copyWith(title: value),
    );
  }

  void _updateCategory(String value) {
    context.read<TicketBoardState>().updateTicket(
      widget.ticketId,
      (t) => t.copyWith(
        category: value.isNotEmpty ? value : null,
        clearCategory: value.isEmpty,
      ),
    );
  }

  void _updateDescription(String value) {
    context.read<TicketBoardState>().updateTicket(
      widget.ticketId,
      (t) => t.copyWith(description: value),
    );
  }

  void _updateKind(TicketKind kind) {
    context.read<TicketBoardState>().updateTicket(
      widget.ticketId,
      (t) => t.copyWith(kind: kind),
    );
  }

  void _removeDependency(int depId) {
    final ticketBoard = context.read<TicketBoardState>();
    final ticket = ticketBoard.getTicket(widget.ticketId);
    if (ticket == null) return;
    ticketBoard.updateTicket(
      widget.ticketId,
      (t) => t.copyWith(
        dependsOn: t.dependsOn.where((id) => id != depId).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ticketBoard = context.watch<TicketBoardState>();
    final ticket = ticketBoard.getTicket(widget.ticketId);

    if (ticket == null) return const SizedBox.shrink();

    return Container(
      key: TicketBulkReviewKeys.editCard,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.15),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Edit card header
          Row(
            children: [
              Icon(Icons.edit, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Editing: ${ticket.displayId}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => ticketBoard.setProposalEditing(null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                splashRadius: 14,
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title field
          _EditRow(
            label: 'Title',
            child: _buildTextField(
              controller: _titleController,
              onChanged: _updateTitle,
            ),
          ),
          const SizedBox(height: 10),

          // Kind + Category row
          _EditRow(
            label: 'Kind / Cat.',
            child: Row(
              children: [
                Expanded(
                  child: _buildDropdown<TicketKind>(
                    value: ticket.kind,
                    items: TicketKind.values,
                    labelBuilder: (k) => k.label.toLowerCase(),
                    onChanged: (v) {
                      if (v != null) _updateKind(v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _categoryController,
                    onChanged: _updateCategory,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Dependencies row
          _EditRow(
            label: 'Depends',
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(minHeight: 32),
              child: ticket.dependsOn.isEmpty
                  ? Text(
                      'No dependencies',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ticket.dependsOn.map((depId) {
                        return _DepChip(
                          depId: depId,
                          onRemove: () => _removeDependency(depId),
                        );
                      }).toList(),
                    ),
            ),
          ),
          const SizedBox(height: 10),

          // Description field
          _EditRow(
            label: 'Description',
            child: _buildTextField(
              controller: _descriptionController,
              onChanged: _updateDescription,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 12),
        onChanged: onChanged,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        style: const TextStyle(fontSize: 12),
        dropdownColor: colorScheme.surfaceContainerHigh,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          border: InputBorder.none,
        ),
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(labelBuilder(item)),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// A row in the edit card with a label and child widget.
class _EditRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _EditRow({
    required this.label,
    required this.child,
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
            padding: const EdgeInsets.only(top: 8),
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
        Expanded(child: child),
      ],
    );
  }
}

/// A removable dependency chip in the edit card.
class _DepChip extends StatelessWidget {
  final int depId;
  final VoidCallback onRemove;

  const _DepChip({
    required this.depId,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayId = 'TKT-${depId.toString().padLeft(3, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayId,
            style: AppFonts.monoTextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 12,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Action bar with select all, deselect all, reject, and approve buttons.
class _ActionBar extends StatelessWidget {
  final int checkedCount;

  const _ActionBar({required this.checkedCount});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.read<TicketBoardState>();

    return Row(
      children: [
        TextButton(
          key: TicketBulkReviewKeys.selectAllButton,
          onPressed: () => ticketBoard.setProposalAllChecked(true),
          child: Text(
            'Select All',
            style: TextStyle(color: colorScheme.primary),
          ),
        ),
        TextButton(
          key: TicketBulkReviewKeys.deselectAllButton,
          onPressed: () => ticketBoard.setProposalAllChecked(false),
          child: Text(
            'Deselect All',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          key: TicketBulkReviewKeys.rejectAllButton,
          onPressed: () => ticketBoard.rejectAll(),
          icon: Icon(Icons.close, size: 16, color: colorScheme.error),
          label: Text(
            'Reject All',
            style: TextStyle(color: colorScheme.error),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.error),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: TicketBulkReviewKeys.approveButton,
          onPressed: () => ticketBoard.approveBulk(),
          icon: const Icon(Icons.check, size: 16),
          label: Text('Approve $checkedCount'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
