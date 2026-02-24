import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/design_tokens.dart';
import '../services/runtime_config.dart';
import 'click_to_scroll_container.dart';
import 'tool_card_inputs.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Known internal CCI orchestrator tool names.
const _cciOrchToolNames = {
  // Agent tools
  'launch_agent',
  'tell_agent',
  'ask_agent',
  'wait_for_agents',
  'check_agents',
  // Ticket tools
  'create_ticket',
  'list_tickets',
  'get_ticket',
  'update_ticket',
  // Worktree tools
  'create_worktree',
  'rebase_and_merge',
  // Tag tools
  'set_tags',
  'list_tags',
};

/// MCP tool name pattern: `mcp__<server>__<tool>`.
final _mcpPattern = RegExp(r'^mcp__([^_]+)__(.+)$');

/// Returns the bare CCI orchestrator tool name if [toolName] is an internal
/// orchestrator MCP tool, or null otherwise.
String? cciOrchToolName(String toolName) {
  final match = _mcpPattern.firstMatch(toolName);
  if (match == null) return null;
  final server = match.group(1)!;
  final tool = match.group(2)!;
  if (server == 'cci' && _cciOrchToolNames.contains(tool)) return tool;
  return null;
}

/// Friendly display name for a CCI orchestrator tool.
String? cciOrchFriendlyName(String orchToolName) {
  return switch (orchToolName) {
    'launch_agent' => 'Launch Agent',
    'tell_agent' => 'Tell Agent',
    'ask_agent' => 'Ask Agent',
    'wait_for_agents' => 'Wait For Agents',
    'check_agents' => 'Check Agents',
    'create_ticket' => 'Create Tickets',
    'list_tickets' => 'List Tickets',
    'get_ticket' => 'Get Ticket',
    'update_ticket' => 'Update Ticket',
    'create_worktree' => 'Create Worktree',
    'rebase_and_merge' => 'Rebase & Merge',
    'set_tags' => 'Set Tags',
    'list_tags' => 'List Tags',
    _ => null,
  };
}

/// Icon for a CCI orchestrator tool.
IconData cciOrchIcon(String orchToolName) {
  return switch (orchToolName) {
    'launch_agent' => Icons.rocket_launch_outlined,
    'tell_agent' => Icons.send_outlined,
    'ask_agent' => Icons.question_answer_outlined,
    'wait_for_agents' => Icons.hourglass_empty,
    'check_agents' => Icons.fact_check_outlined,
    'create_ticket' => Icons.add_task,
    'list_tickets' => Icons.list_alt,
    'get_ticket' => Icons.assignment_outlined,
    'update_ticket' => Icons.update,
    'create_worktree' => Icons.account_tree_outlined,
    'rebase_and_merge' => Icons.merge,
    'set_tags' => Icons.label_outlined,
    'list_tags' => Icons.label_outlined,
    _ => Icons.extension,
  };
}

/// Color for all CCI orchestrator tools.
const Color cciOrchColor = Colors.deepPurple;

/// Summary text for a CCI orchestrator tool header.
String cciOrchSummary(String orchName, Map<String, dynamic> input) {
  return switch (orchName) {
    'launch_agent' => _launchAgentSummary(input),
    'tell_agent' => _tellAgentSummary(input),
    'ask_agent' => _askAgentSummary(input),
    'wait_for_agents' => _agentCountSummary(input),
    'check_agents' => _agentCountSummary(input),
    'create_ticket' => _createTicketSummary(input),
    'list_tickets' => _listTicketsSummary(input),
    'get_ticket' => _getTicketSummary(input),
    'update_ticket' => _updateTicketSummary(input),
    'create_worktree' => input['branch_name'] as String? ?? '',
    'rebase_and_merge' => _shortPath(input['worktree_path'] as String? ?? ''),
    'set_tags' => _setTagsSummary(input),
    'list_tags' => '',
    _ => '',
  };
}

// ---------------------------------------------------------------------------
// Summary helpers
// ---------------------------------------------------------------------------

String _launchAgentSummary(Map<String, dynamic> input) {
  final name = input['name'] as String?;
  final ticketId = input['ticket_id'] as num?;
  final parts = <String>[
    if (name != null) name,
    if (ticketId != null) 'TKT-${ticketId.toInt()}',
  ];
  if (parts.isNotEmpty) return parts.join(' ');
  final instructions = input['instructions'] as String? ?? '';
  return _truncate(instructions, 50);
}

