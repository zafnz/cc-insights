import 'package:cc_insights_v2/widgets/file_viewers/source_code_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../test_helpers.dart';

void main() {
  group('SourceCodeViewer', () {
    Widget createTestApp({
      required String content,
      required String language,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SourceCodeViewer(
            content: content,
            language: language,
          ),
        ),
      );
    }

    testWidgets('renders GptMarkdown', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('renders Dart code', (tester) async {
      const testContent = 'void main() {\n  print("Hello");\n}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // GptMarkdown should be present
      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('renders JSON code', (tester) async {
      const testContent = '{"key": "value"}';
      const testLanguage = 'json';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('renders YAML code', (tester) async {
      const testContent = 'key: value\nlist:\n  - item1\n  - item2';
      const testLanguage = 'yaml';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('renders JavaScript code', (tester) async {
      const testContent = 'function hello() {\n  console.log("Hi");\n}';
      const testLanguage = 'javascript';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('renders Python code', (tester) async {
      const testContent = 'def hello():\n    print("Hello")';
      const testLanguage = 'python';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('renders unknown language', (tester) async {
      const testContent = 'Some code';
      const testLanguage = 'unknown';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // Should still render without error
      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('wraps content in code fence', (tester) async {
      const testContent = 'print("test")';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // GptMarkdown receives wrapped content
      final markdown = tester.widget<GptMarkdown>(
        find.byType(GptMarkdown),
      );

      expect(markdown.data, equals('```$testLanguage\n$testContent\n```'));
    });

    testWidgets('is scrollable', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // Should have scroll view (GptMarkdown may add its own)
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('scrolls for long files', (tester) async {
      // Create a long code file
      final longContent = List.generate(
        50,
        (i) => 'void function$i() { print("$i"); }',
      ).join('\n');
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: longContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // Should render without error
      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('handles empty content', (tester) async {
      const testContent = '';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('handles multiline code', (tester) async {
      const testContent = '''
class MyClass {
  void method() {
    print("test");
  }
}''';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('handles special characters in code', (tester) async {
      const testContent = 'String s = "Special: <>&";';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('is selectable', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('uses correct font size', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      final markdown = tester.widget<GptMarkdown>(
        find.byType(GptMarkdown),
      );

      expect(markdown.style?.fontSize, equals(13.0));
    });

    testWidgets('respects theme colors', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      final testApp = MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: SourceCodeViewer(
            content: testContent,
            language: testLanguage,
          ),
        ),
      );

      await tester.pumpWidget(testApp);
      await safePumpAndSettle(tester);

      final markdown = tester.widget<GptMarkdown>(
        find.byType(GptMarkdown),
      );

      expect(markdown.style?.color, isNotNull);
    });

    testWidgets('has proper padding', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      final paddingFinder = find.ancestor(
        of: find.byType(SelectionArea),
        matching: find.byType(Padding),
      );

      expect(paddingFinder, findsOneWidget);

      final paddingWidget = tester.widget<Padding>(paddingFinder);
      expect(paddingWidget.padding, equals(const EdgeInsets.all(16)));
    });

    testWidgets('handles code with backticks', (tester) async {
      const testContent = 'String code = "`backticks`";';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // Should render without error
      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('handles code with triple backticks', (tester) async {
      const testContent = 'String md = "```dart\\ncode\\n```";';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // Should render without error
      expect(find.byType(GptMarkdown), findsOneWidget);
    });
  });
}
