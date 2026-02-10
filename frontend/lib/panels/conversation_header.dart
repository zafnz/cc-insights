import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/conversation.dart';
import '../services/backend_service.dart';
import '../services/cli_availability_service.dart';
import '../widgets/context_indicator.dart';
import '../widgets/cost_indicator.dart';
import '../widgets/insights_widgets.dart';
import 'compact_dropdown.dart';

// -----------------------------------------------------------------------------
// Shared helpers used by both ConversationHeader and WelcomeHeader
// -----------------------------------------------------------------------------

/// Labels for reasoning effort dropdown.
/// 'Default' means null (use model's default).
const List<String> reasoningEffortItems = [
  'Default',
  'None',
  'Minimal',
  'Low',
  'Medium',
  'High',
  'Extra High',
];

/// Returns a display label for a backend type.
String agentLabel(sdk.BackendType backend) {
  return backend == sdk.BackendType.codex ? 'Codex' : 'Claude';
}

/// Converts a display label to a backend type.
sdk.BackendType backendFromAgent(String value) {
  return value == 'Codex' ? sdk.BackendType.codex : sdk.BackendType.directCli;
}

/// Converts a dropdown label to a ReasoningEffort value.
/// Returns null for 'Default'.
sdk.ReasoningEffort? reasoningEffortFromLabel(String label) {
  return switch (label) {
    'Default' => null,
    'None' => sdk.ReasoningEffort.none,
    'Minimal' => sdk.ReasoningEffort.minimal,
    'Low' => sdk.ReasoningEffort.low,
    'Medium' => sdk.ReasoningEffort.medium,
    'High' => sdk.ReasoningEffort.high,
    'Extra High' => sdk.ReasoningEffort.xhigh,
    _ => null,
  };
}

// -----------------------------------------------------------------------------
// ConversationHeader
// -----------------------------------------------------------------------------

