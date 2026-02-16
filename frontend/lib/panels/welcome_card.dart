import 'package:agent_sdk_core/agent_sdk_core.dart' hide PermissionMode;
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent_config.dart';
import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/project.dart';
import '../services/backend_service.dart';
import '../services/cli_availability_service.dart';
import '../services/macro_executor.dart';
import '../services/runtime_config.dart';
import '../state/selection_state.dart';
import '../widgets/insights_widgets.dart';
import '../widgets/message_input.dart';
import '../widgets/security_config_group.dart';
import 'compact_dropdown.dart';
import 'conversation_header.dart';

/// Checks if an agent is available based on CLI availability.
bool _isAgentAvailable(AgentConfig agent, CliAvailabilityService cli) {
  return cli.isAgentAvailable(agent.id);
}

/// Welcome card shown when no chat is selected.
///
/// Displays project info and invites the user to start chatting.
/// Includes model/permission selectors and a message input box at the bottom
/// that creates a new chat and sends the first message.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final backendService = context.watch<BackendService>();
    final worktree = selection.selectedWorktree;
    final defaultModel = ChatModelCatalog.defaultFromComposite(
      RuntimeConfig.instance.defaultModel,
      fallbackBackend: RuntimeConfig.instance.defaultBackend,
    );

    Widget buildHeader() {
      final model = worktree?.welcomeModel ?? defaultModel;
      final caps = backendService.capabilitiesFor(model.backend);
      final isModelLoading =
          caps.supportsModelListing &&
          backendService.isModelListLoadingFor(model.backend);

      // Get security config from worktree or use default
      final sdk.SecurityConfig securityConfig;
      if (worktree != null) {
        securityConfig = worktree.welcomeSecurityConfig;
      } else {
        // Use default for the current backend
        final defaultBackend = RuntimeConfig.instance.defaultBackend;
        if (defaultBackend == sdk.BackendType.codex) {
          securityConfig = const sdk.CodexSecurityConfig(
            sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
            approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
          );
        } else {
          securityConfig = sdk.ClaudeSecurityConfig(
            permissionMode: sdk.PermissionMode.fromString(
              RuntimeConfig.instance.defaultPermissionMode,
            ),
          );
        }
      }

      return _WelcomeHeader(
        model: model,
        caps: caps,
        securityConfig: securityConfig,
        reasoningEffort: worktree?.welcomeReasoningEffort,
        isModelLoading: isModelLoading,
        codexCapabilities: backendService.codexSecurityCapabilities,
        onAgentChanged: (agentId) async {
          // Look up the agent config
          final agentConfig = RuntimeConfig.instance.agentById(agentId);
          if (agentConfig == null) return;

          final backendService = context.read<BackendService>();
          await backendService.startAgent(agentId, config: agentConfig);
          final error = backendService.errorForAgent(agentId);
          if (error != null) {
            if (context.mounted &&
                !backendService.isAgentErrorForAgent(agentId)) {
              showErrorSnackBar(context, error);
            }
            return;
          }

          // Update worktree with agent ID and model
          if (worktree != null) {
            worktree.welcomeAgentId = agentId;
            final model = ChatModelCatalog.defaultForBackend(
              agentConfig.backendType,
              agentConfig.defaultModel,
            );
            worktree.welcomeModel = model;
          }
        },
        onModelChanged: (model) => worktree?.welcomeModel = model,
        onSecurityConfigChanged: (config) =>
            worktree?.welcomeSecurityConfig = config,
        onReasoningChanged: (effort) =>
            worktree?.welcomeReasoningEffort = effort,
      );
    }

    return Column(
      children: [
        // Header with model/permission selectors
        if (worktree == null)
          ListenableBuilder(
            listenable: RuntimeConfig.instance,
            builder: (context, _) => buildHeader(),
          )
        else
          ListenableBuilder(
            listenable: Listenable.merge([worktree, RuntimeConfig.instance]),
            builder: (context, _) => buildHeader(),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Project icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.3,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        size: 48,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Project name
                    Text(
                      project.data.name,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Worktree path
                    if (worktree != null)
                      Text(
                        worktree.data.worktreeRoot,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 24),
                    // Welcome message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Welcome to CC-Insights',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a new conversation by typing a message below, '
                            'or click "New Chat" in the sidebar to create a '
                            'chat.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Message input - creates a new chat on submit
        // Use worktree path in key so each worktree gets its own input
        MessageInput(
          key: ValueKey(
            'input-welcome-${worktree?.data.worktreeRoot ?? 'none'}',
          ),
          initialText: worktree?.welcomeDraftText ?? '',
          onTextChanged: (text) => worktree?.welcomeDraftText = text,
          onSubmit: (text, images, displayFormat) =>
              MacroExecutor.createChatAndSendMessage(
                context,
                worktree: worktree,
                text: text,
                images: images,
                displayFormat: displayFormat,
                clearWelcomeDraft: true,
              ),
        ),
      ],
    );
  }
}

