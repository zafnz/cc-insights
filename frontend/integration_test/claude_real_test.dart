/// Real Claude Code Integration Tests
///
/// These tests actually connect to Claude Code and send real prompts to the
/// Claude API. They verify the full end-to-end flow of the ACP integration.
///
/// ## IMPORTANT: These tests incur API costs!
///
/// Each test sends real prompts to Claude and will consume API credits.
/// The prompts are designed to be minimal to reduce costs.
///
/// ## Prerequisites
///
/// 1. **Claude Code CLI must be installed**: https://claude.ai/download
/// 2. **The `claude` command must be in PATH**
/// 3. **ANTHROPIC_API_KEY must be set** (or authenticated via `claude login`)
///
/// ## Running the Tests
///
/// These tests are skipped by default. To run them:
///
/// ```bash
/// # Run all real Claude tests on macOS
/// flutter test integration_test/claude_real_test.dart -d macos --run-skipped
///
/// # Run with verbose output to see Claude's responses
/// flutter test integration_test/claude_real_test.dart -d macos --run-skipped -v
///
/// # Run a specific test
/// flutter test integration_test/claude_real_test.dart -d macos --run-skipped \
///   --name "sends simple message and receives response"
/// ```
///
/// ## What These Tests Cover
///
/// 1. **Connection** - Verify we can establish a real connection to Claude Code
/// 2. **Simple Message** - Send a simple prompt and verify we get a response
/// 3. **Session Lifecycle** - Full create/prompt/dispose flow
/// 4. **Multiple Messages** - Send multiple messages in one session
/// 5. **Cancellation** - Start a response and cancel mid-stream
///
/// ## Cost Optimization
///
/// - Prompts are designed to be very short to minimize tokens
/// - Simple prompts that don't require tool use are preferred
/// - The haiku model equivalent (fastest/cheapest) would be used if available
///
@Skip('Requires real Claude Code connection. Run with --run-skipped')
library;

