import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../config/fonts.dart';
import '../services/ask_ai_service.dart';
import '../services/git_service.dart';

/// Keys for testing CreatePrDialog widgets.
class CreatePrDialogKeys {
  CreatePrDialogKeys._();

  static const dialog = Key('create_pr_dialog');
  static const titleField = Key('create_pr_title_field');
  static const bodyField = Key('create_pr_body_field');
  static const customTab = Key('create_pr_custom_tab');
  static const changelogTab = Key('create_pr_changelog_tab');
  static const generatedTab = Key('create_pr_generated_tab');
  static const aiButton = Key('create_pr_ai_button');
  static const createButton = Key('create_pr_create_button');
  static const draftButton = Key('create_pr_draft_button');
  static const cancelButton = Key('create_pr_cancel_button');
  static const spinner = Key('create_pr_spinner');
  static const errorMessage = Key('create_pr_error');
  static const commitList = Key('create_pr_commit_list');
}

/// Shows the create PR dialog and returns true if a PR was created.
Future<bool> showCreatePrDialog({
  required BuildContext context,
  required String worktreePath,
  required String branch,
  required String mainBranch,
  required GitService gitService,
  required AskAiService askAiService,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => CreatePrDialog(
      worktreePath: worktreePath,
      branch: branch,
      mainBranch: mainBranch,
      gitService: gitService,
      askAiService: askAiService,
    ),
  );
  return result ?? false;
}

/// Dialog for creating and pushing a GitHub pull request.
class CreatePrDialog extends StatefulWidget {
  const CreatePrDialog({
    super.key,
    required this.worktreePath,
    required this.branch,
    required this.mainBranch,
    required this.gitService,
    required this.askAiService,
  });

  final String worktreePath;
  final String branch;
  final String mainBranch;
  final GitService gitService;
  final AskAiService askAiService;

  @override
  State<CreatePrDialog> createState() => _CreatePrDialogState();
}

