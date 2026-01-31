import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/acp_session_wrapper.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('ACPSessionWrapper', () {
    late TestResources resources;
    late StreamController<SessionNotification> updateController;
    late StreamController<PendingPermission> permissionController;

    /// Creates a minimal RequestPermissionRequest for testing.
    RequestPermissionRequest createTestPermissionRequest(String sessionId) {
      return RequestPermissionRequest(
        sessionId: sessionId,
        options: [
          PermissionOption(
            optionId: 'allow_once',
            name: 'Allow Once',
            kind: PermissionOptionKind.allowOnce,
          ),
        ],
        toolCall: ToolCallUpdate(
          toolCallId: 'test-tool-call-id',
          title: 'Test Tool',
        ),
      );
    }

    /// Creates a SessionNotification with a text content update.
    SessionNotification createTestNotification(String sessionId, String text) {
      return SessionNotification(
        sessionId: sessionId,
        update: AgentMessageChunkSessionUpdate(
          content: TextContentBlock(text: text),
        ),
      );
    }

    /// Creates a PendingPermission for testing.
    PendingPermission createTestPendingPermission(String sessionId) {
      return PendingPermission(
        request: createTestPermissionRequest(sessionId),
        completer: Completer<RequestPermissionResponse>(),
      );
    }

    setUp(() {
      resources = TestResources();
      updateController = resources.trackBroadcastStream<SessionNotification>();
      permissionController = resources.trackBroadcastStream<PendingPermission>();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    test('filters updates by sessionId', () async {
      // Arrange
      final receivedUpdates = <SessionUpdate>[];
      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'session-1',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
      );
      resources.onCleanup(() async => wrapper.dispose());

      final subscription = wrapper.updates.listen((update) {
        receivedUpdates.add(update);
      });
      resources.trackSubscription(subscription);

      // Act - emit updates for both sessions
      updateController.add(createTestNotification('session-1', 'Hello from session 1'));
      updateController.add(createTestNotification('session-2', 'Hello from session 2'));
      updateController.add(createTestNotification('session-1', 'Another from session 1'));

      // Allow async processing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Assert - only session-1 updates should appear
      expect(receivedUpdates.length, 2);
      expect(
        (receivedUpdates[0] as AgentMessageChunkSessionUpdate).content,
        isA<TextContentBlock>().having((b) => b.text, 'text', 'Hello from session 1'),
      );
      expect(
        (receivedUpdates[1] as AgentMessageChunkSessionUpdate).content,
        isA<TextContentBlock>().having((b) => b.text, 'text', 'Another from session 1'),
      );
    });

    test('filters permission requests by sessionId', () async {
      // Arrange
      final receivedPermissions = <PendingPermission>[];
      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'session-1',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
      );
      resources.onCleanup(() async => wrapper.dispose());

      final subscription = wrapper.permissionRequests.listen((permission) {
        receivedPermissions.add(permission);
      });
      resources.trackSubscription(subscription);

      // Act - emit permissions for both sessions
      permissionController.add(createTestPendingPermission('session-1'));
      permissionController.add(createTestPendingPermission('session-2'));
      permissionController.add(createTestPendingPermission('session-1'));

      // Allow async processing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Assert - only session-1 permissions should appear
      expect(receivedPermissions.length, 2);
      expect(receivedPermissions[0].request.sessionId, 'session-1');
      expect(receivedPermissions[1].request.sessionId, 'session-1');
    });

    test('stores sessionId and modes', () {
      // Arrange
      final modes = SessionModeState(
        availableModes: [
          SessionMode(id: 'code', name: 'Code'),
          SessionMode(id: 'architect', name: 'Architect'),
        ],
        currentModeId: 'code',
      );

      // Act
      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'test-session-id',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
        modes: modes,
      );
      resources.onCleanup(() async => wrapper.dispose());

      // Assert
      expect(wrapper.sessionId, 'test-session-id');
      expect(wrapper.modes, isNotNull);
      expect(wrapper.modes!.currentModeId, 'code');
      expect(wrapper.modes!.availableModes.length, 2);
      expect(wrapper.modes!.availableModes[0].id, 'code');
      expect(wrapper.modes!.availableModes[1].id, 'architect');
    });

    test('modes is null when not provided', () {
      // Act
      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'test-session-id',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
      );
      resources.onCleanup(() async => wrapper.dispose());

      // Assert
      expect(wrapper.modes, isNull);
    });

    test('dispose cancels subscriptions and closes streams', () async {
      // Arrange
      var updateStreamDone = false;
      var permissionStreamDone = false;

      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'test-session-id',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
      );

      final updateSubscription = wrapper.updates.listen(
        (_) {},
        onDone: () => updateStreamDone = true,
      );
      final permissionSubscription = wrapper.permissionRequests.listen(
        (_) {},
        onDone: () => permissionStreamDone = true,
      );

      // Act
      wrapper.dispose();

      // Allow async processing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Assert - streams should be closed
      expect(updateStreamDone, isTrue);
      expect(permissionStreamDone, isTrue);

      // Cleanup
      await updateSubscription.cancel();
      await permissionSubscription.cancel();
    });

    test('updates stream is a broadcast stream', () {
      // Arrange
      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'test-session-id',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
      );
      resources.onCleanup(() async => wrapper.dispose());

      // Act - subscribe multiple times (should not throw for broadcast streams)
      final subscription1 = wrapper.updates.listen((_) {});
      final subscription2 = wrapper.updates.listen((_) {});
      resources.trackSubscription(subscription1);
      resources.trackSubscription(subscription2);

      // Assert - both subscriptions should work
      expect(subscription1, isNotNull);
      expect(subscription2, isNotNull);
    });

    test('permissionRequests stream is a broadcast stream', () {
      // Arrange
      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'test-session-id',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
      );
      resources.onCleanup(() async => wrapper.dispose());

      // Act - subscribe multiple times (should not throw for broadcast streams)
      final subscription1 = wrapper.permissionRequests.listen((_) {});
      final subscription2 = wrapper.permissionRequests.listen((_) {});
      resources.trackSubscription(subscription1);
      resources.trackSubscription(subscription2);

      // Assert - both subscriptions should work
      expect(subscription1, isNotNull);
      expect(subscription2, isNotNull);
    });

    test('handles different SessionUpdate types', () async {
      // Arrange
      final receivedUpdates = <SessionUpdate>[];
      final wrapper = ACPSessionWrapper(
        connection: _FakeClientSideConnection(),
        sessionId: 'session-1',
        updates: updateController.stream,
        permissionRequests: permissionController.stream,
      );
      resources.onCleanup(() async => wrapper.dispose());

      final subscription = wrapper.updates.listen((update) {
        receivedUpdates.add(update);
      });
      resources.trackSubscription(subscription);

      // Act - emit different types of updates
      updateController.add(SessionNotification(
        sessionId: 'session-1',
        update: AgentMessageChunkSessionUpdate(
          content: TextContentBlock(text: 'Message'),
        ),
      ));
      updateController.add(SessionNotification(
        sessionId: 'session-1',
        update: ToolCallSessionUpdate(
          toolCallId: 'tool-1',
          title: 'Test Tool',
          status: ToolCallStatus.inProgress,
        ),
      ));
      updateController.add(SessionNotification(
        sessionId: 'session-1',
        update: PlanSessionUpdate(
          entries: [
            PlanEntry(
              content: 'Test task',
              priority: PlanEntryPriority.medium,
              status: PlanEntryStatus.pending,
            ),
          ],
        ),
      ));

      // Allow async processing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Assert
      expect(receivedUpdates.length, 3);
      expect(receivedUpdates[0], isA<AgentMessageChunkSessionUpdate>());
      expect(receivedUpdates[1], isA<ToolCallSessionUpdate>());
      expect(receivedUpdates[2], isA<PlanSessionUpdate>());
    });

    // Note: prompt(), cancel(), setMode() require a real connection.
    // These tests are marked as skipped since they would require integration testing.

    group('prompt(), cancel(), setMode() - integration tests', () {
      test(
        'prompt() sends PromptRequest to connection',
        skip: 'Requires real ClientSideConnection',
        () async {
          // This test would:
          // 1. Create a wrapper with a mock/spy connection
          // 2. Call prompt() with content
          // 3. Verify PromptRequest was sent with correct sessionId
        },
      );

      test(
        'cancel() sends CancelNotification to connection',
        skip: 'Requires real ClientSideConnection',
        () async {
          // This test would:
          // 1. Create a wrapper with a mock/spy connection
          // 2. Call cancel()
          // 3. Verify CancelNotification was sent with correct sessionId
        },
      );

      test(
        'setMode() sends SetSessionModeRequest to connection',
        skip: 'Requires real ClientSideConnection',
        () async {
          // This test would:
          // 1. Create a wrapper with a mock/spy connection
          // 2. Call setMode('architect')
          // 3. Verify SetSessionModeRequest was sent with correct sessionId and modeId
        },
      );
    });
  });
}

/// Fake implementation of ClientSideConnection for testing.
///
/// This fake uses `noSuchMethod` to satisfy the interface without
/// implementing all required methods. Methods that are actually used
/// in the tests throw UnimplementedError when called.
class _FakeClientSideConnection implements ClientSideConnection {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Provide default implementation for methods not explicitly overridden.
    // This will throw a more helpful error message if called.
    throw UnimplementedError(
      '_FakeClientSideConnection.${invocation.memberName} is not implemented',
    );
  }
}
