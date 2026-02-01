import 'package:cc_insights_v2/widgets/file_viewers/plaintext_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_helpers.dart';

void main() {
  group('PlaintextFileViewer', () {
    Widget createTestApp(String content) {
      return MaterialApp(
        home: Scaffold(
          body: PlaintextFileViewer(content: content),
        ),
      );
    }

    testWidgets('renders text content', (tester) async {
      const testContent = 'Hello, World!\nThis is a test.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.text(testContent), findsOneWidget);
    });

    testWidgets('text is selectable', (tester) async {
      const testContent = 'Selectable text';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // SelectionArea should be present
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('uses monospace font', (tester) async {
      const testContent = 'Monospace text';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // Find the Text widget
      final textWidget = tester.widget<Text>(find.text(testContent));

      // Verify it uses GoogleFonts (monospace)
      expect(textWidget.style, isNotNull);
      expect(textWidget.style!.fontFamily, isNotNull);
      // GoogleFonts generates a unique font family name
      expect(textWidget.style!.fontFamily, contains('JetBrains'));
    });

    testWidgets('uses correct font size', (tester) async {
      const testContent = 'Font size test';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final textWidget = tester.widget<Text>(find.text(testContent));

      expect(textWidget.style!.fontSize, equals(13.0));
    });

    testWidgets('uses correct line height', (tester) async {
      const testContent = 'Line height test';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final textWidget = tester.widget<Text>(find.text(testContent));

      expect(textWidget.style!.height, equals(1.5));
    });

    testWidgets('is scrollable', (tester) async {
      const testContent = 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // SingleChildScrollView should be present
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('scrolls for long content', (tester) async {
      // Create a very long text that would exceed screen height
      final longContent = List.generate(100, (i) => 'Line $i').join('\n');

      await tester.pumpWidget(createTestApp(longContent));
      await safePumpAndSettle(tester);

      // Verify first and last lines exist in widget tree
      expect(find.text(longContent), findsOneWidget);
    });

    testWidgets('handles empty content', (tester) async {
      await tester.pumpWidget(createTestApp(''));
      await safePumpAndSettle(tester);

      // Should render without error
      expect(find.byType(PlaintextFileViewer), findsOneWidget);
    });

    testWidgets('handles multiline content', (tester) async {
      const testContent = 'Line 1\nLine 2\nLine 3';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.text(testContent), findsOneWidget);
    });

    testWidgets('handles special characters', (tester) async {
      const testContent = 'Special: <>&"\'\t\n\r';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.text(testContent), findsOneWidget);
    });

    testWidgets('handles unicode characters', (tester) async {
      const testContent = 'Unicode: 你好 🌍 café';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.text(testContent), findsOneWidget);
    });

    testWidgets('respects theme colors', (tester) async {
      const testContent = 'Theme test';

      // Create a custom theme
      final testApp = MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: PlaintextFileViewer(content: testContent),
        ),
      );

      await tester.pumpWidget(testApp);
      await safePumpAndSettle(tester);

      final textWidget = tester.widget<Text>(find.text(testContent));

      // Should use theme's onSurface color
      expect(textWidget.style!.color, isNotNull);
    });

    testWidgets('has proper padding', (tester) async {
      const testContent = 'Padding test';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // Find the Padding widget
      final paddingFinder = find.ancestor(
        of: find.byType(SelectionArea),
        matching: find.byType(Padding),
      );

      expect(paddingFinder, findsOneWidget);

      final paddingWidget = tester.widget<Padding>(paddingFinder);
      expect(paddingWidget.padding, equals(const EdgeInsets.all(16)));
    });
  });
}