class _CreatePrDialogState extends State<CreatePrDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  List<({String sha, String message})> _commits = [];
  bool _isLoadingCommits = true;
  bool _isGeneratingDescription = false;
  bool _userHasEdited = false;
  String? _cachedDescription;
  String? _error;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _bodyController.addListener(_onBodyChanged);
    _loadCommits();
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onBodyChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onBodyChanged() {
    if (_bodyController.text.isNotEmpty && !_userHasEdited) {
      setState(() {
        _userHasEdited = true;
      });
    }
  }

  Future<void> _loadCommits() async {
    try {
      final commits = await widget.gitService.getCommitsAhead(
        widget.worktreePath,
        widget.mainBranch,
      );
      if (!mounted) return;
      setState(() {
        _commits = commits;
        _isLoadingCommits = false;
      });

      // Auto-populate title
      if (commits.length == 1) {
        _titleController.text = commits.first.message;
      } else {
        _titleController.text = _formatBranchAsTitle(widget.branch);
      }

      // Start AI generation after commits are loaded
      _generateDescription();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load commits: $e';
        _isLoadingCommits = false;
      });
    }
  }

  String _formatBranchAsTitle(String branch) {
    // Convert "add-origin-support" -> "Add origin support"
    return branch
        .replaceAll(RegExp(r'[-_/]'), ' ')
        .trim()
        .replaceFirstMapped(
          RegExp(r'^.'),
          (m) => m.group(0)!.toUpperCase(),
        );
  }

  Future<void> _generateDescription() async {
    if (_commits.isEmpty) return;

    setState(() {
      _isGeneratingDescription = true;
      _error = null;
    });

    final commitList = _commits
        .map((c) => '- ${c.sha}: ${c.message}')
        .join('\n');

    final prompt =
        '''Generate a pull request description for the following '''
        '''commits being merged from branch "${widget.branch}" '''
        '''into "${widget.mainBranch}".

Output the description between markers like this:
===BEGIN===
## Summary
Brief description of the changes.

## Changes
- Change 1
- Change 2
===END===

Commits:
$commitList''';

    try {
      final result = await widget.askAiService.ask(
        prompt: prompt,
        workingDirectory: widget.worktreePath,
        model: 'haiku',
        allowedTools: ['Bash(git:*)', 'Read'],
        maxTurns: 5,
        timeoutSeconds: 120,
      );

      if (!mounted) return;

      if (result != null && !result.isError) {
        final rawMessage = result.result?.trim() ?? '';
        final description = _extractDescription(rawMessage);
        if (description.isNotEmpty) {
          _cachedDescription = description;
          if (!_userHasEdited) {
            _bodyController.text = description;
          }
        } else {
          setState(() {
            _error = 'AI returned an empty response';
          });
        }
      } else {
        setState(() {
          _error =
              'AI generation failed: '
              '${result?.result ?? 'Unknown error'}';
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
          _isGeneratingDescription = false;
        });
      }
    }
  }

  String _extractDescription(String raw) {
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

  Future<void> _triggerAiRegenerate() async {
    if (_cachedDescription != null &&
        _cachedDescription!.isNotEmpty) {
      setState(() {
        _bodyController.text = _cachedDescription!;
        _userHasEdited = false;
      });
      return;
    }

    setState(() {
      _userHasEdited = false;
      _bodyController.clear();
    });
    await _generateDescription();
  }

  Future<void> _createPr({required bool draft}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _error = 'PR title cannot be empty';
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      // Push the branch
      await widget.gitService.push(
        widget.worktreePath,
        setUpstream: true,
      );

      // Create the PR
      final prUrl = await widget.gitService.createPullRequest(
        path: widget.worktreePath,
        title: title,
        body: _bodyController.text.trim(),
        draft: draft,
      );

      if (!mounted) return;

      // Show success snackbar with PR URL
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft
                ? 'Draft PR created: $prUrl'
                : 'PR created: $prUrl',
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    final dialogWidth = (size.width * 0.8).clamp(600.0, 1200.0);
    final dialogHeight = (size.height * 0.8).clamp(400.0, 800.0);

    return Dialog(
      key: CreatePrDialogKeys.dialog,
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
            Expanded(child: _buildContent(colorScheme)),
            if (_error != null) _buildError(colorScheme),
            _buildFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_upload,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Create Pull Request',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${widget.branch} \u2192 ${widget.mainBranch}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onPrimaryContainer
                    .withValues(alpha: 0.7),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Generate PR description with AI',
            child: IconButton(
              key: CreatePrDialogKeys.aiButton,
              icon: Icon(
                Icons.auto_awesome,
                color: colorScheme.onPrimaryContainer,
                size: 20,
              ),
              onPressed: _isGeneratingDescription || _isCreating
                  ? null
                  : _triggerAiRegenerate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PR Title field
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: TextField(
            key: CreatePrDialogKeys.titleField,
            controller: _titleController,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              labelText: 'Title',
              labelStyle: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: colorScheme.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
            enabled: !_isCreating,
          ),
        ),
        // Tabs
        Container(
          color: colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.3),
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                key: CreatePrDialogKeys.customTab,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, size: 16),
                    SizedBox(width: 4),
                    Text('Custom'),
                  ],
                ),
              ),
              Tab(
                key: CreatePrDialogKeys.changelogTab,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.list, size: 16),
                    SizedBox(width: 4),
                    Text('Changelog'),
                  ],
                ),
              ),
              Tab(
                key: CreatePrDialogKeys.generatedTab,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 16),
                    SizedBox(width: 4),
                    Text('Generated'),
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
              _buildCustomTab(colorScheme),
              _buildChangelogTab(colorScheme),
              _buildGeneratedTab(colorScheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomTab(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        key: CreatePrDialogKeys.bodyField,
        controller: _bodyController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: AppFonts.monoTextStyle(
          fontSize: 13,
          color: colorScheme.onSurface,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: _isGeneratingDescription
              ? 'Generating PR description...'
              : 'Enter your PR description...',
          hintStyle: AppFonts.monoTextStyle(
            fontSize: 13,
            color:
                colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: colorScheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
        enabled: !_isCreating,
      ),
    );
  }

  Widget _buildChangelogTab(ColorScheme colorScheme) {
    if (_isLoadingCommits) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_commits.isEmpty) {
      return Center(
        child: Text(
          'No commits found',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return SelectionArea(
      child: ListView.builder(
        key: CreatePrDialogKeys.commitList,
        padding: const EdgeInsets.all(12),
        itemCount: _commits.length,
        itemBuilder: (context, index) {
          final commit = _commits[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  commit.sha,
                  style: AppFonts.monoTextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    commit.message,
                    style: AppFonts.monoTextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGeneratedTab(ColorScheme colorScheme) {
    return Stack(
      children: [
        if (_cachedDescription != null && _cachedDescription!.isNotEmpty)
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectionArea(
              child: GptMarkdown(
                _cachedDescription!,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          )
        else if (!_isGeneratingDescription)
          Center(
            child: Text(
              'No generated description yet',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (_isGeneratingDescription)
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              key: CreatePrDialogKeys.spinner,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI generating...',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Container(
      key: CreatePrDialogKeys.errorMessage,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            constraints:
                const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    return ListenableBuilder(
      listenable: _titleController,
      builder: (context, _) {
        final canCreate =
            _titleController.text.trim().isNotEmpty && !_isCreating;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: CreatePrDialogKeys.cancelButton,
                onPressed: _isCreating
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                key: CreatePrDialogKeys.draftButton,
                onPressed:
                    canCreate ? () => _createPr(draft: true) : null,
                child: _isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Create as Draft'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: CreatePrDialogKeys.createButton,
                onPressed:
                    canCreate ? () => _createPr(draft: false) : null,
                child: _isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create PR'),
              ),
            ],
          ),
        );
      },
    );
  }
}
