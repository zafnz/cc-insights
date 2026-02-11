import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../panels/conversation_panel.dart';
import '../state/selection_state.dart';
import '../testing/replay_conversation_provider.dart';

/// A demo screen for replaying message logs and testing UI rendering.
///
/// This screen allows you to:
/// - Load a JSONL message log file
/// - Play/pause/step through messages
/// - Test how the conversation panel renders different message types
class ReplayDemoScreen extends StatefulWidget {
  const ReplayDemoScreen({super.key});

  @override
  State<ReplayDemoScreen> createState() => _ReplayDemoScreenState();
}

class _ReplayDemoScreenState extends State<ReplayDemoScreen> {
  final TextEditingController _pathController = TextEditingController(
    text: '/tmp/test.msgs.jsonl',
  );

  ReplayConversationProvider? _provider;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _pathController.dispose();
    _provider?.dispose();
    super.dispose();
  }

  Future<void> _loadLogFile() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _errorMessage = 'Please enter a file path');
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      setState(() => _errorMessage = 'File not found: $path');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = ReplayConversationProvider(logFilePath: path);
      await provider.load();

      _provider?.dispose();
      setState(() {
        _provider = provider;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Replay Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload log file',
            onPressed: _provider != null ? _loadLogFile : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // File path input
          _FilePathInput(
            controller: _pathController,
            onLoad: _loadLogFile,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
          ),

          // Main content
          Expanded(
            child: _provider == null
                ? const _LoadPrompt()
                : _ReplayContent(provider: _provider!),
          ),
        ],
      ),
    );
  }
}

/// File path input section.
class _FilePathInput extends StatelessWidget {
  const _FilePathInput({
    required this.controller,
    required this.onLoad,
    required this.isLoading,
    this.errorMessage,
  });

  final TextEditingController controller;
  final VoidCallback onLoad;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Log file path',
                    hintText: '/tmp/test.msgs.jsonl',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: errorMessage,
                  ),
                  onSubmitted: (_) => onLoad(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: isLoading ? null : onLoad,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open),
                label: const Text('Load'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Prompt shown before a log file is loaded.
class _LoadPrompt extends StatelessWidget {
  const _LoadPrompt();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Load a message log file to begin',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'JSONL files from /tmp/test.msgs.jsonl contain SDK messages',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Main content area showing replay controls and conversation panel.
class _ReplayContent extends StatelessWidget {
  const _ReplayContent({required this.provider});

  final ReplayConversationProvider provider;

  @override
  Widget build(BuildContext context) {
    // Create a selection state that points to the replay chat
    final project = createReplayProject();
    final worktree = project.primaryWorktree;
    final selection = SelectionState(project)
      ..selectWorktree(worktree)
      ..selectChat(provider.chat);

    return ChangeNotifierProvider.value(
      value: selection,
      child: Row(
        children: [
          // Left side: Controls and stats
          SizedBox(
            width: 300,
            child: _ControlPanel(provider: provider),
          ),
          const VerticalDivider(width: 1),
          // Right side: Conversation panel
          Expanded(
            child: ListenableBuilder(
              listenable: provider.chat,
              builder: (context, _) => const ConversationPanel(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Control panel with playback controls and statistics.
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.provider});

  final ReplayConversationProvider provider;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Playback controls
            _PlaybackControls(provider: provider),
            const Divider(),
            // Statistics
            Expanded(
              child: _StatisticsPanel(provider: provider),
            ),
          ],
        );
      },
    );
  }
}

/// Playback controls (play, pause, step, speed).
class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.provider});

  final ReplayConversationProvider provider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = provider.totalEntries > 0
        ? provider.currentIndex / provider.totalEntries
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: progress,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          // Progress text
          Text(
            '${provider.currentIndex} / ${provider.totalEntries} entries',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // Main playback buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Stop button
              IconButton.filled(
                onPressed: provider.stop,
                icon: const Icon(Icons.stop),
                tooltip: 'Stop and reset',
              ),
              const SizedBox(width: 8),
              // Step back (not implemented, placeholder)
              const IconButton.outlined(
                onPressed: null,
                icon: Icon(Icons.skip_previous),
                tooltip: 'Step backward (not available)',
              ),
              const SizedBox(width: 8),
              // Play/Pause toggle
              IconButton.filled(
                onPressed: provider.isPlaying ? provider.pause : provider.play,
                icon: Icon(provider.isPlaying ? Icons.pause : Icons.play_arrow),
                tooltip: provider.isPlaying ? 'Pause' : 'Play',
                style: IconButton.styleFrom(
                  minimumSize: const Size(56, 56),
                ),
              ),
              const SizedBox(width: 8),
              // Step forward
              IconButton.outlined(
                onPressed:
                    provider.currentIndex < provider.totalEntries && !provider.isPlaying
                        ? provider.stepForward
                        : null,
                icon: const Icon(Icons.skip_next),
                tooltip: 'Step forward',
              ),
              const SizedBox(width: 8),
              // Play all instantly
              IconButton.filled(
                onPressed: !provider.isPlaying ? provider.playAllInstantly : null,
                icon: const Icon(Icons.fast_forward),
                tooltip: 'Play all instantly',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Speed control
          Row(
            children: [
              const Text('Speed:'),
              Expanded(
                child: Slider(
                  value: provider.speedMultiplier,
                  min: 0.5,
                  max: 10.0,
                  divisions: 19,
                  label: '${provider.speedMultiplier.toStringAsFixed(1)}x',
                  onChanged: (value) => provider.speedMultiplier = value,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${provider.speedMultiplier.toStringAsFixed(1)}x',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Statistics panel showing log file information.
class _StatisticsPanel extends StatelessWidget {
  const _StatisticsPanel({required this.provider});

  final ReplayConversationProvider provider;

  @override
  Widget build(BuildContext context) {
    final stats = provider.stats;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log Statistics',
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          _StatRow('Total lines', '${stats['totalLines'] ?? 0}'),
          _StatRow('Output entries', '${stats['outputEntries'] ?? 0}'),
          const SizedBox(height: 16),
          Text(
            'Message Types',
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _buildTypeStats(stats['messageTypes'] as Map<String, int>?),
          const SizedBox(height: 16),
          Text(
            'Payload Types',
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _buildTypeStats(stats['payloadTypes'] as Map<String, int>?),
          const SizedBox(height: 16),
          Text(
            'Entry Types',
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _buildTypeStats(stats['outputEntryTypes'] as Map<String, int>?),
        ],
      ),
    );
  }

  Widget _buildTypeStats(Map<String, int>? types) {
    if (types == null || types.isEmpty) {
      return const Text('No data');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: types.entries.map((e) => _StatRow(e.key, '${e.value}')).toList(),
    );
  }
}

/// A single statistic row.
class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }
}
