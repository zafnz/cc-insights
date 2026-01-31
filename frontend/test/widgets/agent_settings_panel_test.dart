import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/widgets/agent_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  group('AgentSettingsPanel', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    testWidgets('displays agent list', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'test', name: 'Test Agent', command: '/test'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.text('Test Agent'), findsOneWidget);
    });

    testWidgets('shows empty state when no agents', (tester) async {
      final registry = resources.track(AgentRegistry());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.text('No agents configured'), findsOneWidget);
    });

    testWidgets('add button opens dialog', (tester) async {
      final registry = resources.track(AgentRegistry());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(AgentSettingsPanelKeys.addButton));
      await safePumpAndSettle(tester);

      expect(find.text('Add Custom Agent'), findsOneWidget);
    });

    testWidgets('delete removes custom agent', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'custom', name: 'Custom Agent', command: '/custom'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Find and tap delete button using the key pattern from the implementation
      await tester.tap(find.byKey(const Key('agent_delete_custom')));
      await safePumpAndSettle(tester);

      // Confirm deletion in dialog
      await tester.tap(find.text('Delete'));
      await safePumpAndSettle(tester);

      expect(registry.customAgents, isEmpty);
    });

    testWidgets('can add agent through dialog', (tester) async {
      final registry = resources.track(AgentRegistry());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Open add dialog
      await tester.tap(find.byKey(AgentSettingsPanelKeys.addButton));
      await safePumpAndSettle(tester);

      // Fill in form fields using the defined keys
      await tester.enterText(find.byKey(AddAgentDialogKeys.idField), 'new-agent');
      await tester.enterText(find.byKey(AddAgentDialogKeys.nameField), 'New Agent');
      await tester.enterText(find.byKey(AddAgentDialogKeys.commandField), '/path/to/agent');

      // Tap Add button using the defined key
      await tester.tap(find.byKey(AddAgentDialogKeys.addAgentButton));
      await safePumpAndSettle(tester);

      expect(registry.customAgents.length, equals(1));
      expect(registry.customAgents.first.id, equals('new-agent'));
    });

    testWidgets('displays custom agents section header', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'custom', name: 'Custom Agent', command: '/custom'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.text('Custom Agents'), findsOneWidget);
      expect(find.text('Manually configured agents'), findsOneWidget);
    });

    testWidgets('shows custom badge for custom agents', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'custom', name: 'Custom Agent', command: '/custom'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('cancel button closes add dialog without adding', (tester) async {
      final registry = resources.track(AgentRegistry());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Open add dialog
      await tester.tap(find.byKey(AgentSettingsPanelKeys.addButton));
      await safePumpAndSettle(tester);

      // Fill in some data
      await tester.enterText(find.byKey(AddAgentDialogKeys.idField), 'new-agent');

      // Tap Cancel button
      await tester.tap(find.byKey(AddAgentDialogKeys.cancelButton));
      await safePumpAndSettle(tester);

      // Dialog should be closed and no agent added
      expect(find.text('Add Custom Agent'), findsNothing);
      expect(registry.customAgents, isEmpty);
    });

    testWidgets('validation prevents adding agent without required fields', (tester) async {
      final registry = resources.track(AgentRegistry());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Open add dialog
      await tester.tap(find.byKey(AgentSettingsPanelKeys.addButton));
      await safePumpAndSettle(tester);

      // Try to add without filling in required fields
      await tester.tap(find.byKey(AddAgentDialogKeys.addAgentButton));
      await safePumpAndSettle(tester);

      // Dialog should still be open (validation failed)
      expect(find.text('Add Custom Agent'), findsOneWidget);
      // Validation messages should appear
      expect(find.text('ID is required'), findsOneWidget);
      expect(registry.customAgents, isEmpty);
    });

    testWidgets('shows command in agent list tile', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(
          id: 'custom',
          name: 'Custom Agent',
          command: '/usr/local/bin/custom-agent',
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.text('/usr/local/bin/custom-agent'), findsOneWidget);
    });

    testWidgets('shows args in agent list tile when provided', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(
          id: 'custom',
          name: 'Custom Agent',
          command: '/custom',
          args: ['--verbose', '--mode', 'chat'],
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.textContaining('Args:'), findsOneWidget);
      expect(find.textContaining('--verbose'), findsOneWidget);
    });

    testWidgets('shows env in agent list tile when provided', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(
          id: 'custom',
          name: 'Custom Agent',
          command: '/custom',
          env: {'API_KEY': 'secret', 'DEBUG': 'true'},
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.textContaining('Env:'), findsOneWidget);
      expect(find.textContaining('API_KEY'), findsOneWidget);
    });

    testWidgets('delete dialog shows cancel option', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'custom', name: 'Custom Agent', command: '/custom'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Tap delete button
      await tester.tap(find.byKey(const Key('agent_delete_custom')));
      await safePumpAndSettle(tester);

      // Cancel deletion
      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      // Agent should still exist
      expect(registry.customAgents.length, equals(1));
    });

    testWidgets('can add environment variables in dialog', (tester) async {
      final registry = resources.track(AgentRegistry());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSettingsPanel()),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Open add dialog
      await tester.tap(find.byKey(AgentSettingsPanelKeys.addButton));
      await safePumpAndSettle(tester);

      // Add an environment variable
      await tester.tap(find.byKey(AddAgentDialogKeys.addEnvButton));
      await safePumpAndSettle(tester);

      // Should find env key/value fields
      expect(find.byKey(const Key('env_key_0')), findsOneWidget);
      expect(find.byKey(const Key('env_value_0')), findsOneWidget);
    });
  });
}
