import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/services/agent_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('AgentService', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    test('starts in disconnected state', () {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      expect(service.isConnected, isFalse);
      expect(service.currentAgent, isNull);
      expect(service.capabilities, isNull);
    });

    test('createSession throws when not connected', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      expect(
        () => service.createSession(cwd: '/tmp'),
        throwsA(isA<StateError>()),
      );
    });

    test('disconnect is safe when not connected', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      await expectLater(service.disconnect(), completes);
      expect(service.isConnected, isFalse);
    });

    test('stores agentRegistry reference', () {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      expect(service.agentRegistry, same(registry));
    });

    test('notifies listeners on disconnect', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      var notified = false;
      service.addListener(() => notified = true);

      await service.disconnect();

      expect(notified, isTrue);
    });

    test('agentInfo is null when not connected', () {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      expect(service.agentInfo, isNull);
    });

    test('updates stream is null when not connected', () {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      expect(service.updates, isNull);
    });

    test('permissionRequests stream is null when not connected', () {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      expect(service.permissionRequests, isNull);
    });

    test('currentAgent remains null after disconnect', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      await service.disconnect();

      expect(service.currentAgent, isNull);
    });

    test('multiple disconnects are safe', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      await service.disconnect();
      await service.disconnect();
      await service.disconnect();

      expect(service.isConnected, isFalse);
    });

    // Integration tests that require real agent connection can be skipped
    test('connect establishes connection', () async {
      // Skip: Requires real ACP agent
    }, skip: 'Requires real ACP agent');

    test('createSession returns wrapper when connected', () async {
      // Skip: Requires real ACP agent
    }, skip: 'Requires real ACP agent');

    test('disconnect clears connection after connect', () async {
      // Skip: Requires real ACP agent
    }, skip: 'Requires real ACP agent');
  });
}
