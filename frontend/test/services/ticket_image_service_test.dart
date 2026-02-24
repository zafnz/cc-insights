import 'dart:io';

import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/ticket_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late TicketImageService service;
  const projectId = 'test-proj';
  const ticketId = 42;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ticket_image_test_');
    PersistenceService.setBaseDir(tempDir.path);
    service = TicketImageService();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Creates a temporary PNG file and returns its path.
  String createTestImage({String name = 'test.png'}) {
    final file = File(p.join(tempDir.path, name));
    // Write a minimal 1x1 white PNG.
    file.writeAsBytesSync([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG header
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
    ]);
    return file.path;
  }

  group('TicketImageService', () {
    group('resolveImagePath', () {
      test('joins project dir with relative path', () {
        final result = service.resolveImagePath(
          projectId,
          'ticket-images/42/abc.png',
        );

        final expected = p.join(
          PersistenceService.projectDir(projectId),
          'ticket-images/42/abc.png',
        );
        expect(result, equals(expected));
      });

      test('works with different project IDs', () {
        final result1 = service.resolveImagePath('proj-a', 'ticket-images/1/x.png');
        final result2 = service.resolveImagePath('proj-b', 'ticket-images/1/x.png');

        expect(result1, isNot(equals(result2)));
        expect(result1, contains('proj-a'));
        expect(result2, contains('proj-b'));
      });
    });

    group('attachImage', () {
      test('copies file and returns TicketImage with correct metadata', () async {
        final sourcePath = createTestImage(name: 'screenshot.png');

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        expect(image.fileName, equals('screenshot.png'));
        expect(image.mimeType, equals('image/png'));
        expect(image.id, isNotEmpty);
        expect(image.relativePath, startsWith('ticket-images/$ticketId/'));
        expect(image.relativePath, endsWith('.png'));
      });

      test('creates destination directory', () async {
        final sourcePath = createTestImage();

        await service.attachImage(projectId, ticketId, sourcePath);

        final destDir = Directory(
          TicketImageService.ticketImagesDir(projectId, ticketId),
        );
        expect(destDir.existsSync(), isTrue);
      });

      test('copies file bytes to destination', () async {
        final sourcePath = createTestImage();
        final sourceBytes = File(sourcePath).readAsBytesSync();

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        final destPath = service.resolveImagePath(projectId, image.relativePath);
        final destBytes = File(destPath).readAsBytesSync();
        expect(destBytes, equals(sourceBytes));
      });

      test('generates unique IDs for multiple attachments', () async {
        final sourcePath = createTestImage();

        final image1 = await service.attachImage(projectId, ticketId, sourcePath);
        final image2 = await service.attachImage(projectId, ticketId, sourcePath);

        expect(image1.id, isNot(equals(image2.id)));
        expect(image1.relativePath, isNot(equals(image2.relativePath)));
      });

      test('detects JPEG mime type', () async {
        final sourcePath = createTestImage(name: 'photo.jpg');

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        expect(image.mimeType, equals('image/jpeg'));
        expect(image.relativePath, endsWith('.jpg'));
      });

      test('detects JPEG mime type for .jpeg extension', () async {
        final sourcePath = createTestImage(name: 'photo.jpeg');

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        expect(image.mimeType, equals('image/jpeg'));
      });

      test('detects GIF mime type', () async {
        final sourcePath = createTestImage(name: 'anim.gif');

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        expect(image.mimeType, equals('image/gif'));
      });

      test('detects WebP mime type', () async {
        final sourcePath = createTestImage(name: 'photo.webp');

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        expect(image.mimeType, equals('image/webp'));
      });

      test('throws for non-existent source file', () async {
        expect(
          () => service.attachImage(projectId, ticketId, '/no/such/file.png'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for unsupported extension', () async {
        final path = p.join(tempDir.path, 'file.txt');
        File(path).writeAsStringSync('not an image');

        expect(
          () => service.attachImage(projectId, ticketId, path),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('handles case-insensitive extensions', () async {
        final sourcePath = createTestImage(name: 'PHOTO.PNG');

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        expect(image.mimeType, equals('image/png'));
      });

      test('relative path follows ticket-images/<ticketId>/<uuid>.<ext> format', () async {
        final sourcePath = createTestImage();

        final image = await service.attachImage(projectId, ticketId, sourcePath);

        final parts = image.relativePath.split('/');
        expect(parts.length, equals(3));
        expect(parts[0], equals('ticket-images'));
        expect(parts[1], equals('$ticketId'));
        // UUID filename with .png extension
        expect(parts[2], endsWith('.png'));
        expect(parts[2].length, greaterThan(5)); // uuid + .png
      });
    });

    group('deleteImage', () {
      test('deletes the image file', () async {
        final sourcePath = createTestImage();
        final image = await service.attachImage(projectId, ticketId, sourcePath);

        final absPath = service.resolveImagePath(projectId, image.relativePath);
        expect(File(absPath).existsSync(), isTrue);

        await service.deleteImage(projectId, image);

        expect(File(absPath).existsSync(), isFalse);
      });

      test('does not throw for non-existent file', () async {
        final sourcePath = createTestImage();
        final image = await service.attachImage(projectId, ticketId, sourcePath);

        // Delete twice — second call should not throw.
        await service.deleteImage(projectId, image);
        await service.deleteImage(projectId, image);
      });
    });

    group('deleteTicketImages', () {
      test('deletes entire ticket image directory', () async {
        final sourcePath = createTestImage();
        await service.attachImage(projectId, ticketId, sourcePath);
        await service.attachImage(projectId, ticketId, sourcePath);

        final dir = Directory(
          TicketImageService.ticketImagesDir(projectId, ticketId),
        );
        expect(dir.existsSync(), isTrue);
        expect(dir.listSync().length, equals(2));

        await service.deleteTicketImages(projectId, ticketId);

        expect(dir.existsSync(), isFalse);
      });

      test('does not throw for non-existent directory', () async {
        await service.deleteTicketImages(projectId, 999);
      });

      test('does not affect other ticket image dirs', () async {
        final sourcePath = createTestImage();
        await service.attachImage(projectId, ticketId, sourcePath);
        await service.attachImage(projectId, 99, sourcePath);

        await service.deleteTicketImages(projectId, ticketId);

        final otherDir = Directory(
          TicketImageService.ticketImagesDir(projectId, 99),
        );
        expect(otherDir.existsSync(), isTrue);
        expect(otherDir.listSync().length, equals(1));
      });
    });

    group('ticketImagesDir', () {
      test('is under project dir', () {
        final dir = TicketImageService.ticketImagesDir(projectId, ticketId);
        expect(dir, startsWith(PersistenceService.projectDir(projectId)));
      });

      test('includes ticket ID', () {
        final dir = TicketImageService.ticketImagesDir(projectId, ticketId);
        expect(dir, endsWith('/ticket-images/$ticketId'));
      });
    });
  });
}
