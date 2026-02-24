import 'package:agent_sdk_core/agent_sdk_core.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../instructions/instructions.dart';
import '../models/agent_config.dart';
import '../models/chat.dart' show PermissionMode;
import '../models/chat_model.dart';
import '../models/ticket.dart';
import '../models/project.dart';
import '../services/backend_service.dart';
import '../services/cli_availability_service.dart';
import '../services/runtime_config.dart';
import '../services/ticket_dispatch_factory.dart';
import '../services/worktree_name_generator.dart';
import '../services/worktree_service.dart';
import '../services/git_service.dart';
import '../models/worktree.dart';
import '../state/ticket_board_state.dart';
import 'model_permission_selector.dart';

/// Test keys for [OrchestrationConfigDialog].
class OrchestrationConfigDialogKeys {
  OrchestrationConfigDialogKeys._();

  static const dialog = Key('orchestration_config_dialog');
  static const branchField = Key('orchestration_config_branch');
  static const instructionsField = Key('orchestration_config_instructions');
  static const cancelButton = Key('orchestration_config_cancel');
  static const launchButton = Key('orchestration_config_launch');
  static const modelPermissionSelector =
      Key('orchestration_config_model_permission');
  static const baseWorktreeDropdown =
      Key('orchestration_config_base_worktree');
  static const agentDropdown = Key('orchestration_config_agent');
  static const regenerateNameButton =
      Key('orchestration_config_regenerate_name');
}

class OrchestrationConfigDialog extends StatefulWidget {
  const OrchestrationConfigDialog({super.key, required this.ticketIds});

  final List<int> ticketIds;

  @override
  State<OrchestrationConfigDialog> createState() =>
      _OrchestrationConfigDialogState();
}

class _OrchestrationConfigDialogState extends State<OrchestrationConfigDialog> {
  late final TextEditingController _branchController;
  late final TextEditingController _instructionsController;
  bool _launching = false;

  WorktreeState? _selectedBaseWorktree;
  late String _selectedAgentId;
  String _selectedModelId = 'default';
  PermissionMode _selectedPermissionMode = PermissionMode.defaultMode;

  @override
  void initState() {
    super.initState();
    _selectedAgentId = RuntimeConfig.instance.defaultAgentId;
    final defaultAgent = RuntimeConfig.instance.defaultAgent;
    if (defaultAgent != null) {
      _selectedModelId = defaultAgent.defaultModel.isEmpty
          ? 'default'
          : defaultAgent.defaultModel;
      final perms = defaultAgent.defaultPermissions;
      if (perms.isNotEmpty) {
        _selectedPermissionMode = PermissionMode.fromApiName(perms);
      }
    }
    final project = context.read<ProjectState>();
    final existingBranches =
        project.allWorktrees.map((wt) => wt.data.branch).toSet();
    final slug = generateWorktreeName(existingBranches: existingBranches);
    _branchController = TextEditingController(text: 'orchestrate-$slug');
    _instructionsController = TextEditingController(
      text:
          'Run tickets ${widget.ticketIds.join(', ')}. '
          '$defaultOrchestrationInstructions',
    );
  }

  void _onAgentChanged(String agentId) {
    final agent = RuntimeConfig.instance.agentById(agentId);
    if (agent == null) return;
    setState(() {
      _selectedAgentId = agentId;
      _selectedModelId = agent.defaultModel.isEmpty
          ? 'default'
          : agent.defaultModel;
      final perms = agent.defaultPermissions;
      _selectedPermissionMode = perms.isNotEmpty
          ? PermissionMode.fromApiName(perms)
          : PermissionMode.defaultMode;
    });
  }

  void _regenerateName() {
    final project = context.read<ProjectState>();
    final existingBranches =
        project.allWorktrees.map((wt) => wt.data.branch).toSet();
    _branchController.text =
        'orchestrate-${generateWorktreeName(existingBranches: existingBranches)}';
  }

