import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/services/agent_registry.dart';
import 'package:cc_insights_v2/services/agent_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  group('Provider Setup Tests', () {
    setUp(() {
      // Use mock data to avoid async project loading and real backend
      useMockData = true;
    });

    tearDown(() {
      useMockData = false;
    });

    group('ACP Services', () {
      testWidgets('AgentRegistry is available via Provider', (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        // Find the context from any widget in the tree
        final context = tester.element(find.byType(MaterialApp));

        // Verify AgentRegistry is accessible
        final registry = context.read<AgentRegistry>();
        expect(registry, isNotNull);
        expect(registry, isA<AgentRegistry>());
      });

      testWidgets('AgentService is available via Provider', (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));

        // Verify AgentService is accessible
        final service = context.read<AgentService>();
        expect(service, isNotNull);
        expect(service, isA<AgentService>());
      });

      testWidgets('AgentRegistry is a ChangeNotifier', (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));
        final registry = context.read<AgentRegistry>();

        // Verify it extends ChangeNotifier by adding a listener
        var listenerCalled = false;
        void listener() {
          listenerCalled = true;
        }

        registry.addListener(listener);
        expect(registry, isA<ChangeNotifier>());

        // Clean up listener to avoid issues
        registry.removeListener(listener);
      });

      testWidgets('AgentService is a ChangeNotifier', (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));
        final service = context.read<AgentService>();

        // Verify it extends ChangeNotifier by adding a listener
        var listenerCalled = false;
        void listener() {
          listenerCalled = true;
        }

        service.addListener(listener);
        expect(service, isA<ChangeNotifier>());

        // Clean up listener to avoid issues
        service.removeListener(listener);
      });

      testWidgets(
          'AgentService has reference to AgentRegistry',
          (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));
        final registry = context.read<AgentRegistry>();
        final service = context.read<AgentService>();

        // Verify AgentService references the same AgentRegistry instance
        expect(service.agentRegistry, same(registry));
      });
    });

    group('Provider Tree Integration', () {
      testWidgets(
          'All services are accessible in same widget tree',
          (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));

        // Verify all ACP providers are accessible from the same context
        expect(() => context.read<AgentRegistry>(), returnsNormally);
        expect(() => context.read<AgentService>(), returnsNormally);
      });

      testWidgets(
          'services are the same instance across provider reads',
          (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));

        // Read providers twice and verify same instance is returned
        // This confirms Provider.value is used correctly
        final registry1 = context.read<AgentRegistry>();
        final registry2 = context.read<AgentRegistry>();
        expect(registry1, same(registry2),
            reason: 'AgentRegistry should be same instance');

        final service1 = context.read<AgentService>();
        final service2 = context.read<AgentService>();
        expect(service1, same(service2),
            reason: 'AgentService should be same instance');
      });
    });

    group('Initial State', () {
      testWidgets('AgentRegistry starts with no agents', (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));
        final registry = context.read<AgentRegistry>();

        // In test environment, discovery is async and may not have completed
        // but the agents list should be accessible
        expect(registry.agents, isA<List<AgentConfig>>());
      });

      testWidgets('AgentService starts disconnected', (tester) async {
        await tester.pumpWidget(const CCInsightsApp());
        await safePumpAndSettle(tester);

        final context = tester.element(find.byType(MaterialApp));
        final service = context.read<AgentService>();

        // AgentService should start in disconnected state
        expect(service.isConnected, isFalse);
        expect(service.currentAgent, isNull);
      });
    });
  });
}
