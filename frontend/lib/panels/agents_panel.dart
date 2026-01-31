import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent.dart';
import '../models/conversation.dart';
import '../state/selection_state.dart';
import 'panel_wrapper.dart';

/// Agents panel - shows primary chat + subagent conversations for the selected chat.
class AgentsPanel extends StatelessWidget {
  const AgentsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelWrapper(
      title: 'Agents',
      icon: Icons.smart_toy_outlined,
      child: _AgentsListContent(),
    );
  }
}

/// Content of the agents list panel (without header - that's in PanelWrapper).
/// Shows the primary "Chat" conversation first, followed by subagent conversations.
class _AgentsListContent extends StatelessWidget {
  const _AgentsListContent();

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final selectedChat = selection.selectedChat;

    if (selectedChat == null) {
      return const _EmptyAgentsPlaceholder(
        message: 'Select a chat to view agents',
      );
    }

    // Watch the ChatState to rebuild when subagents are added/updated.
    // We use ListenableBuilder to watch the ChatState directly since
    // it's not provided through Provider (it comes from SelectionState).
    return ListenableBuilder(
      listenable: selectedChat,
      builder: (context, _) {
        final primaryConversation = selectedChat.data.primaryConversation;
        final subagents =
            selectedChat.data.subagentConversations.values.toList();
        final activeAgents = selectedChat.activeAgents;

        return _buildAgentsList(
          context,
          selection,
          primaryConversation,
          subagents,
          activeAgents,
        );
      },
    );
  }

  Widget _buildAgentsList(
    BuildContext context,
    SelectionState selection,
    ConversationData primaryConversation,
    List<ConversationData> subagents,
    Map<String, Agent> activeAgents,
  ) {
    // Reverse subagents so newest appears first (after main chat)
    final reversedSubagents = subagents.reversed.toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Primary "Chat" entry - always first
        _PrimaryChatListItem(
          conversation: primaryConversation,
          isSelected: selection.selectedConversation == primaryConversation,
          onTap: () => selection.selectConversation(primaryConversation),
        ),
        // Subagent entries (newest first)
        ...reversedSubagents.map((subagent) {
          // Find the agent for this conversation
          final agent = activeAgents.values.cast<Agent?>().firstWhere(
            (a) => a?.conversationId == subagent.id,
            orElse: () => null,
          );
          return _AgentListItem(
            conversation: subagent,
            isSelected: selection.selectedConversation == subagent,
            onTap: () => selection.selectConversation(subagent),
            agentStatus: agent?.status,
          );
        }),
      ],
    );
  }
}

/// Placeholder when no agents are available.
class _EmptyAgentsPlaceholder extends StatelessWidget {
  const _EmptyAgentsPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Text(
        message,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The primary "Chat" entry that appears first in the agents list.
class _PrimaryChatListItem extends StatelessWidget {
  const _PrimaryChatListItem({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
  });

  final ConversationData conversation;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Chat icon (different from subagent icon)
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              // "Chat" label
              Expanded(
                child: Text(
                  'Chat',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Entry count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${conversation.entries.length}',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single compact agent/subagent entry in the list.
///
/// Display format:
/// - Line 1: Task description (or "Subagent #N" fallback)
/// - Line 2: subagent_type (or blank if none)
class _AgentListItem extends StatelessWidget {
  const _AgentListItem({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    this.agentStatus,
  });

  final ConversationData conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final AgentStatus? agentStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Primary line: description, or fallback to "Subagent #N"
    final primaryLabel = conversation.taskDescription ??
        'Subagent #${conversation.subagentNumber ?? '?'}';

    // Secondary line: subagent_type (may be null)
    final secondaryLabel = conversation.label;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Agent icon
              Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              // Agent description and type
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryLabel,
                      style: textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (secondaryLabel != null)
                      Text(
                        secondaryLabel,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
              // Status indicator
              if (agentStatus != null) ...[
                _AgentStatusIndicator(status: agentStatus!),
                const SizedBox(width: 4),
              ],
              // Entry count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${conversation.entries.length}',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact status indicator for an agent.
class _AgentStatusIndicator extends StatelessWidget {
  const _AgentStatusIndicator({required this.status});

  final AgentStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return switch (status) {
      AgentStatus.working => SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: colorScheme.primary,
        ),
      ),
      AgentStatus.waitingTool => Tooltip(
        message: 'Waiting for tool permission',
        child: Icon(
          Icons.hourglass_empty,
          size: 12,
          color: colorScheme.tertiary,
        ),
      ),
      AgentStatus.waitingUser => Tooltip(
        message: 'Waiting for user input',
        child: Icon(
          Icons.person_outline,
          size: 12,
          color: colorScheme.secondary,
        ),
      ),
      AgentStatus.completed => Tooltip(
        message: 'Completed',
        child: Icon(
          Icons.check_circle,
          size: 12,
          color: colorScheme.primary,
        ),
      ),
      AgentStatus.error => Tooltip(
        message: 'Error',
        child: Icon(
          Icons.error_outline,
          size: 12,
          color: colorScheme.error,
        ),
      ),
    };
  }
}