/// Header showing conversation context with model/permission selectors and usage.
///
/// Layout behavior:
/// - >= 700px: All elements visible (name, dropdowns, context, tokens)
/// - >= 500px: Context and tokens visible, dropdowns clip under them
/// - >= 350px: Only tokens visible
/// - < 350px: Only chat name visible
class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.conversation,
    required this.chat,
  });

  final ConversationData conversation;
  final ChatState chat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backendService = context.watch<BackendService>();

    final isSubagent = !conversation.isPrimary;

    // Don't show the toolbar for subagent conversations (title is in panel header)
    if (isSubagent) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final showContext = width >= 500;
          final showTokens = width >= 350;
          final isBackendLocked = chat.hasStarted;
          final caps = backendService.capabilitiesFor(chat.model.backend);
          final currentAgentLabel = agentLabel(chat.model.backend);
          final showCost = chat.model.backend != sdk.BackendType.codex;

          return Row(
            children: [
              // Left side: agent, model, and permission dropdowns
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (context) {
                          final cliAvailability =
                              context.watch<CliAvailabilityService>();
                          final agentItems = cliAvailability.codexAvailable
                              ? const ['Claude', 'Codex']
                              : const ['Claude'];
                          return CompactDropdown(
                            value: agentLabel(chat.model.backend),
                            items: agentItems,
                            tooltip: 'Agent',
                            isEnabled: !isBackendLocked &&
                                agentItems.length > 1,
                            onChanged: (value) {
                              unawaited(
                                _handleAgentChange(context, chat, value),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) {
                          final models = ChatModelCatalog.forBackend(
                            chat.model.backend,
                          );
                          final selected = models.firstWhere(
                            (m) => m.id == chat.model.id,
                            orElse: () => chat.model,
                          );
                          final isModelLoading =
                              caps.supportsModelListing &&
                              backendService.isModelListLoadingFor(
                                chat.model.backend,
                              );
                          return CompactDropdown(
                            value: selected.label,
                            items: models.map((m) => m.label).toList(),
                            isLoading: isModelLoading,
                            tooltip: 'Model',
                            onChanged: (value) {
                              final model = models.firstWhere(
                                (m) => m.label == value,
                                orElse: () => selected,
                              );
                              chat.setModel(model);
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      CompactDropdown(
                        value: chat.permissionMode.label,
                        items: PermissionMode.values
                            .map((m) => m.label)
                            .toList(),
                        tooltip: 'Permissions',
                        onChanged: (value) {
                          final mode = PermissionMode.values.firstWhere(
                            (m) => m.label == value,
                            orElse: () => PermissionMode.defaultMode,
                          );
                          chat.setPermissionMode(mode);
                        },
                      ),
                      // Reasoning effort dropdown (only for backends that support it)
                      if (caps.supportsReasoningEffort) ...[
                        const SizedBox(width: 8),
                        CompactDropdown(
                          value: chat.reasoningEffort?.label ?? 'Default',
                          items: reasoningEffortItems,
                          tooltip: 'Reasoning',
                          onChanged: (value) {
                            final effort = reasoningEffortFromLabel(value);
                            chat.setReasoningEffort(effort);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Right side: context indicator and token/cost
              if (showContext) ...[
                const SizedBox(width: 8),
                ContextIndicator(tracker: chat.contextTracker),
              ],
              if (showTokens) ...[
                const SizedBox(width: 8),
                CostIndicator(
                  usage: chat.cumulativeUsage,
                  modelUsage: chat.modelUsage,
                  timingStats: chat.timingStats,
                  agentLabel: currentAgentLabel,
                  showCost: showCost,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleAgentChange(
    BuildContext context,
    ChatState chat,
    String value,
  ) async {
    final backendType = backendFromAgent(value);
    if (backendType == chat.model.backend) return;

    if (chat.hasActiveSession) {
      _showBackendSwitchError(
        context,
        'End the active session before switching agents.',
      );
      return;
    }

    if (chat.hasStarted) {
      _showBackendSwitchError(
        context,
        'Backend is locked once a chat has started.',
      );
      return;
    }

    final backendService = context.read<BackendService>();
    await backendService.start(type: backendType);
    final error = backendService.errorFor(backendType);
    if (error != null) {
      _showBackendSwitchError(context, error);
      return;
    }

    final model = ChatModelCatalog.defaultForBackend(backendType, null);
    chat.setModel(model);
  }

  void _showBackendSwitchError(BuildContext context, String message) {
    showErrorSnackBar(context, message);
  }
}

// -----------------------------------------------------------------------------
// SubagentStatusHeader
// -----------------------------------------------------------------------------

/// Status header shown for subagent conversations.
///
/// Displays:
/// - Agent label/name
/// - Task description
/// - Current status (working, completed, error, etc.)
/// - Result summary when completed
class SubagentStatusHeader extends StatelessWidget {
  const SubagentStatusHeader({
    super.key,
    required this.conversation,
    required this.agent,
  });

  final ConversationData conversation;
  final Agent? agent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Determine status info
    final status = agent?.status;
    final (statusLabel, statusColor, statusIcon) = _getStatusInfo(
      status,
      colorScheme,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // First row: status badge and task description
          Row(
            children: [
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusIcon,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Task description
              if (conversation.taskDescription != null)
                Expanded(
                  child: Text(
                    conversation.taskDescription!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          // Second row: result summary (if completed)
          if (agent?.result != null && agent!.result!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.summarize_outlined,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      agent!.result!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns status label, color, and icon based on agent status.
  (String, Color, IconData) _getStatusInfo(
    AgentStatus? status,
    ColorScheme colorScheme,
  ) {
    return switch (status) {
      AgentStatus.working => (
          'Working',
          colorScheme.primary,
          Icons.sync,
        ),
      AgentStatus.waitingTool => (
          'Waiting for permission',
          Colors.orange,
          Icons.hourglass_top,
        ),
      AgentStatus.waitingUser => (
          'Waiting for input',
          Colors.orange,
          Icons.question_mark,
        ),
      AgentStatus.completed => (
          'Completed',
          Colors.green,
          Icons.check_circle_outline,
        ),
      AgentStatus.error => (
          'Error',
          colorScheme.error,
          Icons.error_outline,
        ),
      null => (
          'Inactive',
          colorScheme.onSurfaceVariant,
          Icons.pause_circle_outline,
        ),
    };
  }
}
