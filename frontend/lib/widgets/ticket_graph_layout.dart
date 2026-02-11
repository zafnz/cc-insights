import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/ticket.dart';

/// Result of a graph layout computation.
///
/// Contains positioned nodes and routed edges for rendering a ticket
/// dependency graph.
@immutable
class GraphLayoutResult {
  /// Ticket ID to top-left corner position.
  final Map<int, Offset> nodePositions;

  /// Edges connecting dependent tickets.
  final List<GraphEdge> edges;

  /// Bounding box that encompasses all nodes (includes node dimensions).
  final Size totalSize;

  /// Creates a [GraphLayoutResult].
  const GraphLayoutResult({
    required this.nodePositions,
    required this.edges,
    required this.totalSize,
  });

  /// Empty result for zero-ticket input.
  static const empty = GraphLayoutResult(
    nodePositions: {},
    edges: [],
    totalSize: Size.zero,
  );
}

/// A directed edge in the graph with a polyline path.
@immutable
class GraphEdge {
  /// The ticket ID this edge originates from (the dependency).
  final int fromId;

  /// The ticket ID this edge points to (the dependent).
  final int toId;

  /// Ordered points forming the edge path.
  final List<Offset> points;

  /// Creates a [GraphEdge].
  const GraphEdge({
    required this.fromId,
    required this.toId,
    required this.points,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GraphEdge &&
        other.fromId == fromId &&
        other.toId == toId &&
        listEquals(other.points, points);
  }

  @override
  int get hashCode => Object.hash(fromId, toId, Object.hashAll(points));

  @override
  String toString() => 'GraphEdge($fromId -> $toId, ${points.length} points)';
}

/// Computes a Sugiyama-style layered layout for a ticket dependency graph.
///
/// The algorithm:
/// 1. Identifies disconnected components and lays them out side by side.
/// 2. Within each component, assigns layers via longest-path from sources.
/// 3. Orders nodes within layers using the barycenter heuristic to reduce
///    edge crossings.
/// 4. Assigns x/y coordinates with configurable spacing.
///
/// Edges flow top-to-bottom: dependencies (layer 0) are at the top, and
/// dependents are in lower layers.
class TicketGraphLayout {
  /// Computes layout positions for [tickets] and their dependency edges.
  ///
  /// Tickets without dependencies appear in layer 0 (top). Each ticket is
  /// placed in the layer one below its deepest dependency.
  ///
  /// [nodeWidth] and [nodeHeight] define the bounding box of each node.
  /// [horizontalGap] is the space between nodes in the same layer.
  /// [verticalGap] is the space between layers.
  static GraphLayoutResult compute(
    List<TicketData> tickets, {
    double nodeWidth = 140,
    double nodeHeight = 80,
    double horizontalGap = 40,
    double verticalGap = 60,
  }) {
    if (tickets.isEmpty) return GraphLayoutResult.empty;

    final ticketMap = {for (final t in tickets) t.id: t};
    final ids = ticketMap.keys.toSet();

    // Build adjacency: from dependency -> dependent (forward edges for layout)
    // "children" of a node are tickets that depend on it
    final children = <int, List<int>>{};
    final parents = <int, List<int>>{};
    for (final id in ids) {
      children[id] = [];
      parents[id] = [];
    }
    for (final t in tickets) {
      for (final depId in t.dependsOn) {
        if (ids.contains(depId)) {
          children[depId]!.add(t.id);
          parents[t.id]!.add(depId);
        }
      }
    }

    // Find disconnected components via BFS
    final components = _findComponents(ids, children, parents);

    // Layout each component, then arrange side by side
    final nodePositions = <int, Offset>{};
    final edges = <GraphEdge>[];
    var componentOffsetX = 0.0;
    var maxHeight = 0.0;

    for (final component in components) {
      final result = _layoutComponent(
        component,
        children,
        parents,
        ticketMap,
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      // Offset positions by current component X offset
      for (final entry in result.nodePositions.entries) {
        nodePositions[entry.key] = Offset(
          entry.value.dx + componentOffsetX,
          entry.value.dy,
        );
      }

      // Offset edge points
      for (final edge in result.edges) {
        edges.add(GraphEdge(
          fromId: edge.fromId,
          toId: edge.toId,
          points: edge.points
              .map((p) => Offset(p.dx + componentOffsetX, p.dy))
              .toList(),
        ));
      }

      componentOffsetX += result.totalSize.width + horizontalGap;
      maxHeight = math.max(maxHeight, result.totalSize.height);
    }

    // Total width: sum of component widths + gaps between them
    // Subtract the trailing gap added after the last component
    final totalWidth = componentOffsetX > 0
        ? componentOffsetX - horizontalGap
        : 0.0;

    return GraphLayoutResult(
      nodePositions: nodePositions,
      edges: edges,
      totalSize: Size(totalWidth, maxHeight),
    );
  }

  /// Finds connected components in an undirected sense.
  static List<Set<int>> _findComponents(
    Set<int> ids,
    Map<int, List<int>> children,
    Map<int, List<int>> parents,
  ) {
    final visited = <int>{};
    final components = <Set<int>>[];

    for (final id in ids) {
      if (visited.contains(id)) continue;
      final component = <int>{};
      final queue = [id];
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        if (!component.add(current)) continue;
        visited.add(current);
        for (final child in children[current] ?? <int>[]) {
          if (!component.contains(child)) queue.add(child);
        }
        for (final parent in parents[current] ?? <int>[]) {
          if (!component.contains(parent)) queue.add(parent);
        }
      }
      components.add(component);
    }

    return components;
  }

