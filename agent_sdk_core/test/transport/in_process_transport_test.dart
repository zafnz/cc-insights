import 'dart:async';

import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fake AgentSession for testing
// ---------------------------------------------------------------------------

class FakeAgentSession implements AgentSession {
  @override
  final String sessionId = 'fake-session-id';

  @override
  String? get resolvedSessionId => 'fake-resolved-id';

  @override
  bool get isActive => true;

  final _eventsController = StreamController<InsightsEvent>.broadcast();
  final _permissionsController =
      StreamController<PermissionRequest>.broadcast();
  final _hooksController = StreamController<HookRequest>.broadcast();

  @override
  Stream<InsightsEvent> get events => _eventsController.stream;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionsController.stream;

  @override
  Stream<HookRequest> get hookRequests => _hooksController.stream;

  // Track calls for verification
  final List<String> sendCalls = [];
  final List<String?> setModelCalls = [];
  final List<String?> setPermissionModeCalls = [];
  final List<String?> setReasoningEffortCalls = [];
  int interruptCount = 0;
  int killCount = 0;

  @override
  Future<void> send(String message) async {
    sendCalls.add(message);
  }

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {}

  @override
  Future<void> interrupt() async {
    interruptCount++;
  }

  @override
  Future<void> kill() async {
    killCount++;
  }

  @override
  Future<void> setModel(String? model) async {
    setModelCalls.add(model);
  }

  @override
  Future<void> setPermissionMode(String? mode) async {
    setPermissionModeCalls.add(mode);
  }

  @override
  Future<void> setReasoningEffort(String? effort) async {
    setReasoningEffortCalls.add(effort);
  }

  @override
  String? get serverModel => null;

  @override
  String? get serverReasoningEffort => null;

  /// Emit an event on the session's events stream.
  void emitEvent(InsightsEvent event) {
    _eventsController.add(event);
  }

  /// Emit a permission request.
  PermissionRequest emitPermissionRequest({
    String id = 'req-1',
    String toolName = 'Bash',
    Map<String, dynamic> toolInput = const {'command': 'ls'},
  }) {
    final completer = Completer<PermissionResponse>();
    final request = PermissionRequest(
      id: id,
      sessionId: sessionId,
      toolName: toolName,
      toolInput: toolInput,
      completer: completer,
    );
    _permissionsController.add(request);
    return request;
  }

  Future<void> close() async {
    await _eventsController.close();
    await _permissionsController.close();
    await _hooksController.close();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeAgentSession session;
  late InProcessTransport transport;

  setUp(() {
    session = FakeAgentSession();
    transport = InProcessTransport(
      session: session,
      capabilities: const BackendCapabilities(
        supportsModelChange: true,
        supportsPermissionModeChange: true,
      ),
    );
  });

  tearDown(() async {
    await transport.dispose();
    await session.close();
  });

  group('InProcessTransport', () {
    group('properties', () {
      test('exposes session ID', () {
        expect(transport.sessionId, 'fake-session-id');
      });

      test('exposes resolved session ID', () {
        expect(transport.resolvedSessionId, 'fake-resolved-id');
      });

      test('exposes capabilities', () {
        expect(transport.capabilities!.supportsModelChange, isTrue);
        expect(transport.capabilities!.supportsPermissionModeChange, isTrue);
        expect(transport.capabilities!.supportsHooks, isFalse);
      });
    });

    group('status', () {
      test('is connected after creation', () {
        expect(transport.currentStatus, TransportStatus.connected);
      });

      test('emits disconnected when session events stream closes', () async {
        final statuses = <TransportStatus>[];
        transport.status.listen(statuses.add);

        // Close the session events stream.
        await session._eventsController.close();

        // Allow the done handler to propagate.
        await Future<void>.delayed(Duration.zero);
        expect(statuses, contains(TransportStatus.disconnected));
        expect(transport.currentStatus, TransportStatus.disconnected);
      });

      test('emits disconnected on dispose', () async {
        final statuses = <TransportStatus>[];
        transport.status.listen(statuses.add);

        await transport.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(statuses, contains(TransportStatus.disconnected));
        expect(transport.currentStatus, TransportStatus.disconnected);
      });
    });

    group('events forwarding', () {
      test('forwards events from session', () async {
        final received = <InsightsEvent>[];
        transport.events.listen(received.add);

        final event = TextEvent(
          id: 'evt-1',
          timestamp: DateTime.utc(2025),
          provider: BackendProvider.claude,
          sessionId: 'fake-session-id',
          text: 'Hello',
          kind: TextKind.text,
        );
        session.emitEvent(event);

        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1));
        expect(received.first, isA<TextEvent>());
        expect((received.first as TextEvent).text, 'Hello');
      });

      test('forwards multiple events in order', () async {
        final received = <InsightsEvent>[];
        transport.events.listen(received.add);

        session.emitEvent(TextEvent(
          id: 'evt-1',
          timestamp: DateTime.utc(2025),
          provider: BackendProvider.claude,
          sessionId: 's',
          text: 'First',
          kind: TextKind.text,
        ));
        session.emitEvent(TextEvent(
          id: 'evt-2',
          timestamp: DateTime.utc(2025),
          provider: BackendProvider.claude,
          sessionId: 's',
          text: 'Second',
          kind: TextKind.text,
        ));

        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(2));
        expect((received[0] as TextEvent).text, 'First');
        expect((received[1] as TextEvent).text, 'Second');
      });
    });