/// Header for the welcome card with model/permission selectors.
///
/// Similar layout to ConversationHeader but for the welcome state.
class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.model,
    required this.caps,
    required this.securityConfig,
    required this.reasoningEffort,
    required this.onModelChanged,
    required this.onSecurityConfigChanged,
    required this.onAgentChanged,
    required this.onReasoningChanged,
    required this.isModelLoading,
    required this.codexCapabilities,
  });

  final ChatModel model;
  final sdk.BackendCapabilities caps;
  final sdk.SecurityConfig securityConfig;
  final sdk.ReasoningEffort? reasoningEffort;
  final ValueChanged<ChatModel> onModelChanged;
  final ValueChanged<sdk.SecurityConfig> onSecurityConfigChanged;
  final ValueChanged<String> onAgentChanged;
  final ValueChanged<sdk.ReasoningEffort?> onReasoningChanged;
  final bool isModelLoading;
  final CodexSecurityCapabilities codexCapabilities;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // Left side: "New Chat" label and dropdowns
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_comment_outlined,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'New Chat',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Builder(
                    builder: (context) {
                      final cliAvailability = context
                          .watch<CliAvailabilityService>();
                      final allAgents = RuntimeConfig.instance.agents;
                      final availableAgents = allAgents
                          .where(
                            (agent) =>
                                _isAgentAvailable(agent, cliAvailability),
                          )
                          .toList();

                      // Handle empty agent list gracefully
                      if (availableAgents.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      // Determine current agent name from model backend
                      // (fallback logic for when agentId is not set)
                      final currentAgentName = availableAgents
                          .firstWhere(
                            (a) => a.backendType == model.backend,
                            orElse: () => availableAgents.first,
                          )
                          .name;

                      return CompactDropdown(
                        value: currentAgentName,
                        items: availableAgents.map((a) => a.name).toList(),
                        tooltip: 'Agent',
                        isEnabled: availableAgents.length > 1,
                        onChanged: (agentName) {
                          // Find agent by name
                          final selectedAgent = availableAgents.firstWhere(
                            (a) => a.name == agentName,
                            orElse: () => availableAgents.first,
                          );
                          onAgentChanged(selectedAgent.id);
                        },
                      );
                    },
                  ),
                  // Model dropdown (hidden for ACP — models are agent-managed)
                  if (model.backend != sdk.BackendType.acp) ...[
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final models = ChatModelCatalog.forBackend(
                          model.backend,
                        );
                        final selected = models.firstWhere(
                          (m) => m.id == model.id,
                          orElse: () => model,
                        );
                        return CompactDropdown(
                          value: selected.label,
                          items: models.map((m) => m.label).toList(),
                          isLoading: isModelLoading,
                          tooltip: 'Model',
                          onChanged: (value) {
                            final next = models.firstWhere(
                              (m) => m.label == value,
                              orElse: () => selected,
                            );
                            onModelChanged(next);
                          },
                        );
                      },
                    ),
                  ],
                  // Backend-conditional security controls
                  if (model.backend == sdk.BackendType.codex) ...[
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final config = securityConfig;
                        if (config is! sdk.CodexSecurityConfig) {
                          return const SizedBox.shrink();
                        }
                        return SecurityConfigGroup(
                          config: config,
                          capabilities: codexCapabilities,
                          isEnabled: true,
                          onConfigChanged: onSecurityConfigChanged,
                        );
                      },
                    ),
                  ] else if (model.backend != sdk.BackendType.acp) ...[
                    // Claude: permission mode dropdown
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final config = securityConfig;
                        final PermissionMode permissionMode;
                        if (config is sdk.ClaudeSecurityConfig) {
                          permissionMode = PermissionMode.fromApiName(
                            config.permissionMode.value,
                          );
                        } else {
                          permissionMode = PermissionMode.defaultMode;
                        }
                        return CompactDropdown(
                          value: permissionMode.label,
                          items: PermissionMode.values
                              .map((m) => m.label)
                              .toList(),
                          tooltip: 'Permissions',
                          onChanged: (value) {
                            final selected = PermissionMode.values.firstWhere(
                              (m) => m.label == value,
                              orElse: () => PermissionMode.defaultMode,
                            );
                            final sdkMode = sdk.PermissionMode.fromString(
                              selected.apiName,
                            );
                            onSecurityConfigChanged(
                              sdk.ClaudeSecurityConfig(permissionMode: sdkMode),
                            );
                          },
                        );
                      },
                    ),
                  ],
                  // Reasoning effort dropdown (capability-gated)
                  if (caps.supportsReasoningEffort) ...[
                    const SizedBox(width: 8),
                    CompactDropdown(
                      value: reasoningEffort?.label ?? 'Default',
                      items: reasoningEffortItems,
                      tooltip: 'Reasoning',
                      onChanged: (value) {
                        final effort = reasoningEffortFromLabel(value);
                        onReasoningChanged(effort);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Right side: empty for new chat (no usage data yet)
        ],
      ),
    );
  }
}
