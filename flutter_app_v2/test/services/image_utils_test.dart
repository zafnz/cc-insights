import 'dart:typed_data';

import 'package:cc_insights_v2/services/image_utils.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSupportedImageExtension', () {
    test('returns true for png', () {
      check(isSupportedImageExtension('png')).isTrue();
      check(isSupportedImageExtension('.png')).isTrue();
      check(isSupportedImageExtension('PNG')).isTrue();
    });

    test('returns true for jpeg/jpg', () {
      check(isSupportedImageExtension('jpg')).isTrue();
      check(isSupportedImageExtension('jpeg')).isTrue();
      check(isSupportedImageExtension('.jpg')).isTrue();
      check(isSupportedImageExtension('.jpeg')).isTrue();
      check(isSupportedImageExtension('JPG')).isTrue();
      check(isSupportedImageExtension('JPEG')).isTrue();
    });

    test('returns true for gif', () {
      check(isSupportedImageExtension('gif')).isTrue();
      check(isSupportedImageExtension('.gif')).isTrue();
      check(isSupportedImageExtension('GIF')).isTrue();
    });

    test('returns true for webp', () {
      check(isSupportedImageExtension('webp')).isTrue();
      check(isSupportedImageExtension('.webp')).isTrue();
      check(isSupportedImageExtension('WEBP')).isTrue();
    });

    test('returns false for unsupported extensions', () {
      check(isSupportedImageExtension('bmp')).isFalse();
      check(isSupportedImageExtension('tiff')).isFalse();
      check(isSupportedImageExtension('svg')).isFalse();
      check(isSupportedImageExtension('pdf')).isFalse();
      check(isSupportedImageExtension('txt')).isFalse();
      check(isSupportedImageExtension('')).isFalse();
    });
  });

  group('getMimeTypeFromExtension', () {
    test('returns image/png for png extension', () {
      check(getMimeTypeFromExtension('png')).equals('image/png');
      check(getMimeTypeFromExtension('.png')).equals('image/png');
      check(getMimeTypeFromExtension('PNG')).equals('image/png');
    });

    test('returns image/jpeg for jpg/jpeg extensions', () {
      check(getMimeTypeFromExtension('jpg')).equals('image/jpeg');
      check(getMimeTypeFromExtension('jpeg')).equals('image/jpeg');
      check(getMimeTypeFromExtension('.jpg')).equals('image/jpeg');
      check(getMimeTypeFromExtension('.jpeg')).equals('image/jpeg');
      check(getMimeTypeFromExtension('JPG')).equals('image/jpeg');
    });

    test('returns image/gif for gif extension', () {
      check(getMimeTypeFromExtension('gif')).equals('image/gif');
      check(getMimeTypeFromExtension('.gif')).equals('image/gif');
      check(getMimeTypeFromExtension('GIF')).equals('image/gif');
    });

    test('returns image/webp for webp extension', () {
      check(getMimeTypeFromExtension('webp')).equals('image/webp');
      check(getMimeTypeFromExtension('.webp')).equals('image/webp');
      check(getMimeTypeFromExtension('WEBP')).equals('image/webp');
    });

    test('returns application/octet-stream for unknown extensions', () {
      check(getMimeTypeFromExtension('bmp')).equals('application/octet-stream');
      check(getMimeTypeFromExtension('tiff')).equals('application/octet-stream');
      check(getMimeTypeFromExtension('')).equals('application/octet-stream');
    });
  });

  group('supportedImageTypes', () {
    test('contains all supported MIME types', () {
      check(supportedImageTypes.contains('image/png')).isTrue();
      check(supportedImageTypes.contains('image/jpeg')).isTrue();
      check(supportedImageTypes.contains('image/gif')).isTrue();
      check(supportedImageTypes.contains('image/webp')).isTrue();
    });

    test('does not contain unsupported MIME types', () {
      check(supportedImageTypes.contains('image/bmp')).isFalse();
      check(supportedImageTypes.contains('image/tiff')).isFalse();
      check(supportedImageTypes.contains('image/svg+xml')).isFalse();
    });
  });

  group('processImage', () {
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

    test('returns image as-is when under compression threshold', () async {
      // Arrange
      final smallImage = testPngBytes;

      // Act
      final result = await processImage(smallImage, 'image/png');

      // Assert
      check(result.wasCompressed).isFalse();
      check(result.mediaType).equals('image/png');
      check(result.data).deepEquals(smallImage);
    });

    test('throws ImageProcessingError for unsupported media type', () async {
      // Arrange
      final imageData = Uint8List.fromList([0x00, 0x01, 0x02]);

      // Act & Assert
      await check(processImage(imageData, 'image/bmp'))
          .throws<ImageProcessingError>();
    });

    test('throws ImageProcessingError for invalid media type format', () async {
      // Arrange
      final imageData = Uint8List.fromList([0x00, 0x01, 0x02]);

      // Act & Assert
      await check(processImage(imageData, 'not-a-mime-type'))
          .throws<ImageProcessingError>();
    });

    test('validates against supportedImageTypes set', () async {
      // Test each supported type passes validation
      for (final mediaType in supportedImageTypes) {
        final result = await processImage(testPngBytes, mediaType);
        check(result.data).isNotNull();
      }
    });
  });

  group('ImageProcessingResult', () {
    test('creates correctly with all fields', () {
      // Arrange
      final data = Uint8List.fromList([1, 2, 3]);
      const mediaType = 'image/jpeg';
      const wasCompressed = true;

      // Act
      final result = ImageProcessingResult(
        data: data,
        mediaType: mediaType,
        wasCompressed: wasCompressed,
      );

      // Assert
      check(result.data).deepEquals(data);
      check(result.mediaType).equals(mediaType);
      check(result.wasCompressed).isTrue();
    });
  });

  group('ImageProcessingError', () {
    test('creates with message', () {
      // Arrange & Act
      const error = ImageProcessingError('Test error message');

      // Assert
      check(error.message).equals('Test error message');
    });

    test('toString includes message', () {
      // Arrange
      const error = ImageProcessingError('Something went wrong');

      // Act
      final str = error.toString();

      // Assert
      check(str).contains('ImageProcessingError');
      check(str).contains('Something went wrong');
    });
  });
}
