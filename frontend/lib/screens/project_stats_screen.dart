import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/output_entry.dart';
import '../models/project_stats.dart';
import '../models/timing_stats.dart';
import '../services/persistence_service.dart';
import '../services/stats_service.dart';
import '../state/selection_state.dart';

/// Screen showing project-wide statistics with drill-down navigation.
///
/// Shows aggregated cost and usage data with three levels:
/// 1. Project overview - all worktrees
/// 2. Worktree detail - all chats in a worktree
/// 3. Chat detail - per-model breakdown for a single chat
class ProjectStatsScreen extends StatefulWidget {
  const ProjectStatsScreen({super.key});

  @override
  State<ProjectStatsScreen> createState() => _ProjectStatsScreenState();
}

class _ProjectStatsScreenState extends State<ProjectStatsScreen> {
  _StatsView _currentView = _StatsView.project;
  WorktreeStats? _selectedWorktree;
  ChatStats? _selectedChat;
  ProjectStats? _projectStats;
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasLoadedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedOnce) {
      _hasLoadedOnce = true;
      _loadStats();
    }
  }

  /// Reloads stats, preserving the current drill-down selection if possible.
  Future<void> _refreshStats() async {
    final previousWorktreeName = _selectedWorktree?.worktreeName;
    final previousChatName = _selectedChat?.chatName;

    await _loadStats();

    if (_projectStats != null && previousWorktreeName != null) {
      final worktree = _projectStats!.worktrees
          .where((w) => w.worktreeName == previousWorktreeName)
          .firstOrNull;
      if (worktree != null) {
        _selectedWorktree = worktree;
        _currentView = _StatsView.worktree;

        if (previousChatName != null) {
          final chat = worktree.chats
              .where((c) => c.chatName == previousChatName)
              .firstOrNull;
          if (chat != null) {
            _selectedChat = chat;
            _currentView = _StatsView.chat;
          }
        }
      }
      setState(() {});
    }
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final selectionState = context.read<SelectionState>();
      final project = selectionState.project;
      final persistence = context.read<PersistenceService>();

      final projectId = PersistenceService.generateProjectId(project.data.repoRoot);
      final statsService = StatsService(persistence: persistence);
      final stats = await statsService.buildProjectStats(
        project: project,
        projectId: projectId,
      );

      if (mounted) {
        setState(() {
          _projectStats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load stats: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _selectWorktree(WorktreeStats worktree) {
    setState(() {
      _selectedWorktree = worktree;
      _currentView = _StatsView.worktree;
    });
  }

  void _selectChat(ChatStats chat) {
    setState(() {
      _selectedChat = chat;
      _currentView = _StatsView.chat;
    });
  }

  void _backToProject() {
    setState(() {
      _currentView = _StatsView.project;
      _selectedWorktree = null;
      _selectedChat = null;
    });
  }

  void _backToWorktree() {
    setState(() {
      _currentView = _StatsView.worktree;
      _selectedChat = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (_projectStats == null) {
      return const Center(child: Text('No project selected'));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildCurrentView(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    return switch (_currentView) {
      _StatsView.project => _ProjectOverviewView(
          stats: _projectStats!,
          onSelectWorktree: _selectWorktree,
          onRefresh: _refreshStats,
        ),
      _StatsView.worktree => _WorktreeDetailView(
          worktree: _selectedWorktree!,
          onBack: _backToProject,
          onSelectChat: _selectChat,
          onRefresh: _refreshStats,
        ),
      _StatsView.chat => _ChatDetailView(
          chat: _selectedChat!,
          onBack: _backToWorktree,
          onRefresh: _refreshStats,
        ),
    };
  }
}

enum _StatsView { project, worktree, chat }

// =============================================================================
// Project Overview
// =============================================================================

class _ProjectOverviewView extends StatelessWidget {
  final ProjectStats stats;
  final void Function(WorktreeStats) onSelectWorktree;
  final VoidCallback onRefresh;

  const _ProjectOverviewView({
    required this.stats,
    required this.onSelectWorktree,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              'Project Stats',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: onRefresh,
              tooltip: 'Refresh stats',
              visualDensity: VisualDensity.compact,
            ),
            const Spacer(),
            Text(
              stats.projectName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // KPI Summary Row
        _KPISummaryRow(
          cost: stats.totalCost,
          tokens: stats.totalTokens,
          time: stats.totalTiming.claudeWorkingDuration,
          chats: stats.totalChats,
          hasCostData: stats.worktrees.any((w) =>
              w.chats.any((c) => c.hasCostData)),
        ),
        const SizedBox(height: 24),

        // Cost by Model
        _ModelCostSection(
          modelUsage: stats.aggregatedModelUsage,
          backends: stats.worktrees.expand((w) => w.backends).toSet(),
        ),
        const SizedBox(height: 24),

        // Token Breakdown
        _TokenBreakdownSection(
          inputTokens: stats.aggregatedModelUsage.fold(
              0, (sum, m) => sum + m.inputTokens),
          outputTokens: stats.aggregatedModelUsage.fold(
              0, (sum, m) => sum + m.outputTokens),
          cacheReadTokens: stats.aggregatedModelUsage.fold(
              0, (sum, m) => sum + m.cacheReadTokens),
          cacheCreationTokens: stats.aggregatedModelUsage.fold(
              0, (sum, m) => sum + m.cacheCreationTokens),
        ),
        const SizedBox(height: 16),

        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),

        // Worktrees table
        Text(
          'WORKTREES',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        _WorktreesTable(
          worktrees: stats.worktrees,
          onSelectWorktree: onSelectWorktree,
        ),
      ],
    );
  }
}

// =============================================================================
// Worktree Detail View
// =============================================================================

class _WorktreeDetailView extends StatelessWidget {
  final WorktreeStats worktree;
  final VoidCallback onBack;
  final void Function(ChatStats) onSelectChat;
  final VoidCallback onRefresh;

  const _WorktreeDetailView({
    required this.worktree,
    required this.onBack,
    required this.onSelectChat,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with back button
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
              tooltip: 'Back to project overview',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                worktree.worktreeName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: onRefresh,
              tooltip: 'Refresh stats',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Text(
              'Worktree Stats',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // KPI Summary Row
        _KPISummaryRow(
          cost: worktree.totalCost,
          tokens: worktree.totalTokens,
          time: worktree.totalTiming.claudeWorkingDuration,
          chats: worktree.chatCount,
          hasCostData: worktree.chats.any((c) => c.hasCostData),
        ),
        const SizedBox(height: 24),

        // Cost by Model
        _ModelCostSection(
          modelUsage: worktree.aggregatedModelUsage,
          backends: worktree.backends,
        ),
        const SizedBox(height: 24),

        // Timing section
        _TimingSection(
          agentWorking: worktree.totalTiming.claudeWorkingDuration,
          userResponse: worktree.totalTiming.userResponseDuration,
          avgTurn: worktree.totalTiming.averageClaudeWorkingTime,
          avgResponse: worktree.totalTiming.averageUserResponseTime,
        ),
        const SizedBox(height: 16),

        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),

        // Chats table
        Text(
          'CHATS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        _ChatsTable(
          chats: worktree.chats,
          onSelectChat: onSelectChat,
        ),
      ],
    );
  }
}

// =============================================================================
// Chat Detail View
// =============================================================================

class _ChatDetailView extends StatelessWidget {
  final ChatStats chat;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  const _ChatDetailView({
    required this.chat,
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with back button
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
              tooltip: 'Back to worktree',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chat.chatName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: onRefresh,
              tooltip: 'Refresh stats',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Text(
              'Chat Stats',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // KPI Summary Row (3 cards for chat)
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                value: _formatCost(chat.totalCost,
                    hasCostData: chat.hasCostData),
                label: 'Cost',
                color: chat.hasCostData ? const Color(0xFF4CAF50) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                value: _formatTokenCount(chat.totalTokens),
                label: 'Tokens',
                color: const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                value: TimingStats.formatDuration(
                    chat.timing.claudeWorkingDuration),
                label: 'Agent Time',
                color: const Color(0xFFFF9800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Model Usage table
        Text(
          'MODEL USAGE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        _ModelUsageTable(
          modelUsage: chat.modelUsage,
          hasCostData: chat.hasCostData,
        ),
        const SizedBox(height: 24),

        // Timing section
        _TimingSection(
          agentWorking: chat.timing.claudeWorkingDuration,
          userResponse: chat.timing.userResponseDuration,
          avgTurn: chat.timing.averageClaudeWorkingTime,
          avgResponse: chat.timing.averageUserResponseTime,
          showCounts: true,
          workCycles: chat.timing.claudeWorkCount,
          userPrompts: chat.timing.userResponseCount,
        ),
        const SizedBox(height: 16),

        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),

        // Details metadata table
        Text(
          'DETAILS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        _ChatDetailsTable(chat: chat),
      ],
    );
  }
}

// =============================================================================
// Shared Components
// =============================================================================

class _KPISummaryRow extends StatelessWidget {
  final double cost;
  final int tokens;
  final Duration time;
  final int chats;
  final bool hasCostData;

  const _KPISummaryRow({
    required this.cost,
    required this.tokens,
    required this.time,
    required this.chats,
    required this.hasCostData,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            value: _formatCost(cost, hasCostData: hasCostData),
            label: 'Total Cost',
            color: hasCostData ? const Color(0xFF4CAF50) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            value: _formatTokenCount(tokens),
            label: 'Total Tokens',
            color: const Color(0xFF2196F3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            value: TimingStats.formatDuration(time),
            label: 'Agent Time',
            color: const Color(0xFFFF9800),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            value: chats.toString(),
            label: 'Chats',
            color: const Color(0xFFD0BCFF),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;

  const _SummaryCard({
    required this.value,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _ModelCostSection extends StatelessWidget {
  final List<ModelUsageInfo> modelUsage;
  final Set<String> backends;

  const _ModelCostSection({
    required this.modelUsage,
    required this.backends,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Calculate total for bar proportions
    final costModels = modelUsage.where((m) => m.costUsd > 0).toList();
    final total = costModels.fold(0.0, (sum, m) => sum + m.costUsd);
    final hasCodex = backends.contains('codex');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COST BY MODEL',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),

        // Stacked bar
        if (costModels.isNotEmpty && total > 0) ...[
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: colorScheme.surfaceContainerHighest,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: costModels
                    .map((model) => Expanded(
                          flex: math.max(
                            1,
                            (model.costUsd / total * 1000).round(),
                          ),
                          child: Container(
                            color: _getModelColor(model.modelName),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ...modelUsage.map((model) => _ModelLegendItem(
                  model: model,
                  hasCostData: model.costUsd > 0 || !hasCodex,
                )),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Costs are only calculated for models that support them (currently Claude models only).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
                fontSize: 11,
              ),
        ),
      ],
    );
  }
}

class _ModelLegendItem extends StatelessWidget {
  final ModelUsageInfo model;
  final bool hasCostData;

  const _ModelLegendItem({
    required this.model,
    required this.hasCostData,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _getModelColor(model.modelName),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${model.displayName} — ${hasCostData ? _formatCost(model.costUsd, hasCostData: true) : '${_formatTokenCount(model.totalTokens)} tokens'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _TokenBreakdownSection extends StatelessWidget {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;

  const _TokenBreakdownSection({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheCreationTokens,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOKEN BREAKDOWN',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _TokenItem(label: 'Input', value: inputTokens)),
            const SizedBox(width: 8),
            Expanded(child: _TokenItem(label: 'Output', value: outputTokens)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _TokenItem(label: 'Cache Read', value: cacheReadTokens)),
            const SizedBox(width: 8),
            Expanded(
                child: _TokenItem(
                    label: 'Cache Write', value: cacheCreationTokens)),
          ],
        ),
      ],
    );
  }
}

class _TokenItem extends StatelessWidget {
  final String label;
  final int value;

  const _TokenItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  letterSpacing: 0.3,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatTokenCount(value),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _TimingSection extends StatelessWidget {
  final Duration agentWorking;
  final Duration userResponse;
  final Duration avgTurn;
  final Duration avgResponse;
  final bool showCounts;
  final int workCycles;
  final int userPrompts;

  const _TimingSection({
    required this.agentWorking,
    required this.userResponse,
    required this.avgTurn,
    required this.avgResponse,
    this.showCounts = false,
    this.workCycles = 0,
    this.userPrompts = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TIMING',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TimingItem(
                label: 'Agent Working',
                value: TimingStats.formatDuration(agentWorking),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TimingItem(
                label: 'User Response',
                value: TimingStats.formatDuration(userResponse),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TimingItem(
                label: showCounts ? 'Work Cycles' : 'Avg Turn Time',
                value:
                    showCounts ? workCycles.toString() : TimingStats.formatDuration(avgTurn),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TimingItem(
                label: showCounts ? 'User Prompts' : 'Avg Response',
                value: showCounts
                    ? userPrompts.toString()
                    : TimingStats.formatDuration(avgResponse),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimingItem extends StatelessWidget {
  final String label;
  final String value;

  const _TimingItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  letterSpacing: 0.3,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

enum _SortDirection { ascending, descending }

class _WorktreesTable extends StatefulWidget {
  final List<WorktreeStats> worktrees;
  final void Function(WorktreeStats) onSelectWorktree;

  const _WorktreesTable({
    required this.worktrees,
    required this.onSelectWorktree,
  });

  @override
  State<_WorktreesTable> createState() => _WorktreesTableState();
}

class _WorktreesTableState extends State<_WorktreesTable> {
  String? _sortColumn;
  _SortDirection _sortDirection = _SortDirection.descending;

  List<WorktreeStats> get _sortedWorktrees {
    if (_sortColumn == null) return widget.worktrees;

    final sorted = List<WorktreeStats>.from(widget.worktrees);
    final asc = _sortDirection == _SortDirection.ascending;

    sorted.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'Worktree':
          cmp = a.worktreeName.toLowerCase().compareTo(b.worktreeName.toLowerCase());
        case 'Chats':
          cmp = a.chatCount.compareTo(b.chatCount);
        case 'Tokens':
          cmp = a.totalTokens.compareTo(b.totalTokens);
        case 'Cost':
          cmp = a.totalCost.compareTo(b.totalCost);
        case 'Time':
          cmp = a.totalTiming.claudeWorkingMs.compareTo(b.totalTiming.claudeWorkingMs);
        default:
          cmp = 0;
      }
      return asc ? cmp : -cmp;
    });
    return sorted;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortDirection = _sortDirection == _SortDirection.ascending
            ? _SortDirection.descending
            : _SortDirection.ascending;
      } else {
        _sortColumn = column;
        _sortDirection = column == 'Worktree'
            ? _SortDirection.ascending
            : _SortDirection.descending;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sorted = _sortedWorktrees;

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
        6: FixedColumnWidth(24),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            _SortableTableHeader('Worktree',
                sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _TableHeader('Backend'),
            _SortableTableHeader('Chats',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _SortableTableHeader('Tokens',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _SortableTableHeader('Cost',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _SortableTableHeader('Time',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            const SizedBox(),
          ],
        ),
        ...sorted.map((worktree) => TableRow(
              children: [
                _WorktreeNameCell(worktree: worktree),
                _BackendBadgesCell(backends: worktree.backends),
                _TableCell(worktree.chatCount.toString(), align: TextAlign.right),
                _TableCell(_formatTokenCount(worktree.totalTokens),
                    align: TextAlign.right, mono: true),
                _TableCell(
                  _formatCost(worktree.totalCost,
                      hasCostData: worktree.chats.any((c) => c.hasCostData)),
                  align: TextAlign.right,
                  mono: true,
                ),
                _TableCell(
                  TimingStats.formatDuration(
                      worktree.totalTiming.claudeWorkingDuration),
                  align: TextAlign.right,
                  mono: true,
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: InkWell(
                    onTap: () => widget.onSelectWorktree(worktree),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ],
            )),
      ],
    );
  }
}

class _WorktreeNameCell extends StatelessWidget {
  final WorktreeStats worktree;

  const _WorktreeNameCell({required this.worktree});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  worktree.worktreeName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (worktree.isDeleted) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF44336).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFFF44336).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'deleted',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFF44336),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            worktree.isDeleted
                ? 'worktree no longer exists'
                : worktree.worktreePath!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: colorScheme.outline,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BackendBadgesCell extends StatelessWidget {
  final Set<String> backends;

  const _BackendBadgesCell({required this.backends});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: backends.map((backend) => _BackendBadge(backend: backend)).toList(),
      ),
    );
  }
}

class _BackendBadge extends StatelessWidget {
  final String backend;

  const _BackendBadge({required this.backend});

  @override
  Widget build(BuildContext context) {
    final isClaude = backend == 'claude';
    final color = isClaude ? const Color(0xFFD0BCFF) : const Color(0xFF00BCD4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isClaude ? 'Claude' : 'Codex',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class _ChatsTable extends StatefulWidget {
  final List<ChatStats> chats;
  final void Function(ChatStats) onSelectChat;

  const _ChatsTable({
    required this.chats,
    required this.onSelectChat,
  });

  @override
  State<_ChatsTable> createState() => _ChatsTableState();
}

class _ChatsTableState extends State<_ChatsTable> {
  String? _sortColumn;
  _SortDirection _sortDirection = _SortDirection.descending;

  List<ChatStats> get _sortedChats {
    if (_sortColumn == null) return widget.chats;

    final sorted = List<ChatStats>.from(widget.chats);
    final asc = _sortDirection == _SortDirection.ascending;

    sorted.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'Chat':
          cmp = a.chatName.toLowerCase().compareTo(b.chatName.toLowerCase());
        case 'Tokens':
          cmp = a.totalTokens.compareTo(b.totalTokens);
        case 'Cost':
          cmp = a.totalCost.compareTo(b.totalCost);
        case 'Agent Time':
          cmp = a.timing.claudeWorkingMs.compareTo(b.timing.claudeWorkingMs);
        case 'Date':
          cmp = a.timestamp.compareTo(b.timestamp);
        default:
          cmp = 0;
      }
      return asc ? cmp : -cmp;
    });
    return sorted;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortDirection = _sortDirection == _SortDirection.ascending
            ? _SortDirection.descending
            : _SortDirection.ascending;
      } else {
        _sortColumn = column;
        _sortDirection = column == 'Chat'
            ? _SortDirection.ascending
            : _SortDirection.descending;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sorted = _sortedChats;

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
        6: FixedColumnWidth(24),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            _SortableTableHeader('Chat',
                sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _TableHeader('Backend'),
            _SortableTableHeader('Tokens',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _SortableTableHeader('Cost',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _SortableTableHeader('Agent Time',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            _SortableTableHeader('Date',
                align: TextAlign.right, sortColumn: _sortColumn, sortDirection: _sortDirection, onSort: _onSort),
            const SizedBox(),
          ],
        ),
        ...sorted.map((chat) => TableRow(
              children: [
                _ChatNameCell(chat: chat),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _BackendBadge(backend: chat.backend),
                  ),
                ),
                _TableCell(_formatTokenCount(chat.totalTokens),
                    align: TextAlign.right, mono: true),
                _TableCell(
                  _formatCost(chat.totalCost, hasCostData: chat.hasCostData),
                  align: TextAlign.right,
                  mono: true,
                ),
                _TableCell(
                  TimingStats.formatDuration(
                      chat.timing.claudeWorkingDuration),
                  align: TextAlign.right,
                  mono: true,
                ),
                _TableCell(
                  _formatRelativeTime(chat.timestamp, isActive: chat.isActive),
                  align: TextAlign.right,
                  mono: true,
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: InkWell(
                    onTap: () => widget.onSelectChat(chat),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ],
            )),
      ],
    );
  }
}

class _ChatNameCell extends StatelessWidget {
  final ChatStats chat;

  const _ChatNameCell({required this.chat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              chat.chatName,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.isActive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'active',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelUsageTable extends StatelessWidget {
  final List<ModelUsageInfo> modelUsage;
  final bool hasCostData;

  const _ModelUsageTable({
    required this.modelUsage,
    required this.hasCostData,
  });

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            _TableHeader('Model'),
            _TableHeader('Input', align: TextAlign.right),
            _TableHeader('Output', align: TextAlign.right),
            _TableHeader('Cache Read', align: TextAlign.right),
            _TableHeader('Cache Write', align: TextAlign.right),
            _TableHeader('Cost', align: TextAlign.right),
          ],
        ),
        ...modelUsage.map((model) => TableRow(
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: _getModelColor(model.modelName),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(model.displayName),
                      ],
                    ),
                  ),
                ),
                _TableCell(_formatTokenCount(model.inputTokens),
                    align: TextAlign.right, mono: true),
                _TableCell(_formatTokenCount(model.outputTokens),
                    align: TextAlign.right, mono: true),
                _TableCell(_formatTokenCount(model.cacheReadTokens),
                    align: TextAlign.right, mono: true),
                _TableCell(_formatTokenCount(model.cacheCreationTokens),
                    align: TextAlign.right, mono: true),
                _TableCell(
                  _formatCost(model.costUsd, hasCostData: hasCostData),
                  align: TextAlign.right,
                  mono: true,
                ),
              ],
            )),
      ],
    );
  }
}

class _ChatDetailsTable extends StatelessWidget {
  final ChatStats chat;

  const _ChatDetailsTable({required this.chat});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(140),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          _TableCell('Backend', color: colorScheme.outline),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _BackendBadge(backend: chat.backend),
            ),
          ),
        ]),
        TableRow(children: [
          _TableCell('Worktree', color: colorScheme.outline),
          _TableCell(chat.worktree),
        ]),
        TableRow(children: [
          _TableCell('Status', color: colorScheme.outline),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: chat.isActive
                  ? Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'active',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF4CAF50),
                        ),
                      ),
                    )
                  : Text(
                      'Closed (${_formatRelativeTime(chat.timestamp, isActive: false)})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ),
          ),
        ]),
        TableRow(children: [
          _TableCell('Context Window', color: colorScheme.outline),
          _TableCell(
            chat.modelUsage.isNotEmpty
                ? _formatNumber(chat.modelUsage.first.contextWindow)
                : '—',
            mono: true,
          ),
        ]),
        TableRow(children: [
          _TableCell('Avg Turn', color: colorScheme.outline),
          _TableCell(
            TimingStats.formatDuration(
                chat.timing.averageClaudeWorkingTime),
            mono: true,
          ),
        ]),
        TableRow(children: [
          _TableCell('Avg Response', color: colorScheme.outline),
          _TableCell(
            TimingStats.formatDuration(chat.timing.averageUserResponseTime),
            mono: true,
          ),
        ]),
      ],
    );
  }
}

