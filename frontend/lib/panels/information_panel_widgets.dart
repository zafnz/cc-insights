import 'package:flutter/material.dart';

import '../models/worktree.dart';
import '../services/git_service.dart';

/// Keys for testing InformationPanel widgets.
///
/// Duplicated here so widget classes can reference them without importing
/// the main information_panel.dart file.
class InformationPanelKeys {
  InformationPanelKeys._();

  static const refreshButton = Key('info_panel_refresh');
  static const commitButton = Key('info_panel_commit');
  static const changeBaseButton = Key('info_panel_change_base');
  static const rebaseOntoBaseButton = Key('info_panel_rebase_onto_base');
  static const mergeBaseButton = Key('info_panel_merge_base');
  static const mergeBranchIntoMainButton =
      Key('info_panel_merge_branch_into_main');
  static const pushButton = Key('info_panel_push');
  static const pullRebaseButton = Key('info_panel_pull_rebase');
  static const pullMergeButton = Key('info_panel_pull_merge');
  static const createPrButton = Key('info_panel_create_pr');
  static const baseSection = Key('info_panel_base_section');
  static const upstreamSection = Key('info_panel_upstream_section');
}

// ---------------------------------------------------------------------------
// Section label / divider
// ---------------------------------------------------------------------------

class InfoSectionLabel extends StatelessWidget {
  const InfoSectionLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Text(
      label,
      style: textTheme.labelSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class InfoSectionDivider extends StatelessWidget {
  const InfoSectionDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dividerColor = colorScheme.outlineVariant.withValues(alpha: 0.4);

    return LayoutBuilder(
      builder: (context, constraints) {
        // For very narrow panels, just show text centered
        if (constraints.maxWidth < 150) {
          return Center(
            child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        return Row(
          children: [
            Expanded(child: Divider(color: dividerColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Divider(color: dividerColor)),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Status counts
// ---------------------------------------------------------------------------

class InfoStatusCounts extends StatelessWidget {
  const InfoStatusCounts({super.key, required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Tooltip(
      message: 'Uncommitted: ${data.uncommittedFiles} files\n'
          'Staged: ${data.stagedFiles} files\n'
          'Commits ahead of upstream: ${data.commitsAhead}',
      child: Text(
        'Uncommitted / Staged / Commits:  '
        '${data.uncommittedFiles} / ${data.stagedFiles} / '
        '${data.commitsAhead}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Base section
// ---------------------------------------------------------------------------

class InfoBaseSection extends StatelessWidget {
  const InfoBaseSection({
    super.key,
    required this.data,
    required this.baseRef,
    required this.onChangeBase,
  });

  final WorktreeData data;
  final String baseRef;
  final VoidCallback onChangeBase;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isLocal = !data.isRemoteBase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InfoSectionLabel(label: 'Base'),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 220;
            final baseLabel = isLocal ? 'local $baseRef' : baseRef;

            if (isWide) {
              return Row(
                children: [
                  Text(
                    isLocal ? '🏠' : '🌐',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      baseLabel,
                      style: textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InfoCompactButton(
                    key: InformationPanelKeys.changeBaseButton,
                    onPressed: onChangeBase,
                    label: 'Change...',
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isLocal ? '🏠' : '🌐',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        baseLabel,
                        style: textTheme.bodySmall?.copyWith(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: InfoCompactButton(
                    key: InformationPanelKeys.changeBaseButton,
                    onPressed: onChangeBase,
                    label: 'Change...',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        InfoAheadBehindIndicator(
          ahead: data.commitsAheadOfMain,
          behind: data.commitsBehindMain,
          targetRef: baseRef,
          aheadPrefix: '+',
          behindPrefix: '-',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Upstream sections
// ---------------------------------------------------------------------------

class InfoUpstreamSection extends StatelessWidget {
  const InfoUpstreamSection({
    super.key,
    required this.data,
  });

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InfoSectionLabel(label: 'Upstream'),
        const SizedBox(height: 4),
        if (data.upstreamBranch == null)
          Row(
            children: [
              Icon(
                Icons.cloud_off,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '(not published)',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Icon(
                Icons.cloud,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.upstreamBranch!,
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InfoAheadBehindIndicator(
            ahead: data.commitsAhead,
            behind: data.commitsBehind,
            targetRef: data.upstreamBranch!,
          ),
        ],
      ],
    );
  }
}

class InfoPrimaryUpstreamSection extends StatelessWidget {
  const InfoPrimaryUpstreamSection({
    super.key,
    required this.data,
    required this.canPush,
    required this.onPush,
    required this.onPullMerge,
    required this.onPullRebase,
  });

  final WorktreeData data;
  final bool canPush;
  final VoidCallback onPush;
  final VoidCallback onPullMerge;
  final VoidCallback onPullRebase;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InfoSectionLabel(label: 'Upstream'),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.cloud,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                data.upstreamBranch!,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        InfoAheadBehindIndicator(
          ahead: data.commitsAhead,
          behind: data.commitsBehind,
          targetRef: data.upstreamBranch!,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: InfoCompactButton(
            key: InformationPanelKeys.pushButton,
            onPressed: canPush ? onPush : null,
            label: 'Push',
            icon: Icons.cloud_upload,
            tooltip: canPush ? null : 'Nothing to push',
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: InfoCompactButton(
                key: InformationPanelKeys.pullMergeButton,
                onPressed: onPullMerge,
                label: 'Pull / Merge',
                icon: Icons.cloud_download,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InfoCompactButton(
                key: InformationPanelKeys.pullRebaseButton,
                onPressed: onPullRebase,
                label: 'Pull / Rebase',
                icon: Icons.cloud_download,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ahead/behind indicator
// ---------------------------------------------------------------------------

class InfoAheadBehindIndicator extends StatelessWidget {
  const InfoAheadBehindIndicator({
    super.key,
    required this.ahead,
    required this.behind,
    required this.targetRef,
    this.aheadPrefix = '\u{2191}',
    this.behindPrefix = '\u{2193}',
  });

  final int ahead;
  final int behind;
  final String targetRef;
  final String aheadPrefix;
  final String behindPrefix;

  String get _tooltipMessage {
    final lines = <String>[];
    if (ahead > 0) {
      lines.add('This branch has $ahead commit${ahead == 1 ? '' : 's'} '
          'not in $targetRef');
    }
    if (behind > 0) {
      lines.add('$targetRef has $behind commit${behind == 1 ? '' : 's'} '
          'not in this branch');
    }
    if (ahead > 0 && behind > 0) {
      lines.add('Your branches have diverged.');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (ahead == 0 && behind == 0) {
      return Text(
        'Up to date',
        style: textTheme.bodySmall?.copyWith(
          color: Colors.green,
        ),
      );
    }

    return Tooltip(
      message: _tooltipMessage,
      child: RichText(
        text: TextSpan(
          style: textTheme.bodySmall,
          children: [
            if (ahead > 0)
              TextSpan(
                text: '$aheadPrefix$ahead',
                style: const TextStyle(color: Colors.green),
              ),
            if (ahead > 0 && behind > 0) const TextSpan(text: '  '),
            if (behind > 0)
              TextSpan(
                text: '$behindPrefix$behind',
                style: const TextStyle(color: Colors.orange),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions section
// ---------------------------------------------------------------------------

class InfoActionsSection extends StatelessWidget {
  const InfoActionsSection({
    super.key,
    required this.data,
    required this.baseRef,
    required this.canUpdateFromBase,
    required this.canMergeIntoMain,
    required this.canPush,
    required this.canCreatePr,
    required this.onRebaseOntoBase,
    required this.onMergeBase,
    required this.onMergeIntoMain,
    required this.onPush,
    required this.onPullMerge,
    required this.onPullRebase,
    required this.onCreatePr,
  });

  final WorktreeData data;
  final String baseRef;
  final bool canUpdateFromBase;
  final bool canMergeIntoMain;
  final bool canPush;
  final bool canCreatePr;
  final VoidCallback onRebaseOntoBase;
  final VoidCallback onMergeBase;
  final VoidCallback onMergeIntoMain;
  final VoidCallback onPush;
  final VoidCallback onPullMerge;
  final VoidCallback onPullRebase;
  final VoidCallback onCreatePr;

  bool get _isLocalBase => !data.isRemoteBase;
  bool get _hasUpstream => data.upstreamBranch != null;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoSectionDivider(
          label: _isLocalBase ? 'Local actions' : 'Remote actions',
        ),
        const SizedBox(height: 4),
        Text(
          'Update from $baseRef',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: InfoCompactButton(
                key: InformationPanelKeys.rebaseOntoBaseButton,
                onPressed: canUpdateFromBase ? onRebaseOntoBase : null,
                label: 'Rebase',
                icon: Icons.low_priority,
                tooltip: canUpdateFromBase ? null : 'Already up to date',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InfoCompactButton(
                key: InformationPanelKeys.mergeBaseButton,
                onPressed: canUpdateFromBase ? onMergeBase : null,
                label: 'Merge',
                icon: Icons.merge,
                tooltip: canUpdateFromBase ? null : 'Already up to date',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLocalBase) ...[
          const InfoSectionDivider(label: 'Integrate locally'),
          const SizedBox(height: 8),
          InfoCompactButton(
            key: InformationPanelKeys.mergeBranchIntoMainButton,
            onPressed: canMergeIntoMain ? onMergeIntoMain : null,
            label: 'Merge branch \u{2192} $baseRef',
            icon: Icons.merge,
            tooltip: _mergeIntoMainTooltip,
          ),
        ] else if (!_hasUpstream) ...[
          const InfoSectionDivider(label: 'Publish'),
          const SizedBox(height: 8),
          InfoCompactButton(
            key: InformationPanelKeys.pushButton,
            onPressed: onPush,
            label: 'Push to origin/${data.branch}...',
            icon: Icons.cloud_upload,
          ),
          const SizedBox(height: 12),
          const InfoSectionDivider(label: 'Pull Request'),
          const SizedBox(height: 8),
          const InfoCompactButton(
            key: InformationPanelKeys.createPrButton,
            onPressed: null,
            label: 'Create PR (push required)',
            icon: Icons.open_in_new,
            tooltip: 'Push required before creating PR',
          ),
        ] else ...[
          const InfoSectionDivider(label: 'Sync'),
          const SizedBox(height: 4),
          Text(
            'Sync with ${data.upstreamBranch}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: InfoCompactButton(
              key: InformationPanelKeys.pushButton,
              onPressed: canPush ? onPush : null,
              label: 'Push',
              icon: Icons.cloud_upload,
              tooltip: canPush ? null : 'Nothing to push',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InfoCompactButton(
                  key: InformationPanelKeys.pullMergeButton,
                  onPressed: onPullMerge,
                  label: 'Pull / Merge',
                  icon: Icons.cloud_download,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InfoCompactButton(
                  key: InformationPanelKeys.pullRebaseButton,
                  onPressed: onPullRebase,
                  label: 'Pull / Rebase',
                  icon: Icons.cloud_download,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const InfoSectionDivider(label: 'Pull Request'),
          const SizedBox(height: 8),
          InfoCompactButton(
            key: InformationPanelKeys.createPrButton,
            onPressed: canCreatePr ? onCreatePr : null,
            label: 'Create PR',
            icon: Icons.open_in_new,
            tooltip: _createPrTooltip,
          ),
        ],
      ],
    );
  }

  String? get _mergeIntoMainTooltip {
    if (data.commitsAheadOfMain == 0) return 'No commits to merge';
    if (data.commitsBehindMain > 0) {
      return 'Update this branch with the latest from $baseRef '
          'before merging it back in';
    }
    return null;
  }

  String? get _createPrTooltip {
    if (data.commitsAheadOfMain == 0) return 'No commits to push';
    return null;
  }
}

// ---------------------------------------------------------------------------
// Conflict in progress
// ---------------------------------------------------------------------------

class InfoConflictInProgress extends StatelessWidget {
  const InfoConflictInProgress({
    super.key,
    required this.data,
    required this.onAbort,
    required this.onAskClaude,
    required this.onContinue,
  });

  final WorktreeData data;
  final VoidCallback onAbort;
  final VoidCallback onAskClaude;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final operationLabel =
        data.conflictOperation == MergeOperationType.rebase
            ? 'Rebase'
            : 'Merge';

    final resolved =
        !data.hasMergeConflict && data.conflictOperation != null;

    final Color bannerColor;
    final IconData bannerIcon;
    final String bannerText;
    if (resolved) {
      bannerColor = Colors.green.shade700;
      bannerIcon = Icons.check_circle_outline;
      bannerText = 'Conflicts resolved \u{2014} ready to continue';
    } else {
      bannerColor = Colors.orange.shade700;
      bannerIcon = Icons.warning_amber;
      bannerText = '$operationLabel conflict in progress';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bannerColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: bannerColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(bannerIcon, size: 14, color: bannerColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bannerText,
                  style: textTheme.labelSmall?.copyWith(
                    color: bannerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (resolved)
          Row(
            children: [
              Expanded(
                child: InfoCompactButton(
                  onPressed: onContinue,
                  label: 'Continue',
                  icon: Icons.play_arrow,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InfoCompactButton(
                  onPressed: onAbort,
                  label: 'Abort',
                  icon: Icons.cancel_outlined,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: InfoCompactButton(
                  onPressed: onAbort,
                  label: 'Abort',
                  icon: Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InfoCompactButton(
                  onPressed: onAskClaude,
                  label: 'Ask Claude',
                  icon: Icons.auto_fix_high,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Compact button
// ---------------------------------------------------------------------------

class InfoCompactButton extends StatelessWidget {
  const InfoCompactButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEnabled = onPressed != null;

    final contentColor = isEnabled
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final borderColor = isEnabled
        ? colorScheme.outline
        : colorScheme.outlineVariant.withValues(alpha: 0.3);

    Widget button = Opacity(
      opacity: isEnabled ? 1.0 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 12, color: contentColor),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: textTheme.labelSmall?.copyWith(
                      color: contentColor,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

// ---------------------------------------------------------------------------
// Pull rebase warning dialog
// ---------------------------------------------------------------------------

enum PullRebaseChoice { rebase, merge }

class PullRebaseWarningDialog extends StatelessWidget {
  const PullRebaseWarningDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Pull with rebase?'),
      content: const Text(
        'A git pull rebase rewrites the commit history. This is fine, '
        'but any worktrees basing off local main will suddenly report '
        'they are very out-of-sync. That can be solved by doing a rebase '
        'on each worktree.\n\n'
        'You may find doing a pull / merge is a better option and will '
        'avoid that.',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(PullRebaseChoice.rebase),
          child: Text(
            'Git pull (rebase)',
            style: TextStyle(color: colorScheme.error),
          ),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(PullRebaseChoice.merge),
          child: const Text('Git pull (merge)'),
        ),
      ],
    );
  }
}
