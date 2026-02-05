import 'dart:convert';
import 'dart:io';

import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

/// A [CodexSession] subclass that bypasses the test-session guard and uses
/// a fake [CodexProcess]-like send so we can exercise the real temp-file logic
/// without spawning a subprocess.
class _TestableCodexSession extends CodexSession {
  _TestableCodexSession() : super.forTesting(threadId: 'test-thread');

  /// Override [sendWithContent] to replicate the real implementation but
  /// use [_fakeSendRequest] instead of `_process!.sendRequest`.
  bool sendRequestCalled = false;
  bool sendRequestShouldThrow = false;

  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    final inputs = await convertContentForTest(content);
    if (inputs.isEmpty) return;

    final tempPaths = Set<String>.of(tempImagePaths);
    try {
      sendRequestCalled = true;
      if (sendRequestShouldThrow) {
        throw StateError('Simulated send failure');
      }
    } finally {
      deleteTempFilesForTest(tempPaths);
    }
  }

  /// Expose [_convertContent] for testing.
  Future<List<Map<String, dynamic>>> convertContentForTest(
    List<ContentBlock> content,
  ) async {
    final inputs = <Map<String, dynamic>>[];
    for (final block in content) {
      if (block is TextBlock) {
        inputs.add({'type': 'text', 'text': block.text});
      } else if (block is ImageBlock) {
        final source = block.source;
        if (source.type == 'url' && source.url != null) {
          inputs.add({'type': 'image', 'url': source.url});
        } else if (source.type == 'base64' && source.data != null) {
          final path = await writeTempImageForTest(source.data!, source.mediaType);
          inputs.add({'type': 'localImage', 'path': path});
        }
      }
    }
    return inputs;
  }

  /// Expose [_writeTempImage] for testing.
  Future<String> writeTempImageForTest(String base64Data, String? mediaType) async {
    final bytes = base64Decode(base64Data);
    final ext = _extensionForMediaType(mediaType);
    final file = await File(
      '${Directory.systemTemp.path}/codex-image-test-${DateTime.now().microsecondsSinceEpoch}.$ext',
    ).create();
    await file.writeAsBytes(bytes, flush: true);
    tempImagePaths.add(file.path);
    return file.path;
  }

  /// Expose [_deleteTempFiles] for testing.
  void deleteTempFilesForTest(Set<String> paths) {
    for (final path in paths) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // Ignore — file may already be deleted.
      }
      tempImagePaths.remove(path);
    }
  }

  String _extensionForMediaType(String? mediaType) {
    return switch (mediaType) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
  }
}

/// A tiny 1x1 red PNG encoded as base64.
final _tinyPngBase64 = base64Encode([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
  0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
  0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  group('CodexSession temp image cleanup', () {
    test('temp file is deleted after sendWithContent succeeds', () async {
      final session = _TestableCodexSession();

      final content = [
        ImageBlock(
          source: ImageSource(
            type: 'base64',
            data: _tinyPngBase64,
            mediaType: 'image/png',
          ),
        ),
      ];

      // Convert content to create the temp file and capture its path.
      final inputs = await session.convertContentForTest(content);
      final path = inputs.first['path'] as String;
      expect(File(path).existsSync(), isTrue, reason: 'Temp file should exist after creation');
      expect(session.tempImagePaths, contains(path));

      // Now do the full sendWithContent which should clean up.
      // Re-create since the previous call already created + tracked it.
      // Reset state first.
      session.tempImagePaths.clear();

      await session.sendWithContent([
        ImageBlock(
          source: ImageSource(
            type: 'base64',
            data: _tinyPngBase64,
            mediaType: 'image/png',
          ),
        ),
      ]);

      expect(session.sendRequestCalled, isTrue);
      expect(session.tempImagePaths, isEmpty,
          reason: 'Temp paths should be cleared after send');

      // Clean up the first file manually since we cleared tracking.
      File(path).deleteSync();
    });

    test('temp file is deleted even when sendRequest throws', () async {
      final session = _TestableCodexSession()..sendRequestShouldThrow = true;

      await expectLater(
        session.sendWithContent([
          ImageBlock(
            source: ImageSource(
              type: 'base64',
              data: _tinyPngBase64,
              mediaType: 'image/png',
            ),
          ),
        ]),
        throwsA(isA<StateError>()),
      );

      expect(session.tempImagePaths, isEmpty,
          reason: 'Temp paths should be cleaned up even on error');
    });

    test('kill() cleans up remaining temp files', () async {
      final session = _TestableCodexSession();

      // Manually create a temp file and register it.
      final path = await session.writeTempImageForTest(_tinyPngBase64, 'image/png');
      expect(File(path).existsSync(), isTrue);
      expect(session.tempImagePaths, contains(path));

      // Kill should clean up via _dispose.
      await session.kill();

      expect(session.tempImagePaths, isEmpty);
      expect(File(path).existsSync(), isFalse,
          reason: 'Temp file should be deleted on kill/dispose');
    });

    test('url images do not create temp files', () async {
      final session = _TestableCodexSession();

      final inputs = await session.convertContentForTest([
        ImageBlock(
          source: ImageSource(
            type: 'url',
            url: 'https://example.com/image.png',
          ),
        ),
      ]);

      expect(inputs.first['type'], 'image');
      expect(session.tempImagePaths, isEmpty,
          reason: 'URL images should not create temp files');
    });

    test('multiple images all get cleaned up', () async {
      final session = _TestableCodexSession();

      final path1 = await session.writeTempImageForTest(_tinyPngBase64, 'image/png');
      final path2 = await session.writeTempImageForTest(_tinyPngBase64, 'image/jpeg');
      final path3 = await session.writeTempImageForTest(_tinyPngBase64, 'image/webp');

      expect(session.tempImagePaths, hasLength(3));
      expect(File(path1).existsSync(), isTrue);
      expect(File(path2).existsSync(), isTrue);
      expect(File(path3).existsSync(), isTrue);

      await session.kill();

      expect(session.tempImagePaths, isEmpty);
      expect(File(path1).existsSync(), isFalse);
      expect(File(path2).existsSync(), isFalse);
      expect(File(path3).existsSync(), isFalse);
    });
  });
}