class _SortableTableHeader extends StatelessWidget {
  final String text;
  final TextAlign align;
  final String? sortColumn;
  final _SortDirection sortDirection;
  final void Function(String) onSort;

  const _SortableTableHeader(
    this.text, {
    this.align = TextAlign.left,
    required this.sortColumn,
    required this.sortDirection,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = sortColumn == text;
    final color = isActive ? colorScheme.onSurface : colorScheme.outline;

    final label = Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            letterSpacing: 0.5,
            fontWeight: isActive ? FontWeight.w600 : null,
          ),
    );

    final arrow = isActive
        ? Icon(
            sortDirection == _SortDirection.ascending
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            size: 12,
            color: color,
          )
        : null;

    final children = align == TextAlign.right
        ? [if (arrow != null) arrow, label]
        : [label, if (arrow != null) arrow];

    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: InkWell(
        onTap: () => onSort(text),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: align == TextAlign.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: children.map<Widget>((c) {
              if (c is Icon) {
                return Padding(
                  padding: align == TextAlign.right
                      ? const EdgeInsets.only(right: 2)
                      : const EdgeInsets.only(left: 2),
                  child: c,
                );
              }
              return c;
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  final TextAlign align;

  const _TableHeader(this.text, {this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
              letterSpacing: 0.5,
            ),
        textAlign: align,
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final TextAlign align;
  final bool mono;
  final Color? color;

  const _TableCell(
    this.text, {
    this.align = TextAlign.left,
    this.mono = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: mono ? 'JetBrains Mono' : null,
              fontSize: mono ? 11 : null,
              color: color,
            ),
        textAlign: align,
      ),
    );
  }
}

// =============================================================================
// Formatting Helpers
// =============================================================================

String _formatTokenCount(int tokens) {
  if (tokens >= 1000000) {
    return '${(tokens / 1000000).toStringAsFixed(1)}M';
  } else if (tokens >= 1000) {
    return '${(tokens / 1000).toStringAsFixed(0)}K';
  }
  return tokens.toString();
}

String _formatCost(double cost, {bool hasCostData = true}) {
  if (!hasCostData) return '—';
  if (cost >= 0.01 || cost == 0) {
    return '\$${cost.toStringAsFixed(2)}';
  }
  return '\$${cost.toStringAsFixed(4)}';
}

String _formatNumber(int value) {
  if (value < 1000) return value.toString();

  final str = value.toString();
  final buffer = StringBuffer();
  final length = str.length;

  for (var i = 0; i < length; i++) {
    if (i > 0 && (length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(str[i]);
  }

  return buffer.toString();
}

String _formatRelativeTime(String isoTimestamp, {required bool isActive}) {
  if (isActive) return 'now';
  if (isoTimestamp.trim().isEmpty) return '—';

  late final DateTime timestamp;
  try {
    timestamp = DateTime.parse(isoTimestamp);
  } catch (_) {
    return '—';
  }
  final now = DateTime.now().toUtc();
  final diff = now.difference(timestamp);

  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  } else if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  } else if (diff.inDays == 1) {
    return 'yesterday';
  } else if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  } else {
    // More than a week, show date
    return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
  }
}

Color _getModelColor(String modelName) {
  final lower = modelName.toLowerCase();
  // Claude models
  if (lower.contains('opus')) {
    return const Color(0xFFD0BCFF); // purple
  } else if (lower.contains('sonnet')) {
    return const Color(0xFFFF9800); // orange
  } else if (lower.contains('haiku')) {
    return const Color(0xFF69F0AE); // green
  }
  // GPT/Codex models - distinguish by variant
  if (lower.contains('codex-mini')) {
    return const Color(0xFF4DD0E1); // cyan
  } else if (lower.contains('codex-max')) {
    return const Color(0xFFFF5252); // red
  } else if (lower.contains('codex')) {
    return const Color(0xFF00BCD4); // teal
  } else if (lower.startsWith('gpt-')) {
    return const Color(0xFF42A5F5); // blue
  }
  // Unknown
  return const Color(0xFF9E9E9E); // grey
}
