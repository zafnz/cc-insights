import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';
import '../state/ticket_board_state.dart';
import '../widgets/ticket_graph_layout.dart';
import '../widgets/ticket_visuals.dart';

/// Test keys for the ticket graph view.
class TicketGraphViewKeys {
  TicketGraphViewKeys._();
  static const Key listToggle = Key('graph-view-list-toggle');
  static const Key graphToggle = Key('graph-view-graph-toggle');
  static const Key ticketCount = Key('graph-view-ticket-count');
  static const Key zoomIn = Key('graph-view-zoom-in');
  static const Key zoomOut = Key('graph-view-zoom-out');
  static const Key fitToScreen = Key('graph-view-fit-to-screen');
  static const Key emptyState = Key('graph-view-empty-state');
  static const Key interactiveViewer = Key('graph-view-interactive-viewer');
  static const Key legend = Key('graph-view-legend');

  /// Returns the key for a graph node by ticket ID.
  static Key nodeKey(int ticketId) => Key('graph-node-$ticketId');
}

/// Interactive graph visualization of ticket dependencies.
///
/// Renders tickets as card nodes positioned by [TicketGraphLayout] with edges
/// drawn between dependent tickets. Supports zoom/pan via [InteractiveViewer]
/// and syncs selection with [TicketBoardState].
class TicketGraphView extends StatefulWidget {
  const TicketGraphView({super.key});

  @override
  State<TicketGraphView> createState() => _TicketGraphViewState();
}

class _TicketGraphViewState extends State<TicketGraphView> {
  final TransformationController _transformController =
      TransformationController();

  /// Layout padding around the graph content.
  static const double _graphPadding = 40.0;

  /// Default zoom scale step for zoom in/out buttons.
  static const double _zoomStep = 0.25;

  /// Minimum zoom scale.
  static const double _minScale = 0.1;

  /// Maximum zoom scale.
  static const double _maxScale = 3.0;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale + _zoomStep).clamp(_minScale, _maxScale);
    _applyScale(newScale, currentScale);
  }

  void _zoomOut() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale - _zoomStep).clamp(_minScale, _maxScale);
    _applyScale(newScale, currentScale);
  }

  void _applyScale(double newScale, double currentScale) {
    if (newScale == currentScale) return;
    final scaleFactor = newScale / currentScale;
    final matrix = _transformController.value.clone();
    matrix.scale(scaleFactor);
    _transformController.value = matrix;
  }

  void _fitToScreen(GraphLayoutResult layout, BoxConstraints constraints) {
    if (layout.nodePositions.isEmpty) return;

    final contentWidth = layout.totalSize.width + _graphPadding * 2;
    final contentHeight = layout.totalSize.height + _graphPadding * 2;

    final scaleX = constraints.maxWidth / contentWidth;
    final scaleY = constraints.maxHeight / contentHeight;
    final scale = math.min(scaleX, scaleY).clamp(_minScale, _maxScale);

    // Center the content
    final scaledWidth = contentWidth * scale;
    final scaledHeight = contentHeight * scale;
    final offsetX = (constraints.maxWidth - scaledWidth) / 2;
    final offsetY = (constraints.maxHeight - scaledHeight) / 2;

    final matrix = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(scale);
    _transformController.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.watch<TicketBoardState>();
    final tickets = ticketBoard.filteredTickets;
    final layout = TicketGraphLayout.compute(tickets);

    return Column(
      children: [
        _GraphToolbar(
          ticketCount: tickets.length,
          onZoomIn: _zoomIn,
          onZoomOut: _zoomOut,
          onFitToScreen: () {
            // Need constraints from the graph area; use a post-frame callback
            // after the layout builder runs.
            _fitToScreenDeferred(layout);
          },
        ),
        Expanded(
          child: tickets.isEmpty
              ? const _EmptyGraphState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return _GraphArea(
                      layout: layout,
                      tickets: tickets,
                      transformController: _transformController,
                      onFitToScreen: () =>
                          _fitToScreen(layout, constraints),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _fitToScreenDeferred(GraphLayoutResult layout) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final size = renderBox.size;
      // Subtract toolbar height (approximately 40px)
      final constraints = BoxConstraints(
        maxWidth: size.width,
        maxHeight: size.height - 40,
      );
      _fitToScreen(layout, constraints);
    });
  }
}

/// Toolbar with view toggle, ticket count, and zoom controls.
class _GraphToolbar extends StatelessWidget {
  const _GraphToolbar({
    required this.ticketCount,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToScreen,
  });

  final int ticketCount;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitToScreen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.read<TicketBoardState>();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // View toggle: List / Graph
          _ViewToggleButtons(
            currentMode: context.watch<TicketBoardState>().viewMode,
            onChanged: ticketBoard.setViewMode,
          ),
          const SizedBox(width: 12),
          // Ticket count
          Text(
            '$ticketCount tickets',
            key: TicketGraphViewKeys.ticketCount,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Zoom controls
          IconButton(
            key: TicketGraphViewKeys.zoomIn,
            onPressed: onZoomIn,
            icon: const Icon(Icons.zoom_in, size: 18),
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: 'Zoom in',
          ),
          IconButton(
            key: TicketGraphViewKeys.zoomOut,
            onPressed: onZoomOut,
            icon: const Icon(Icons.zoom_out, size: 18),
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: 'Zoom out',
          ),
          IconButton(
            key: TicketGraphViewKeys.fitToScreen,
            onPressed: onFitToScreen,
            icon: const Icon(Icons.fit_screen, size: 18),
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: 'Fit to screen',
          ),
        ],
      ),
    );
  }
}

