import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/widgets/agent_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  group('AgentSelector', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    testWidgets('shows available agents', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'a', name: 'Agent A', command: '/a'),
      );
      registry.addCustomAgent(
        const AgentConfig(id: 'b', name: 'Agent B', command: '/b'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSelector()),
          ),
        ),
      );

      // Open the dropdown
      await tester.tap(find.byType(DropdownButton<AgentConfig>));
      await safePumpAndSettle(tester);

      expect(find.text('Agent A'), findsWidgets);
      expect(find.text('Agent B'), findsWidgets);
    });

    testWidgets('calls onSelect when agent chosen', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'a', name: 'Agent A', command: '/a'),
      );

      AgentConfig? selected;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: MaterialApp(
            home: Scaffold(
              body: AgentSelector(onSelect: (config) => selected = config),
            ),
          ),
        ),
      );

      // Open dropdown and select
      await tester.tap(find.byType(DropdownButton<AgentConfig>));
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Agent A').last);
      await safePumpAndSettle(tester);

      expect(selected?.id, equals('a'));
    });

    testWidgets('shows "No agents available" when empty', (tester) async {
      final registry = resources.track(AgentRegistry());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(body: AgentSelector()),
          ),
        ),
      );

      expect(find.text('No agents available'), findsOneWidget);
    });

    testWidgets('shows hint text when no selection', (tester) async {
      final registry = resources.track(AgentRegistry());
      registry.addCustomAgent(
        const AgentConfig(id: 'a', name: 'Agent A', command: '/a'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(
              body: AgentSelector(hint: 'Choose agent'),
            ),
          ),
        ),
      );

      expect(find.text('Choose agent'), findsOneWidget);
    });

    testWidgets('shows selected agent', (tester) async {
      final registry = resources.track(AgentRegistry());
      const agent = AgentConfig(id: 'a', name: 'Agent A', command: '/a');
      registry.addCustomAgent(agent);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: registry,
          child: const MaterialApp(
            home: Scaffold(
              body: AgentSelector(selectedAgent: agent),
            ),
          ),
        ),
      );

      // Selected agent should be visible without opening dropdown
      expect(find.text('Agent A'), findsOneWidget);
    });
  });
}
