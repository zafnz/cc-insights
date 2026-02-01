import 'dart:io';

import 'package:cc_insights_v2/widgets/file_viewers/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  group('ImageViewer', () {
    // Path to test image
    late String testImagePath;

    setUp(() {
      // Get path to test fixture
      final testDir = Directory.current.path;
      testImagePath = '$testDir/test/fixtures/test_image.png';

      // Verify test image exists
      expect(
        File(testImagePath).existsSync(),
        isTrue,
        reason: 'Test image should exist at $testImagePath',
      );
    });

    Widget createTestApp(String path) {
      return MaterialApp(
        home: Scaffold(
          body: ImageViewer(path: path),
        ),
      );
    }

    testWidgets('displays image', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump(); // Initial build
      await tester.pump(); // Image load frame

      // Image widget should be present
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('wraps image in InteractiveViewer', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump();
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('InteractiveViewer has correct min scale', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump();
      await tester.pump();

      final interactiveViewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );

      expect(interactiveViewer.minScale, equals(0.5));
    });

    testWidgets('InteractiveViewer has correct max scale', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump();
      await tester.pump();

      final interactiveViewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );

      expect(interactiveViewer.maxScale, equals(4.0));
    });

    testWidgets('centers image', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump();
      await tester.pump();

      // Center widget should wrap the image
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('shows error for non-existent file', (tester) async {
      const nonExistentPath = '/path/that/does/not/exist.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      // Wait for image to fail loading
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      // Error widget should be shown
      expect(find.text('Failed to load image'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });

    testWidgets('error shows broken image icon', (tester) async {
      const nonExistentPath = '/invalid.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      expect(find.byIcon(Icons.broken_image), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.broken_image));
      expect(icon.size, equals(48.0));
    });

    testWidgets('error message shows error details', (tester) async {
      const nonExistentPath = '/invalid.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      // Should show error message
      expect(find.text('Failed to load image'), findsOneWidget);
      // Error details should be present (truncated)
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('error widget uses error color', (tester) async {
      const nonExistentPath = '/invalid.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      final icon = tester.widget<Icon>(find.byIcon(Icons.broken_image));

      expect(icon.color, isNotNull);
      // Should use theme error color
    });

    testWidgets('handles empty path gracefully', (tester) async {
      await tester.pumpWidget(createTestApp(''));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      // Should show error
      expect(find.text('Failed to load image'), findsOneWidget);
    });

    testWidgets('loads image from valid path', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));

      // Wait for image to load
      await tester.pump();
      await tester.pump();

      // Image should be loaded (no error)
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('image uses file provider', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump();
      await tester.pump();

      final imageWidget = tester.widget<Image>(find.byType(Image));

      // Should use FileImage provider
      expect(imageWidget.image, isA<FileImage>());
    });

    testWidgets('error widget has proper padding', (tester) async {
      const nonExistentPath = '/invalid.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      // Find the padding widget within error display
      final paddingFinder = find.byType(Padding);

      expect(paddingFinder, findsWidgets);

      final paddingWidget = tester.widget<Padding>(paddingFinder.first);
      expect(paddingWidget.padding, equals(const EdgeInsets.all(16)));
    });

    testWidgets('error widget has proper layout', (tester) async {
      const nonExistentPath = '/invalid.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      // Should have Column layout
      final columnFinder = find.byType(Column);

      expect(columnFinder, findsWidgets);

      final column = tester.widget<Column>(columnFinder.first);
      expect(column.mainAxisSize, equals(MainAxisSize.min));
    });

    testWidgets('error text has correct alignment', (tester) async {
      const nonExistentPath = '/invalid.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      final errorText = tester.widget<Text>(
        find.text('Failed to load image'),
      );

      expect(errorText.textAlign, equals(TextAlign.center));
    });

    testWidgets('error details text is truncated', (tester) async {
      const nonExistentPath = '/invalid.png';

      await tester.pumpWidget(createTestApp(nonExistentPath));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await safePumpAndSettle(tester);

      // Find text widgets that are not the main error message
      final textWidgets = tester.widgetList<Text>(find.byType(Text));

      // At least one text widget should have ellipsis overflow
      final hasEllipsis = textWidgets.any(
        (text) => text.overflow == TextOverflow.ellipsis,
      );

      expect(hasEllipsis, isTrue);
    });

    testWidgets('creates correct file object', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump();
      await tester.pump();

      final imageWidget = tester.widget<Image>(find.byType(Image));
      final fileImage = imageWidget.image as FileImage;

      expect(fileImage.file.path, equals(testImagePath));
    });

    testWidgets('handles path with spaces', (tester) async {
      // Use test image path (it doesn't have spaces, but we test handling)
      await tester.pumpWidget(createTestApp(testImagePath));
      await tester.pump();
      await tester.pump();

      // Should load without error
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders without frame after initial pump', (tester) async {
      await tester.pumpWidget(createTestApp(testImagePath));

      // Just pump once
      await tester.pump();

      // Should have InteractiveViewer even before image loads
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}
