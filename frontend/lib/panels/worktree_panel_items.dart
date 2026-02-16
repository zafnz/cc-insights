part of 'worktree_panel.dart';

/// Shows the animated bell overlay using an Overlay so it's not clipped.
///
/// This is a helper widget that manages inserting/removing the overlay entry.
class _AnimatedBellOverlay extends StatefulWidget {
  const _AnimatedBellOverlay({
    required this.targetKey,
    required this.onAnimationComplete,
  });

  /// The GlobalKey of the target worktree item to position over.
  final GlobalKey? targetKey;

  /// Called when the animation completes.
  final VoidCallback onAnimationComplete;

  @override
  State<_AnimatedBellOverlay> createState() => _AnimatedBellOverlayState();
}

class _AnimatedBellOverlayState extends State<_AnimatedBellOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _sizeAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _shakeAnimation;

  OverlayEntry? _overlayEntry;
  Offset? _targetPosition;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Size animation: small -> big (slow) -> hold -> small (fast)
    _sizeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 10,
          end: 70,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50, // Grow phase
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(70),
        weight: 25, // Hold at max size while shaking
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 70,
          end: 10,
        ).chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 25, // Shrink phase
      ),
    ]).animate(_controller);

    // Shake animation: oscillates during the hold phase
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(0),
        weight: 50, // No shake during growth
      ),
      // Shake sequence during hold
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: 0.15), weight: 2.5),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.15, end: -0.15),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.15, end: 0.12),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.12, end: -0.12),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.12, end: 0.08),
        weight: 4,
      ),
      TweenSequenceItem(tween: Tween<double>(begin: 0.08, end: 0), weight: 3.5),
      TweenSequenceItem(
        tween: ConstantTween<double>(0),
        weight: 25, // No shake during shrink
      ),
    ]).animate(_controller);

    // Opacity: fade in quickly, hold, then fade out
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 70),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _removeOverlay();
        widget.onAnimationComplete();
      }
    });

    // Get target position and show overlay after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTargetPosition();
      if (_targetPosition != null) {
        _showOverlay();
        _controller.forward();
      }
    });
  }

  void _updateTargetPosition() {
    final targetKey = widget.targetKey;
    if (targetKey?.currentContext != null) {
      final renderBox =
          targetKey!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null && mounted) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        // Position over the permission indicator (right side of branch name)
        _targetPosition = Offset(
          position.dx + size.width - 20,
          position.dy + 12, // Near top where branch name is
        );
      }
    }
  }

  void _showOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (context) => _BellOverlayContent(
        targetPosition: _targetPosition!,
        sizeAnimation: _sizeAnimation,
        opacityAnimation: _opacityAnimation,
        shakeAnimation: _shakeAnimation,
        controller: _controller,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This widget doesn't render anything itself - the overlay does
    return const SizedBox.shrink();
  }
}

/// The actual bell content rendered in the overlay.
class _BellOverlayContent extends StatelessWidget {
  const _BellOverlayContent({
    required this.targetPosition,
    required this.sizeAnimation,
    required this.opacityAnimation,
    required this.shakeAnimation,
    required this.controller,
  });

  final Offset targetPosition;
  final Animation<double> sizeAnimation;
  final Animation<double> opacityAnimation;
  final Animation<double> shakeAnimation;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final size = sizeAnimation.value;
        final opacity = opacityAnimation.value;
        final shake = shakeAnimation.value;

        return Positioned(
          left: targetPosition.dx - size / 2,
          top: targetPosition.dy - size / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: shake,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.4),
                        blurRadius: size / 3,
                        spreadRadius: size / 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.notifications_active,
                      size: size * 0.6,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ghost card for creating a new worktree.
///
/// Displays a subtle "New Worktree" action that when clicked
/// will (in the future) open a dialog to create a new git worktree.
class CreateWorktreeCard extends StatelessWidget {
  const CreateWorktreeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.read<SelectionState>().showCreateWorktreePanel();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'New Worktree',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single compact worktree entry in the list.
class _WorktreeListItem extends StatefulWidget {
  const _WorktreeListItem({
    super.key,
    required this.worktree,
    required this.repoRoot,
    required this.isSelected,
    required this.onTap,
  });