String _tellAgentSummary(Map<String, dynamic> input) {
  final agentId = _shortAgentId(input['agent_id'] as String? ?? '');
  final message = input['message'] as String? ?? '';
  return '$agentId: ${_truncate(message, 40)}';
}

String _askAgentSummary(Map<String, dynamic> input) {
  final agentId = _shortAgentId(input['agent_id'] as String? ?? '');
  final message = input['message'] as String? ?? '';
  return '$agentId: ${_truncate(message, 40)}';
}

String _agentCountSummary(Map<String, dynamic> input) {
  final ids = input['agent_ids'] as List<dynamic>? ?? [];
  return '${ids.length} agent${ids.length == 1 ? '' : 's'}';
}

String _createTicketSummary(Map<String, dynamic> input) {
  final tickets = input['tickets'] as List<dynamic>? ?? [];
  return '${tickets.length} ticket${tickets.length == 1 ? '' : 's'}';
}

String _listTicketsSummary(Map<String, dynamic> input) {
  final statuses = input['status'] as List<dynamic>?;
  final category = input['category'] as String?;
  final parts = <String>[
    if (statuses != null) statuses.join(', '),
    if (category != null) 'cat: $category',
  ];
  return parts.join(' ');
}

String _getTicketSummary(Map<String, dynamic> input) {
  final id = input['ticket_id'] as num?;
  return id != null ? 'TKT-${id.toInt()}' : '';
}

String _updateTicketSummary(Map<String, dynamic> input) {
  final id = input['ticket_id'] as num?;
  final status = input['status'] as String?;
  final parts = <String>[
    if (id != null) 'TKT-${id.toInt()}',
    if (status != null) '\u2192 $status',
  ];
  return parts.join(' ');
}

String _setTagsSummary(Map<String, dynamic> input) {
  final tags = input['tags'] as List<dynamic>? ?? [];
  return tags.join(', ');
}

// ---------------------------------------------------------------------------
// Shared string helpers
// ---------------------------------------------------------------------------

/// Abbreviates agent IDs like "agent-chat-1771936832434" to a shorter form.
String _shortAgentId(String agentId) {
  // Try extracting a meaningful name from common patterns
  // Pattern: "agent-chat-<timestamp>" -> show last 6 digits
  if (agentId.startsWith('agent-chat-') && agentId.length > 17) {
    return 'agent-${agentId.substring(agentId.length - 6)}';
  }
  if (agentId.length > 20) return '${agentId.substring(0, 20)}\u2026';
  return agentId;
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength - 3)}\u2026';
}

/// Shortens an absolute path by taking the last two segments.
String _shortPath(String path) {
  if (path.isEmpty) return '';
  final parts = path.split('/');
  if (parts.length <= 2) return path;
  return '\u2026/${parts.sublist(parts.length - 2).join('/')}';
}

// ---------------------------------------------------------------------------
// JSON / content-block helpers
// ---------------------------------------------------------------------------

/// Extracts plain text from a tool result that may be a content-block list.
///
/// MCP tool results arrive as `[{type: text, text: "..."}]`. This helper
/// unwraps such lists into the concatenated text.
dynamic _unwrapContentBlocks(dynamic result) {
  if (result is List) {
    final buffer = StringBuffer();
    for (final block in result) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text'] ?? '');
      }
    }
    if (buffer.isNotEmpty) return buffer.toString();
  }
  return result;
}

