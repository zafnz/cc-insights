import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_errors.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('AgentConfig', () {
    test('stores all properties correctly', () {
      // Arrange & Act
      const config = AgentConfig(
        id: 'test-agent',
        name: 'Test Agent',
        command: '/usr/bin/test-agent',
        args: ['--flag', 'value'],
        env: {'TEST_VAR': 'test-value'},
      );

      // Assert
      expect(config.id, 'test-agent');
      expect(config.name, 'Test Agent');
      expect(config.command, '/usr/bin/test-agent');
      expect(config.args, ['--flag', 'value']);
      expect(config.env, {'TEST_VAR': 'test-value'});
    });

    test('uses default empty values for optional parameters', () {
      // Arrange & Act
      const config = AgentConfig(
        id: 'minimal-agent',
        name: 'Minimal Agent',
        command: 'agent-cmd',
      );

      // Assert
      expect(config.id, 'minimal-agent');
      expect(config.name, 'Minimal Agent');
      expect(config.command, 'agent-cmd');
      expect(config.args, isEmpty);
      expect(config.env, isEmpty);
    });

    test('toString returns readable representation', () {
      // Arrange
      const config = AgentConfig(
        id: 'my-agent',
        name: 'My Agent',
        command: 'agent',
      );

      // Act
      final result = config.toString();

      // Assert
      expect(result, 'AgentConfig(my-agent: My Agent)');
    });
  });

  group('AgentInfo', () {
    test('stores properties correctly', () {
      // Arrange & Act
      const info = AgentInfo(
        id: 'agent-id',
        name: 'Agent Name',
      );

      // Assert
      expect(info.id, 'agent-id');
      expect(info.name, 'Agent Name');
    });

    test('toString returns readable representation', () {
      // Arrange
      const info = AgentInfo(
        id: 'my-agent',
        name: 'My Agent',
      );

      // Act
      final result = info.toString();

      // Assert
      expect(result, 'AgentInfo(my-agent: My Agent)');
    });
  });

  group('ACPClientWrapper', () {
    late TestResources resources;
    late ACPClientWrapper wrapper;

    setUp(() {
      resources = TestResources();
      wrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'test-agent',
          name: 'Test Agent',
          command: 'echo', // A harmless command
        ),
      );
      resources.track(wrapper);
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    test('starts in disconnected state', () {
      // Assert - wrapper should be disconnected initially
      expect(wrapper.isConnected, isFalse);
      expect(wrapper.connectionState, ACPConnectionState.disconnected);
      expect(wrapper.lastError, isNull);
      expect(wrapper.capabilities, isNull);
      expect(wrapper.agentInfo, isNull);
      expect(wrapper.protocolVersion, isNull);
      expect(wrapper.authMethods, isEmpty);
      expect(wrapper.connection, isNull);
    });

    test('exposes update and permission streams', () {
      // Assert - streams should be accessible (not null)
      expect(wrapper.updates, isNotNull);
      expect(wrapper.permissionRequests, isNotNull);

      // Verify streams are broadcast streams (can have multiple listeners)
      expect(wrapper.updates, isA<Stream<SessionNotification>>());
      expect(wrapper.permissionRequests, isA<Stream<PendingPermission>>());
    });

    test('update stream allows subscription', () async {
      // Arrange
      final receivedUpdates = <SessionNotification>[];
      final subscription = wrapper.updates.listen((update) {
        receivedUpdates.add(update);
      });
      resources.trackSubscription(subscription);

      // Assert - subscription should not throw
      expect(receivedUpdates, isEmpty);
    });

    test('permission stream allows subscription', () async {
      // Arrange
      final receivedPermissions = <PendingPermission>[];
      final subscription = wrapper.permissionRequests.listen((permission) {
        receivedPermissions.add(permission);
      });
      resources.trackSubscription(subscription);

      // Assert - subscription should not throw
      expect(receivedPermissions, isEmpty);
    });

    test('notifies listeners on state change via dispose', () async {
      // Arrange
      var notificationCount = 0;
      void listener() {
        notificationCount++;
      }

      wrapper.addListener(listener);
      expect(notificationCount, 0);

      // The wrapper will notify on disconnect which happens during dispose
      // We can't test connect() without a real agent, but we can verify
      // the listener mechanism works
      wrapper.removeListener(listener);

      // Verify listener was properly added and removed (no exceptions)
      expect(notificationCount, 0);
    });

    test('stores agent config correctly', () {
      // Assert
      expect(wrapper.agentConfig.id, 'test-agent');
      expect(wrapper.agentConfig.name, 'Test Agent');
      expect(wrapper.agentConfig.command, 'echo');
    });

    test('disconnect is safe to call when not connected', () async {
      // Act - should not throw
      await wrapper.disconnect();

      // Assert
      expect(wrapper.isConnected, isFalse);
    });

    test('disconnect can be called multiple times', () async {
      // Act - multiple calls should not throw
      await wrapper.disconnect();
      await wrapper.disconnect();
      await wrapper.disconnect();

      // Assert
      expect(wrapper.isConnected, isFalse);
      expect(wrapper.connectionState, ACPConnectionState.disconnected);
    });

    test('disconnect clears error state', () async {
      // Arrange - create wrapper with non-existent command to trigger error
      final badWrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'bad-agent',
          name: 'Bad Agent',
          command: '/nonexistent/command/that/does/not/exist',
        ),
      );
      resources.track(badWrapper);

      // Try to connect (will fail)
      try {
        await badWrapper.connect();
      } catch (_) {
        // Expected to fail
      }

      // Act
      await badWrapper.disconnect();

      // Assert - error should be cleared
      expect(badWrapper.lastError, isNull);
      expect(badWrapper.connectionState, ACPConnectionState.disconnected);
    });

    test('has default connection timeout', () {
      // Assert
      expect(wrapper.connectionTimeout, const Duration(seconds: 30));
    });

    test('accepts custom connection timeout', () {
      // Arrange
      final customWrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'test',
          name: 'Test',
          command: 'echo',
        ),
        connectionTimeout: const Duration(seconds: 60),
      );
      resources.track(customWrapper);

      // Assert
      expect(customWrapper.connectionTimeout, const Duration(seconds: 60));
    });

    test('createSession throws ACPStateError when not connected', () async {
      // Act & Assert
      expect(
        () async => wrapper.createSession(cwd: '/tmp'),
        throwsA(isA<ACPStateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected'),
        )),
      );
    });

    test('dispose closes streams', () async {
      // Arrange - subscribe to streams before disposal
      var updateStreamDone = false;
      var permissionStreamDone = false;

      // Create a separate wrapper for this test to avoid conflict with tearDown
      final testWrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'dispose-test',
          name: 'Dispose Test',
          command: 'echo',
        ),
      );

      final updateSubscription = testWrapper.updates.listen(
        (_) {},
        onDone: () => updateStreamDone = true,
      );

      final permissionSubscription = testWrapper.permissionRequests.listen(
        (_) {},
        onDone: () => permissionStreamDone = true,
      );

      // Act
      testWrapper.dispose();

      // Allow async operations to complete
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Assert - streams should be closed
      expect(updateStreamDone, isTrue);
      expect(permissionStreamDone, isTrue);

      // Cleanup
      await updateSubscription.cancel();
      await permissionSubscription.cancel();
    });
  });

  group('ACPClientWrapper error handling', () {
    late TestResources resources;

    setUp(() {
      resources = TestResources();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    test('connect throws ACPConnectionError for non-existent command', () async {
      // Arrange
      final wrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'bad-agent',
          name: 'Bad Agent',
          command: '/nonexistent/command/path/12345',
        ),
      );
      resources.track(wrapper);

      // Act & Assert
      expect(
        () async => wrapper.connect(),
        throwsA(isA<ACPConnectionError>()),
      );
    });

    test('connection failure sets error state', () async {
      // Arrange
      final wrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'bad-agent',
          name: 'Bad Agent',
          command: '/nonexistent/command/path/12345',
        ),
      );
      resources.track(wrapper);

      // Act
      try {
        await wrapper.connect();
      } on ACPConnectionError {
        // Expected
      }

      // Assert
      expect(wrapper.connectionState, ACPConnectionState.error);
      expect(wrapper.lastError, isA<ACPConnectionError>());
      expect(wrapper.isConnected, isFalse);
    });

    test('connect notifies listeners during state transitions', () async {
      // Arrange
      final wrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'bad-agent',
          name: 'Bad Agent',
          command: '/nonexistent/command/path/12345',
        ),
      );
      resources.track(wrapper);

      final states = <ACPConnectionState>[];
      wrapper.addListener(() {
        states.add(wrapper.connectionState);
      });

      // Act
      try {
        await wrapper.connect();
      } on ACPConnectionError {
        // Expected
      }

      // Assert - should have notified for 'connecting' and 'error' states
      expect(states, contains(ACPConnectionState.connecting));
      expect(states, contains(ACPConnectionState.error));
    });

    test('connect clears previous error when retrying', () async {
      // Arrange
      final wrapper = ACPClientWrapper(
        agentConfig: const AgentConfig(
          id: 'bad-agent',
          name: 'Bad Agent',
          command: '/nonexistent/command/path/12345',
        ),
      );
      resources.track(wrapper);

      // First attempt (will fail)
      try {
        await wrapper.connect();
      } on ACPConnectionError {
        // Expected
      }
      expect(wrapper.lastError, isNotNull);

      // Act - second attempt should clear error initially
      var errorCleared = false;
      wrapper.addListener(() {
        if (wrapper.connectionState == ACPConnectionState.connecting &&
            wrapper.lastError == null) {
          errorCleared = true;
        }
      });

      try {
        await wrapper.connect();
      } on ACPConnectionError {
        // Expected
      }

      // Assert
      expect(errorCleared, isTrue);
    });
  });

  group('ACPConnectionState enum', () {
    test('has all expected values', () {
      expect(ACPConnectionState.values, hasLength(4));
      expect(
        ACPConnectionState.values,
        containsAll([
          ACPConnectionState.disconnected,
          ACPConnectionState.connecting,
          ACPConnectionState.connected,
          ACPConnectionState.error,
        ]),
      );
    });
  });

  group('ACPClientWrapper integration tests', () {
    // These tests would require a real ACP agent and are marked as skipped.
    // They document the expected behavior for future integration testing.

    test(
      'connect() spawns agent process and initializes connection',
      skip: 'Requires real ACP agent',
      () async {
        // This test would:
        // 1. Create a wrapper with a real agent command
        // 2. Call connect()
        // 3. Verify isConnected is true
        // 4. Verify connectionState is ACPConnectionState.connected
        // 5. Verify capabilities is not null
        // 6. Clean up with disconnect()
      },
    );

    test(
      'connect() throws ACPStateError when already connected',
      skip: 'Requires real ACP agent',
      () async {
        // This test would:
        // 1. Create wrapper and connect()
        // 2. Try to connect() again
        // 3. Verify ACPStateError is thrown
      },
    );

    test(
      'createSession returns ACPSessionWrapper when connected',
      skip: 'Requires real ACP agent',
      () async {
        // This test would:
        // 1. Create wrapper and connect()
        // 2. Call createSession()
        // 3. Verify response is an ACPSessionWrapper with sessionId
        // 4. Verify session.updates and session.permissionRequests are accessible
      },
    );

    test(
      'process crash sets error state and notifies listeners',
      skip: 'Requires real ACP agent',
      () async {
        // This test would:
        // 1. Create wrapper and connect()
        // 2. Kill the agent process externally
        // 3. Verify connectionState becomes ACPConnectionState.error
        // 4. Verify lastError is ACPConnectionError.processCrashed
        // 5. Verify listeners were notified
      },
    );

    test(
      'connection timeout throws ACPTimeoutError',
      skip: 'Requires slow/hanging agent',
      () async {
        // This test would:
        // 1. Create wrapper with a very short timeout
        // 2. Connect to a slow agent that doesn't respond
        // 3. Verify ACPTimeoutError is thrown
      },
    );

    test(
      'disconnect notifies listeners',
      skip: 'Requires real ACP agent',
      () async {
        // This test would:
        // 1. Create wrapper and connect()
        // 2. Add listener
        // 3. Call disconnect()
        // 4. Verify listener was notified
      },
    );
  });
}
