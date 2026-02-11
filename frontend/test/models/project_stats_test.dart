import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/project_stats.dart';
import 'package:cc_insights_v2/models/timing_stats.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatStats', () {
    test('totalCost sums model usage costs', () {
      // Arrange
      const chat = ChatStats(
        chatName: 'Test Chat',
        worktree: 'main',
        backend: 'claude',
        modelUsage: [
          ModelUsageInfo(
            modelName: 'claude-sonnet-4-5-20250929',
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.05,
            contextWindow: 200000,
          ),
          ModelUsageInfo(
            modelName: 'claude-haiku-4-5-20251001',
            inputTokens: 500,
            outputTokens: 250,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
        timing: TimingStats.zero(),
        timestamp: '2026-02-11T10:00:00Z',
        isActive: true,
      );

      // Act & Assert
      check(chat.totalCost).isCloseTo(0.06, 0.0001);
    });

    test('totalTokens sums model usage tokens', () {
      // Arrange
      const chat = ChatStats(
        chatName: 'Test Chat',
        worktree: 'main',
        backend: 'claude',
        modelUsage: [
          ModelUsageInfo(
            modelName: 'claude-sonnet-4-5-20250929',
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.05,
            contextWindow: 200000,
          ),
          ModelUsageInfo(
            modelName: 'claude-haiku-4-5-20251001',
            inputTokens: 500,
            outputTokens: 250,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
            contextWindow: 200000,
          ),
        ],
        timing: TimingStats.zero(),
        timestamp: '2026-02-11T10:00:00Z',
        isActive: true,
      );

      // Act & Assert
      check(chat.totalTokens).equals(2250); // 1000 + 500 + 500 + 250
    });

    test('hasCostData returns false for codex', () {
      // Arrange
      const claudeChat = ChatStats(
        chatName: 'Claude Chat',
        worktree: 'main',
        backend: 'claude',
        modelUsage: [],
        timing: TimingStats.zero(),
        timestamp: '2026-02-11T10:00:00Z',
        isActive: true,
      );

      const codexChat = ChatStats(
        chatName: 'Codex Chat',
        worktree: 'main',
        backend: 'codex',
        modelUsage: [],
        timing: TimingStats.zero(),
        timestamp: '2026-02-11T10:00:00Z',
        isActive: true,
      );

      // Act & Assert
      check(claudeChat.hasCostData).isTrue();
      check(codexChat.hasCostData).isFalse();
    });
  });

  group('WorktreeStats', () {
    test('totalCost only sums chats with hasCostData', () {
      // Arrange
      const worktree = WorktreeStats(
        worktreeName: 'main',
        worktreePath: '/path/to/worktree',
        chats: [
          ChatStats(
            chatName: 'Claude Chat',
            worktree: 'main',
            backend: 'claude',
            modelUsage: [
              ModelUsageInfo(
                modelName: 'claude-sonnet-4-5-20250929',
                inputTokens: 1000,
                outputTokens: 500,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                costUsd: 0.05,
                contextWindow: 200000,
              ),
            ],
            timing: TimingStats.zero(),
            timestamp: '2026-02-11T10:00:00Z',
            isActive: true,
          ),
          ChatStats(
            chatName: 'Codex Chat',
            worktree: 'main',
            backend: 'codex',
            modelUsage: [
              ModelUsageInfo(
                modelName: 'gpt-4',
                inputTokens: 500,
                outputTokens: 250,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                costUsd: 0.00,
                contextWindow: 128000,
              ),
            ],
            timing: TimingStats.zero(),
            timestamp: '2026-02-11T11:00:00Z',
            isActive: true,
          ),
        ],
        backends: {'claude', 'codex'},
      );

      // Act & Assert
      // Only the Claude chat should be included in cost
      check(worktree.totalCost).equals(0.05);
    });

    test('totalTokens includes all chats including codex', () {
      // Arrange
      const worktree = WorktreeStats(
        worktreeName: 'main',
        worktreePath: '/path/to/worktree',
        chats: [
          ChatStats(
            chatName: 'Claude Chat',
            worktree: 'main',
            backend: 'claude',
            modelUsage: [
              ModelUsageInfo(
                modelName: 'claude-sonnet-4-5-20250929',
                inputTokens: 1000,
                outputTokens: 500,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                costUsd: 0.05,
                contextWindow: 200000,
              ),
            ],
            timing: TimingStats.zero(),
            timestamp: '2026-02-11T10:00:00Z',
            isActive: true,
          ),
          ChatStats(
            chatName: 'Codex Chat',
            worktree: 'main',
            backend: 'codex',
            modelUsage: [
              ModelUsageInfo(
                modelName: 'gpt-4',
                inputTokens: 500,
                outputTokens: 250,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                costUsd: 0.00,
                contextWindow: 128000,
              ),
            ],
            timing: TimingStats.zero(),
            timestamp: '2026-02-11T11:00:00Z',
            isActive: true,
          ),
        ],
        backends: {'claude', 'codex'},
      );

      // Act & Assert
      check(worktree.totalTokens).equals(2250); // 1000 + 500 + 500 + 250
    });

    test('totalTiming merges all chat timings', () {
      // Arrange
      const worktree = WorktreeStats(
        worktreeName: 'main',
        worktreePath: '/path/to/worktree',
        chats: [
          ChatStats(
            chatName: 'Chat 1',
            worktree: 'main',
            backend: 'claude',
            modelUsage: [],
            timing: TimingStats(
              claudeWorkingMs: 5000,
              userResponseMs: 2000,
              claudeWorkCount: 2,
              userResponseCount: 1,
            ),
            timestamp: '2026-02-11T10:00:00Z',
            isActive: true,
          ),
          ChatStats(
            chatName: 'Chat 2',
            worktree: 'main',
            backend: 'claude',
            modelUsage: [],
            timing: TimingStats(
              claudeWorkingMs: 3000,
              userResponseMs: 1000,
              claudeWorkCount: 1,
              userResponseCount: 1,
            ),
            timestamp: '2026-02-11T11:00:00Z',
            isActive: false,
          ),
        ],
        backends: {'claude'},
      );

      // Act
      final totalTiming = worktree.totalTiming;

      // Assert
      check(totalTiming.claudeWorkingMs).equals(8000);
      check(totalTiming.userResponseMs).equals(3000);
      check(totalTiming.claudeWorkCount).equals(3);
      check(totalTiming.userResponseCount).equals(2);
    });

    test('aggregatedModelUsage merges entries by model name', () {
      // Arrange
      const worktree = WorktreeStats(
        worktreeName: 'main',
        worktreePath: '/path/to/worktree',
        chats: [
          ChatStats(
            chatName: 'Chat 1',
            worktree: 'main',
            backend: 'claude',
            modelUsage: [
              ModelUsageInfo(
                modelName: 'claude-sonnet-4-5-20250929',
                inputTokens: 1000,
                outputTokens: 500,
                cacheReadTokens: 100,
                cacheCreationTokens: 50,
                costUsd: 0.05,
                contextWindow: 200000,
              ),
            ],
            timing: TimingStats.zero(),
            timestamp: '2026-02-11T10:00:00Z',
            isActive: true,
          ),
          ChatStats(
            chatName: 'Chat 2',
            worktree: 'main',
            backend: 'claude',
            modelUsage: [
              ModelUsageInfo(
                modelName: 'claude-sonnet-4-5-20250929',
                inputTokens: 500,
                outputTokens: 250,
                cacheReadTokens: 50,
                cacheCreationTokens: 25,
                costUsd: 0.025,
                contextWindow: 200000,
              ),
            ],
            timing: TimingStats.zero(),
            timestamp: '2026-02-11T11:00:00Z',
            isActive: false,
          ),
        ],
        backends: {'claude'},
      );

      // Act
      final aggregated = worktree.aggregatedModelUsage;

      // Assert
      check(aggregated).length.equals(1);
      check(aggregated[0].modelName).equals('claude-sonnet-4-5-20250929');
      check(aggregated[0].inputTokens).equals(1500);
      check(aggregated[0].outputTokens).equals(750);
      check(aggregated[0].cacheReadTokens).equals(150);
      check(aggregated[0].cacheCreationTokens).equals(75);
      check(aggregated[0].costUsd).isCloseTo(0.075, 0.0001);
      check(aggregated[0].contextWindow).equals(200000);
    });

    test('isDeleted returns true when path is null', () {
      // Arrange
      const deletedWorktree = WorktreeStats(
        worktreeName: 'feature-x',
        worktreePath: null,
        chats: [],
        backends: {},
      );

      const activeWorktree = WorktreeStats(
        worktreeName: 'main',
        worktreePath: '/path/to/worktree',
        chats: [],
        backends: {},
      );

      // Act & Assert
      check(deletedWorktree.isDeleted).isTrue();
      check(activeWorktree.isDeleted).isFalse();
    });
  });

  group('ProjectStats', () {
    test('aggregates correctly across worktrees', () {
      // Arrange
      const project = ProjectStats(
        projectName: 'Test Project',
        worktrees: [
          WorktreeStats(
            worktreeName: 'main',
            worktreePath: '/path/to/main',
            chats: [
              ChatStats(
                chatName: 'Chat 1',
                worktree: 'main',
                backend: 'claude',
                modelUsage: [
                  ModelUsageInfo(
                    modelName: 'claude-sonnet-4-5-20250929',
                    inputTokens: 1000,
                    outputTokens: 500,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    costUsd: 0.05,
                    contextWindow: 200000,
                  ),
                ],
                timing: TimingStats(
                  claudeWorkingMs: 5000,
                  userResponseMs: 2000,
                  claudeWorkCount: 2,
                  userResponseCount: 1,
                ),
                timestamp: '2026-02-11T10:00:00Z',
                isActive: true,
              ),
            ],
            backends: {'claude'},
          ),
          WorktreeStats(
            worktreeName: 'feature-a',
            worktreePath: '/path/to/feature-a',
            chats: [
              ChatStats(
                chatName: 'Chat 2',
                worktree: 'feature-a',
                backend: 'claude',
                modelUsage: [
                  ModelUsageInfo(
                    modelName: 'claude-haiku-4-5-20251001',
                    inputTokens: 500,
                    outputTokens: 250,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    costUsd: 0.01,
                    contextWindow: 200000,
                  ),
                ],
                timing: TimingStats(
                  claudeWorkingMs: 3000,
                  userResponseMs: 1000,
                  claudeWorkCount: 1,
                  userResponseCount: 1,
                ),
                timestamp: '2026-02-11T11:00:00Z',
                isActive: true,
              ),
            ],
            backends: {'claude'},
          ),
        ],
      );

      // Act & Assert
      check(project.totalCost).isCloseTo(0.06, 0.0001);
      check(project.totalTokens).equals(2250); // 1000 + 500 + 500 + 250
      check(project.totalChats).equals(2);
      check(project.totalTiming.claudeWorkingMs).equals(8000);
      check(project.totalTiming.userResponseMs).equals(3000);
      check(project.totalTiming.claudeWorkCount).equals(3);
      check(project.totalTiming.userResponseCount).equals(2);
      check(project.aggregatedModelUsage).length.equals(2);
    });
  });

  group('mergeModelUsage', () {
    test('combines same-model entries', () {
      // Arrange
      const entries = [
        ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        ),
        ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 500,
          outputTokens: 250,
          cacheReadTokens: 50,
          cacheCreationTokens: 25,
          costUsd: 0.025,
          contextWindow: 200000,
        ),
      ];

      // Act
      final merged = mergeModelUsage(entries);

      // Assert
      check(merged).length.equals(1);
      check(merged[0].modelName).equals('claude-sonnet-4-5-20250929');
      check(merged[0].inputTokens).equals(1500);
      check(merged[0].outputTokens).equals(750);
      check(merged[0].cacheReadTokens).equals(150);
      check(merged[0].cacheCreationTokens).equals(75);
      check(merged[0].costUsd).isCloseTo(0.075, 0.0001);
      check(merged[0].contextWindow).equals(200000);
    });

    test('preserves distinct models', () {
      // Arrange
      const entries = [
        ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.05,
          contextWindow: 200000,
        ),
        ModelUsageInfo(
          modelName: 'claude-haiku-4-5-20251001',
          inputTokens: 500,
          outputTokens: 250,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.01,
          contextWindow: 200000,
        ),
      ];

      // Act
      final merged = mergeModelUsage(entries);

      // Assert
      check(merged).length.equals(2);
      final modelNames = merged.map((m) => m.modelName).toSet();
      check(modelNames)
          .deepEquals({'claude-sonnet-4-5-20250929', 'claude-haiku-4-5-20251001'});
    });

    test('handles empty list', () {
      // Act
      final merged = mergeModelUsage([]);

      // Assert
      check(merged).isEmpty();
    });

    test('takes maximum context window when merging', () {
      // Arrange
      const entries = [
        ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.05,
          contextWindow: 200000,
        ),
        ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 500,
          outputTokens: 250,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.025,
          contextWindow: 300000,
        ),
      ];

      // Act
      final merged = mergeModelUsage(entries);

      // Assert
      check(merged).length.equals(1);
      check(merged[0].contextWindow).equals(300000);
    });
  });
}
