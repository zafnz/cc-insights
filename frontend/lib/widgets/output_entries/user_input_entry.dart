import 'package:flutter/material.dart';

import '../../models/output_entry.dart';

/// Displays a user input entry.
class UserInputEntryWidget extends StatelessWidget {
  const UserInputEntryWidget({super.key, required this.entry});

  final UserInputEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Existing row with icon and text
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.person_outline,
                size: 16,
                color: colorScheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  entry.text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),

          // Image thumbnails (only if images exist)
          if (entry.images.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  entry.images.map((img) => _ImageThumbnail(image: img)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Displays a thumbnail of an attached image.
class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.image});

  final AttachedImage image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        image.data,
        width: 150,
        height: 150,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 150,
          height: 150,
          color: Colors.grey[800],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }
}
