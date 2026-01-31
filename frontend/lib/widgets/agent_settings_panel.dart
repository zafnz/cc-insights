import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../acp/acp_client_wrapper.dart';
import '../services/agent_registry.dart';

/// Keys for testing AgentSettingsPanel widgets.
///
/// Use these keys in tests to reliably find widgets without depending on
/// text content which may change with localization or formatting.
class AgentSettingsPanelKeys {
  AgentSettingsPanelKeys._();

  /// The root container of the settings panel.
  static const panel = Key('agent_settings_panel');

  /// The refresh button in the header.
  static const refreshButton = Key('agent_settings_refresh_button');

  /// The add agent button in the header.
  static const addButton = Key('agent_settings_add_button');

  /// The discovered agents section header.
  static const discoveredSection = Key('agent_settings_discovered_section');

  /// The custom agents section header.
  static const customSection = Key('agent_settings_custom_section');

  /// The empty state message.
  static const emptyState = Key('agent_settings_empty_state');

  /// Prefix for agent list tiles. Use with agent ID: 'agent_tile_$id'.
  static const agentTilePrefix = 'agent_tile_';

  /// Prefix for delete buttons. Use with agent ID: 'agent_delete_$id'.
  static const deleteButtonPrefix = 'agent_delete_';
}

/// Keys for testing AddAgentDialog widgets.
class AddAgentDialogKeys {
  AddAgentDialogKeys._();

  /// The dialog itself.
  static const dialog = Key('add_agent_dialog');

  /// The ID text field.
  static const idField = Key('add_agent_id_field');

  /// The name text field.
  static const nameField = Key('add_agent_name_field');

  /// The command text field.
  static const commandField = Key('add_agent_command_field');

  /// The args text field.
  static const argsField = Key('add_agent_args_field');

  /// The add environment variable button.
  static const addEnvButton = Key('add_agent_add_env_button');

  /// The cancel button.
  static const cancelButton = Key('add_agent_cancel_button');

  /// The add button.
  static const addAgentButton = Key('add_agent_add_button');

  /// Prefix for env key fields. Use with index: 'env_key_$index'.
  static const envKeyFieldPrefix = 'env_key_';

  /// Prefix for env value fields. Use with index: 'env_value_$index'.
  static const envValueFieldPrefix = 'env_value_';

  /// Prefix for env delete buttons. Use with index: 'env_delete_$index'.
  static const envDeleteButtonPrefix = 'env_delete_';
}

/// A settings panel for managing ACP agents.
///
/// This panel allows users to:
/// - View discovered and custom agents
/// - Add new custom agents with environment variables
/// - Remove custom agents
/// - Refresh agent discovery
///
/// The panel uses [Consumer] to watch the [AgentRegistry] for changes,
/// automatically rebuilding when agents are discovered, added, or removed.
///
/// Example usage:
/// ```dart
/// // In a settings screen
/// Scaffold(
///   body: AgentSettingsPanel(),
/// )
/// ```
///
/// The panel shows agents in two sections:
/// - **Discovered Agents**: System-installed agents found via PATH lookup.
///   These cannot be deleted, only refreshed.
/// - **Custom Agents**: User-defined agents with custom commands, arguments,
///   and environment variables. These can be added and removed.
class AgentSettingsPanel extends StatefulWidget {
  /// Creates an agent settings panel.
  const AgentSettingsPanel({super.key});

  @override
  State<AgentSettingsPanel> createState() => _AgentSettingsPanelState();
}