  /// Lays out a single connected component.
  static GraphLayoutResult _layoutComponent(
    Set<int> component,
    Map<int, List<int>> children,
    Map<int, List<int>> parents,
    Map<int, TicketData> ticketMap, {
    required double nodeWidth,
    required double nodeHeight,
    required double horizontalGap,
    required double verticalGap,
  }) {
    // Assign layers using longest path from sources (nodes with no parents
    // in this component).
    final layers = _assignLayers(component, children, parents);

    // Group nodes by layer
    final maxLayer = layers.values.fold(0, math.max);
    final layerNodes = List.generate(maxLayer + 1, (_) => <int>[]);
    for (final entry in layers.entries) {
      layerNodes[entry.value].add(entry.key);
    }

    // Initial ordering: sort by ID for determinism
    for (final layer in layerNodes) {
      layer.sort();
    }

    // Barycenter heuristic — sweep down then up to reduce crossings
    _barycentricOrdering(layerNodes, children, parents);

    // Assign coordinates
    final nodePositions = <int, Offset>{};
    var totalWidth = 0.0;

    for (var layerIdx = 0; layerIdx < layerNodes.length; layerIdx++) {
      final nodes = layerNodes[layerIdx];
      final layerWidth =
          nodes.length * nodeWidth + (nodes.length - 1) * horizontalGap;
      totalWidth = math.max(totalWidth, layerWidth);
    }

    for (var layerIdx = 0; layerIdx < layerNodes.length; layerIdx++) {
      final nodes = layerNodes[layerIdx];
      final layerWidth =
          nodes.length * nodeWidth + (nodes.length - 1) * horizontalGap;
      // Center the layer within the total width
      final startX = (totalWidth - layerWidth) / 2;
      final y = layerIdx * (nodeHeight + verticalGap);

      for (var i = 0; i < nodes.length; i++) {
        final x = startX + i * (nodeWidth + horizontalGap);
        nodePositions[nodes[i]] = Offset(x, y.toDouble());
      }
    }

    // Create edges: straight line from bottom-center of parent to top-center
    // of child.
    final edges = <GraphEdge>[];
    for (final id in component) {
      for (final childId in children[id]!) {
        if (!component.contains(childId)) continue;
        final fromPos = nodePositions[id]!;
        final toPos = nodePositions[childId]!;
        final fromPoint = Offset(
          fromPos.dx + nodeWidth / 2,
          fromPos.dy + nodeHeight,
        );
        final toPoint = Offset(
          toPos.dx + nodeWidth / 2,
          toPos.dy,
        );
        edges.add(GraphEdge(
          fromId: id,
          toId: childId,
          points: [fromPoint, toPoint],
        ));
      }
    }

    final totalHeight = layerNodes.length * nodeHeight +
        (layerNodes.length - 1) * verticalGap;

    return GraphLayoutResult(
      nodePositions: nodePositions,
      edges: edges,
      totalSize: Size(totalWidth, totalHeight),
    );
  }