  final WorktreeState worktree;
  final String repoRoot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_WorktreeListItem> createState() => _WorktreeListItemState();
}

class _WorktreeListItemState extends State<_WorktreeListItem> {
  /// When true, the next tap will be treated as a double-click.
  bool _awaitingSecondClick = false;

  /// Timer for resetting _awaitingSecondClick after the double-click window.
  Timer? _doubleClickTimer;

  /// Duration of the double-click detection window.
  static const _doubleClickDuration = Duration(milliseconds: 300);

  /// Controller for the context menu.
  final _menuController = MenuController();

  @override
  void dispose() {
    _doubleClickTimer?.cancel();
    super.dispose();
  }

  void _handleTap(BuildContext context) {
    final isPrimary = widget.worktree.data.isPrimary;

    if (isPrimary && _awaitingSecondClick) {
      // This is a double-click on the primary worktree
      _doubleClickTimer?.cancel();
      _awaitingSecondClick = false;
      context.read<SelectionState>().showProjectSettingsPanel();
    } else {
      // First click - always select the worktree
      widget.onTap();

      if (isPrimary) {
        // Start the double-click detection timer for primary worktree
        _awaitingSecondClick = true;
        _doubleClickTimer?.cancel();
        _doubleClickTimer = Timer(_doubleClickDuration, () {
          if (mounted) {
            setState(() {
              _awaitingSecondClick = false;
            });
          }
        });
      }
    }
  }

  WorktreeState get worktree => widget.worktree;
  String get repoRoot => widget.repoRoot;
  bool get isSelected => widget.isSelected;

  /// Refreshes git status for this worktree after an operation.
  void _refreshStatus() {
    try {
      final watcher = context.read<WorktreeWatcherService>();
      watcher.forceRefresh(worktree);
    } catch (_) {
      // Provider not available (e.g., in tests)
    }
  }

  // ---------------------------------------------------------------------------
  // Git operation handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleStageCommit(BuildContext context) async {
    LogService.instance.info(
      'WorktreeMenu',
      'Stage & Commit: ${worktree.data.branch}',
    );
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();
    final fileSystemService = context.read<FileSystemService>();

    final committed = await showCommitDialog(
      context: context,
      worktreePath: worktree.data.worktreeRoot,
      gitService: gitService,
      askAiService: askAiService,
      fileSystemService: fileSystemService,
    );

    if (committed) _refreshStatus();
  }

  Future<void> _handleRebase(BuildContext context) async {
    final data = worktree.data;
    final baseRef = data.baseRef ?? 'main';
    LogService.instance.info(
      'WorktreeMenu',
      'Rebase: ${data.branch} onto $baseRef',
    );
    final gitService = context.read<GitService>();

    await showConflictResolutionDialog(
      context: context,
      worktreePath: data.worktreeRoot,
      branch: data.branch,
      mainBranch: baseRef,
      operation: MergeOperationType.rebase,
      gitService: gitService,
    );

    _refreshStatus();
  }

  Future<void> _handleMergeFromBase(BuildContext context) async {
    final data = worktree.data;
    final baseRef = data.baseRef ?? 'main';
    LogService.instance.info(
      'WorktreeMenu',
      'Merge from base: $baseRef into ${data.branch}',
    );
    final gitService = context.read<GitService>();

    await showConflictResolutionDialog(
      context: context,
      worktreePath: data.worktreeRoot,
      branch: data.branch,
      mainBranch: baseRef,
      operation: MergeOperationType.merge,
      gitService: gitService,
    );

    _refreshStatus();
  }

  Future<void> _handleSquash(BuildContext context) async {
    final data = worktree.data;
    final baseRef = data.baseRef ?? 'main';
    LogService.instance.info('WorktreeMenu', 'Squash: ${data.branch}');
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();

    final squashed = await showSquashDialog(
      context: context,
      worktreePath: data.worktreeRoot,
      branch: data.branch,
      baseRef: baseRef,
      gitService: gitService,
      askAiService: askAiService,
    );

    if (squashed) _refreshStatus();
  }

