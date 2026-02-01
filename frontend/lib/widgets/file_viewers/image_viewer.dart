import 'dart:io';

import 'package:flutter/material.dart';

/// Displays image files with zoom and pan support.
///
/// This viewer uses InteractiveViewer to provide zoom (0.5x - 4.0x)
/// and pan capabilities for images. Supports common image formats:
/// PNG, JPG, GIF, BMP, WebP.
class ImageViewer extends StatelessWidget {
  const ImageViewer({super.key, required this.path});

  /// The absolute path to the image file.
  final String path;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.file(
          File(path),
          errorBuilder: (context, error, stackTrace) {
            return _ImageError(error: error.toString());
          },
        ),
      ),
    );
  }
}

/// Widget shown when image loading fails.
class _ImageError extends StatelessWidget {
  const _ImageError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image,
            size: 48,
            color: colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Failed to load image',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
