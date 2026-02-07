import 'dart:convert';
import 'dart:io';

import 'package:agent_sdk_core/agent_sdk_core.dart' show ToolKind;
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/persistence_models.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late _TestPersistenceService persistence;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('persistence_service_test_');
    persistence = _TestPersistenceService(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PersistenceService', () {
    group('generateProjectId', () {
      test('generates stable ID from path', () {
        // Arrange
        const path = '/Users/test/my-project';

        // Act
        final id1 = PersistenceService.generateProjectId(path);
        final id2 = PersistenceService.generateProjectId(path);

        // Assert
        check(id1).equals(id2);
        check(id1.length).equals(8);
      });

      test('generates different IDs for different paths', () {
        // Arrange
        const path1 = '/Users/test/project1';
        const path2 = '/Users/test/project2';

        // Act
        final id1 = PersistenceService.generateProjectId(path1);
        final id2 = PersistenceService.generateProjectId(path2);

        // Assert
        check(id1).not((it) => it.equals(id2));
      });
    });

    group('updateChatSessionId', () {
      test('updates session ID for existing chat', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const chatId = 'chat-123';
        const sessionId = 'session-abc';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(
                      name: 'Test Chat',
                      chatId: chatId,
                    ),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.updateChatSessionId(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
          sessionId: sessionId,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final updatedChat =
            updatedIndex.projects[projectRoot]!.worktrees[worktreePath]!.chats[0];
        check(updatedChat.lastSessionId).equals(sessionId);
      });

      test('clears session ID when null is passed', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const chatId = 'chat-123';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(
                      name: 'Test Chat',
                      chatId: chatId,
                      lastSessionId: 'existing-session',
                    ),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.updateChatSessionId(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
          sessionId: null,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final updatedChat =
            updatedIndex.projects[projectRoot]!.worktrees[worktreePath]!.chats[0];
        check(updatedChat.lastSessionId).isNull();
      });

      test('handles missing project gracefully', () async {
        // Arrange
        const projectRoot = '/test/nonexistent';
        const worktreePath = '/test/nonexistent';
        const chatId = 'chat-123';

        // Act - should not throw
        await persistence.updateChatSessionId(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
          sessionId: 'session-123',
        );

        // Assert - projects.json should remain unchanged (or empty)
        final index = await persistence.loadProjectsIndex();
        check(index.projects).isEmpty();
      });

      test('handles missing worktree gracefully', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project/feature';
        const chatId = 'chat-123';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                projectRoot: const WorktreeInfo.primary(name: 'main'),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act - should not throw
        await persistence.updateChatSessionId(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
          sessionId: 'session-123',
        );

        // Assert - projects.json should remain unchanged
        final index = await persistence.loadProjectsIndex();
        final worktree = index.projects[projectRoot]!.worktrees[projectRoot];
        check(worktree).isNotNull();
        check(worktree!.chats).isEmpty();
      });

      test('only updates the matching chat in a worktree with multiple chats',
          () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const targetChatId = 'chat-2';
        const otherChatId = 'chat-1';
        const sessionId = 'new-session';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(
                      name: 'Chat 1',
                      chatId: otherChatId,
                      lastSessionId: 'original-session',
                    ),
                    ChatReference(
                      name: 'Chat 2',
                      chatId: targetChatId,
                    ),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.updateChatSessionId(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: targetChatId,
          sessionId: sessionId,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final chats =
            updatedIndex.projects[projectRoot]!.worktrees[worktreePath]!.chats;

        // First chat should be unchanged
        check(chats[0].chatId).equals(otherChatId);
        check(chats[0].lastSessionId).equals('original-session');

        // Second chat should be updated
        check(chats[1].chatId).equals(targetChatId);
        check(chats[1].lastSessionId).equals(sessionId);
      });

      test('preserves chat name when updating session ID', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const chatId = 'chat-123';
        const chatName = 'My Important Chat';
        const sessionId = 'session-abc';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(
                      name: chatName,
                      chatId: chatId,
                    ),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.updateChatSessionId(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
          sessionId: sessionId,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final updatedChat =
            updatedIndex.projects[projectRoot]!.worktrees[worktreePath]!.chats[0];
        check(updatedChat.name).equals(chatName);
        check(updatedChat.chatId).equals(chatId);
        check(updatedChat.lastSessionId).equals(sessionId);
      });
    });

    group('removeChatFromIndex', () {
      test('removes chat from worktree with single chat', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const chatId = 'chat-123';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(name: 'Test Chat', chatId: chatId),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.removeChatFromIndex(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final chats =
            updatedIndex.projects[projectRoot]!.worktrees[worktreePath]!.chats;
        check(chats).isEmpty();
      });

      test('removes only matching chat from worktree with multiple chats',
          () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const chatToRemove = 'chat-2';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(name: 'Chat 1', chatId: 'chat-1'),
                    ChatReference(name: 'Chat 2', chatId: chatToRemove),
                    ChatReference(name: 'Chat 3', chatId: 'chat-3'),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.removeChatFromIndex(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatToRemove,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final chats =
            updatedIndex.projects[projectRoot]!.worktrees[worktreePath]!.chats;
        check(chats.length).equals(2);
        check(chats[0].chatId).equals('chat-1');
        check(chats[1].chatId).equals('chat-3');
      });

      test('handles missing project gracefully', () async {
        // Arrange - empty index
        await persistence.saveProjectsIndex(const ProjectsIndex.empty());

        // Act - should not throw
        await persistence.removeChatFromIndex(
          projectRoot: '/nonexistent',
          worktreePath: '/nonexistent',
          chatId: 'chat-123',
        );

        // Assert - index should remain unchanged
        final index = await persistence.loadProjectsIndex();
        check(index.projects).isEmpty();
      });

      test('handles missing worktree gracefully', () async {
        // Arrange
        const projectRoot = '/test/project';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                projectRoot: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [ChatReference(name: 'Chat', chatId: 'chat-1')],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act - try to remove from nonexistent worktree
        await persistence.removeChatFromIndex(
          projectRoot: projectRoot,
          worktreePath: '/nonexistent/worktree',
          chatId: 'chat-1',
        );

        // Assert - original worktree should be unchanged
        final index = await persistence.loadProjectsIndex();
        final chats = index.projects[projectRoot]!.worktrees[projectRoot]!.chats;
        check(chats.length).equals(1);
        check(chats[0].chatId).equals('chat-1');
      });

      test('handles nonexistent chat ID gracefully', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(name: 'Chat 1', chatId: 'chat-1'),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act - try to remove nonexistent chat
        await persistence.removeChatFromIndex(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: 'nonexistent-chat',
        );

        // Assert - existing chat should remain
        final index = await persistence.loadProjectsIndex();
        final chats = index.projects[projectRoot]!.worktrees[worktreePath]!.chats;
        check(chats.length).equals(1);
        check(chats[0].chatId).equals('chat-1');
      });
    });

    group('loadChatHistory', () {
      test('merges tool results with tool use entries', () async {
        // Arrange
        const projectId = 'test-project';
        const chatId = 'chat-123';
        const toolUseId = 'tool-use-abc';

        // Create a JSONL file with tool_use followed by tool_result
        final toolUse = ToolUseOutputEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 0),
          toolName: 'Read',
          toolKind: ToolKind.read,
          toolUseId: toolUseId,
          toolInput: {'file_path': '/test/file.txt'},
        );

        final result = ToolResultEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 1),
          toolUseId: toolUseId,
          result: 'File contents here',
          isError: false,
        );

        await persistence.writeJsonlEntries(projectId, chatId, [
          toolUse,
          result,
        ]);

        // Act
        final entries = await persistence.loadChatHistory(projectId, chatId);

        // Assert
        check(entries.length).equals(1);
        check(entries.first).isA<ToolUseOutputEntry>();

        final loadedToolUse = entries.first as ToolUseOutputEntry;
        check(loadedToolUse.toolUseId).equals(toolUseId);
        check(loadedToolUse.toolName).equals('Read');
        check(loadedToolUse.result).equals('File contents here');
        check(loadedToolUse.isError).equals(false);
      });

      test('handles tool result arriving before tool use', () async {
        // Arrange - edge case: result before use (shouldn't happen, but be robust)
        const projectId = 'test-project';
        const chatId = 'chat-456';
        const toolUseId = 'tool-use-def';

        final result = ToolResultEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 0),
          toolUseId: toolUseId,
          result: 'Orphan result',
          isError: false,
        );

        final toolUse = ToolUseOutputEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 1),
          toolName: 'Write',
          toolKind: ToolKind.edit,
          toolUseId: toolUseId,
          toolInput: {'content': 'test'},
        );

        await persistence.writeJsonlEntries(projectId, chatId, [
          result,
          toolUse,
        ]);

        // Act
        final entries = await persistence.loadChatHistory(projectId, chatId);

        // Assert - should still merge correctly
        check(entries.length).equals(1);
        final loadedToolUse = entries.first as ToolUseOutputEntry;
        check(loadedToolUse.result).equals('Orphan result');
      });

      test('handles error tool results', () async {
        // Arrange
        const projectId = 'test-project';
        const chatId = 'chat-789';
        const toolUseId = 'tool-use-err';

        final toolUse = ToolUseOutputEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 0),
          toolName: 'Bash',
          toolKind: ToolKind.execute,
          toolUseId: toolUseId,
          toolInput: {'command': 'invalid-command'},
        );

        final result = ToolResultEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 1),
          toolUseId: toolUseId,
          result: 'Command not found',
          isError: true,
        );

        await persistence.writeJsonlEntries(projectId, chatId, [
          toolUse,
          result,
        ]);

        // Act
        final entries = await persistence.loadChatHistory(projectId, chatId);

        // Assert
        check(entries.length).equals(1);
        final loadedToolUse = entries.first as ToolUseOutputEntry;
        check(loadedToolUse.isError).equals(true);
        check(loadedToolUse.result).equals('Command not found');
      });

      test('preserves non-tool entries unchanged', () async {
        // Arrange
        const projectId = 'test-project';
        const chatId = 'chat-mixed';

        final textEntry = TextOutputEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 0),
          text: 'Hello world',
          contentType: 'text',
        );

        final toolUse = ToolUseOutputEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 1),
          toolName: 'Read',
          toolKind: ToolKind.read,
          toolUseId: 'tool-123',
          toolInput: {'path': '/test'},
        );

        final result = ToolResultEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 2),
          toolUseId: 'tool-123',
          result: 'file content',
          isError: false,
        );

        final thinkingEntry = TextOutputEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 3),
          text: 'I should analyze this...',
          contentType: 'thinking',
        );

        await persistence.writeJsonlEntries(projectId, chatId, [
          textEntry,
          toolUse,
          result,
          thinkingEntry,
        ]);

        // Act
        final entries = await persistence.loadChatHistory(projectId, chatId);

        // Assert - 3 entries (text, tool_use with result, thinking)
        check(entries.length).equals(3);
        check(entries[0]).isA<TextOutputEntry>();
        check((entries[0] as TextOutputEntry).text).equals('Hello world');

        check(entries[1]).isA<ToolUseOutputEntry>();
        check((entries[1] as ToolUseOutputEntry).result).equals('file content');

        check(entries[2]).isA<TextOutputEntry>();
        check((entries[2] as TextOutputEntry).contentType).equals('thinking');
      });

      test('handles tool use without result (still in progress)', () async {
        // Arrange
        const projectId = 'test-project';
        const chatId = 'chat-incomplete';

        final toolUse = ToolUseOutputEntry(
          timestamp: DateTime(2024, 1, 1, 12, 0, 0),
          toolName: 'Bash',
          toolKind: ToolKind.execute,
          toolUseId: 'tool-pending',
          toolInput: {'command': 'sleep 10'},
        );

        await persistence.writeJsonlEntries(projectId, chatId, [toolUse]);

        // Act
        final entries = await persistence.loadChatHistory(projectId, chatId);

        // Assert
        check(entries.length).equals(1);
        final loadedToolUse = entries.first as ToolUseOutputEntry;
        check(loadedToolUse.result).isNull();
        check(loadedToolUse.isError).equals(false);
      });
    });

    group('archiveChat', () {
      test('moves chat from worktree to archived list', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const chatId = 'chat-to-archive';
        final projectId =
            PersistenceService.generateProjectId(projectRoot);

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: projectId,
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(
                      name: 'Archive Me',
                      chatId: chatId,
                      lastSessionId: 'session-1',
                    ),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.archiveChat(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final worktree =
            updatedIndex.projects[projectRoot]!.worktrees[worktreePath]!;
        check(worktree.chats).isEmpty();

        final archived = updatedIndex.projects[projectRoot]!.archivedChats;
        check(archived.length).equals(1);
        check(archived[0].chatId).equals(chatId);
        check(archived[0].name).equals('Archive Me');
        check(archived[0].lastSessionId).equals('session-1');
        check(archived[0].originalWorktreePath).equals(worktreePath);
      });

      test('preserves chat files on disk', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project';
        const chatId = 'chat-with-files';
        final projectId =
            PersistenceService.generateProjectId(projectRoot);

        await persistence.createChatFiles(projectId, chatId);

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: projectId,
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.primary(
                  name: 'main',
                  chats: [
                    ChatReference(name: 'Chat', chatId: chatId),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.archiveChat(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
        );

        // Assert - files should still exist
        final filesExist =
            await persistence.chatFilesExist(projectId, chatId);
        check(filesExist).isTrue();
      });
    });

    group('restoreArchivedChat', () {
      test('moves chat from archived list to target worktree', () async {
        // Arrange
        const projectRoot = '/test/project';
        const targetWorktreePath = '/test/project/feature';
        const chatId = 'chat-to-restore';
        final archivedAt = DateTime.utc(2025, 6, 15, 10, 30);

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                targetWorktreePath: const WorktreeInfo.linked(
                  name: 'feature',
                ),
              },
              archivedChats: [
                ArchivedChatReference(
                  name: 'Restored Chat',
                  chatId: chatId,
                  lastSessionId: 'session-old',
                  originalWorktreePath: '/test/project',
                  archivedAt: archivedAt,
                ),
              ],
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.restoreArchivedChat(
          projectRoot: projectRoot,
          targetWorktreePath: targetWorktreePath,
          chatId: chatId,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final project = updatedIndex.projects[projectRoot]!;

        // Chat should be in the target worktree
        final worktree = project.worktrees[targetWorktreePath]!;
        check(worktree.chats.length).equals(1);
        check(worktree.chats[0].chatId).equals(chatId);
        check(worktree.chats[0].name).equals('Restored Chat');
        check(worktree.chats[0].lastSessionId).equals('session-old');

        // Chat should be removed from archived list
        check(project.archivedChats).isEmpty();
      });
    });

    group('archiveWorktreeChats', () {
      test('archives all chats in a worktree', () async {
        // Arrange
        const projectRoot = '/test/project';
        const worktreePath = '/test/project/feature';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                worktreePath: const WorktreeInfo.linked(
                  name: 'feature',
                  chats: [
                    ChatReference(name: 'Chat 1', chatId: 'chat-1'),
                    ChatReference(
                      name: 'Chat 2',
                      chatId: 'chat-2',
                      lastSessionId: 'session-2',
                    ),
                    ChatReference(name: 'Chat 3', chatId: 'chat-3'),
                  ],
                ),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.archiveWorktreeChats(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
        );

        // Assert
        final updatedIndex = await persistence.loadProjectsIndex();
        final project = updatedIndex.projects[projectRoot]!;

        // Worktree should have no chats
        final worktree = project.worktrees[worktreePath]!;
        check(worktree.chats).isEmpty();

        // All chats should be in the archived list
        check(project.archivedChats.length).equals(3);
        check(project.archivedChats[0].chatId).equals('chat-1');
        check(project.archivedChats[1].chatId).equals('chat-2');
        check(project.archivedChats[1].lastSessionId).equals('session-2');
        check(project.archivedChats[2].chatId).equals('chat-3');

        // All should reference the original worktree path
        for (final archived in project.archivedChats) {
          check(archived.originalWorktreePath).equals(worktreePath);
        }
      });
    });

    group('deleteArchivedChat', () {
      test('removes from archived list and deletes files', () async {
        // Arrange
        const projectRoot = '/test/project';
        const chatId = 'chat-to-delete';
        final projectId =
            PersistenceService.generateProjectId(projectRoot);
        final archivedAt = DateTime.utc(2025, 6, 15, 10, 30);

        // Create chat files on disk
        await persistence.createChatFiles(projectId, chatId);

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: projectId,
              name: 'Test Project',
              archivedChats: [
                ArchivedChatReference(
                  name: 'Delete Me',
                  chatId: chatId,
                  originalWorktreePath: '/test/project',
                  archivedAt: archivedAt,
                ),
              ],
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        await persistence.deleteArchivedChat(
          projectRoot: projectRoot,
          projectId: projectId,
          chatId: chatId,
        );

        // Assert - removed from index
        final updatedIndex = await persistence.loadProjectsIndex();
        final project = updatedIndex.projects[projectRoot]!;
        check(project.archivedChats).isEmpty();

        // Assert - files deleted from disk
        final filesExist =
            await persistence.chatFilesExist(projectId, chatId);
        check(filesExist).isFalse();
      });
    });

    group('getArchivedChats', () {
      test('returns archived chats for project', () async {
        // Arrange
        const projectRoot = '/test/project';
        final archivedAt = DateTime.utc(2025, 6, 15, 10, 30);

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              archivedChats: [
                ArchivedChatReference(
                  name: 'Archived 1',
                  chatId: 'chat-a1',
                  originalWorktreePath: '/test/project',
                  archivedAt: archivedAt,
                ),
                ArchivedChatReference(
                  name: 'Archived 2',
                  chatId: 'chat-a2',
                  originalWorktreePath: '/test/project/feature',
                  archivedAt: archivedAt,
                ),
              ],
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        final result = await persistence.getArchivedChats(
          projectRoot: projectRoot,
        );

        // Assert
        check(result.length).equals(2);
        check(result[0].chatId).equals('chat-a1');
        check(result[1].chatId).equals('chat-a2');
      });

      test('returns empty list for project with no archived chats',
          () async {
        // Arrange
        const projectRoot = '/test/project';

        final projectsIndex = ProjectsIndex(
          projects: {
            projectRoot: ProjectInfo(
              id: PersistenceService.generateProjectId(projectRoot),
              name: 'Test Project',
              worktrees: {
                projectRoot: const WorktreeInfo.primary(name: 'main'),
              },
            ),
          },
        );
        await persistence.saveProjectsIndex(projectsIndex);

        // Act
        final result = await persistence.getArchivedChats(
          projectRoot: projectRoot,
        );

        // Assert
        check(result).isEmpty();
      });
    });
  });
}

