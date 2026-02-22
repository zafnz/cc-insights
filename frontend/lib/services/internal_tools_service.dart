import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/chat.dart';
import '../models/managed_agent.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/ticket.dart';
import '../models/worktree.dart';
import '../models/worktree_tag.dart';
import '../state/bulk_proposal_state.dart';
import '../state/orchestrator_state.dart';
import '../state/selection_state.dart';
import '../state/ticket_board_state.dart';
import 'backend_service.dart';
import 'event_handler.dart';
import 'git_service.dart';
import 'orchestration_prompts.dart';
import 'persistence_service.dart';
import 'project_restore_service.dart';
import 'settings_service.dart';
import 'worktree_service.dart';

class _OrchestrationContext {
  const _OrchestrationContext({
    required this.backend,
    required this.eventHandler,
    required this.project,
    required this.selection,
    required this.ticketBoard,
    required this.worktreeService,
    required this.restoreService,
  });

  final BackendService backend;
  final EventHandler eventHandler;
  final ProjectState project;
  final SelectionState selection;
  final TicketRepository ticketBoard;
  final WorktreeService worktreeService;
  final ProjectRestoreService restoreService;
}

/// Service that manages internal MCP tools for CC-Insights.
///
/// Owns the [InternalToolRegistry] and registers application-level tools
/// that agent backends can invoke via the MCP protocol.
class InternalToolsService extends ChangeNotifier {
  final InternalToolRegistry _registry = InternalToolRegistry();
  final Map<String, OrchestratorState> _orchestratorsByChatId = {};

  /// The tool registry to pass to backend sessions.
  InternalToolRegistry get registry => _registry;

  /// Returns system prompt text to append when git tools are registered,
  /// or null if no git tools are active.
  String? get systemPromptAppend {
    if (_gitService == null) return null;
    return 'You have access to internal git MCP tools '
        '(git_commit_context, git_commit, git_log, git_diff). '
        'Prefer these over running git commands via the shell — '
        'they are faster and safer. '
        'Fall back to shell git only for operations these tools '
        'do not cover.';
  }

  /// Returns per-chat internal tool system prompt append text.
  String? systemPromptAppendForChat(Chat chat) {
    if (chat.settings.isOrchestratorChat) {
      return _mergePromptText([systemPromptAppend, orchestratorSystemPrompt]);
    }
    return systemPromptAppend;
  }

  /// Builds a tool registry for a specific chat.
  ///
  /// Normal chats only get normal tools. Orchestrator chats and chats with
  /// orchestration tools enabled get the full orchestration toolset.
  InternalToolRegistry registryForChat(Chat chat) {
    final chatRegistry = InternalToolRegistry();
    final baseTools = _normalTools();
    for (final tool in baseTools) {
      chatRegistry.register(tool);
    }
    if (shouldEnableOrchestrationTools(chat)) {
      for (final tool in _orchestratorTools(chat)) {
        chatRegistry.register(tool);
      }
    }
    return chatRegistry;
  }

  _OrchestrationContext? _orchestrationContext;

  BackendService? get _backend => _orchestrationContext?.backend;
  EventHandler? get _eventHandler => _orchestrationContext?.eventHandler;
  ProjectState? get _project => _orchestrationContext?.project;
  SelectionState? get _selection => _orchestrationContext?.selection;
  TicketRepository? get _ticketBoard => _orchestrationContext?.ticketBoard;
  WorktreeService? get _worktreeService =>
      _orchestrationContext?.worktreeService;
  ProjectRestoreService? get _restoreService =>
      _orchestrationContext?.restoreService;

  SettingsService? _settingsService;
  PersistenceService? _persistenceService;

  /// Binds orchestration dependencies from app providers.
  void bindOrchestrationContext({
    required BackendService backend,
    required EventHandler eventHandler,
    required ProjectState project,
    required SelectionState selection,
    required TicketRepository ticketBoard,
    required WorktreeService worktreeService,
    required ProjectRestoreService restoreService,
    required GitService gitService,
    required SettingsService settingsService,
    required PersistenceService persistenceService,
  }) {
    _orchestrationContext = _OrchestrationContext(
      backend: backend,
      eventHandler: eventHandler,
      project: project,
      selection: selection,
      ticketBoard: ticketBoard,
      worktreeService: worktreeService,
      restoreService: restoreService,
    );
    _gitService ??= gitService;
    _settingsService ??= settingsService;
    _persistenceService ??= persistenceService;
  }

  bool shouldEnableOrchestrationTools(Chat chat) {
    return isOrchestratorChat(chat) || chat.settings.orchestrationToolsEnabled;
  }

  bool isOrchestratorChat(Chat chat) {
    return chat.settings.isOrchestratorChat ||
        _orchestratorsByChatId.containsKey(chat.id);
  }

  OrchestratorState? getOrchestratorState(Chat chat) {
    final state = _orchestratorsByChatId[chat.id];
    if (state != null) return state;
    final snapshot = chat.settings.orchestrationData;
    if (!chat.settings.isOrchestratorChat || snapshot == null) {
      return null;
    }
    return _restoreOrchestratorStateFromSnapshot(chat, snapshot);
  }

  Iterable<OrchestratorState> get activeOrchestrators =>
      _orchestratorsByChatId.values;

  /// Maximum number of ticket proposals allowed in a single create_ticket call.
  static const int maxProposalCount = 50;
  static const int _defaultWaitTimeoutSeconds = 600;
  static const int _defaultAskTimeoutSeconds = 60;
  static const int _maxWaitTimeoutSeconds = 3600;

  static const Set<String> _orchestratorToolNames = {
    'launch_agent',
    'tell_agent',
    'ask_agent',
    'wait_for_agents',
    'check_agents',
    'list_tickets',
    'get_ticket',
    'update_ticket',
    'create_worktree',
    'rebase_and_merge',
    // 'delete_worktree', // Disabled: finished worktrees should be left as-is
    'set_tags',
    'list_tags',
  };

