import 'package:cc_insights_v2/widgets/file_viewers/markdown_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../test_helpers.dart';

void main() {
  group('MarkdownViewer', () {
    Widget createTestApp(String content) {
      return MaterialApp(
        home: Scaffold(
          body: MarkdownViewer(content: content),
        ),
      );
    }

    testWidgets('renders in preview mode by default', (tester) async {
      const testContent = '# Hello\n\nThis is **markdown**.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // MarkdownBody should be present in preview mode
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('renders markdown content', (tester) async {
      const testContent = '# Title\n\nParagraph text.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.byType(MarkdownBody), findsOneWidget);

      final markdown = tester.widget<MarkdownBody>(
        find.byType(MarkdownBody),
      );
      expect(markdown.data, equals(testContent));
    });

    testWidgets('toggles to raw mode', (tester) async {
      const testContent = '# Hello\n\nThis is **markdown**.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // Initially in preview mode
      expect(find.byType(MarkdownBody), findsOneWidget);

      // Get the state and toggle
      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();

      await tester.pump();

      // Now should be in raw mode (plain Text widget)
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.text(testContent), findsOneWidget);
    });

    testWidgets('toggles back to preview mode', (tester) async {
      const testContent = '# Hello\n\nThis is **markdown**.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );

      // Toggle to raw
      state.toggleMode();
      await tester.pump();
      expect(find.byType(MarkdownBody), findsNothing);

      // Toggle back to preview
      state.toggleMode();
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('preview mode shows rendered markdown', (tester) async {
      const testContent = '# Heading\n\n**Bold** and *italic*.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // MarkdownBody renders the content
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('raw mode shows plain text', (tester) async {
      const testContent = '# Heading\n\n**Bold** and *italic*.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      // Should show exact raw text
      expect(find.text(testContent), findsOneWidget);
    });

    testWidgets('raw mode uses monospace font', (tester) async {
      const testContent = '# Heading';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text(testContent));

      // Should use monospace font
      expect(textWidget.style, isNotNull);
      expect(textWidget.style!.fontFamily, isNotNull);
      expect(textWidget.style!.fontFamily, contains('JetBrains'));
    });

    testWidgets('raw mode uses correct font size', (tester) async {
      const testContent = '# Heading';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text(testContent));

      expect(textWidget.style!.fontSize, equals(13.0));
    });

    testWidgets('raw mode uses correct line height', (tester) async {
      const testContent = '# Heading';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text(testContent));

      expect(textWidget.style!.height, equals(1.5));
    });

    testWidgets('is scrollable in both modes', (tester) async {
      const testContent = '# Heading\n\nContent.';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // Preview mode
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      // Raw mode
      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('is selectable in both modes', (tester) async {
      const testContent = '# Heading';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // Preview mode
      expect(find.byType(SelectionArea), findsOneWidget);

      // Raw mode
      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('handles empty content', (tester) async {
      await tester.pumpWidget(createTestApp(''));
      await safePumpAndSettle(tester);

      expect(find.byType(MarkdownViewer), findsOneWidget);
    });

    testWidgets('handles markdown with code blocks', (tester) async {
      const testContent = '''
# Code Example

```dart
void main() {
  print("Hello");
}
```
''';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('handles markdown with lists', (tester) async {
      const testContent = '''
# List

- Item 1
- Item 2
- Item 3
''';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('handles markdown with links', (tester) async {
      const testContent = '[Link](https://example.com)';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('handles markdown with images', (tester) async {
      const testContent = '![Alt text](https://example.com/image.png)';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('handles complex markdown', (tester) async {
      const testContent = '''
# Main Title

## Subtitle

This is a paragraph with **bold** and *italic* text.

### Code

```dart
void main() {
  print("test");
}
```

### List

1. First item
2. Second item
   - Nested item
   - Another nested

### Link

[GitHub](https://github.com)
''';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('preserves content when toggling', (tester) async {
      const testContent = '# Title\n\n**Content**';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );

      // Toggle to raw and back
      state.toggleMode();
      await tester.pump();
      state.toggleMode();
      await tester.pump();

      // Content should still be there
      final markdown = tester.widget<MarkdownBody>(
        find.byType(MarkdownBody),
      );
      expect(markdown.data, equals(testContent));
    });

    testWidgets('respects theme colors in preview mode', (tester) async {
      const testContent = '# Test';

      final testApp = MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: MarkdownViewer(content: testContent),
        ),
      );

      await tester.pumpWidget(testApp);
      await safePumpAndSettle(tester);

      final markdown = tester.widget<MarkdownBody>(
        find.byType(MarkdownBody),
      );

      expect(markdown.styleSheet?.p?.color, isNotNull);
    });

    testWidgets('respects theme colors in raw mode', (tester) async {
      const testContent = '# Test';

      final testApp = MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: MarkdownViewer(content: testContent),
        ),
      );

      await tester.pumpWidget(testApp);
      await safePumpAndSettle(tester);

      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text(testContent));

      expect(textWidget.style!.color, isNotNull);
    });

    testWidgets('has proper padding in both modes', (tester) async {
      const testContent = '# Test';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      // Preview mode
      var paddingFinder = find.ancestor(
        of: find.byType(SelectionArea),
        matching: find.byType(Padding),
      );
      expect(paddingFinder, findsOneWidget);

      var paddingWidget = tester.widget<Padding>(paddingFinder);
      expect(paddingWidget.padding, equals(const EdgeInsets.all(16)));

      // Raw mode
      final state = tester.state<MarkdownViewerState>(
        find.byType(MarkdownViewer),
      );
      state.toggleMode();
      await tester.pump();

      paddingFinder = find.ancestor(
        of: find.byType(SelectionArea),
        matching: find.byType(Padding),
      );
      expect(paddingFinder, findsOneWidget);

      paddingWidget = tester.widget<Padding>(paddingFinder);
      expect(paddingWidget.padding, equals(const EdgeInsets.all(16)));
    });

    testWidgets('preview mode uses correct font size', (tester) async {
      const testContent = '# Test';

      await tester.pumpWidget(createTestApp(testContent));
      await safePumpAndSettle(tester);

      final markdown = tester.widget<MarkdownBody>(
        find.byType(MarkdownBody),
      );

      expect(markdown.styleSheet?.p?.fontSize, equals(13.0));
    });
  });
}