/// List/Graph toggle buttons in the toolbar.
class _ViewToggleButtons extends StatelessWidget {
  const _ViewToggleButtons({
    required this.currentMode,
    required this.onChanged,
  });

  final TicketViewMode currentMode;
  final ValueChanged<TicketViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            key: TicketGraphViewKeys.listToggle,
            icon: Icons.list,
            label: 'List',
            isActive: currentMode == TicketViewMode.list,
            onTap: () => onChanged(TicketViewMode.list),
          ),
          _ToggleButton(
            key: TicketGraphViewKeys.graphToggle,
            icon: Icons.account_tree,
            label: 'Graph',
            isActive: currentMode == TicketViewMode.graph,
            onTap: () => onChanged(TicketViewMode.graph),
          ),
        ],
      ),
    );
  }
}

/// A single toggle button segment.
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The graph area with interactive viewer, edges, nodes, and legend.
class _GraphArea extends StatelessWidget {
  const _GraphArea({
    required this.layout,
    required this.tickets,
    required this.transformController,
    required this.onFitToScreen,
  });

  final GraphLayoutResult layout;
  final List<TicketData> tickets;
  final TransformationController transformController;
  final VoidCallback onFitToScreen;

  static const double _nodeWidth = 140;
  static const double _nodeHeight = 80;
  static const double _padding = 40;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.watch<TicketBoardState>();
    final selectedId = ticketBoard.selectedTicket?.id;

    // Build a map for quick ticket lookup
    final ticketMap = {for (final t in tickets) t.id: t};

    // Content size with padding
    final contentWidth = layout.totalSize.width + _padding * 2;
    final contentHeight = layout.totalSize.height + _padding * 2;

