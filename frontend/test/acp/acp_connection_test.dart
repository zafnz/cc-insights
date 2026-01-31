/// Integration test for ACP connection to Claude Code.
///
/// This test requires:
/// 1. The claude-code-acp package to be built (npm run build in packages/claude-code-acp)
/// 2. ANTHROPIC_API_KEY to be set in the environment
///
/// Run with: flutter test test/acp/acp_connection_test.dart
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/acp/acp_client_wrapper.dart';
import '../../lib/services/agent_registry.dart';
import '../test_helpers.dart';

void main() {
  group('ACP Connection', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    test('discovers claude-code-acp agent', () async {
      final registry = resources.track(AgentRegistry());
      await registry.discover();

      debugPrint('Discovered agents:');
      for (final agent in registry.agents) {
        debugPrint('  - ${agent.name} (command: ${agent.command})');
      }

      final claude = registry.getAgent('claude-code');
      expect(claude, isNotNull, reason: 'claude-code-acp should be discovered');
      expect(claude!.command, isNot(contains('claude')),
          reason: 'Should use claude-code-acp, not the regular claude CLI');
    });

    test(
      'connects to Claude Code via ACP',
      () async {
        // Skip if no API key
        final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
        if (apiKey == null || apiKey.isEmpty) {
          markTestSkipped('ANTHROPIC_API_KEY not set');
          return;
        }

        // Discover the agent
        final registry = resources.track(AgentRegistry());
        await registry.discover();

        final claude = registry.getAgent('claude-code');
        if (claude == null) {
          markTestSkipped('claude-code-acp not found');
          return;
        }

        debugPrint('Connecting to Claude Code...');
        debugPrint('  Command: ${claude.command}');
        debugPrint('  Args: ${claude.args}');

        // Create the wrapper and connect
        final wrapper = ACPClientWrapper(
          agentConfig: claude,
          connectionTimeout: const Duration(seconds: 30),
        );
        resources.track(wrapper);

        try {
          await wrapper.connect();

          expect(wrapper.isConnected, isTrue);
          expect(wrapper.connectionState, ACPConnectionState.connected);
          expect(wrapper.protocolVersion, isNotNull);
          debugPrint('Connected! Protocol version: ${wrapper.protocolVersion}');

          // Disconnect cleanly
          await wrapper.disconnect();
          expect(wrapper.isConnected, isFalse);
        } catch (e) {
          debugPrint('Connection failed: $e');
          rethrow;
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
