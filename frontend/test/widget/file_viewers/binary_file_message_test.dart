import 'dart:typed_data';

import 'package:cc_insights_v2/models/file_content.dart';
import 'package:cc_insights_v2/widgets/file_viewers/binary_file_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  group('BinaryFileMessage', () {
    Widget createTestApp(FileContent file) {
      return MaterialApp(
        home: Scaffold(
          body: BinaryFileMessage(file: file),
        ),
      );
    }

    FileContent createBinaryFile({
      required String path,
      required int byteCount,
    }) {
      return FileContent.binary(
        path: path,
        bytes: Uint8List(byteCount),
      );
    }

    testWidgets('renders message', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('Cannot display binary file'), findsOneWidget);
    });

    testWidgets('shows file icon', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    });

    testWidgets('icon has correct size', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.insert_drive_file),
      );

      expect(icon.size, equals(48.0));
    });

    testWidgets('displays file name', (tester) async {
      final file = createBinaryFile(
        path: '/test/path/myfile.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('myfile.bin'), findsOneWidget);
    });

    testWidgets('displays file size in bytes', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 500,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('500 B'), findsOneWidget);
    });

    testWidgets('displays file size in KB', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1536, // 1.5 KB
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('1.5 KB'), findsOneWidget);
    });

    testWidgets('displays file size in MB', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 2 * 1024 * 1024, // 2 MB
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('2.0 MB'), findsOneWidget);
    });

    testWidgets('displays file size in GB', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 3 * 1024 * 1024 * 1024, // 3 GB
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('3.0 GB'), findsOneWidget);
    });

    testWidgets('formats decimal places correctly', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1234, // 1.2 KB (rounded)
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Should show 1 decimal place
      expect(find.text('1.2 KB'), findsOneWidget);
    });

    testWidgets('displays file type/extension', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('BIN'), findsOneWidget);
    });

    testWidgets('displays uppercase extension', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.exe',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('EXE'), findsOneWidget);
    });

    testWidgets('handles file without extension', (tester) async {
      final file = createBinaryFile(
        path: '/test/file',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Type row should not be shown
      expect(find.text('Type: '), findsNothing);
    });

    testWidgets('handles extension with dot at end', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Type row should not be shown
      expect(find.text('Type: '), findsNothing);
    });

    testWidgets('shows file info labels', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Labels are in separate Text widgets with ': ' suffix
      expect(find.text('File: '), findsOneWidget);
      expect(find.text('Size: '), findsOneWidget);
      expect(find.text('Type: '), findsOneWidget);
    });

    testWidgets('is centered', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Center widget is at the top level
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('has proper padding', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      final paddingFinder = find.descendant(
        of: find.byType(Center),
        matching: find.byType(Padding),
      );

      expect(paddingFinder, findsOneWidget);

      final paddingWidget = tester.widget<Padding>(paddingFinder);
      expect(paddingWidget.padding, equals(const EdgeInsets.all(16)));
    });

    testWidgets('has proper layout structure', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Should have Column layout
      final columnFinder = find.descendant(
        of: find.byType(BinaryFileMessage),
        matching: find.byType(Column),
      );

      expect(columnFinder, findsWidgets);
    });

    testWidgets('uses muted colors for icon', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.insert_drive_file),
      );

      // Icon should have muted color with opacity
      expect(icon.color, isNotNull);
    });

    testWidgets('uses muted colors for text', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Message text should use onSurfaceVariant
      final messageText = tester.widget<Text>(
        find.text('Cannot display binary file'),
      );

      expect(messageText.style, isNotNull);
      expect(messageText.style!.color, isNotNull);
    });

    testWidgets('handles null binary content', (tester) async {
      const file = FileContent(
        path: '/test/file.bin',
        type: FileContentType.binary,
        data: null,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Should show "Unknown" size
      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('handles zero-byte file', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 0,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('0 B'), findsOneWidget);
    });

    testWidgets('handles large file sizes correctly', (tester) async {
      final file = createBinaryFile(
        path: '/test/large.bin',
        byteCount: 1536 * 1024 * 1024, // 1.5 GB
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      expect(find.text('1.5 GB'), findsOneWidget);
    });

    testWidgets('handles file with multiple dots in name', (tester) async {
      final file = createBinaryFile(
        path: '/test/my.file.tar.gz',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Should extract last extension
      expect(find.text('GZ'), findsOneWidget);
      expect(find.text('my.file.tar.gz'), findsOneWidget);
    });

    testWidgets('info rows have correct alignment', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Find Row widgets in info section
      final rowFinder = find.descendant(
        of: find.byType(BinaryFileMessage),
        matching: find.byType(Row),
      );

      expect(rowFinder, findsWidgets);

      // All info rows should have min size
      for (final row in tester.widgetList<Row>(rowFinder)) {
        expect(row.mainAxisSize, equals(MainAxisSize.min));
      }
    });

    testWidgets('respects theme in light mode', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      final testApp = MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: BinaryFileMessage(file: file),
        ),
      );

      await tester.pumpWidget(testApp);
      await safePumpAndSettle(tester);

      // Should render without error
      expect(find.byType(BinaryFileMessage), findsOneWidget);
    });

    testWidgets('respects theme in dark mode', (tester) async {
      final file = createBinaryFile(
        path: '/test/file.bin',
        byteCount: 1024,
      );

      final testApp = MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: BinaryFileMessage(file: file),
        ),
      );

      await tester.pumpWidget(testApp);
      await safePumpAndSettle(tester);

      // Should render without error
      expect(find.byType(BinaryFileMessage), findsOneWidget);
    });

    testWidgets('file name extracts correctly from path', (tester) async {
      final file = createBinaryFile(
        path: '/very/long/path/to/myfile.exe',
        byteCount: 1024,
      );

      await tester.pumpWidget(createTestApp(file));
      await safePumpAndSettle(tester);

      // Should show only filename, not full path
      expect(find.text('myfile.exe'), findsOneWidget);
      expect(
        find.text('/very/long/path/to/myfile.exe'),
        findsNothing,
      );
    });
  });
}
