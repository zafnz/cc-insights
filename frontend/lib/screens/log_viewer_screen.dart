import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/log_filter.dart';
import '../services/log_service.dart';

/// Screen for viewing and filtering application log entries.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _queryController = TextEditingController();

  String? _selectedSource;
  LogLevel? _minimumLevel;
  LogFilter? _queryFilter;

  Timer? _queryDebounce;
  bool _isAtBottom = true;

  // Cached filtered list — recomputed on notification
  List<LogEntry> _filteredEntries = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _recomputeFiltered();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _queryController.dispose();
    _queryDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    _isAtBottom = pos.pixels >= pos.maxScrollExtent - 50;
  }

  void _recomputeFiltered() {
    final all = LogService.instance.entries;
    _filteredEntries = all.where((entry) {
      if (_selectedSource != null && entry.source != _selectedSource) {
        return false;
      }
      if (_minimumLevel != null && !entry.level.meetsThreshold(_minimumLevel!)) {
        return false;
      }
      if (_queryFilter != null && !_queryFilter!.matches(entry)) {
        return false;
      }
      return true;
    }).toList();
  }

  void _onQueryChanged(String query) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _queryFilter = LogFilter.parse(query);
        _recomputeFiltered();
      });
    });
  }

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      _isAtBottom = true;
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedSource = null;
      _minimumLevel = null;
      _queryFilter = null;
      _queryController.clear();
      _recomputeFiltered();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch for changes (rate-limited by LogService)
    context.watch<LogService>();
    _recomputeFiltered();

    final totalCount = LogService.instance.entryCount;
    final visibleCount = _filteredEntries.length;

    // Auto-scroll if at bottom
    if (_isAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }

    final colorScheme = Theme.of(context).colorScheme;
    final hasFilters =
        _selectedSource != null ||
        _minimumLevel != null ||
        _queryFilter != null;

    return Column(
      children: [
        // Filter bar
        _FilterBar(
          sources: LogService.instance.sources,
          selectedSource: _selectedSource,
          minimumLevel: _minimumLevel,
          queryController: _queryController,
          onSourceChanged: (source) {
            setState(() {
              _selectedSource = source;
              _recomputeFiltered();
            });
          },
          onLevelChanged: (level) {
            setState(() {
              _minimumLevel = level;
              _recomputeFiltered();
            });
          },
          onQueryChanged: _onQueryChanged,
          onClear: hasFilters ? _clearFilters : null,
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        // Log list
        Expanded(
          child: Stack(
            children: [
              _filteredEntries.isEmpty
                  ? Center(
                      child: Text(
                        totalCount == 0
                            ? 'No log entries yet'
                            : 'No entries match the current filters',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _filteredEntries.length,
                      itemExtent: null,
                      itemBuilder: (context, index) {
                        return _LogEntryRow(entry: _filteredEntries[index]);
                      },
                    ),
              // Jump to bottom FAB
              if (!_isAtBottom && _filteredEntries.isNotEmpty)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: _jumpToBottom,
                    tooltip: 'Jump to bottom',
                    child: const Icon(Icons.arrow_downward, size: 18),
                  ),
                ),
            ],
          ),
        ),
        // Status bar
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Text(
                hasFilters
                    ? '$visibleCount of $totalCount entries'
                    : '$totalCount entries',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Filter bar with source dropdown, level dropdown, and query input.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sources,
    required this.selectedSource,
    required this.minimumLevel,
    required this.queryController,
    required this.onSourceChanged,
    required this.onLevelChanged,
    required this.onQueryChanged,
    required this.onClear,
  });

  final Set<String> sources;
  final String? selectedSource;
  final LogLevel? minimumLevel;
  final TextEditingController queryController;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<LogLevel?> onLevelChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sortedSources = sources.toList()..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          // Source filter
          SizedBox(
            width: 140,
            child: _CompactDropdown<String?>(
              value: selectedSource,
              hint: 'All Sources',
              items: [
                const DropdownMenuItem(value: null, child: Text('All Sources')),
                ...sortedSources.map(
                  (s) => DropdownMenuItem(value: s, child: Text(s)),
                ),
              ],
              onChanged: onSourceChanged,
            ),
          ),
          const SizedBox(width: 8),
          // Level filter
          SizedBox(
            width: 110,
            child: _CompactDropdown<LogLevel?>(
              value: minimumLevel,
              hint: 'All Levels',
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Levels'),
                ),
                ...LogLevel.values.map(
                  (l) => DropdownMenuItem(
                    value: l,
                    child: Row(
                      children: [
                        _LevelBadge(level: l, compact: true),
                        const SizedBox(width: 6),
                        Text(_levelLabel(l)),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: onLevelChanged,
            ),
          ),
          const SizedBox(width: 8),
          // Query filter
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: queryController,
                onChanged: onQueryChanged,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: '.source == "App"',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.filter_list,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 0,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Clear button
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.clear, size: 16),
              tooltip: 'Clear filters',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _levelLabel(LogLevel level) {
    return switch (level) {
      LogLevel.debug => 'Debug',
      LogLevel.info => 'Info',
      LogLevel.notice => 'Notice',
      LogLevel.warn => 'Warn',
      LogLevel.error => 'Error',
    };
  }
}

/// Compact dropdown wrapper matching app styling.
class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 30,
      child: DropdownButtonFormField<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        icon: Icon(
          Icons.arrow_drop_down,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colorScheme.primary),
          ),
        ),
      ),
    );
  }
}

/// Individual log entry row.
class _LogEntryRow extends StatefulWidget {
  const _LogEntryRow({required this.entry});

  final LogEntry entry;

  @override
  State<_LogEntryRow> createState() => _LogEntryRowState();
}

class _LogEntryRowState extends State<_LogEntryRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = widget.entry;
    final hasMeta = entry.meta != null && entry.meta!.isNotEmpty;
    final monoStyle = GoogleFonts.jetBrainsMono(
      fontSize: 11,
      color: colorScheme.onSurface,
    );

    return InkWell(
      onTap: hasMeta ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timestamp
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: monoStyle.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                // Level badge
                _LevelBadge(level: entry.level),
                const SizedBox(width: 8),
                // Source
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    entry.source,
                    style: monoStyle.copyWith(
                      fontSize: 10,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Message
                Expanded(
                  child: Text(
                    entry.message,
                    style: monoStyle,
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                  ),
                ),
                // Meta indicator
                if (hasMeta)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
              ],
            ),
            // Expanded meta
            if (_expanded && hasMeta)
              Padding(
                padding: const EdgeInsets.only(left: 80, top: 2, bottom: 2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:
                        colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(entry.meta),
                    style: monoStyle.copyWith(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    final s = ts.second.toString().padLeft(2, '0');
    final ms = ts.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// Color-coded level badge.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, this.compact = false});

  final LogLevel level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (level) {
      LogLevel.debug => (Colors.grey, 'DBG'),
      LogLevel.info => (Colors.blue, 'INF'),
      LogLevel.notice => (Colors.cyan, 'NTC'),
      LogLevel.warn => (Colors.orange, 'WRN'),
      LogLevel.error => (Colors.red, 'ERR'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