    return Stack(
      children: [
        // Interactive graph
        InteractiveViewer(
          key: TicketGraphViewKeys.interactiveViewer,
          transformationController: transformController,
          constrained: false,
          minScale: 0.1,
          maxScale: 3.0,
          boundaryMargin: const EdgeInsets.all(200),
          child: SizedBox(
            width: math.max(contentWidth, 400),
            height: math.max(contentHeight, 400),
            child: Stack(
              children: [
                // Edge layer
                CustomPaint(
                  size: Size(contentWidth, contentHeight),
                  painter: _EdgePainter(
                    edges: layout.edges,
                    offset: Offset(_padding, _padding),
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                // Node layer
                ...layout.nodePositions.entries.map((entry) {
                  final ticket = ticketMap[entry.key];
                  if (ticket == null) return const SizedBox.shrink();
                  return Positioned(
                    left: entry.value.dx + _padding,
                    top: entry.value.dy + _padding,
                    width: _nodeWidth,
                    height: _nodeHeight,
                    child: _TicketGraphNode(
                      key: TicketGraphViewKeys.nodeKey(ticket.id),
                      ticket: ticket,
                      isSelected: ticket.id == selectedId,
                      onTap: () => ticketBoard.selectTicket(ticket.id),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // Legend overlay
        Positioned(
          bottom: 16,
          left: 16,
          child: _StatusLegend(key: TicketGraphViewKeys.legend),
        ),
      ],
    );
  }
}

/// Empty state when no tickets match the current filters.
class _EmptyGraphState extends StatelessWidget {
  const _EmptyGraphState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      key: TicketGraphViewKeys.emptyState,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_tree,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No tickets to display',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create tickets or adjust filters to see the dependency graph',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card node representing a ticket in the graph.
///
/// Displays the ticket's status icon, display ID, title, and a colored
/// border indicating status. Tapping selects the ticket.
class _TicketGraphNode extends StatelessWidget {
  const _TicketGraphNode({
    super.key,
    required this.ticket,
    required this.isSelected,
    required this.onTap,
  });

  final TicketData ticket;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = TicketStatusVisuals.color(ticket.status, colorScheme);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(
            children: [
              // Left status color bar
              Container(
                width: 4,
                color: statusColor,
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: status icon + display ID
                      Row(
                        children: [
                          TicketStatusIcon(
                            status: ticket.status,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            ticket.displayId,
                            style: AppFonts.monoTextStyle(
                              fontSize: 9,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Title
                      Expanded(
                        child: Text(
                          ticket.title,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Bottom status bar
                      Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for drawing edges between ticket nodes.
class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.edges,
    required this.offset,
    required this.color,
  });

  final List<GraphEdge> edges;
  final Offset offset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final edge in edges) {
      if (edge.points.length < 2) continue;

      // Draw the line path
      final path = Path();
      final firstPoint = edge.points.first + offset;
      path.moveTo(firstPoint.dx, firstPoint.dy);

      for (var i = 1; i < edge.points.length; i++) {
        final point = edge.points[i] + offset;
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);

      // Draw arrowhead at the end point
      _drawArrowhead(
        canvas,
        arrowPaint,
        edge.points[edge.points.length - 2] + offset,
        edge.points.last + offset,
      );
    }
  }

  void _drawArrowhead(
    Canvas canvas,
    Paint paint,
    Offset from,
    Offset to,
  ) {
    const arrowSize = 8.0;
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);

    final arrowPath = Path();
    arrowPath.moveTo(to.dx, to.dy);
    arrowPath.lineTo(
      to.dx - arrowSize * math.cos(angle - 0.4),
      to.dy - arrowSize * math.sin(angle - 0.4),
    );
    arrowPath.lineTo(
      to.dx - arrowSize * math.cos(angle + 0.4),
      to.dy - arrowSize * math.sin(angle + 0.4),
    );
    arrowPath.close();

    canvas.drawPath(arrowPath, paint);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      edges != oldDelegate.edges ||
      offset != oldDelegate.offset ||
      color != oldDelegate.color;
}

/// Legend showing status colors and labels.
class _StatusLegend extends StatelessWidget {
  const _StatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show a subset of statuses to keep legend compact
    final statuses = [
      TicketStatus.ready,
      TicketStatus.active,
      TicketStatus.blocked,
      TicketStatus.inReview,
      TicketStatus.completed,
      TicketStatus.cancelled,
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Status',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ...statuses.map((status) {
            final statusColor =
                TicketStatusVisuals.color(status, colorScheme);
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
