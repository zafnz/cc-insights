import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/ticket.dart';
import 'persistence_service.dart';

/// MIME types for supported image formats.
const _mimeTypes = <String, String>{
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml',
};

/// Service for managing image attachments on tickets.
///
/// Images are stored under `<data-dir>/projects/<projectId>/ticket-images/<ticketId>/`.
/// Each image is copied to that directory with a UUID-based filename to avoid
/// collisions. The [TicketImage] model stores a relative path from the project
/// data directory for portability.
class TicketImageService {
  final Uuid _uuid;

  /// Creates a [TicketImageService].
  TicketImageService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// Directory for a ticket's image attachments.
  static String ticketImagesDir(String projectId, int ticketId) =>
      '${PersistenceService.projectDir(projectId)}/ticket-images/$ticketId';

  /// Attaches an image to a ticket by copying the source file.
  ///
  /// Returns a [TicketImage] with a relative path suitable for serialization.
  /// Throws [ArgumentError] if the source file doesn't exist or has an
  /// unsupported extension.
  Future<TicketImage> attachImage(
    String projectId,
    int ticketId,
    String sourcePath,
  ) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw ArgumentError('Source file does not exist: $sourcePath');
    }

    final ext = p.extension(sourcePath).toLowerCase();
    final mimeType = _mimeTypes[ext];
    if (mimeType == null) {
      throw ArgumentError('Unsupported image format: $ext');
    }

    final id = _uuid.v4();
    final originalName = p.basename(sourcePath);
    final destFileName = '$id$ext';

    final destDir = Directory(ticketImagesDir(projectId, ticketId));
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    final destPath = p.join(destDir.path, destFileName);
    await sourceFile.copy(destPath);

    final relativePath = 'ticket-images/$ticketId/$destFileName';

    developer.log(
      'Attached image $originalName to ticket $ticketId as $destFileName',
      name: 'TicketImageService',
    );

    return TicketImage(
      id: id,
      fileName: originalName,
      relativePath: relativePath,
      mimeType: mimeType,
      createdAt: DateTime.now(),
    );
  }

  /// Deletes a single image file from disk.
  ///
  /// Silently ignores if the file doesn't exist.
  Future<void> deleteImage(String projectId, TicketImage image) async {
    final absPath = resolveImagePath(projectId, image.relativePath);
    final file = File(absPath);

    if (await file.exists()) {
      await file.delete();
      developer.log(
        'Deleted image ${image.fileName} (${image.id})',
        name: 'TicketImageService',
      );
    }
  }

  /// Deletes all images for a ticket by removing its image directory.
  ///
  /// Silently ignores if the directory doesn't exist.
  Future<void> deleteTicketImages(String projectId, int ticketId) async {
    final dir = Directory(ticketImagesDir(projectId, ticketId));

    if (await dir.exists()) {
      await dir.delete(recursive: true);
      developer.log(
        'Deleted all images for ticket $ticketId',
        name: 'TicketImageService',
      );
    }
  }

  /// Converts a relative image path to an absolute path.
  ///
  /// The relative path is resolved against the project data directory.
  String resolveImagePath(String projectId, String relativePath) {
    return p.join(PersistenceService.projectDir(projectId), relativePath);
  }
}
