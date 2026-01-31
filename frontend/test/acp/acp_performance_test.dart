import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_session_wrapper.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:cc_insights_v2/acp/session_update_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('ACP Performance Tests', () {
    group('Rapid Update Handling', () {
      late TestResources resources;
      late StreamController<SessionNotification> updateController;
      late StreamController<PendingPermission> permissionController;

      setUp(() {
        resources = TestResources();
        updateController =
            resources.trackBroadcastStream<SessionNotification>();
        permissionController =
            resources.trackBroadcastStream<PendingPermission>();
      });

      tearDown(() async {
        await resources.disposeAll();
      });

      test('handles 1000 rapid updates without dropping any', () async {
        // Arrange
        const updateCount = 1000;
        final receivedUpdates = <SessionUpdate>[];
        final wrapper = ACPSessionWrapper(
          connection: _FakeClientSideConnection(),
          sessionId: 'perf-session',
          updates: updateController.stream,
          permissionRequests: permissionController.stream,
        );
        resources.onCleanup(() async => wrapper.dispose());

        final subscription = wrapper.updates.listen((update) {
          receivedUpdates.add(update);
        });
        resources.trackSubscription(subscription);

        // Act - emit many updates rapidly without awaiting between them
        for (var i = 0; i < updateCount; i++) {
          updateController.add(SessionNotification(
            sessionId: 'perf-session',
            update: AgentMessageChunkSessionUpdate(
              content: TextContentBlock(text: 'Message $i'),
            ),
          ));
        }

        // Allow async processing with generous time
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Assert - all updates should be received
        expect(
          receivedUpdates.length,
          updateCount,
          reason: 'All updates should be received without dropping',
        );
      });

      test('filters updates efficiently under load', () async {
        // Arrange - test that filtering doesn't cause issues under load
        const updatesPerSession = 500;
        final session1Updates = <SessionUpdate>[];
        final session2Updates = <SessionUpdate>[];

        final wrapper1 = ACPSessionWrapper(
          connection: _FakeClientSideConnection(),
          sessionId: 'session-1',
          updates: updateController.stream,
          permissionRequests: permissionController.stream,
        );
        resources.onCleanup(() async => wrapper1.dispose());

        final wrapper2 = ACPSessionWrapper(
          connection: _FakeClientSideConnection(),
          sessionId: 'session-2',
          updates: updateController.stream,
          permissionRequests: permissionController.stream,
        );
        resources.onCleanup(() async => wrapper2.dispose());

        final sub1 = wrapper1.updates.listen((u) => session1Updates.add(u));
        final sub2 = wrapper2.updates.listen((u) => session2Updates.add(u));
        resources.trackSubscription(sub1);
        resources.trackSubscription(sub2);

        // Act - interleave updates for both sessions
        for (var i = 0; i < updatesPerSession; i++) {
          updateController.add(SessionNotification(
            sessionId: 'session-1',
            update: AgentMessageChunkSessionUpdate(
              content: TextContentBlock(text: 'S1-$i'),
            ),
          ));
          updateController.add(SessionNotification(
            sessionId: 'session-2',
            update: AgentMessageChunkSessionUpdate(
              content: TextContentBlock(text: 'S2-$i'),
            ),
          ));
        }

        // Allow async processing
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Assert - each session should only receive its own updates
        expect(
          session1Updates.length,
          updatesPerSession,
          reason: 'Session 1 should receive exactly its updates',
        );
        expect(
          session2Updates.length,
          updatesPerSession,
          reason: 'Session 2 should receive exactly its updates',
        );

        // Verify content is correct
        for (var i = 0; i < updatesPerSession; i++) {
          final update = session1Updates[i] as AgentMessageChunkSessionUpdate;
          final text = (update.content as TextContentBlock).text;
          expect(text, 'S1-$i');
        }
      });

      test('multiple subscribers receive all updates', () async {
        // Arrange
        const updateCount = 100;
        final subscriber1Updates = <SessionUpdate>[];
        final subscriber2Updates = <SessionUpdate>[];
        final subscriber3Updates = <SessionUpdate>[];

        final wrapper = ACPSessionWrapper(
          connection: _FakeClientSideConnection(),
          sessionId: 'multi-sub-session',
          updates: updateController.stream,
          permissionRequests: permissionController.stream,
        );
        resources.onCleanup(() async => wrapper.dispose());

        final sub1 = wrapper.updates.listen((u) => subscriber1Updates.add(u));
        final sub2 = wrapper.updates.listen((u) => subscriber2Updates.add(u));
        final sub3 = wrapper.updates.listen((u) => subscriber3Updates.add(u));
        resources.trackSubscription(sub1);
        resources.trackSubscription(sub2);
        resources.trackSubscription(sub3);

        // Act
        for (var i = 0; i < updateCount; i++) {
          updateController.add(SessionNotification(
            sessionId: 'multi-sub-session',
            update: ToolCallSessionUpdate(
              toolCallId: 'tc-$i',
              title: 'Tool $i',
              status: ToolCallStatus.pending,
            ),
          ));
        }

        // Allow async processing
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Assert - all subscribers should receive all updates
        expect(subscriber1Updates.length, updateCount);
        expect(subscriber2Updates.length, updateCount);
        expect(subscriber3Updates.length, updateCount);
      });
    });

    group('SessionUpdateHandler Performance', () {
      test('handles 1000 rapid updates efficiently', () async {
        // Arrange
        const updateCount = 1000;
        var messageCount = 0;
        var toolCallCount = 0;
        var toolCallUpdateCount = 0;

        final handler = SessionUpdateHandler(
          onAgentMessage: (_) => messageCount++,
          onToolCall: (_) => toolCallCount++,
          onToolCallUpdate: (_) => toolCallUpdateCount++,
        );

        final stopwatch = Stopwatch()..start();

        // Act - process many updates
        for (var i = 0; i < updateCount; i++) {
          // Mix of different update types
          if (i % 3 == 0) {
            handler.handleUpdate(AgentMessageChunkSessionUpdate(
              content: TextContentBlock(text: 'Message $i'),
            ));
          } else if (i % 3 == 1) {
            handler.handleUpdate(ToolCallSessionUpdate(
              toolCallId: 'tc-$i',
              title: 'Tool $i',
              status: ToolCallStatus.pending,
            ));
          } else {
            handler.handleUpdate(ToolCallUpdateSessionUpdate(
              toolCallId: 'tc-$i',
              status: ToolCallStatus.completed,
            ));
          }
        }

        stopwatch.stop();

        // Assert
        expect(messageCount, updateCount ~/ 3 + 1);
        expect(toolCallCount, updateCount ~/ 3);
        expect(toolCallUpdateCount, updateCount ~/ 3);

        // Processing should be fast (synchronous operations)
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(100),
          reason: 'Processing 1000 updates should take less than 100ms',
        );
      });

      test('tool call conversation mapping does not grow unbounded', () {
        // Arrange
        final handler = SessionUpdateHandler();

        // Act - register many mappings
        for (var i = 0; i < 1000; i++) {
          handler.registerToolCallConversation('tc-$i', 'conv-$i');
        }

        // Simulate cleanup of old mappings (as would happen in real usage)
        for (var i = 0; i < 500; i++) {
          handler.unregisterToolCallConversation('tc-$i');
        }

        // Assert - only 500 mappings remain
        var remainingCount = 0;
        for (var i = 0; i < 1000; i++) {
          if (handler.getConversationForToolCall('tc-$i') != null) {
            remainingCount++;
          }
        }
        expect(remainingCount, 500);

        // Clear all should work
        handler.clearConversationMappings();
        for (var i = 500; i < 1000; i++) {
          expect(handler.getConversationForToolCall('tc-$i'), isNull);
        }
      });
    });

    group('ACPClientWrapper Stream Cleanup', () {
      late TestResources resources;

      setUp(() {
        resources = TestResources();
      });

      tearDown(() async {
        await resources.disposeAll();
      });

      test('streams are properly closed on dispose', () async {
        // Arrange
        final wrapper = ACPClientWrapper(
          agentConfig: const AgentConfig(
            id: 'test',
            name: 'Test',
            command: 'echo',
          ),
        );

        var updatesDone = false;
        var permissionsDone = false;

        final updateSub = wrapper.updates.listen(
          (_) {},
          onDone: () => updatesDone = true,
        );
        final permSub = wrapper.permissionRequests.listen(
          (_) {},
          onDone: () => permissionsDone = true,
        );

        // Act
        wrapper.dispose();

        // Allow async processing
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Assert
        expect(updatesDone, isTrue, reason: 'Updates stream should be closed');
        expect(
          permissionsDone,
          isTrue,
          reason: 'Permissions stream should be closed',
        );

        // Cleanup
        await updateSub.cancel();
        await permSub.cancel();
      });

      test('disconnect is idempotent', () async {
        // Arrange
        final wrapper = ACPClientWrapper(
          agentConfig: const AgentConfig(
            id: 'test',
            name: 'Test',
            command: 'echo',
          ),
        );
        resources.track(wrapper);

        // Act - call disconnect multiple times rapidly
        final futures = <Future<void>>[];
        for (var i = 0; i < 10; i++) {
          futures.add(wrapper.disconnect());
        }

        // Should not throw
        await Future.wait(futures);

        // Assert
        expect(wrapper.connectionState, ACPConnectionState.disconnected);
      });
    });

    group('Memory Efficiency', () {
      test('session wrapper can be created and disposed repeatedly', () async {
        // This test verifies no memory leaks from repeated create/dispose cycles
        final resources = TestResources();
        final updateController =
            resources.trackBroadcastStream<SessionNotification>();
        final permissionController =
            resources.trackBroadcastStream<PendingPermission>();

        // Create and dispose many wrappers
        for (var i = 0; i < 100; i++) {
          final wrapper = ACPSessionWrapper(
            connection: _FakeClientSideConnection(),
            sessionId: 'session-$i',
            updates: updateController.stream,
            permissionRequests: permissionController.stream,
          );

          // Subscribe and receive some updates
          final updates = <SessionUpdate>[];
          final sub = wrapper.updates.listen((u) => updates.add(u));

          updateController.add(SessionNotification(
            sessionId: 'session-$i',
            update: AgentMessageChunkSessionUpdate(
              content: TextContentBlock(text: 'Test $i'),
            ),
          ));

          await Future<void>.delayed(const Duration(milliseconds: 1));
          expect(updates.length, 1);

          await sub.cancel();
          wrapper.dispose();
        }

        await resources.disposeAll();

        // If we get here without memory issues, test passes
        expect(true, isTrue);
      });

      test('update handler can process updates indefinitely', () {
        // Verify that the update handler doesn't accumulate state
        final handler = SessionUpdateHandler(
          onAgentMessage: (_) {},
          onToolCall: (_) {},
          onToolCallUpdate: (_) {},
        );

        // Process many updates - should not accumulate memory
        for (var i = 0; i < 10000; i++) {
          handler.handleUpdate(AgentMessageChunkSessionUpdate(
            content: TextContentBlock(text: 'Message $i'),
          ));
        }

        // The handler should not have accumulated any state
        // (it only stores tool call conversation mappings when explicitly registered)
        expect(handler.getConversationForToolCall('any'), isNull);
      });
    });

    group('Stress Tests', () {
      test('handles burst of mixed update types', () async {
        // Arrange
        final resources = TestResources();
        final updateController =
            resources.trackBroadcastStream<SessionNotification>();
        final permissionController =
            resources.trackBroadcastStream<PendingPermission>();

        final wrapper = ACPSessionWrapper(
          connection: _FakeClientSideConnection(),
          sessionId: 'stress-test',
          updates: updateController.stream,
          permissionRequests: permissionController.stream,
        );
        resources.onCleanup(() async => wrapper.dispose());

        final allUpdates = <SessionUpdate>[];
        final sub = wrapper.updates.listen((u) => allUpdates.add(u));
        resources.trackSubscription(sub);

        // Act - emit burst of mixed updates
        const burstSize = 500;
        for (var i = 0; i < burstSize; i++) {
          // Rotate through different update types
          final updateType = i % 6;
          late SessionUpdate update;

          switch (updateType) {
            case 0:
              update = AgentMessageChunkSessionUpdate(
                content: TextContentBlock(text: 'Msg $i'),
              );
            case 1:
              update = AgentThoughtChunkSessionUpdate(
                content: TextContentBlock(text: 'Think $i'),
              );
            case 2:
              update = ToolCallSessionUpdate(
                toolCallId: 'tc-$i',
                title: 'Tool $i',
                status: ToolCallStatus.pending,
              );
            case 3:
              update = ToolCallUpdateSessionUpdate(
                toolCallId: 'tc-$i',
                status: ToolCallStatus.completed,
              );
            case 4:
              update = PlanSessionUpdate(entries: [
                PlanEntry(
                  content: 'Task $i',
                  priority: PlanEntryPriority.medium,
                  status: PlanEntryStatus.pending,
                ),
              ]);
            case 5:
              update = CurrentModeUpdateSessionUpdate(
                currentModeId: 'mode-$i',
              );
          }

          updateController.add(SessionNotification(
            sessionId: 'stress-test',
            update: update,
          ));
        }

        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Assert
        expect(
          allUpdates.length,
          burstSize,
          reason: 'All updates should be received',
        );

        await resources.disposeAll();
      });

      test('subscription cancellation during active stream', () async {
        // Test that cancelling a subscription during active streaming is safe
        final resources = TestResources();
        final updateController =
            resources.trackBroadcastStream<SessionNotification>();
        final permissionController =
            resources.trackBroadcastStream<PendingPermission>();

        final wrapper = ACPSessionWrapper(
          connection: _FakeClientSideConnection(),
          sessionId: 'cancel-test',
          updates: updateController.stream,
          permissionRequests: permissionController.stream,
        );
        resources.onCleanup(() async => wrapper.dispose());

        final updates = <SessionUpdate>[];
        final sub = wrapper.updates.listen((u) => updates.add(u));

        // Start emitting updates
        for (var i = 0; i < 50; i++) {
          updateController.add(SessionNotification(
            sessionId: 'cancel-test',
            update: AgentMessageChunkSessionUpdate(
              content: TextContentBlock(text: 'Pre-cancel $i'),
            ),
          ));
        }

        // Cancel subscription mid-stream
        await sub.cancel();

        // Continue emitting (should not throw)
        for (var i = 0; i < 50; i++) {
          updateController.add(SessionNotification(
            sessionId: 'cancel-test',
            update: AgentMessageChunkSessionUpdate(
              content: TextContentBlock(text: 'Post-cancel $i'),
            ),
          ));
        }

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Updates received should be <= 50 (pre-cancel only)
        expect(updates.length, lessThanOrEqualTo(50));

        await resources.disposeAll();
      });
    });
  });
}

/// Fake implementation of ClientSideConnection for testing.
class _FakeClientSideConnection implements ClientSideConnection {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeClientSideConnection.${invocation.memberName} is not implemented',
    );
  }
}
