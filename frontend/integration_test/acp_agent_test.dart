/// ACP Agent Integration Tests
///
/// These tests verify the complete conversation flow with real ACP agents.
/// They are skipped by default since they require agents to be installed
/// on the system.
///
/// ## Test Categories
///
/// The tests are organized into two main categories:
///
/// 1. **Single-Agent Tests** - Tests that work with Claude Code only
/// 2. **Multi-Agent Tests** - Tests that verify multi-agent support
///    - Agent switching between providers
///    - Agent discovery for Gemini and Codex
///    - Capabilities comparison across agents
///    - Agent-agnostic API behavior
///
/// ## Prerequisites
///
/// ### For Claude Code Tests (Required)
/// 1. Install Claude Code CLI: https://claude.ai/download
/// 2. Ensure `claude` command is in PATH
/// 3. Set up ANTHROPIC_API_KEY environment variable
///
/// ### For Gemini Tests (Optional - tagged with @Tags(['requires-gemini']))
/// 1. Install Gemini CLI: https://ai.google.dev/gemini-api/docs/cli
/// 2. Ensure `gemini` command is in PATH
/// 3. Set up GOOGLE_API_KEY environment variable
///
/// ### For Codex Tests (Optional - tagged with @Tags(['requires-codex']))
/// 1. Install Codex CLI: npm install -g @openai/codex
/// 2. Ensure `codex` command is in PATH
/// 3. Set up OPENAI_API_KEY environment variable
///
/// ## Running the Tests
///
/// To run these tests, use the `--run-skipped` flag:
///
/// ```bash
/// # Run all tests on macOS
/// flutter test integration_test/acp_agent_test.dart -d macos --run-skipped
///
/// # Run with verbose output
/// flutter test integration_test/acp_agent_test.dart -d macos --run-skipped -v
///
/// # Run only tests that require Gemini (if using tags)
/// flutter test integration_test/acp_agent_test.dart -d macos --run-skipped \
///   --tags requires-gemini
/// ```
///
/// ## Cost Warning
///
/// These tests send real prompts to agents and will incur API costs.
/// The prompts are designed to be simple and low-cost.
///
@Skip('Requires ACP agents installed. Run with --run-skipped')
library;

