import 'package:agent_sdk_core/agent_sdk_core.dart' show BackendCapabilities;
import 'package:agent_sdk_core/agent_sdk_core.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart' show PermissionMode;
import '../models/chat_model.dart';
import '../models/ticket.dart';
import '../models/project.dart';
import '../services/backend_service.dart';
import '../services/ticket_dispatch_factory.dart';
import '../services/worktree_service.dart';
import '../services/git_service.dart';
import '../state/selection_state.dart';
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

  String _selectedModelId = 'default';
  PermissionMode _selectedPermissionMode = PermissionMode.defaultMode;

  @override
  void initState() {
    super.initState();
    final slug = widget.ticketIds.isEmpty
        ? 'orchestration'
        : 'orchestrate-${widget.ticketIds.first}-${widget.ticketIds.last}';
    _branchController = TextEditingController(text: slug);
    _instructionsController = TextEditingController(
      text:
          'Run tickets ${widget.ticketIds.join(', ')}. Respect dependencies, '
          'use parallel execution where safe, and report progress frequently.',
    );
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

    final backend = context.watch<BackendService>();
    final backendType = backend.backendType;
    final capabilities = backendType != null
        ? backend.capabilitiesFor(backendType)
        : const BackendCapabilities();
    final models = backendType != null
        ? ChatModelCatalog.forBackend(backendType)
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
                        subtitle: Text(t.status.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: OrchestrationConfigDialogKeys.branchField,
              controller: _branchController,
              decoration: const InputDecoration(
                labelText: 'Feature branch name',
                border: OutlineInputBorder(),
              ),
            ),
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
      final selection = context.read<SelectionState>();
      final gitService = context.read<GitService>();
      final worktreeService = WorktreeService(gitService: gitService);

      final root = await calculateDefaultWorktreeRoot(project.data.repoRoot);
      final base =
          selection.selectedWorktree?.data.branch ??
          project.primaryWorktree.data.branch;
      final created = await worktreeService.createWorktree(
        project: project,
        branch: _branchController.text.trim(),
        worktreeRoot: root,
        base: base,
      );
      project.addLinkedWorktree(created, select: true);

      final dispatch = createTicketDispatchService(context);

      // Resolve selected model to a ChatModel object.
      final backend = context.read<BackendService>();
      final backendType = backend.backendType;
      final selectedModel = backendType != null
          ? ChatModelCatalog.defaultForBackend(backendType, _selectedModelId)
          : null;

      await dispatch.createOrchestratorChat(
        worktreeState: created,
        ticketIds: widget.ticketIds,
        initialInstructions:
            '${_instructionsController.text.trim()}\n\nBase worktree: ${created.data.worktreeRoot}\nBase branch: ${created.data.branch}',
        model: selectedModel,
        permissionMode: sdk.PermissionMode.fromString(
            _selectedPermissionMode.apiName),
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
