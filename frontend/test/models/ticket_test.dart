import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/models/ticket.dart';

void main() {
  group('TicketStatus enum', () {
    test('has correct labels', () {
      check(TicketStatus.draft.label).equals('Draft');
      check(TicketStatus.ready.label).equals('Ready');
      check(TicketStatus.active.label).equals('Active');
      check(TicketStatus.blocked.label).equals('Blocked');
      check(TicketStatus.needsInput.label).equals('Needs Input');
      check(TicketStatus.inReview.label).equals('In Review');
      check(TicketStatus.completed.label).equals('Completed');
      check(TicketStatus.cancelled.label).equals('Cancelled');
    });

    test('has correct jsonValues', () {
      check(TicketStatus.draft.jsonValue).equals('draft');
      check(TicketStatus.ready.jsonValue).equals('ready');
      check(TicketStatus.active.jsonValue).equals('active');
      check(TicketStatus.blocked.jsonValue).equals('blocked');
      check(TicketStatus.needsInput.jsonValue).equals('needsInput');
      check(TicketStatus.inReview.jsonValue).equals('inReview');
      check(TicketStatus.completed.jsonValue).equals('completed');
      check(TicketStatus.cancelled.jsonValue).equals('cancelled');
    });

    test('fromJson round-trips', () {
      for (final status in TicketStatus.values) {
        check(TicketStatus.fromJson(status.jsonValue)).equals(status);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => TicketStatus.fromJson('invalid'))
          .throws<ArgumentError>();
    });
  });

  group('TicketKind enum', () {
    test('has correct labels', () {
      check(TicketKind.feature.label).equals('Feature');
      check(TicketKind.bugfix.label).equals('Bug Fix');
      check(TicketKind.research.label).equals('Research');
      check(TicketKind.split.label).equals('Split');
      check(TicketKind.question.label).equals('Question');
      check(TicketKind.test.label).equals('Test');
      check(TicketKind.docs.label).equals('Docs');
      check(TicketKind.chore.label).equals('Chore');
    });

    test('has correct jsonValues', () {
      check(TicketKind.feature.jsonValue).equals('feature');
      check(TicketKind.bugfix.jsonValue).equals('bugfix');
      check(TicketKind.research.jsonValue).equals('research');
      check(TicketKind.split.jsonValue).equals('split');
      check(TicketKind.question.jsonValue).equals('question');
      check(TicketKind.test.jsonValue).equals('test');
      check(TicketKind.docs.jsonValue).equals('docs');
      check(TicketKind.chore.jsonValue).equals('chore');
    });

    test('fromJson round-trips', () {
      for (final kind in TicketKind.values) {
        check(TicketKind.fromJson(kind.jsonValue)).equals(kind);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => TicketKind.fromJson('invalid'))
          .throws<ArgumentError>();
    });
  });

  group('TicketPriority enum', () {
    test('has correct labels', () {
      check(TicketPriority.low.label).equals('Low');
      check(TicketPriority.medium.label).equals('Medium');
      check(TicketPriority.high.label).equals('High');
      check(TicketPriority.critical.label).equals('Critical');
    });

    test('has correct jsonValues', () {
      check(TicketPriority.low.jsonValue).equals('low');
      check(TicketPriority.medium.jsonValue).equals('medium');
      check(TicketPriority.high.jsonValue).equals('high');
      check(TicketPriority.critical.jsonValue).equals('critical');
    });

    test('fromJson round-trips', () {
      for (final priority in TicketPriority.values) {
        check(TicketPriority.fromJson(priority.jsonValue)).equals(priority);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => TicketPriority.fromJson('invalid'))
          .throws<ArgumentError>();
    });
  });

  group('TicketEffort enum', () {
    test('has correct labels', () {
      check(TicketEffort.small.label).equals('Small');
      check(TicketEffort.medium.label).equals('Medium');
      check(TicketEffort.large.label).equals('Large');
    });

    test('has correct jsonValues', () {
      check(TicketEffort.small.jsonValue).equals('small');
      check(TicketEffort.medium.jsonValue).equals('medium');
      check(TicketEffort.large.jsonValue).equals('large');
    });

    test('fromJson round-trips', () {
      for (final effort in TicketEffort.values) {
        check(TicketEffort.fromJson(effort.jsonValue)).equals(effort);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => TicketEffort.fromJson('invalid'))
          .throws<ArgumentError>();
    });
  });

  group('TicketViewMode enum', () {
    test('has correct labels', () {
      check(TicketViewMode.list.label).equals('List');
      check(TicketViewMode.graph.label).equals('Graph');
    });

    test('has correct jsonValues', () {
      check(TicketViewMode.list.jsonValue).equals('list');
      check(TicketViewMode.graph.jsonValue).equals('graph');
    });

    test('fromJson round-trips', () {
      for (final mode in TicketViewMode.values) {
        check(TicketViewMode.fromJson(mode.jsonValue)).equals(mode);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => TicketViewMode.fromJson('invalid'))
          .throws<ArgumentError>();
    });
  });

  group('TicketGroupBy enum', () {
    test('has correct labels', () {
      check(TicketGroupBy.category.label).equals('Category');
      check(TicketGroupBy.status.label).equals('Status');
      check(TicketGroupBy.kind.label).equals('Kind');
      check(TicketGroupBy.priority.label).equals('Priority');
    });

    test('has correct jsonValues', () {
      check(TicketGroupBy.category.jsonValue).equals('category');
      check(TicketGroupBy.status.jsonValue).equals('status');
      check(TicketGroupBy.kind.jsonValue).equals('kind');
      check(TicketGroupBy.priority.jsonValue).equals('priority');
    });

    test('fromJson round-trips', () {
      for (final groupBy in TicketGroupBy.values) {
        check(TicketGroupBy.fromJson(groupBy.jsonValue)).equals(groupBy);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => TicketGroupBy.fromJson('invalid'))
          .throws<ArgumentError>();
    });
  });

  group('LinkedWorktree', () {
    test('toJson/fromJson round-trip', () {
      const worktree = LinkedWorktree(
        worktreeRoot: '/path/to/worktree',
        branch: 'feature-branch',
      );

      final json = worktree.toJson();
      final restored = LinkedWorktree.fromJson(json);

      check(restored).equals(worktree);
    });

    test('toJson/fromJson round-trip with null branch', () {
      const worktree = LinkedWorktree(
        worktreeRoot: '/path/to/worktree',
      );

      final json = worktree.toJson();
      final restored = LinkedWorktree.fromJson(json);

      check(restored).equals(worktree);
    });

    test('toJson excludes null branch', () {
      const worktree = LinkedWorktree(
        worktreeRoot: '/path/to/worktree',
      );

      final json = worktree.toJson();

      check(json).deepEquals({
        'worktreeRoot': '/path/to/worktree',
      });
    });

    test('fromJson handles missing fields', () {
      final worktree = LinkedWorktree.fromJson({});

      check(worktree.worktreeRoot).equals('');
      check(worktree.branch).isNull();
    });

    test('equality and hashCode', () {
      const w1 = LinkedWorktree(
        worktreeRoot: '/path/to/worktree',
        branch: 'main',
      );
      const w2 = LinkedWorktree(
        worktreeRoot: '/path/to/worktree',
        branch: 'main',
      );
      const w3 = LinkedWorktree(
        worktreeRoot: '/different/path',
        branch: 'main',
      );

      check(w1).equals(w2);
      check(w1.hashCode).equals(w2.hashCode);
      check(w1).not((it) => it.equals(w3));
    });

    test('toString', () {
      const worktree = LinkedWorktree(
        worktreeRoot: '/path/to/worktree',
        branch: 'main',
      );

      check(worktree.toString()).contains('LinkedWorktree');
      check(worktree.toString()).contains('/path/to/worktree');
      check(worktree.toString()).contains('main');
    });
  });

  group('LinkedChat', () {
    test('toJson/fromJson round-trip', () {
      const chat = LinkedChat(
        chatId: 'chat-123',
        chatName: 'My Chat',
        worktreeRoot: '/path/to/worktree',
      );

      final json = chat.toJson();
      final restored = LinkedChat.fromJson(json);

      check(restored).equals(chat);
    });

    test('fromJson handles missing fields', () {
      final chat = LinkedChat.fromJson({});

      check(chat.chatId).equals('');
      check(chat.chatName).equals('');
      check(chat.worktreeRoot).equals('');
    });

    test('equality and hashCode', () {
      const c1 = LinkedChat(
        chatId: 'chat-123',
        chatName: 'My Chat',
        worktreeRoot: '/path/to/worktree',
      );
      const c2 = LinkedChat(
        chatId: 'chat-123',
        chatName: 'My Chat',
        worktreeRoot: '/path/to/worktree',
      );
      const c3 = LinkedChat(
        chatId: 'chat-456',
        chatName: 'Other Chat',
        worktreeRoot: '/path/to/worktree',
      );

      check(c1).equals(c2);
      check(c1.hashCode).equals(c2.hashCode);
      check(c1).not((it) => it.equals(c3));
    });

    test('toString', () {
      const chat = LinkedChat(
        chatId: 'chat-123',
        chatName: 'My Chat',
        worktreeRoot: '/path/to/worktree',
      );

      check(chat.toString()).contains('LinkedChat');
      check(chat.toString()).contains('chat-123');
      check(chat.toString()).contains('My Chat');
    });
  });

  group('TicketCostStats', () {
    test('toJson/fromJson round-trip', () {
      const stats = TicketCostStats(
        totalTokens: 1000,
        totalCost: 0.05,
        agentTimeMs: 30000,
        waitingTimeMs: 5000,
      );

      final json = stats.toJson();
      final restored = TicketCostStats.fromJson(json);

      check(restored).equals(stats);
    });

    test('fromJson handles missing fields', () {
      final stats = TicketCostStats.fromJson({});

      check(stats.totalTokens).equals(0);
      check(stats.totalCost).equals(0.0);
      check(stats.agentTimeMs).equals(0);
      check(stats.waitingTimeMs).equals(0);
    });

    test('equality and hashCode', () {
      const s1 = TicketCostStats(
        totalTokens: 1000,
        totalCost: 0.05,
        agentTimeMs: 30000,
        waitingTimeMs: 5000,
      );
      const s2 = TicketCostStats(
        totalTokens: 1000,
        totalCost: 0.05,
        agentTimeMs: 30000,
        waitingTimeMs: 5000,
      );
      const s3 = TicketCostStats(
        totalTokens: 2000,
        totalCost: 0.10,
        agentTimeMs: 60000,
        waitingTimeMs: 10000,
      );

      check(s1).equals(s2);
      check(s1.hashCode).equals(s2.hashCode);
      check(s1).not((it) => it.equals(s3));
    });

    test('toString', () {
      const stats = TicketCostStats(
        totalTokens: 1000,
        totalCost: 0.05,
        agentTimeMs: 30000,
        waitingTimeMs: 5000,
      );

      check(stats.toString()).contains('TicketCostStats');
      check(stats.toString()).contains('1000');
      check(stats.toString()).contains('0.05');
    });
  });

  group('TicketData', () {
    final now = DateTime.now();

    TicketData createTestTicket({
      int id = 1,
      String title = 'Test Ticket',
      String description = 'Test description',
      TicketStatus status = TicketStatus.ready,
      TicketKind kind = TicketKind.feature,
      TicketPriority priority = TicketPriority.medium,
      TicketEffort effort = TicketEffort.medium,
      String? category,
      Set<String> tags = const {},
      List<int> dependsOn = const [],
      List<LinkedWorktree> linkedWorktrees = const [],
      List<LinkedChat> linkedChats = const [],
      String? sourceConversationId,
      TicketCostStats? costStats,
    }) {
      return TicketData(
        id: id,
        title: title,
        description: description,
        status: status,
        kind: kind,
        priority: priority,
        effort: effort,
        category: category,
        tags: tags,
        dependsOn: dependsOn,
        linkedWorktrees: linkedWorktrees,
        linkedChats: linkedChats,
        sourceConversationId: sourceConversationId,
        costStats: costStats,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('displayId formats correctly', () {
      check(createTestTicket(id: 1).displayId).equals('TKT-001');
      check(createTestTicket(id: 42).displayId).equals('TKT-042');
      check(createTestTicket(id: 999).displayId).equals('TKT-999');
      check(createTestTicket(id: 1234).displayId).equals('TKT-1234');
    });

    test('isTerminal returns true for completed', () {
      final ticket = createTestTicket(status: TicketStatus.completed);
      check(ticket.isTerminal).isTrue();
    });

    test('isTerminal returns true for cancelled', () {
      final ticket = createTestTicket(status: TicketStatus.cancelled);
      check(ticket.isTerminal).isTrue();
    });

    test('isTerminal returns false for non-terminal states', () {
      for (final status in [
        TicketStatus.draft,
        TicketStatus.ready,
        TicketStatus.active,
        TicketStatus.blocked,
        TicketStatus.needsInput,
        TicketStatus.inReview,
      ]) {
        final ticket = createTestTicket(status: status);
        check(ticket.isTerminal).isFalse();
      }
    });

    test('copyWith updates fields', () {
      final original = createTestTicket();
      final updated = original.copyWith(
        title: 'Updated Title',
        status: TicketStatus.active,
      );

      check(updated.title).equals('Updated Title');
      check(updated.status).equals(TicketStatus.active);
      check(updated.id).equals(original.id);
      check(updated.description).equals(original.description);
    });

    test('copyWith clears category', () {
      final original = createTestTicket(category: 'Frontend');
      final updated = original.copyWith(clearCategory: true);

      check(updated.category).isNull();
    });

    test('copyWith clears sourceConversationId', () {
      final original = createTestTicket(sourceConversationId: 'conv-123');
      final updated = original.copyWith(clearSourceConversationId: true);

      check(updated.sourceConversationId).isNull();
    });

    test('copyWith clears costStats', () {
      final original = createTestTicket(
        costStats: const TicketCostStats(
          totalTokens: 1000,
          totalCost: 0.05,
          agentTimeMs: 30000,
          waitingTimeMs: 5000,
        ),
      );
      final updated = original.copyWith(clearCostStats: true);

      check(updated.costStats).isNull();
    });

    test('toJson/fromJson round-trip with all fields', () {
      final ticket = createTestTicket(
        id: 42,
        title: 'Test Ticket',
        description: 'Description',
        status: TicketStatus.active,
        kind: TicketKind.bugfix,
        priority: TicketPriority.high,
        effort: TicketEffort.small,
        category: 'Backend',
        tags: {'bug', 'urgent'},
        dependsOn: [1, 2, 3],
        linkedWorktrees: [
          const LinkedWorktree(
            worktreeRoot: '/path/to/wt1',
            branch: 'main',
          ),
        ],
        linkedChats: [
          const LinkedChat(
            chatId: 'chat-1',
            chatName: 'Chat 1',
            worktreeRoot: '/path/to/wt1',
          ),
        ],
        sourceConversationId: 'conv-123',
        costStats: const TicketCostStats(
          totalTokens: 1000,
          totalCost: 0.05,
          agentTimeMs: 30000,
          waitingTimeMs: 5000,
        ),
      );

      final json = ticket.toJson();
      final restored = TicketData.fromJson(json);

      // Check all fields individually since DateTime serialization may lose microseconds
      check(restored.id).equals(ticket.id);
      check(restored.title).equals(ticket.title);
      check(restored.description).equals(ticket.description);
      check(restored.status).equals(ticket.status);
      check(restored.kind).equals(ticket.kind);
      check(restored.priority).equals(ticket.priority);
      check(restored.effort).equals(ticket.effort);
      check(restored.category).equals(ticket.category);
      check(restored.tags).deepEquals(ticket.tags);
      check(restored.dependsOn).deepEquals(ticket.dependsOn);
      check(restored.linkedWorktrees).deepEquals(ticket.linkedWorktrees);
      check(restored.linkedChats).deepEquals(ticket.linkedChats);
      check(restored.sourceConversationId).equals(ticket.sourceConversationId);
      check(restored.costStats).equals(ticket.costStats);
      // DateTimes may differ by microseconds after serialization
      check(restored.createdAt.toIso8601String())
          .equals(ticket.createdAt.toUtc().toIso8601String());
      check(restored.updatedAt.toIso8601String())
          .equals(ticket.updatedAt.toUtc().toIso8601String());
    });

    test('toJson/fromJson round-trip with minimal fields', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();
      final restored = TicketData.fromJson(json);

      check(restored.id).equals(ticket.id);
      check(restored.title).equals(ticket.title);
      check(restored.description).equals(ticket.description);
      check(restored.status).equals(ticket.status);
      check(restored.kind).equals(ticket.kind);
      check(restored.priority).equals(ticket.priority);
      check(restored.effort).equals(ticket.effort);
    });

    test('toJson excludes empty collections', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();

      check(json).not((it) => it.containsKey('tags'));
      check(json).not((it) => it.containsKey('dependsOn'));
      check(json).not((it) => it.containsKey('linkedWorktrees'));
      check(json).not((it) => it.containsKey('linkedChats'));
    });

    test('toJson excludes null optional fields', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();

      check(json).not((it) => it.containsKey('category'));
      check(json).not((it) => it.containsKey('sourceConversationId'));
      check(json).not((it) => it.containsKey('costStats'));
    });

    test('toJson includes non-empty collections', () {
      final ticket = createTestTicket(
        tags: {'tag1', 'tag2'},
        dependsOn: [1, 2],
      );

      final json = ticket.toJson();

      check(json).has((it) => it['tags'], 'tags')
          .isA<List>()
          .length.equals(2);
      check(json).has((it) => it['dependsOn'], 'dependsOn')
          .isA<List>()
          .length.equals(2);
    });

    test('toJson serializes dates as UTC ISO8601', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();

      check(json['createdAt']).isA<String>();
      check(json['updatedAt']).isA<String>();
      // Verify parseable
      DateTime.parse(json['createdAt'] as String);
      DateTime.parse(json['updatedAt'] as String);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 1,
        'title': 'Test',
        'description': 'Desc',
        'status': 'ready',
        'kind': 'feature',
        'priority': 'medium',
        'effort': 'medium',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final ticket = TicketData.fromJson(json);

      check(ticket.category).isNull();
      check(ticket.tags).isEmpty();
      check(ticket.dependsOn).isEmpty();
      check(ticket.linkedWorktrees).isEmpty();
      check(ticket.linkedChats).isEmpty();
      check(ticket.sourceConversationId).isNull();
      check(ticket.costStats).isNull();
    });

    test('fromJson uses defaults for missing required fields', () {
      final ticket = TicketData.fromJson({});

      check(ticket.id).equals(0);
      check(ticket.title).equals('');
      check(ticket.description).equals('');
      check(ticket.status).equals(TicketStatus.draft);
      check(ticket.kind).equals(TicketKind.feature);
      check(ticket.priority).equals(TicketPriority.medium);
      check(ticket.effort).equals(TicketEffort.medium);
    });

    test('equality and hashCode', () {
      final t1 = createTestTicket(id: 1, title: 'Test');
      final t2 = createTestTicket(id: 1, title: 'Test');
      final t3 = createTestTicket(id: 2, title: 'Different');

      check(t1).equals(t2);
      check(t1.hashCode).equals(t2.hashCode);
      check(t1).not((it) => it.equals(t3));
    });

    test('equality handles Set comparison', () {
      final t1 = createTestTicket(tags: {'a', 'b'});
      final t2 = createTestTicket(tags: {'b', 'a'});
      final t3 = createTestTicket(tags: {'a', 'c'});

      check(t1).equals(t2);
      check(t1).not((it) => it.equals(t3));
    });

    test('toString', () {
      final ticket = createTestTicket(
        id: 42,
        title: 'Test Ticket',
        status: TicketStatus.active,
      );

      final str = ticket.toString();
      check(str).contains('TicketData');
      check(str).contains('42');
      check(str).contains('Test Ticket');
      check(str).contains('active');
    });
  });
}
