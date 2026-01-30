import 'dart:typed_data';

import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/widgets/output_entries/user_input_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  // Minimal valid PNG (1x1 pixel) - using a valid PNG structure
  final testPngBytes = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 pixels
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
    0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
    0x00, 0x05, 0xFE, 0x02, 0xFE, 0xDC, 0xCC, 0x59,
    0xE7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  Widget createTestApp({required UserInputEntry entry}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UserInputEntryWidget(entry: entry),
        ),
      ),
    );
  }

  group('UserInputEntryWidget', () {
    group('text display', () {
      testWidgets('displays text content', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Hello, Claude!',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.text('Hello, Claude!'), findsOneWidget);
      });

      testWidgets('displays empty text', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: '',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.byType(UserInputEntryWidget), findsOneWidget);
      });

      testWidgets('displays multi-line text', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Line 1\nLine 2\nLine 3',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.textContaining('Line 1'), findsOneWidget);
        expect(find.textContaining('Line 2'), findsOneWidget);
        expect(find.textContaining('Line 3'), findsOneWidget);
      });

      testWidgets('displays user icon', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Test message',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.byIcon(Icons.person_outline), findsOneWidget);
      });

      testWidgets('text is selectable', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Selectable text',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.byType(SelectableText), findsOneWidget);
      });
    });

    group('image display', () {
      testWidgets('does not show image section when no images', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Text only message',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        // Should not find Image.memory widgets
        expect(find.byType(Image), findsNothing);
        // Should not find Wrap widget (used for image layout)
        // Verify there's no extra spacing for images
        final wrapFinder = find.byType(Wrap);
        expect(wrapFinder, findsNothing);
      });

      testWidgets('displays single image with text', (tester) async {
        // Arrange
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Check this image',
          images: [image],
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.text('Check this image'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
      });

      testWidgets('displays multiple images', (tester) async {
        // Arrange
        final image1 = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );
        final image2 = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );
        final image3 = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Multiple images',
          images: [image1, image2, image3],
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.byType(Image), findsNWidgets(3));
      });

      testWidgets('images are wrapped in ClipRRect for rounded corners',
          (tester) async {
        // Arrange
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Image with rounded corners',
          images: [image],
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.byType(ClipRRect), findsWidgets);
      });

      testWidgets('images use Wrap for layout', (tester) async {
        // Arrange
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Image in wrap',
          images: [image],
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.byType(Wrap), findsOneWidget);
      });

      testWidgets('displays text and images together', (tester) async {
        // Arrange
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Here is an image:',
          images: [image],
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        expect(find.text('Here is an image:'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        // Verify the Column layout contains both
        expect(find.byType(Column), findsWidgets);
      });
    });

    group('styling', () {
      testWidgets('has correct background color', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Styled message',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert - find the container with the user message styling
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            // Check for the user message purple color
            return decoration.color == const Color(0xFF3D2A54);
          }
          return false;
        });
        expect(containers.isNotEmpty, isTrue);
      });

      testWidgets('has rounded corners', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Rounded message',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            return decoration.borderRadius != null;
          }
          return false;
        });
        expect(containers.isNotEmpty, isTrue);
      });

      testWidgets('has bottom margin', (tester) async {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Margined message',
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
          final margin = container.margin;
          if (margin is EdgeInsets) {
            return margin.bottom > 0;
          }
          return false;
        });
        expect(containers.isNotEmpty, isTrue);
      });
    });

    group('error handling', () {
      testWidgets('shows broken image icon for invalid image data',
          (tester) async {
        // Arrange - use invalid image data
        final invalidImage = AttachedImage(
          data: Uint8List.fromList([0, 1, 2, 3]),
          mediaType: 'image/png',
        );
        final entry = UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Invalid image',
          images: [invalidImage],
        );

        // Act
        await tester.pumpWidget(createTestApp(entry: entry));
        await safePumpAndSettle(tester);

        // Assert - should show broken image icon as fallback
        expect(find.byIcon(Icons.broken_image), findsOneWidget);
      });
    });
  });
}
