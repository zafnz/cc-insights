import 'dart:convert';
import 'dart:io';

import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('AgentRegistry', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    test('starts with empty agents list', () {
      final registry = resources.track(AgentRegistry());

      expect(registry.agents, isEmpty);
      expect(registry.hasDiscovered, isFalse);
    });

    test('discover sets hasDiscovered to true', () async {
      final registry = resources.track(AgentRegistry());

      await registry.discover();

      expect(registry.hasDiscovered, isTrue);
    });

    test('addCustomAgent adds to list', () {
      final registry = resources.track(AgentRegistry());
      const config = AgentConfig(
        id: 'custom',
        name: 'Custom Agent',
        command: '/path/to/agent',
      );

      registry.addCustomAgent(config);

      expect(registry.agents, contains(config));
      expect(registry.customAgents, contains(config));
    });

    test('removeAgent removes from list', () {
      final registry = resources.track(AgentRegistry());
      const config = AgentConfig(id: 'custom', name: 'Custom', command: '/a');
      registry.addCustomAgent(config);

      registry.removeAgent('custom');

      expect(registry.agents, isNot(contains(config)));
    });

    test('getAgent returns agent by ID', () {
      final registry = resources.track(AgentRegistry());
      const config = AgentConfig(id: 'test', name: 'Test', command: '/test');
      registry.addCustomAgent(config);

      expect(registry.getAgent('test'), equals(config));
      expect(registry.getAgent('nonexistent'), isNull);
    });

    test('hasAgent returns true for existing agent', () {
      final registry = resources.track(AgentRegistry());
      const config = AgentConfig(id: 'test', name: 'Test', command: '/test');
      registry.addCustomAgent(config);

      expect(registry.hasAgent('test'), isTrue);
      expect(registry.hasAgent('nonexistent'), isFalse);
    });

    test('notifies listeners on change', () {
      final registry = resources.track(AgentRegistry());
      var notified = false;
      registry.addListener(() => notified = true);

      registry.addCustomAgent(
        const AgentConfig(id: 'x', name: 'X', command: '/x'),
      );

      expect(notified, isTrue);
    });

    test('agents list is unmodifiable', () {
      final registry = resources.track(AgentRegistry());

      expect(
        () => registry.agents.add(
          const AgentConfig(id: 'x', name: 'X', command: '/x'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('notifies listeners on discover', () async {
      final registry = resources.track(AgentRegistry());
      var notified = false;
      registry.addListener(() => notified = true);

      await registry.discover();

      expect(notified, isTrue);
    });

    test('notifies listeners on removeAgent', () {
      final registry = resources.track(AgentRegistry());
      const config = AgentConfig(id: 'test', name: 'Test', command: '/test');
      registry.addCustomAgent(config);

      var notified = false;
      registry.addListener(() => notified = true);

      registry.removeAgent('test');

      expect(notified, isTrue);
    });

    test('removeAgent does not notify if agent not found', () {
      final registry = resources.track(AgentRegistry());
      var notified = false;
      registry.addListener(() => notified = true);

      registry.removeAgent('nonexistent');

      expect(notified, isFalse);
    });

    test('addCustomAgent does not duplicate existing agent', () {
      final registry = resources.track(AgentRegistry());
      const config = AgentConfig(id: 'test', name: 'Test', command: '/test');

      registry.addCustomAgent(config);
      registry.addCustomAgent(config);

      expect(registry.agents.length, equals(1));
    });

    test('configDir is preserved', () {
      final registry = resources.track(AgentRegistry(configDir: '/config/path'));

      expect(registry.configDir, equals('/config/path'));
    });

    test('discoveredAgents is separate from customAgents', () {
      final registry = resources.track(AgentRegistry());
      const config = AgentConfig(id: 'custom', name: 'Custom', command: '/custom');

      registry.addCustomAgent(config);

      expect(registry.customAgents, contains(config));
      expect(registry.discoveredAgents, isEmpty);
    });

    test('discoveredAgents list is unmodifiable', () {
      final registry = resources.track(AgentRegistry());

      expect(
        () => registry.discoveredAgents.add(
          const AgentConfig(id: 'x', name: 'X', command: '/x'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('customAgents list is unmodifiable', () {
      final registry = resources.track(AgentRegistry());

      expect(
        () => registry.customAgents.add(
          const AgentConfig(id: 'x', name: 'X', command: '/x'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    group('Agent Discovery', () {
      test('discover completes without error', () async {
        final registry = resources.track(AgentRegistry());

        // Should not throw even if no agents installed
        await expectLater(registry.discover(), completes);
      });

      test('discover returns list (may be empty)', () async {
        final registry = resources.track(AgentRegistry());
        await registry.discover();

        // Should return a list (possibly empty)
        expect(registry.discoveredAgents, isA<List<AgentConfig>>());
      });

      test('discovered agents have valid properties', () async {
        final registry = resources.track(AgentRegistry());
        await registry.discover();

        // If any agents were found, verify they have valid properties
        for (final agent in registry.discoveredAgents) {
          expect(agent.id, isNotEmpty);
          expect(agent.name, isNotEmpty);
          expect(agent.command, isNotEmpty);
        }
      });

      test('claude-code agent has expected ID if discovered', () async {
        final registry = resources.track(AgentRegistry());
        await registry.discover();

        final claude = registry.getAgent('claude-code');
        if (claude != null) {
          expect(claude.id, equals('claude-code'));
          // Name varies based on whether it's the global install or local dev package
          expect(claude.name, anyOf(equals('Claude Code'), equals('Claude Code (local)')));
        }
      });

      test('gemini-cli agent has expected ID if discovered', () async {
        final registry = resources.track(AgentRegistry());
        await registry.discover();

        final gemini = registry.getAgent('gemini-cli');
        if (gemini != null) {
          expect(gemini.id, equals('gemini-cli'));
          expect(gemini.name, equals('Gemini CLI'));
        }
      });
    });

    group('Agent Persistence', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('agent_test_');
      });

      tearDown(() async {
        await tempDir.delete(recursive: true);
      });

      test('save creates config file', () async {
        final registry = AgentRegistry(configDir: tempDir.path);
        registry.addCustomAgent(
          const AgentConfig(id: 'test', name: 'Test', command: '/test'),
        );

        // Wait for fire-and-forget save to complete
        await Future.delayed(const Duration(milliseconds: 100));

        final file = File('${tempDir.path}/agents.json');
        expect(await file.exists(), isTrue);
      });

      test('save persists agent data correctly', () async {
        final registry = AgentRegistry(configDir: tempDir.path);
        registry.addCustomAgent(const AgentConfig(
          id: 'test-agent',
          name: 'Test Agent',
          command: '/usr/bin/test',
          args: ['--flag'],
          env: {'KEY': 'value'},
        ));

        await Future.delayed(const Duration(milliseconds: 100));

        final file = File('${tempDir.path}/agents.json');
        final content = await file.readAsString();
        final json = jsonDecode(content) as List<dynamic>;

        expect(json.length, equals(1));
        expect(json[0]['id'], equals('test-agent'));
        expect(json[0]['name'], equals('Test Agent'));
      });

      test('load restores saved agents', () async {
        // First save some agents
        final registry1 = AgentRegistry(configDir: tempDir.path);
        registry1.addCustomAgent(
          const AgentConfig(id: 'saved', name: 'Saved Agent', command: '/saved'),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        // Create new registry and load
        final registry2 = AgentRegistry(configDir: tempDir.path);
        await registry2.load();

        expect(registry2.customAgents.length, equals(1));
        expect(registry2.customAgents.first.id, equals('saved'));
      });

      test('load handles missing file gracefully', () async {
        final registry = AgentRegistry(configDir: tempDir.path);

        // Should not throw
        await expectLater(registry.load(), completes);
        expect(registry.customAgents, isEmpty);
      });

      test('load handles corrupt file gracefully', () async {
        final file = File('${tempDir.path}/agents.json');
        await file.writeAsString('not valid json');

        final registry = AgentRegistry(configDir: tempDir.path);

        // Should not throw
        await expectLater(registry.load(), completes);
      });

      test('removeAgent also saves', () async {
        final registry = AgentRegistry(configDir: tempDir.path);
        registry.addCustomAgent(
          const AgentConfig(
            id: 'to-remove',
            name: 'To Remove',
            command: '/remove',
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        registry.removeAgent('to-remove');
        await Future.delayed(const Duration(milliseconds: 100));

        // Load in new registry to verify save happened
        final registry2 = AgentRegistry(configDir: tempDir.path);
        await registry2.load();
        expect(registry2.customAgents, isEmpty);
      });
    });
  });
}
