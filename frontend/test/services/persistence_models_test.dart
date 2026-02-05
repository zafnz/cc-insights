import 'dart:convert';

import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/persistence_models.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContextInfo', () {
    test('empty() creates instance with defaults', () {
      const context = ContextInfo.empty();

      check(context.currentTokens).equals(0);
      check(context.maxTokens).equals(200000);
    });

    test('copyWith preserves unchanged fields', () {
      const original = ContextInfo(currentTokens: 5000, maxTokens: 100000);

      final modified = original.copyWith(currentTokens: 10000);

      check(modified.currentTokens).equals(10000);
      check(modified.maxTokens).equals(100000);
    });

    test('toJson produces correct structure', () {
      const context = ContextInfo(currentTokens: 50000, maxTokens: 200000);

      final json = context.toJson();

      check(json['currentTokens']).equals(50000);
      check(json['maxTokens']).equals(200000);
    });

    test('fromJson restores correctly', () {
      final json = {'currentTokens': 25000, 'maxTokens': 128000};

      final context = ContextInfo.fromJson(json);

      check(context.currentTokens).equals(25000);
      check(context.maxTokens).equals(128000);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final context = ContextInfo.fromJson(json);

      check(context.currentTokens).equals(0);
      check(context.maxTokens).equals(200000);
    });

    test('round-trip preserves data', () {
      const original = ContextInfo(currentTokens: 75000, maxTokens: 150000);

      final json = jsonEncode(original.toJson());
      final restored = ContextInfo.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored).equals(original);
    });

    test('equality works correctly', () {
      const a = ContextInfo(currentTokens: 1000, maxTokens: 2000);
      const b = ContextInfo(currentTokens: 1000, maxTokens: 2000);
      const c = ContextInfo(currentTokens: 1001, maxTokens: 2000);

      check(a == b).isTrue();
      check(a.hashCode).equals(b.hashCode);
      check(a == c).isFalse();
    });
  });

  group('ChatMeta', () {
    test('create() generates defaults', () {
      final meta = ChatMeta.create();

      check(meta.model).equals('opus');
      check(meta.backendType).equals('direct');
      check(meta.permissionMode).equals('default');
      check(meta.context.currentTokens).equals(0);
      check(meta.usage.inputTokens).equals(0);
    });

    test('create() accepts custom model and permission', () {
      final meta = ChatMeta.create(
        model: 'sonnet',
        permissionMode: 'acceptEdits',
        backendType: 'direct',
      );

      check(meta.model).equals('sonnet');
      check(meta.backendType).equals('direct');
      check(meta.permissionMode).equals('acceptEdits');
    });

    test('copyWith preserves unchanged fields', () {
      final original = ChatMeta.create(model: 'sonnet');

      final modified = original.copyWith(model: 'opus');

      check(modified.model).equals('opus');
      check(modified.backendType).equals('direct');
      check(modified.permissionMode).equals('default');
      check(modified.createdAt).equals(original.createdAt);
    });

    test('toJson produces correct structure', () {
      final meta = ChatMeta(
        model: 'sonnet',
        backendType: 'direct',
        hasStarted: false,
        permissionMode: 'acceptEdits',
        createdAt: DateTime.utc(2025, 1, 27, 10, 0, 0),
        lastActiveAt: DateTime.utc(2025, 1, 27, 14, 30, 0),
        context: const ContextInfo(currentTokens: 50000, maxTokens: 200000),
        usage: const UsageInfo(
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
        ),
      );

      final json = meta.toJson();

      check(json['model']).equals('sonnet');
      check(json['backendType']).equals('direct');
      check(json['permissionMode']).equals('acceptEdits');
      check(json['createdAt']).equals('2025-01-27T10:00:00.000Z');
      check(json['lastActiveAt']).equals('2025-01-27T14:30:00.000Z');
      check((json['context'] as Map)['currentTokens']).equals(50000);
      check((json['usage'] as Map)['inputTokens']).equals(1000);
    });

    test('fromJson restores correctly', () {
      final json = {
        'model': 'opus',
        'backendType': 'direct',
        'permissionMode': 'bypassPermissions',
        'createdAt': '2025-01-27T10:00:00.000Z',
        'lastActiveAt': '2025-01-27T14:30:00.000Z',
        'context': {'currentTokens': 75000, 'maxTokens': 200000},
        'usage': {
          'inputTokens': 2000,
          'outputTokens': 1000,
          'cacheReadTokens': 500,
          'cacheCreationTokens': 200,
          'costUsd': 0.15,
        },
      };

      final meta = ChatMeta.fromJson(json);

      check(meta.model).equals('opus');
      check(meta.backendType).equals('direct');
      check(meta.permissionMode).equals('bypassPermissions');
      check(meta.createdAt).equals(DateTime.utc(2025, 1, 27, 10, 0, 0));
      check(meta.lastActiveAt).equals(DateTime.utc(2025, 1, 27, 14, 30, 0));
      check(meta.context.currentTokens).equals(75000);
      check(meta.usage.inputTokens).equals(2000);
      check(meta.usage.costUsd).equals(0.15);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final meta = ChatMeta.fromJson(json);

      check(meta.model).equals('opus');
      check(meta.backendType).equals('direct');
      check(meta.permissionMode).equals('default');
      check(meta.context.currentTokens).equals(0);
      check(meta.usage.inputTokens).equals(0);
    });

    test('round-trip preserves data', () {
      final original = ChatMeta(
        model: 'sonnet',
        backendType: 'direct',
        hasStarted: false,
        permissionMode: 'plan',
        createdAt: DateTime.utc(2025, 1, 27, 10, 0, 0),
        lastActiveAt: DateTime.utc(2025, 1, 27, 14, 30, 0),
        context: const ContextInfo(currentTokens: 50000, maxTokens: 200000),
        usage: const UsageInfo(
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
        ),
      );

      final json = jsonEncode(original.toJson());
      final restored = ChatMeta.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored.model).equals(original.model);
      check(restored.permissionMode).equals(original.permissionMode);
      check(restored.createdAt).equals(original.createdAt);
      check(restored.lastActiveAt).equals(original.lastActiveAt);
      check(restored.context).equals(original.context);
      check(restored.usage).equals(original.usage);
    });
  });

  group('ChatReference', () {
    test('creates with required fields', () {
      const ref = ChatReference(name: 'Test Chat', chatId: 'chat-123');

      check(ref.name).equals('Test Chat');
      check(ref.chatId).equals('chat-123');
      check(ref.lastSessionId).isNull();
    });

    test('creates with optional lastSessionId', () {
      const ref = ChatReference(
        name: 'Test Chat',
        chatId: 'chat-123',
        lastSessionId: 'session-xyz',
      );

      check(ref.lastSessionId).equals('session-xyz');
    });

    test('copyWith preserves unchanged fields', () {
      const original = ChatReference(
        name: 'Original',
        chatId: 'chat-123',
        lastSessionId: 'session-abc',
      );

      final modified = original.copyWith(name: 'Modified');

      check(modified.name).equals('Modified');
      check(modified.chatId).equals('chat-123');
      check(modified.lastSessionId).equals('session-abc');
    });

    test('toJson produces correct structure', () {
      const ref = ChatReference(
        name: 'Test Chat',
        chatId: 'chat-123',
        lastSessionId: 'session-xyz',
      );

      final json = ref.toJson();

      check(json['name']).equals('Test Chat');
      check(json['chatId']).equals('chat-123');
      check(json['lastSessionId']).equals('session-xyz');
    });

    test('toJson includes null lastSessionId', () {
      const ref = ChatReference(name: 'Test', chatId: 'chat-456');

      final json = ref.toJson();

      check(json.containsKey('lastSessionId')).isTrue();
      check(json['lastSessionId']).isNull();
    });

    test('fromJson restores correctly', () {
      final json = {
        'name': 'Restored Chat',
        'chatId': 'chat-789',
        'lastSessionId': 'session-123',
      };

      final ref = ChatReference.fromJson(json);

      check(ref.name).equals('Restored Chat');
      check(ref.chatId).equals('chat-789');
      check(ref.lastSessionId).equals('session-123');
    });

    test('fromJson handles missing name', () {
      final json = {'chatId': 'chat-789'};

      final ref = ChatReference.fromJson(json);

      check(ref.name).equals('Untitled Chat');
    });

    test('fromJson handles null lastSessionId', () {
      final json = {
        'name': 'Test',
        'chatId': 'chat-789',
        'lastSessionId': null,
      };

      final ref = ChatReference.fromJson(json);

      check(ref.lastSessionId).isNull();
    });

    test('round-trip preserves data', () {
      const original = ChatReference(
        name: 'Round Trip Chat',
        chatId: 'chat-roundtrip',
        lastSessionId: 'session-rt',
      );

      final json = jsonEncode(original.toJson());
      final restored = ChatReference.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored).equals(original);
    });

    test('equality works correctly', () {
      const a = ChatReference(name: 'A', chatId: '1');
      const b = ChatReference(name: 'A', chatId: '1');
      const c = ChatReference(name: 'A', chatId: '2');

      check(a == b).isTrue();
      check(a.hashCode).equals(b.hashCode);
      check(a == c).isFalse();
    });
  });

  group('WorktreeInfo', () {
    test('primary() creates primary worktree', () {
      const worktree = WorktreeInfo.primary(name: 'main');

      check(worktree.type).equals('primary');
      check(worktree.name).equals('main');
      check(worktree.isPrimary).isTrue();
      check(worktree.isLinked).isFalse();
      check(worktree.chats).isEmpty();
    });

    test('linked() creates linked worktree', () {
      const worktree = WorktreeInfo.linked(name: 'feature-branch');

      check(worktree.type).equals('linked');
      check(worktree.name).equals('feature-branch');
      check(worktree.isPrimary).isFalse();
      check(worktree.isLinked).isTrue();
    });

    test('creates with chats list', () {
      const worktree = WorktreeInfo.primary(
        name: 'main',
        chats: [
          ChatReference(name: 'Chat 1', chatId: 'chat-1'),
          ChatReference(name: 'Chat 2', chatId: 'chat-2'),
        ],
      );

      check(worktree.chats.length).equals(2);
      check(worktree.chats[0].name).equals('Chat 1');
    });

    test('copyWith preserves unchanged fields', () {
      const original = WorktreeInfo.primary(
        name: 'main',
        chats: [ChatReference(name: 'Chat', chatId: 'chat-1')],
      );

      final modified = original.copyWith(name: 'development');

      check(modified.name).equals('development');
      check(modified.type).equals('primary');
      check(modified.chats.length).equals(1);
    });

    test('toJson produces correct structure', () {
      const worktree = WorktreeInfo.linked(
        name: 'feature',
        chats: [ChatReference(name: 'Chat', chatId: 'chat-1')],
      );

      final json = worktree.toJson();

      check(json['type']).equals('linked');
      check(json['name']).equals('feature');
      check((json['chats'] as List).length).equals(1);
    });

    test('fromJson restores correctly', () {
      final json = {
        'type': 'primary',
        'name': 'main',
        'chats': [
          {'name': 'Chat 1', 'chatId': 'chat-1'},
          {'name': 'Chat 2', 'chatId': 'chat-2'},
        ],
      };

      final worktree = WorktreeInfo.fromJson(json);

      check(worktree.type).equals('primary');
      check(worktree.name).equals('main');
      check(worktree.chats.length).equals(2);
      check(worktree.chats[0].chatId).equals('chat-1');
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final worktree = WorktreeInfo.fromJson(json);

      check(worktree.type).equals('primary');
      check(worktree.name).equals('main');
      check(worktree.chats).isEmpty();
    });

    test('round-trip preserves data', () {
      const original = WorktreeInfo.linked(
        name: 'feature-auth',
        chats: [
          ChatReference(
            name: 'Auth Chat',
            chatId: 'chat-auth',
            lastSessionId: 'session-1',
          ),
        ],
      );

      final json = jsonEncode(original.toJson());
      final restored = WorktreeInfo.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored).equals(original);
    });

    test('creates with baseOverride', () {
      const worktree = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'develop',
      );

      check(worktree.baseOverride).equals('develop');
    });

    test('baseOverride defaults to null', () {
      const worktree = WorktreeInfo.primary(name: 'main');

      check(worktree.baseOverride).isNull();
    });

    test('toJson omits baseOverride when null', () {
      const worktree = WorktreeInfo.primary(name: 'main');

      final json = worktree.toJson();

      check(json.containsKey('baseOverride')).isFalse();
    });

    test('toJson includes baseOverride when set', () {
      const worktree = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'develop',
      );

      final json = worktree.toJson();

      check(json['baseOverride']).equals('develop');
    });

    test('fromJson restores baseOverride', () {
      final json = {
        'type': 'linked',
        'name': 'feature',
        'chats': <dynamic>[],
        'baseOverride': 'develop',
      };

      final worktree = WorktreeInfo.fromJson(json);

      check(worktree.baseOverride).equals('develop');
    });

    test('fromJson handles missing baseOverride', () {
      final json = {
        'type': 'linked',
        'name': 'feature',
        'chats': <dynamic>[],
      };

      final worktree = WorktreeInfo.fromJson(json);

      check(worktree.baseOverride).isNull();
    });

    test('round-trip preserves baseOverride', () {
      const original = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'origin/develop',
      );

      final json = jsonEncode(original.toJson());
      final restored = WorktreeInfo.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored).equals(original);
      check(restored.baseOverride).equals('origin/develop');
    });

    test('round-trip preserves null baseOverride', () {
      const original = WorktreeInfo.linked(name: 'feature');

      final json = jsonEncode(original.toJson());
      final restored = WorktreeInfo.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored).equals(original);
      check(restored.baseOverride).isNull();
    });

    test('copyWith updates baseOverride', () {
      const original = WorktreeInfo.linked(name: 'feature');

      final modified = original.copyWith(baseOverride: 'develop');

      check(modified.baseOverride).equals('develop');
      check(modified.name).equals('feature');
    });

    test('copyWith preserves baseOverride when not specified', () {
      const original = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'develop',
      );

      final modified = original.copyWith(name: 'other');

      check(modified.baseOverride).equals('develop');
    });

    test('copyWith clears baseOverride with clearBaseOverride', () {
      const original = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'develop',
      );

      final modified = original.copyWith(clearBaseOverride: true);

      check(modified.baseOverride).isNull();
    });

    test('equality includes baseOverride', () {
      const a = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'develop',
      );
      const b = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'develop',
      );
      const c = WorktreeInfo.linked(
        name: 'feature',
        baseOverride: 'main',
      );
      const d = WorktreeInfo.linked(name: 'feature');

      check(a == b).isTrue();
      check(a.hashCode).equals(b.hashCode);
      check(a == c).isFalse();
      check(a == d).isFalse();
    });
  });

  group('ProjectInfo', () {
    test('creates with required fields', () {
      const project = ProjectInfo(id: 'abc123', name: 'My Project');

      check(project.id).equals('abc123');
      check(project.name).equals('My Project');
      check(project.worktrees).isEmpty();
    });

    test('creates with worktrees', () {
      const project = ProjectInfo(
        id: 'abc123',
        name: 'My Project',
        worktrees: {
          '/path/to/project': WorktreeInfo.primary(name: 'main'),
          '/path/to/feature': WorktreeInfo.linked(name: 'feature'),
        },
      );

      check(project.worktrees.length).equals(2);
      check(project.worktrees['/path/to/project']!.isPrimary).isTrue();
    });

    test('copyWith preserves unchanged fields', () {
      const original = ProjectInfo(
        id: 'abc123',
        name: 'Original',
        worktrees: {'/path': WorktreeInfo.primary(name: 'main')},
      );

      final modified = original.copyWith(name: 'Modified');

      check(modified.name).equals('Modified');
      check(modified.id).equals('abc123');
      check(modified.worktrees.length).equals(1);
    });

    test('toJson produces correct structure', () {
      const project = ProjectInfo(
        id: 'abc123',
        name: 'Test Project',
        worktrees: {'/path': WorktreeInfo.primary(name: 'main')},
      );

      final json = project.toJson();

      check(json['id']).equals('abc123');
      check(json['name']).equals('Test Project');
      check((json['worktrees'] as Map).containsKey('/path')).isTrue();
    });

    test('fromJson restores correctly', () {
      final json = {
        'id': 'xyz789',
        'name': 'Restored Project',
        'worktrees': {
          '/restored/path': {'type': 'primary', 'name': 'main', 'chats': []},
        },
      };

      final project = ProjectInfo.fromJson(json);

      check(project.id).equals('xyz789');
      check(project.name).equals('Restored Project');
      check(project.worktrees.length).equals(1);
      check(project.worktrees['/restored/path']!.name).equals('main');
    });

    test('fromJson uses defaults for missing optional fields', () {
      final json = {'id': 'abc123'};

      final project = ProjectInfo.fromJson(json);

      check(project.name).equals('Unnamed Project');
      check(project.worktrees).isEmpty();
    });

    test('round-trip preserves data', () {
      const original = ProjectInfo(
        id: 'roundtrip',
        name: 'Round Trip Project',
        worktrees: {
          '/primary': WorktreeInfo.primary(
            name: 'main',
            chats: [ChatReference(name: 'Chat', chatId: 'chat-1')],
          ),
          '/linked': WorktreeInfo.linked(name: 'feature'),
        },
      );

      final json = jsonEncode(original.toJson());
      final restored = ProjectInfo.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored).equals(original);
    });
  });

  group('ProjectsIndex', () {
    test('empty() creates empty index', () {
      const index = ProjectsIndex.empty();

      check(index.projects).isEmpty();
    });

    test('creates with projects map', () {
      const index = ProjectsIndex(
        projects: {
          '/project1': ProjectInfo(id: 'id1', name: 'Project 1'),
          '/project2': ProjectInfo(id: 'id2', name: 'Project 2'),
        },
      );

      check(index.projects.length).equals(2);
      check(index.projects['/project1']!.name).equals('Project 1');
    });

    test('copyWith preserves unchanged fields', () {
      const original = ProjectsIndex(
        projects: {'/old': ProjectInfo(id: '1', name: 'Old')},
      );

      final modified = original.copyWith(
        projects: {'/new': const ProjectInfo(id: '2', name: 'New')},
      );

      check(modified.projects.length).equals(1);
      check(modified.projects.containsKey('/new')).isTrue();
    });

    test('toJson produces correct structure', () {
      const index = ProjectsIndex(
        projects: {
          '/my/project': ProjectInfo(
            id: 'abc123',
            name: 'My Project',
            worktrees: {'/my/project': WorktreeInfo.primary(name: 'main')},
          ),
        },
      );

      final json = index.toJson();

      check(json.containsKey('/my/project')).isTrue();
      check((json['/my/project'] as Map)['id']).equals('abc123');
    });

    test('fromJson restores correctly', () {
      final json = {
        '/restored/project': {
          'id': 'restored-id',
          'name': 'Restored Project',
          'worktrees': {
            '/restored/project': {'type': 'primary', 'name': 'main'},
          },
        },
      };

      final index = ProjectsIndex.fromJson(json);

      check(index.projects.length).equals(1);
      check(index.projects['/restored/project']!.id).equals('restored-id');
    });

    test('fromJson handles empty object', () {
      final json = <String, dynamic>{};

      final index = ProjectsIndex.fromJson(json);

      check(index.projects).isEmpty();
    });

    test('round-trip preserves data', () {
      const original = ProjectsIndex(
        projects: {
          '/project/a': ProjectInfo(
            id: 'id-a',
            name: 'Project A',
            worktrees: {
              '/project/a': WorktreeInfo.primary(
                name: 'main',
                chats: [
                  ChatReference(
                    name: 'Chat 1',
                    chatId: 'chat-1',
                    lastSessionId: 'session-1',
                  ),
                ],
              ),
            },
          ),
          '/project/b': ProjectInfo(
            id: 'id-b',
            name: 'Project B',
            worktrees: {
              '/project/b': WorktreeInfo.primary(name: 'develop'),
              '/project/b-feature': WorktreeInfo.linked(name: 'feature'),
            },
          ),
        },
      );

      final json = jsonEncode(original.toJson());
      final restored = ProjectsIndex.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      check(restored).equals(original);
    });

    test('equality works correctly', () {
      const a = ProjectsIndex(
        projects: {'/p': ProjectInfo(id: '1', name: 'P')},
      );
      const b = ProjectsIndex(
        projects: {'/p': ProjectInfo(id: '1', name: 'P')},
      );
      const c = ProjectsIndex(
        projects: {'/q': ProjectInfo(id: '2', name: 'Q')},
      );

      check(a == b).isTrue();
      // Note: hashCode equality not tested for Map-based types as iteration
      // order is not guaranteed to be consistent
      check(a == c).isFalse();
    });
  });
}