  /// Assigns each node to a layer using longest-path from sources.
  ///
  /// Source nodes (no parents in the component) go to layer 0.
  /// Each other node goes one layer below its deepest parent.
  static Map<int, int> _assignLayers(
    Set<int> component,
    Map<int, List<int>> children,
    Map<int, List<int>> parents,
  ) {
    final layers = <int, int>{};

    // Filter parents/children to only those in this component
    List<int> componentParents(int id) =>
        (parents[id] ?? []).where(component.contains).toList();
    List<int> componentChildren(int id) =>
        (children[id] ?? []).where(component.contains).toList();

    // Kahn's algorithm style: process in topological order
    final inDegree = <int, int>{};
    for (final id in component) {
      inDegree[id] = componentParents(id).length;
    }

    // Start with sources
    final queue = <int>[];
    for (final id in component) {
      if (inDegree[id] == 0) {
        queue.add(id);
        layers[id] = 0;
      }
    }

    // Sort queue for determinism
    queue.sort();

    var idx = 0;
    while (idx < queue.length) {
      final id = queue[idx++];
      final myLayer = layers[id]!;

      for (final childId in componentChildren(id)) {
        // Child layer is at least one more than this parent
        final candidateLayer = myLayer + 1;
        if (!layers.containsKey(childId) || layers[childId]! < candidateLayer) {
          layers[childId] = candidateLayer;
        }
        inDegree[childId] = inDegree[childId]! - 1;
        if (inDegree[childId] == 0) {
          queue.add(childId);
        }
      }
    }

    return layers;
  }

  /// Applies the barycenter heuristic to reorder nodes within layers.
  ///
  /// Performs a downward sweep followed by an upward sweep. Each node is
  /// assigned the average position of its connected nodes in the adjacent
  /// layer, then the layer is sorted by these barycenters.
  static void _barycentricOrdering(
    List<List<int>> layerNodes,
    Map<int, List<int>> children,
    Map<int, List<int>> parents,
  ) {
    // Build position index for fast lookups
    Map<int, int> positionIndex(List<List<int>> layers) {
      final index = <int, int>{};
      for (final layer in layers) {
        for (var i = 0; i < layer.length; i++) {
          index[layer[i]] = i;
        }
      }
      return index;
    }

    // Number of sweeps
    const sweeps = 4;
    for (var sweep = 0; sweep < sweeps; sweep++) {
      // Downward sweep: for each layer (except first), order by barycenter
      // of parents in the previous layer
      var posIdx = positionIndex(layerNodes);
      for (var i = 1; i < layerNodes.length; i++) {
        final layer = layerNodes[i];
        final barycenters = <int, double>{};
        for (final id in layer) {
          final parentPositions = (parents[id] ?? [])
              .where((p) => posIdx.containsKey(p))
              .map((p) => posIdx[p]!.toDouble())
              .toList();
          if (parentPositions.isNotEmpty) {
            barycenters[id] =
                parentPositions.reduce((a, b) => a + b) / parentPositions.length;
          } else {
            // Keep original position
            barycenters[id] = posIdx[id]?.toDouble() ?? 0;
          }
        }
        layer.sort((a, b) => barycenters[a]!.compareTo(barycenters[b]!));
      }

      // Upward sweep: for each layer (except last), order by barycenter
      // of children in the next layer
      posIdx = positionIndex(layerNodes);
      for (var i = layerNodes.length - 2; i >= 0; i--) {
        final layer = layerNodes[i];
        final barycenters = <int, double>{};
        for (final id in layer) {
          final childPositions = (children[id] ?? [])
              .where((c) => posIdx.containsKey(c))
              .map((c) => posIdx[c]!.toDouble())
              .toList();
          if (childPositions.isNotEmpty) {
            barycenters[id] =
                childPositions.reduce((a, b) => a + b) / childPositions.length;
          } else {
            barycenters[id] = posIdx[id]?.toDouble() ?? 0;
          }
        }
        layer.sort((a, b) => barycenters[a]!.compareTo(barycenters[b]!));
      }
    }
  }
}
