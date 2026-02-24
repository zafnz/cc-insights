import 'dart:io';

import 'package:flutter/material.dart';

import '../models/ticket.dart';

/// A thumbnail for a ticket image with an optional remove button overlay.
///
/// Clicking the thumbnail opens a [TicketImageViewer] dialog showing the
/// full-size image. The optional [onRemove] callback shows an "x" button
/// overlay in the top-right corner for deleting the image.
class TicketImageThumbnail extends StatelessWidget {
  const TicketImageThumbnail({
    super.key,
    required this.image,
    required this.resolvedPath,
    this.onRemove,
    this.width = 120,
    this.height = 90,
  });

  /// The ticket image metadata.
  final TicketImage image;

  /// The absolute path to the image file on disk.
  final String resolvedPath;

  /// Called when the user taps the remove ("x") button.
  /// If null, the remove button is not shown.
  final VoidCallback? onRemove;

  /// Thumbnail width.
  final double width;

  /// Thumbnail height.
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final file = File(resolvedPath);

    return GestureDetector(
      onTap: () => TicketImageViewer.show(
        context,
        image: image,
        resolvedPath: resolvedPath,
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.cover)
                  : Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            if (onRemove != null)
              Positioned(
                top: 2,
                right: 2,
                child: _RemoveButton(onTap: onRemove!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small circular "x" button overlaid on a thumbnail.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 14, color: Colors.white),
      ),
    );
  }
}

/// A dialog that displays a ticket image at full size.
///
/// Shows the image file name in a title bar with a close button.
class TicketImageViewer extends StatelessWidget {
  const TicketImageViewer({
    super.key,
    required this.image,
    required this.resolvedPath,
  });

  /// The ticket image metadata.
  final TicketImage image;

  /// The absolute path to the image file on disk.
  final String resolvedPath;

  /// Shows the viewer as a dialog.
  static void show(
    BuildContext context, {
    required TicketImage image,
    required String resolvedPath,
  }) {
    showDialog(
      context: context,
      builder: (_) => TicketImageViewer(
        image: image,
        resolvedPath: resolvedPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = File(resolvedPath);

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(image.fileName),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Flexible(
              child: file.existsSync()
                  ? InteractiveViewer(
                      child: Image.file(file),
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Image not found'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
