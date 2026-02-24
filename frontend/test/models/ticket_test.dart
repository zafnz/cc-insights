import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/models/ticket.dart';

void main() {
  group('AuthorType enum', () {
    test('has correct jsonValues', () {
      check(AuthorType.user.jsonValue).equals('user');
      check(AuthorType.agent.jsonValue).equals('agent');
    });

    test('fromJson round-trips', () {
      for (final type in AuthorType.values) {
        check(AuthorType.fromJson(type.jsonValue)).equals(type);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => AuthorType.fromJson('invalid')).throws<ArgumentError>();
    });
  });

  group('ActivityEventType enum', () {
    test('has all expected values', () {
      check(ActivityEventType.values.length).equals(12);
    });

    test('has correct jsonValues', () {
      check(ActivityEventType.tagAdded.jsonValue).equals('tagAdded');
      check(ActivityEventType.tagRemoved.jsonValue).equals('tagRemoved');
      check(ActivityEventType.worktreeLinked.jsonValue)
          .equals('worktreeLinked');
      check(ActivityEventType.worktreeUnlinked.jsonValue)
          .equals('worktreeUnlinked');
      check(ActivityEventType.chatLinked.jsonValue).equals('chatLinked');
      check(ActivityEventType.chatUnlinked.jsonValue).equals('chatUnlinked');
      check(ActivityEventType.dependencyAdded.jsonValue)
          .equals('dependencyAdded');
      check(ActivityEventType.dependencyRemoved.jsonValue)
          .equals('dependencyRemoved');
      check(ActivityEventType.closed.jsonValue).equals('closed');
      check(ActivityEventType.reopened.jsonValue).equals('reopened');
      check(ActivityEventType.titleEdited.jsonValue).equals('titleEdited');
      check(ActivityEventType.bodyEdited.jsonValue).equals('bodyEdited');
    });

    test('fromJson round-trips', () {
      for (final type in ActivityEventType.values) {
        check(ActivityEventType.fromJson(type.jsonValue)).equals(type);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => ActivityEventType.fromJson('invalid'))
          .throws<ArgumentError>();
    });
  });

  group('TicketSortOrder enum', () {
    test('has correct labels', () {
      check(TicketSortOrder.newest.label).equals('Newest');
      check(TicketSortOrder.oldest.label).equals('Oldest');
      check(TicketSortOrder.recentlyUpdated.label).equals('Recently updated');
    });

    test('has correct jsonValues', () {
      check(TicketSortOrder.newest.jsonValue).equals('newest');
      check(TicketSortOrder.oldest.jsonValue).equals('oldest');
      check(TicketSortOrder.recentlyUpdated.jsonValue)
          .equals('recentlyUpdated');
    });

    test('fromJson round-trips', () {
      for (final order in TicketSortOrder.values) {
        check(TicketSortOrder.fromJson(order.jsonValue)).equals(order);
      }
    });

    test('fromJson throws on invalid value', () {
      check(() => TicketSortOrder.fromJson('invalid')).throws<ArgumentError>();
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
      check(() => TicketViewMode.fromJson('invalid')).throws<ArgumentError>();
    });
  });

  group('ActivityEvent', () {
    final timestamp = DateTime.utc(2025, 6, 22, 10, 0, 0);

    test('toJson/fromJson round-trip', () {
      final event = ActivityEvent(
        id: 'evt-001',
        type: ActivityEventType.tagAdded,
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: timestamp,
        data: {'tag': 'feature'},
      );

      final json = event.toJson();
      final restored = ActivityEvent.fromJson(json);

      check(restored.id).equals(event.id);
      check(restored.type).equals(event.type);
      check(restored.actor).equals(event.actor);
      check(restored.actorType).equals(event.actorType);
      check(restored.timestamp.toIso8601String())
          .equals(event.timestamp.toIso8601String());
      check(restored.data).deepEquals(event.data);
    });

    test('toJson/fromJson round-trip with empty data', () {
      final event = ActivityEvent(
        id: 'evt-002',
        type: ActivityEventType.closed,
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: timestamp,
      );

      final json = event.toJson();
      check(json).not((it) => it.containsKey('data'));

      final restored = ActivityEvent.fromJson(json);
      check(restored.data).isEmpty();
    });

    test('toJson includes non-empty data', () {
      final event = ActivityEvent(
        id: 'evt-003',
        type: ActivityEventType.dependencyAdded,
        actor: 'agent auth-refactor',
        actorType: AuthorType.agent,
        timestamp: timestamp,
        data: {'ticketId': 5},
      );

      final json = event.toJson();
      check(json).containsKey('data');
      check(json['data']).isA<Map>().deepEquals({'ticketId': 5});
    });

    test('copyWith updates fields', () {
      final original = ActivityEvent(
        id: 'evt-001',
        type: ActivityEventType.tagAdded,
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: timestamp,
        data: {'tag': 'feature'},
      );

      final updated = original.copyWith(
        type: ActivityEventType.tagRemoved,
        data: {'tag': 'bug'},
      );

      check(updated.id).equals('evt-001');
      check(updated.type).equals(ActivityEventType.tagRemoved);
      check(updated.actor).equals('zaf');
      check(updated.data).deepEquals({'tag': 'bug'});
    });

    test('equality and hashCode', () {
      final e1 = ActivityEvent(
        id: 'evt-001',
        type: ActivityEventType.closed,
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: timestamp,
      );
      final e2 = ActivityEvent(
        id: 'evt-001',
        type: ActivityEventType.closed,
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: timestamp,
      );
      final e3 = ActivityEvent(
        id: 'evt-002',
        type: ActivityEventType.reopened,
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: timestamp,
      );

      check(e1).equals(e2);
      check(e1.hashCode).equals(e2.hashCode);
      check(e1).not((it) => it.equals(e3));
    });

    test('toString', () {
      final event = ActivityEvent(
        id: 'evt-001',
        type: ActivityEventType.tagAdded,
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: timestamp,
      );

      check(event.toString()).contains('ActivityEvent');
      check(event.toString()).contains('evt-001');
      check(event.toString()).contains('tagAdded');
      check(event.toString()).contains('zaf');
    });
  });

  group('TicketImage', () {
    final createdAt = DateTime.utc(2025, 6, 22, 10, 0, 0);

    test('toJson/fromJson round-trip', () {
      final image = TicketImage(
        id: 'img-001',
        fileName: 'screenshot.png',
        relativePath: 'ticket-images/1/screenshot.png',
        mimeType: 'image/png',
        createdAt: createdAt,
      );

      final json = image.toJson();
      final restored = TicketImage.fromJson(json);

      check(restored.id).equals(image.id);
      check(restored.fileName).equals(image.fileName);
      check(restored.relativePath).equals(image.relativePath);
      check(restored.mimeType).equals(image.mimeType);
      check(restored.createdAt.toIso8601String())
          .equals(image.createdAt.toIso8601String());
    });

    test('fromJson handles missing fields', () {
      final image = TicketImage.fromJson({});

      check(image.id).equals('');
      check(image.fileName).equals('');
      check(image.relativePath).equals('');
      check(image.mimeType).equals('');
    });

    test('equality and hashCode', () {
      final i1 = TicketImage(
        id: 'img-001',
        fileName: 'screenshot.png',
        relativePath: 'ticket-images/1/screenshot.png',
        mimeType: 'image/png',
        createdAt: createdAt,
      );
      final i2 = TicketImage(
        id: 'img-001',
        fileName: 'screenshot.png',
        relativePath: 'ticket-images/1/screenshot.png',
        mimeType: 'image/png',
        createdAt: createdAt,
      );
      final i3 = TicketImage(
        id: 'img-002',
        fileName: 'other.jpg',
        relativePath: 'ticket-images/1/other.jpg',
        mimeType: 'image/jpeg',
        createdAt: createdAt,
      );

      check(i1).equals(i2);
      check(i1.hashCode).equals(i2.hashCode);
      check(i1).not((it) => it.equals(i3));
    });

    test('toString', () {
      final image = TicketImage(
        id: 'img-001',
        fileName: 'screenshot.png',
        relativePath: 'ticket-images/1/screenshot.png',
        mimeType: 'image/png',
        createdAt: createdAt,
      );

      check(image.toString()).contains('TicketImage');
      check(image.toString()).contains('img-001');
      check(image.toString()).contains('screenshot.png');
    });
  });

  group('TicketComment', () {
    final createdAt = DateTime.utc(2025, 6, 22, 10, 0, 0);
    final updatedAt = DateTime.utc(2025, 6, 23, 15, 30, 0);

    test('toJson/fromJson round-trip with all fields', () {
      final comment = TicketComment(
        id: 'cmt-001',
        text: 'This is a comment',
        author: 'zaf',
        authorType: AuthorType.user,
        images: [
          TicketImage(
            id: 'img-001',
            fileName: 'screenshot.png',
            relativePath: 'ticket-images/1/screenshot.png',
            mimeType: 'image/png',
            createdAt: createdAt,
          ),
        ],
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final json = comment.toJson();
      final restored = TicketComment.fromJson(json);

      check(restored.id).equals(comment.id);
      check(restored.text).equals(comment.text);
      check(restored.author).equals(comment.author);
      check(restored.authorType).equals(comment.authorType);
      check(restored.images.length).equals(1);
      check(restored.images.first.id).equals('img-001');
      check(restored.createdAt.toIso8601String())
          .equals(comment.createdAt.toIso8601String());
      check(restored.updatedAt!.toIso8601String())
          .equals(comment.updatedAt!.toIso8601String());
    });

    test('toJson/fromJson round-trip with minimal fields', () {
      final comment = TicketComment(
        id: 'cmt-002',
        text: 'Simple comment',
        author: 'agent bot',
        authorType: AuthorType.agent,
        createdAt: createdAt,
      );

      final json = comment.toJson();
      check(json).not((it) => it.containsKey('images'));
      check(json).not((it) => it.containsKey('updatedAt'));

      final restored = TicketComment.fromJson(json);
      check(restored.images).isEmpty();
      check(restored.updatedAt).isNull();
    });

    test('copyWith updates fields', () {
      final original = TicketComment(
        id: 'cmt-001',
        text: 'Original',
        author: 'zaf',
        authorType: AuthorType.user,
        createdAt: createdAt,
      );

      final updated = original.copyWith(
        text: 'Edited',
        updatedAt: updatedAt,
      );

      check(updated.id).equals('cmt-001');
      check(updated.text).equals('Edited');
      check(updated.updatedAt).equals(updatedAt);
    });

    test('copyWith clearUpdatedAt', () {
      final original = TicketComment(
        id: 'cmt-001',
        text: 'Comment',
        author: 'zaf',
        authorType: AuthorType.user,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final cleared = original.copyWith(clearUpdatedAt: true);
      check(cleared.updatedAt).isNull();
    });

    test('equality and hashCode', () {
      final c1 = TicketComment(
        id: 'cmt-001',
        text: 'Comment',
        author: 'zaf',
        authorType: AuthorType.user,
        createdAt: createdAt,
      );
      final c2 = TicketComment(
        id: 'cmt-001',
        text: 'Comment',
        author: 'zaf',
        authorType: AuthorType.user,
        createdAt: createdAt,
      );
      final c3 = TicketComment(
        id: 'cmt-002',
        text: 'Different',
        author: 'agent',
        authorType: AuthorType.agent,
        createdAt: createdAt,
      );

      check(c1).equals(c2);
      check(c1.hashCode).equals(c2.hashCode);
      check(c1).not((it) => it.equals(c3));
    });

    test('toString', () {
      final comment = TicketComment(
        id: 'cmt-001',
        text: 'Comment',
        author: 'zaf',
        authorType: AuthorType.user,
        createdAt: createdAt,
      );

      check(comment.toString()).contains('TicketComment');
      check(comment.toString()).contains('cmt-001');
      check(comment.toString()).contains('zaf');
    });
  });

  group('TagDefinition', () {
    test('normalizes name to lowercase', () {
      final tag = TagDefinition(name: 'Feature');
      check(tag.name).equals('feature');
    });

    test('toJson/fromJson round-trip', () {
      final tag = TagDefinition(name: 'bug', color: '#ef5350');

      final json = tag.toJson();
      final restored = TagDefinition.fromJson(json);

      check(restored).equals(tag);
    });

    test('toJson/fromJson round-trip with null color', () {
      final tag = TagDefinition(name: 'feature');

      final json = tag.toJson();
      check(json).not((it) => it.containsKey('color'));

      final restored = TagDefinition.fromJson(json);
      check(restored).equals(tag);
      check(restored.color).isNull();
    });

    test('fromJson handles missing fields', () {
      final tag = TagDefinition.fromJson({});
      check(tag.name).equals('');
      check(tag.color).isNull();
    });

    test('equality and hashCode', () {
      final t1 = TagDefinition(name: 'bug', color: '#ef5350');
      final t2 = TagDefinition(name: 'BUG', color: '#ef5350');
      final t3 = TagDefinition(name: 'feature');

      check(t1).equals(t2);
      check(t1.hashCode).equals(t2.hashCode);
      check(t1).not((it) => it.equals(t3));
    });

    test('toString', () {
      final tag = TagDefinition(name: 'bug', color: '#ef5350');
      check(tag.toString()).contains('TagDefinition');
      check(tag.toString()).contains('bug');
      check(tag.toString()).contains('#ef5350');
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

  group('TicketData', () {
    final now = DateTime.utc(2025, 6, 22, 10, 0, 0);
    final later = DateTime.utc(2025, 6, 23, 15, 30, 0);

    TicketData createTestTicket({
      int id = 1,
      String title = 'Test Ticket',
      String body = 'Test body',
      String author = 'zaf',
      bool isOpen = true,
      Set<String> tags = const {},
      List<int> dependsOn = const [],
      List<LinkedWorktree> linkedWorktrees = const [],
      List<LinkedChat> linkedChats = const [],
      List<TicketComment> comments = const [],
      List<ActivityEvent> activityLog = const [],
      List<TicketImage> bodyImages = const [],
      String? sourceConversationId,
      DateTime? closedAt,
    }) {
      return TicketData(
        id: id,
        title: title,
        body: body,
        author: author,
        isOpen: isOpen,
        tags: tags,
        dependsOn: dependsOn,
        linkedWorktrees: linkedWorktrees,
        linkedChats: linkedChats,
        comments: comments,
        activityLog: activityLog,
        bodyImages: bodyImages,
        sourceConversationId: sourceConversationId,
        createdAt: now,
        updatedAt: now,
        closedAt: closedAt,
      );
    }

    test('displayId formats correctly', () {
      check(createTestTicket(id: 1).displayId).equals('#1');
      check(createTestTicket(id: 42).displayId).equals('#42');
      check(createTestTicket(id: 999).displayId).equals('#999');
    });

    test('tags are normalized to lowercase on construction', () {
      final ticket = createTestTicket(tags: {'Feature', 'BUG', 'ToDo'});
      check(ticket.tags).deepEquals({'feature', 'bug', 'todo'});
    });

    test('copyWith updates fields', () {
      final original = createTestTicket();
      final updated = original.copyWith(
        title: 'Updated Title',
        isOpen: false,
      );

      check(updated.title).equals('Updated Title');
      check(updated.isOpen).isFalse();
      check(updated.id).equals(original.id);
      check(updated.body).equals(original.body);
    });

    test('copyWith clears sourceConversationId', () {
      final original = createTestTicket(sourceConversationId: 'conv-123');
      final updated = original.copyWith(clearSourceConversationId: true);

      check(updated.sourceConversationId).isNull();
    });

    test('copyWith clears closedAt', () {
      final original = createTestTicket(closedAt: later);
      final updated = original.copyWith(clearClosedAt: true);

      check(updated.closedAt).isNull();
    });

    test('copyWith normalizes tags to lowercase', () {
      final original = createTestTicket();
      final updated = original.copyWith(tags: {'Feature', 'BUG'});

      check(updated.tags).deepEquals({'feature', 'bug'});
    });

    test('toJson/fromJson round-trip with all fields', () {
      final ticket = createTestTicket(
        id: 42,
        title: 'Test Ticket',
        body: 'Full description',
        author: 'zaf',
        isOpen: false,
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
        comments: [
          TicketComment(
            id: 'cmt-001',
            text: 'A comment',
            author: 'zaf',
            authorType: AuthorType.user,
            createdAt: now,
          ),
        ],
        activityLog: [
          ActivityEvent(
            id: 'evt-001',
            type: ActivityEventType.closed,
            actor: 'zaf',
            actorType: AuthorType.user,
            timestamp: later,
          ),
        ],
        bodyImages: [
          TicketImage(
            id: 'img-001',
            fileName: 'screenshot.png',
            relativePath: 'ticket-images/42/screenshot.png',
            mimeType: 'image/png',
            createdAt: now,
          ),
        ],
        sourceConversationId: 'conv-123',
        closedAt: later,
      );

      final json = ticket.toJson();
      final restored = TicketData.fromJson(json);

      check(restored.id).equals(ticket.id);
      check(restored.title).equals(ticket.title);
      check(restored.body).equals(ticket.body);
      check(restored.author).equals(ticket.author);
      check(restored.isOpen).equals(ticket.isOpen);
      check(restored.tags).deepEquals(ticket.tags);
      check(restored.dependsOn).deepEquals(ticket.dependsOn);
      check(restored.linkedWorktrees).deepEquals(ticket.linkedWorktrees);
      check(restored.linkedChats).deepEquals(ticket.linkedChats);
      check(restored.comments.length).equals(1);
      check(restored.comments.first.id).equals('cmt-001');
      check(restored.activityLog.length).equals(1);
      check(restored.activityLog.first.id).equals('evt-001');
      check(restored.bodyImages.length).equals(1);
      check(restored.bodyImages.first.id).equals('img-001');
      check(restored.sourceConversationId).equals(ticket.sourceConversationId);
      check(restored.createdAt.toIso8601String())
          .equals(ticket.createdAt.toIso8601String());
      check(restored.updatedAt.toIso8601String())
          .equals(ticket.updatedAt.toIso8601String());
      check(restored.closedAt!.toIso8601String())
          .equals(ticket.closedAt!.toIso8601String());
    });

    test('toJson/fromJson round-trip with minimal fields', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();
      final restored = TicketData.fromJson(json);

      check(restored.id).equals(ticket.id);
      check(restored.title).equals(ticket.title);
      check(restored.body).equals(ticket.body);
      check(restored.author).equals(ticket.author);
      check(restored.isOpen).equals(ticket.isOpen);
    });

    test('toJson excludes empty collections', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();

      check(json).not((it) => it.containsKey('tags'));
      check(json).not((it) => it.containsKey('dependsOn'));
      check(json).not((it) => it.containsKey('linkedWorktrees'));
      check(json).not((it) => it.containsKey('linkedChats'));
      check(json).not((it) => it.containsKey('comments'));
      check(json).not((it) => it.containsKey('activityLog'));
      check(json).not((it) => it.containsKey('bodyImages'));
    });

    test('toJson excludes null optional fields', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();

      check(json).not((it) => it.containsKey('sourceConversationId'));
      check(json).not((it) => it.containsKey('closedAt'));
    });

    test('toJson includes non-empty collections', () {
      final ticket = createTestTicket(
        tags: {'tag1', 'tag2'},
        dependsOn: [1, 2],
      );

      final json = ticket.toJson();

      check(json)
          .has((it) => it['tags'], 'tags')
          .isA<List>()
          .length
          .equals(2);
      check(json)
          .has((it) => it['dependsOn'], 'dependsOn')
          .isA<List>()
          .length
          .equals(2);
    });

    test('toJson serializes dates as UTC ISO8601', () {
      final ticket = createTestTicket();

      final json = ticket.toJson();

      check(json['createdAt']).isA<String>();
      check(json['updatedAt']).isA<String>();
      DateTime.parse(json['createdAt'] as String);
      DateTime.parse(json['updatedAt'] as String);
    });

    test('toJson always includes isOpen and author', () {
      final ticket = createTestTicket();
      final json = ticket.toJson();

      check(json).containsKey('isOpen');
      check(json).containsKey('author');
      check(json['isOpen']).equals(true);
      check(json['author']).equals('zaf');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 1,
        'title': 'Test',
        'body': 'Desc',
        'author': 'zaf',
        'isOpen': true,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final ticket = TicketData.fromJson(json);

      check(ticket.tags).isEmpty();
      check(ticket.dependsOn).isEmpty();
      check(ticket.linkedWorktrees).isEmpty();
      check(ticket.linkedChats).isEmpty();
      check(ticket.comments).isEmpty();
      check(ticket.activityLog).isEmpty();
      check(ticket.bodyImages).isEmpty();
      check(ticket.sourceConversationId).isNull();
      check(ticket.closedAt).isNull();
    });

    test('fromJson uses defaults for missing required fields', () {
      final ticket = TicketData.fromJson({});

      check(ticket.id).equals(0);
      check(ticket.title).equals('');
      check(ticket.body).equals('');
      check(ticket.author).equals('');
      check(ticket.isOpen).isTrue();
    });

    test('fromJson normalizes tags to lowercase', () {
      final ticket = TicketData.fromJson({
        'id': 1,
        'title': 'Test',
        'body': '',
        'author': 'zaf',
        'isOpen': true,
        'tags': ['Feature', 'BUG', 'ToDo'],
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });

      check(ticket.tags).deepEquals({'feature', 'bug', 'todo'});
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
        isOpen: false,
      );

      final str = ticket.toString();
      check(str).contains('TicketData');
      check(str).contains('42');
      check(str).contains('Test Ticket');
      check(str).contains('isOpen: false');
    });
  });
}
