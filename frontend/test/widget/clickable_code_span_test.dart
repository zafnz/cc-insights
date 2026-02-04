import 'package:cc_insights_v2/widgets/clickable_code_span.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('looksLikeFilePath', () {
    test('returns true for paths with forward slash', () {
      expect(looksLikeFilePath('src/main.dart'), isTrue);
      expect(looksLikeFilePath('lib/widgets/tool_card.dart'), isTrue);
      expect(looksLikeFilePath('/usr/bin/bash'), isTrue);
    });

    test('returns true for tilde-prefixed paths', () {
      expect(looksLikeFilePath('~/.bashrc'), isTrue);
      expect(looksLikeFilePath('~/Documents'), isTrue);
    });

    test('returns true for Windows-style paths', () {
      expect(looksLikeFilePath(r'C:\Users\foo'), isTrue);
      expect(looksLikeFilePath(r'D:\projects\bar'), isTrue);
      expect(looksLikeFilePath(r'\Windows\System32'), isTrue);
    });

    test('returns true for dotfiles', () {
      expect(looksLikeFilePath('.gitignore'), isTrue);
      expect(looksLikeFilePath('.env'), isTrue);
      expect(looksLikeFilePath('.bashrc'), isTrue);
    });

    test('returns true for files with extensions', () {
      expect(looksLikeFilePath('test.txt'), isTrue);
      expect(looksLikeFilePath('main.dart'), isTrue);
      expect(looksLikeFilePath('foo.bar.baz'), isTrue);
      expect(looksLikeFilePath('package.json'), isTrue);
    });

    test('returns false for bare identifiers', () {
      expect(looksLikeFilePath('className'), isFalse);
      expect(looksLikeFilePath('myFunction'), isFalse);
      expect(looksLikeFilePath('some_var'), isFalse);
    });

    test('returns false for hyphenated identifiers', () {
      expect(looksLikeFilePath('test-thing'), isFalse);
      expect(looksLikeFilePath('my-component'), isFalse);
    });

    test('returns false for URLs', () {
      expect(looksLikeFilePath('https://example.com'), isFalse);
      expect(looksLikeFilePath('http://localhost:3000'), isFalse);
    });

    test('returns false for empty string', () {
      expect(looksLikeFilePath(''), isFalse);
      expect(looksLikeFilePath('   '), isFalse);
    });

    test('handles Dart package imports with slash', () {
      expect(looksLikeFilePath('package:flutter/material.dart'), isTrue);
    });
  });

  group('resolveFilePath', () {
    test('expands tilde to home directory', () {
      final result = resolveFilePath('~/file.txt', '/project');
      expect(result.startsWith('~'), isFalse);
      expect(result.endsWith('/file.txt'), isTrue);
    });

    test('returns absolute paths unchanged', () {
      expect(
        resolveFilePath('/absolute/path.txt', '/project'),
        equals('/absolute/path.txt'),
      );
    });

    test('returns Windows absolute paths unchanged', () {
      expect(
        resolveFilePath(r'C:\Users\foo', '/project'),
        equals(r'C:\Users\foo'),
      );
    });

    test('prepends projectDir for relative paths', () {
      expect(
        resolveFilePath('relative/path.txt', '/project'),
        equals('/project/relative/path.txt'),
      );
    });

    test('handles projectDir with trailing slash', () {
      expect(
        resolveFilePath('file.txt', '/project/'),
        equals('/project/file.txt'),
      );
    });

    test('returns path as-is when projectDir is null', () {
      expect(
        resolveFilePath('relative/path.txt', null),
        equals('relative/path.txt'),
      );
    });

    test('returns path as-is when projectDir is empty', () {
      expect(
        resolveFilePath('relative/path.txt', ''),
        equals('relative/path.txt'),
      );
    });
  });

  group('ClickableCodeSpan', () {
    Widget createTestApp({
      required String text,
      String? projectDir,
      Future<bool> Function(String)? fileExistsCheck,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: ClickableCodeSpan(
              text: text,
              baseStyle: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.grey,
              ),
              backgroundColor: Colors.grey.shade200,
              projectDir: projectDir,
              fileExistsCheck: fileExistsCheck,
            ),
          ),
        ),
      );
    }

    /// Finds the MouseRegion that is a descendant of ClickableCodeSpan.
    Finder findSpanMouseRegion() {
      return find.descendant(
        of: find.byType(ClickableCodeSpan),
        matching: find.byType(MouseRegion),
      );
    }

    testWidgets('renders text content', (tester) async {
      await tester.pumpWidget(createTestApp(text: 'className'));
      await safePumpAndSettle(tester);

      expect(find.text('className'), findsOneWidget);
    });

    testWidgets('uses basic cursor for non-file-path text', (tester) async {
      await tester.pumpWidget(createTestApp(text: 'className'));
      await safePumpAndSettle(tester);

      final mouseRegion = tester.widget<MouseRegion>(
        findSpanMouseRegion().first,
      );
      expect(mouseRegion.cursor, equals(SystemMouseCursors.basic));
    });

    testWidgets('checks file existence on hover for file-path text',
        (tester) async {
      bool checkCalled = false;

      await tester.pumpWidget(
        createTestApp(
          text: 'src/main.dart',
          projectDir: '/project',
          fileExistsCheck: (path) async {
            checkCalled = true;
            expect(path, equals('/project/src/main.dart'));
            return true;
          },
        ),
      );
      await safePumpAndSettle(tester);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('src/main.dart')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(checkCalled, isTrue);
      await gesture.removePointer();
    });

    testWidgets('shows click cursor when file exists', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          text: 'src/main.dart',
          projectDir: '/project',
          fileExistsCheck: (_) async => true,
        ),
      );
      await safePumpAndSettle(tester);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('src/main.dart')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final mouseRegion = tester.widget<MouseRegion>(
        findSpanMouseRegion().first,
      );
      expect(mouseRegion.cursor, equals(SystemMouseCursors.click));
      await gesture.removePointer();
    });

    testWidgets('shows basic cursor when file does not exist',
        (tester) async {
      await tester.pumpWidget(
        createTestApp(
          text: 'src/main.dart',
          projectDir: '/project',
          fileExistsCheck: (_) async => false,
        ),
      );
      await safePumpAndSettle(tester);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('src/main.dart')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final mouseRegion = tester.widget<MouseRegion>(
        findSpanMouseRegion().first,
      );
      expect(mouseRegion.cursor, equals(SystemMouseCursors.basic));
      await gesture.removePointer();
    });

    testWidgets('does not check file existence for non-file text',
        (tester) async {
      bool checkCalled = false;

      await tester.pumpWidget(
        createTestApp(
          text: 'className',
          projectDir: '/project',
          fileExistsCheck: (_) async {
            checkCalled = true;
            return true;
          },
        ),
      );
      await safePumpAndSettle(tester);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('className')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(checkCalled, isFalse);
      await gesture.removePointer();
    });

    testWidgets('caches file existence check across hovers', (tester) async {
      int checkCount = 0;

      await tester.pumpWidget(
        createTestApp(
          text: 'src/main.dart',
          projectDir: '/project',
          fileExistsCheck: (_) async {
            checkCount++;
            return true;
          },
        ),
      );
      await safePumpAndSettle(tester);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      // First hover
      await gesture.moveTo(tester.getCenter(find.text('src/main.dart')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Move away
      await gesture.moveTo(Offset.zero);
      await tester.pump();

      // Second hover
      await gesture.moveTo(tester.getCenter(find.text('src/main.dart')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should only have checked once
      expect(checkCount, equals(1));
      await gesture.removePointer();
    });
  });
}