/// Test persistence service that uses a custom base directory.
class _TestPersistenceService extends PersistenceService {
  final String _testBaseDir;

  _TestPersistenceService(this._testBaseDir);

  String get _baseDir => '$_testBaseDir/.ccinsights';

  String _chatsDir(String projectId) => '$_baseDir/projects/$projectId/chats';

  String _chatJsonlPath(String projectId, String chatId) =>
      '${_chatsDir(projectId)}/$chatId.chat.jsonl';

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
  Future<void> removeChatFromIndex({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) return;

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) return;

    final updatedChats =
        worktree.chats.where((chat) => chat.chatId != chatId).toList();

    final updatedWorktree = worktree.copyWith(chats: updatedChats);
    final updatedProject = project.copyWith(
      worktrees: {
        ...project.worktrees,
        worktreePath: updatedWorktree,
      },
    );
    final updatedIndex = projectsIndex.copyWith(
      projects: {
        ...projectsIndex.projects,
        projectRoot: updatedProject,
      },
    );

    await saveProjectsIndex(updatedIndex);
  }

  @override
  Future<List<OutputEntry>> loadChatHistory(
    String projectId,
    String chatId,
  ) async {
    final path = _chatJsonlPath(projectId, chatId);
    final file = File(path);

    if (!await file.exists()) {
      return [];
    }

    final entries = <OutputEntry>[];
    final lines = await file.readAsLines();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;
      entries.add(OutputEntry.fromJson(json));
    }

    // Apply tool results (same logic as parent class)
    return _applyToolResults(entries);
  }

  List<OutputEntry> _applyToolResults(List<OutputEntry> entries) {
    final toolUseMap = <String, ToolUseOutputEntry>{};
    for (final entry in entries) {
      if (entry is ToolUseOutputEntry) {
        toolUseMap[entry.toolUseId] = entry;
      }
    }

    for (final entry in entries) {
      if (entry is ToolResultEntry) {
        final toolUse = toolUseMap[entry.toolUseId];
        if (toolUse != null) {
          toolUse.updateResult(entry.result, entry.isError);
        }
      }
    }

    return entries.where((e) => e is! ToolResultEntry).toList();
  }

  @override
  Future<void> deleteChat(String projectId, String chatId) async {
    final jsonlPath = _chatJsonlPath(projectId, chatId);
    final metaPath =
        '${_chatsDir(projectId)}/$chatId.meta.json';

    final jsonlFile = File(jsonlPath);
    if (await jsonlFile.exists()) {
      await jsonlFile.delete();
    }

    final metaFile = File(metaPath);
    if (await metaFile.exists()) {
      await metaFile.delete();
    }
  }

  /// Helper method to write entries to a JSONL file for testing.
  Future<void> writeJsonlEntries(
    String projectId,
    String chatId,
    List<OutputEntry> entries,
  ) async {
    final dir = Directory(_chatsDir(projectId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final path = _chatJsonlPath(projectId, chatId);
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer.writeln(jsonEncode(entry.toJson()));
    }
    await File(path).writeAsString(buffer.toString());
  }

  /// Helper to create empty chat files (jsonl + meta) on disk for testing.
  Future<void> createChatFiles(String projectId, String chatId) async {
    final dir = Directory(_chatsDir(projectId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File(_chatJsonlPath(projectId, chatId)).writeAsString('');
    await File(
      '${_chatsDir(projectId)}/$chatId.meta.json',
    ).writeAsString('{}');
  }

  /// Helper to check if chat files exist on disk.
  Future<bool> chatFilesExist(String projectId, String chatId) async {
    final jsonlExists =
        await File(_chatJsonlPath(projectId, chatId)).exists();
    final metaExists = await File(
      '${_chatsDir(projectId)}/$chatId.meta.json',
    ).exists();
    return jsonlExists || metaExists;
  }
}