  Future<void> _handleChangeBase(BuildContext context) async {
    final previousValue = worktree.base;
    final result = await showBaseSelectorDialog(
      context,
      currentBase: previousValue,
      branchName: worktree.data.branch,
    );

    if (!context.mounted || result == null) return;

    final newBase = result.base;
    if (newBase == previousValue) return;

    LogService.instance.notice(
      'WorktreeMenu',
      'Base changed: ${worktree.data.branch} ${previousValue ?? "none"} -> $newBase',
    );
    worktree.setBase(newBase);

    try {
      final project = context.read<ProjectState>();
      final persistence = context.read<PersistenceService>();
      await persistence.updateWorktreeBase(
        projectRoot: project.data.repoRoot,
        worktreePath: worktree.data.worktreeRoot,
        base: newBase,
      );
    } catch (e, stack) {
      LogService.instance.logUnhandledException(e, stack);
      worktree.setBase(previousValue);
      if (context.mounted) {
        showErrorSnackBar(
          context,
          'Failed to update base branch. Please try again.',
        );
      }
      return;
    }

    _refreshStatus();

    if (result.rebase && context.mounted) {
      LogService.instance.info(
        'WorktreeMenu',
        'Rebase onto new base: ${worktree.data.branch} -> $newBase',
      );
      final gitService = context.read<GitService>();

      await showConflictResolutionDialog(
        context: context,
        worktreePath: worktree.data.worktreeRoot,
        branch: worktree.data.branch,
        mainBranch: newBase,
        operation: MergeOperationType.rebase,
        gitService: gitService,
        oldBase: previousValue ?? 'main',
      );

      if (context.mounted) _refreshStatus();
    }
  }

  Future<void> _handleMergeIntoBase(BuildContext context) async {
    final data = worktree.data;
    LogService.instance.info('WorktreeMenu', 'Merge into base: ${data.branch}');
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();

    String? mainBranch;
    try {
      mainBranch = await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Failed to detect main branch: $e');
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Could not detect main branch');
      return;
    }

    if (!context.mounted) return;

    final primaryWorktreePath = project.primaryWorktree.data.worktreeRoot;

    await showConflictResolutionDialog(
      context: context,
      worktreePath: primaryWorktreePath,
      branch: mainBranch,
      mainBranch: data.branch,
      operation: MergeOperationType.merge,
      gitService: gitService,
    );

    _refreshStatus();
  }

  Future<void> _handlePush(
    BuildContext context, {
    bool setUpstream = false,
  }) async {
    LogService.instance.info(
      'WorktreeMenu',
      'Push: ${worktree.data.branch}${setUpstream ? ' (set upstream)' : ''}',
    );
    final gitService = context.read<GitService>();
    try {
      await gitService.push(
        worktree.data.worktreeRoot,
        setUpstream: setUpstream,
      );
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Push failed: $e');
      return;
    }
    _refreshStatus();
  }

  Future<void> _handlePullFfOnly(BuildContext context) async {
    LogService.instance.info(
      'WorktreeMenu',
      'Pull FF-only: ${worktree.data.branch}',
    );
    final gitService = context.read<GitService>();
    final result = await gitService.pullFfOnly(worktree.data.worktreeRoot);
    if (result.error != null && context.mounted) {
      showErrorSnackBar(context, 'Pull (FF only) failed: ${result.error}');
    }
    _refreshStatus();
  }

  Future<void> _handlePullMerge(BuildContext context) async {
    final data = worktree.data;
    LogService.instance.info('WorktreeMenu', 'Pull merge: ${data.branch}');
    final gitService = context.read<GitService>();

    final upstream = data.upstreamBranch;
    if (upstream == null) return;

    await showConflictResolutionDialog(
      context: context,
      worktreePath: data.worktreeRoot,
      branch: data.branch,
      mainBranch: upstream,
      operation: MergeOperationType.merge,
      gitService: gitService,
      fetchFirst: true,
    );

    _refreshStatus();
  }

  Future<void> _handlePullRebase(BuildContext context) async {
    final data = worktree.data;
    LogService.instance.info('WorktreeMenu', 'Pull rebase: ${data.branch}');
    final gitService = context.read<GitService>();

    final upstream = data.upstreamBranch;
    if (upstream == null) return;

    await showConflictResolutionDialog(
      context: context,
      worktreePath: data.worktreeRoot,
      branch: data.branch,
      mainBranch: upstream,
      operation: MergeOperationType.rebase,
      gitService: gitService,
      fetchFirst: true,
    );

    _refreshStatus();
  }

