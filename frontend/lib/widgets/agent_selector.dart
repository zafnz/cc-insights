import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../acp/acp_client_wrapper.dart';
import '../services/agent_registry.dart';

/// A dropdown selector for choosing an ACP agent.
///
/// This widget displays available agents from the [AgentRegistry]
/// and allows the user to select one for a new chat session.
///
/// The widget uses Provider's [Consumer] to watch the registry for changes,
/// automatically rebuilding when agents are discovered, added, or removed.
///
/// Example usage:
/// ```dart
/// AgentSelector(
///   selectedAgent: currentAgent,
///   onSelect: (agent) {
///     setState(() => currentAgent = agent);
///   },
/// )
/// ```
///
/// When no agents are available, displays an error message instead of
/// the dropdown. The dropdown shows agent icons based on the agent ID
/// to help users quickly identify different agent types.
class AgentSelector extends StatelessWidget {
  /// Creates an agent selector widget.
  ///
  /// The [selectedAgent] is the currently selected agent, if any.
  /// The [onSelect] callback is called when the user selects an agent.
  /// The [hint] is displayed when no agent is selected.
  const AgentSelector({
    super.key,
    this.selectedAgent,
    this.onSelect,
    this.hint = 'Select an agent',
  });

  /// Currently selected agent, if any.
  final AgentConfig? selectedAgent;

  /// Called when an agent is selected.
  final void Function(AgentConfig agent)? onSelect;

  /// Hint text when no agent is selected.
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentRegistry>(
      builder: (context, registry, _) {
        final agents = registry.agents;

        if (agents.isEmpty) {
          return Text(
            'No agents available',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          );
        }

        return DropdownButton<AgentConfig>(
          value: selectedAgent,
          hint: Text(hint),
          isExpanded: true,
          items: agents.map((agent) {
            return DropdownMenuItem<AgentConfig>(
              value: agent,
              child: _AgentDropdownItem(agent: agent),
            );
          }).toList(),
          onChanged: (agent) {
            if (agent != null) {
              onSelect?.call(agent);
            }
          },
        );
      },
    );
  }
}

/// A dropdown menu item showing an agent's icon and name.
class _AgentDropdownItem extends StatelessWidget {
  const _AgentDropdownItem({required this.agent});

  final AgentConfig agent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_getAgentIcon(agent.id), size: 20),
        const SizedBox(width: 8),
        Text(agent.name),
      ],
    );
  }

  /// Returns an appropriate icon for the given agent ID.
  ///
  /// Uses specific icons for known agent types:
  /// - Claude Code: psychology (brain) icon
  /// - Gemini CLI: auto_awesome (stars) icon
  /// - Codex CLI: code icon
  /// - Other agents: smart_toy (robot) icon
  IconData _getAgentIcon(String agentId) {
    switch (agentId) {
      case 'claude-code':
        return Icons.psychology;
      case 'gemini-cli':
        return Icons.auto_awesome;
      case 'codex-cli':
        return Icons.code;
      default:
        return Icons.smart_toy;
    }
  }
}
