import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Supported image MIME types for the Claude API.
const supportedImageTypes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};

/// Maximum file size before compression (500 KB).
const _compressionThreshold = 500 * 1024;

/// Maximum file size after compression (3 MB).
const _maxCompressedSize = 3 * 1024 * 1024;

/// Maximum dimension for resized images.
const _maxDimension = 2048;

/// JPEG quality for compression.
const _jpegQuality = 85;

/// Result of image processing.
class ImageProcessingResult {
  /// The processed image data.
  final Uint8List data;

  /// The MIME type of the processed image.
  final String mediaType;

  /// Whether the image was compressed.
  final bool wasCompressed;

  const ImageProcessingResult({
    required this.data,
    required this.mediaType,
    required this.wasCompressed,
  });
}

/// Error thrown when image processing fails.
class ImageProcessingError implements Exception {
  final String message;

  const ImageProcessingError(this.message);

  @override
  String toString() => 'ImageProcessingError: $message';
}

/// Processes an image, compressing it if necessary.
///
/// - Images under 1MB are returned as-is.
/// - Larger images are resized to max 2048px and compressed as JPEG.
/// - Returns null if the image cannot be processed or is still too large
///   after compression.
Future<ImageProcessingResult> processImage(
  Uint8List data,
  String mediaType,
) async {
  // Validate media type
  if (!supportedImageTypes.contains(mediaType)) {
    throw ImageProcessingError(
      'Unsupported image type: $mediaType. '
      'Supported types: ${supportedImageTypes.join(", ")}',
    );
  }

  // If under threshold, return as-is
  if (data.length < _compressionThreshold) {
    return ImageProcessingResult(
      data: data,
      mediaType: mediaType,
      wasCompressed: false,
    );
  }

  // Compress the image
  final compressed = await _compressImage(data);

  // Check if still too large
  if (compressed.length > _maxCompressedSize) {
    throw ImageProcessingError(
      'Image is too large (${_formatSize(compressed.length)}). '
      'Maximum size after compression is ${_formatSize(_maxCompressedSize)}.',
    );
  }

  return ImageProcessingResult(
    data: compressed,
    mediaType: 'image/jpeg', // Compression always outputs JPEG
    wasCompressed: true,
  );
}

/// Compresses an image by resizing and re-encoding as JPEG.
Future<Uint8List> _compressImage(Uint8List data) async {
  // Decode the image
  final image = img.decodeImage(data);
  if (image == null) {
    throw const ImageProcessingError('Failed to decode image');
  }

  // Calculate new dimensions
  final scale = math.min(
    1.0,
    _maxDimension / math.max(image.width, image.height),
  );
  final newWidth = (image.width * scale).round();
  final newHeight = (image.height * scale).round();

  // Resize if needed
  final resized = scale < 1.0
      ? img.copyResize(
          image,
          width: newWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        )
      : image;

  // Encode as JPEG
  final encoded = img.encodeJpg(resized, quality: _jpegQuality);
  return Uint8List.fromList(encoded);
}

/// Determines the MIME type from file extension.
String getMimeTypeFromExtension(String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}

/// Checks if a file extension is a supported image type.
bool isSupportedImageExtension(String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');
  return ['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext);
}

/// Formats a file size in bytes as a human-readable string.
String _formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