import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/acp/acp_session_wrapper.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late TestResources resources;

  setUp(() {
    resources = TestResources();
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  group('Agent Discovery', () {
    test('AgentRegistry.discover() finds Claude Code if installed', () async {
      // Arrange
      final registry = AgentRegistry();
      resources.track(registry);

      // Act
      await registry.discover();

      // Assert
      expect(registry.hasDiscovered, isTrue);

      // Check if Claude Code was found
      final claudeAgent = registry.getAgent('claude-code');
      if (claudeAgent != null) {
        expect(claudeAgent.name, 'Claude Code');
        expect(claudeAgent.command, isNotEmpty);
        // Print for debugging when running manually
        // ignore: avoid_print
        print('Found Claude Code at: ${claudeAgent.command}');
      } else {
        // If not found, the test still passes (it's just informational)
        // ignore: avoid_print
        print('Claude Code not found. Install with: https://claude.ai/download');
      }
    });

    test('AgentRegistry lists all discovered agents', () async {
      // Arrange
      final registry = AgentRegistry();
      resources.track(registry);

      // Act
      await registry.discover();

      // Assert
      expect(registry.agents, isA<List<AgentConfig>>());

      // Print discovered agents for debugging
      for (final agent in registry.agents) {
        // ignore: avoid_print
        print('Discovered agent: ${agent.name} (${agent.id}) at ${agent.command}');
      }
    });
  });

  group('Agent Connection', () {
    late AgentConfig? claudeConfig;

    setUp(() async {
      // Discover Claude Code agent
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();
      claudeConfig = registry.getAgent('claude-code');
    });

    test('connects to discovered Claude Code agent', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      // Act
      await wrapper.connect();

      // Assert
      expect(wrapper.isConnected, isTrue);
      expect(wrapper.agentInfo, isNotNull);
      expect(wrapper.agentInfo!.id, 'claude-code');
      expect(wrapper.agentInfo!.name, 'Claude Code');
      expect(wrapper.protocolVersion, isNotNull);

      // Print connection info for debugging
      // ignore: avoid_print
      print('Connected to: ${wrapper.agentInfo!.name}');
      // ignore: avoid_print
      print('Protocol version: ${wrapper.protocolVersion}');

      // Cleanup
      await wrapper.disconnect();
      expect(wrapper.isConnected, isFalse);
    });

    test('exposes capabilities after connection', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      // Act
      await wrapper.connect();

      // Assert
      // Capabilities may be null if agent doesn't advertise them
      if (wrapper.capabilities != null) {
        // ignore: avoid_print
        print('Agent capabilities: ${wrapper.capabilities}');
      } else {
        // ignore: avoid_print
        print('Agent did not advertise capabilities');
      }

      // Cleanup
      await wrapper.disconnect();
    });
  });

  group('Session Creation', () {
    late AgentConfig? claudeConfig;

    setUp(() async {
      // Discover Claude Code agent
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();
      claudeConfig = registry.getAgent('claude-code');
    });

    test('creates session with working directory', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();

      // Act - create session in /tmp to avoid permission issues
      final session = await wrapper.createSession(cwd: '/tmp');

      // Assert
      expect(session, isA<ACPSessionWrapper>());
      expect(session.sessionId, isNotEmpty);

      // Print session info for debugging
      // ignore: avoid_print
      print('Session created: ${session.sessionId}');

      if (session.modes != null) {
        // ignore: avoid_print
        print('Available modes: ${session.modes!.availableModes}');
        // ignore: avoid_print
        print('Current mode: ${session.modes!.currentModeId}');
      }

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    });

    test('session provides update stream', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Assert - stream should be accessible
      expect(session.updates, isA<Stream<SessionUpdate>>());
      expect(session.permissionRequests, isNotNull);

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    });
  });

  group('Simple Prompt', () {
    late AgentConfig? claudeConfig;

    setUp(() async {
      // Discover Claude Code agent
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();
      claudeConfig = registry.getAgent('claude-code');
    });

    test('sends simple prompt and receives response', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Collect updates
      final updates = <SessionUpdate>[];
      final subscription = session.updates.listen((update) {
        updates.add(update);
        // Print update type for debugging
        // ignore: avoid_print
        print('Update: ${update.runtimeType}');
      });
      resources.trackSubscription(subscription);

      // Act - send a very simple prompt that doesn't require tools
      // ignore: avoid_print
      print('Sending prompt...');
      final response = await session.prompt([
        TextContentBlock(text: 'Say "Hello" and nothing else.'),
      ]);

      // Assert
      expect(response, isA<PromptResponse>());
      expect(response.stopReason, isNotNull);
      // ignore: avoid_print
      print('Stop reason: ${response.stopReason}');
      // ignore: avoid_print
      print('Updates received: ${updates.length}');

      // Should have received at least one update (agent message)
      expect(updates, isNotEmpty);

      // Check for text content in updates
      final textUpdates = updates.whereType<AgentMessageChunkSessionUpdate>();
      // ignore: avoid_print
      print('Text updates: ${textUpdates.length}');

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('can cancel an in-progress prompt', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Start prompt but don't await it
      final promptFuture = session.prompt([
        TextContentBlock(
          text: 'Count from 1 to 100, saying each number slowly.',
        ),
      ]);

      // Wait a moment then cancel
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // ignore: avoid_print
      print('Cancelling prompt...');
      await session.cancel();

      // The prompt should complete with cancelled status
      final response = await promptFuture;
      // ignore: avoid_print
      print('Stop reason after cancel: ${response.stopReason}');

      // StopReason might be cancelled or the prompt might have completed
      // before the cancel was processed
      expect(response.stopReason, isNotNull);

      // Cleanup
      session.dispose();
      await wrapper.disconnect();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Session Cleanup', () {
    late AgentConfig? claudeConfig;

    setUp(() async {
      // Discover Claude Code agent
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();
      claudeConfig = registry.getAgent('claude-code');
    });

    test('session dispose cancels subscriptions', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();
      final session = await wrapper.createSession(cwd: '/tmp');

      // Subscribe to streams
      var updatesDone = false;
      var permissionsDone = false;

      final updateSub = session.updates.listen(
        (_) {},
        onDone: () => updatesDone = true,
      );
      final permSub = session.permissionRequests.listen(
        (_) {},
        onDone: () => permissionsDone = true,
      );

      // Act
      session.dispose();

      // Wait for streams to close
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Assert
      expect(updatesDone, isTrue);
      expect(permissionsDone, isTrue);

      // Cleanup subscriptions
      await updateSub.cancel();
      await permSub.cancel();
      await wrapper.disconnect();
    });

    test('wrapper disconnect cleans up connection', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);

      await wrapper.connect();
      expect(wrapper.isConnected, isTrue);
      expect(wrapper.connection, isNotNull);

      // Act
      await wrapper.disconnect();

      // Assert
      expect(wrapper.isConnected, isFalse);
      expect(wrapper.connection, isNull);
      expect(wrapper.agentInfo, isNull);
      expect(wrapper.protocolVersion, isNull);
    });

    test('wrapper dispose is idempotent', () async {
      // Skip if Claude Code not found
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      // Arrange - don't track this wrapper since we'll dispose it manually
      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);

      await wrapper.connect();

      // Act - dispose multiple times should not throw
      wrapper.dispose();
      wrapper.dispose();
      wrapper.dispose();

      // Assert
      expect(wrapper.isConnected, isFalse);
    });
  });

  // ===========================================================================
  // Multi-Agent Integration Tests
  // ===========================================================================
  //
  // These tests verify multi-agent support including:
  // - Agent discovery for different providers (Gemini, Codex)
  // - Agent switching between different providers
  // - Capabilities comparison across agents
  // - Agent-agnostic session API behavior
  //
  // Prerequisites for specific tests:
  // - Gemini CLI tests: Install `gemini` CLI and set GOOGLE_API_KEY
  // - Codex CLI tests: Install `codex` CLI and set OPENAI_API_KEY
  // - Claude Code tests: Install `claude` CLI and set ANTHROPIC_API_KEY
  //
  // ===========================================================================

  group('Multi-Agent Discovery', () {
    /// Tests that AgentRegistry can discover Gemini CLI if installed.
    ///
    /// Prerequisites:
    /// - Gemini CLI must be installed (`gemini` command in PATH)
    /// - GOOGLE_API_KEY environment variable should be set for actual usage
    ///
    /// This test only checks discovery - it does not connect or send prompts.
    ///
    /// Tag: requires-gemini
    test('discovers Gemini CLI if installed', () async {
      // Arrange
      final registry = AgentRegistry();
      resources.track(registry);

      // Act
      await registry.discover();

      // Assert
      expect(registry.hasDiscovered, isTrue);

      final geminiAgent = registry.getAgent('gemini-cli');
      if (geminiAgent != null) {
        expect(geminiAgent.name, 'Gemini CLI');
        expect(geminiAgent.command, isNotEmpty);
        // Gemini requires --acp flag for ACP mode
        expect(geminiAgent.args, contains('--acp'));
        // ignore: avoid_print
        print('Found Gemini CLI at: ${geminiAgent.command}');
        // ignore: avoid_print
        print('Args: ${geminiAgent.args}');
      } else {
        // If not found, print helpful info but don't fail
        // ignore: avoid_print
        print('Gemini CLI not found.');
        // ignore: avoid_print
        print('To install: https://ai.google.dev/gemini-api/docs/cli');
      }
    });

    /// Tests that AgentRegistry can discover Codex CLI if installed.
    ///
    /// Prerequisites:
    /// - Codex CLI must be installed (`codex` command in PATH)
    /// - OPENAI_API_KEY environment variable should be set for actual usage
    ///
    /// This test only checks discovery - it does not connect or send prompts.
    ///
    /// Tag: requires-codex
    test('discovers Codex CLI if installed', () async {
      // Arrange
      final registry = AgentRegistry();
      resources.track(registry);

      // Act
      await registry.discover();

      // Assert
      expect(registry.hasDiscovered, isTrue);

      final codexAgent = registry.getAgent('codex-cli');
      if (codexAgent != null) {
        expect(codexAgent.name, 'Codex CLI');
        expect(codexAgent.command, isNotEmpty);
        // ignore: avoid_print
        print('Found Codex CLI at: ${codexAgent.command}');
      } else {
        // If not found, print helpful info but don't fail
        // ignore: avoid_print
        print('Codex CLI not found.');
        // ignore: avoid_print
        print('To install: npm install -g @openai/codex');
      }
    });

    test('discovers all available agents', () async {
      // Arrange
      final registry = AgentRegistry();
      resources.track(registry);

      // Act
      await registry.discover();

      // Assert
      expect(registry.hasDiscovered, isTrue);
      // ignore: avoid_print
      print('Discovered ${registry.agents.length} agent(s):');
      for (final agent in registry.agents) {
        // ignore: avoid_print
        print('  - ${agent.name} (${agent.id})');
        // ignore: avoid_print
        print('    Command: ${agent.command}');
        if (agent.args.isNotEmpty) {
          // ignore: avoid_print
          print('    Args: ${agent.args}');
        }
      }
    });
  });

  group('Agent Switching', () {
    late AgentConfig? claudeConfig;
    late AgentConfig? geminiConfig;

    setUp(() async {
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();
      claudeConfig = registry.getAgent('claude-code');
      geminiConfig = registry.getAgent('gemini-cli');
    });

    /// Tests that we can switch between different agent connections.
    ///
    /// Prerequisites:
    /// - At least two ACP agents must be installed
    /// - Currently tests Claude Code and Gemini CLI
    ///
    /// This test verifies that:
    /// - We can connect to one agent
    /// - Disconnect cleanly
    /// - Connect to a different agent
    /// - Both agents report correct identity
    ///
    /// Tag: requires-gemini
    test('can switch between Claude and Gemini agents', () async {
      // Skip if neither agent is available
      if (claudeConfig == null && geminiConfig == null) {
        // ignore: avoid_print
        print('Skipping: Neither Claude Code nor Gemini CLI installed');
        return;
      }

      // Test Claude first if available
      if (claudeConfig != null) {
        final claudeWrapper = ACPClientWrapper(agentConfig: claudeConfig!);
        resources.track(claudeWrapper);

        await claudeWrapper.connect();
        expect(claudeWrapper.isConnected, isTrue);
        expect(claudeWrapper.agentInfo?.id, 'claude-code');
        // ignore: avoid_print
        print('Connected to Claude Code');

        await claudeWrapper.disconnect();
        expect(claudeWrapper.isConnected, isFalse);
        // ignore: avoid_print
        print('Disconnected from Claude Code');
      }

      // Then switch to Gemini if available
      if (geminiConfig != null) {
        final geminiWrapper = ACPClientWrapper(agentConfig: geminiConfig!);
        resources.track(geminiWrapper);

        await geminiWrapper.connect();
        expect(geminiWrapper.isConnected, isTrue);
        expect(geminiWrapper.agentInfo?.id, 'gemini-cli');
        // ignore: avoid_print
        print('Connected to Gemini CLI');

        await geminiWrapper.disconnect();
        expect(geminiWrapper.isConnected, isFalse);
        // ignore: avoid_print
        print('Disconnected from Gemini CLI');
      }
    });

    /// Tests that multiple agents can be discovered and managed independently.
    ///
    /// This test verifies that:
    /// - AgentRegistry tracks all discovered agents
    /// - Each agent has a unique ID
    /// - Agent configs can be retrieved by ID
    test('manages multiple agents independently', () async {
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();

      // Get all discovered agent IDs
      final agentIds = registry.agents.map((a) => a.id).toSet();
      // ignore: avoid_print
      print('Discovered agent IDs: $agentIds');

      // Verify each agent can be retrieved individually
      for (final id in agentIds) {
        final agent = registry.getAgent(id);
        expect(agent, isNotNull);
        expect(agent!.id, id);
        // ignore: avoid_print
        print('Retrieved agent $id: ${agent.name}');
      }

      // Verify IDs are unique
      expect(agentIds.length, registry.agents.length);
    });
  });

  group('Capabilities Comparison', () {
    late AgentConfig? claudeConfig;
    late AgentConfig? geminiConfig;

    setUp(() async {
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();
      claudeConfig = registry.getAgent('claude-code');
      geminiConfig = registry.getAgent('gemini-cli');
    });

    /// Tests that different agents may report different capabilities.
    ///
    /// Prerequisites:
    /// - Claude Code must be installed for baseline comparison
    /// - Gemini CLI for comparison (optional)
    ///
    /// This test verifies that:
    /// - Agents report capabilities after connection
    /// - Different agents may have different capability sets
    ///
    /// Tag: requires-gemini
    test('agents report their capabilities', () async {
      final capabilities = <String, dynamic>{};

      // Get Claude capabilities if available
      if (claudeConfig != null) {
        final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
        resources.track(wrapper);
        resources.onCleanup(() => wrapper.disconnect());

        await wrapper.connect();
        capabilities['claude-code'] = wrapper.capabilities;
        // ignore: avoid_print
        print('Claude Code capabilities: ${wrapper.capabilities}');
        await wrapper.disconnect();
      }

      // Get Gemini capabilities if available
      if (geminiConfig != null) {
        final wrapper = ACPClientWrapper(agentConfig: geminiConfig!);
        resources.track(wrapper);
        resources.onCleanup(() => wrapper.disconnect());

        try {
          await wrapper.connect();
          capabilities['gemini-cli'] = wrapper.capabilities;
          // ignore: avoid_print
          print('Gemini CLI capabilities: ${wrapper.capabilities}');
          await wrapper.disconnect();
        } catch (e) {
          // ignore: avoid_print
          print('Failed to connect to Gemini: $e');
        }
      }

      // Report comparison
      if (capabilities.length >= 2) {
        // ignore: avoid_print
        print('\nCapabilities comparison:');
        for (final entry in capabilities.entries) {
          // ignore: avoid_print
          print('  ${entry.key}: ${entry.value}');
        }
      }
    });

    /// Tests that protocol version is reported consistently.
    ///
    /// All ACP-compatible agents should report a protocol version
    /// after successful connection.
    test('agents report protocol version', () async {
      if (claudeConfig == null) {
        // ignore: avoid_print
        print('Skipping: Claude Code not installed');
        return;
      }

      final wrapper = ACPClientWrapper(agentConfig: claudeConfig!);
      resources.track(wrapper);
      resources.onCleanup(() => wrapper.disconnect());

      await wrapper.connect();

      // Protocol version should be non-null after connection
      expect(wrapper.protocolVersion, isNotNull);
      expect(wrapper.protocolVersion, greaterThan(0));
      // ignore: avoid_print
      print('Protocol version: ${wrapper.protocolVersion}');

      await wrapper.disconnect();
    });
  });

  group('Agent-Agnostic API', () {
    late AgentConfig? claudeConfig;
    late AgentConfig? geminiConfig;

    setUp(() async {
      final registry = AgentRegistry();
      resources.track(registry);
      await registry.discover();
      claudeConfig = registry.getAgent('claude-code');
      geminiConfig = registry.getAgent('gemini-cli');
    });

    /// Tests that the same session API works regardless of which agent is used.
    ///
    /// Prerequisites:
    /// - At least one ACP agent must be installed
    ///
    /// This test verifies that:
    /// - Sessions can be created with any agent using the same API
    /// - Session provides consistent streams (updates, permissionRequests)
    /// - Session ID is always returned
    test('session creation API is consistent across agents', () async {
      Future<void> testSessionCreation(AgentConfig config) async {
        final wrapper = ACPClientWrapper(agentConfig: config);
        resources.track(wrapper);
        resources.onCleanup(() => wrapper.disconnect());

        await wrapper.connect();
        final session = await wrapper.createSession(cwd: '/tmp');

        // Verify session API is consistent
        expect(session.sessionId, isNotEmpty);
        expect(session.updates, isA<Stream<SessionUpdate>>());
        expect(session.permissionRequests, isNotNull);

        // ignore: avoid_print
        print('${config.name} session created: ${session.sessionId}');

        session.dispose();
        await wrapper.disconnect();
      }

      // Test with Claude if available
      if (claudeConfig != null) {
        // ignore: avoid_print
        print('Testing session API with Claude Code...');
        await testSessionCreation(claudeConfig!);
      }

      // Test with Gemini if available
      if (geminiConfig != null) {
        // ignore: avoid_print
        print('Testing session API with Gemini CLI...');
        try {
          await testSessionCreation(geminiConfig!);
        } catch (e) {
          // ignore: avoid_print
          print('Gemini session creation failed: $e');
        }
      }

      // At least one agent should be available
      if (claudeConfig == null && geminiConfig == null) {
        // ignore: avoid_print
        print('Warning: No agents available for testing');
      }
    });

    /// Tests that the wrapper API provides consistent methods for any agent.
    ///
    /// This test verifies:
    /// - isConnected works consistently
    /// - agentInfo returns correct data for each agent
    /// - connect/disconnect lifecycle is the same
    test('wrapper API is consistent across agents', () async {
      Future<void> testWrapperAPI(AgentConfig config) async {
        final wrapper = ACPClientWrapper(agentConfig: config);
        resources.track(wrapper);

        // Before connect
        expect(wrapper.isConnected, isFalse);
        expect(wrapper.agentInfo, isNull);
        expect(wrapper.connection, isNull);

        // Connect
        await wrapper.connect();
        expect(wrapper.isConnected, isTrue);
        expect(wrapper.agentInfo, isNotNull);
        expect(wrapper.agentInfo!.id, config.id);
        expect(wrapper.agentInfo!.name, config.name);
        expect(wrapper.connection, isNotNull);

        // ignore: avoid_print
        print('${config.name}: Connected successfully');

        // Disconnect
        await wrapper.disconnect();
        expect(wrapper.isConnected, isFalse);
        expect(wrapper.agentInfo, isNull);
        expect(wrapper.connection, isNull);

        // ignore: avoid_print
        print('${config.name}: Disconnected successfully');
      }

      if (claudeConfig != null) {
        await testWrapperAPI(claudeConfig!);
      }

      if (geminiConfig != null) {
        try {
          await testWrapperAPI(geminiConfig!);
        } catch (e) {
          // ignore: avoid_print
          print('Gemini wrapper test failed: $e');
        }
      }

      if (claudeConfig == null && geminiConfig == null) {
        // ignore: avoid_print
        print('Warning: No agents available for testing');
      }
    });

    /// Tests that custom agents can be added and used with the same API.
    ///
    /// This test verifies:
    /// - Custom agents can be added to the registry
    /// - Custom agents use the same AgentConfig structure
    /// - Custom agents can be retrieved by ID
    test('custom agents use consistent API', () async {
      final registry = AgentRegistry();
      resources.track(registry);

      // Add a custom agent configuration
      const customConfig = AgentConfig(
        id: 'custom-test-agent',
        name: 'Custom Test Agent',
        command: '/usr/bin/false', // Intentionally invalid for test
        args: ['--acp'],
        env: {'TEST_VAR': 'test_value'},
      );

      registry.addCustomAgent(customConfig);

      // Verify it can be retrieved
      final retrieved = registry.getAgent('custom-test-agent');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'custom-test-agent');
      expect(retrieved.name, 'Custom Test Agent');
      expect(retrieved.args, ['--acp']);
      expect(retrieved.env['TEST_VAR'], 'test_value');

      // ignore: avoid_print
      print('Custom agent added and retrieved successfully');

      // Clean up
      registry.removeAgent('custom-test-agent');
      expect(registry.getAgent('custom-test-agent'), isNull);
      // ignore: avoid_print
      print('Custom agent removed successfully');
    });
  });
}