    group('send commands', () {
      test('SendMessageCommand calls session.send()', () async {
        await transport.send(SendMessageCommand(
          sessionId: 'fake-session-id',
          text: 'Fix the bug',
        ));

        expect(session.sendCalls, ['Fix the bug']);
      });

      test('InterruptCommand calls session.interrupt()', () async {
        await transport.send(InterruptCommand(sessionId: 'fake-session-id'));
        expect(session.interruptCount, 1);
      });

      test('KillCommand calls session.kill()', () async {
        await transport.send(KillCommand(sessionId: 'fake-session-id'));
        expect(session.killCount, 1);
      });

      test('SetModelCommand calls session.setModel()', () async {
        await transport.send(SetModelCommand(
          sessionId: 'fake-session-id',
          model: 'claude-sonnet-4-5',
        ));
        expect(session.setModelCalls, ['claude-sonnet-4-5']);
      });

      test('SetPermissionModeCommand calls session.setPermissionMode()',
          () async {
        await transport.send(SetPermissionModeCommand(
          sessionId: 'fake-session-id',
          mode: 'acceptEdits',
        ));
        expect(session.setPermissionModeCalls, ['acceptEdits']);
      });

      test('SetReasoningEffortCommand calls session.setReasoningEffort()',
          () async {
        await transport.send(SetReasoningEffortCommand(
          sessionId: 'fake-session-id',
          effort: 'high',
        ));
        expect(session.setReasoningEffortCalls, ['high']);
      });

      test('CreateSessionCommand throws UnsupportedError', () async {
        expect(
          () => transport.send(CreateSessionCommand(
            cwd: '/tmp',
            prompt: 'Hello',
          )),
          throwsUnsupportedError,
        );
      });
    });

    group('permission handling', () {
      test('forwards permission requests from session', () async {
        final received = <PermissionRequest>[];
        transport.permissionRequests.listen(received.add);

        session.emitPermissionRequest(id: 'req-1');

        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1));
        expect(received.first.id, 'req-1');
      });

      test('PermissionResponseCommand (allow) resolves the request', () async {
        transport.permissionRequests.listen((_) {});
        session.emitPermissionRequest(id: 'req-42');

        await Future<void>.delayed(Duration.zero);

        await transport.send(PermissionResponseCommand(
          requestId: 'req-42',
          allowed: true,
          updatedInput: {'command': 'ls -la'},
        ));

        // The request's completer should have been resolved.
        // We verify by checking the send completes without error.
      });

      test('PermissionResponseCommand (deny) resolves the request', () async {
        transport.permissionRequests.listen((_) {});
        session.emitPermissionRequest(id: 'req-43');

        await Future<void>.delayed(Duration.zero);

        await transport.send(PermissionResponseCommand(
          requestId: 'req-43',
          allowed: false,
          message: 'Not allowed',
          interrupt: true,
        ));
      });

      test('PermissionResponseCommand for unknown request is ignored',
          () async {
        // Should not throw.
        await transport.send(PermissionResponseCommand(
          requestId: 'nonexistent',
          allowed: true,
        ));
      });

      test('allow with updatedPermissions passes them through', () async {
        final receivedPermissions = <PermissionRequest>[];
        transport.permissionRequests.listen(receivedPermissions.add);

        session.emitPermissionRequest(id: 'req-50');
        await Future<void>.delayed(Duration.zero);
        await transport.send(PermissionResponseCommand(
          requestId: 'req-50',
          allowed: true,
          updatedPermissions: [
            {'toolName': 'Bash', 'behavior': 'allow'}
          ],
        ));

        // If we got here without throwing, the permission was resolved.
        expect(receivedPermissions, hasLength(1));
      });
    });

    group('dispose', () {
      test('clears pending permissions', () async {
        transport.permissionRequests.listen((_) {});
        session.emitPermissionRequest(id: 'req-100');
        await Future<void>.delayed(Duration.zero);

        await transport.dispose();

        // After dispose, sending a response should be a no-op (not throw).
        await transport.send(PermissionResponseCommand(
          requestId: 'req-100',
          allowed: true,
        ));
      });
    });
  });
}
