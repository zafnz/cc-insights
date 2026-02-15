part of 'worktree_panel.dart';

/// Displays Base and Sync badges plus uncommitted/conflict indicators.
///
/// - **Base Badge**: integration state vs merge target (local or remote)
/// - **Sync Badge**: publication state vs upstream tracking branch
/// - Uncommitted files and merge conflicts shown as inline text after badges
class InlineStatusIndicators extends StatelessWidget {
  const InlineStatusIndicators({super.key, required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final hasBase = data.commitsAheadOfMain > 0 ||
        data.commitsBehindMain > 0 ||
        data.baseRef != null;
    final hasExtra =
        data.uncommittedFiles > 0 || data.hasMergeConflict;

    if (!hasBase &&
        data.upstreamBranch == null &&
        !hasExtra) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasExtra) _ExtraIndicators(data: data),
          if (hasExtra) const SizedBox(width: 4),
          if (hasBase) _BaseBadge(data: data),
          if (hasBase) const SizedBox(width: 4),
          _SyncBadge(data: data),
        ],
      ),
    );
  }
}

/// Badge showing integration state: how far this branch is from its
/// merge target (local main or origin/main).
class _BaseBadge extends StatelessWidget {
  const _BaseBadge({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.labelSmall;
    final icon = data.isRemoteBase ? '\u{1F310}' : '\u{1F3E0}';
    final refName = data.baseRef ?? 'main';
    final ahead = data.commitsAheadOfMain;
    final behind = data.commitsBehindMain;

    final parts = <TextSpan>[
      TextSpan(text: '$icon ', style: style),
    ];

    if (ahead > 0) {
      parts.add(TextSpan(
        text: '+$ahead',
        style: style?.copyWith(color: Colors.green),
      ));
    }
    if (behind > 0) {
      if (ahead > 0) {
        parts.add(TextSpan(text: ' ', style: style));
      }
      parts.add(TextSpan(
        text: '\u{2212}$behind',
        style: style?.copyWith(color: Colors.orange),
      ));
    }
    if (ahead == 0 && behind == 0) {
      parts.add(TextSpan(
        text: '=',
        style: style?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ));
    }

    final tooltipLines = <String>['Base: $refName'];
    if (ahead > 0) {
      tooltipLines.add(
        '${data.branch} has $ahead commit${ahead == 1 ? '' : 's'}'
        ' not on $refName',
      );
    }
    if (behind > 0) {
      tooltipLines.add(
        '$refName has $behind commit${behind == 1 ? '' : 's'}'
        ' not on ${data.branch}',
      );
    }
    if (ahead > 0 && behind > 0) {
      tooltipLines.add('Branches have diverged');
    } else if (ahead == 0 && behind == 0) {
      tooltipLines.add('Up to date');
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: _BadgeContainer(
        child: RichText(text: TextSpan(children: parts)),
      ),
    );
  }
}

/// Badge showing publication state: how far this branch is from its
/// upstream tracking branch.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.labelSmall;
    final hasUpstream = data.upstreamBranch != null;

    final parts = <TextSpan>[
      TextSpan(text: '\u{2601} ', style: style),
    ];

    final tooltipLines = <String>[];

    if (!hasUpstream) {
      parts.add(TextSpan(
        text: '\u{2014}',
        style: style?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ));
      tooltipLines.add('Sync: no upstream');
      tooltipLines.add(
        '${data.branch} is not tracking a remote branch',
      );
    } else {
      final upstream = data.upstreamBranch!;
      final ahead = data.commitsAhead;
      final behind = data.commitsBehind;
      if (ahead > 0) {
        parts.add(TextSpan(
          text: '\u{2191}$ahead',
          style: style?.copyWith(color: Colors.green),
        ));
      }
      if (behind > 0) {
        if (ahead > 0) {
          parts.add(TextSpan(text: ' ', style: style));
        }
        parts.add(TextSpan(
          text: '\u{2193}$behind',
          style: style?.copyWith(color: Colors.orange),
        ));
      }
      if (ahead == 0 && behind == 0) {
        parts.add(TextSpan(
          text: '=',
          style: style?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ));
      }

      tooltipLines.add('Sync: $upstream');
      if (ahead > 0) {
        tooltipLines.add(
          '${data.branch} has $ahead commit${ahead == 1 ? '' : 's'}'
          ' not on $upstream',
        );
      }
      if (behind > 0) {
        tooltipLines.add(
          '$upstream has $behind commit${behind == 1 ? '' : 's'}'
          ' not on ${data.branch}',
        );
      }
      if (ahead > 0 && behind > 0) {
        tooltipLines.add('Branches have diverged');
      } else if (ahead == 0 && behind == 0) {
        tooltipLines.add('Up to date');
      }
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: _BadgeContainer(
        child: RichText(text: TextSpan(children: parts)),
      ),
    );
  }
}

