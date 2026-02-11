import 'dart:io';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/cost_tracking.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/services/stats_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  late Directory tempDir;
  late PersistenceService persistence;
  late StatsService statsService;
  late String projectId;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    // Set up test config isolation
    cleanupConfig = await setupTestConfig();

    // Create temp directory for this test
    tempDir = await Directory.systemTemp.createTemp('stats_service_test_');
    persistence = PersistenceService();
    PersistenceService.setBaseDir(tempDir.path);

    projectId = PersistenceService.generateProjectId('/test/project');
    statsService = StatsService(persistence: persistence);

    // Initialize RuntimeConfig for ChatState
    RuntimeConfig.resetForTesting();
    RuntimeConfig.initialize([]);
  });

  tearDown(() async {
    await cleanupConfig();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StatsService.buildProjectStats', () {
    test('returns empty stats for empty project with no tracking data',
        () async {
      // Arrange
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      check(stats.projectName).equals('Test Project');
      check(stats.worktrees).isEmpty();
      check(stats.totalCost).isCloseTo(0.0, 0.0001);
      check(stats.totalTokens).equals(0);
    });

    test('includes historical entries from tracking.jsonl', () async {
      // Arrange
      await persistence.ensureDirectories(projectId);

      // Write historical entries
      final entry1 = CostTrackingEntry(
        worktree: 'main',
        chatName: 'Historical Chat 1',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.05,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, entry1);

      final entry2 = CostTrackingEntry(
        worktree: 'main',
        chatName: 'Historical Chat 2',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 2000,
            outputTokens: 1000,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.10,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, entry2);

      // Create empty project
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      check(stats.worktrees.length).equals(1);
      final worktree = stats.worktrees.first;
      check(worktree.worktreeName).equals('main');
      check(worktree.chats.length).equals(2);
      check(worktree.chats[0].isActive).isFalse();
      check(worktree.chats[1].isActive).isFalse();
      check(worktree.totalCost).isCloseTo(0.15, 0.0001);
    });

    test('includes live chat data from project state', () async {
      // Arrange
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );

      // Create a chat with model usage
      final chatData = ChatData.create(
        name: 'Live Chat',
        worktreeRoot: '/test/project',
      );
      final chat = ChatState(chatData);
      chat.updateCumulativeUsage(
        usage: const UsageInfo(
          inputTokens: 500,
          outputTokens: 250,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.025,
        ),
        totalCostUsd: 0.025,
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 500,
            outputTokens: 250,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.025,
            contextWindow: 200000,
          ),
        ],
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
        chats: [chat],
      );

      final project = ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      check(stats.worktrees.length).equals(1);
      final worktree = stats.worktrees.first;
      check(worktree.worktreeName).equals('project');
      check(worktree.chats.length).equals(1);
      check(worktree.chats.first.chatName).equals('Live Chat');
      check(worktree.chats.first.isActive).isTrue();
      check(worktree.chats.first.backend).equals('claude');
      check(worktree.totalCost).isCloseTo(0.025, 0.0001);
    });

    test('merges historical and live data for same worktree', () async {
      // Arrange
      await persistence.ensureDirectories(projectId);

      // Write historical entry
      final historicalEntry = CostTrackingEntry(
        worktree: 'project',
        chatName: 'Historical Chat',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.05,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, historicalEntry);

      // Create project with live chat
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );

      final chatData = ChatData.create(
        name: 'Live Chat',
        worktreeRoot: '/test/project',
      );
      final chat = ChatState(chatData);
      chat.updateCumulativeUsage(
        usage: const UsageInfo(
          inputTokens: 500,
          outputTokens: 250,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.025,
        ),
        totalCostUsd: 0.025,
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 500,
            outputTokens: 250,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.025,
            contextWindow: 200000,
          ),
        ],
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
        chats: [chat],
      );

      final project = ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      check(stats.worktrees.length).equals(1);
      final worktree = stats.worktrees.first;
      check(worktree.worktreeName).equals('project');
      check(worktree.chats.length).equals(2);

      // Find live and historical chats
      final liveChat = worktree.chats.firstWhere((c) => c.isActive);
      final historicalChat = worktree.chats.firstWhere((c) => !c.isActive);

      check(liveChat.chatName).equals('Live Chat');
      check(historicalChat.chatName).equals('Historical Chat');
      check(worktree.totalCost).isCloseTo(0.075, 0.0001);
    });

    test('marks deleted worktrees with null path', () async {
      // Arrange
      await persistence.ensureDirectories(projectId);

      // Write historical entries for a deleted worktree
      final entry1 = CostTrackingEntry(
        worktree: 'deleted-feature',
        chatName: 'Old Chat 1',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.05,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, entry1);

      // Create project with only live worktree
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      check(stats.worktrees.length).equals(1);
      final deletedWorktree = stats.worktrees.first;
      check(deletedWorktree.worktreeName).equals('deleted-feature');
      check(deletedWorktree.worktreePath).isNull();
      check(deletedWorktree.isDeleted).isTrue();
    });

    test('correctly identifies backends per worktree', () async {
      // Arrange
      await persistence.ensureDirectories(projectId);

      // Write historical entries with different backends
      final claudeEntry = CostTrackingEntry(
        worktree: 'project',
        chatName: 'Claude Chat',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.05,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, claudeEntry);

      final codexEntry = CostTrackingEntry(
        worktree: 'project',
        chatName: 'Codex Chat',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'codex',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'gpt-4',
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.0,
            contextWindow: 128000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, codexEntry);

      // Create empty project
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      check(stats.worktrees.length).equals(1);
      final worktree = stats.worktrees.first;
      check(worktree.backends.length).equals(2);
      check(worktree.backends.contains('claude')).isTrue();
      check(worktree.backends.contains('codex')).isTrue();
    });

    test('sets isActive true for live chats, false for historical', () async {
      // Arrange
      await persistence.ensureDirectories(projectId);

      // Historical entry
      final historicalEntry = CostTrackingEntry(
        worktree: 'project',
        chatName: 'Historical',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, historicalEntry);

      // Live chat
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );
      final chatData = ChatData.create(
        name: 'Live',
        worktreeRoot: '/test/project',
      );
      final chat = ChatState(chatData);
      chat.updateCumulativeUsage(
        usage: const UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.01,
        ),
        totalCostUsd: 0.01,
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project',
          isPrimary: true,
          branch: 'main',
        ),
        chats: [chat],
      );
      final project = ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      final worktree = stats.worktrees.first;
      check(worktree.chats.length).equals(2);

      final liveChat = worktree.chats.firstWhere((c) => c.chatName == 'Live');
      final historicalChat =
          worktree.chats.firstWhere((c) => c.chatName == 'Historical');

      check(liveChat.isActive).isTrue();
      check(historicalChat.isActive).isFalse();
    });

    test('sorts worktrees: active first, then deleted', () async {
      // Arrange
      await persistence.ensureDirectories(projectId);

      // Historical entries for deleted worktrees
      final deleted1 = CostTrackingEntry(
        worktree: 'zeta-deleted',
        chatName: 'Old Chat',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, deleted1);

      final deleted2 = CostTrackingEntry(
        worktree: 'alpha-deleted',
        chatName: 'Old Chat',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        backend: 'claude',
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
      );
      await persistence.appendCostTracking(projectId, deleted2);

      // Live worktrees with chats
      const projectData = ProjectData(
        name: 'Test Project',
        repoRoot: '/test/project',
      );

      // Create chats for live worktrees
      final zetaChat = ChatState(
        ChatData.create(
          name: 'Zeta Chat',
          worktreeRoot: '/test/project/zeta-live',
        ),
      );
      zetaChat.updateCumulativeUsage(
        usage: const UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.01,
        ),
        totalCostUsd: 0.01,
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
      );

      final alphaChat = ChatState(
        ChatData.create(
          name: 'Alpha Chat',
          worktreeRoot: '/test/project/alpha-live',
        ),
      );
      alphaChat.updateCumulativeUsage(
        usage: const UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.01,
        ),
        totalCostUsd: 0.01,
        modelUsage: [
          const ModelUsageInfo(
            modelName: 'claude-opus-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project/zeta-live',
          isPrimary: true,
          branch: 'main',
        ),
        chats: [zetaChat],
      );
      final linkedWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/project/alpha-live',
          isPrimary: false,
          branch: 'feature',
        ),
        chats: [alphaChat],
      );
      final project = ProjectState(
        projectData,
        primaryWorktree,
        linkedWorktrees: [linkedWorktree],
        autoValidate: false,
        watchFilesystem: false,
      );

      // Act
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      // Assert
      check(stats.worktrees.length).equals(4);

      // First two should be active (alphabetical)
      check(stats.worktrees[0].worktreeName).equals('alpha-live');
      check(stats.worktrees[0].isDeleted).isFalse();
      check(stats.worktrees[1].worktreeName).equals('zeta-live');
      check(stats.worktrees[1].isDeleted).isFalse();

      // Last two should be deleted (alphabetical)
      check(stats.worktrees[2].worktreeName).equals('alpha-deleted');
      check(stats.worktrees[2].isDeleted).isTrue();
      check(stats.worktrees[3].worktreeName).equals('zeta-deleted');
      check(stats.worktrees[3].isDeleted).isTrue();
    });
  });
}
