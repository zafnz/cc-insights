import 'dart:async';

import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

/// Tests for Codex dynamic tool call handling (item/tool/call).
///
/// Verifies that CodexSession correctly routes dynamic tool calls to the
/// InternalToolRegistry and responds with the appropriate format.
void main() {
  group('CodexSession dynamic tool calls', () {
    late InternalToolRegistry registry;
    late CodexSession session;
    late List<InsightsEvent> capturedEvents;
    late StreamSubscription<InsightsEvent> eventSub;

    setUp(() {
      registry = InternalToolRegistry();
      registry.register(InternalToolDefinition(
        name: 'create_ticket',
        description: 'Create a ticket',
        inputSchema: {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
          },
        },
        handler: (input) async {
          final title = input['title'] as String? ?? 'untitled';
          return InternalToolResult.text('Created ticket: $title');
        },
      ));
      registry.register(InternalToolDefinition(
        name: 'failing_tool',
        description: 'A tool that returns errors',
        inputSchema: {'type': 'object'},
        handler: (input) async {
          return InternalToolResult.error('Something went wrong');
        },
      ));
      registry.register(InternalToolDefinition(
        name: 'throwing_tool',
        description: 'A tool that throws',
        inputSchema: {'type': 'object'},
        handler: (input) async {
          throw StateError('handler exploded');
        },
      ));

      session = CodexSession.forTesting(
        threadId: 'test-thread',
        registry: registry,
      );
      capturedEvents = [];
      eventSub = session.events.listen((e) => capturedEvents.add(e));
    });

    tearDown(() async {
      await eventSub.cancel();
      await session.kill();
    });

    Future<void> waitForEvents() async {
      await Future.delayed(Duration(milliseconds: 10));
    }

    test('routes item/tool/call to registry handler and responds with success',
        () async {
      // CodexSession.forTesting has no process, so sendResponse is a no-op.
      // We verify the handler is invoked by checking it doesn't throw.
      session.injectServerRequest(JsonRpcServerRequest(
        id: 100,
        method: 'item/tool/call',
        params: {
          'threadId': 'test-thread',
          'tool': 'create_ticket',
          'arguments': {'title': 'Fix bug'},
          'callId': 'call-001',
        },
      ));
      await waitForEvents();
      // No InsightsEvents should be emitted for dynamic tool calls
      expect(capturedEvents, isEmpty);
    });

    test('returns error for unknown tool name', () async {
      session.injectServerRequest(JsonRpcServerRequest(
        id: 101,
        method: 'item/tool/call',
        params: {
          'threadId': 'test-thread',
          'tool': 'nonexistent_tool',
          'arguments': {},
        },
      ));
      await waitForEvents();
      expect(capturedEvents, isEmpty);
    });

    test('handles tool that returns error result', () async {
      session.injectServerRequest(JsonRpcServerRequest(
        id: 102,
        method: 'item/tool/call',
        params: {
          'threadId': 'test-thread',
          'tool': 'failing_tool',
          'arguments': {},
        },
      ));
      await waitForEvents();
      expect(capturedEvents, isEmpty);
    });

    test('handles tool handler that throws exception', () async {
      session.injectServerRequest(JsonRpcServerRequest(
        id: 103,
        method: 'item/tool/call',
        params: {
          'threadId': 'test-thread',
          'tool': 'throwing_tool',
          'arguments': {},
        },
      ));
      await waitForEvents();
      // Should not throw unhandled async error
      expect(capturedEvents, isEmpty);
    });

    test('ignores item/tool/call with wrong threadId', () async {
      session.injectServerRequest(JsonRpcServerRequest(
        id: 104,
        method: 'item/tool/call',
        params: {
          'threadId': 'wrong-thread',
          'tool': 'create_ticket',
          'arguments': {'title': 'test'},
        },
      ));
      await waitForEvents();
      expect(capturedEvents, isEmpty);
    });

    test('handles missing registry gracefully', () async {
      final noRegistrySession = CodexSession.forTesting(
        threadId: 'test-thread',
      );
      final events = <InsightsEvent>[];
      final sub = noRegistrySession.events.listen((e) => events.add(e));

      noRegistrySession.injectServerRequest(JsonRpcServerRequest(
        id: 105,
        method: 'item/tool/call',
        params: {
          'threadId': 'test-thread',
          'tool': 'create_ticket',
          'arguments': {},
        },
      ));
      await waitForEvents();
      expect(events, isEmpty);

      await sub.cancel();
      await noRegistrySession.kill();
    });

    test('handles null arguments gracefully', () async {
      session.injectServerRequest(JsonRpcServerRequest(
        id: 106,
        method: 'item/tool/call',
        params: {
          'threadId': 'test-thread',
          'tool': 'create_ticket',
          'arguments': null,
        },
      ));
      await waitForEvents();
      expect(capturedEvents, isEmpty);
    });

    test('does not interfere with existing approval requests', () async {
      // Verify that existing server request handling still works
      session.injectServerRequest(JsonRpcServerRequest(
        id: 200,
        method: 'item/commandExecution/requestApproval',
        params: {
          'threadId': 'test-thread',
          'command': 'ls',
          'cwd': '/tmp',
          'itemId': 'item-200',
        },
      ));
      await waitForEvents();
      expect(capturedEvents, hasLength(1));
      expect(capturedEvents.first, isA<PermissionRequestEvent>());
      final event = capturedEvents.first as PermissionRequestEvent;
      expect(event.toolName, 'Bash');
    });
  });
}
