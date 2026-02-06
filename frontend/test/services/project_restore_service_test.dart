import 'dart:convert';
import 'dart:io';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/persistence_models.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    // Create a temporary directory for each test
    tempDir = await Directory.systemTemp.createTemp('project_restore_test_');
    // Redirect PersistenceService to temp dir so ChatState.initPersistence
    // doesn't create directories in ~/.ccinsights/projects/
    PersistenceService.setBaseDir('${tempDir.path}/.ccinsights');
  });

  tearDown(() async {
    // Reset persistence service to default
    PersistenceService.setBaseDir(
      '${Platform.environment['HOME']}/.ccinsights',
    );
    // Clean up temporary directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProjectRestoreService', () {
    group('restoreOrCreateProject', () {
      test('creates new project when none exists', () async {
        // Arrange
        final projectRoot = tempDir.path;
        final service = ProjectRestoreService(
          persistence: _TestPersistenceService(tempDir.path),
        );

        // Act
        final (project, isNew) = await service.restoreOrCreateProject(
          projectRoot,
        );

        // Assert
        check(isNew).isTrue();
        check(project.data.repoRoot).equals(projectRoot);
        check(project.primaryWorktree.data.worktreeRoot).equals(projectRoot);
        check(project.primaryWorktree.data.isPrimary).isTrue();
        check(project.primaryWorktree.chats).isEmpty();
      });

      test('restores existing project with worktrees and chats', () async {
        // Arrange
        final projectRoot = tempDir.path;
        final projectId = PersistenceService.generateProjectId(projectRoot);
        final persistence = _TestPersistenceService(tempDir.path);

        // Create a projects.json with existing project data
        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: projectId,
              name: 'Test Project',
              worktrees: {
                projectRoot: WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    const ChatReference(
                      name: 'Chat 1',
                      chatId: 'chat-123',
                    ),
                    const ChatReference(
                      name: 'Chat 2',
                      chatId: 'chat-456',
                    ),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        final service = ProjectRestoreService(persistence: persistence);

        // Act
        final (project, isNew) = await service.restoreOrCreateProject(
          projectRoot,
        );

        // Assert
        check(isNew).isFalse();
        check(project.data.name).equals('Test Project');
        check(project.data.repoRoot).equals(projectRoot);
        check(project.primaryWorktree.chats.length).equals(2);
        check(project.primaryWorktree.chats[0].data.name).equals('Chat 1');
        check(project.primaryWorktree.chats[0].data.id).equals('chat-123');
        check(project.primaryWorktree.chats[1].data.name).equals('Chat 2');
        check(project.primaryWorktree.chats[1].data.id).equals('chat-456');
      });

      test('restores project with linked worktrees', () async {
        // Arrange
        final projectRoot = tempDir.path;
        final linkedWorktreePath = '$projectRoot-feature';
        final projectId = PersistenceService.generateProjectId(projectRoot);
        final persistence = _TestPersistenceService(tempDir.path);

        // Create the linked worktree directory so validation doesn't prune it
        Directory(linkedWorktreePath).createSync();

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: projectId,
              name: 'Test Project',
              worktrees: {
                projectRoot: const WorktreeInfo.primary(name: 'main'),
                linkedWorktreePath: const WorktreeInfo.linked(
                  name: 'feature-branch',
                  chats: [
                    ChatReference(name: 'Feature Chat', chatId: 'chat-789'),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        final service = ProjectRestoreService(persistence: persistence);

        // Act
        final (project, isNew) = await service.restoreOrCreateProject(
          projectRoot,
          autoValidate: false,
          watchFilesystem: false,
        );

        // Assert
        check(isNew).isFalse();
        check(project.linkedWorktrees.length).equals(1);
        check(
          project.linkedWorktrees[0].data.worktreeRoot,
        ).equals(linkedWorktreePath);
        check(project.linkedWorktrees[0].data.isPrimary).isFalse();
        check(project.linkedWorktrees[0].chats.length).equals(1);
        check(
          project.linkedWorktrees[0].chats[0].data.name,
        ).equals('Feature Chat');
      });

      test('applies model and permission settings from meta', () async {
        // Arrange
        final projectRoot = tempDir.path;
        final projectId = PersistenceService.generateProjectId(projectRoot);
        final persistence = _TestPersistenceService(tempDir.path);

        // Create projects.json
        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: projectId,
              name: 'Test Project',
              worktrees: {
                projectRoot: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(name: 'Test Chat', chatId: 'chat-meta-test'),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Create chat meta with specific settings.
        // Note: model name must match ChatModelCatalog IDs (e.g., 'opus').
        await persistence.saveChatMeta(
          projectId,
          'chat-meta-test',
          ChatMeta.create(
            model: 'opus',
            permissionMode: 'acceptEdits',
          ),
        );

        final service = ProjectRestoreService(persistence: persistence);

        // Act
        final (project, _) = await service.restoreOrCreateProject(projectRoot);

        // Assert
        final chat = project.primaryWorktree.chats[0];
        check(chat.model).equals(ChatModelCatalog.claudeModels.last);
        check(chat.permissionMode).equals(PermissionMode.acceptEdits);
      });
    });

    group('loadChatHistory', () {
      test('loads entries from persistence into chat', () async {
        // Arrange
        final projectRoot = tempDir.path;
        final projectId = PersistenceService.generateProjectId(projectRoot);
        final persistence = _TestPersistenceService(tempDir.path);

        // Create chat state
        final chat = ChatState.create(
          name: 'Test Chat',
          worktreeRoot: projectRoot,
        );
        await chat.initPersistence(projectId);

        // Write some entries to the chat history file
        final entries = [
          UserInputEntry(
            timestamp: DateTime.parse('2025-01-27T10:00:00.000Z'),
            text: 'Hello!',
          ),
          TextOutputEntry(
            timestamp: DateTime.parse('2025-01-27T10:00:01.000Z'),
            text: 'Hi there!',
            contentType: 'text',
          ),
        ];
        for (final entry in entries) {
          await persistence.appendChatEntry(projectId, chat.data.id, entry);
        }

        final service = ProjectRestoreService(persistence: persistence);

        // Act
        final count = await service.loadChatHistory(chat, projectId);

        // Assert
        check(count).equals(2);
        check(chat.data.primaryConversation.entries.length).equals(2);
        check(
          (chat.data.primaryConversation.entries[0] as UserInputEntry).text,
        ).equals('Hello!');
        check(
          (chat.data.primaryConversation.entries[1] as TextOutputEntry).text,
        ).equals('Hi there!');
      });

      test('returns 0 when no history exists', () async {
        // Arrange
        final projectRoot = tempDir.path;
        final projectId = PersistenceService.generateProjectId(projectRoot);
        final persistence = _TestPersistenceService(tempDir.path);

        final chat = ChatState.create(
          name: 'Empty Chat',
          worktreeRoot: projectRoot,
        );
        await chat.initPersistence(projectId);

        final service = ProjectRestoreService(persistence: persistence);

        // Act
        final count = await service.loadChatHistory(chat, projectId);

        // Assert
        check(count).equals(0);
        check(chat.data.primaryConversation.entries).isEmpty();
      });
    });

    group('addChatToWorktree', () {
      test('adds chat to projects.json and initializes persistence', () async {
        // Arrange
        final projectRoot = tempDir.path;
        final projectId = PersistenceService.generateProjectId(projectRoot);
        final persistence = _TestPersistenceService(tempDir.path);

        // Create initial project
        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: projectId,
              name: 'Test Project',
              worktrees: {
                projectRoot: const WorktreeInfo.primary(name: 'main'),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        final chat = ChatState.create(
          name: 'New Chat',
          worktreeRoot: projectRoot,
        );

        final service = ProjectRestoreService(persistence: persistence);

        // Act
        await service.addChatToWorktree(projectRoot, projectRoot, chat);

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final project = updatedIndex.projects[projectRoot]!;
        final worktree = project.worktrees[projectRoot]!;
        check(worktree.chats.length).equals(1);
        check(worktree.chats[0].name).equals('New Chat');
        check(worktree.chats[0].chatId).equals(chat.data.id);
        check(chat.projectId).equals(projectId);
      });
    });
  });

  group('ChatState.loadEntriesFromPersistence', () {
    test('replaces existing entries without triggering persistence', () {
      // Arrange
      final chat = ChatState.create(name: 'Test', worktreeRoot: '/path');
      chat.addEntry(
        UserInputEntry(timestamp: DateTime.now(), text: 'Original'),
      );
      check(chat.data.primaryConversation.entries.length).equals(1);

      // Act
      chat.loadEntriesFromPersistence([
        UserInputEntry(
          timestamp: DateTime.parse('2025-01-27T10:00:00.000Z'),
          text: 'Restored 1',
        ),
        TextOutputEntry(
          timestamp: DateTime.parse('2025-01-27T10:00:01.000Z'),
          text: 'Restored 2',
          contentType: 'text',
        ),
      ]);

      // Assert
      check(chat.data.primaryConversation.entries.length).equals(2);
      check(
        (chat.data.primaryConversation.entries[0] as UserInputEntry).text,
      ).equals('Restored 1');
    });

    test('notifies listeners when entries are loaded', () {
      // Arrange
      final chat = ChatState.create(name: 'Test', worktreeRoot: '/path');
      var notified = false;
      chat.addListener(() => notified = true);

      // Act
      chat.loadEntriesFromPersistence([
        UserInputEntry(timestamp: DateTime.now(), text: 'Test'),
      ]);

      // Assert
      check(notified).isTrue();
    });
  });

  group('ChatState.hasLoadedHistory', () {
    test('returns false when no entries', () {
      final chat = ChatState.create(name: 'Test', worktreeRoot: '/path');
      check(chat.hasLoadedHistory).isFalse();
    });

    test('returns true when entries exist', () {
      final chat = ChatState.create(name: 'Test', worktreeRoot: '/path');
      chat.addEntry(UserInputEntry(timestamp: DateTime.now(), text: 'Test'));
      check(chat.hasLoadedHistory).isTrue();
    });
  });
}

/// Test persistence service that uses a custom base directory.
class _TestPersistenceService extends PersistenceService {
  final String _testBaseDir;

  _TestPersistenceService(this._testBaseDir);

  String get _baseDir => '$_testBaseDir/.ccinsights';

  @override
  Future<ProjectsIndex> loadProjectsIndex() async {
    final file = File('$_baseDir/projects.json');

    if (!await file.exists()) {
      return const ProjectsIndex.empty();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return const ProjectsIndex.empty();
      }
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ProjectsIndex.fromJson(json);
    } catch (e) {
      return const ProjectsIndex.empty();
    }
  }

  @override
  Future<void> saveProjectsIndex(ProjectsIndex index) async {
    final dir = Directory(_baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('$_baseDir/projects.json');
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(index.toJson()));
  }

  @override
  Future<ChatMeta> loadChatMeta(String projectId, String chatId) async {
    final path = '$_baseDir/projects/$projectId/chats/$chatId.meta.json';
    final file = File(path);

    if (!await file.exists()) {
      return ChatMeta.create();
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ChatMeta.fromJson(json);
    } catch (e) {
      return ChatMeta.create();
    }
  }

  @override
  Future<void> saveChatMeta(
    String projectId,
    String chatId,
    ChatMeta meta,
  ) async {
    final dirPath = '$_baseDir/projects/$projectId/chats';
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final path = '$dirPath/$chatId.meta.json';
    final encoder = const JsonEncoder.withIndent('  ');
    await File(path).writeAsString(encoder.convert(meta.toJson()));
  }

  @override
  Future<List<OutputEntry>> loadChatHistory(
    String projectId,
    String chatId,
  ) async {
    final path = '$_baseDir/projects/$projectId/chats/$chatId.chat.jsonl';
    final file = File(path);

    if (!await file.exists()) {
      return [];
    }

    final entries = <OutputEntry>[];
    final lines = await file.readAsLines();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        entries.add(OutputEntry.fromJson(json));
      } catch (_) {
        // Skip invalid lines
      }
    }

    return entries;
  }

  @override
  Future<void> appendChatEntry(
    String projectId,
    String chatId,
    OutputEntry entry,
  ) async {
    final dirPath = '$_baseDir/projects/$projectId/chats';
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final path = '$dirPath/$chatId.chat.jsonl';
    final json = jsonEncode(entry.toJson());
    await File(path).writeAsString('$json\n', mode: FileMode.append);
  }

  @override
  Future<void> ensureDirectories(String projectId) async {
    final dirPath = '$_baseDir/projects/$projectId/chats';
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
