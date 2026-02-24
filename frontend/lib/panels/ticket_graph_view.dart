import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';
import '../state/ticket_view_state.dart';
import '../widgets/ticket_graph_layout.dart';

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
    final viewState = context.watch<TicketViewState>();
    final tickets = viewState.filteredTickets;
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
    final viewState = context.read<TicketViewState>();

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
            currentMode: context.watch<TicketViewState>().viewMode,
            onChanged: viewState.setViewMode,
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
    final viewState = context.watch<TicketViewState>();
    final selectedId = viewState.selectedTicket?.id;

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
                    ticketMap: ticketMap,
                    satisfiedColor: _openClosedColors.closed,
                    unsatisfiedColor: colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
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
                      onTap: () => viewState.selectTicket(ticket.id),
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

/// Open/Closed colour constants for the graph.
const _openClosedColors = (
  open: Color(0xFF4CAF50),
  closed: Color(0xFFCE93D8),
);

/// A card node representing a ticket in the graph.
///
/// Displays the ticket's open/closed icon, display ID, title, and tag chips.
/// Tapping selects the ticket.
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
    final statusColor =
        ticket.isOpen ? _openClosedColors.open : _openClosedColors.closed;

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
                      // Header: open/closed icon + display ID
                      Row(
                        children: [
                          Icon(
                            ticket.isOpen
                                ? Icons.radio_button_unchecked
                                : Icons.check_circle_outline,
                            size: 12,
                            color: statusColor,
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
                      // Tag chips
                      if (ticket.tags.isNotEmpty)
                        SizedBox(
                          height: 14,
                          child: Row(
                            children: ticket.tags
                                .take(3)
                                .map((tag) => Padding(
                                      padding:
                                          const EdgeInsets.only(right: 4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                            fontSize: 8,
                                            color:
                                                colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
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
///
/// Edges are coloured based on whether the dependency (source node) is
/// satisfied (closed) or unsatisfied (open).
class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.edges,
    required this.offset,
    required this.ticketMap,
    required this.satisfiedColor,
    required this.unsatisfiedColor,
  });

  final List<GraphEdge> edges;
  final Offset offset;
  final Map<int, TicketData> ticketMap;
  final Color satisfiedColor;
  final Color unsatisfiedColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      if (edge.points.length < 2) continue;

      // Determine if the dependency (from-node) is satisfied (closed).
      final fromTicket = ticketMap[edge.fromId];
      final isSatisfied = fromTicket != null && !fromTicket.isOpen;
      final edgeColor = isSatisfied ? satisfiedColor : unsatisfiedColor;

      final paint = Paint()
        ..color = edgeColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final arrowPaint = Paint()
        ..color = edgeColor
        ..style = PaintingStyle.fill;

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
      ticketMap != oldDelegate.ticketMap ||
      satisfiedColor != oldDelegate.satisfiedColor ||
      unsatisfiedColor != oldDelegate.unsatisfiedColor;
}

/// Legend showing Open/Closed status colours.
class _StatusLegend extends StatelessWidget {
  const _StatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    const entries = [
      (label: 'Open', color: _openClosedColors, isOpen: true),
      (label: 'Closed', color: _openClosedColors, isOpen: false),
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
          ...entries.map((entry) {
            final dotColor =
                entry.isOpen ? _openClosedColors.open : _openClosedColors.closed;
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    entry.label,
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
