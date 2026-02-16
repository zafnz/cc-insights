import 'package:agent_sdk_core/agent_sdk_core.dart'
    show
        BackendProvider,
        PermissionRequestEvent,
        TurnCompleteEvent,
        TokenUsage,
        ToolKind;
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart'
    show TicketRepository;
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// Event ID counter for generating unique event IDs.
int _idCounter = 0;

/// Generates a unique event ID.
String _nextId() => 'evt-transition-${_idCounter++}';

/// Helper to create a TurnCompleteEvent with optional usage data.
TurnCompleteEvent makeTurnCompleteEvent({
  TokenUsage? usage,
  double? costUsd,
  int? durationMs,
  String? parentToolUseId,
}) {
  return TurnCompleteEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    usage: usage,
    costUsd: costUsd,
    durationMs: durationMs,
    extensions: parentToolUseId != null
        ? {'parent_tool_use_id': parentToolUseId}
        : null,
  );
}

/// Helper to create a PermissionRequestEvent.
PermissionRequestEvent makePermissionRequestEvent({
  String? requestId,
  String toolName = 'Bash',
}) {
  return PermissionRequestEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    requestId: requestId ?? 'req-${_nextId()}',
    toolName: toolName,
    toolKind: ToolKind.execute,
    toolInput: {'command': 'ls'},
  );
}