  // ---------------------------------------------------------------------------
  // Menu builder
  // ---------------------------------------------------------------------------

  /// Builds the menu children for the context menu.
  List<Widget> _buildMenuChildren(BuildContext context) {
    final data = worktree.data;
    final colorScheme = Theme.of(context).colorScheme;

    final hasUncommitted = data.uncommittedFiles > 0;
    final hasBase = data.baseRef != null;
    final behindBase = data.commitsBehindMain > 0;
    final aheadOfBase = data.commitsAheadOfMain > 0;
    final hasUpstream = data.upstreamBranch != null;

    final menuItems = <Widget>[];

    // Project Settings (only for primary worktree)
    if (data.isPrimary) {
      menuItems.add(
        MenuItemButton(
          leadingIcon: Icon(
            Icons.settings_outlined,
            size: 16,
            color: colorScheme.onSurface,
          ),
          onPressed: () {
            context.read<SelectionState>().showProjectSettingsPanel();
          },
          child: Text(
            'Project Settings',
            style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
          ),
        ),
      );
      menuItems.add(
        MenuItemButton(
          leadingIcon: Icon(Icons.add, size: 16, color: colorScheme.onSurface),
          onPressed: () {
            context.read<SelectionState>().showCreateWorktreePanel();
          },
          child: Text(
            'New worktree...',
            style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
          ),
        ),
      );
      menuItems.add(const Divider(height: 1));
    }

    // Tags submenu - capture providers eagerly (the Builder's context is
    // deactivated by the time MenuItemButton.onPressed fires post-frame).
    menuItems.add(
      Builder(
        builder: (BuildContext menuContext) {
          final settings = menuContext.read<SettingsService>();
          final availableTags = settings.availableTags;
          final project = menuContext.read<ProjectState>();
          final persistence = menuContext.read<PersistenceService>();

          return SubmenuButton(
            leadingIcon: Icon(
              Icons.label_outlined,
              size: 16,
              color: colorScheme.onSurface,
            ),
            menuChildren: availableTags.map((tag) {
              final isChecked = worktree.tags.contains(tag.name);
              return MenuItemButton(
                onPressed: () {
                  worktree.toggleTag(tag.name);
                  persistence
                      .updateWorktreeTags(
                        projectRoot: project.data.repoRoot,
                        worktreePath: worktree.data.worktreeRoot,
                        tags: List.of(worktree.tags),
                      )
                      .catchError((Object e, StackTrace stack) {
                        LogService.instance.logUnhandledException(e, stack);
                        worktree.toggleTag(tag.name); // revert
                      });
                  setState(() {});
                },
                leadingIcon: SizedBox(
                  width: 20,
                  child: isChecked
                      ? Icon(Icons.check, size: 14, color: colorScheme.primary)
                      : null,
                ),
                trailingIcon: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: tag.color,
                    shape: BoxShape.circle,
                  ),
                ),
                child: Text(
                  tag.name,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                ),
              );
            }).toList(),
            child: Text(
              'Tags',
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
            ),
          );
        },
      ),
    );

    // Git submenu
    menuItems.add(
      SubmenuButton(
        leadingIcon: Icon(
          Icons.source_outlined,
          size: 16,
          color: colorScheme.onSurface,
        ),
        menuChildren: _buildGitMenuChildren(
          context,
          colorScheme: colorScheme,
          hasUncommitted: hasUncommitted,
          hasBase: hasBase,
          behindBase: behindBase,
          aheadOfBase: aheadOfBase,
          hasUpstream: hasUpstream,
        ),
        child: Text(
          'Git',
          style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
        ),
      ),
    );

