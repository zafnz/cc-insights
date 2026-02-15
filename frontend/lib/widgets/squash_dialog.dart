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

    // Pre-fill manual tab with commit messages separated by comment headers
    // (oldest first, matching git's squash message format).
    final reversed = selected.reversed.toList();
    final parts = <String>[];
    for (final c in reversed) {
      parts.add('# ${c.sha}');
      parts.add(c.message);
    }
    _manualMessageController.text = parts.join('\n\n');

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
        .map((c) => '--- ${c.sha} ---\n${c.message}')
        .join('\n\n');

    final prompt = '''Generate a single git commit message that summarizes these commits being squashed together. Match the style and tone of the original commit messages — if they use bullet points, use bullet points; if they are prose, use prose; if they are terse one-liners, be terse.

Output ONLY the commit message between these markers:
===BEGIN===
<your commit message here>
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

      final squashShas = selected
          .where((c) => c.sha != keepSha)
          .map((c) => c.sha)
          .toList();

      final result = await widget.gitService.squashCommits(
        widget.worktreePath,
        keepSha: keepSha,
        topSha: topSha,
        message: message,
        squashShas: squashShas,
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

    const dialogWidth = 840.0;
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
            _showStep2 ? Icons.edit_note : Icons.compress,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _showStep2 ? 'Squash Commit Message' : 'Squash Commits',
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
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colorScheme.primary,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.compress,
                  size: 16,
                  color: colorScheme.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${selectedIndices.length} commits',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      TextSpan(
                        text: ' selected \u2014 will be squashed into 1 commit at position of oldest',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
    final isInRange = selectedIndices.contains(index);
    final rangeMin = selectedIndices.isEmpty ? -1 : selectedIndices.first;
    final rangeMax = selectedIndices.isEmpty ? -1 : selectedIndices.last;
    final isRangeTop = isInRange && index == rangeMin;
    final isRangeBottom = isInRange && index == rangeMax;
    final isHandle = isRangeTop || isRangeBottom;

    return InkWell(
      onTap: () => _onCommitTapped(index),
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        decoration: BoxDecoration(
          color: isInRange
              ? colorScheme.primary.withValues(alpha: 0.06)
              : null,
          border: Border(
            top: isRangeTop
                ? BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.35),
                    width: 2,
                  )
                : BorderSide.none,
            bottom: isRangeBottom
                ? BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.35),
                    width: 2,
                  )
                : BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
          ),
        ),
        child: Row(
          children: [
            // Left gutter with range indicator
            SizedBox(
              width: 36,
              child: Center(
                child: isHandle
                    ? _buildRangeHandle(colorScheme)
                    : isInRange
                        ? Container(
                            width: 3,
                            height: 38,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          )
                        : null,
              ),
            ),
            // SHA
            SizedBox(
              width: 60,
              child: Text(
                commit.sha,
                style: AppFonts.monoTextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Commit message
            Expanded(
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
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeHandle(ColorScheme colorScheme) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.surface,
          width: 2,
        ),
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
          ),
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
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
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
          // AI badge
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'AI GENERATED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                  letterSpacing: 0.06 * 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
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
          const SizedBox(height: 10),
          Row(
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
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 800.0,
                height: constraints.maxHeight,
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
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  enabled: !_isSquashing,
                ),
              ),
            );
          },
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Text(
            'base: ${widget.baseRef} \u00b7 ${_commits.length} commits total',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canSquash ? _goToStep2 : null,
            icon: const Icon(Icons.compress, size: 16),
            label: Text('Squash $selectedCount commits'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Footer(ColorScheme colorScheme) {
    final canCommit = !_isSquashing &&
        ((_tabController.index == 0 && _generatedMessage != null) ||
            (_tabController.index == 1 && _manualMessageController.text.trim().isNotEmpty));

    final selected = _getSelectedCommits();
    final hintText = selected.length >= 2
        ? 'Squashing commits ${selected.first.sha}..${selected.last.sha}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (hintText.isNotEmpty)
            Text(
              hintText,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: _isSquashing ? null : _goBackToStep1,
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canCommit ? _squash : null,
            icon: _isSquashing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.check, size: 16),
            label: const Text('Commit'),
          ),
        ],
      ),
    );
  }
}
