import 'dart:typed_data';

import 'package:cc_insights_v2/widgets/image_attachment_helper.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

// A minimal 1x1 white PNG (67 bytes).
final _tinyPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
  0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
  0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, //
  0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
  0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

void main() {
  group('ImageAttachmentHelper', () {
    late ImageAttachmentHelper helper;
    late int changeCount;
    late List<String> errors;

    setUp(() {
      changeCount = 0;
      errors = [];
      helper = ImageAttachmentHelper(
        maxImages: 3,
        onChanged: () => changeCount++,
        onError: (msg) => errors.add(msg),
        isMounted: () => true,
      );
    });

    test('starts with empty images', () {
      check(helper.images).isEmpty();
      check(helper.imageCount).equals(0);
      check(helper.isAtMax).isFalse();
      check(helper.isProcessing).isFalse();
    });

    test('addImageData processes and adds image', () async {
      await helper.addImageData(_tinyPng, 'image/png');

      check(helper.imageCount).equals(1);
      check(helper.images.first.mediaType).equals('image/png');
      // onChanged called at least twice: once for isProcessing=true, once after add
      check(changeCount).isGreaterOrEqual(2);
    });

    test('addImageData respects max limit', () async {
      // Add max images
      for (var i = 0; i < 3; i++) {
        await helper.addImageData(_tinyPng, 'image/png');
      }
      check(helper.imageCount).equals(3);
      check(helper.isAtMax).isTrue();

      // Try to add one more
      errors.clear();
      await helper.addImageData(_tinyPng, 'image/png');
      check(helper.imageCount).equals(3);
      check(errors).isNotEmpty();
    });

    test('removeImage removes at index', () async {
      await helper.addImageData(_tinyPng, 'image/png');
      await helper.addImageData(_tinyPng, 'image/png');
      check(helper.imageCount).equals(2);

      helper.removeImage(0);
      check(helper.imageCount).equals(1);
    });

    test('clear removes all images', () async {
      await helper.addImageData(_tinyPng, 'image/png');
      await helper.addImageData(_tinyPng, 'image/png');
      check(helper.imageCount).equals(2);

      helper.clear();
      check(helper.imageCount).equals(0);
      check(helper.images).isEmpty();
    });

    test('error callback fires on unsupported image type', () async {
      await helper.addImageData(
        Uint8List.fromList([0, 1, 2, 3]),
        'image/bmp',
      );

      check(helper.imageCount).equals(0);
      check(errors).isNotEmpty();
    });

    test('does not add image when isMounted returns false', () async {
      helper = ImageAttachmentHelper(
        maxImages: 3,
        onChanged: () => changeCount++,
        onError: (msg) => errors.add(msg),
        isMounted: () => false,
      );

      await helper.addImageData(_tinyPng, 'image/png');

      // Image should not be added because isMounted is false
      check(helper.imageCount).equals(0);
    });

    test('images list is unmodifiable', () async {
      await helper.addImageData(_tinyPng, 'image/png');
      final images = helper.images;
      check(images).length.equals(1);
      // The returned list should be unmodifiable
      check(() => images.removeAt(0)).throws<UnsupportedError>();
    });
  });
}