  @override
  void dispose() {
    _branchController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.watch<TicketRepository>();
    final tickets = widget.ticketIds
        .map(ticketBoard.getTicket)
        .whereType<TicketData>()
        .toList();

    final project = context.watch<ProjectState>();
    final worktrees = project.allWorktrees;
    final effectiveBaseWorktree = worktrees.contains(_selectedBaseWorktree)
        ? _selectedBaseWorktree!
        : project.primaryWorktree;

    final backend = context.watch<BackendService>();
    final cliAvailability = context.watch<CliAvailabilityService>();
    final allAgents = RuntimeConfig.instance.agents;
    final availableAgents = allAgents
        .where((agent) => cliAvailability.isAgentAvailable(agent.id))
        .toList();
    final selectedAgent = RuntimeConfig.instance.agentById(_selectedAgentId);
    final effectiveBackendType = selectedAgent?.backendType ??
        backend.backendType;
    // Always enable model/permission selection in this pre-launch dialog.
    const capabilities = sdk.BackendCapabilities(
      supportsModelChange: true,
      supportsPermissionModeChange: true,
    );
    final models = effectiveBackendType != null
        ? ChatModelCatalog.forBackend(effectiveBackendType)
        : ChatModelCatalog.claudeModels;

    return AlertDialog(
      key: OrchestrationConfigDialogKeys.dialog,
      title: const Text('Run orchestration'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(
              'Tickets (${tickets.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                shrinkWrap: true,
                children: tickets
                    .map(
                      (t) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${t.displayId}  ${t.title}'),
                        subtitle: Text(t.isOpen ? 'Open' : 'Closed'),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WorktreeState>(
              key: OrchestrationConfigDialogKeys.baseWorktreeDropdown,
              value: effectiveBaseWorktree,
              decoration: const InputDecoration(
                labelText: 'Base worktree',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: worktrees.map((wt) {
                final label = wt.data.isPrimary
                    ? '${wt.data.branch} (primary)'
                    : wt.data.branch;
                return DropdownMenuItem<WorktreeState>(
                  value: wt,
                  child: Text(label, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedBaseWorktree = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: OrchestrationConfigDialogKeys.branchField,
              controller: _branchController,
              decoration: InputDecoration(
                labelText: 'Feature branch name',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: OrchestrationConfigDialogKeys.regenerateNameButton,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Generate new name',
                  onPressed: _regenerateName,
                ),
              ),
            ),
            if (availableAgents.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: OrchestrationConfigDialogKeys.agentDropdown,
                value: availableAgents.any((a) => a.id == _selectedAgentId)
                    ? _selectedAgentId
                    : availableAgents.first.id,
                decoration: const InputDecoration(
                  labelText: 'Agent',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: availableAgents.map((agent) {
                  return DropdownMenuItem<String>(
                    value: agent.id,
                    child: Text(agent.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) _onAgentChanged(value);
                },
              ),
            ],
            const SizedBox(height: 12),
            ModelPermissionSelector(
              key: OrchestrationConfigDialogKeys.modelPermissionSelector,
              models: models,
              selectedModelId: _selectedModelId,
              onModelChanged: (id) => setState(() => _selectedModelId = id),
              permissionModes: PermissionMode.values.toList(),
              selectedPermissionMode: _selectedPermissionMode,
              onPermissionModeChanged: (mode) =>
                  setState(() => _selectedPermissionMode = mode),
              capabilities: capabilities,
            ),
            const SizedBox(height: 12),
            TextField(
              key: OrchestrationConfigDialogKeys.instructionsField,
              controller: _instructionsController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Initial instructions',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: OrchestrationConfigDialogKeys.cancelButton,
          onPressed: _launching ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: OrchestrationConfigDialogKeys.launchButton,
          onPressed: _launching ? null : _launch,
          child: _launching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Launch'),
        ),
      ],
    );
  }

  Future<void> _launch() async {
    setState(() => _launching = true);
    try {
      final project = context.read<ProjectState>();
      final gitService = context.read<GitService>();
      final worktreeService = WorktreeService(gitService: gitService);

      final root = await calculateDefaultWorktreeRoot(project.data.repoRoot);
      final base = _selectedBaseWorktree?.data.branch ??
          project.primaryWorktree.data.branch;
      final created = await worktreeService.createWorktree(
        project: project,
        branch: _branchController.text.trim(),
        worktreeRoot: root,
        base: base,
      );
      project.addLinkedWorktree(created, select: true);

      final dispatch = createTicketDispatchService(context);

      // Resolve selected model using the selected agent's backend type.
      final agent = RuntimeConfig.instance.agentById(_selectedAgentId);
      final resolvedBackendType = agent?.backendType ??
          context.read<BackendService>().backendType;
      final selectedModel = resolvedBackendType != null
          ? ChatModelCatalog.defaultForBackend(
              resolvedBackendType, _selectedModelId)
          : null;

      final instructions = buildOrchestrationLaunchMessage(
        ticketIds: widget.ticketIds,
        worktreePath: created.data.worktreeRoot,
        branch: created.data.branch,
        instructions: _instructionsController.text.trim(),
      );

      await dispatch.createOrchestratorChat(
        worktreeState: created,
        ticketIds: widget.ticketIds,
        initialInstructions: instructions,
        model: selectedModel,
        permissionMode: sdk.PermissionMode.fromString(
            _selectedPermissionMode.apiName),
        agentId: _selectedAgentId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch orchestration: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _launching = false);
      }
    }
  }
}
