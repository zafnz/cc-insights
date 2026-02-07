import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/fonts.dart';
import '../../models/output_entry.dart';
import '../../state/theme_state.dart';
import '../markdown_renderer.dart';

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
          // Row with icon and text content
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
                child: _buildTextContent(
                  textTheme,
                  onBubbleColor,
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

  Widget _buildTextContent(TextTheme textTheme, Color onBubbleColor) {
    switch (entry.displayFormat) {
      case DisplayFormat.plain:
        return SelectableText(
          entry.text,
          style: textTheme.bodyMedium?.copyWith(
            color: onBubbleColor,
          ),
        );
      case DisplayFormat.fixedWidth:
        return SelectableText(
          entry.text,
          style: AppFonts.monoTextStyle(
            fontSize: textTheme.bodyMedium?.fontSize ?? 14,
            color: onBubbleColor,
          ),
        );
      case DisplayFormat.markdown:
        return MarkdownRenderer(
          data: entry.text,
          codeColor: onBubbleColor,
        );
    }
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
