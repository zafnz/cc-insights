import 'package:cc_insights_v2/widgets/file_viewers/source_code_viewer.dart';
import 'package:code_highlight_view/code_highlight_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  group('SourceCodeViewer', () {
    Widget createTestApp({
      required String content,
      required String language,
      Brightness brightness = Brightness.light,
    }) {
      return MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: SourceCodeViewer(
            content: content,
            language: language,
          ),
        ),
      );
    }

    testWidgets('renders CodeHighlightView', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('renders Dart code', (tester) async {
      const testContent = 'void main() {\n  print("Hello");\n}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('renders JSON code', (tester) async {
      const testContent = '{"key": "value"}';
      const testLanguage = 'json';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('renders YAML code', (tester) async {
      const testContent = 'key: value\nlist:\n  - item1\n  - item2';
      const testLanguage = 'yaml';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('renders JavaScript code', (tester) async {
      const testContent = 'function hello() {\n  console.log("Hi");\n}';
      const testLanguage = 'javascript';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('renders Python code', (tester) async {
      const testContent = 'def hello():\n    print("Hello")';
      const testLanguage = 'python';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
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
      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('passes content to CodeHighlightView', (tester) async {
      const testContent = 'print("test")';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // Verify CodeHighlightView is rendered with the content
      expect(find.byType(CodeHighlightView), findsOneWidget);
      // The content should be visible in the rendered text
      expect(find.textContaining('print'), findsOneWidget);
    });

    testWidgets('is scrollable', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

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
      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('handles empty content', (tester) async {
      const testContent = '';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
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

      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('handles special characters in code', (tester) async {
      const testContent = 'String s = "Special: <>&";';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      expect(find.byType(CodeHighlightView), findsOneWidget);
    });

    testWidgets('is selectable', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      // CodeHighlightView has isSelectable: true
      final highlighter = tester.widget<CodeHighlightView>(
        find.byType(CodeHighlightView),
      );
      expect(highlighter.isSelectable, isTrue);
    });

    testWidgets('uses correct font settings', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      final highlighter = tester.widget<CodeHighlightView>(
        find.byType(CodeHighlightView),
      );

      expect(highlighter.textStyle.fontSize, equals(13.0));
      expect(highlighter.textStyle.fontFamily, equals('JetBrains Mono'));
    });

    testWidgets('uses light theme for light mode', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
        brightness: Brightness.light,
      ));
      await safePumpAndSettle(tester);

      final highlighter = tester.widget<CodeHighlightView>(
        find.byType(CodeHighlightView),
      );

      // Theme should be set (not null)
      expect(highlighter.theme, isNotNull);
    });

    testWidgets('uses dark theme for dark mode', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
        brightness: Brightness.dark,
      ));
      await safePumpAndSettle(tester);

      final highlighter = tester.widget<CodeHighlightView>(
        find.byType(CodeHighlightView),
      );

      // Theme should be set (not null)
      expect(highlighter.theme, isNotNull);
    });

    testWidgets('has proper padding', (tester) async {
      const testContent = 'void main() {}';
      const testLanguage = 'dart';

      await tester.pumpWidget(createTestApp(
        content: testContent,
        language: testLanguage,
      ));
      await safePumpAndSettle(tester);

      final highlighter = tester.widget<CodeHighlightView>(
        find.byType(CodeHighlightView),
      );

      expect(highlighter.padding, equals(const EdgeInsets.all(16)));
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
      expect(find.byType(CodeHighlightView), findsOneWidget);
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
      expect(find.byType(CodeHighlightView), findsOneWidget);
    });
  });
}
