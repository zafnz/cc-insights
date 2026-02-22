import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../state/selection_state.dart';
import '../state/ticket_board_state.dart';
import 'backend_service.dart';
import 'chat_session_service.dart';
import 'event_handler.dart';
import 'git_service.dart';
import 'internal_tools_service.dart';
import 'project_restore_service.dart';
import 'ticket_dispatch_service.dart';
import 'worktree_service.dart';

/// Creates [TicketDispatchService] from standard app providers.
TicketDispatchService createTicketDispatchService(BuildContext context) {
  return TicketDispatchService(
    ticketBoard: context.read<TicketRepository>(),
    project: context.read<ProjectState>(),
    selection: context.read<SelectionState>(),
    worktreeService: WorktreeService(gitService: context.read<GitService>()),
    restoreService: context.read<ProjectRestoreService>(),
    backend: context.read<BackendService>(),
    eventHandler: context.read<EventHandler>(),
    internalToolsService: context.read<InternalToolsService>(),
    chatSessionService: context.read<ChatSessionService>(),
  );
}
