part of 'settings_screen.dart';

// -----------------------------------------------------------------------------
// Agents settings content
// -----------------------------------------------------------------------------

class _AgentsSettingsContent extends StatefulWidget {
  const _AgentsSettingsContent({required this.settings});

  final SettingsService settings;

  @override
  State<_AgentsSettingsContent> createState() => _AgentsSettingsContentState();
}

class _AgentsSettingsContentState extends State<_AgentsSettingsContent> {
  String? _selectedAgentId;

  late TextEditingController _nameController;
  late TextEditingController _cliPathController;
  late TextEditingController _cliArgsController;
  late TextEditingController _environmentController;
  String _driver = 'claude';
  String _defaultModel = 'default';
  String _defaultPermissions = 'default';
  String _codexSandboxMode = 'workspace-write';
  String _codexApprovalPolicy = 'on-request';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _cliPathController = TextEditingController();
    _cliArgsController = TextEditingController();
    _environmentController = TextEditingController();

    // Auto-select the first agent.
    final agents = widget.settings.availableAgents;
    if (agents.isNotEmpty) {
      _selectedAgentId = agents.first.id;
      _loadSelectedAgent();
    }
  }

  @override
  void didUpdateWidget(_AgentsSettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if the selected agent still exists.
    if (_selectedAgentId != null) {
      final agent = widget.settings.agentById(_selectedAgentId!);
      if (agent != null) {
        _loadSelectedAgent();
      } else {
        // Selected agent was removed.
        setState(() {
          _selectedAgentId = null;
          _clearForm();
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cliPathController.dispose();
    _cliArgsController.dispose();
    _environmentController.dispose();
    super.dispose();
  }

  void _loadSelectedAgent() {
    if (_selectedAgentId == null) return;
    final agent = widget.settings.agentById(_selectedAgentId!);
    if (agent == null) return;

    _nameController.text = agent.name;
    _cliPathController.text = agent.cliPath;
    _cliArgsController.text = agent.cliArgs;
    _environmentController.text = agent.environment;
    _driver = agent.driver;
    final modelOpts = _modelOptionsForDriver(agent.driver);
    _defaultModel = agent.defaultModel.isEmpty && modelOpts.isNotEmpty
        ? modelOpts.first.$1
        : agent.defaultModel;
    _defaultPermissions = agent.defaultPermissions;
    _codexSandboxMode = agent.codexSandboxMode ?? 'workspace-write';
    _codexApprovalPolicy = agent.codexApprovalPolicy ?? 'on-request';
  }

  void _clearForm() {
    _nameController.clear();
    _cliPathController.clear();
    _cliArgsController.clear();
    _environmentController.clear();
    _driver = 'claude';
    _defaultModel = 'default';
    _defaultPermissions = 'default';
    _codexSandboxMode = 'workspace-write';
    _codexApprovalPolicy = 'on-request';
  }

  void _saveCurrentAgent() {
    if (_selectedAgentId == null) return;
    final agent = widget.settings.agentById(_selectedAgentId!);
    if (agent == null) return;

    final updated = agent.copyWith(
      name: _nameController.text.trim(),
      driver: _driver,
      cliPath: _cliPathController.text.trim(),
      cliArgs: _cliArgsController.text.trim(),
      defaultModel: _defaultModel,
      environment: _environmentController.text,
      defaultPermissions: _defaultPermissions,
      codexSandboxMode: _driver == 'codex' ? _codexSandboxMode : null,
      codexApprovalPolicy: _driver == 'codex' ? _codexApprovalPolicy : null,
    );

    unawaited(widget.settings.updateAgent(updated));

    // Re-check CLI availability when paths or drivers change.
    if (updated.cliPath != agent.cliPath || updated.driver != agent.driver) {
      final cliAvailability = context.read<CliAvailabilityService>();
      unawaited(cliAvailability.checkAgents(RuntimeConfig.instance.agents));
    }
  }

  void _addAgent() {
    final newAgent = AgentConfig(
      id: AgentConfig.generateId(),
      name: 'New Agent',
      driver: 'claude',
      cliPath: '',
      cliArgs: '',
      environment: '',
      defaultModel: 'default',
      defaultPermissions: 'default',
    );

    unawaited(widget.settings.addAgent(newAgent));
    setState(() {
      _selectedAgentId = newAgent.id;
      _loadSelectedAgent();
    });

    // Start backend to discover models for the new agent.
    final backendService = context.read<BackendService>();
    unawaited(backendService.startAgent(newAgent.id, config: newAgent));
  }

  void _removeAgent() {
    if (_selectedAgentId == null) return;

    final agents = widget.settings.availableAgents;
    if (agents.length <= 1) return;

    final agent = widget.settings.agentById(_selectedAgentId!);
    if (agent == null) return;

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Agent'),
        content: Text(
          'Are you sure you want to remove agent \'${agent.name}\'?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final agentId = _selectedAgentId!;
              unawaited(widget.settings.removeAgent(agentId));

              // Terminate chats that were using this agent.
              final project = context.read<ProjectState>();
              for (final worktree in project.allWorktrees) {
                for (final chat in worktree.chats) {
                  if (chat.agentId == agentId) {
                    unawaited(chat.terminateForAgentRemoval());
                  }
                }
              }

              // Dispose the backend instance for this agent.
              final backendService = context.read<BackendService>();
              unawaited(backendService.disposeAgent(agentId));

              setState(() {
                _selectedAgentId = null;
                _clearForm();
              });
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _setAsDefault() {
    if (_selectedAgentId == null) return;
    unawaited(widget.settings.setDefaultAgent(_selectedAgentId!));
  }

  Future<void> _pickCliPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CLI executable',
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        setState(() => _cliPathController.text = path);
        _saveCurrentAgent();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final agents = widget.settings.availableAgents;
    final defaultAgentId = widget.settings.defaultAgentId;
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category header
              Text(
                'Agents',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure AI agents and their backend drivers',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              // Agent list
              for (final agent in agents) ...[
                _AgentRow(
                  agent: agent,
                  isSelected: agent.id == _selectedAgentId,
                  isDefault: agent.id == defaultAgentId,
                  onTap: () {
                    setState(() {
                      _selectedAgentId = agent.id;
                      _loadSelectedAgent();
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              // Add Agent button
              SizedBox(
                height: 36,
                child: InsightsTonalButton(
                  onPressed: _addAgent,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Agent'),
                ),
              ),
              // Detail form (shown when an agent is selected)
              if (_selectedAgentId != null) ...[
                Divider(
                  height: 48,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                Text(
                  'Agent Configuration',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                // Name
                _FormField(
                  label: 'Name',
                  child: InsightsTextField(
                    controller: _nameController,
                    hintText: 'Agent name',
                    onSubmitted: (_) => _saveCurrentAgent(),
                    onTapOutside: (_) => _saveCurrentAgent(),
                  ),
                ),
                const SizedBox(height: 16),
                // Driver
                _FormField(
                  label: 'Driver',
                  child: _buildDropdown(
                    value: _driver,
                    options: const [
                      ('claude', 'Claude'),
                      ('codex', 'Codex'),
                      ('acp', 'ACP'),
                    ],
                    onChanged: (value) {
                      setState(() => _driver = value);
                      _saveCurrentAgent();
                      // Start backend for updated driver to trigger model discovery.
                      if (_selectedAgentId != null) {
                        final bs = context.read<BackendService>();
                        unawaited(bs.startAgent(_selectedAgentId!));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // CLI Path
                Builder(builder: (context) {
                  final cliService = context.watch<CliAvailabilityService>();
                  final isAvailable = _selectedAgentId != null &&
                      cliService.isAgentAvailable(_selectedAgentId!);
                  final resolvedPath = _selectedAgentId != null
                      ? cliService.resolvedPathForAgent(_selectedAgentId!)
                      : null;
                  final showAutoDetected =
                      _cliPathController.text.trim().isEmpty;

                  return _FormField(
                    label: 'CLI Path',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _cliPathController,
                                style: mono,
                                decoration: InputDecoration(
                                  hintText: 'Auto-detect',
                                  hintStyle: mono.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onSubmitted: (_) => _saveCurrentAgent(),
                                onTapOutside: (_) => _saveCurrentAgent(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.folder_open, size: 18),
                              tooltip: 'Browse',
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: _pickCliPath,
                            ),
                          ],
                        ),
                        if (showAutoDetected && isAvailable && resolvedPath != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              resolvedPath,
                              style: mono.copyWith(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        if (showAutoDetected && !isAvailable && cliService.checked)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _CliNotFoundMessage(driver: _driver),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                // CLI Arguments
                _FormField(
                  label: 'CLI Arguments',
                  child: TextField(
                    controller: _cliArgsController,
                    style: mono,
                    decoration: InputDecoration(
                      hintText: 'Optional',
                      hintStyle: mono.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _saveCurrentAgent(),
                    onTapOutside: (_) => _saveCurrentAgent(),
                  ),
                ),
                // Default Model (Claude and Codex only — ACP has no model concept)
                if (_driver == 'claude' || _driver == 'codex') ...[
                  const SizedBox(height: 16),
                  Builder(builder: (context) {
                    final bs = context.watch<BackendService>();
                    final isLoading = _selectedAgentId != null &&
                        (bs.isModelListLoadingForAgent(_selectedAgentId!) ||
                            bs.isStartingForAgent(_selectedAgentId!));
                    final modelOpts = _modelOptionsForDriver(_driver);

                    return _FormField(
                      label: 'Default Model',
                      child: isLoading && modelOpts.length <= 1
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Discovering models...',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _buildDropdownWithDescriptions(
                              value: modelOpts.any((o) => o.$1 == _defaultModel)
                                  ? _defaultModel
                                  : modelOpts.first.$1,
                              options: modelOpts,
                              onChanged: (value) {
                                setState(() => _defaultModel = value);
                                _saveCurrentAgent();
                              },
                            ),
                    );
                  }),
                ],
                // Default Permissions (Claude only)
                if (_driver == 'claude') ...[
                  const SizedBox(height: 16),
                  _FormField(
                    label: 'Default Permissions',
                    child: _buildDropdown(
                      value: _defaultPermissions,
                      options: const [
                        ('default', 'Default'),
                        ('acceptEdits', 'Accept Edits'),
                        ('plan', 'Plan'),
                        ('bypassPermissions', 'Bypass'),
                      ],
                      onChanged: (value) {
                        setState(() => _defaultPermissions = value);
                        _saveCurrentAgent();
                      },
                    ),
                  ),
                ],
                // Codex security settings
                if (_driver == 'codex') ...[
                  const SizedBox(height: 16),
                  _FormField(
                    label: 'Security',
                    child: SecurityConfigGroup(
                      config: CodexSecurityConfig(
                        sandboxMode:
                            CodexSandboxMode.fromNameOrWire(_codexSandboxMode),
                        approvalPolicy: CodexApprovalPolicy.fromNameOrWire(
                            _codexApprovalPolicy),
                      ),
                      capabilities: CodexSecurityCapabilities(),
                      onConfigChanged: (config) {
                        setState(() {
                          _codexSandboxMode = config.sandboxMode.wireValue;
                          _codexApprovalPolicy =
                              config.approvalPolicy.wireValue;
                        });
                        _saveCurrentAgent();
                      },
                    ),
                  ),
                ],
                // Environment
                _FormField(
                  label: 'Environment',
                  child: TextField(
                    controller: _environmentController,
                    style: mono,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'KEY=VALUE\nONE_PER_LINE',
                      hintStyle: mono.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onTapOutside: (_) => _saveCurrentAgent(),
                  ),
                ),
                const SizedBox(height: 24),
                // Action buttons
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (_selectedAgentId != defaultAgentId)
                      InsightsTonalButton(
                        onPressed: _setAsDefault,
                        icon: const Icon(Icons.star_outline, size: 16),
                        label: const Text('Set as Default'),
                      ),
                    if (agents.length > 1)
                      InsightsOutlinedButton(
                        onPressed: _removeAgent,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        child: const Text('Remove Agent'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Returns dropdown options for the model field based on driver type.
  ///
  /// Returns tuples of (id, label, description).
  List<(String, String, String)> _modelOptionsForDriver(String driver) {
    switch (driver) {
      case 'claude':
        return ChatModelCatalog.claudeModels
            .map((m) => (m.id, m.label, m.description))
            .toList();
      case 'codex':
        return ChatModelCatalog.codexModels
            .map((m) => (m.id, m.label, m.description))
            .toList();
      default:
        return const [];
    }
  }

  Widget _buildDropdown({
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    return _buildDropdownWithDescriptions(
      value: value,
      options: options.map((o) => (o.$1, o.$2, '')).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownWithDescriptions({
    required String value,
    required List<(String, String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDescriptions = options.any((o) => o.$3.isNotEmpty);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface,
          ),
          dropdownColor: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          // Show just label + description hint in the collapsed button.
          selectedItemBuilder: hasDescriptions
              ? (context) => options.map((opt) {
                    final desc = opt.$3;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        desc.isNotEmpty ? '${opt.$2}  ·  $desc' : opt.$2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    );
                  }).toList()
              : null,
          items: options
              .map(
                (opt) => DropdownMenuItem<String>(
                  value: opt.$1,
                  child: opt.$3.isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(opt.$2),
                            Text(
                              opt.$3,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        )
                      : Text(opt.$2),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.agent,
    required this.isSelected,
    required this.isDefault,
    required this.onTap,
  });

  final AgentConfig agent;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              // Agent name
              Expanded(
                child: Text(
                  agent.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Driver badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  agent.driver,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Default indicator
              if (isDefault) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.star,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a "CLI not found" message with a clickable install link.
class _CliNotFoundMessage extends StatelessWidget {
  const _CliNotFoundMessage({required this.driver});

  final String driver;

  static const _installUrls = {
    'claude': 'https://docs.anthropic.com/en/docs/claude-code/overview',
    'codex': 'https://github.com/openai/codex',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final driverLabel = driver.substring(0, 1).toUpperCase() + driver.substring(1);
    final installUrl = _installUrls[driver];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 14,
          color: colorScheme.error.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Text(
          '$driverLabel CLI not found. ',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.error.withValues(alpha: 0.8),
          ),
        ),
        if (installUrl != null)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse(installUrl)),
              child: Text(
                'Install $driverLabel CLI',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
