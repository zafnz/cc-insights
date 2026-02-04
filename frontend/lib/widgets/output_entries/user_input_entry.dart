import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/output_entry.dart';
import '../../state/theme_state.dart';

/// Displays a user input entry.
class UserInputEntryWidget extends StatelessWidget {
  const UserInputEntryWidget({super.key, required this.entry});

  final UserInputEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final themeState = context.watch<ThemeState>();
    final bubbleColor =
        themeState.inputTextColor ?? colorScheme.primary;
    final onBubbleColor = _contrastColor(bubbleColor);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
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
                color: onBubbleColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  entry.text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: onBubbleColor,
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

/// Returns white or black depending on the luminance of [color].
Color _contrastColor(Color color) {
  return color.computeLuminance() > 0.5
      ? Colors.black
      : Colors.white;
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
