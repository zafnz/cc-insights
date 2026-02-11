import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/widgets/cost_indicator.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('CostIndicator', () {
    Widget createTestApp({
      required UsageInfo usage,
      List<ModelUsageInfo> modelUsage = const [],
      String agentLabel = 'Claude',
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: CostIndicator(
              usage: usage,
              modelUsage: modelUsage,
              agentLabel: agentLabel,
            ),
          ),
        ),
      );
    }

    group('Basic rendering', () {
      testWidgets('renders with zero usage', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo.zero(),
        ));
        await safePumpAndSettle(tester);

        // Should show token icon
        expect(find.byIcon(Icons.token), findsOneWidget);

        // Should show zero tokens and zero cost
        expect(find.text('0'), findsOneWidget);
        expect(find.text(r'$0.00'), findsOneWidget);
      });

      testWidgets('shows token icon with correct styling', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.01,
          ),
        ));
        await safePumpAndSettle(tester);

        final iconFinder = find.byIcon(Icons.token);
        expect(iconFinder, findsOneWidget);

        final icon = tester.widget<Icon>(iconFinder);
        check(icon.size).equals(14);
        check(icon.color).equals(Colors.grey[600]);
      });

      testWidgets('applies correct container styling', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo.zero(),
        ));
        await safePumpAndSettle(tester);

        // Find the container with the expected decoration
        final containers = tester.widgetList<Container>(find.byType(Container));
        final styledContainer = containers.where((c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration) {
            return decoration.borderRadius == BorderRadius.circular(4);
          }
          return false;
        });
        check(styledContainer).isNotEmpty();
      });
    });

    group('Token count formatting', () {
      testWidgets('shows correct token count under 1000', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 500,
            outputTokens: 200,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.05,
          ),
        ));
        await safePumpAndSettle(tester);

        // Total is 700
        expect(find.text('700'), findsOneWidget);
      });

      testWidgets('formats thousands with k suffix', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 100000,
            outputTokens: 55000,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 1.50,
          ),
        ));
        await safePumpAndSettle(tester);

        // Total is 155000 -> "155k"
        expect(find.text('155k'), findsOneWidget);
      });

      testWidgets('formats millions with M suffix', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 1000000,
            outputTokens: 234567,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 15.00,
          ),
        ));
        await safePumpAndSettle(tester);

        // Total is 1234567 -> "1.2M"
        expect(find.text('1.2M'), findsOneWidget);
      });

      testWidgets('handles large numbers correctly', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 5000000,
            outputTokens: 3000000,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 100.00,
          ),
        ));
        await safePumpAndSettle(tester);

        // Total is 8000000 -> "8.0M"
        expect(find.text('8.0M'), findsOneWidget);
      });
    });

    group('Cost formatting', () {
      testWidgets('shows correct cost with 2 decimal places', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 2.31,
          ),
        ));
        await safePumpAndSettle(tester);

        expect(find.text(r'$2.31'), findsOneWidget);
      });

      testWidgets('shows cost with 4 decimal places for small amounts',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 50,
            outputTokens: 25,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.0025,
          ),
        ));
        await safePumpAndSettle(tester);

        expect(find.text(r'$0.0025'), findsOneWidget);
      });

      testWidgets('shows zero cost correctly', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo.zero(),
        ));
        await safePumpAndSettle(tester);

        expect(find.text(r'$0.00'), findsOneWidget);
      });
    });

    group('Tooltip content', () {
      testWidgets('has tooltip widget configured', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheCreationTokens: 100,
            costUsd: 0.15,
          ),
        ));
        await safePumpAndSettle(tester);

        // Verify that a Tooltip widget is present
        expect(find.byType(Tooltip), findsOneWidget);

        // Verify the tooltip has richMessage configured
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        check(tooltip.richMessage).isNotNull();
      });

      testWidgets('tooltip message contains usage details', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 1234,
            outputTokens: 567,
            cacheReadTokens: 890,
            cacheCreationTokens: 123,
            costUsd: 0.42,
          ),
        ));
        await safePumpAndSettle(tester);

        // Get the tooltip and check its richMessage content
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage!;

        // Convert the TextSpan to plain text for checking
        final buffer = StringBuffer();
        richMessage.computeToPlainText(buffer);
        final tooltipText = buffer.toString();

        // Check all fields are present in tooltip text
        check(tooltipText).contains('Usage Details');
        check(tooltipText).contains('Input tokens: 1,234');
        check(tooltipText).contains('Output tokens: 567');
        check(tooltipText).contains('Cache read: 890');
        check(tooltipText).contains('Cache creation: 123');
        check(tooltipText).contains(r'Total cost: $0.42');
      });
    });

    group('Model usage breakdown', () {
      testWidgets('shows model breakdown in tooltip when provided',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 5000,
            outputTokens: 2000,
            cacheReadTokens: 1000,
            cacheCreationTokens: 500,
            costUsd: 1.50,
          ),
          modelUsage: const [
            ModelUsageInfo(
              modelName: 'claude-sonnet-4-5-20250929',
              inputTokens: 3000,
              outputTokens: 1500,
              cacheReadTokens: 800,
              cacheCreationTokens: 400,
              costUsd: 1.00,
              contextWindow: 200000,
            ),
            ModelUsageInfo(
              modelName: 'claude-haiku-4-5-20251001',
              inputTokens: 2000,
              outputTokens: 500,
              cacheReadTokens: 200,
              cacheCreationTokens: 100,
              costUsd: 0.50,
              contextWindow: 200000,
            ),
          ],
        ));
        await safePumpAndSettle(tester);

        // Get the tooltip and check its richMessage content
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage!;

        // Convert the TextSpan to plain text for checking
        final buffer = StringBuffer();
        richMessage.computeToPlainText(buffer);
        final tooltipText = buffer.toString();

        // Check model display names are shown
        check(tooltipText).contains('Sonnet 4.5');
        check(tooltipText).contains('Haiku 4.5');
      });

      testWidgets('handles empty modelUsage gracefully', (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.10,
          ),
          modelUsage: const [],
        ));
        await safePumpAndSettle(tester);

        // Get the tooltip and check its richMessage content
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage!;

        // Convert the TextSpan to plain text for checking
        final buffer = StringBuffer();
        richMessage.computeToPlainText(buffer);
        final tooltipText = buffer.toString();

        // Should still show base usage details
        check(tooltipText).contains('Usage Details');
        check(tooltipText).contains('Input tokens');

        // Should not contain model-specific content when empty
        check(tooltipText).not((it) => it.contains('Sonnet'));
        check(tooltipText).not((it) => it.contains('Haiku'));
        check(tooltipText).not((it) => it.contains('Opus'));
      });

      testWidgets('tooltip shows model-specific usage details',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          usage: const UsageInfo(
            inputTokens: 3000,
            outputTokens: 1500,
            cacheReadTokens: 800,
            cacheCreationTokens: 400,
            costUsd: 1.00,
          ),
          modelUsage: const [
            ModelUsageInfo(
              modelName: 'claude-opus-4-5-20251101',
              inputTokens: 3000,
              outputTokens: 1500,
              cacheReadTokens: 800,
              cacheCreationTokens: 400,
              costUsd: 1.00,
              contextWindow: 200000,
            ),
          ],
        ));
        await safePumpAndSettle(tester);

        // Get the tooltip and check its richMessage content
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage!;

        // Convert the TextSpan to plain text for checking
        final buffer = StringBuffer();
        richMessage.computeToPlainText(buffer);
        final tooltipText = buffer.toString();

        // Check model-specific details
        check(tooltipText).contains('Opus 4.5');
        check(tooltipText).contains('Input/Output: 3,000 / 1,500');
        check(tooltipText).contains('Cache: 800 read, 400 created');
        check(tooltipText).contains(r'Cost: $1.00');
      });
    });
  });
}