class _AgentSettingsPanelState extends State<AgentSettingsPanel> {
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentRegistry>(
      builder: (context, registry, _) {
        return Container(
          key: AgentSettingsPanelKeys.panel,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, registry),
              const Divider(height: 24),
              Expanded(
                child: _buildAgentList(context, registry),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the header with title and action buttons.
  Widget _buildHeader(BuildContext context, AgentRegistry registry) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          Icons.smart_toy_outlined,
          size: 24,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Text(
          'Agents',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        IconButton(
          key: AgentSettingsPanelKeys.refreshButton,
          icon: _isRefreshing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onPressed: _isRefreshing ? null : () => _handleRefresh(registry),
          tooltip: 'Refresh discovered agents',
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: AgentSettingsPanelKeys.addButton,
          onPressed: () => _showAddAgentDialog(context, registry),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Agent'),
        ),
      ],
    );
  }

  /// Builds the scrollable list of agents.
  Widget _buildAgentList(BuildContext context, AgentRegistry registry) {
    final discoveredAgents = registry.discoveredAgents;
    final customAgents = registry.customAgents;

    if (discoveredAgents.isEmpty && customAgents.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView(
      children: [
        // Discovered agents section
        if (discoveredAgents.isNotEmpty) ...[
          const _SectionHeader(
            key: AgentSettingsPanelKeys.discoveredSection,
            title: 'Discovered Agents',
            subtitle: 'Auto-detected from your system PATH',
          ),
          const SizedBox(height: 8),
          ...discoveredAgents.map(
            (agent) => _AgentListTile(
              key: Key('${AgentSettingsPanelKeys.agentTilePrefix}${agent.id}'),
              agent: agent,
              isCustom: false,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Custom agents section
        if (customAgents.isNotEmpty) ...[
          const _SectionHeader(
            key: AgentSettingsPanelKeys.customSection,
            title: 'Custom Agents',
            subtitle: 'Manually configured agents',
          ),
          const SizedBox(height: 8),
          ...customAgents.map(
            (agent) => _AgentListTile(
              key: Key('${AgentSettingsPanelKeys.agentTilePrefix}${agent.id}'),
              agent: agent,
              isCustom: true,
              onDelete: () => _handleDeleteAgent(context, registry, agent),
            ),
          ),
        ],
      ],
    );
  }

  /// Builds the empty state when no agents are configured.
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: AgentSettingsPanelKeys.emptyState,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No agents configured',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Refresh" to discover installed agents,\n'
            'or "Add Agent" to configure a custom one.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// Handles the refresh button press.
  Future<void> _handleRefresh(AgentRegistry registry) async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      await registry.discover();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// Shows the add agent dialog.
  void _showAddAgentDialog(BuildContext context, AgentRegistry registry) {
    showDialog<void>(
      context: context,
      builder: (context) => _AddAgentDialog(
        existingIds: registry.agents.map((a) => a.id).toSet(),
        onAdd: (config) {
          registry.addCustomAgent(config);
        },
      ),
    );
  }

  /// Handles deleting a custom agent with confirmation.
  void _handleDeleteAgent(
    BuildContext context,
    AgentRegistry registry,
    AgentConfig agent,
  ) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Agent'),
        content: Text('Are you sure you want to delete "${agent.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        registry.removeAgent(agent.id);
      }
    });
  }
}

/// Section header widget for agent list sections.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

/// List tile widget for displaying an agent.
class _AgentListTile extends StatelessWidget {
  const _AgentListTile({
    super.key,
    required this.agent,
    required this.isCustom,
    this.onDelete,
  });

  final AgentConfig agent;
  final bool isCustom;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Agent icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getAgentIcon(agent.id),
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            // Agent info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        agent.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Custom',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agent.command,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (agent.args.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Args: ${agent.args.join(" ")}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (agent.env.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Env: ${agent.env.keys.join(", ")}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Delete button (only for custom agents)
            if (isCustom && onDelete != null)
              IconButton(
                key: Key(
                  '${AgentSettingsPanelKeys.deleteButtonPrefix}${agent.id}',
                ),
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                onPressed: onDelete,
                tooltip: 'Delete agent',
              ),
          ],
        ),
      ),
    );
  }

  /// Returns an appropriate icon for the given agent ID.
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

/// Dialog for adding a new custom agent.
class _AddAgentDialog extends StatefulWidget {
  const _AddAgentDialog({
    required this.existingIds,
    required this.onAdd,
  });

  /// Set of existing agent IDs to prevent duplicates.
  final Set<String> existingIds;

  /// Callback when a new agent is added.
  final void Function(AgentConfig config) onAdd;

  @override
  State<_AddAgentDialog> createState() => _AddAgentDialogState();
}