    if (!data.isPrimary) {
      menuItems.add(const Divider(height: 1));
      menuItems.add(
        MenuItemButton(
          leadingIcon: Icon(
            Icons.fork_right,
            size: 16,
            color: colorScheme.onSurface,
          ),
          onPressed: () {
            context.read<SelectionState>().showCreateWorktreePanel(
              baseBranch: worktree.data.branch,
            );
          },
          child: Text(
            'Branch off this worktree',
            style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
          ),
        ),
      );
      menuItems.add(const Divider(height: 1));
      if (worktree.hidden) {
        menuItems.add(
          MenuItemButton(
            leadingIcon: Icon(
              Icons.visibility_outlined,
              size: 16,
              color: colorScheme.onSurface,
            ),
            onPressed: () async {
              await _handleUnhide(context);
            },
            child: Text(
              'Unhide Worktree',
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
            ),
          ),
        );
      } else {
        menuItems.add(
          MenuItemButton(
            leadingIcon: Icon(
              Icons.visibility_off_outlined,
              size: 16,
              color: colorScheme.onSurface,
            ),
            onPressed: () async {
              await _handleHide(context);
            },
            child: Text(
              'Hide Worktree',
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
            ),
          ),
        );
      }
      menuItems.add(
        MenuItemButton(
          leadingIcon: Icon(
            Icons.delete_outline,
            size: 16,
            color: colorScheme.error,
          ),
          onPressed: () async {
            await _handleDelete(context);
          },
          child: Text(
            'Delete Worktree',
            style: TextStyle(color: colorScheme.error, fontSize: 13),
          ),
        ),
      );
    }