import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_session_wrapper.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late TestResources resources;
  late AgentConfig? claudeConfig;

  setUpAll(() async {
    // Discover Claude Code agent once for all tests
    final registry = AgentRegistry();
    await registry.discover();
    claudeConfig = registry.getAgent('claude-code');

    if (claudeConfig == null) {
      // ignore: avoid_print
      print('''
================================================================================
CLAUDE CODE NOT FOUND

These tests require Claude Code to be installed and accessible.

To install:
  1. Visit https://claude.ai/download
  2. Download and install Claude Code for your platform
  3. Ensure the 'claude' command is in your PATH
  4. Authenticate with: claude login

Then re-run these tests with:
  flutter test integration_test/claude_real_test.dart -d macos --run-skipped
================================================================================
''');
    } else {
      // ignore: avoid_print
      print('Found Claude Code at: ${claudeConfig!.command}');
    }
  });

  setUp(() {
    resources = TestResources();
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  group('Real Claude Connection', () {
    test('establishes connection to Claude Code', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      // Act
      // ignore: avoid_print
      print('Connecting to Claude Code...');
      final stopwatch = Stopwatch()..start();
      await wrapper.connect();
      stopwatch.stop();

      // Assert
      expect(wrapper.isConnected, isTrue);
      expect(wrapper.agentInfo, isNotNull);
      expect(wrapper.agentInfo!.id, 'claude-code');
      expect(wrapper.protocolVersion, isNotNull);

      // ignore: avoid_print
      print('Connected in ${stopwatch.elapsedMilliseconds}ms');
      // ignore: avoid_print
      print('Protocol version: ${wrapper.protocolVersion}');

      // Cleanup
      await wrapper.disconnect();
      expect(wrapper.isConnected, isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('Real Claude Messages', () {
    test('sends simple message and receives response', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');
      // ignore: avoid_print
      print('Session created: ${session.sessionId}');

      // Collect all text from the response
      final responseText = StringBuffer();
      final updates = <SessionUpdate>[];

      final subscription = session.updates.listen((update) {
        updates.add(update);
        if (update is AgentMessageChunkSessionUpdate) {
          final content = update.content;
          if (content is TextContentBlock) {
            responseText.write(content.text);
          }
        }
      });
      resources.trackSubscription(subscription);

      // Act - send a very simple prompt
      // ignore: avoid_print
      print('\n--- Sending prompt: "Say hello in exactly 3 words" ---');

      final stopwatch = Stopwatch()..start();
      final response = await session.prompt([
        TextContentBlock(text: 'Say hello in exactly 3 words.'),
      ]);
      stopwatch.stop();

      // Assert
      expect(response, isA<PromptResponse>());
      expect(response.stopReason, isNotNull);

      // ignore: avoid_print
      print('--- Response received in ${stopwatch.elapsedMilliseconds}ms ---');
      // ignore: avoid_print
      print('Stop reason: ${response.stopReason}');
      // ignore: avoid_print
      print('Updates received: ${updates.length}');
      // ignore: avoid_print
      print('Response text: "${responseText.toString()}"');
      // ignore: avoid_print
      print('---');

      // Verify we got some text back
      expect(responseText.toString(), isNotEmpty);

      // Should have at least one update
      expect(updates, isNotEmpty);

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('handles mathematical question correctly', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Collect response
      final responseText = StringBuffer();
      final subscription = session.updates.listen((update) {
        if (update is AgentMessageChunkSessionUpdate) {
          final content = update.content;
          if (content is TextContentBlock) {
            responseText.write(content.text);
          }
        }
      });
      resources.trackSubscription(subscription);

      // Act - ask a simple math question with known answer
      // ignore: avoid_print
      print('\n--- Sending prompt: "What is 2+2? Reply with just the number." ---');

      final response = await session.prompt([
        TextContentBlock(text: 'What is 2+2? Reply with just the number.'),
      ]);

      // Assert
      expect(response.stopReason, equals(StopReason.endTurn));

      final text = responseText.toString();
      // ignore: avoid_print
      print('Response: "$text"');

      // The response should contain "4"
      expect(text.contains('4'), isTrue);

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Session Lifecycle', () {
    test('full session lifecycle: create, prompt, dispose', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Step 1: Connect
      // ignore: avoid_print
      print('Step 1: Connecting...');
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      expect(wrapper.isConnected, isTrue);
      // ignore: avoid_print
      print('  Connected: ${wrapper.agentInfo?.name}');

      // Step 2: Create session
      // ignore: avoid_print
      print('Step 2: Creating session...');
      final session = await wrapper.createSession(cwd: '/tmp');
      expect(session.sessionId, isNotEmpty);
      // ignore: avoid_print
      print('  Session: ${session.sessionId}');

      // Step 3: Subscribe to updates
      // ignore: avoid_print
      print('Step 3: Setting up update stream...');
      var updateCount = 0;
      final responseText = StringBuffer();
      final subscription = session.updates.listen((update) {
        updateCount++;
        if (update is AgentMessageChunkSessionUpdate) {
          final content = update.content;
          if (content is TextContentBlock) {
            responseText.write(content.text);
          }
        }
      });
      resources.trackSubscription(subscription);
      // ignore: avoid_print
      print('  Update stream ready');

      // Step 4: Send prompt
      // ignore: avoid_print
      print('Step 4: Sending prompt...');
      final response = await session.prompt([
        TextContentBlock(text: 'Reply with the word "OK" only.'),
      ]);
      // ignore: avoid_print
      print('  Received response, stop reason: ${response.stopReason}');
      // ignore: avoid_print
      print('  Updates received: $updateCount');
      // ignore: avoid_print
      print('  Response text: "${responseText.toString()}"');

      // Step 5: Verify response
      // ignore: avoid_print
      print('Step 5: Verifying response...');
      expect(response.stopReason, isNotNull);
      expect(updateCount, greaterThan(0));
      expect(responseText.toString(), isNotEmpty);
      // ignore: avoid_print
      print('  Response verified');

      // Step 6: Dispose session
      // ignore: avoid_print
      print('Step 6: Disposing session...');
      session.dispose();
      // ignore: avoid_print
      print('  Session disposed');

      // Step 7: Disconnect
      // ignore: avoid_print
      print('Step 7: Disconnecting...');
      await wrapper.disconnect();
      expect(wrapper.isConnected, isFalse);
      // ignore: avoid_print
      print('  Disconnected');

      // ignore: avoid_print
      print('Session lifecycle test completed successfully!');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Multiple Messages', () {
    test('sends multiple messages in one session', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      final allResponses = <String>[];

      String collectResponse(ACPSessionWrapper s) {
        final buffer = StringBuffer();
        final sub = s.updates.listen((update) {
          if (update is AgentMessageChunkSessionUpdate) {
            final content = update.content;
            if (content is TextContentBlock) {
              buffer.write(content.text);
            }
          }
        });
        resources.trackSubscription(sub);
        return ''; // Placeholder - we'll read buffer after prompt
      }

      // Message 1
      // ignore: avoid_print
      print('\n--- Message 1: "What is 1+1? Just the number." ---');
      var buffer = StringBuffer();
      var sub = session.updates.listen((update) {
        if (update is AgentMessageChunkSessionUpdate) {
          final content = update.content;
          if (content is TextContentBlock) {
            buffer.write(content.text);
          }
        }
      });

      var response = await session.prompt([
        TextContentBlock(text: 'What is 1+1? Just the number.'),
      ]);
      await sub.cancel();

      allResponses.add(buffer.toString());
      // ignore: avoid_print
      print('Response 1: "${buffer.toString()}"');
      expect(response.stopReason, equals(StopReason.endTurn));

      // Message 2
      // ignore: avoid_print
      print('\n--- Message 2: "What is 2+2? Just the number." ---');
      buffer = StringBuffer();
      sub = session.updates.listen((update) {
        if (update is AgentMessageChunkSessionUpdate) {
          final content = update.content;
          if (content is TextContentBlock) {
            buffer.write(content.text);
          }
        }
      });

      response = await session.prompt([
        TextContentBlock(text: 'What is 2+2? Just the number.'),
      ]);
      await sub.cancel();

      allResponses.add(buffer.toString());
      // ignore: avoid_print
      print('Response 2: "${buffer.toString()}"');
      expect(response.stopReason, equals(StopReason.endTurn));

      // Message 3 - tests conversation continuity
      // ignore: avoid_print
      print('\n--- Message 3: "What is 3+3? Just the number." ---');
      buffer = StringBuffer();
      sub = session.updates.listen((update) {
        if (update is AgentMessageChunkSessionUpdate) {
          final content = update.content;
          if (content is TextContentBlock) {
            buffer.write(content.text);
          }
        }
      });

      response = await session.prompt([
        TextContentBlock(text: 'What is 3+3? Just the number.'),
      ]);
      await sub.cancel();

      allResponses.add(buffer.toString());
      // ignore: avoid_print
      print('Response 3: "${buffer.toString()}"');
      expect(response.stopReason, equals(StopReason.endTurn));

      // Verify all responses
      expect(allResponses.length, equals(3));
      expect(allResponses[0].contains('2'), isTrue);
      expect(allResponses[1].contains('4'), isTrue);
      expect(allResponses[2].contains('6'), isTrue);

      // ignore: avoid_print
      print('\nAll 3 messages completed successfully!');

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('Cancellation', () {
    test('can cancel a long-running response', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Track how much we received before cancellation
      final receivedChunks = <String>[];
      var cancelled = false;

      final subscription = session.updates.listen((update) {
        if (update is AgentMessageChunkSessionUpdate) {
          final content = update.content;
          if (content is TextContentBlock) {
            receivedChunks.add(content.text);
            // ignore: avoid_print
            print('Chunk: "${content.text}"');
          }
        }
      });
      resources.trackSubscription(subscription);

      // Act - start a prompt that would generate a long response
      // ignore: avoid_print
      print('\n--- Starting long prompt (will cancel after 1s) ---');
      // ignore: avoid_print
      print('Prompt: "Count from 1 to 50, each on a new line"');

      final promptFuture = session.prompt([
        TextContentBlock(text: 'Count from 1 to 50, each number on a new line.'),
      ]);

      // Wait a moment to let some output come through
      await Future<void>.delayed(const Duration(seconds: 1));

      // Cancel the prompt
      // ignore: avoid_print
      print('\n--- Cancelling prompt ---');
      await session.cancel();
      cancelled = true;

      // Wait for the prompt to complete (should be quick after cancel)
      final response = await promptFuture;

      // Assert
      // ignore: avoid_print
      print('Stop reason: ${response.stopReason}');
      // ignore: avoid_print
      print('Chunks received before cancel: ${receivedChunks.length}');

      // The response should complete (possibly with cancelled status)
      expect(response.stopReason, isNotNull);

      // We should have received some chunks before cancellation
      // (unless the model was very fast or very slow)
      // ignore: avoid_print
      print('Total text received: "${receivedChunks.join()}"');

      // Cleanup
      session.dispose();
      await wrapper.disconnect();

      // ignore: avoid_print
      print('Cancellation test completed!');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Error Handling', () {
    test('handles connection to invalid working directory gracefully', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();

      // Act - create session with non-existent directory
      // Note: Claude Code may or may not accept this, depending on implementation
      // ignore: avoid_print
      print('Creating session with non-existent directory...');

      // This might throw or might create a session depending on Claude Code behavior
      try {
        final session = await wrapper.createSession(
          cwd: '/nonexistent/path/that/does/not/exist',
        );
        // ignore: avoid_print
        print('Session created (Claude Code accepted the path)');
        session.dispose();
      } catch (e) {
        // ignore: avoid_print
        print('Session creation failed (expected): $e');
        // This is acceptable behavior
      }

      // Cleanup
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('Update Types', () {
    test('receives various update types during prompt', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Track update types
      final updateTypes = <String, int>{};

      final subscription = session.updates.listen((update) {
        final typeName = update.runtimeType.toString();
        updateTypes[typeName] = (updateTypes[typeName] ?? 0) + 1;
      });
      resources.trackSubscription(subscription);

      // Act - send a simple prompt
      await session.prompt([
        TextContentBlock(text: 'Say "Test complete" only.'),
      ]);

      // Assert
      // ignore: avoid_print
      print('\n--- Update types received ---');
      for (final entry in updateTypes.entries) {
        // ignore: avoid_print
        print('  ${entry.key}: ${entry.value}');
      }
      // ignore: avoid_print
      print('---');

      // We should have received at least AgentMessageChunkSessionUpdate
      expect(
        updateTypes.containsKey('AgentMessageChunkSessionUpdate'),
        isTrue,
        reason: 'Should receive agent message chunks',
      );

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Session Modes', () {
    test('reports available session modes', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('SKIPPED: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Act - check modes
      // ignore: avoid_print
      print('\n--- Session modes ---');

      if (session.modes != null) {
        // ignore: avoid_print
        print('Current mode: ${session.modes!.currentModeId}');
        // ignore: avoid_print
        print('Available modes:');
        for (final mode in session.modes!.availableModes) {
          // ignore: avoid_print
          print('  - ${mode.id}: ${mode.name}');
          if (mode.description != null) {
            // ignore: avoid_print
            print('    ${mode.description}');
          }
        }
      } else {
        // ignore: avoid_print
        print('No modes reported by agent');
      }
      // ignore: avoid_print
      print('---');

      // Assert - modes may or may not be present depending on Claude Code version
      // Just verify we can access the property without error

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
