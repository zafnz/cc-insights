import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_errors.dart';
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
      expect(service.connectionState, ACPConnectionState.disconnected);
      expect(service.lastError, isNull);
      expect(service.currentAgent, isNull);
      expect(service.capabilities, isNull);
    });

    test('createSession throws ACPStateError when not connected', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      expect(
        () => service.createSession(cwd: '/tmp'),
        throwsA(isA<ACPStateError>()),
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

  group('AgentService error handling', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    test('connect throws ACPConnectionError for invalid command', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      const badConfig = AgentConfig(
        id: 'bad-agent',
        name: 'Bad Agent',
        command: '/nonexistent/command/path/12345',
      );

      expect(
        () => service.connect(badConfig),
        throwsA(isA<ACPConnectionError>()),
      );
    });

    test('connection failure exposes error through lastError', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      const badConfig = AgentConfig(
        id: 'bad-agent',
        name: 'Bad Agent',
        command: '/nonexistent/command/path/12345',
      );

      try {
        await service.connect(badConfig);
      } on ACPConnectionError {
        // Expected
      }

      expect(service.lastError, isA<ACPConnectionError>());
      expect(service.connectionState, ACPConnectionState.error);
    });

    test('connection failure notifies listeners', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      var notificationCount = 0;
      service.addListener(() => notificationCount++);

      const badConfig = AgentConfig(
        id: 'bad-agent',
        name: 'Bad Agent',
        command: '/nonexistent/command/path/12345',
      );

      try {
        await service.connect(badConfig);
      } on ACPConnectionError {
        // Expected
      }

      // Should notify for state changes (connecting, error)
      expect(notificationCount, greaterThanOrEqualTo(1));
    });

    test('reconnect returns false when no previous agent', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      final result = await service.reconnect();

      expect(result, isFalse);
    });

    test('reconnect attempts with previous agent config', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      const badConfig = AgentConfig(
        id: 'bad-agent',
        name: 'Bad Agent',
        command: '/nonexistent/command/path/12345',
      );

      // First connection attempt (will fail)
      try {
        await service.connect(badConfig);
      } on ACPConnectionError {
        // Expected
      }

      // Reconnect should attempt with same config
      expect(
        () => service.reconnect(),
        throwsA(isA<ACPConnectionError>()),
      );
    });

    test('disconnect clears error state', () async {
      final registry = resources.track(AgentRegistry());
      final service = resources.track(AgentService(agentRegistry: registry));

      const badConfig = AgentConfig(
        id: 'bad-agent',
        name: 'Bad Agent',
        command: '/nonexistent/command/path/12345',
      );

      try {
        await service.connect(badConfig);
      } on ACPConnectionError {
        // Expected
      }

      expect(service.lastError, isNotNull);

      await service.disconnect();

      // After disconnect, client is null so lastError is null
      expect(service.lastError, isNull);
      expect(service.connectionState, ACPConnectionState.disconnected);
    });
  });
}