class _AddAgentDialogState extends State<_AddAgentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();
  final _argsController = TextEditingController();

  /// List of environment variable entries as (key, value) pairs.
  final List<_EnvEntry> _envEntries = [];

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    for (final entry in _envEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      key: AddAgentDialogKeys.dialog,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add Custom Agent',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ID field
                      TextFormField(
                        key: AddAgentDialogKeys.idField,
                        controller: _idController,
                        decoration: const InputDecoration(
                          labelText: 'Agent ID',
                          hintText: 'e.g., my-agent',
                          helperText: 'Unique identifier (lowercase, hyphens)',
                        ),
                        validator: _validateId,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      const SizedBox(height: 16),

                      // Name field
                      TextFormField(
                        key: AddAgentDialogKeys.nameField,
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          hintText: 'e.g., My Custom Agent',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Name is required';
                          }
                          return null;
                        },
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      const SizedBox(height: 16),

                      // Command field
                      TextFormField(
                        key: AddAgentDialogKeys.commandField,
                        controller: _commandController,
                        decoration: const InputDecoration(
                          labelText: 'Command',
                          hintText: 'e.g., /usr/local/bin/my-agent',
                          helperText: 'Path to the agent executable',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Command is required';
                          }
                          return null;
                        },
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      const SizedBox(height: 16),

                      // Args field
                      TextFormField(
                        key: AddAgentDialogKeys.argsField,
                        controller: _argsController,
                        decoration: const InputDecoration(
                          labelText: 'Arguments (optional)',
                          hintText: 'e.g., --mode chat --verbose',
                          helperText: 'Space-separated command arguments',
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Environment variables section
                      _buildEnvSection(context),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: AddAgentDialogKeys.cancelButton,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: AddAgentDialogKeys.addAgentButton,
                    onPressed: _handleAdd,
                    child: const Text('Add Agent'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the environment variables section.
  Widget _buildEnvSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Environment Variables',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              key: AddAgentDialogKeys.addEnvButton,
              onPressed: _addEnvEntry,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Variable'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_envEntries.isEmpty)
          Text(
            'No environment variables configured',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          ...List.generate(_envEntries.length, (index) {
            return _buildEnvRow(context, index);
          }),
      ],
    );
  }

  /// Builds a single environment variable row.
  Widget _buildEnvRow(BuildContext context, int index) {
    final entry = _envEntries[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              key: Key('${AddAgentDialogKeys.envKeyFieldPrefix}$index'),
              controller: entry.keyController,
              decoration: const InputDecoration(
                labelText: 'Key',
                hintText: 'API_KEY',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              key: Key('${AddAgentDialogKeys.envValueFieldPrefix}$index'),
              controller: entry.valueController,
              decoration: const InputDecoration(
                labelText: 'Value',
                hintText: 'secret-value',
                isDense: true,
              ),
              obscureText: true,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: Key('${AddAgentDialogKeys.envDeleteButtonPrefix}$index'),
            icon: Icon(
              Icons.remove_circle_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _removeEnvEntry(index),
            tooltip: 'Remove variable',
          ),
        ],
      ),
    );
  }

  /// Validates the agent ID.
  String? _validateId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'ID is required';
    }

    final trimmed = value.trim();

    // Check format (lowercase letters, numbers, hyphens)
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(trimmed)) {
      return 'Use lowercase letters, numbers, and hyphens only';
    }

    // Check for duplicates
    if (widget.existingIds.contains(trimmed)) {
      return 'An agent with this ID already exists';
    }

    return null;
  }

  /// Adds a new environment variable entry.
  void _addEnvEntry() {
    setState(() {
      _envEntries.add(_EnvEntry());
    });
  }

  /// Removes an environment variable entry.
  void _removeEnvEntry(int index) {
    setState(() {
      final entry = _envEntries.removeAt(index);
      entry.dispose();
    });
  }

  /// Handles the add button press.
  void _handleAdd() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Parse arguments
    final argsText = _argsController.text.trim();
    final args = argsText.isEmpty ? <String>[] : argsText.split(RegExp(r'\s+'));

    // Build environment map
    final env = <String, String>{};
    for (final entry in _envEntries) {
      final key = entry.keyController.text.trim();
      final value = entry.valueController.text;
      if (key.isNotEmpty) {
        env[key] = value;
      }
    }

    final config = AgentConfig(
      id: _idController.text.trim(),
      name: _nameController.text.trim(),
      command: _commandController.text.trim(),
      args: args,
      env: env,
    );

    widget.onAdd(config);
    Navigator.of(context).pop();
  }
}

/// Helper class to manage environment variable entry controllers.
class _EnvEntry {
  final keyController = TextEditingController();
  final valueController = TextEditingController();

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
