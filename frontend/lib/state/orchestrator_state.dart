import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/managed_agent.dart';
import '../models/ticket.dart';
import 'ticket_board_state.dart';

/// Per-orchestrator runtime state.
class OrchestratorState extends ChangeNotifier {
  OrchestratorState({
    required TicketRepository ticketBoard,
    required Iterable<int> ticketIds,
    required String baseWorktreePath,
    Chat? orchestratorChat,
    DateTime? startTime,
  }) : _ticketBoard = ticketBoard,
       _ticketIds = {...ticketIds},
       _baseWorktreePath = baseWorktreePath,
       _orchestrationStartTime = startTime ?? DateTime.now() {
    if (orchestratorChat != null) {
      setOrchestratorChat(orchestratorChat);
    }
  }

  final TicketRepository _ticketBoard;
  final Map<String, ManagedAgent> _agents = {};
  final Map<String, List<VoidCallback>> _agentListeners = {};
  Chat? _orchestratorChat;
  VoidCallback? _orchestratorMetricsListener;

  final Set<int> _ticketIds;
  final String _baseWorktreePath;
  final DateTime _orchestrationStartTime;

  Map<String, ManagedAgent> get agents => Map.unmodifiable(_agents);
  Set<int> get ticketIds => Set.unmodifiable(_ticketIds);
  String get baseWorktreePath => _baseWorktreePath;
  DateTime get orchestrationStartTime => _orchestrationStartTime;

  void registerAgent({
    required String agentId,
    required Chat chat,
    int? ticketId,
  }) {
    if (_agents.containsKey(agentId)) {
      throw ArgumentError('Agent already registered: $agentId');
    }

    final agent = ManagedAgent(id: agentId, chat: chat, ticketId: ticketId);
    _agents[agentId] = agent;

    final listeners = <VoidCallback>[];
    void forward() => notifyListeners();
    chat.session.addListener(forward);
    listeners.add(() => chat.session.removeListener(forward));
    chat.permissions.addListener(forward);
    listeners.add(() => chat.permissions.removeListener(forward));
    chat.metrics.addListener(forward);
    listeners.add(() => chat.metrics.removeListener(forward));
    _agentListeners[agentId] = listeners;

    notifyListeners();
  }

  void unregisterAgent(String agentId) {
    final removed = _agents.remove(agentId);
    if (removed == null) return;

    final listeners = _agentListeners.remove(agentId);
    if (listeners != null) {
      for (final dispose in listeners) {
        dispose();
      }
    }

    notifyListeners();
  }

  /// Sets (or replaces) the orchestrator chat whose cost is included in
  /// [getTotalCost].
  void setOrchestratorChat(Chat chat) {
    if (identical(_orchestratorChat, chat)) return;
    // Remove previous listener.
    if (_orchestratorMetricsListener != null) {
      _orchestratorChat?.metrics.removeListener(_orchestratorMetricsListener!);
    }
    _orchestratorChat = chat;
    void forward() => notifyListeners();
    chat.metrics.addListener(forward);
    _orchestratorMetricsListener = forward;
  }

  ManagedAgent? getAgent(String agentId) => _agents[agentId];

  Duration getElapsedTime() =>
      DateTime.now().difference(_orchestrationStartTime);

  ({int completed, int total}) getProgress() {
    final tickets = _ticketIds
        .map(_ticketBoard.getTicket)
        .whereType<TicketData>()
        .toList();
    final completed = tickets
        .where((t) => t.status == TicketStatus.completed)
        .length;
    return (completed: completed, total: tickets.length);
  }

  int get activeAgentCount =>
      _agents.values.where((a) => a.chat.session.isWorking).length;

  double getTotalCost() {
    final orchestratorCost =
        _orchestratorChat?.metrics.cumulativeUsage.costUsd ?? 0.0;
    return _agents.values.fold<double>(
      orchestratorCost,
      (sum, agent) => sum + agent.chat.metrics.cumulativeUsage.costUsd,
    );
  }

  Map<String, dynamic> toSnapshot() {
    return {
      'ticketIds': _ticketIds.toList()..sort(),
      'baseWorktreePath': _baseWorktreePath,
      'startTime': _orchestrationStartTime.toUtc().toIso8601String(),
      'agents': _agents.values.map((a) => a.toSnapshot()).toList(),
    };
  }

  @override
  void dispose() {
    if (_orchestratorMetricsListener != null) {
      _orchestratorChat?.metrics.removeListener(_orchestratorMetricsListener!);
      _orchestratorMetricsListener = null;
    }
    _orchestratorChat = null;

    for (final agent in _agents.values) {
      if (agent.chat.session.hasActiveSession) {
        unawaited(agent.chat.session.stop().catchError((_) {}));
      }
    }
    _agents.clear();

    for (final listeners in _agentListeners.values) {
      for (final dispose in listeners) {
        dispose();
      }
    }
    _agentListeners.clear();
    super.dispose();
  }
}
