import 'dart:async';

import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

/// Tests for Codex config/warning notification handling.
void main() {
  group('CodexSession config/warning handling', () {
    late CodexSession session;
    late List<InsightsEvent> capturedEvents;
    late StreamSubscription<InsightsEvent> eventSub;

    setUp(() {
      session = CodexSession.forTesting(threadId: 'test-thread');
      capturedEvents = [];
      eventSub = session.events.listen((event) => capturedEvents.add(event));
    });

    tearDown(() async {
      await eventSub.cancel();
      await session.kill();
    });

    /// Helper to wait for events to be processed
    Future<void> waitForEvents() async {
      await Future.delayed(Duration(milliseconds: 10));
    }

    test('emits TextEvent with error kind on config/warning', () async {
      session.injectNotification(JsonRpcNotification(
        method: 'config/warning',
        params: {
          'summary': 'Sandbox mode read-only is required by policy',
          'details': {
            'requestedMode': 'workspace-write',
            'effectiveMode': 'read-only',
          },
        },
      ));

      await waitForEvents();

      expect(capturedEvents, hasLength(1));
      final event = capturedEvents.first as TextEvent;
      expect(event.provider, BackendProvider.codex);
      expect(event.sessionId, 'test-thread');
      expect(event.kind, TextKind.error);
      expect(event.text, 'Sandbox mode read-only is required by policy');
      expect(event.id.startsWith('evt-codex-'), isTrue);
      expect(event.raw, isNotNull);
    });

    test('handles config/warning with empty summary', () async {
      session.injectNotification(JsonRpcNotification(
        method: 'config/warning',
        params: {},
      ));

      await waitForEvents();

      expect(capturedEvents, hasLength(1));
      final event = capturedEvents.first as TextEvent;
      expect(event.text, '');
      expect(event.kind, TextKind.error);
    });

    test('handles config/warning with null summary', () async {
      session.injectNotification(JsonRpcNotification(
        method: 'config/warning',
        params: {
          'summary': null,
        },
      ));

      await waitForEvents();

      expect(capturedEvents, hasLength(1));
      final event = capturedEvents.first as TextEvent;
      expect(event.text, '');
      expect(event.kind, TextKind.error);
    });
  });
}
