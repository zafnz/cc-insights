import 'dart:ui';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/widgets/ticket_graph_layout.dart';

/// Helper to create a minimal [TicketData] for layout tests.
TicketData _ticket(int id, {List<int> dependsOn = const []}) {
  final now = DateTime.now();
  return TicketData(
    id: id,
    title: 'Ticket $id',
    description: 'Description for ticket $id',
    status: TicketStatus.ready,
    kind: TicketKind.feature,
    priority: TicketPriority.medium,
    effort: TicketEffort.medium,
    dependsOn: dependsOn,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const nodeWidth = 140.0;
  const nodeHeight = 80.0;
  const horizontalGap = 40.0;
  const verticalGap = 60.0;

  group('TicketGraphLayout', () {
    test('empty input returns empty result', () {
      final result = TicketGraphLayout.compute([]);

      check(result.nodePositions).isEmpty();
      check(result.edges).isEmpty();
      check(result.totalSize.width).equals(0.0);
      check(result.totalSize.height).equals(0.0);
    });

    test('single ticket is positioned at origin', () {
      final result = TicketGraphLayout.compute(
        [_ticket(1)],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      check(result.nodePositions).length.equals(1);
      check(result.nodePositions[1]).isNotNull();
      check(result.nodePositions[1]!.dx).equals(0.0);
      check(result.nodePositions[1]!.dy).equals(0.0);
      check(result.edges).isEmpty();
      check(result.totalSize).equals(const Size(nodeWidth, nodeHeight));
    });

    test('linear chain A->B->C laid out in 3 layers vertically', () {
      // A(1) has no deps, B(2) depends on A, C(3) depends on B
      final result = TicketGraphLayout.compute(
        [
          _ticket(1),
          _ticket(2, dependsOn: [1]),
          _ticket(3, dependsOn: [2]),
        ],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      check(result.nodePositions).length.equals(3);

      // All three should be centered horizontally (same X since one per layer)
      final pos1 = result.nodePositions[1]!;
      final pos2 = result.nodePositions[2]!;
      final pos3 = result.nodePositions[3]!;

      check(pos1.dx).equals(pos2.dx);
      check(pos2.dx).equals(pos3.dx);

      // Verify vertical ordering: layer 0 < layer 1 < layer 2
      check(pos1.dy).isLessThan(pos2.dy);
      check(pos2.dy).isLessThan(pos3.dy);

      // Verify exact Y positions
      check(pos1.dy).equals(0.0);
      check(pos2.dy).equals(nodeHeight + verticalGap);
      check(pos3.dy).equals(2 * (nodeHeight + verticalGap));

      // Verify edges: 1->2, 2->3
      check(result.edges).length.equals(2);
      final edgeIds = result.edges.map((e) => '${e.fromId}->${e.toId}').toSet();
      check(edgeIds).contains('1->2');
      check(edgeIds).contains('2->3');
    });

    test('diamond shape: A->B, A->C, B->D, C->D', () {
      // Layer 0: A(1)
      // Layer 1: B(2), C(3)
      // Layer 2: D(4)
      final result = TicketGraphLayout.compute(
        [
          _ticket(1),
          _ticket(2, dependsOn: [1]),
          _ticket(3, dependsOn: [1]),
          _ticket(4, dependsOn: [2, 3]),
        ],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      check(result.nodePositions).length.equals(4);

      final pos1 = result.nodePositions[1]!;
      final pos2 = result.nodePositions[2]!;
      final pos3 = result.nodePositions[3]!;
      final pos4 = result.nodePositions[4]!;

      // Layer 0: ticket 1 (single node, centered)
      // Layer 1: tickets 2, 3 (two nodes side by side)
      // Layer 2: ticket 4 (single node, centered)
      check(pos1.dy).equals(0.0);
      check(pos2.dy).equals(nodeHeight + verticalGap);
      check(pos3.dy).equals(nodeHeight + verticalGap);
      check(pos4.dy).equals(2 * (nodeHeight + verticalGap));

      // B and C should be at different X positions
      check(pos2.dx).not((it) => it.equals(pos3.dx));

      // A and D should be centered (same X position)
      check(pos1.dx).equals(pos4.dx);

      // Verify 4 edges
      check(result.edges).length.equals(4);
    });

    test('disconnected components are placed side by side', () {
      // Component 1: ticket 1 -> ticket 2
      // Component 2: ticket 10 -> ticket 11
      final result = TicketGraphLayout.compute(
        [
          _ticket(1),
          _ticket(2, dependsOn: [1]),
          _ticket(10),
          _ticket(11, dependsOn: [10]),
        ],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      check(result.nodePositions).length.equals(4);

      // Both components have 2 layers, so same height
      final pos1 = result.nodePositions[1]!;
      final pos2 = result.nodePositions[2]!;
      final pos10 = result.nodePositions[10]!;
      final pos11 = result.nodePositions[11]!;

      // Within each component, vertical ordering is correct
      check(pos1.dy).isLessThan(pos2.dy);
      check(pos10.dy).isLessThan(pos11.dy);

      // The two components should not overlap horizontally.
      // Component 1 nodes should all be to the left of component 2 nodes
      // (or vice versa — the key is no overlap).
      final comp1MaxX = [pos1.dx, pos2.dx].reduce((a, b) => a > b ? a : b) + nodeWidth;
      final comp2MinX = [pos10.dx, pos11.dx].reduce((a, b) => a < b ? a : b);

      // Either component 1 is fully left of component 2 or vice versa
      final separated = comp1MaxX <= comp2MinX ||
          ([pos10.dx, pos11.dx].reduce((a, b) => a > b ? a : b) + nodeWidth) <=
              [pos1.dx, pos2.dx].reduce((a, b) => a < b ? a : b);
      check(separated).isTrue();
    });

    test('wide graph: 10 tickets depending on 1 root', () {
      // Root ticket 1, then tickets 2-11 all depend on ticket 1
      final tickets = [_ticket(1)];
      for (var i = 2; i <= 11; i++) {
        tickets.add(_ticket(i, dependsOn: [1]));
      }

      final result = TicketGraphLayout.compute(
        tickets,
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      check(result.nodePositions).length.equals(11);

      // Root should be in layer 0
      final rootPos = result.nodePositions[1]!;
      check(rootPos.dy).equals(0.0);

      // All 10 children should be in layer 1
      for (var i = 2; i <= 11; i++) {
        check(result.nodePositions[i]!.dy).equals(nodeHeight + verticalGap);
      }

      // Layer 1 width: 10 nodes * 140 + 9 gaps * 40 = 1760
      final expectedLayerWidth = 10 * nodeWidth + 9 * horizontalGap;
      check(result.totalSize.width).equals(expectedLayerWidth);

      // 2 layers total
      check(result.totalSize.height).equals(2 * nodeHeight + verticalGap);

      // 10 edges from root to each child
      check(result.edges).length.equals(10);
    });

    test('total size encompasses all nodes', () {
      // Use a diamond to get multiple layers and widths
      final result = TicketGraphLayout.compute(
        [
          _ticket(1),
          _ticket(2, dependsOn: [1]),
          _ticket(3, dependsOn: [1]),
          _ticket(4, dependsOn: [2, 3]),
        ],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      // Verify every node fits within the total size bounding box
      for (final entry in result.nodePositions.entries) {
        final pos = entry.value;
        check(pos.dx)
            .isGreaterOrEqual(0.0);
        check(pos.dy)
            .isGreaterOrEqual(0.0);
        check(pos.dx + nodeWidth)
            .isLessOrEqual(result.totalSize.width + 0.001);
        check(pos.dy + nodeHeight)
            .isLessOrEqual(result.totalSize.height + 0.001);
      }
    });

    test('edges have valid start and end points', () {
      final result = TicketGraphLayout.compute(
        [
          _ticket(1),
          _ticket(2, dependsOn: [1]),
          _ticket(3, dependsOn: [2]),
        ],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      for (final edge in result.edges) {
        check(edge.points).isNotEmpty();

        // Start point should be at bottom-center of the from-node
        final fromPos = result.nodePositions[edge.fromId]!;
        final startPoint = edge.points.first;
        check(startPoint.dx).equals(fromPos.dx + nodeWidth / 2);
        check(startPoint.dy).equals(fromPos.dy + nodeHeight);

        // End point should be at top-center of the to-node
        final toPos = result.nodePositions[edge.toId]!;
        final endPoint = edge.points.last;
        check(endPoint.dx).equals(toPos.dx + nodeWidth / 2);
        check(endPoint.dy).equals(toPos.dy);
      }
    });

    test('dependencies outside ticket set are ignored', () {
      // Ticket 2 depends on ticket 99, which is not in the list
      final result = TicketGraphLayout.compute(
        [
          _ticket(1),
          _ticket(2, dependsOn: [99]),
        ],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      // Both tickets are independent — both in layer 0
      check(result.nodePositions).length.equals(2);
      check(result.nodePositions[1]!.dy).equals(result.nodePositions[2]!.dy);
      // No edges (dep 99 not in set)
      check(result.edges).isEmpty();
    });

    test('GraphEdge equality and hashCode', () {
      const a = GraphEdge(
        fromId: 1,
        toId: 2,
        points: [Offset(0, 0), Offset(10, 10)],
      );
      const b = GraphEdge(
        fromId: 1,
        toId: 2,
        points: [Offset(0, 0), Offset(10, 10)],
      );
      const c = GraphEdge(
        fromId: 1,
        toId: 3,
        points: [Offset(0, 0), Offset(10, 10)],
      );

      check(a).equals(b);
      check(a.hashCode).equals(b.hashCode);
      check(a).not((it) => it.equals(c));
    });

    test('GraphLayoutResult.empty is truly empty', () {
      const result = GraphLayoutResult.empty;

      check(result.nodePositions).isEmpty();
      check(result.edges).isEmpty();
      check(result.totalSize).equals(Size.zero);
    });

    test('complex multi-layer DAG assigns correct layers', () {
      // Layer 0: 1
      // Layer 1: 2 (depends on 1)
      // Layer 2: 3 (depends on 2), 4 (depends on 1, but should be in layer 2
      //          because 3 and 4 have no ordering constraint — 4 depends on 1
      //          so it goes to layer 1, not 2)
      // Actually: 4 depends on 1 -> layer 1. 3 depends on 2 -> layer 2.
      // 5 depends on 3 and 4 -> layer max(2,1)+1 = 3
      final result = TicketGraphLayout.compute(
        [
          _ticket(1),
          _ticket(2, dependsOn: [1]),
          _ticket(3, dependsOn: [2]),
          _ticket(4, dependsOn: [1]),
          _ticket(5, dependsOn: [3, 4]),
        ],
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

      // Verify layer assignments via Y positions
      final layerForY = (double y) => (y / (nodeHeight + verticalGap)).round();

      check(layerForY(result.nodePositions[1]!.dy)).equals(0);
      check(layerForY(result.nodePositions[2]!.dy)).equals(1);
      check(layerForY(result.nodePositions[4]!.dy)).equals(1);
      check(layerForY(result.nodePositions[3]!.dy)).equals(2);
      check(layerForY(result.nodePositions[5]!.dy)).equals(3);
    });
  });
}