Map<String, dynamic>? _tryParseJson(dynamic result) {
  try {
    if (result is String) {
      return jsonDecode(result) as Map<String, dynamic>;
    } else if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// Visual helpers (string-based, no dependency on ticket model enums)
// ---------------------------------------------------------------------------

Color _statusColor(String status) {
  return switch (status) {
    'completed' => const Color(0xFF4CAF50),
    'active' => const Color(0xFF42A5F5),
    'inReview' => const Color(0xFFCE93D8),
    'blocked' || 'needsInput' => const Color(0xFFFFA726),
    'cancelled' => const Color(0xFFEF5350),
    'ready' => const Color(0xFF757575),
    'draft' || 'split' => const Color(0xFF9E9E9E),
    _ => const Color(0xFF9E9E9E),
  };
}

IconData _statusIcon(String status) {
  return switch (status) {
    'draft' => Icons.edit_note,
    'ready' => Icons.radio_button_unchecked,
    'active' => Icons.play_circle_outline,
    'blocked' => Icons.block,
    'needsInput' => Icons.help_outline,
    'inReview' => Icons.rate_review_outlined,
    'completed' => Icons.check_circle_outline,
    'cancelled' => Icons.cancel_outlined,
    'split' => Icons.call_split,
    _ => Icons.circle_outlined,
  };
}

Color _kindColor(String kind) {
  return switch (kind) {
    'feature' => const Color(0xFFBA68C8),
    'bugfix' => const Color(0xFFEF5350),
    'research' => const Color(0xFFCE93D8),
    'question' => const Color(0xFFFFCA28),
    'test' => const Color(0xFF4DB6AC),
    'docs' || 'chore' => const Color(0xFF9E9E9E),
    _ => const Color(0xFF9E9E9E),
  };
}

IconData _kindIcon(String kind) {
  return switch (kind) {
    'feature' => Icons.star_outline,
    'bugfix' => Icons.bug_report_outlined,
    'research' => Icons.science_outlined,
    'question' => Icons.help_outline,
    'test' => Icons.science,
    'docs' => Icons.description_outlined,
    'chore' => Icons.handyman_outlined,
    _ => Icons.circle_outlined,
  };
}

Color _priorityColor(String priority) {
  return switch (priority) {
    'critical' || 'high' => const Color(0xFFEF5350),
    'medium' => const Color(0xFFFFA726),
    'low' => const Color(0xFF9E9E9E),
    _ => const Color(0xFF9E9E9E),
  };
}

// =============================================================================
// Shared private badge widget
// =============================================================================

class _OrchBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const _OrchBadge({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final badgeColor = color ?? cciOrchColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: Radii.smallBorderRadius,
      ),
      child: Text(
        label,
        style: GoogleFonts.getFont(
          RuntimeConfig.instance.monoFontFamily,
          fontSize: FontSizes.code,
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
      ),
    );
  }
}

// =============================================================================
// Raw text fallback
// =============================================================================

class _RawTextFallback extends StatelessWidget {
  final String text;

  const _RawTextFallback({required this.text});

  @override
  Widget build(BuildContext context) {
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    return ClickToScrollContainer(
      maxHeight: 300,
      padding: const EdgeInsets.all(8),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: Radii.smallBorderRadius,
      child: SelectableText(
        text,
        style: GoogleFonts.getFont(
          monoFont,
          fontSize: FontSizes.code,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

// =============================================================================
// Input widgets
// =============================================================================

/// Dispatches to the correct orchestrator tool input widget.
class OrchToolInputWidget extends StatelessWidget {
  final String orchToolName;
  final Map<String, dynamic> input;

  const OrchToolInputWidget({
    super.key,
    required this.orchToolName,
    required this.input,
  });

  @override
  Widget build(BuildContext context) {
    return switch (orchToolName) {
      'launch_agent' => _LaunchAgentInput(input: input),
      'tell_agent' => _MessageToAgentInput(input: input),
      'ask_agent' => _MessageToAgentInput(input: input, showTimeout: true),
      'wait_for_agents' => _AgentIdsInput(input: input, showTimeout: true),
      'check_agents' => _AgentIdsInput(input: input),
      'create_ticket' => _CreateTicketInput(input: input),
      'list_tickets' => _ListTicketsInput(input: input),
      'get_ticket' => _GetTicketInput(input: input),
      'update_ticket' => _UpdateTicketInput(input: input),
      'create_worktree' => _CreateWorktreeInput(input: input),
      'rebase_and_merge' => _RebaseAndMergeInput(input: input),
      'set_tags' => _SetTagsInput(input: input),
      'list_tags' => const SizedBox.shrink(),
      _ => GenericInputWidget(input: input),
    };
  }
}

// -----------------------------------------------------------------------------
// Agent tool inputs
// -----------------------------------------------------------------------------

class _LaunchAgentInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _LaunchAgentInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final worktree = input['worktree'] as String? ?? '';
    final name = input['name'] as String?;
    final ticketId = input['ticket_id'] as num?;
    final instructions = input['instructions'] as String? ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Badges row
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (name != null) _OrchBadge(label: name),
            if (ticketId != null)
              _OrchBadge(
                label: 'TKT-${ticketId.toInt()}',
                color: Colors.teal,
              ),
          ],
        ),
        if (name != null || ticketId != null) const SizedBox(height: 6),
        // Worktree path
        Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: IconSizes.xs,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _shortPath(worktree),
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: FontSizes.code,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // Instructions
        if (instructions.isNotEmpty) ...[
          const SizedBox(height: 6),
          ClickToScrollContainer(
            maxHeight: 200,
            padding: const EdgeInsets.all(8),
            backgroundColor: colorScheme.surfaceContainerHighest,
            borderRadius: Radii.smallBorderRadius,
            child: SelectableText(
              instructions,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: FontSizes.code,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MessageToAgentInput extends StatelessWidget {
  final Map<String, dynamic> input;
  final bool showTimeout;

  const _MessageToAgentInput({
    required this.input,
    this.showTimeout = false,
  });

  @override
  Widget build(BuildContext context) {
    final agentId = input['agent_id'] as String? ?? '';
    final message = input['message'] as String? ?? '';
    final timeout = input['timeout_seconds'] as num?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _OrchBadge(label: _shortAgentId(agentId)),
            if (showTimeout && timeout != null)
              _OrchBadge(
                label: '${timeout.toInt()}s timeout',
                color: Colors.grey,
              ),
          ],
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 6),
          ClickToScrollContainer(
            maxHeight: 150,
            padding: const EdgeInsets.all(8),
            backgroundColor: colorScheme.surfaceContainerHighest,
            borderRadius: Radii.smallBorderRadius,
            child: SelectableText(
              message,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: FontSizes.code,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AgentIdsInput extends StatelessWidget {
  final Map<String, dynamic> input;
  final bool showTimeout;

  const _AgentIdsInput({required this.input, this.showTimeout = false});

  @override
  Widget build(BuildContext context) {
    final ids = input['agent_ids'] as List<dynamic>? ?? [];
    final timeout = input['timeout_seconds'] as num?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final id in ids)
              _OrchBadge(label: _shortAgentId(id.toString())),
          ],
        ),
        if (showTimeout && timeout != null) ...[
          const SizedBox(height: 6),
          _OrchBadge(
            label: '${timeout.toInt()}s timeout',
            color: Colors.grey,
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Ticket tool inputs
// -----------------------------------------------------------------------------

class _CreateTicketInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _CreateTicketInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final tickets = input['tickets'] as List<dynamic>? ?? [];
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < tickets.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _TicketProposalRow(
            index: i + 1,
            ticket: tickets[i] as Map<String, dynamic>,
            colorScheme: colorScheme,
          ),
        ],
      ],
    );
  }
}

class _TicketProposalRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> ticket;
  final ColorScheme colorScheme;

  const _TicketProposalRow({
    required this.index,
    required this.ticket,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final title = ticket['title'] as String? ?? '';
    final kind = ticket['kind'] as String? ?? '';
    final priority = ticket['priority'] as String?;
    final effort = ticket['effort'] as String?;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Text(
            '$index.',
            style: TextStyle(
              fontSize: FontSizes.code,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (kind.isNotEmpty) ...[
          _OrchBadge(label: kind, color: _kindColor(kind)),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: FontSizes.bodySmall,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        if (priority != null) ...[
          const SizedBox(width: 6),
          _OrchBadge(label: priority, color: _priorityColor(priority)),
        ],
        if (effort != null) ...[
          const SizedBox(width: 4),
          _OrchBadge(label: effort, color: Colors.grey),
        ],
      ],
    );
  }
}

class _ListTicketsInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _ListTicketsInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final statuses = input['status'] as List<dynamic>?;
    final category = input['category'] as String?;
    final ids = input['ids'] as List<dynamic>?;
    final dependsOn = input['depends_on'] as num?;
    final dependencyOf = input['dependency_of'] as num?;

    final hasSomething = (statuses != null && statuses.isNotEmpty) ||
        category != null ||
        ids != null ||
        dependsOn != null ||
        dependencyOf != null;

    if (!hasSomething) {
      return Text(
        'All tickets',
        style: TextStyle(
          fontSize: FontSizes.bodySmall,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (statuses != null)
          for (final s in statuses)
            _OrchBadge(label: s.toString(), color: _statusColor(s.toString())),
        if (category != null) _OrchBadge(label: 'cat: $category'),
        if (ids != null)
          _OrchBadge(
            label: ids.map((id) => 'TKT-$id').join(', '),
            color: Colors.teal,
          ),
        if (dependsOn != null)
          _OrchBadge(
            label: 'depends on TKT-${dependsOn.toInt()}',
            color: Colors.grey,
          ),
        if (dependencyOf != null)
          _OrchBadge(
            label: 'dependency of TKT-${dependencyOf.toInt()}',
            color: Colors.grey,
          ),
      ],
    );
  }
}

class _GetTicketInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _GetTicketInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final ticketId = input['ticket_id'] as num?;
    return Row(
      children: [
        Icon(Icons.assignment_outlined, size: IconSizes.xs, color: cciOrchColor),
        const SizedBox(width: 8),
        _OrchBadge(
          label: 'TKT-${ticketId?.toInt() ?? '?'}',
          color: Colors.teal,
        ),
      ],
    );
  }
}

class _UpdateTicketInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _UpdateTicketInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final ticketId = input['ticket_id'] as num?;
    final status = input['status'] as String?;
    final comment = input['comment'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _OrchBadge(
              label: 'TKT-${ticketId?.toInt() ?? '?'}',
              color: Colors.teal,
            ),
            if (status != null) ...[
              Icon(
                Icons.arrow_forward,
                size: IconSizes.xs,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              _OrchBadge(label: status, color: _statusColor(status)),
            ],
          ],
        ),
        if (comment != null && comment.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.comment_outlined,
                size: IconSizes.xs,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  comment,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: FontSizes.code,
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Worktree tool inputs
// -----------------------------------------------------------------------------

class _CreateWorktreeInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _CreateWorktreeInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final branchName = input['branch_name'] as String? ?? '';
    final baseRef = input['base_ref'] as String?;

    return Row(
      children: [
        Icon(Icons.account_tree_outlined, size: IconSizes.xs, color: cciOrchColor),
        const SizedBox(width: 8),
        _OrchBadge(label: branchName, color: Colors.teal),
        if (baseRef != null) ...[
          const SizedBox(width: 6),
          Text(
            'from ',
            style: TextStyle(
              fontSize: FontSizes.code,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          _OrchBadge(label: baseRef, color: Colors.grey),
        ],
      ],
    );
  }
}

class _RebaseAndMergeInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _RebaseAndMergeInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final worktreePath = input['worktree_path'] as String? ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Row(
      children: [
        Icon(Icons.merge, size: IconSizes.xs, color: cciOrchColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _shortPath(worktreePath),
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: FontSizes.code,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Tag tool inputs
// -----------------------------------------------------------------------------

class _SetTagsInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _SetTagsInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final worktree = input['worktree'] as String? ?? '';
    final tags = input['tags'] as List<dynamic>? ?? [];
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: IconSizes.xs,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _shortPath(worktree),
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: FontSizes.code,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in tags)
                _OrchBadge(label: tag.toString(), color: cciOrchColor),
            ],
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Result widgets
// =============================================================================

/// Dispatches to the correct orchestrator tool result widget.
class OrchToolResultWidget extends StatelessWidget {
  final String orchToolName;
  final dynamic result;

  const OrchToolResultWidget({
    super.key,
    required this.orchToolName,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final unwrapped = _unwrapContentBlocks(result);
    return switch (orchToolName) {
      'launch_agent' => _LaunchAgentResult(result: unwrapped),
      'tell_agent' => _TellAgentResult(result: unwrapped),
      'ask_agent' => _AskAgentResult(result: unwrapped),
      'wait_for_agents' => _WaitForAgentsResult(result: unwrapped),
      'check_agents' => _CheckAgentsResult(result: unwrapped),
      'create_ticket' => _CreateTicketResult(result: unwrapped),
      'list_tickets' => _ListTicketsResult(result: unwrapped),
      'get_ticket' => _GetTicketResult(result: unwrapped),
      'update_ticket' => _UpdateTicketResult(result: unwrapped),
      'create_worktree' => _CreateWorktreeResult(result: unwrapped),
      'rebase_and_merge' => _RebaseAndMergeResult(result: unwrapped),
      'set_tags' => _SetTagsResult(result: unwrapped),
      'list_tags' => _ListTagsResult(result: unwrapped),
      _ => _RawTextFallback(text: unwrapped?.toString() ?? ''),
    };
  }
}

// -----------------------------------------------------------------------------
// Agent tool results
// -----------------------------------------------------------------------------

class _LaunchAgentResult extends StatelessWidget {
  final dynamic result;

  const _LaunchAgentResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final agentId = parsed['agent_id'] as String? ?? '';
    final worktree = parsed['worktree'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: IconSizes.sm, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              'Agent launched',
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _OrchBadge(label: _shortAgentId(agentId)),
            if (worktree.isNotEmpty)
              _OrchBadge(label: _shortPath(worktree), color: Colors.teal),
          ],
        ),
      ],
    );
  }
}

class _TellAgentResult extends StatelessWidget {
  final dynamic result;

  const _TellAgentResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final restarted = parsed['restarted'] == true;

    return Row(
      children: [
        const Icon(Icons.check_circle, size: IconSizes.sm, color: Colors.green),
        const SizedBox(width: 8),
        Text(
          'Message sent',
          style: TextStyle(
            fontSize: FontSizes.bodySmall,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        if (restarted) ...[
          const SizedBox(width: 8),
          _OrchBadge(label: 'restarted', color: Colors.orange),
        ],
      ],
    );
  }
}

class _AskAgentResult extends StatelessWidget {
  final dynamic result;

  const _AskAgentResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final response = parsed['response'] as String? ?? '';
    final timedOut = parsed['wait_timed_out'] == true;
    final error = parsed['error'] as String?;
    final status = parsed['status'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status row
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (timedOut)
              _OrchBadge(label: 'timed out', color: Colors.orange)
            else
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: IconSizes.sm, color: Colors.green),
                  SizedBox(width: 4),
                ],
              ),
            if (status != null) _OrchBadge(label: status, color: Colors.grey),
          ],
        ),
        // Response text
        if (response.isNotEmpty) ...[
          const SizedBox(height: 6),
          ClickToScrollContainer(
            maxHeight: 300,
            padding: const EdgeInsets.all(8),
            backgroundColor: colorScheme.surfaceContainerHighest,
            borderRadius: Radii.smallBorderRadius,
            child: SelectableText(
              response,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: FontSizes.code,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
        // Error
        if (error != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.error_outline, size: IconSizes.xs, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  error,
                  style: TextStyle(
                    fontSize: FontSizes.code,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _WaitForAgentsResult extends StatelessWidget {
  final dynamic result;

  const _WaitForAgentsResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final ready = parsed['ready'] as List<dynamic>? ?? [];
    final timedOut = parsed['wait_timed_out'] == true;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              timedOut ? Icons.timer_off : Icons.check_circle,
              size: IconSizes.sm,
              color: timedOut ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(
              timedOut
                  ? '${ready.length} agent${ready.length == 1 ? '' : 's'} ready (timed out)'
                  : '${ready.length} agent${ready.length == 1 ? '' : 's'} ready',
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        if (ready.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final agent in ready)
            if (agent is Map<String, dynamic>)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    _OrchBadge(
                      label: _shortAgentId(agent['agent_id']?.toString() ?? ''),
                    ),
                    const SizedBox(width: 6),
                    if (agent['reason'] != null)
                      _OrchBadge(
                        label: agent['reason'].toString(),
                        color: Colors.grey,
                      ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}

class _CheckAgentsResult extends StatelessWidget {
  final dynamic result;

  const _CheckAgentsResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final agents = parsed['agents'] as List<dynamic>? ?? [];
    final errors = parsed['errors'] as List<dynamic>? ?? [];
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final agent in agents)
          if (agent is Map<String, dynamic>)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    _agentStatusIcon(agent['status']?.toString() ?? ''),
                    size: IconSizes.xs,
                    color: _agentStatusColor(agent['status']?.toString() ?? ''),
                  ),
                  const SizedBox(width: 6),
                  _OrchBadge(
                    label: _shortAgentId(agent['agent_id']?.toString() ?? ''),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _agentStatusText(agent),
                      style: GoogleFonts.getFont(
                        monoFont,
                        fontSize: FontSizes.code,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final err in errors)
            if (err is Map<String, dynamic>)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: IconSizes.xs,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${err['agent_id'] ?? ''}: ${err['error'] ?? ''}',
                        style: TextStyle(
                          fontSize: FontSizes.code,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }

  static IconData _agentStatusIcon(String status) {
    return switch (status) {
      'idle' || 'ready' => Icons.check_circle_outline,
      'working' || 'busy' => Icons.pending,
      'stopped' => Icons.stop_circle_outlined,
      'error' || 'errored' => Icons.error_outline,
      _ => Icons.circle_outlined,
    };
  }

  static Color _agentStatusColor(String status) {
    return switch (status) {
      'idle' || 'ready' => Colors.green,
      'working' || 'busy' => Colors.blue,
      'stopped' => Colors.grey,
      'error' || 'errored' => Colors.red,
      _ => Colors.grey,
    };
  }

  static String _agentStatusText(Map<String, dynamic> agent) {
    final status = agent['status']?.toString() ?? '';
    final turn = agent['turn'] as num?;
    final parts = <String>[
      status,
      if (turn != null) 'turn $turn',
    ];
    return parts.join(', ');
  }
}

// -----------------------------------------------------------------------------
// Ticket tool results
// -----------------------------------------------------------------------------

class _CreateTicketResult extends StatelessWidget {
  final dynamic result;

  const _CreateTicketResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final text = result?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return _RawTextFallback(text: text);
  }
}

class _ListTicketsResult extends StatelessWidget {
  final dynamic result;

  const _ListTicketsResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    final tickets = parsed?['tickets'] as List<dynamic>?;
    if (tickets == null) return _RawTextFallback(text: result?.toString() ?? '');

    if (tickets.isEmpty) {
      return Text(
        'No tickets found',
        style: TextStyle(
          fontSize: FontSizes.code,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    return ClickToScrollContainer(
      maxHeight: 300,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: Radii.smallBorderRadius,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final ticket in tickets)
              if (ticket is Map<String, dynamic>)
                _TicketRow(ticket: ticket),
          ],
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  final Map<String, dynamic> ticket;

  const _TicketRow({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final id = ticket['id'] as num? ?? ticket['ticket_id'] as num?;
    final displayId = ticket['display_id'] as String? ??
        (id != null ? 'TKT-${id.toInt()}' : '');
    final title = ticket['title'] as String? ?? '';
    final status = ticket['status'] as String? ?? '';
    final kind = ticket['kind'] as String? ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            _statusIcon(status),
            size: IconSizes.xs,
            color: _statusColor(status),
          ),
          const SizedBox(width: 6),
          Text(
            displayId,
            style: TextStyle(
              fontSize: FontSizes.code,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(width: 6),
          if (kind.isNotEmpty) ...[
            _OrchBadge(label: kind, color: _kindColor(kind)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: FontSizes.code,
                color: colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _GetTicketResult extends StatelessWidget {
  final dynamic result;

  const _GetTicketResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    final ticket = parsed?['ticket'] as Map<String, dynamic>?;
    if (ticket == null) return _RawTextFallback(text: result?.toString() ?? '');

    final id = ticket['id'] as num? ?? ticket['ticket_id'] as num?;
    final displayId = ticket['display_id'] as String? ??
        (id != null ? 'TKT-${id.toInt()}' : '');
    final title = ticket['title'] as String? ?? '';
    final status = ticket['status'] as String? ?? '';
    final kind = ticket['kind'] as String? ?? '';
    final priority = ticket['priority'] as String?;
    final description = ticket['description'] as String? ?? '';
    final dependsOn = ticket['depends_on'] as List<dynamic>?;
    final unblockedBy = parsed?['unblocked_by'] as List<dynamic>?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row
        Row(
          children: [
            Icon(
              _statusIcon(status),
              size: IconSizes.sm,
              color: _statusColor(status),
            ),
            const SizedBox(width: 6),
            Text(
              displayId,
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: FontSizes.bodySmall,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        // Metadata badges
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _OrchBadge(label: status, color: _statusColor(status)),
            if (kind.isNotEmpty)
              _OrchBadge(label: kind, color: _kindColor(kind)),
            if (priority != null)
              _OrchBadge(label: priority, color: _priorityColor(priority)),
          ],
        ),
        // Description
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          ClickToScrollContainer(
            maxHeight: 150,
            padding: const EdgeInsets.all(8),
            backgroundColor: colorScheme.surfaceContainerHighest,
            borderRadius: Radii.smallBorderRadius,
            child: SelectableText(
              description,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: FontSizes.code,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
        // Dependencies
        if (dependsOn != null && dependsOn.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Depends on: ',
                style: TextStyle(
                  fontSize: FontSizes.code,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final dep in dependsOn)
                      _OrchBadge(
                        label: 'TKT-${dep is num ? dep.toInt() : dep}',
                        color: Colors.grey,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
        // Unblocked by
        if (unblockedBy != null && unblockedBy.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Unblocked by: ',
                style: TextStyle(
                  fontSize: FontSizes.code,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final dep in unblockedBy)
                      _OrchBadge(
                        label: 'TKT-${dep is num ? dep.toInt() : dep}',
                        color: Colors.green,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _UpdateTicketResult extends StatelessWidget {
  final dynamic result;

  const _UpdateTicketResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final prevStatus = parsed['previous_status'] as String? ?? '';
    final newStatus = parsed['new_status'] as String? ?? '';
    final unblocked = parsed['unblocked_tickets'] as List<dynamic>? ?? [];
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: IconSizes.sm, color: Colors.green),
            const SizedBox(width: 8),
            if (prevStatus.isNotEmpty) ...[
              _OrchBadge(label: prevStatus, color: _statusColor(prevStatus)),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward,
                size: IconSizes.xs,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
            ],
            _OrchBadge(label: newStatus, color: _statusColor(newStatus)),
          ],
        ),
        if (unblocked.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Unblocked: ',
                style: TextStyle(
                  fontSize: FontSizes.code,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final id in unblocked)
                      _OrchBadge(
                        label: 'TKT-${id is num ? id.toInt() : id}',
                        color: Colors.green,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Worktree tool results
// -----------------------------------------------------------------------------

class _CreateWorktreeResult extends StatelessWidget {
  final dynamic result;

  const _CreateWorktreeResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final worktreePath = parsed['worktree_path'] as String? ?? '';
    final branch = parsed['branch'] as String? ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: IconSizes.sm, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              'Worktree created',
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.account_tree, size: IconSizes.xs, color: Colors.teal),
            const SizedBox(width: 6),
            _OrchBadge(label: branch, color: Colors.teal),
          ],
        ),
        if (worktreePath.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: IconSizes.xs,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  worktreePath,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: FontSizes.code,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RebaseAndMergeResult extends StatelessWidget {
  final dynamic result;

  const _RebaseAndMergeResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final success = parsed['success'] == true;
    final conflicts = parsed['conflicts'] as bool? ?? false;
    final mergedCommits = parsed['merged_commits'] as num?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              success && !conflicts ? Icons.check_circle : Icons.warning_amber,
              size: IconSizes.sm,
              color: success && !conflicts ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(
              conflicts ? 'Conflicts detected' : 'Merge successful',
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        if (mergedCommits != null) ...[
          const SizedBox(height: 4),
          Text(
            '${mergedCommits.toInt()} commit${mergedCommits.toInt() == 1 ? '' : 's'} merged',
            style: TextStyle(
              fontSize: FontSizes.code,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Tag tool results
// -----------------------------------------------------------------------------

class _SetTagsResult extends StatelessWidget {
  final dynamic result;

  const _SetTagsResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    if (parsed == null) return _RawTextFallback(text: result?.toString() ?? '');

    final tags = parsed['tags'] as List<dynamic>? ?? [];

    return Row(
      children: [
        const Icon(Icons.check_circle, size: IconSizes.sm, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in tags)
                _OrchBadge(label: tag.toString(), color: cciOrchColor),
            ],
          ),
        ),
      ],
    );
  }
}

class _ListTagsResult extends StatelessWidget {
  final dynamic result;

  const _ListTagsResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = _tryParseJson(result);
    final tags = parsed?['tags'] as List<dynamic>?;
    if (tags == null) return _RawTextFallback(text: result?.toString() ?? '');

    if (tags.isEmpty) {
      return Text(
        'No tags defined',
        style: TextStyle(
          fontSize: FontSizes.code,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          if (tag is Map<String, dynamic>)
            _OrchBadge(
              label: tag['name']?.toString() ?? '',
              color: _parseTagColor(tag['color'] as String?),
            ),
      ],
    );
  }

  static Color _parseTagColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return cciOrchColor;
    // Try to parse hex color like "#FF5722" or "FF5722"
    final hex = colorStr.replaceFirst('#', '');
    if (hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    return cciOrchColor;
  }
}
