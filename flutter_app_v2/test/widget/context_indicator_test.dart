import 'package:cc_insights_v2/models/context_tracker.dart';
import 'package:cc_insights_v2/widgets/context_indicator.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('ContextIndicator Tests', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    Widget createTestApp(ContextTracker tracker) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: ContextIndicator(tracker: tracker),
          ),
        ),
      );
    }

    group('formatTokens helper function', () {
      test('formats millions correctly', () {
        check(formatTokens(1500000)).equals('1.5M');
        check(formatTokens(1000000)).equals('1.0M');
        check(formatTokens(2300000)).equals('2.3M');
      });

      test('formats thousands correctly', () {
        check(formatTokens(155000)).equals('155.0k');
        check(formatTokens(1000)).equals('1.0k');
        check(formatTokens(50500)).equals('50.5k');
      });

      test('formats small numbers without suffix', () {
        check(formatTokens(999)).equals('999');
        check(formatTokens(0)).equals('0');
        check(formatTokens(500)).equals('500');
      });
    });

    group('Renders with default (empty) tracker', () {
      testWidgets('shows zero tokens with default tracker', (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        // Default tracker has 0 current tokens and 200k max
        expect(find.textContaining('0'), findsWidgets);
        expect(find.textContaining('200.0k'), findsOneWidget);
      });

      testWidgets('shows 0% with default tracker', (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.text('0%'), findsOneWidget);
      });

      testWidgets('shows memory icon (not warning) with default tracker',
          (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.memory), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      });
    });

    group('Shows correct token count formatting', () {
      testWidgets('formats thousands with k suffix', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.textContaining('50.0k'), findsWidgets);
      });

      testWidgets('formats millions with M suffix', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateMaxTokens(2000000);
        tracker.updateFromUsage({'input_tokens': 1500000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.textContaining('1.5M'), findsWidgets);
        expect(find.textContaining('2.0M'), findsOneWidget);
      });
    });

    group('Shows correct percentage', () {
      testWidgets('shows 25% when at quarter usage', (tester) async {
        final tracker = resources.track(ContextTracker());
        // 50000 / 200000 = 25%
        tracker.updateFromUsage({'input_tokens': 50000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.text('25%'), findsOneWidget);
      });

      testWidgets('shows 50% when at half usage', (tester) async {
        final tracker = resources.track(ContextTracker());
        // 100000 / 200000 = 50%
        tracker.updateFromUsage({'input_tokens': 100000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.text('50%'), findsOneWidget);
      });

      testWidgets('shows 75% when at three quarter usage', (tester) async {
        final tracker = resources.track(ContextTracker());
        // 150000 / 200000 = 75%
        tracker.updateFromUsage({'input_tokens': 150000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.text('75%'), findsOneWidget);
      });
    });

    group('Color changes based on usage level', () {
      testWidgets('shows green when < 75% of autocompact threshold',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        // Autocompact threshold is 77.5%
        // 75% of 77.5% = 58.125%
        // So usage below 58.125% should be green
        // Use 40% = 80000 tokens
        tracker.updateFromUsage({'input_tokens': 80000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        final animation =
            progressIndicator.valueColor as AlwaysStoppedAnimation<Color>;
        check(animation.value).equals(Colors.green);
      });

      testWidgets('shows amber when 75-90% of autocompact threshold',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        // Autocompact threshold is 77.5%
        // 75% of 77.5% = 58.125%
        // 90% of 77.5% = 69.75%
        // So usage between 58.125% and 69.75% should be amber
        // Use 65% = 130000 tokens (effective: 65/77.5 = 83.9%)
        tracker.updateFromUsage({'input_tokens': 130000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        final animation =
            progressIndicator.valueColor as AlwaysStoppedAnimation<Color>;
        check(animation.value).equals(Colors.amber);
      });

      testWidgets('shows orange when 90-100% of autocompact threshold',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        // Autocompact threshold is 77.5%
        // 90% of 77.5% = 69.75%
        // So usage between 69.75% and 77.5% should be orange
        // Use 72% = 144000 tokens (effective: 72/77.5 = 92.9%)
        tracker.updateFromUsage({'input_tokens': 144000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        final animation =
            progressIndicator.valueColor as AlwaysStoppedAnimation<Color>;
        check(animation.value).equals(Colors.orange);
      });

      testWidgets('shows red when >= autocompact threshold', (tester) async {
        final tracker = resources.track(ContextTracker());
        // Use 80% = 160000 tokens (above 77.5% threshold)
        tracker.updateFromUsage({'input_tokens': 160000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        final animation =
            progressIndicator.valueColor as AlwaysStoppedAnimation<Color>;
        check(animation.value).equals(Colors.red);
      });
    });

    group('Warning icon appears when approaching threshold', () {
      testWidgets('shows memory icon when usage is low', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000}); // 25%

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.memory), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      });

      testWidgets('shows warning icon when approaching threshold (orange)',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        // 72% usage (effective 92.9% - triggers orange + warning)
        tracker.updateFromUsage({'input_tokens': 144000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(find.byIcon(Icons.memory), findsNothing);
      });

      testWidgets('shows warning icon when at threshold (red)', (tester) async {
        final tracker = resources.track(ContextTracker());
        // 80% usage (above 77.5% threshold)
        tracker.updateFromUsage({'input_tokens': 160000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(find.byIcon(Icons.memory), findsNothing);
      });

      testWidgets('warning icon has the same color as progress bar',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 160000}); // 80% - red

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final icon = tester.widget<Icon>(
          find.byIcon(Icons.warning_amber_rounded),
        );
        check(icon.color).equals(Colors.red);
      });
    });

    group('Updates when tracker changes', () {
      testWidgets('updates display when tokens change', (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        // Initially 0%
        expect(find.text('0%'), findsOneWidget);

        // Update tokens
        tracker.updateFromUsage({'input_tokens': 100000});
        await tester.pump();

        // Should now show 50%
        expect(find.text('50%'), findsOneWidget);
        expect(find.text('0%'), findsNothing);
      });

      testWidgets('updates display when max tokens change', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000}); // 25% of 200k

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.text('25%'), findsOneWidget);

        // Update max tokens to 100k (50000 / 100000 = 50%)
        tracker.updateMaxTokens(100000);
        await tester.pump();

        expect(find.text('50%'), findsOneWidget);
      });

      testWidgets('updates color when crossing threshold', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000}); // 25% - green

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        var progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        var animation =
            progressIndicator.valueColor as AlwaysStoppedAnimation<Color>;
        check(animation.value).equals(Colors.green);

        // Update to 80% - should be red
        tracker.updateFromUsage({'input_tokens': 160000});
        await tester.pump();

        progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        animation =
            progressIndicator.valueColor as AlwaysStoppedAnimation<Color>;
        check(animation.value).equals(Colors.red);
      });

      testWidgets('updates after reset', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 100000}); // 50%

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.text('50%'), findsOneWidget);

        // Reset the tracker
        tracker.reset();
        await tester.pump();

        expect(find.text('0%'), findsOneWidget);
      });
    });

    group('Tooltip contains expected information', () {
      testWidgets('tooltip has context window header', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 100000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;

        // Check that the tooltip contains the expected text
        final fullText = _extractTextFromSpan(richMessage);
        check(fullText).contains('Context Window');
      });

      testWidgets('tooltip shows current tokens', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 100000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;
        final fullText = _extractTextFromSpan(richMessage);

        check(fullText).contains('Current:');
        check(fullText).contains('100.0k');
        check(fullText).contains('50.0%');
      });

      testWidgets('tooltip shows free space', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 100000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;
        final fullText = _extractTextFromSpan(richMessage);

        check(fullText).contains('Free Space:');
      });

      testWidgets('tooltip shows autocompact buffer', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;
        final fullText = _extractTextFromSpan(richMessage);

        check(fullText).contains('Autocompact:');
        check(fullText).contains('22.5%');
      });

      testWidgets('tooltip shows max context', (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;
        final fullText = _extractTextFromSpan(richMessage);

        check(fullText).contains('Max Context:');
        check(fullText).contains('200.0k');
      });

      testWidgets('tooltip shows warning when approaching threshold',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        // 70% usage (90% of 77.5% = 69.75%, so 70% triggers warning message)
        tracker.updateFromUsage({'input_tokens': 140000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;
        final fullText = _extractTextFromSpan(richMessage);

        check(fullText).contains('Approaching autocompact threshold');
      });

      testWidgets('tooltip does not show warning when usage is low',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000}); // 25%

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;
        final fullText = _extractTextFromSpan(richMessage);

        check(fullText.contains('Approaching autocompact threshold'))
            .equals(false);
      });
    });

    group('Progress bar displays correctly', () {
      testWidgets('progress bar shows correct value', (tester) async {
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 100000}); // 50%

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        check(progressIndicator.value).isNotNull().equals(0.5);
      });

      testWidgets('progress bar value is clamped between 0 and 1',
          (tester) async {
        final tracker = resources.track(ContextTracker());
        // Set to over 100%
        tracker.updateFromUsage({'input_tokens': 250000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        check(progressIndicator.value).equals(1.0);
      });

      testWidgets('progress bar has grey background', (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        check(progressIndicator.backgroundColor).equals(Colors.grey[300]);
      });
    });

    group('Widget structure', () {
      testWidgets('has correct widget hierarchy', (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        expect(find.byType(Tooltip), findsOneWidget);
        expect(find.byType(Container), findsWidgets);
        expect(find.byType(Row), findsWidgets);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });

      testWidgets('progress bar is 40x4 pixels', (tester) async {
        final tracker = resources.track(ContextTracker());

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
        final progressBox = sizedBoxes.where(
          (box) => box.width == 40 && box.height == 4,
        );
        check(progressBox.length).equals(1);
      });
    });

    group('Edge cases', () {
      testWidgets('handles zero max tokens gracefully', (tester) async {
        final tracker = resources.track(ContextTracker());
        // Cannot set max tokens to 0 (the setter ignores non-positive values)
        // So this test verifies the default behavior works

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        // Should not crash and should show 0%
        expect(find.text('0%'), findsOneWidget);
      });

      testWidgets('handles cache tokens in usage', (tester) async {
        final tracker = resources.track(ContextTracker());
        // Total should be 10000 + 5000 + 3000 = 18000
        tracker.updateFromUsage({
          'input_tokens': 10000,
          'cache_creation_input_tokens': 5000,
          'cache_read_input_tokens': 3000,
        });

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        // 18000 / 200000 = 9%
        expect(find.text('9%'), findsOneWidget);
      });

      testWidgets('negative free space shows with minus sign', (tester) async {
        final tracker = resources.track(ContextTracker());
        // At 90% usage, free space is 10% of 200k = 20k
        // Autocompact buffer is 22.5% of 200k = 45k
        // Free space before autocompact = 20k - 45k = -25k
        tracker.updateFromUsage({'input_tokens': 180000});

        await tester.pumpWidget(createTestApp(tracker));
        await safePumpAndSettle(tester);

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        final richMessage = tooltip.richMessage as TextSpan;
        final fullText = _extractTextFromSpan(richMessage);

        // Free space should show as negative
        check(fullText).contains('-');
      });
    });
  });
}

/// Extracts all text from a TextSpan and its children.
String _extractTextFromSpan(TextSpan span) {
  final buffer = StringBuffer();
  if (span.text != null) {
    buffer.write(span.text);
  }
  if (span.children != null) {
    for (final child in span.children!) {
      if (child is TextSpan) {
        buffer.write(_extractTextFromSpan(child));
      }
    }
  }
  return buffer.toString();
}
