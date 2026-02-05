import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/log_service.dart';

/// Screen for viewing application logs in real-time.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  late List<LogEntry> _entries;
  StreamSubscription<LogEntry>? _subscription;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  bool _isAtBottom = true;

  // Filters
  LogLevel _minimumLevel = LogLevel.debug;
  String? _selectedWorktree; // null = all worktrees
  String? _selectedService; // null = all services
  String? _selectedType; // null = all types
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _entries = List.of(LogService.instance.entries);
    _subscription = LogService.instance.logs.listen(_onLogEntry);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onLogEntry(LogEntry entry) {
    setState(() {
      _entries.add(entry);
      // Keep in sync with LogService's cap
      if (_entries.length > LogService.maxEntries) {
        _entries.removeRange(0, _entries.length - LogService.maxEntries);
      }
    });
    if (_autoScroll && _isAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 50;
    if (atBottom != _isAtBottom) {
      setState(() => _isAtBottom = atBottom);
    }
  }

  /// Get unique worktrees from all entries.
  Set<String> get _availableWorktrees {
    return _entries
        .where((e) => e.worktree != null)
        .map((e) => e.worktree!)
        .toSet();
  }

  /// Get unique services from all entries.
  Set<String> get _availableServices {
    return _entries.map((e) => e.service).toSet();
  }

  /// Get unique types from all entries.
  Set<String> get _availableTypes {
    return _entries.map((e) => e.type).toSet();
  }

  List<LogEntry> get _filteredEntries {
    return _entries.where((entry) {
      // Level filter (show entries at or above minimum level)
      if (!entry.level.meetsThreshold(_minimumLevel)) return false;

      // Worktree filter
      if (_selectedWorktree != null && entry.worktree != _selectedWorktree) {
        return false;
      }

      // Service filter
      if (_selectedService != null && entry.service != _selectedService) {
        return false;
      }

      // Type filter
      if (_selectedType != null && entry.type != _selectedType) {
        return false;
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesService = entry.service.toLowerCase().contains(query);
        final matchesType = entry.type.toLowerCase().contains(query);
        final matchesWorktree =
            entry.worktree?.toLowerCase().contains(query) ?? false;
        final matchesText =
            entry.message['text']?.toString().toLowerCase().contains(query) ??
                false;
        final matchesData = jsonEncode(entry.message).toLowerCase().contains(query);
        if (!matchesService &&
            !matchesType &&
            !matchesWorktree &&
            !matchesText &&
            !matchesData) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;

    return Row(
      children: [
        _LogSidebar(
          minimumLevel: _minimumLevel,
          onLevelChanged: (level) {
            setState(() => _minimumLevel = level);
          },
          selectedWorktree: _selectedWorktree,
          availableWorktrees: _availableWorktrees,
          onWorktreeChanged: (worktree) {
            setState(() => _selectedWorktree = worktree);
          },
          selectedService: _selectedService,
          availableServices: _availableServices,
          onServiceChanged: (service) {
            setState(() => _selectedService = service);
          },
          selectedType: _selectedType,
          availableTypes: _availableTypes,
          onTypeChanged: (type) {
            setState(() => _selectedType = type);
          },
          totalCount: _entries.length,
          filteredCount: filtered.length,
          onClear: () {
            LogService.instance.clear();
            setState(() => _entries.clear());
          },
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
        ),
        Expanded(
          child: Column(
            children: [
              _LogToolbar(
                searchController: _searchController,
                onSearchChanged: (query) {
                  setState(() => _searchQuery = query);
                },
                autoScroll: _autoScroll,
                onAutoScrollToggled: () {
                  setState(() => _autoScroll = !_autoScroll);
                },
                isAtBottom: _isAtBottom,
                onScrollToBottom: () {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                },
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : _LogEntryList(
                        entries: filtered,
                        scrollController: _scrollController,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasEntries = _entries.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasEntries ? Icons.filter_list_off : Icons.terminal_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            hasEntries
                ? 'No logs match the current filters'
                : 'No log entries yet',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (!hasEntries) ...[
            const SizedBox(height: 4),
            Text(
              'Logs will appear here as the application runs',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

class _LogSidebar extends StatelessWidget {
  const _LogSidebar({
    required this.minimumLevel,
    required this.onLevelChanged,
    required this.selectedWorktree,
    required this.availableWorktrees,
    required this.onWorktreeChanged,
    required this.selectedService,
    required this.availableServices,
    required this.onServiceChanged,
    required this.selectedType,
    required this.availableTypes,
    required this.onTypeChanged,
    required this.totalCount,
    required this.filteredCount,
    required this.onClear,
  });

  final LogLevel minimumLevel;
  final ValueChanged<LogLevel> onLevelChanged;
  final String? selectedWorktree;
  final Set<String> availableWorktrees;
  final ValueChanged<String?> onWorktreeChanged;
  final String? selectedService;
  final Set<String> availableServices;
  final ValueChanged<String?> onServiceChanged;
  final String? selectedType;
  final Set<String> availableTypes;
  final ValueChanged<String?> onTypeChanged;
  final int totalCount;
  final int filteredCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'Logs',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Worktree filter
                _FilterSection(
                  title: 'WORKTREE',
                  child: _FilterDropdown(
                    value: selectedWorktree,
                    items: availableWorktrees.toList()..sort(),
                    allLabel: 'All Worktrees',
                    onChanged: onWorktreeChanged,
                  ),
                ),
                const SizedBox(height: 12),
                // Level filter
                _FilterSection(
                  title: 'MINIMUM LEVEL',
                  child: _FilterDropdown(
                    value: minimumLevel.name,
                    items: LogLevel.values.map((l) => l.name).toList(),
                    allLabel: null, // No "all" option for level
                    onChanged: (value) {
                      if (value != null) {
                        onLevelChanged(
                          LogLevel.values.firstWhere((l) => l.name == value),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Service filter
                _FilterSection(
                  title: 'SERVICE',
                  child: _FilterDropdown(
                    value: selectedService,
                    items: availableServices.toList()..sort(),
                    allLabel: 'All Services',
                    onChanged: onServiceChanged,
                  ),
                ),
                const SizedBox(height: 12),
                // Type filter
                _FilterSection(
                  title: 'TYPE',
                  child: _FilterDropdown(
                    value: selectedType,
                    items: availableTypes.toList()..sort(),
                    allLabel: 'All Types',
                    onChanged: onTypeChanged,
                  ),
                ),
              ],
            ),
          ),
          // Footer with count + clear
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$filteredCount / $totalCount entries',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: totalCount > 0 ? onClear : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Clear Logs'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter section
// ---------------------------------------------------------------------------

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter dropdown
// ---------------------------------------------------------------------------

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.allLabel,
    required this.onChanged,
  });

  final String? value;
  final List<String> items;
  final String? allLabel; // If null, no "all" option
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface,
          ),
          dropdownColor: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          items: [
            if (allLabel != null)
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  allLabel!,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ...items.map(
              (item) => DropdownMenuItem<String?>(
                value: item,
                child: Text(
                  item,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

class _LogToolbar extends StatelessWidget {
  const _LogToolbar({
    required this.searchController,
    required this.onSearchChanged,
    required this.autoScroll,
    required this.onAutoScrollToggled,
    required this.isAtBottom,
    required this.onScrollToBottom,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool autoScroll;
  final VoidCallback onAutoScrollToggled;
  final bool isAtBottom;
  final VoidCallback onScrollToBottom;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search logs...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Auto-scroll toggle
          Tooltip(
            message:
                autoScroll ? 'Auto-scroll enabled' : 'Auto-scroll disabled',
            child: IconButton(
              onPressed: onAutoScrollToggled,
              icon: Icon(
                autoScroll
                    ? Icons.vertical_align_bottom
                    : Icons.vertical_align_bottom_outlined,
                size: 18,
                color:
                    autoScroll ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ),
          // Scroll to bottom (only when not at bottom)
          if (!isAtBottom)
            Tooltip(
              message: 'Scroll to bottom',
              child: IconButton(
                onPressed: onScrollToBottom,
                icon: Icon(
                  Icons.arrow_downward,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Log entry list
// ---------------------------------------------------------------------------

class _LogEntryList extends StatelessWidget {
  const _LogEntryList({
    required this.entries,
    required this.scrollController,
  });

  final List<LogEntry> entries;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _LogEntryRow(entry: entries[index]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Log entry row
// ---------------------------------------------------------------------------

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
    final hasDetails = entry.message.length > 1 ||
        (entry.message.length == 1 && !entry.message.containsKey('text'));
    final ts = entry.timestamp;
    final timeStr = '${ts.hour.toString().padLeft(2, '0')}'
        ':${ts.minute.toString().padLeft(2, '0')}'
        ':${ts.second.toString().padLeft(2, '0')}'
        '.${ts.millisecond.toString().padLeft(3, '0')}';

    return InkWell(
      onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.1),
            ),
          ),
          color: _rowBackground(entry.level, colorScheme),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Timestamp
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                // Level badge
                _LevelBadge(level: entry.level),
                const SizedBox(width: 6),
                // Service badge
                _ServiceBadge(service: entry.service),
                const SizedBox(width: 6),
                // Type badge
                _TypeBadge(type: entry.type),
                // Worktree badge (if present)
                if (entry.worktree != null) ...[
                  const SizedBox(width: 6),
                  _WorktreeBadge(worktree: entry.worktree!),
                ],
                const SizedBox(width: 8),
                // Message text
                Expanded(
                  child: Text(
                    entry.text ?? jsonEncode(entry.message),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'JetBrains Mono',
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Expand indicator
                if (hasDetails)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                // Copy button
                Tooltip(
                  message: 'Copy log entry',
                  child: IconButton(
                    onPressed: () => _copyEntry(entry),
                    icon: Icon(
                      Icons.copy,
                      size: 14,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            // Expanded details
            if (_expanded && hasDetails)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    _prettyJson(entry.message),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'JetBrains Mono',
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _copyEntry(LogEntry entry) {
    final text = _prettyJson(entry.toJson());
    Clipboard.setData(ClipboardData(text: text));
  }

  String _prettyJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  Color? _rowBackground(LogLevel level, ColorScheme colorScheme) {
    return switch (level) {
      LogLevel.error => colorScheme.error.withValues(alpha: 0.05),
      LogLevel.warn => Colors.orange.withValues(alpha: 0.03),
      _ => null,
    };
  }
}

// ---------------------------------------------------------------------------
// Level badge
// ---------------------------------------------------------------------------

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final LogLevel level;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _levelColor(level, colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        level.name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: 'JetBrains Mono',
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service badge
// ---------------------------------------------------------------------------

class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({required this.service});

  final String service;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        service,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type badge
// ---------------------------------------------------------------------------

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          fontFamily: 'JetBrains Mono',
          color: colorScheme.secondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Worktree badge
// ---------------------------------------------------------------------------

class _WorktreeBadge extends StatelessWidget {
  const _WorktreeBadge({required this.worktree});

  final String worktree;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_tree,
            size: 8,
            color: Colors.teal.shade700,
          ),
          const SizedBox(width: 2),
          Text(
            worktree,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              fontFamily: 'JetBrains Mono',
              color: Colors.teal.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

Color _levelColor(LogLevel level, ColorScheme colorScheme) {
  return switch (level) {
    LogLevel.debug => colorScheme.onSurfaceVariant,
    LogLevel.info => colorScheme.primary,
    LogLevel.notice => Colors.blue,
    LogLevel.warn => Colors.orange,
    LogLevel.error => colorScheme.error,
  };
}
