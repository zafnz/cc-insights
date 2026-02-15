import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/output_entry.dart';
import '../services/image_utils.dart';

/// Maximum number of images that can be attached to a single message.
const maxAttachedImages = 5;

/// Manages image attachments for a message input widget.
///
/// Handles clipboard paste, drag-and-drop, file picker, image processing,
/// and the pending image list. Widget-level concerns (setState, mounted,
/// snackbars) are delegated through callbacks.
class ImageAttachmentHelper {
  final int maxImages;
  final VoidCallback onChanged;
  final void Function(String message) onError;

  /// Called to check whether the owning widget is still mounted.
  final bool Function() isMounted;

  final List<AttachedImage> _images = [];
  bool isProcessing = false;

  ImageAttachmentHelper({
    this.maxImages = maxAttachedImages,
    required this.onChanged,
    required this.onError,
    required this.isMounted,
  });

  /// The current list of attached images (unmodifiable view).
  List<AttachedImage> get images => List.unmodifiable(_images);

  /// The current number of attached images.
  int get imageCount => _images.length;

  /// Whether the max image limit has been reached.
  bool get isAtMax => _images.length >= maxImages;

  /// Handle paste from system clipboard - checks for images.
  Future<void> handlePaste() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final reader = await clipboard.read();

    for (final format in [Formats.png, Formats.jpeg, Formats.gif]) {
      if (reader.canProvide(format)) {
        reader.getFile(format, (file) async {
          final stream = file.getStream();
          final chunks = <List<int>>[];
          await for (final chunk in stream) {
            chunks.add(chunk);
          }
          final data = Uint8List.fromList(
            chunks.expand((chunk) => chunk).toList(),
          );
          final mediaType = _formatToMediaType(format);
          await addImageData(data, mediaType);
        });
        return;
      }
    }
  }

  /// Handle drag-and-drop files.
  Future<void> handleDrop(DropDoneDetails details) async {
    for (final file in details.files) {
      final path = file.path;
      if (path.isEmpty) continue;

      final extension = path.split('.').last;
      if (!isSupportedImageExtension(extension)) continue;

      final bytes = await File(path).readAsBytes();
      final mediaType = getMimeTypeFromExtension(extension);
      await addImageData(bytes, mediaType);
    }
  }

  /// Pick images from file system via file picker.
  Future<void> pickImages() async {
    if (isAtMax) {
      _showMaxImagesWarning();
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result == null) return;

    for (final file in result.files) {
      if (isAtMax) {
        _showMaxImagesWarning();
        break;
      }

      if (file.bytes != null && file.extension != null) {
        final mediaType = getMimeTypeFromExtension(file.extension!);
        await addImageData(file.bytes!, mediaType);
      }
    }
  }

  /// Process and add raw image data.
  Future<void> addImageData(Uint8List data, String mediaType) async {
    if (isAtMax) {
      _showMaxImagesWarning();
      return;
    }

    isProcessing = true;
    onChanged();

    try {
      final result = await processImage(data, mediaType);
      if (!isMounted()) return;

      _images.add(AttachedImage(
        data: result.data,
        mediaType: result.mediaType,
      ));
      isProcessing = false;
      onChanged();
    } on ImageProcessingError catch (e) {
      if (!isMounted()) return;
      isProcessing = false;
      onChanged();
      onError(e.message);
    } catch (e) {
      if (!isMounted()) return;
      isProcessing = false;
      onChanged();
      onError('Failed to process image');
    }
  }

  /// Remove image at the given index.
  void removeImage(int index) {
    _images.removeAt(index);
    onChanged();
  }

  /// Clear all images and reset state.
  void clear() {
    _images.clear();
    onChanged();
  }

  /// Convert super_clipboard format to MIME type.
  String _formatToMediaType(DataFormat format) {
    if (format == Formats.png) return 'image/png';
    if (format == Formats.jpeg) return 'image/jpeg';
    if (format == Formats.gif) return 'image/gif';
    return 'image/png';
  }

  void _showMaxImagesWarning() {
    onError('Maximum $maxImages images per message');
  }
}