/// Shared container styling for Base and Sync badges.
class _BadgeContainer extends StatelessWidget {
  const _BadgeContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

/// Compact inline indicators for uncommitted files and merge conflicts.
class _ExtraIndicators extends StatelessWidget {
  const _ExtraIndicators({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final parts = <TextSpan>[];

    if (data.uncommittedFiles > 0) {
      parts.add(TextSpan(
        text: '~${data.uncommittedFiles}',
        style: textTheme.labelSmall?.copyWith(color: Colors.blue),
      ));
    }

    if (data.hasMergeConflict) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(TextSpan(
        text: '!',
        style: textTheme.labelSmall?.copyWith(color: Colors.red),
      ));
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    final tooltipLines = <String>[];
    if (data.uncommittedFiles > 0) {
      final s = data.uncommittedFiles == 1 ? '' : 's';
      tooltipLines.add(
        '~ ${data.uncommittedFiles} uncommitted file$s',
      );
    }
    if (data.hasMergeConflict) {
      tooltipLines.add('! Merge conflict');
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: RichText(text: TextSpan(children: parts)),
    );
  }
}

/// A small spinner shown to the left of the worktree branch name when any
/// chat in the worktree is actively working.
///
/// When [WorktreePanel.disableAnimations] is true (e.g. in tests), renders
/// a static circle icon instead of an animated [CircularProgressIndicator]
/// so that [WidgetTester.pumpAndSettle] does not hang.
class _WorktreeActivitySpinner extends StatelessWidget {
  const _WorktreeActivitySpinner({required this.color});

  final Color color;

  static const double _size = 12.0;

  @override
  Widget build(BuildContext context) {
    if (WorktreePanel.disableAnimations) {
      return SizedBox(
        width: _size,
        height: _size,
        child: Icon(
          Icons.circle,
          size: _size,
          color: color.withValues(alpha: 0.6),
        ),
      );
    }
    return SizedBox(
      width: _size,
      height: _size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tag pills
// -----------------------------------------------------------------------------

/// Displays a row of small colored pill chips for each assigned tag.
class _TagPills extends StatelessWidget {
  const _TagPills({
    required this.tagNames,
    required this.availableTags,
  });

  final List<String> tagNames;
  final List<WorktreeTag> availableTags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: tagNames.map((name) {
        final tagDef = availableTags
            .where((t) => t.name == name)
            .firstOrNull;
        final color = tagDef?.color ?? Colors.grey;
        return _TagChip(name: name, color: color);
      }).toList(),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cost/token summary for linked worktrees
// -----------------------------------------------------------------------------

/// Displays aggregated cost and token usage per backend for a linked worktree.
///
/// Shows total cost followed by per-backend token counts, e.g.:
/// `$5.20 - Claude 🪙5M Codex 🪙2.7M`
///
/// Only renders when there is usage data. Hidden for primary worktrees.
class _WorktreeCostSummary extends StatelessWidget {
  const _WorktreeCostSummary({required this.worktree});

  final WorktreeState worktree;

  @override
  Widget build(BuildContext context) {
    final costPerBackend = worktree.costPerBackend;
    if (costPerBackend.isEmpty) return const SizedBox.shrink();

    final totalCost = costPerBackend.values.fold(
      0.0,
      (sum, v) => sum + v.costUsd,
    );
    final hasAnyCost = costPerBackend.values.any((v) => v.costUsd > 0);

    final textStyle = TextStyle(fontSize: 11, color: Colors.grey[600]);

    return ClipRect(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAnyCost) ...[
            Text(
              '\$${_formatCost(totalCost)}',
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '-',
                style: textStyle,
              ),
            ),
          ],
          // Per-backend token summaries
          ...costPerBackend.entries.expand((entry) {
            final label = switch (entry.key) {
              'codex' => 'Codex',
              'acp' => 'ACP',
              _ => 'Claude',
            };
            return [
              Flexible(
                child: Text(
                  label,
                  style: textStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.token,
                size: 12,
                color: Colors.grey[600],
              ),
              Flexible(
                child: Text(
                  _formatTokenCount(entry.value.totalTokens),
                  style: textStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
            ];
          }),
        ],
      ),
    );
  }

  static String _formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}k';
    }
    return count.toString();
  }

  static String _formatCost(double cost) {
    if (cost >= 0.01 || cost == 0) {
      return cost.toStringAsFixed(2);
    }
    return cost.toStringAsFixed(4);
  }
}
