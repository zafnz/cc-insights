import 'dart:convert';

import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:checks/checks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Minimal valid PNG (1x1 transparent pixel)
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

  group('AttachedImage', () {
    group('creation', () {
      test('creates correctly with data and mediaType', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        const mediaType = 'image/png';

        // Act
        final image = AttachedImage(data: data, mediaType: mediaType);

        // Assert
        check(image.data).deepEquals(data);
        check(image.mediaType).equals(mediaType);
      });

      test('creates with valid PNG data', () {
        // Arrange & Act
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );

        // Assert
        check(image.data.length).equals(testPngBytes.length);
        check(image.mediaType).equals('image/png');
      });

      test('creates with different media types', () {
        // Arrange
        final data = Uint8List.fromList([0xFF, 0xD8, 0xFF]);

        // Act & Assert
        final jpegImage = AttachedImage(data: data, mediaType: 'image/jpeg');
        check(jpegImage.mediaType).equals('image/jpeg');

        final gifImage = AttachedImage(data: data, mediaType: 'image/gif');
        check(gifImage.mediaType).equals('image/gif');

        final webpImage = AttachedImage(data: data, mediaType: 'image/webp');
        check(webpImage.mediaType).equals('image/webp');
      });
    });

    group('base64 encoding', () {
      test('returns correct base64 encoding', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final image = AttachedImage(data: data, mediaType: 'image/png');

        // Act
        final base64Result = image.base64;

        // Assert
        check(base64Result).equals(base64Encode(data));
        // Verify it decodes back correctly
        check(base64Decode(base64Result)).deepEquals(data);
      });

      test('handles empty data', () {
        // Arrange
        final data = Uint8List(0);
        final image = AttachedImage(data: data, mediaType: 'image/png');

        // Act
        final base64Result = image.base64;

        // Assert
        check(base64Result).equals('');
      });

      test('encodes PNG data correctly', () {
        // Arrange
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );

        // Act
        final base64Result = image.base64;

        // Assert
        // Verify it's valid base64 that decodes back to original
        final decoded = base64Decode(base64Result);
        check(decoded).deepEquals(testPngBytes);
      });

      test('produces consistent base64 for same data', () {
        // Arrange
        final data = Uint8List.fromList([10, 20, 30, 40, 50]);
        final image = AttachedImage(data: data, mediaType: 'image/jpeg');

        // Act
        final base64First = image.base64;
        final base64Second = image.base64;

        // Assert
        check(base64First).equals(base64Second);
      });
    });

    group('JSON serialization', () {
      test('toJson produces correct structure', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3]);
        final image = AttachedImage(data: data, mediaType: 'image/png');

        // Act
        final json = image.toJson();

        // Assert
        check(json['data']).equals(base64Encode(data));
        check(json['media_type']).equals('image/png');
        check(json.length).equals(2);
      });

      test('fromJson restores image correctly', () {
        // Arrange
        final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final json = {
          'data': base64Encode(originalData),
          'media_type': 'image/jpeg',
        };

        // Act
        final image = AttachedImage.fromJson(json);

        // Assert
        check(image.data).deepEquals(originalData);
        check(image.mediaType).equals('image/jpeg');
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = AttachedImage.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.data).deepEquals(original.data);
        check(restored.mediaType).equals(original.mediaType);
      });

      test('round-trip with complex data', () {
        // Arrange - use bytes that might be problematic in JSON
        final data = Uint8List.fromList([0, 127, 128, 255, 0, 1, 254]);
        final original = AttachedImage(data: data, mediaType: 'image/webp');

        // Act
        final json = jsonEncode(original.toJson());
        final restored = AttachedImage.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.data).deepEquals(original.data);
        check(restored.mediaType).equals(original.mediaType);
      });
    });

    group('equality', () {
      test('equals returns true for identical images', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final image1 = AttachedImage(data: data, mediaType: 'image/png');
        final image2 = AttachedImage(
          data: Uint8List.fromList([1, 2, 3, 4, 5]),
          mediaType: 'image/png',
        );

        // Act & Assert
        check(image1 == image2).isTrue();
        check(image1.hashCode).equals(image2.hashCode);
      });

      test('equals returns false for different data', () {
        // Arrange
        final image1 = AttachedImage(
          data: Uint8List.fromList([1, 2, 3]),
          mediaType: 'image/png',
        );
        final image2 = AttachedImage(
          data: Uint8List.fromList([1, 2, 4]),
          mediaType: 'image/png',
        );

        // Act & Assert
        check(image1 == image2).isFalse();
      });

      test('equals returns false for different media types', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3]);
        final image1 = AttachedImage(data: data, mediaType: 'image/png');
        final image2 = AttachedImage(data: data, mediaType: 'image/jpeg');

        // Act & Assert
        check(image1 == image2).isFalse();
      });

      test('equals returns true for same instance', () {
        // Arrange
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );

        // Act & Assert
        check(image == image).isTrue();
      });

      test('equals returns false for different types', () {
        // Arrange
        final image = AttachedImage(
          data: Uint8List.fromList([1, 2, 3]),
          mediaType: 'image/png',
        );

        // Act & Assert
        // ignore: unrelated_type_equality_checks
        check(image == 'not an image').isFalse();
        // The image object is never null, so we just verify it's not equal to strings
        check(image).isNotNull();
      });
    });

    group('toString', () {
      test('includes mediaType and size', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final image = AttachedImage(data: data, mediaType: 'image/png');

        // Act
        final str = image.toString();

        // Assert
        check(str).contains('AttachedImage');
        check(str).contains('image/png');
        check(str).contains('5 bytes');
      });

      test('shows correct size for larger images', () {
        // Arrange
        final image = AttachedImage(
          data: testPngBytes,
          mediaType: 'image/png',
        );

        // Act
        final str = image.toString();

        // Assert
        check(str).contains('${testPngBytes.length} bytes');
      });
    });
  });

  group('UserInputEntry with images', () {
    test('creates with empty images by default', () {
      // Arrange & Act
      final entry = UserInputEntry(
        timestamp: DateTime.now(),
        text: 'Hello',
      );

      // Assert
      check(entry.images).isEmpty();
    });

    test('creates with images list', () {
      // Arrange
      final image = AttachedImage(
        data: testPngBytes,
        mediaType: 'image/png',
      );

      // Act
      final entry = UserInputEntry(
        timestamp: DateTime.now(),
        text: 'Check this image',
        images: [image],
      );

      // Assert
      check(entry.images.length).equals(1);
      check(entry.images.first.mediaType).equals('image/png');
    });

    test('creates with multiple images', () {
      // Arrange
      final image1 = AttachedImage(
        data: Uint8List.fromList([1, 2, 3]),
        mediaType: 'image/png',
      );
      final image2 = AttachedImage(
        data: Uint8List.fromList([4, 5, 6]),
        mediaType: 'image/jpeg',
      );

      // Act
      final entry = UserInputEntry(
        timestamp: DateTime.now(),
        text: 'Multiple images',
        images: [image1, image2],
      );

      // Assert
      check(entry.images.length).equals(2);
    });

    group('JSON serialization with images', () {
      test('toJson includes images array', () {
        // Arrange
        final image = AttachedImage(
          data: Uint8List.fromList([1, 2, 3]),
          mediaType: 'image/png',
        );
        final entry = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Test',
          images: [image],
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('user');
        check(json['text']).equals('Test');
        check(json.containsKey('images')).isTrue();
        final imagesList = json['images'] as List;
        check(imagesList.length).equals(1);
      });

      test('toJson omits images key when empty', () {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'No images',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json.containsKey('images')).isFalse();
      });

      test('fromJson restores images correctly', () {
        // Arrange
        final imageData = Uint8List.fromList([1, 2, 3]);
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'With image',
          'images': [
            {
              'data': base64Encode(imageData),
              'media_type': 'image/png',
            },
          ],
        };

        // Act
        final entry = UserInputEntry.fromJson(json);

        // Assert
        check(entry.images.length).equals(1);
        check(entry.images.first.data).deepEquals(imageData);
        check(entry.images.first.mediaType).equals('image/png');
      });

      test('fromJson handles missing images key', () {
        // Arrange
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'No images',
        };

        // Act
        final entry = UserInputEntry.fromJson(json);

        // Assert
        check(entry.images).isEmpty();
      });

      test('round-trip preserves images', () {
        // Arrange
        final original = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Image test',
          images: [
            AttachedImage(
              data: testPngBytes,
              mediaType: 'image/png',
            ),
          ],
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = UserInputEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.text).equals(original.text);
        check(restored.images.length).equals(1);
        check(restored.images.first.data).deepEquals(original.images.first.data);
        check(restored.images.first.mediaType)
            .equals(original.images.first.mediaType);
      });
    });

    group('equality with images', () {
      test('equals returns true when images match', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3]);
        final entry1 = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Test',
          images: [AttachedImage(data: data, mediaType: 'image/png')],
        );
        final entry2 = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Test',
          images: [
            AttachedImage(
              data: Uint8List.fromList([1, 2, 3]),
              mediaType: 'image/png',
            ),
          ],
        );

        // Act & Assert
        check(entry1 == entry2).isTrue();
      });

      test('equals returns false when images differ', () {
        // Arrange
        final entry1 = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Test',
          images: [
            AttachedImage(
              data: Uint8List.fromList([1, 2, 3]),
              mediaType: 'image/png',
            ),
          ],
        );
        final entry2 = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Test',
          images: [
            AttachedImage(
              data: Uint8List.fromList([4, 5, 6]),
              mediaType: 'image/png',
            ),
          ],
        );

        // Act & Assert
        check(entry1 == entry2).isFalse();
      });

      test('equals returns false when image count differs', () {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3]);
        final entry1 = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Test',
          images: [AttachedImage(data: data, mediaType: 'image/png')],
        );
        final entry2 = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Test',
          images: [],
        );

        // Act & Assert
        check(entry1 == entry2).isFalse();
      });
    });

    group('copyWith', () {
      test('copyWith preserves images when not specified', () {
        // Arrange
        final original = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Original',
          images: [
            AttachedImage(
              data: Uint8List.fromList([1, 2, 3]),
              mediaType: 'image/png',
            ),
          ],
        );

        // Act
        final modified = original.copyWith(text: 'Modified');

        // Assert
        check(modified.text).equals('Modified');
        check(modified.images.length).equals(1);
        check(listEquals(modified.images, original.images)).isTrue();
      });

      test('copyWith can replace images', () {
        // Arrange
        final original = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          text: 'Original',
          images: [
            AttachedImage(
              data: Uint8List.fromList([1, 2, 3]),
              mediaType: 'image/png',
            ),
          ],
        );
        final newImages = [
          AttachedImage(
            data: Uint8List.fromList([4, 5, 6]),
            mediaType: 'image/jpeg',
          ),
        ];

        // Act
        final modified = original.copyWith(images: newImages);

        // Assert
        check(modified.images.length).equals(1);
        check(modified.images.first.mediaType).equals('image/jpeg');
      });
    });
  });
}
