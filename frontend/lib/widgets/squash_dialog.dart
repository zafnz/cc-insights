import 'package:flutter/material.dart';

import '../config/fonts.dart';
import '../services/ask_ai_service.dart';
import '../services/git_service.dart';
import '../services/runtime_config.dart';

/// Shows the squash commits dialog and returns true if squash was performed.
Future<bool> showSquashDialog({
  required BuildContext context,
  required String worktreePath,
  required String branch,
  required String baseRef,
  required GitService gitService,
  required AskAiService askAiService,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SquashDialog(
      worktreePath: worktreePath,
      branch: branch,
      baseRef: baseRef,
      gitService: gitService,
      askAiService: askAiService,
    ),
  );
  return result ?? false;
}

/// Dialog for squashing commits.
class SquashDialog extends StatefulWidget {
  const SquashDialog({
    super.key,
    required this.worktreePath,
    required this.branch,
    required this.baseRef,
    required this.gitService,
    required this.askAiService,
  });

  final String worktreePath;
  final String branch;
  final String baseRef;
  final GitService gitService;
  final AskAiService askAiService;

  @override
  State<SquashDialog> createState() => _SquashDialogState();
}

class _SquashDialogState extends State<SquashDialog>
    with SingleTickerProviderStateMixin {
  // Step 1: Commit selection
  List<({String sha, String message})> _commits = [];
  bool _isLoadingCommits = true;
  String? _error;
  int? _selectedStartIndex;
  int? _selectedEndIndex;

  // Step 2: Commit message
  bool _showStep2 = false;
  late TabController _tabController;
  final _manualMessageController = TextEditingController();
  bool _isGeneratingMessage = false;
  String? _generatedMessage;
  bool _isSquashing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCommits();
  }

  @override
  void dispose() {
    _manualMessageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCommits() async {
    try {
      final commits =
          await widget.gitService.getCommitsAhead(widget.worktreePath, widget.baseRef);
      if (!mounted) return;
      setState(() {
        _commits = commits;
        _isLoadingCommits = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load commits: $e';
        _isLoadingCommits = false;
      });
    }
  }

  void _onCommitTapped(int index) {
    setState(() {
      if (_selectedStartIndex == null) {
        // First click - start the selection
        _selectedStartIndex = index;
        _selectedEndIndex = null;
      } else if (_selectedEndIndex == null) {
        // Second click - complete the range
        _selectedEndIndex = index;
      } else {
        // Third click - reset to new start
        _selectedStartIndex = index;
        _selectedEndIndex = null;
      }
    });
  }

  List<int> _getSelectedIndices() {
    if (_selectedStartIndex == null) return [];
    if (_selectedEndIndex == null) return [_selectedStartIndex!];

    final start = _selectedStartIndex! < _selectedEndIndex!
        ? _selectedStartIndex!
        : _selectedEndIndex!;
    final end = _selectedStartIndex! > _selectedEndIndex!
        ? _selectedStartIndex!
        : _selectedEndIndex!;

    return List.generate(end - start + 1, (i) => start + i);
  }

  List<({String sha, String message})> _getSelectedCommits() {
    final indices = _getSelectedIndices();
    return indices.map((i) => _commits[i]).toList();
  }

  bool get _canSquash {
    final indices = _getSelectedIndices();
    return indices.length >= 2;
  }

  void _goToStep2() {
    final selected = _getSelectedCommits();
    if (selected.length < 2) return;

    // Pre-fill manual tab with concatenated messages (oldest first)
    final reversed = selected.reversed.toList();
    final concatenated = reversed.map((c) => c.message).join('\n\n');
    final commented = reversed
        .map((c) => '#   ${c.sha} ${c.message}')
        .join('\n');

    _manualMessageController.text = '$concatenated\n\n'
        '# Squashing ${selected.length} commits:\n'
        '$commented';

    setState(() {
      _showStep2 = true;
    });

    // Start AI generation immediately
    if (RuntimeConfig.instance.aiAssistanceEnabled) {
      _generateAiMessage();
    }
  }

  Future<void> _generateAiMessage() async {
    final selected = _getSelectedCommits();
    if (selected.isEmpty) return;

    setState(() {
      _isGeneratingMessage = true;
      _error = null;
    });

    // Build prompt with commit list (oldest to newest)
    final reversed = selected.reversed.toList();
    final commitList = reversed
        .map((c) => '- ${c.sha} ${c.message}')
        .join('\n');

    final prompt = '''Generate a single git commit message that summarizes these commits being squashed together.

Output the commit message between markers like this:
===BEGIN===
Short summary line (50-72 chars)

- Bullet point explaining a change
- Another bullet point
===END===

Commits being squashed (oldest to newest):
$commitList''';

    try {
      final result = await widget.askAiService.ask(
        prompt: prompt,
        workingDirectory: widget.worktreePath,
        model: RuntimeConfig.instance.aiAssistanceModel,
        allowedTools: ['Bash(git:*)', 'Read'],
        maxTurns: 5,
        timeoutSeconds: 120,
      );

      if (!mounted) return;

      if (result != null && !result.isError) {
        final rawMessage = result.result.trim();
        final message = _extractCommitMessage(rawMessage);
        if (message.isNotEmpty) {
          setState(() {
            _generatedMessage = message;
          });
        } else {
          setState(() {
            _error = 'AI returned an empty response';
          });
        }
      } else {
        setState(() {
          _error = 'AI generation failed: ${result?.result ?? 'Unknown error'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'AI generation error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingMessage = false;
        });
      }
    }
  }

  String _extractCommitMessage(String raw) {
    const beginMarker = '===BEGIN===';
    const endMarker = '===END===';

    final beginIndex = raw.indexOf(beginMarker);
    final endIndex = raw.indexOf(endMarker);

    if (beginIndex != -1 && endIndex != -1 && endIndex > beginIndex) {
      return raw
          .substring(beginIndex + beginMarker.length, endIndex)
          .trim();
    }

    return raw.trim();
  }

  Future<void> _squash() async {
    // Get message from current tab
    String message;
    if (_tabController.index == 0) {
      // Auto-generated tab
      if (_generatedMessage == null || _generatedMessage!.isEmpty) {
        setState(() {
          _error = 'No commit message available';
        });
        return;
      }
      message = _generatedMessage!;
    } else {
      // Manual tab
      message = _manualMessageController.text;
    }

    // Strip comment lines (lines starting with #)
    final lines = message.split('\n');
    final filteredLines = lines.where((line) => !line.trim().startsWith('#'));
    message = filteredLines.join('\n').trim();

    if (message.isEmpty) {
      setState(() {
        _error = 'Commit message cannot be empty';
      });
      return;
    }

    setState(() {
      _isSquashing = true;
      _error = null;
    });

    try {
      final selected = _getSelectedCommits();
      // Oldest commit (last in list because commits are newest-first)
      final keepSha = selected.last.sha;
      // Newest commit (first in list)
      final topSha = selected.first.sha;

      final result = await widget.gitService.squashCommits(
        widget.worktreePath,
        keepSha: keepSha,
        topSha: topSha,
        message: message,
      );

      if (!mounted) return;

      if (result.hasConflicts) {
        setState(() {
          _error = 'Squash resulted in conflicts. Please resolve them manually.';
          _isSquashing = false;
        });
      } else if (result.error != null) {
        setState(() {
          _error = 'Squash failed: ${result.error}';
          _isSquashing = false;
        });
      } else {
        // Success
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Squash failed: $e';
        _isSquashing = false;
      });
    }
  }

  void _goBackToStep1() {
    setState(() {
      _showStep2 = false;
      _generatedMessage = null;
      _error = null;
    });
  }

  void _copyGeneratedToManual() {
    if (_generatedMessage != null) {
      _manualMessageController.text = _generatedMessage!;
      _tabController.animateTo(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    const dialogWidth = 600.0;
    final dialogHeight = (size.height * 0.7).clamp(400.0, 700.0);

    return Dialog(
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            _buildHeader(colorScheme),
            if (!_showStep2) _buildInstructionBar(colorScheme),
            Expanded(
              child: _showStep2
                  ? _buildStep2Content(colorScheme)
                  : _buildStep1Content(colorScheme),
            ),
            if (_error != null) _buildError(colorScheme),
            _buildFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.compress,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Squash Commits',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const Spacer(),
          Text(
            widget.branch,
            style: AppFonts.monoTextStyle(
              fontSize: 13,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Click a commit to start the range, then click another to set the end. Selected commits will be squashed into one.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Content(ColorScheme colorScheme) {
    if (_isLoadingCommits) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_commits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No commits ahead of ${widget.baseRef}',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final selectedIndices = _getSelectedIndices();
    final hasSelection = selectedIndices.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Commit list
        Expanded(
          child: ListView.builder(
            itemCount: _commits.length,
            itemBuilder: (context, index) {
              return _buildCommitItem(
                _commits[index],
                index,
                selectedIndices,
                colorScheme,
              );
            },
          ),
        ),
        // Summary bar
        if (hasSelection)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(
                  Icons.compress,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '${selectedIndices.length} commits selected — will be squashed into 1',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCommitItem(
    ({String sha, String message}) commit,
    int index,
    List<int> selectedIndices,
    ColorScheme colorScheme,
  ) {
    final isSelected = selectedIndices.contains(index);
    final isRangeStart = _selectedStartIndex == index || _selectedEndIndex == index;
    final isRangeEnd = _selectedEndIndex == index || _selectedStartIndex == index;

    return InkWell(
      onTap: () => _onCommitTapped(index),
      child: Container(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.06)
            : null,
        child: Row(
          children: [
            // Left gutter with range indicator
            Container(
              width: 36,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: isSelected
                  ? Column(
                      children: [
                        if (isRangeStart)
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (!isRangeStart && !isRangeEnd)
                          Expanded(
                            child: Container(
                              width: 3,
                              color: colorScheme.primary,
                            ),
                          ),
                        if (!isRangeStart)
                          Expanded(
                            child: Container(
                              width: 3,
                              color: colorScheme.primary,
                            ),
                          ),
                        if (isRangeEnd && selectedIndices.length > 1)
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  : null,
            ),
            // SHA
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                commit.sha,
                style: AppFonts.monoTextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Commit message
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  commit.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Content(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab bar
        Container(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 16),
                    SizedBox(width: 4),
                    Text('Auto-generated'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, size: 16),
                    SizedBox(width: 4),
                    Text('Manual'),
                  ],
                ),
              ),
            ],
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAutoGeneratedTab(colorScheme),
              _buildManualTab(colorScheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAutoGeneratedTab(ColorScheme colorScheme) {
    if (_isGeneratingMessage) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Generating commit message from ${_getSelectedCommits().length} squashed commits...',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_generatedMessage == null) {
      return Center(
        child: Text(
          'No message generated',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                  ),
                ),
                child: SelectionArea(
                  child: Text(
                    _generatedMessage!,
                    style: AppFonts.monoTextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _isGeneratingMessage || _isSquashing
                    ? null
                    : _generateAiMessage,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Regenerate'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _isSquashing ? null : _copyGeneratedToManual,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualTab(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _manualMessageController,
        maxLines: null,
        expands: true,
        autofocus: true,
        textAlignVertical: TextAlignVertical.top,
        style: AppFonts.monoTextStyle(
          fontSize: 13,
          color: colorScheme.onSurface,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: 'Enter commit message...',
          hintStyle: AppFonts.monoTextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
        enabled: !_isSquashing,
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 16,
              color: colorScheme.onErrorContainer,
            ),
            onPressed: () => setState(() => _error = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    if (_showStep2) {
      return _buildStep2Footer(colorScheme);
    }
    return _buildStep1Footer(colorScheme);
  }

  Widget _buildStep1Footer(ColorScheme colorScheme) {
    final canSquash = _canSquash;
    final selectedCount = _getSelectedIndices().length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Text(
            'base: ${widget.baseRef} · ${_commits.length} commits total',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: canSquash ? _goToStep2 : null,
            child: Text('Squash $selectedCount commits'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Footer(ColorScheme colorScheme) {
    final canCommit = !_isSquashing &&
        ((_tabController.index == 0 && _generatedMessage != null) ||
            (_tabController.index == 1 && _manualMessageController.text.trim().isNotEmpty));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isSquashing ? null : _goBackToStep1,
            child: const Text('Back'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: canCommit ? _squash : null,
            child: _isSquashing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Text('Commit'),
          ),
        ],
      ),
    );
  }
}