  /// Register the create_ticket tool with the given bulk proposal state.
  ///
  /// The tool handler parses ticket proposals from the input,
  /// stages them for user review, and waits for
  /// the review to complete via [BulkProposalState.onBulkReviewComplete] stream.
  void registerTicketTools(BulkProposalState proposalState) {
    _registry.register(
      InternalToolDefinition(
        name: 'create_ticket',
        description:
            'Create one or more tickets on the project board. '
            'Each ticket has a title, description, kind '
            '(feature/bugfix/research/question/test/docs/chore), '
            'optional priority, effort, category, tags, '
            'and dependency indices.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'tickets': {
              'type': 'array',
              'description': 'Array of ticket proposals to create',
              'items': {
                'type': 'object',
                'properties': {
                  'title': {
                    'type': 'string',
                    'description': 'Short title describing the ticket',
                  },
                  'description': {
                    'type': 'string',
                    'description': 'Detailed description of the work',
                  },
                  'kind': {
                    'type': 'string',
                    'enum': [
                      'feature',
                      'bugfix',
                      'research',
                      'question',
                      'test',
                      'docs',
                      'chore',
                    ],
                    'description': 'Type of work',
                  },
                  'priority': {
                    'type': 'string',
                    'enum': ['critical', 'high', 'medium', 'low'],
                    'description': 'Priority level (defaults to medium)',
                  },
                  'effort': {
                    'type': 'string',
                    'enum': ['small', 'medium', 'large'],
                    'description': 'Estimated effort (defaults to medium)',
                  },
                  'category': {
                    'type': 'string',
                    'description': 'Optional category for grouping',
                  },
                  'tags': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Tags for categorization',
                  },
                  'dependsOnIndices': {
                    'type': 'array',
                    'items': {'type': 'integer'},
                    'description':
                        'Indices of tickets in this array that '
                        'this ticket depends on',
                  },
                },
                'required': ['title', 'description', 'kind'],
              },
            },
          },
          'required': ['tickets'],
        },
        handler: (input) => _handleCreateTicket(proposalState, input),
      ),
    );
  }

  /// Unregister ticket tools (e.g., when board changes).
  void unregisterTicketTools() {
    _registry.unregister('create_ticket');
  }

  Future<InternalToolResult> _handleCreateTicket(
    BulkProposalState proposalState,
    Map<String, dynamic> input,
  ) async {
    // Parse tickets array
    final ticketsInput = input['tickets'];
    if (ticketsInput == null || ticketsInput is! List) {
      return InternalToolResult.error(
        'Missing or invalid "tickets" field. '
        'Expected an array of ticket objects.',
      );
    }

    if (ticketsInput.isEmpty) {
      return InternalToolResult.error('Empty tickets array.');
    }

    if (ticketsInput.length > maxProposalCount) {
      return InternalToolResult.error(
        'Too many proposals '
        '(${ticketsInput.length} > $maxProposalCount).',
      );
    }

    // Parse proposals
    final proposals = <TicketProposal>[];
    for (var i = 0; i < ticketsInput.length; i++) {
      final json = ticketsInput[i];
      if (json is! Map<String, dynamic>) {
        return InternalToolResult.error(
          'Ticket at index $i is not a valid object.',
        );
      }

      final title = json['title'] as String?;
      final description = json['description'] as String?;
      final kind = json['kind'] as String?;

      if (title == null || title.isEmpty) {
        return InternalToolResult.error(
          'Ticket at index $i missing required "title" field.',
        );
      }
      if (description == null) {
        return InternalToolResult.error(
          'Ticket at index $i missing required "description" field.',
        );
      }
      if (kind == null || kind.isEmpty) {
        return InternalToolResult.error(
          'Ticket at index $i missing required "kind" field.',
        );
      }

      try {
        proposals.add(TicketProposal.fromJson(json));
      } catch (e) {
        return InternalToolResult.error(
          'Failed to parse ticket at index $i: $e',
        );
      }
    }

    // Listen for the next bulk review completion event
    final resultFuture = proposalState.onBulkReviewComplete.first.then((
      result,
    ) {
      final total = result.approvedCount + result.rejectedCount;
      final String resultText;
      if (result.approvedCount == 0) {
        resultText = 'All $total ticket proposals were rejected by the user.';
      } else if (result.rejectedCount == 0) {
        resultText =
            'All ${result.approvedCount} ticket proposals were approved '
            'and created.';
      } else {
        resultText =
            '${result.approvedCount} of $total ticket proposals were approved '
            'and created. ${result.rejectedCount} were rejected.';
      }
      return InternalToolResult.text(resultText);
    });

    // Stage proposals
    proposalState.proposeBulk(
      proposals,
      sourceChatId: 'mcp-tool',
      sourceChatName: 'Agent',
    );

    developer.log(
      'create_ticket: staged ${proposals.length} proposals for bulk review',
      name: 'InternalToolsService',
    );

    return resultFuture;
  }

  // ===========================================================================
  // Orchestration tools
  // ===========================================================================

  List<InternalToolDefinition> _normalTools() {
    return _registry.tools
        .where((tool) => !_orchestratorToolNames.contains(tool.name))
        .toList();
  }

  List<InternalToolDefinition> _orchestratorTools(Chat orchestratorChat) {
    return [
      _launchAgentTool(orchestratorChat),
      _tellAgentTool(orchestratorChat),
      _askAgentTool(orchestratorChat),
      _waitForAgentsTool(orchestratorChat),
      _checkAgentsTool(orchestratorChat),
      _listTicketsTool(),
      _getTicketTool(),
      _updateTicketTool(),
      _createWorktreeTool(orchestratorChat),
      _rebaseAndMergeTool(orchestratorChat),
      // _deleteWorktreeTool(), // Disabled: finished worktrees should be left as-is
      _setTagsTool(),
      _listTagsTool(),
    ];
  }

  void attachOrchestratorState(Chat chat, OrchestratorState state) {
    _orchestratorsByChatId[chat.id] = state;
    state.setOrchestratorChat(chat);
    chat.settings.setIsOrchestratorChat(true);
    chat.settings.setOrchestrationToolsEnabled(true);
    chat.settings.setOrchestrationData(state.toSnapshot());
    state.addListener(() {
      if (_orchestratorsByChatId[chat.id] != state) return;
      chat.settings.setOrchestrationData(state.toSnapshot());
    });
    notifyListeners();
  }

  OrchestratorState? _restoreOrchestratorStateFromSnapshot(
    Chat chat,
    Map<String, dynamic> snapshot,
  ) {
    final ticketBoard = _ticketBoard;
    if (ticketBoard == null) return null;
    final ticketIds = (snapshot['ticketIds'] as List<dynamic>? ?? [])
        .map((e) => e as int)
        .toList();
    final basePath = snapshot['baseWorktreePath'] as String?;
    if (basePath == null || ticketIds.isEmpty) return null;
    final startTime = snapshot['startTime'] as String?;
    final state = OrchestratorState(
      ticketBoard: ticketBoard,
      ticketIds: ticketIds,
      baseWorktreePath: basePath,
      startTime: startTime != null ? DateTime.tryParse(startTime) : null,
    );
    // Attach without notifying synchronously — this is called during build
    // via getOrchestratorState(). Defer the notification to avoid
    // "setState() called during build" errors.
    _orchestratorsByChatId[chat.id] = state;
    chat.settings.setIsOrchestratorChat(true);
    chat.settings.setOrchestrationToolsEnabled(true);
    chat.settings.setOrchestrationData(state.toSnapshot());
    state.addListener(() {
      if (_orchestratorsByChatId[chat.id] != state) return;
      chat.settings.setOrchestrationData(state.toSnapshot());
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });

    final agents = snapshot['agents'] as List<dynamic>? ?? [];
    for (final raw in agents) {
      if (raw is! Map<String, dynamic>) continue;
      final agentId = raw['id'] as String?;
      final chatId = raw['chatId'] as String?;
      if (agentId == null || chatId == null) continue;
      final worker = _findChatById(chatId);
      if (worker == null) continue;
      state.registerAgent(
        agentId: agentId,
        chat: worker,
        ticketId: raw['ticketId'] as int?,
      );
    }
    return state;
  }

  InternalToolDefinition _launchAgentTool(Chat orchestratorChat) {
    return InternalToolDefinition(
      name: 'launch_agent',
      description: 'Launches a worker agent in a worktree with instructions.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'worktree': {'type': 'string'},
          'instructions': {'type': 'string'},
          'ticket_id': {'type': 'integer'},
          'name': {'type': 'string'},
        },
        'required': ['worktree', 'instructions'],
      },
      handler: (input) => _handleLaunchAgent(orchestratorChat, input),
    );
  }

  Future<InternalToolResult> _handleLaunchAgent(
    Chat orchestratorChat,
    Map<String, dynamic> input,
  ) async {
    final context = _orchestrationContext;
    if (context == null) {
      return InternalToolResult.error(
        'Orchestration context is not initialized.',
      );
    }

    final worktreePath = input['worktree'] as String?;
    final instructions = input['instructions'] as String?;
    final ticketId = (input['ticket_id'] as num?)?.toInt();
    final name = input['name'] as String?;
    if (worktreePath == null || worktreePath.isEmpty) {
      return InternalToolResult.error('Missing required "worktree"');
    }
    if (instructions == null || instructions.trim().isEmpty) {
      return InternalToolResult.error('Missing required "instructions"');
    }

    final worktree = _findWorktreeByPath(worktreePath);
    if (worktree == null) {
      return InternalToolResult.error('Worktree not found: $worktreePath');
    }

    try {
      final chat = await _createWorkerChat(
        context: context,
        worktree: worktree,
        worktreePath: worktreePath,
        ticketId: ticketId,
        name: name,
      );
      await _startWorkerSession(
        context: context,
        chat: chat,
        instructions: instructions,
      );

      final state = getOrchestratorState(orchestratorChat);
      if (state == null) {
        return InternalToolResult.error('Orchestrator state is not available.');
      }

      final agentId = 'agent-${chat.id}';
      state.registerAgent(agentId: agentId, chat: chat, ticketId: ticketId);
      _linkWorkerTicket(
        context: context,
        ticketId: ticketId,
        worktree: worktree,
        chat: chat,
      );

      return InternalToolResult.text(
        jsonEncode({
          'agent_id': agentId,
          'chat_id': chat.id,
          'worktree': worktreePath,
        }),
      );
    } catch (e) {
      return InternalToolResult.error('Failed to launch agent session: $e');
    }
  }

  Future<Chat> _createWorkerChat({
    required _OrchestrationContext context,
    required WorktreeState worktree,
    required String worktreePath,
    required int? ticketId,
    required String? name,
  }) async {
    final chat = Chat.create(
      name:
          name ?? (ticketId != null ? 'TKT-$ticketId Worker' : 'Worker Agent'),
      worktreeRoot: worktreePath,
    );
    await context.restoreService.addChatToWorktree(
      context.project.data.repoRoot,
      worktreePath,
      chat,
    );
    worktree.addChat(chat, select: false);
    return chat;
  }

  Future<void> _startWorkerSession({
    required _OrchestrationContext context,
    required Chat chat,
    required String instructions,
  }) {
    return chat.session.start(
      backend: context.backend,
      eventHandler: context.eventHandler,
      prompt: instructions,
      internalToolsService: this,
    );
  }

  void _linkWorkerTicket({
    required _OrchestrationContext context,
    required int? ticketId,
    required WorktreeState worktree,
    required Chat chat,
  }) {
    if (ticketId == null) return;
    context.ticketBoard.setStatus(ticketId, TicketStatus.active);
    context.ticketBoard.linkWorktree(
      ticketId,
      worktree.data.worktreeRoot,
      worktree.data.branch,
    );
    context.ticketBoard.linkChat(
      ticketId,
      chat.id,
      chat.name,
      worktree.data.worktreeRoot,
    );
  }

  InternalToolDefinition _tellAgentTool(Chat orchestratorChat) {
    return InternalToolDefinition(
      name: 'tell_agent',
      description: 'Send a non-blocking message to an idle agent.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'agent_id': {'type': 'string'},
          'message': {'type': 'string'},
        },
        'required': ['agent_id', 'message'],
      },
      handler: (input) => _handleTellAgent(orchestratorChat, input),
    );
  }

  Future<InternalToolResult> _handleTellAgent(
    Chat orchestratorChat,
    Map<String, dynamic> input,
  ) async {
    final agentId = input['agent_id'] as String?;
    final message = input['message'] as String?;
    if (agentId == null || message == null) {
      return InternalToolResult.error(
        'Missing required fields: agent_id, message',
      );
    }
    final agent = getOrchestratorState(orchestratorChat)?.getAgent(agentId);
    if (agent == null)
      return InternalToolResult.error('agent_not_found: $agentId');
    if (!agent.chat.session.hasActiveSession) {
      return InternalToolResult.error('agent_stopped: $agentId');
    }
    if (agent.chat.session.isWorking) {
      return InternalToolResult.error('agent_busy: $agentId');
    }

    await agent.chat.session.sendMessage(message);
    return InternalToolResult.text(jsonEncode({'success': true}));
  }

  InternalToolDefinition _askAgentTool(Chat orchestratorChat) {
    return InternalToolDefinition(
      name: 'ask_agent',
      description:
          'Send a message and wait for the agent turn to complete. '
          'Default timeout is ${_defaultAskTimeoutSeconds}s.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'agent_id': {'type': 'string'},
          'message': {'type': 'string'},
          'timeout_seconds': {
            'type': 'integer',
            'description':
                'Optional wait timeout in seconds (default: '
                '$_defaultAskTimeoutSeconds)',
          },
        },
        'required': ['agent_id', 'message'],
      },
      handler: (input) => _handleAskAgent(orchestratorChat, input),
    );
  }

  Future<InternalToolResult> _handleAskAgent(
    Chat orchestratorChat,
    Map<String, dynamic> input,
  ) async {
    final agentId = input['agent_id'] as String?;
    final message = input['message'] as String?;
    if (agentId == null || message == null) {
      return InternalToolResult.error(
        'Missing required fields: agent_id, message',
      );
    }
    final agent = getOrchestratorState(orchestratorChat)?.getAgent(agentId);
    if (agent == null)
      return InternalToolResult.error('agent_not_found: $agentId');
    if (!agent.chat.session.hasActiveSession) {
      return InternalToolResult.error('agent_stopped: $agentId');
    }
    if (agent.chat.session.isWorking) {
      return InternalToolResult.error('agent_busy: $agentId');
    }

    final timeout = _parseAskTimeout(input);
    await agent.chat.session.sendMessage(message);
    final completed = await _waitUntilAgentIdle(
      agent.chat,
      timeout: timeout,
      treatPermissionAsReady: false,
    );
    final response = _extractLastAssistantMessage(agent.chat);
    final result = <String, dynamic>{
      'response': response,
      'completion_status': AgentCompletionStatus.unknown.wireValue,
      'wait_timed_out': !completed,
    };
    if (!completed) {
      final status = _reasonForAgent(agent.chat);
      result['status'] = status.wireValue;
      final seconds = timeout.inSeconds;
      final unit = seconds == 1 ? 'second' : 'seconds';
      if (status == AgentReadyReason.permissionNeeded) {
        result['error'] =
            'ask_agent timed out after $seconds $unit -- '
            'the agent is waiting on the user. You should use '
            'wait_for_agents to wait for the user to respond to that agent.';
      } else if (agent.chat.session.isWorking) {
        result['error'] =
            'ask_agent timed out after $seconds $unit -- '
            'you can use wait_for_agents to wait until the agent is idle.';
      }
    }
    return InternalToolResult.text(jsonEncode(result));
  }

  InternalToolDefinition _waitForAgentsTool(Chat orchestratorChat) {
    return InternalToolDefinition(
      name: 'wait_for_agents',
      description:
          'Waits until one or more agents become ready. '
          'Pass last_known_status to skip agents whose status has not changed '
          'since the previous call.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'agent_ids': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'timeout_seconds': {
            'type': 'integer',
            'description':
                'Optional wait timeout in seconds (default: '
                '$_defaultWaitTimeoutSeconds). If timed out, check status and '
                'call wait_for_agents again.',
          },
          'last_known_status': {
            'type': 'object',
            'description':
                'Optional map of agent_id → last known status string. '
                'Agents whose current status matches the provided value '
                'are not considered ready.',
            'additionalProperties': {'type': 'string'},
          },
        },
        'required': ['agent_ids'],
      },
      handler: (input) => _handleWaitForAgents(orchestratorChat, input),
    );
  }

  Future<InternalToolResult> _handleWaitForAgents(
    Chat orchestratorChat,
    Map<String, dynamic> input,
  ) async {
    final idsRaw = input['agent_ids'];
    if (idsRaw is! List || idsRaw.isEmpty) {
      return InternalToolResult.error(
        'Missing required non-empty "agent_ids" array',
      );
    }
    final ids = idsRaw.map((e) => e.toString()).toList();
    final timeout = _parseWaitTimeout(input);
    final state = getOrchestratorState(orchestratorChat);
    if (state == null) {
      return InternalToolResult.error('Orchestrator state not found');
    }

    // Parse optional last_known_status map.
    final lastKnownRaw = input['last_known_status'];
    final Map<String, String>? lastKnownStatus;
    if (lastKnownRaw is Map) {
      lastKnownStatus = lastKnownRaw.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } else {
      lastKnownStatus = null;
    }

    final agents = <ManagedAgent>[];
    for (final id in ids) {
      final agent = state.getAgent(id);
      if (agent == null) {
        return InternalToolResult.error('agent_not_found: $id');
      }
      agents.add(agent);
    }

    List<Map<String, String>> collectReady() {
      return agents
          .where((a) {
            if (!_isAgentReady(a.chat)) return false;
            if (lastKnownStatus != null &&
                lastKnownStatus.containsKey(a.id)) {
              // Skip if current status matches last known status.
              final current = _reasonForAgent(a.chat).wireValue;
              if (current == lastKnownStatus[a.id]) return false;
            }
            return true;
          })
          .map(
            (a) => {
              'agent_id': a.id,
              'reason': _reasonForAgent(a.chat).wireValue,
            },
          )
          .toList();
    }

    var ready = collectReady();
    if (ready.isNotEmpty) {
      return InternalToolResult.text(
        jsonEncode({'ready': ready, 'wait_timed_out': false}),
      );
    }

    final completer = Completer<void>();
    final listeners = <VoidCallback>[];

    void onAnyChange() {
      if (!completer.isCompleted && collectReady().isNotEmpty) {
        completer.complete();
      }
    }

    for (final agent in agents) {
      agent.chat.session.addListener(onAnyChange);
      listeners.add(() => agent.chat.session.removeListener(onAnyChange));
      agent.chat.permissions.addListener(onAnyChange);
      listeners.add(() => agent.chat.permissions.removeListener(onAnyChange));
    }

    var timedOut = false;
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
    } finally {
      for (final dispose in listeners) {
        dispose();
      }
    }

    ready = collectReady();
    if (ready.isNotEmpty) {
      return InternalToolResult.text(
        jsonEncode({'ready': ready, 'wait_timed_out': false}),
      );
    }

    return InternalToolResult.text(
      jsonEncode({
        'ready': ready,
        'wait_timed_out': timedOut,
        if (timedOut) 'timeout_seconds': timeout.inSeconds,
        if (timedOut)
          'status': agents
              .map(
                (a) => {
                  'agent_id': a.id,
                  'reason': _reasonForAgent(a.chat).wireValue,
                  'is_working': a.chat.session.isWorking,
                },
              )
              .toList(),
      }),
    );
  }

  InternalToolDefinition _checkAgentsTool(Chat orchestratorChat) {
    return InternalToolDefinition(
      name: 'check_agents',
      description:
          'Returns a non-blocking status snapshot for one or more agents.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'agent_ids': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['agent_ids'],
      },
      handler: (input) => _handleCheckAgents(orchestratorChat, input),
    );
  }

  Future<InternalToolResult> _handleCheckAgents(
    Chat orchestratorChat,
    Map<String, dynamic> input,
  ) async {
    final rawIds = input['agent_ids'];
    if (rawIds is! List || rawIds.isEmpty) {
      return InternalToolResult.error('Missing or empty "agent_ids"');
    }
    final List<String> agentIds;
    try {
      agentIds = List<String>.from(rawIds);
    } on TypeError {
      return InternalToolResult.error(
        'Invalid "agent_ids": all elements must be strings',
      );
    }
    final state = getOrchestratorState(orchestratorChat);
    final agents = <Map<String, dynamic>>[];
    final errors = <Map<String, dynamic>>[];
    for (final agentId in agentIds) {
      final agent = state?.getAgent(agentId);
      if (agent == null) {
        errors.add({'agent_id': agentId, 'error': 'agent_not_found'});
        continue;
      }
      final lastMessage = _extractLastAssistantMessage(agent.chat);
      final entryCount = agent.chat.data.primaryConversation.entries.length;
      final status = _reasonForAgent(agent.chat);
      agents.add({
        'agent_id': agentId,
        'status': status.wireValue,
        'is_working': agent.chat.session.isWorking,
        if (lastMessage.isNotEmpty)
          'last_message': lastMessage.substring(
            0,
            lastMessage.length.clamp(0, 100),
          ),
        'turn_count': (entryCount / 2).floor(),
        'has_pending_permission':
            agent.chat.permissions.pendingPermission != null,
      });
    }
    return InternalToolResult.text(
      jsonEncode({'agents': agents, 'errors': errors}),
    );
  }

  InternalToolDefinition _listTicketsTool() {
    return InternalToolDefinition(
      name: 'list_tickets',
      description: 'Lists tickets with optional filters.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'category': {'type': 'string'},
          'depends_on': {'type': 'integer'},
          'dependency_of': {'type': 'integer'},
          'ids': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
        },
      },
      handler: _handleListTickets,
    );
  }

  Future<InternalToolResult> _handleListTickets(
    Map<String, dynamic> input,
  ) async {
    final ticketBoard = _ticketBoard;
    if (ticketBoard == null) {
      return InternalToolResult.error('Ticket board not available');
    }
    var tickets = ticketBoard.tickets.toList();
    final statuses = (input['status'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toSet();
    if (statuses != null && statuses.isNotEmpty) {
      tickets = tickets.where((t) => statuses.contains(t.status.name)).toList();
    }
    final category = input['category'] as String?;
    if (category != null && category.isNotEmpty) {
      tickets = tickets.where((t) => t.category == category).toList();
    }
    final dependsOn = (input['depends_on'] as num?)?.toInt();
    if (dependsOn != null) {
      tickets = tickets.where((t) => t.dependsOn.contains(dependsOn)).toList();
    }
    final dependencyOf = (input['dependency_of'] as num?)?.toInt();
    if (dependencyOf != null) {
      final target = ticketBoard.getTicket(dependencyOf);
      if (target != null) {
        tickets = tickets
            .where((t) => target.dependsOn.contains(t.id))
            .toList();
      } else {
        tickets = [];
      }
    }
    final ids = (input['ids'] as List<dynamic>?)
        ?.map((e) => (e as num).toInt())
        .toSet();
    if (ids != null && ids.isNotEmpty) {
      tickets = tickets.where((t) => ids.contains(t.id)).toList();
    }

    final summaries = tickets
        .map(
          (t) => {
            'id': t.id,
            'display_id': t.displayId,
            'title': t.title,
            'status': t.status.name,
            'kind': t.kind.name,
            'priority': t.priority.name,
            'depends_on': t.dependsOn,
          },
        )
        .toList();
    return InternalToolResult.text(jsonEncode({'tickets': summaries}));
  }

  InternalToolDefinition _getTicketTool() {
    return InternalToolDefinition(
      name: 'get_ticket',
      description: 'Gets full details for a single ticket.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ticket_id': {'type': 'integer'},
        },
        'required': ['ticket_id'],
      },
      handler: _handleGetTicket,
    );
  }

  Future<InternalToolResult> _handleGetTicket(
    Map<String, dynamic> input,
  ) async {
    final ticketBoard = _ticketBoard;
    if (ticketBoard == null) {
      return InternalToolResult.error('Ticket board not available');
    }
    final id = (input['ticket_id'] as num?)?.toInt();
    if (id == null) return InternalToolResult.error('Missing "ticket_id"');
    final ticket = ticketBoard.getTicket(id);
    if (ticket == null)
      return InternalToolResult.error('ticket_not_found: $id');
    final unblockedBy = ticket.dependsOn.where((depId) {
      final dep = ticketBoard.getTicket(depId);
      return dep?.status == TicketStatus.completed;
    }).toList();
    return InternalToolResult.text(
      jsonEncode({'ticket': ticket.toJson(), 'unblocked_by': unblockedBy}),
    );
  }

  InternalToolDefinition _updateTicketTool() {
    return InternalToolDefinition(
      name: 'update_ticket',
      description: 'Updates ticket status and/or appends a comment.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ticket_id': {'type': 'integer'},
          'status': {'type': 'string'},
          'comment': {'type': 'string'},
        },
        'required': ['ticket_id'],
      },
      handler: _handleUpdateTicket,
    );
  }

  Future<InternalToolResult> _handleUpdateTicket(
    Map<String, dynamic> input,
  ) async {
    final ticketBoard = _ticketBoard;
    if (ticketBoard == null) {
      return InternalToolResult.error('Ticket board not available');
    }
    final ticketId = (input['ticket_id'] as num?)?.toInt();
    if (ticketId == null)
      return InternalToolResult.error('Missing "ticket_id"');
    final ticket = ticketBoard.getTicket(ticketId);
    if (ticket == null)
      return InternalToolResult.error('ticket_not_found: $ticketId');

    final previousStatus = ticket.status.name;
    TicketStatus? nextStatus;
    final rawStatus = input['status'] as String?;
    if (rawStatus != null) {
      nextStatus = _parseTicketStatus(rawStatus);
      if (nextStatus == null) {
        return InternalToolResult.error('invalid_status: $rawStatus');
      }
      ticketBoard.setStatus(ticketId, nextStatus);
    }

    final comment = input['comment'] as String?;
    if (comment != null && comment.trim().isNotEmpty) {
      ticketBoard.addComment(ticketId, comment.trim());
    }

    final unblocked = ticketBoard
        .getBlockedBy(ticketId)
        .where((id) => ticketBoard.getTicket(id)?.status == TicketStatus.ready)
        .toList();

    return InternalToolResult.text(
      jsonEncode({
        'success': true,
        'previous_status': previousStatus,
        'new_status': (nextStatus ?? ticket.status).name,
        'unblocked_tickets': unblocked,
      }),
    );
  }

  InternalToolDefinition _createWorktreeTool(Chat orchestratorChat) {
    return InternalToolDefinition(
      name: 'create_worktree',
      description: 'Creates a new linked worktree.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'branch_name': {'type': 'string'},
          'base_ref': {'type': 'string'},
        },
        'required': ['branch_name'],
      },
      handler: (input) => _handleCreateWorktree(orchestratorChat, input),
    );
  }

  Future<InternalToolResult> _handleCreateWorktree(
    Chat orchestratorChat,
    Map<String, dynamic> input,
  ) async {
    final project = _project;
    final worktreeService = _worktreeService;
    if (project == null || worktreeService == null) {
      return InternalToolResult.error('Worktree context not available');
    }
    final branchName = input['branch_name'] as String?;
    if (branchName == null || branchName.isEmpty) {
      return InternalToolResult.error('Missing "branch_name"');
    }
    var baseRef = input['base_ref'] as String?;
    if (baseRef == null || baseRef.isEmpty) {
      final state = getOrchestratorState(orchestratorChat);
      final baseWorktree = state != null
          ? _findWorktreeByPath(state.baseWorktreePath)
          : project.primaryWorktree;
      baseRef = baseWorktree?.data.branch;
    }

    try {
      final worktreeRoot = await calculateDefaultWorktreeRoot(
        project.data.repoRoot,
      );
      final worktree = await worktreeService.createWorktree(
        project: project,
        branch: branchName,
        worktreeRoot: worktreeRoot,
        base: baseRef,
      );
      project.addLinkedWorktree(worktree);
      return InternalToolResult.text(
        jsonEncode({
          'worktree_path': worktree.data.worktreeRoot,
          'branch': worktree.data.branch,
        }),
      );
    } catch (e) {
      return InternalToolResult.error('Failed to create worktree: $e');
    }
  }

  InternalToolDefinition _rebaseAndMergeTool(Chat orchestratorChat) {
    return InternalToolDefinition(
      name: 'rebase_and_merge',
      description:
          'Rebases a worker branch onto base and merges into the base worktree.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'worktree_path': {'type': 'string'},
        },
        'required': ['worktree_path'],
      },
      handler: (input) => _handleRebaseAndMerge(orchestratorChat, input),
    );
  }

  Future<InternalToolResult> _handleRebaseAndMerge(
    Chat orchestratorChat,
    Map<String, dynamic> input,
  ) async {
    final path = input['worktree_path'] as String?;
    final gitService = _gitService;
    final project = _project;
    if (path == null || path.isEmpty) {
      return InternalToolResult.error('Missing "worktree_path"');
    }
    if (gitService == null || project == null) {
      return InternalToolResult.error('Git/project context not available');
    }

    final worker = _findWorktreeByPath(path);
    if (worker == null)
      return InternalToolResult.error('worktree_not_found: $path');
    final orchestratorState = getOrchestratorState(orchestratorChat);
    if (orchestratorState == null) {
      return InternalToolResult.error('orchestrator_state_missing');
    }
    final baseWorktree = _findWorktreeByPath(
      orchestratorState.baseWorktreePath,
    );
    if (baseWorktree == null) {
      return InternalToolResult.error(
        'base_worktree_not_found: ${orchestratorState.baseWorktreePath}',
      );
    }
    final baseBranch = baseWorktree.data.branch;

    final rebase = await gitService.rebase(path, baseBranch);
    if (rebase.hasConflicts) {
      return InternalToolResult.text(
        jsonEncode({'success': false, 'conflicts': true, 'merged_commits': 0}),
      );
    }
    if (rebase.error != null) {
      return InternalToolResult.error(rebase.error ?? 'Rebase failed');
    }

    final merge = await gitService.merge(
      baseWorktree.data.worktreeRoot,
      worker.data.branch,
    );
    if (merge.hasConflicts) {
      return InternalToolResult.text(
        jsonEncode({'success': false, 'conflicts': true, 'merged_commits': 0}),
      );
    }
    if (merge.error != null) {
      return InternalToolResult.error(merge.error ?? 'Merge failed');
    }

    // Update the worker worktree's base ref to point at the orchestrator's
    // branch, so the UI accurately reflects the merge target.
    worker.setBase(baseBranch);
    final persistence = _persistenceService;
    if (persistence != null && project != null) {
      try {
        await persistence.updateWorktreeBase(
          projectRoot: project.data.repoRoot,
          worktreePath: path,
          base: baseBranch,
        );
      } catch (e) {
        developer.log(
          'rebase_and_merge: failed to persist base update: $e',
          name: 'InternalToolsService',
        );
      }
    }

    return InternalToolResult.text(
      jsonEncode({'success': true, 'conflicts': false, 'merged_commits': 1}),
    );
  }

  InternalToolDefinition _deleteWorktreeTool() {
    return InternalToolDefinition(
      name: 'delete_worktree',
      description: 'Deletes a linked worktree and optionally its branch.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'worktree_path': {'type': 'string'},
          'delete_branch': {'type': 'boolean'},
        },
        'required': ['worktree_path'],
      },
      handler: _handleDeleteWorktree,
    );
  }

  Future<InternalToolResult> _handleDeleteWorktree(
    Map<String, dynamic> input,
  ) async {
    final path = input['worktree_path'] as String?;
    final deleteBranch = input['delete_branch'] as bool? ?? false;
    final project = _project;
    final gitService = _gitService;
    if (path == null || path.isEmpty) {
      return InternalToolResult.error('Missing "worktree_path"');
    }
    if (project == null || gitService == null) {
      return InternalToolResult.error('Worktree context not available');
    }
    final worktree = _findWorktreeByPath(path);
    if (worktree == null) {
      return InternalToolResult.error('worktree_not_found: $path');
    }
    if (worktree.data.isPrimary) {
      return InternalToolResult.error('Cannot delete primary worktree');
    }

    try {
      await gitService.removeWorktree(
        repoRoot: project.data.repoRoot,
        worktreePath: path,
      );
      if (deleteBranch) {
        await gitService.deleteBranch(
          repoRoot: project.data.repoRoot,
          branchName: worktree.data.branch,
        );
      }
      project.removeLinkedWorktree(worktree);
      return InternalToolResult.text(jsonEncode({'success': true}));
    } catch (e) {
      return InternalToolResult.error('Failed to delete worktree: $e');
    }
  }

  InternalToolDefinition _setTagsTool() {
    return InternalToolDefinition(
      name: 'set_tags',
      description: 'Sets the tags for a given worktree.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'worktree': {
            'type': 'string',
            'description': 'Absolute path to the worktree',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'List of tag names to assign to the worktree',
          },
        },
        'required': ['worktree', 'tags'],
      },
      handler: _handleSetTags,
    );
  }

  Future<InternalToolResult> _handleSetTags(
    Map<String, dynamic> input,
  ) async {
    final worktreePath = input['worktree'] as String?;
    if (worktreePath == null || worktreePath.isEmpty) {
      return InternalToolResult.error('Missing required "worktree"');
    }
    final tagsInput = input['tags'];
    if (tagsInput == null || tagsInput is! List) {
      return InternalToolResult.error(
        'Missing or invalid "tags" field. Expected an array of strings.',
      );
    }
    final tags = tagsInput.map((e) => e.toString()).toList();

    final worktree = _findWorktreeByPath(worktreePath);
    if (worktree == null) {
      return InternalToolResult.error('worktree_not_found: $worktreePath');
    }

    worktree.setTags(tags);

    final project = _project;
    final persistence = _persistenceService;
    if (project != null && persistence != null) {
      try {
        await persistence.updateWorktreeTags(
          projectRoot: project.data.repoRoot,
          worktreePath: worktreePath,
          tags: tags,
        );
      } catch (e) {
        developer.log(
          'set_tags: failed to persist tags: $e',
          name: 'InternalToolsService',
        );
      }
    }

    return InternalToolResult.text(
      jsonEncode({
        'success': true,
        'worktree': worktreePath,
        'tags': tags,
      }),
    );
  }

  InternalToolDefinition _listTagsTool() {
    return InternalToolDefinition(
      name: 'list_tags',
      description: 'Lists all available tags that can be applied to worktrees.',
      inputSchema: {
        'type': 'object',
        'properties': {},
      },
      handler: _handleListTags,
    );
  }

  Future<InternalToolResult> _handleListTags(
    Map<String, dynamic> input,
  ) async {
    final settings = _settingsService;
    final tags = settings?.availableTags ?? WorktreeTag.defaults;
    return InternalToolResult.text(
      jsonEncode({
        'tags': tags.map((t) => {'name': t.name, 'color': t.colorValue}).toList(),
      }),
    );
  }

  WorktreeState? _findWorktreeByPath(String path) {
    final project = _project;
    if (project == null) return null;
    return project.allWorktrees
        .where((w) => w.data.worktreeRoot == path)
        .firstOrNull;
  }

  Chat? _findChatById(String chatId) {
    final project = _project;
    if (project == null) return null;
    for (final worktree in project.allWorktrees) {
      for (final chat in worktree.chats) {
        if (chat.id == chatId) return chat;
      }
    }
    return null;
  }

  bool _isAgentReady(Chat chat) {
    if (chat.session.sessionPhase == SessionPhase.errored) return true;
    if (!chat.session.hasActiveSession) return true;
    return !chat.session.isWorking;
  }

  AgentReadyReason _reasonForAgent(Chat chat) {
    if (chat.session.sessionPhase == SessionPhase.errored) {
      return AgentReadyReason.error;
    }
    if (!chat.session.hasActiveSession) {
      return AgentReadyReason.stopped;
    }
    return AgentReadyReason.turnComplete;
  }

  Future<bool> _waitUntilAgentIdle(
    Chat chat, {
    required Duration timeout,
    bool treatPermissionAsReady = true,
  }) async {
    bool isReady() => treatPermissionAsReady
        ? _isAgentReady(chat)
        : _isAgentIdleIgnoringPermissions(chat);

    if (isReady()) return true;
    final completer = Completer<void>();
    void listener() {
      if (isReady() && !completer.isCompleted) {
        completer.complete();
      }
    }

    chat.session.addListener(listener);
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      chat.session.removeListener(listener);
    }
  }

  /// Like [_isAgentReady] but does NOT treat pending permissions as "ready".
  /// Used by ask_agent so the orchestrator gets a timeout error when the
  /// agent is waiting on user permission rather than silently completing.
  bool _isAgentIdleIgnoringPermissions(Chat chat) {
    if (chat.session.sessionPhase == SessionPhase.errored) return true;
    if (!chat.session.hasActiveSession) return true;
    return !chat.session.isWorking;
  }

  String _extractLastAssistantMessage(Chat chat) {
    final entries = chat.data.primaryConversation.entries;
    for (final entry in entries.reversed) {
      if (entry is TextOutputEntry &&
          entry.contentType != 'error' &&
          entry.text.trim().isNotEmpty) {
        return entry.text.trim();
      }
    }
    return '';
  }

  Duration _parseWaitTimeout(Map<String, dynamic> input) {
    final raw = (input['timeout_seconds'] as num?)?.toInt();
    if (raw == null || raw <= 0) {
      return const Duration(seconds: _defaultWaitTimeoutSeconds);
    }
    final seconds = raw.clamp(1, _maxWaitTimeoutSeconds);
    return Duration(seconds: seconds);
  }

  Duration _parseAskTimeout(Map<String, dynamic> input) {
    final raw = (input['timeout_seconds'] as num?)?.toInt();
    if (raw == null || raw <= 0) {
      return const Duration(seconds: _defaultAskTimeoutSeconds);
    }
    final seconds = raw.clamp(1, _maxWaitTimeoutSeconds);
    return Duration(seconds: seconds);
  }

  TicketStatus? _parseTicketStatus(String statusName) {
    for (final status in TicketStatus.values) {
      if (status.name == statusName) {
        return status;
      }
    }
    return null;
  }

  String? _mergePromptText(List<String?> parts) {
    final filtered = parts
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (filtered.isEmpty) return null;
    return filtered.join('\n\n');
  }

  // ===========================================================================
  // Git tools
  // ===========================================================================

  GitService? _gitService;

  /// Register git tools (commit_context, commit, log, diff) with the given
  /// git service.
  void registerGitTools(GitService gitService) {
    _gitService = gitService;
    _registry.register(_gitCommitContextTool());
    _registry.register(_gitCommitTool());
    _registry.register(_gitLogTool());
    _registry.register(_gitDiffTool());
  }

  /// Unregister git tools.
  void unregisterGitTools() {
    _registry.unregister('git_commit_context');
    _registry.unregister('git_commit');
    _registry.unregister('git_log');
    _registry.unregister('git_diff');
    _gitService = null;
  }

  // ---------------------------------------------------------------------------
  // git_commit_context
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitCommitContextTool() {
    return InternalToolDefinition(
      name: 'git_commit_context',
      description:
          'Returns git context needed for crafting a commit: '
          'current branch, file status grouped by type, diff stat, '
          'and recent commit messages. Use before making a commit.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
        },
        'required': ['path'],
      },
      handler: _handleGitCommitContext,
    );
  }

  Future<InternalToolResult> _handleGitCommitContext(
    Map<String, dynamic> input,
  ) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    try {
      final results = await Future.wait([
        gitService.getCurrentBranch(path),
        gitService.getChangedFiles(path),
        gitService.getDiffStat(path),
        gitService.getRecentCommits(path, count: 5),
      ]);

      final branch = results[0] as String?;
      final changedFiles = results[1] as List<GitFileChange>;
      final diffStat = results[2] as String;
      final recentCommits = results[3] as List<({String sha, String message})>;

      // Group files by status
      final modified = <String>[];
      final untracked = <String>[];
      final deleted = <String>[];
      final staged = <String>[];

      for (final file in changedFiles) {
        if (file.status == GitFileStatus.untracked) {
          untracked.add(file.path);
        } else if (file.isStaged) {
          staged.add(file.path);
        } else if (file.status == GitFileStatus.deleted) {
          deleted.add(file.path);
        } else {
          modified.add(file.path);
        }
      }

      final result = jsonEncode({
        'branch': branch,
        'status': {
          'modified': modified,
          'untracked': untracked,
          'deleted': deleted,
          'staged': staged,
        },
        'diff_stat': diffStat.trimRight(),
        'recent_commits': recentCommits
            .map((c) => {'sha': c.sha, 'message': c.message})
            .toList(),
      });

      return InternalToolResult.text(result);
    } on GitException catch (e) {
      return InternalToolResult.error('Git error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // git_commit
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitCommitTool() {
    return InternalToolDefinition(
      name: 'git_commit',
      description:
          'Stages specific files and creates a git commit. '
          'Files must be listed explicitly — no wildcards or "." allowed. '
          'Does not support amending.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
          'files': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'File paths (relative to path) to stage. '
                'No "." or "*" wildcards.',
          },
          'message': {'type': 'string', 'description': 'The commit message'},
          'co_author': {
            'type': 'string',
            'description':
                'Optional Co-Authored-By value '
                '(e.g. "Name <email>"). Appended as a trailer.',
          },
        },
        'required': ['path', 'files', 'message'],
      },
      handler: _handleGitCommit,
    );
  }

  Future<InternalToolResult> _handleGitCommit(
    Map<String, dynamic> input,
  ) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    // Validate files
    final filesInput = input['files'];
    if (filesInput == null || filesInput is! List || filesInput.isEmpty) {
      return InternalToolResult.error(
        'Missing or invalid "files" field. '
        'Expected a non-empty array of file paths.',
      );
    }

    final files = <String>[];
    for (var i = 0; i < filesInput.length; i++) {
      final file = filesInput[i];
      if (file is! String || file.isEmpty) {
        return InternalToolResult.error(
          'File at index $i is not a valid string.',
        );
      }
      if (file == '.' || file.contains('*')) {
        return InternalToolResult.error(
          'Wildcards and "." are not allowed. '
          'Specify each file explicitly. Got: "$file"',
        );
      }
      files.add(file);
    }

    // Validate message
    final message = input['message'] as String?;
    if (message == null || message.isEmpty) {
      return InternalToolResult.error('Missing or empty "message" field.');
    }

    // Build full message with optional co-author trailer
    final coAuthor = input['co_author'] as String?;
    final fullMessage = StringBuffer(message);
    if (coAuthor != null && coAuthor.isNotEmpty) {
      fullMessage.write('\n\nCo-Authored-By: $coAuthor');
    }

    try {
      await gitService.stageFiles(path, files);
      await gitService.commit(path, fullMessage.toString());

      // Get the short SHA of the new commit
      final sha = await gitService.getHeadShortSha(path);

      final fileCount = files.length;
      final filesWord = fileCount == 1 ? 'file' : 'files';
      return InternalToolResult.text(
        'Committed $sha ($fileCount $filesWord): '
        '${message.split('\n').first}',
      );
    } on GitException catch (e) {
      // Best-effort reset of the index on failure
      try {
        await gitService.resetIndex(path);
      } catch (_) {}

      return InternalToolResult.error('Commit failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // git_log
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitLogTool() {
    return InternalToolDefinition(
      name: 'git_log',
      description:
          'Returns the full git log (messages, authors, dates) '
          'for recent commits.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
          'count': {
            'type': 'integer',
            'description': 'Number of commits to show (default: 5, max: 50)',
          },
        },
        'required': ['path'],
      },
      handler: _handleGitLog,
    );
  }

  Future<InternalToolResult> _handleGitLog(Map<String, dynamic> input) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    var count = (input['count'] as num?)?.toInt() ?? 5;
    if (count < 1) count = 1;
    if (count > 50) count = 50;

    try {
      final log = await gitService.getLog(path, count: count);
      if (log.isEmpty) {
        return InternalToolResult.text('(no commits)');
      }
      return InternalToolResult.text(log.trimRight());
    } on GitException catch (e) {
      return InternalToolResult.error('Git error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // git_diff
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitDiffTool() {
    return InternalToolDefinition(
      name: 'git_diff',
      description:
          'Returns the git diff output for the working directory. '
          'Shows unstaged changes by default, or staged changes '
          'with the staged option.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
          'staged': {
            'type': 'boolean',
            'description':
                'If true, show staged changes (--cached). Default: false',
          },
          'files': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional list of file paths to limit the diff to',
          },
        },
        'required': ['path'],
      },
      handler: _handleGitDiff,
    );
  }

  Future<InternalToolResult> _handleGitDiff(Map<String, dynamic> input) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    final staged = input['staged'] as bool? ?? false;

    List<String>? files;
    final filesInput = input['files'];
    if (filesInput is List && filesInput.isNotEmpty) {
      files = filesInput.cast<String>();
    }

    try {
      final diff = await gitService.getDiff(path, staged: staged, files: files);
      if (diff.isEmpty) {
        return InternalToolResult.text('(no changes)');
      }
      return InternalToolResult.text(diff.trimRight());
    } on GitException catch (e) {
      return InternalToolResult.error('Git error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  /// Validates and extracts the path from tool input.
  /// Returns null if path is missing, empty, or not absolute.
  String? _validatePath(Map<String, dynamic> input) {
    final path = input['path'] as String?;
    if (path == null || path.isEmpty || !path.startsWith('/')) {
      return null;
    }
    return path;
  }
}