    return menuItems;
  }

  /// Builds Git submenu children with conditional visibility and disabled states.
  List<Widget> _buildGitMenuChildren(
    BuildContext context, {
    required ColorScheme colorScheme,
    required bool hasUncommitted,
    required bool hasBase,
    required bool behindBase,
    required bool aheadOfBase,
    required bool hasUpstream,
  }) {
    final items = <Widget>[];
    final enabledColor = colorScheme.onSurface;
    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.38);

    // Stage & Commit - disabled when no uncommitted changes
    final stageEnabled = hasUncommitted;
    items.add(
      MenuItemButton(
        leadingIcon: Icon(
          Icons.commit,
          size: 16,
          color: stageEnabled ? enabledColor : disabledColor,
        ),
        onPressed: stageEnabled ? () => _handleStageCommit(context) : null,
        child: Text(
          'Stage & Commit...',
          style: TextStyle(
            color: stageEnabled ? enabledColor : disabledColor,
            fontSize: 13,
          ),
        ),
      ),
    );

    // Base operations - only shown when there is a base
    if (hasBase) {
      items.add(const Divider(height: 1));

      // Rebase - disabled when already up to date with base
      items.add(
        MenuItemButton(
          leadingIcon: Icon(
            Icons.merge,
            size: 16,
            color: behindBase ? enabledColor : disabledColor,
          ),
          onPressed: behindBase ? () => _handleRebase(context) : null,
          child: Text(
            'Rebase',
            style: TextStyle(
              color: behindBase ? enabledColor : disabledColor,
              fontSize: 13,
            ),
          ),
        ),
      );

      // Merge from base - disabled when already up to date with base
      items.add(
        MenuItemButton(
          leadingIcon: Icon(
            Icons.call_merge,
            size: 16,
            color: behindBase ? enabledColor : disabledColor,
          ),
          onPressed: behindBase ? () => _handleMergeFromBase(context) : null,
          child: Text(
            'Merge from base',
            style: TextStyle(
              color: behindBase ? enabledColor : disabledColor,
              fontSize: 13,
            ),
          ),
        ),
      );

      // Squash commits - disabled when fewer than 2 commits ahead of base
      final squashEnabled =
          aheadOfBase && worktree.data.commitsAheadOfMain >= 2;
      items.add(
        MenuItemButton(
          leadingIcon: Icon(
            Icons.compress,
            size: 16,
            color: squashEnabled ? enabledColor : disabledColor,
          ),
          onPressed: squashEnabled ? () => _handleSquash(context) : null,
          child: Text(
            'Squash commits',
            style: TextStyle(
              color: squashEnabled ? enabledColor : disabledColor,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    // Change base & Merge into base
    items.add(const Divider(height: 1));

    items.add(
      MenuItemButton(
        leadingIcon: Icon(
          Icons.settings_backup_restore,
          size: 16,
          color: enabledColor,
        ),
        onPressed: () => _handleChangeBase(context),
        child: Text(
          'Change base...',
          style: TextStyle(color: enabledColor, fontSize: 13),
        ),
      ),
    );

    // Merge into base - disabled when no commits ahead
    items.add(
      MenuItemButton(
        leadingIcon: Icon(
          Icons.merge_type,
          size: 16,
          color: aheadOfBase ? enabledColor : disabledColor,
        ),
        onPressed: aheadOfBase ? () => _handleMergeIntoBase(context) : null,
        child: Text(
          'Merge into base',
          style: TextStyle(
            color: aheadOfBase ? enabledColor : disabledColor,
            fontSize: 13,
          ),
        ),
      ),
    );

    // Pull/Push - only shown when there is an upstream
    if (hasUpstream) {
      items.add(const Divider(height: 1));

      items.add(
        SubmenuButton(
          leadingIcon: Icon(
            Icons.cloud_download,
            size: 16,
            color: enabledColor,
          ),
          menuChildren: [
            MenuItemButton(
              onPressed: worktree.data.commitsAhead == 0
                  ? () => _handlePullFfOnly(context)
                  : null,
              child: Builder(
                builder: (context) {
                  final ffEnabled = worktree.data.commitsAhead == 0;
                  return Text(
                    'FF Only',
                    style: TextStyle(
                      color: ffEnabled ? enabledColor : disabledColor,
                      fontSize: 13,
                    ),
                  );
                },
              ),
            ),
            MenuItemButton(
              onPressed: () => _handlePullMerge(context),
              child: Text(
                'with Merge',
                style: TextStyle(color: enabledColor, fontSize: 13),
              ),
            ),
            MenuItemButton(
              onPressed: () => _handlePullRebase(context),
              child: Text(
                'with Rebase',
                style: TextStyle(color: enabledColor, fontSize: 13),
              ),
            ),
          ],
          child: Text(
            'Pull',
            style: TextStyle(color: enabledColor, fontSize: 13),
          ),
        ),
      );

      // Push - disabled when nothing to push (ahead == 0)
      final pushEnabled = worktree.data.commitsAhead > 0;
      items.add(
        MenuItemButton(
          leadingIcon: Icon(
            Icons.cloud_upload,
            size: 16,
            color: pushEnabled ? enabledColor : disabledColor,
          ),
          onPressed: pushEnabled ? () => _handlePush(context) : null,
          child: Text(
            'Push',
            style: TextStyle(
              color: pushEnabled ? enabledColor : disabledColor,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return items;
  }

  Future<void> _handleHide(BuildContext context) async {
    final project = context.read<ProjectState>();
    final persistenceService = context.read<PersistenceService>();

    // Set hidden flag in projects.json
    try {
      await persistenceService.hideWorktreeFromIndex(
        projectRoot: project.data.repoRoot,
        worktreePath: worktree.data.worktreeRoot,
      );
    } catch (e, stack) {
      LogService.instance.logUnhandledException(e, stack);
      if (context.mounted) {
        showErrorSnackBar(
          context,
          'Failed to hide worktree. Please try again.',
        );
      }
      return;
    }

    if (!context.mounted) return;

    // Update in-memory state and notify project so the panel header rebuilds
    worktree.setHidden(true);
    project.notifyListeners();
  }

  Future<void> _handleUnhide(BuildContext context) async {
    final project = context.read<ProjectState>();
    final persistenceService = context.read<PersistenceService>();

    // Clear hidden flag in projects.json
    await persistenceService.unhideWorktreeFromIndex(
      projectRoot: project.data.repoRoot,
      worktreePath: worktree.data.worktreeRoot,
    );

    if (!context.mounted) return;

    // Update in-memory state and notify project so the panel header rebuilds
    worktree.setHidden(false);
    project.notifyListeners();
  }

  Future<void> _handleDelete(BuildContext context) async {
    final project = context.read<ProjectState>();
    final gitService = context.read<GitService>();
    final persistenceService = context.read<PersistenceService>();
    final askAiService = context.read<AskAiService>();
    final fileSystemService = context.read<FileSystemService>();
    final restoreService = context.read<ProjectRestoreService>();
    final scriptService = context.read<ScriptExecutionService>();
    final settings = context.read<SettingsService>();
    final archive = settings.getEffectiveValue<bool>('behavior.archiveChats');

    // Save cost tracking for all chats in this worktree before deletion
    final projectId = PersistenceService.generateProjectId(repoRoot);
    await restoreService.saveWorktreeCostTracking(projectId, worktree);

    // Archive chats before deletion if the setting is enabled.
    // This moves chat references to the archived list so that
    // removeWorktreeFromIndex() won't delete the chat files.
    if (archive) {
      try {
        await persistenceService.archiveWorktreeChats(
          projectRoot: project.data.repoRoot,
          worktreePath: worktree.data.worktreeRoot,
        );
      } catch (e, stack) {
        LogService.instance.logUnhandledException(e, stack);
        if (context.mounted) {
          showErrorSnackBar(
            context,
            'Failed to archive chats. Worktree deletion aborted to prevent data loss.',
          );
        }
        return;
      }
    }

    final deleteBranch = settings.getEffectiveValue<bool>(
      'behavior.deleteBranchWithWorktree',
    );

    if (!context.mounted) return;
    final result = await showDeleteWorktreeDialog(
      context: context,
      worktreePath: worktree.data.worktreeRoot,
      repoRoot: repoRoot,
      branch: worktree.data.branch,
      base: worktree.data.baseRef ?? 'main',
      projectId: projectId,
      gitService: gitService,
      persistenceService: persistenceService,
      askAiService: askAiService,
      fileSystemService: fileSystemService,
      deleteBranch: deleteBranch,
      configService: ProjectConfigService(),
      scriptService: scriptService,
    );

    if (result == DeleteWorktreeResult.deleted && context.mounted) {
      // Remove the worktree from the project state
      // Note: The filesystem watcher should also detect this, but we do it
      // explicitly to ensure immediate UI update
      project.removeLinkedWorktree(worktree);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Listen to worktree (git status) and all chat session/permission states.
    final chatListenables = <Listenable>[
      for (final chat in worktree.chats) chat.permissions,
      for (final chat in worktree.chats) chat.session,
    ];
    return ListenableBuilder(
      listenable: Listenable.merge([worktree, ...chatListenables]),
      builder: (context, _) {
        final data = worktree.data;
        // Check if any chat in this worktree has a pending permission
        final hasAnyPermissionPending = worktree.chats.any(
          (chat) => chat.permissions.isWaitingForPermission,
        );
        final hasAnyActiveChat = worktree.chats.any(
          (chat) => chat.session.isWorking,
        );

        Widget item = MenuAnchor(
          controller: _menuController,
          builder:
              (BuildContext context, MenuController controller, Widget? child) {
                return child!;
              },
          menuChildren: _buildMenuChildren(context),
          alignmentOffset: const Offset(0, 0),
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(
              colorScheme.surfaceContainerHigh,
            ),
            elevation: WidgetStateProperty.all(8),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
          child: GestureDetector(
            onSecondaryTapUp: (details) {
              _menuController.open(position: details.localPosition);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.surfaceContainerHighest,
                    width: 1,
                  ),
                ),
              ),
              child: Material(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _handleTap(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: spinner + branch name + permission indicator
                        Row(
                          children: [
                            // Activity spinner
                            if (hasAnyActiveChat)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _WorktreeActivitySpinner(
                                  color: colorScheme.primary,
                                ),
                              ),
                            // Hidden indicator
                            if (worktree.hidden)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.visibility_off,
                                  size: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            // Branch name (normal weight, ~13px)
                            Expanded(
                              child: Text(
                                data.branch,
                                style: textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Permission indicator (orange bell)
                            if (hasAnyPermissionPending)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.notifications_active,
                                  size: 14,
                                  color: Colors.orange,
                                ),
                              ),
                          ],
                        ),
                        // Tag pills
                        if (worktree.tags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Builder(
                              builder: (BuildContext tagContext) {
                                final settings = tagContext
                                    .read<SettingsService>();
                                return _TagPills(
                                  tagNames: worktree.tags,
                                  availableTags: settings.availableTags,
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 2),
                        // Path + status on same line (muted, monospace, ~11px)
                        // Primary worktree: show full path trimmed from the start.
                        // Linked worktrees: cost/token summary instead of path.
                        Row(
                          children: [
                            if (data.isPrimary)
                              Expanded(
                                child: Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: Text(
                                    data.worktreeRoot,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: RuntimeConfig.instance.showWorktreeCost
                                    ? _WorktreeCostSummary(worktree: worktree)
                                    : const SizedBox.shrink(),
                              ),
                            // Inline status indicators
                            InlineStatusIndicators(data: data),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (worktree.hidden) {
          item = Opacity(opacity: 0.5, child: item);
        }

        return item;
      },
    );
  }
}