void main() {
  final resources = TestResources();

  late Chat chat;
  late EventHandler handler;
  late TicketRepository ticketBoard;

  setUp(() {
    chat = resources.track(
      Chat.create(name: 'Test Chat', worktreeRoot: '/tmp/test'),
    );
    ticketBoard = resources.track(TicketRepository('test-project'));
    handler = EventHandler(ticketBoard: ticketBoard);
    _idCounter = 0;
  });

  tearDown(() async {
    handler.dispose();
    await resources.disposeAll();
  });

  group('EventHandler - turn complete ticket transitions', () {
    test('turn complete transitions linked ticket to inReview', () {
      // Create a ticket and link the chat to it
      final ticket = ticketBoard.createTicket(
        title: 'Implement feature',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      // Fire turn complete event
      final event = makeTurnCompleteEvent(
        usage: const TokenUsage(inputTokens: 1000, outputTokens: 500),
        costUsd: 0.05,
        durationMs: 3000,
      );
      handler.handleEvent(chat, event);

      // Verify ticket transitioned to inReview
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.inReview);
    });

    test('turn complete does not transition terminal tickets', () {
      // Create a completed ticket and link the chat
      final ticket = ticketBoard.createTicket(
        title: 'Done ticket',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      final event = makeTurnCompleteEvent(
        usage: const TokenUsage(inputTokens: 100, outputTokens: 50),
        costUsd: 0.01,
      );
      handler.handleEvent(chat, event);

      // Status should remain completed
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.completed);
    });

    test('events for unlinked chats do not crash or cause transitions', () {
      // Create a ticket but do NOT link the chat
      final ticket = ticketBoard.createTicket(
        title: 'Unlinked ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      final event = makeTurnCompleteEvent(
        usage: const TokenUsage(inputTokens: 500, outputTokens: 200),
        costUsd: 0.03,
      );

      // Should not throw
      handler.handleEvent(chat, event);

      // Ticket should still be active
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.active);
    });
  });

  group('EventHandler - permission request ticket transitions', () {
    test('permission request transitions linked ticket to needsInput', () {
      final ticket = ticketBoard.createTicket(
        title: 'Active ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      final event = makePermissionRequestEvent();
      handler.handleEvent(chat, event);

      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.needsInput);
    });

    test('permission request does not transition non-active tickets', () {
      // Ticket is in ready state, not active
      final ticket = ticketBoard.createTicket(
        title: 'Ready ticket',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      final event = makePermissionRequestEvent();
      handler.handleEvent(chat, event);

      // Should remain ready since it wasn't active
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.ready);
    });
  });

  group('EventHandler - permission response ticket transitions', () {
    test(
      'permission response transitions ticket from needsInput to active',
      () {
        final ticket = ticketBoard.createTicket(
          title: 'Waiting ticket',
          kind: TicketKind.feature,
          status: TicketStatus.needsInput,
        );
        ticketBoard.linkChat(
          ticket.id,
          chat.data.id,
          chat.data.name,
          '/tmp/test',
        );

        handler.handlePermissionResponse(chat);

        final updated = ticketBoard.getTicket(ticket.id)!;
        check(updated.status).equals(TicketStatus.active);
      },
    );

    test('permission response does not transition non-needsInput tickets', () {
      final ticket = ticketBoard.createTicket(
        title: 'Active ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      handler.handlePermissionResponse(chat);

      // Should remain active
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.active);
    });

    test('permission response is no-op when ticketBoard is null', () {
      final handlerWithoutBoard = EventHandler();

      // Should not throw
      handlerWithoutBoard.handlePermissionResponse(chat);

      handlerWithoutBoard.dispose();
    });
  });

  group('EventHandler - cost accumulation', () {
    test('turn complete accumulates cost stats on linked ticket', () {
      final ticket = ticketBoard.createTicket(
        title: 'Cost tracking ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      final event = makeTurnCompleteEvent(
        usage: const TokenUsage(inputTokens: 1000, outputTokens: 500),
        costUsd: 0.05,
        durationMs: 3000,
      );
      handler.handleEvent(chat, event);

      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.costStats).isNotNull();
      check(updated.costStats!.totalTokens).equals(1500);
      check(updated.costStats!.totalCost).equals(0.05);
      check(updated.costStats!.agentTimeMs).equals(3000);
    });

    test('cost accumulation from zero creates new costStats', () {
      final ticket = ticketBoard.createTicket(
        title: 'Fresh ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      // Verify no cost stats yet
      check(ticketBoard.getTicket(ticket.id)!.costStats).isNull();

      final event = makeTurnCompleteEvent(
        usage: const TokenUsage(inputTokens: 200, outputTokens: 100),
        costUsd: 0.01,
        durationMs: 1000,
      );
      handler.handleEvent(chat, event);

      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.costStats).isNotNull();
      check(updated.costStats!.totalTokens).equals(300);
      check(updated.costStats!.totalCost).equals(0.01);
      check(updated.costStats!.agentTimeMs).equals(1000);
      check(updated.costStats!.waitingTimeMs).equals(0);
    });

    test('cost stats accumulate across multiple turns', () {
      final ticket = ticketBoard.createTicket(
        title: 'Multi-turn ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      // First turn
      handler.handleEvent(
        chat,
        makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 1000, outputTokens: 500),
          costUsd: 0.05,
          durationMs: 3000,
        ),
      );

      // Second turn
      handler.handleEvent(
        chat,
        makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 2000, outputTokens: 800),
          costUsd: 0.08,
          durationMs: 5000,
        ),
      );

      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.costStats!.totalTokens).equals(4300); // 1500 + 2800
      check(updated.costStats!.totalCost).equals(0.13); // 0.05 + 0.08
      check(updated.costStats!.agentTimeMs).equals(8000); // 3000 + 5000
    });

    test('turn complete without usage does not add cost stats', () {
      final ticket = ticketBoard.createTicket(
        title: 'No usage ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      // Turn complete with no usage data
      final event = makeTurnCompleteEvent();
      handler.handleEvent(chat, event);

      // Should still transition to inReview but no cost stats
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.inReview);
      check(updated.costStats).isNull();
    });
  });

  group('TicketRepository - dependency auto-unblock', () {
    test('completing a dependency unblocks blocked ticket', () {
      // Create two tickets: dep and dependent
      final dep = ticketBoard.createTicket(
        title: 'Dependency',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dependent = ticketBoard.createTicket(
        title: 'Dependent',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [dep.id],
      );

      // Complete the dependency
      ticketBoard.markCompleted(dep.id);

      // Dependent should now be ready
      final updated = ticketBoard.getTicket(dependent.id)!;
      check(updated.status).equals(TicketStatus.ready);
    });

    test('partial dependency completion does not unblock', () {
      // Create three tickets: dep1, dep2, and dependent
      final dep1 = ticketBoard.createTicket(
        title: 'Dependency 1',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dep2 = ticketBoard.createTicket(
        title: 'Dependency 2',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dependent = ticketBoard.createTicket(
        title: 'Dependent',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [dep1.id, dep2.id],
      );

      // Complete only the first dependency
      ticketBoard.markCompleted(dep1.id);

      // Dependent should still be blocked
      final updated = ticketBoard.getTicket(dependent.id)!;
      check(updated.status).equals(TicketStatus.blocked);
    });

    test('completing all dependencies unblocks ticket', () {
      final dep1 = ticketBoard.createTicket(
        title: 'Dependency 1',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dep2 = ticketBoard.createTicket(
        title: 'Dependency 2',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dependent = ticketBoard.createTicket(
        title: 'Dependent',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [dep1.id, dep2.id],
      );

      // Complete both dependencies
      ticketBoard.markCompleted(dep1.id);
      ticketBoard.markCompleted(dep2.id);

      // Now dependent should be ready
      final updated = ticketBoard.getTicket(dependent.id)!;
      check(updated.status).equals(TicketStatus.ready);
    });

    test('auto-unblock only affects blocked tickets', () {
      final dep = ticketBoard.createTicket(
        title: 'Dependency',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      // Dependent is active, not blocked
      final dependent = ticketBoard.createTicket(
        title: 'Active dependent',
        kind: TicketKind.feature,
        status: TicketStatus.active,
        dependsOn: [dep.id],
      );

      ticketBoard.markCompleted(dep.id);

      // Should remain active (not changed to ready since it wasn't blocked)
      final updated = ticketBoard.getTicket(dependent.id)!;
      check(updated.status).equals(TicketStatus.active);
    });
  });

  group('TicketRepository - accumulateCostStats', () {
    test('creates cost stats from null', () {
      final ticket = ticketBoard.createTicket(
        title: 'Fresh ticket',
        kind: TicketKind.feature,
      );

      check(ticketBoard.getTicket(ticket.id)!.costStats).isNull();

      ticketBoard.accumulateCostStats(
        ticket.id,
        tokens: 1000,
        cost: 0.05,
        agentTimeMs: 3000,
      );

      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.costStats).isNotNull();
      check(updated.costStats!.totalTokens).equals(1000);
      check(updated.costStats!.totalCost).equals(0.05);
      check(updated.costStats!.agentTimeMs).equals(3000);
      check(updated.costStats!.waitingTimeMs).equals(0);
    });

    test('accumulates onto existing cost stats', () {
      final ticket = ticketBoard.createTicket(
        title: 'Existing stats ticket',
        kind: TicketKind.feature,
      );

      // First accumulation
      ticketBoard.accumulateCostStats(
        ticket.id,
        tokens: 500,
        cost: 0.02,
        agentTimeMs: 1000,
      );

      // Second accumulation
      ticketBoard.accumulateCostStats(
        ticket.id,
        tokens: 300,
        cost: 0.03,
        agentTimeMs: 2000,
      );

      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.costStats!.totalTokens).equals(800);
      check(updated.costStats!.totalCost).equals(0.05);
      check(updated.costStats!.agentTimeMs).equals(3000);
    });

    test('notifies listeners on cost accumulation', () {
      final ticket = ticketBoard.createTicket(
        title: 'Notify ticket',
        kind: TicketKind.feature,
      );

      var notified = false;
      ticketBoard.addListener(() => notified = true);

      ticketBoard.accumulateCostStats(
        ticket.id,
        tokens: 100,
        cost: 0.01,
        agentTimeMs: 500,
      );

      check(notified).isTrue();
    });
  });
}
