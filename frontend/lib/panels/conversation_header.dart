import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/agent.dart';
import '../models/agent_config.dart';
import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/conversation.dart';
import '../services/backend_service.dart';
import '../services/cli_availability_service.dart';
import '../services/runtime_config.dart';
import '../widgets/context_indicator.dart';
import '../widgets/cost_indicator.dart';
import '../widgets/insights_widgets.dart';
import '../widgets/security_badge.dart';
import '../widgets/security_config_group.dart';
import '../widgets/styled_popup_menu.dart';
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

/// Returns a display label for a backend type (fallback for legacy chats).
String _agentLabel(sdk.BackendType backend) {
  return switch (backend) {
    sdk.BackendType.directCli => 'Claude',
    sdk.BackendType.codex => 'Codex',
    sdk.BackendType.acp => 'ACP',
  };
}

/// Checks if an agent is available based on CLI availability.
bool _isAgentAvailable(AgentConfig agent, CliAvailabilityService cli) {
  return cli.isAgentAvailable(agent.id);
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
/// - Toolbar wraps to additional lines when space is tight
/// - Security permissions stay grouped as a single unit
/// - Indicators remain visible instead of clipping
class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.conversation,
    required this.chat,
  });

  final ConversationData conversation;
  final Chat chat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backendService = context.watch<BackendService>();
    final settings = chat.settings;
    final session = chat.session;
    final metrics = chat.metrics;
    final agents = chat.agents;

    final isSubagent = !conversation.isPrimary;
    final isAcp = settings.model.backend == sdk.BackendType.acp;
    final acpConfigWidgets = isAcp
        ? _buildAcpConfigWidgets(settings)
        : const <Widget>[];

    // Check if backend is starting for this chat's agent
    final startingAgent =
        (agents.agentId != null &&
            backendService.isStartingForAgent(agents.agentId!))
        ? agents.agentName
        : null;

    // Don't show the toolbar for subagent conversations (title is in panel header)
    if (isSubagent) {
      return const SizedBox.shrink();
    }

    final isBackendLocked = session.hasStarted;
    // Use agent-keyed capabilities when available
    final caps = agents.agentId != null
        ? backendService.capabilitiesForAgent(agents.agentId!)
        : backendService.capabilitiesFor(settings.model.backend);
    const showCost = true;
    final rightWidgets = <Widget>[
      if (settings.model.backend == sdk.BackendType.codex &&
          session.hasActiveSession)
        Builder(
          builder: (context) {
            final config = settings.securityConfig;
            if (config is sdk.CodexSecurityConfig) {
              return SecurityBadge(config: config);
            }
            return const SizedBox.shrink();
          },
        ),
      ContextIndicator(tracker: metrics.contextTracker),
      CostIndicator(
        usage: metrics.cumulativeUsage,
        modelUsage: metrics.modelUsage,
        timingStats: metrics.timingStats,
        agentLabel: agents.agentName,
        showCost: showCost,
      ),
    ];

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showHeaderContextMenu(context, details.globalPosition);
      },
      child: Container(
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left side: agent, model, and permission dropdowns
            Expanded(
              child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Builder(
                  builder: (context) {
                    final cliAvailability = context
                        .watch<CliAvailabilityService>();
                    final allAgents = RuntimeConfig.instance.agents;
                    final availableAgents = allAgents
                        .where(
                          (agent) => _isAgentAvailable(agent, cliAvailability),
                        )
                        .toList();

                    // Handle empty agent list gracefully
                    if (availableAgents.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    // Get current agent name
                    final currentAgentName = agents.agentName;

                    final isAgentStarting =
                        agents.agentId != null &&
                        backendService.isStartingForAgent(agents.agentId!);

                    return CompactDropdown(
                      value: currentAgentName,
                      items: availableAgents.map((a) => a.name).toList(),
                      tooltip: 'Agent',
                      isLoading: isAgentStarting,
                      isEnabled:
                          !isBackendLocked &&
                          !isAgentStarting &&
                          availableAgents.length > 1,
                      onChanged: (agentName) {
                        // Find agent by name
                        final selectedAgent = availableAgents.firstWhere(
                          (a) => a.name == agentName,
                          orElse: () => availableAgents.first,
                        );
                        unawaited(
                          _handleAgentChange(context, chat, selectedAgent.id),
                        );
                      },
                    );
                  },
                ),
                if (startingAgent != null)
                  _buildBackendStartingIndicator(context, startingAgent),
                if (!isAcp)
                  Builder(
                    builder: (context) {
                      final models = ChatModelCatalog.forBackend(
                        settings.model.backend,
                      );
                      final selected = models.firstWhere(
                        (m) => m.id == settings.model.id,
                        orElse: () => settings.model,
                      );
                      final isModelLoading =
                          caps.supportsModelListing &&
                          (agents.agentId != null
                              ? backendService.isModelListLoadingForAgent(
                                  agents.agentId!,
                                )
                              : backendService.isModelListLoadingFor(
                                  settings.model.backend,
                                ));
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
                          settings.setModel(model);
                        },
                      );
                    },
                  )
                else
                  ...acpConfigWidgets,
                // Backend-specific security controls
                if (settings.model.backend == sdk.BackendType.codex) ...[
                  Builder(
                    builder: (context) {
                      final config = settings.securityConfig;
                      if (config is! sdk.CodexSecurityConfig) {
                        return const SizedBox.shrink();
                      }
                      final codexCaps = agents.agentId != null
                          ? backendService.codexSecurityCapabilitiesForAgent(
                              agents.agentId!,
                            )
                          : backendService.codexSecurityCapabilities;
                      return SecurityConfigGroup(
                        config: config,
                        capabilities: codexCaps,
                        isEnabled: true,
                        onConfigChanged: (newConfig) {
                          settings.setSecurityConfig(newConfig);
                        },
                      );
                    },
                  ),
                ] else if (!isAcp) ...[
                  // Claude: existing single dropdown (unchanged)
                  CompactDropdown(
                    value: settings.permissionMode.label,
                    items: PermissionMode.values.map((m) => m.label).toList(),
                    tooltip: 'Permissions',
                    onChanged: (value) {
                      final mode = PermissionMode.values.firstWhere(
                        (m) => m.label == value,
                        orElse: () => PermissionMode.defaultMode,
                      );
                      settings.setPermissionMode(mode);
                    },
                  ),
                ],
                // Reasoning effort dropdown (only for backends that support it)
                if (caps.supportsReasoningEffort)
                  CompactDropdown(
                    value: settings.reasoningEffort?.label ?? 'Default',
                    items: reasoningEffortItems,
                    tooltip: 'Reasoning',
                    onChanged: (value) {
                      final effort = reasoningEffortFromLabel(value);
                      settings.setReasoningEffort(effort);
                    },
                  ),
              ],
            ),
          ),
          if (rightWidgets.isNotEmpty) ...[
            const SizedBox(width: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: rightWidgets,
            ),
          ],
        ],
      ),
      ),
    );
  }

  void _showHeaderContextMenu(BuildContext context, Offset position) {
    final chatId = chat.data.id;
    showStyledMenu<String>(
      context: context,
      position: menuPositionFromOffset(position),
      items: [
        styledMenuItem(
          value: 'copy_chat_id',
          child: const Row(
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Text('Copy Chat ID'),
            ],
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: chatId));
          },
        ),
      ],
    );
  }

  Future<void> _handleAgentChange(
    BuildContext context,
    Chat chat,
    String agentId,
  ) async {
    // Look up the agent config from RuntimeConfig
    final agentConfig = RuntimeConfig.instance.agentById(agentId);
    if (agentConfig == null) return;

    final backendType = agentConfig.backendType;
    if (backendType == chat.settings.model.backend &&
        chat.agents.agentId == agentId) {
      return;
    }

    if (chat.session.hasActiveSession) {
      _showBackendSwitchError(
        context,
        'End the active session before switching agents.',
      );
      return;
    }

    if (chat.session.hasStarted) {
      _showBackendSwitchError(
        context,
        'Backend is locked once a chat has started.',
      );
      return;
    }

    // Set agent ID optimistically so the dropdown updates immediately
    // and the loading indicator shows for the correct agent.
    final previousAgentId = chat.agents.agentId;
    chat.agents.agentId = agentId;

    final backendService = context.read<BackendService>();
    await backendService.startAgent(agentId, config: agentConfig);
    final error = backendService.errorForAgent(agentId);
    if (error != null) {
      // Revert to previous agent on failure
      chat.agents.agentId = previousAgentId;
      if (!context.mounted) return;
      if (!backendService.isAgentErrorForAgent(agentId)) {
        _showBackendSwitchError(context, error);
      }
      return;
    }

    // Set the model from the agent config
    final model = ChatModelCatalog.defaultForBackend(
      backendType,
      agentConfig.defaultModel,
    );
    chat.settings.setModel(model);
  }

  void _showBackendSwitchError(BuildContext context, String message) {
    showErrorSnackBar(context, message);
  }

  Widget _buildBackendStartingIndicator(
    BuildContext context,
    String agentName,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Starting $agentName...',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ACP config option helpers
// -----------------------------------------------------------------------------

List<Widget> _buildAcpConfigWidgets(ChatSettingsState settings) {
  final options = _parseAcpConfigOptions(settings.acpConfigOptions);
  if (options.isEmpty &&
      (settings.acpAvailableModes == null ||
          (settings.acpAvailableModes?.length ?? 0) <= 1)) {
    return const [];
  }

  final widgets = <Widget>[];
  final modelOptions = options.where((o) => o.category == 'model').toList();
  final modeOptions = options.where((o) => o.category == 'mode').toList();
  final otherOptions = options
      .where((o) => o.category != 'model' && o.category != 'mode')
      .toList();

  for (final option in modelOptions) {
    final widget = _buildAcpOptionDropdown(option, settings);
    if (widget != null) widgets.add(widget);
  }

  for (final option in modeOptions) {
    final widget = _buildAcpOptionDropdown(option, settings);
    if (widget != null) widgets.add(widget);
  }

  if (modeOptions.isEmpty) {
    final fallback = _buildAcpModeFallback(settings);
    if (fallback != null) widgets.add(fallback);
  }

  final overflow = _buildAcpOverflowDropdown(otherOptions, settings);
  if (overflow != null) widgets.add(overflow);

  return widgets;
}

Widget? _buildAcpOptionDropdown(
  _AcpConfigOption option,
  ChatSettingsState settings,
) {
  if (option.values.length <= 1) return null;
  final items = option.values.map((v) => v.label).toList();
  final selectedLabel = option.selectedLabel();
  return CompactDropdown(
    value: selectedLabel,
    items: items,
    tooltip: option.name,
    onChanged: (valueLabel) {
      final selectedValue =
          option.valueForLabel(valueLabel) ?? option.values.first.value;
      settings.setAcpConfigOption(configId: option.id, value: selectedValue);
    },
  );
}

Widget? _buildAcpModeFallback(ChatSettingsState settings) {
  final modes = _parseAcpModes(settings.acpAvailableModes);
  if (modes.length <= 1) return null;
  final currentMode = settings.acpCurrentModeId;
  final selectedLabel = _resolveSelectedLabel(modes, currentMode);
  return CompactDropdown(
    value: selectedLabel,
    items: modes.map((m) => m.label).toList(),
    tooltip: 'Mode',
    onChanged: (valueLabel) {
      final selected = modes.firstWhere(
        (mode) => mode.label == valueLabel,
        orElse: () => modes.first,
      );
      settings.setAcpMode(selected.value.toString());
    },
  );
}

Widget? _buildAcpOverflowDropdown(
  List<_AcpConfigOption> options,
  ChatSettingsState settings,
) {
  final items = <String>[];
  final selectionMap = <String, _AcpConfigSelection>{};

  for (final option in options) {
    if (option.values.length <= 1) continue;
    for (final value in option.values) {
      var label = '${option.name}: ${value.label}';
      if (selectionMap.containsKey(label)) {
        label = '$label (${option.id})';
      }
      selectionMap[label] = _AcpConfigSelection(
        configId: option.id,
        value: value.value,
      );
      items.add(label);
    }
  }

  if (items.isEmpty) return null;

  return CompactDropdown(
    value: 'More',
    items: items,
    tooltip: 'More',
    onChanged: (label) {
      final selection = selectionMap[label];
      if (selection == null) return;
      settings.setAcpConfigOption(
        configId: selection.configId,
        value: selection.value,
      );
    },
  );
}

List<_AcpConfigOption> _parseAcpConfigOptions(
  List<Map<String, dynamic>>? rawOptions,
) {
  if (rawOptions == null || rawOptions.isEmpty) return const [];
  final parsed = <_AcpConfigOption>[];

  for (final option in rawOptions) {
    final id = _readString(option, const ['id', 'configId']);
    if (id == null || id.isEmpty) continue;
    final name = _readString(option, const ['name', 'title', 'label']) ?? id;
    final category =
        (_readString(option, const ['category', 'group']) ?? 'other')
            .toLowerCase();
    final values = _parseAcpValues(
      option['values'] ?? option['options'] ?? option['choices'],
    );
    if (values.isEmpty) continue;
    final currentValue =
        option['value'] ??
        option['currentValue'] ??
        option['selectedValue'] ??
        option['defaultValue'];

    parsed.add(
      _AcpConfigOption(
        id: id,
        name: name,
        category: category,
        values: values,
        currentValue: currentValue,
      ),
    );
  }

  return parsed;
}

List<_AcpConfigValue> _parseAcpValues(Object? rawValues) {
  if (rawValues is List) {
    final values = <_AcpConfigValue>[];
    for (final entry in rawValues) {
      if (entry is Map) {
        final map = Map<String, dynamic>.from(entry);
        final value = map['value'] ?? map['id'] ?? map['name'];
        final label = map['label'] ?? map['name'] ?? map['title'] ?? value;
        if (label != null) {
          values.add(
            _AcpConfigValue(
              value: value ?? label.toString(),
              label: label.toString(),
            ),
          );
        }
      } else if (entry != null) {
        values.add(_AcpConfigValue(value: entry, label: entry.toString()));
      }
    }
    return values;
  }
  return const [];
}

List<_AcpConfigValue> _parseAcpModes(List<Map<String, dynamic>>? rawModes) {
  if (rawModes == null || rawModes.isEmpty) return const [];
  final values = <_AcpConfigValue>[];
  for (final mode in rawModes) {
    final id = _readString(mode, const ['id', 'modeId', 'value']) ?? '';
    final label = _readString(mode, const ['name', 'label', 'title']) ?? id;
    if (id.isEmpty || label.isEmpty) continue;
    values.add(_AcpConfigValue(value: id, label: label));
  }
  return values;
}

String _resolveSelectedLabel(
  List<_AcpConfigValue> values,
  dynamic currentValue,
) {
  if (values.isEmpty) return '';
  if (currentValue == null) return values.first.label;
  final currentKey = _valueKey(currentValue);
  for (final value in values) {
    if (_valueKey(value.value) == currentKey) {
      return value.label;
    }
  }
  return values.first.label;
}

String? _readString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _valueKey(dynamic value) {
  if (value is Map) {
    final id = value['id'] ?? value['value'] ?? value['name'];
    if (id != null) return id.toString();
  }
  return value?.toString() ?? '';
}

class _AcpConfigOption {
  const _AcpConfigOption({
    required this.id,
    required this.name,
    required this.category,
    required this.values,
    required this.currentValue,
  });

  final String id;
  final String name;
  final String category;
  final List<_AcpConfigValue> values;
  final dynamic currentValue;

  String selectedLabel() => _resolveSelectedLabel(values, currentValue);

  dynamic valueForLabel(String label) {
    for (final value in values) {
      if (value.label == label) return value.value;
    }
    return null;
  }
}

class _AcpConfigValue {
  const _AcpConfigValue({required this.value, required this.label});

  final dynamic value;
  final String label;
}

class _AcpConfigSelection {
  const _AcpConfigSelection({required this.configId, required this.value});

  final String configId;
  final dynamic value;
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
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
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
      AgentStatus.working => ('Working', colorScheme.primary, Icons.sync),
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
      AgentStatus.error => ('Error', colorScheme.error, Icons.error_outline),
      null => (
        'Inactive',
        colorScheme.onSurfaceVariant,
        Icons.pause_circle_outline,
      ),
    };
  }
}
