import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';
import '../panels/ticket_bulk_review_panel.dart';
import '../panels/ticket_create_form.dart';
import '../panels/ticket_detail_panel.dart';
import '../panels/ticket_graph_view.dart';
import '../panels/ticket_list_panel.dart';
import '../state/bulk_proposal_state.dart';
import '../state/ticket_board_state.dart';
import '../state/ticket_view_state.dart';

/// Ticket management screen with resizable split panels.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  late final SplitLayoutController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SplitLayoutController(rootNode: _buildInitialLayout());
    // Match file manager behavior: editable split layout with draggable divider.
    _controller.editMode = true;
  }

  SplitNode _buildInitialLayout() {
    return SplitNode.branch(
      id: 'ticket_root',
      axis: SplitAxis.horizontal,
      children: [
        SplitNode.leaf(
          id: 'ticket_list',
          widgetBuilder: (context) => const TicketListPanel(),
        ),
        SplitNode.leaf(
          id: 'ticket_content',
          flex: 2.5,
          widgetBuilder: (context) => const _TicketContentPanel(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: EditableMultiSplitView(
            controller: _controller,
            config: EditableMultiSplitViewConfig(
              dividerThickness: 1.0,
              dividerHandleBuffer: 3.0,
              paneConfig: DraggablePaneConfig(
                dragFeedbackOpacity: 0.8,
                dragFeedbackScale: 0.95,
                useLongPressOnMobile: true,
                previewStyle: DropPreviewStyle(
                  splitColor: colorScheme.primary.withValues(alpha: 0.3),
                  replaceColor: colorScheme.secondary.withValues(alpha: 0.3),
                  borderWidth: 2.0,
                  animationDuration: const Duration(milliseconds: 150),
                ),
                dragHandleBuilder: (context) => Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
        const _StatusBar(),
      ],
    );
  }
}

class _TicketContentPanel extends StatelessWidget {
  const _TicketContentPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewState = context.watch<TicketViewState>();
    final bulkProposal = context.watch<BulkProposalState>();
    final repo = context.watch<TicketRepository>();

    Widget content;
    if (bulkProposal.hasActiveProposal) {
      content = const TicketBulkReviewPanel();
    } else if (viewState.viewMode == TicketViewMode.graph) {
      content = const TicketGraphView();
    } else if (viewState.detailMode == TicketDetailMode.create) {
      content = const TicketCreateForm();
    } else if (repo.tickets.isEmpty &&
        viewState.detailMode == TicketDetailMode.detail) {
      content = const _NoTicketsEmpty();
    } else {
      content = const TicketDetailPanel();
    }

    return Material(
      color: colorScheme.surface,
      child: content,
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final repo = context.watch<TicketRepository>();
    final viewState = context.watch<TicketViewState>();
    final total = repo.tickets.length;
    final open = viewState.openCount;
    final closed = viewState.closedCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Text(
        '$total tickets \u2013 $open open \u2013 $closed closed',
        style: AppFonts.monoTextStyle(
          fontSize: 11,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NoTicketsEmpty extends StatelessWidget {
  const _NoTicketsEmpty();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final viewState = context.read<TicketViewState>();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.task_alt,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No tickets',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => viewState.showCreateForm(),
            child: Text(
              'Create your first ticket',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
