import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../panels/ticket_bulk_review_panel.dart';
import '../panels/ticket_detail_panel.dart';
import '../panels/ticket_graph_view.dart';
import '../panels/ticket_list_panel.dart';
import '../state/bulk_proposal_state.dart';
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
    return EditableMultiSplitView(
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

    return Material(
      color: colorScheme.surface,
      child: bulkProposal.hasActiveProposal
          ? const TicketBulkReviewPanel()
          : viewState.viewMode == TicketViewMode.graph
              ? const TicketGraphView()
              : const TicketDetailPanel(),
    );
  }
}
