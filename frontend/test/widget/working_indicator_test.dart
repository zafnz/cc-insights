import 'package:cc_insights_v2/widgets/output_entries/working_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  group('WorkingIndicator', () {
    Widget buildTestWidget({String agentName = 'Claude'}) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: WorkingIndicator(agentName: agentName),
        ),
      );
    }

    testWidgets('renders container with correct key', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(WorkingIndicatorKeys.container), findsOneWidget);
    });

    testWidgets('renders spinner', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(WorkingIndicatorKeys.spinner), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(WorkingIndicatorKeys.label), findsOneWidget);
      expect(find.text('Claude is working...'), findsOneWidget);
    });

    testWidgets('spinner uses primary color', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );

      // Verify the color is set (will use theme's primary color)
      expect(indicator.color, isNotNull);
    });

    testWidgets('label text has italic style', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final textWidget = tester.widget<Text>(
        find.byKey(WorkingIndicatorKeys.label),
      );

      expect(textWidget.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('shows "Compacting context..." when isCompacting is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: WorkingIndicator(isCompacting: true),
          ),
        ),
      );

      expect(find.text('Compacting context...'), findsOneWidget);
      expect(find.text('Claude is working...'), findsNothing);
    });

    testWidgets('shows "Claude is working..." when isCompacting is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: WorkingIndicator(isCompacting: false),
          ),
        ),
      );

      expect(find.text('Claude is working...'), findsOneWidget);
      expect(find.text('Compacting context...'), findsNothing);
    });

    testWidgets('shows "Codex is working..." when agentName is Codex',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(agentName: 'Codex'));

      expect(find.text('Codex is working...'), findsOneWidget);
      expect(find.text('Claude is working...'), findsNothing);
    });
  });
}
