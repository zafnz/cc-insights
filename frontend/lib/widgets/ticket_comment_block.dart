import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/ticket.dart';
import 'markdown_renderer.dart';

/// A comment block widget for the ticket timeline.
///
/// Renders a single comment (or the ticket body) with a header bar showing
/// the author avatar, name, optional badges, and timestamp, plus a body
/// area with rendered markdown and optional image thumbnails.
class TicketCommentBlock extends StatelessWidget {
  const TicketCommentBlock({
    super.key,
    required this.author,
    required this.authorType,
    this.ticketAuthor,
    required this.timestamp,
    required this.markdownContent,
    this.images = const [],
  });

  /// Display name of the comment author.
  final String author;

  /// Whether the author is a human user or an AI agent.
  final AuthorType authorType;

  /// The ticket creator's name. If [author] matches this, an "Owner" badge
  /// is shown.
  final String? ticketAuthor;

  /// When this comment was created.
  final DateTime timestamp;

  /// Markdown content of the comment body.
  final String markdownContent;

  /// Images attached to this comment.
  final List<TicketImage> images;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              author: author,
              authorType: authorType,
              isOwner: ticketAuthor != null && author == ticketAuthor,
              timestamp: timestamp,
            ),
            _Body(
              markdownContent: markdownContent,
              images: images,
            ),
          ],
        ),
      ),
    );
  }
}

/// The header bar of a comment block.
class _Header extends StatelessWidget {
  const _Header({
    required this.author,
    required this.authorType,
    required this.isOwner,
    required this.timestamp,
  });

  final String author;
  final AuthorType authorType;
  final bool isOwner;
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          _Avatar(author: author, authorType: authorType),
          const SizedBox(width: 8),
          Text(
            author,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          if (authorType == AuthorType.agent) ...[
            const SizedBox(width: 6),
            _AgentBadge(),
          ],
          if (isOwner) ...[
            const SizedBox(width: 6),
            _OwnerBadge(),
          ],
          const Spacer(),
          Text(
            _formatTimestamp(timestamp),
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The body section of a comment block.
class _Body extends StatelessWidget {
  const _Body({
    required this.markdownContent,
    this.images = const [],
  });

  final String markdownContent;
  final List<TicketImage> images;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (markdownContent.isNotEmpty)
            MarkdownRenderer(data: markdownContent),
          if (images.isNotEmpty) ...[
            if (markdownContent.isNotEmpty) const SizedBox(height: 12),
            _ImageGrid(images: images),
          ],
        ],
      ),
    );
  }
}

/// Avatar circle showing the first letter of the author name.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.author, required this.authorType});

  final String author;
  final AuthorType authorType;

  @override
  Widget build(BuildContext context) {
    final initial =
        author.isNotEmpty ? author[0].toUpperCase() : '?';

    // Purple tint for users, blue tint for agents.
    final Color backgroundColor;
    final Color foregroundColor;
    if (authorType == AuthorType.agent) {
      backgroundColor = Colors.blue.shade100;
      foregroundColor = Colors.blue.shade800;
    } else {
      backgroundColor = Colors.purple.shade100;
      foregroundColor = Colors.purple.shade800;
    }

    return SizedBox(
      width: 28,
      height: 28,
      child: CircleAvatar(
        backgroundColor: backgroundColor,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: foregroundColor,
          ),
        ),
      ),
    );
  }
}

/// Small "agent" chip badge.
class _AgentBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        'agent',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.blue.shade700,
        ),
      ),
    );
  }
}

/// "Owner" label badge.
class _OwnerBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        'Owner',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A grid of image thumbnails that can be tapped to expand.
class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});

  final List<TicketImage> images;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final image in images)
          _ImageThumbnail(image: image),
      ],
    );
  }
}

/// A single image thumbnail that expands in a dialog on tap.
class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.image});

  final TicketImage image;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final file = File(image.relativePath);

    return GestureDetector(
      onTap: () => _showExpandedImage(context),
      child: Container(
        width: 120,
        height: 90,
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
    );
  }

  void _showExpandedImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final file = File(image.relativePath);
        return Dialog(
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
                    ? Image.file(file)
                    : const Center(child: Text('Image not found')),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Formats a [DateTime] for display in comment headers.
///
/// - Same day as now: time only (e.g. "14:30")
/// - Same year as now: day + abbreviated month (e.g. "22 Jun")
/// - Different year: day + abbreviated month + year (e.g. "22 Jun 2025")
String _formatTimestamp(DateTime timestamp) {
  final now = DateTime.now();
  final localTimestamp = timestamp.toLocal();

  if (localTimestamp.year == now.year &&
      localTimestamp.month == now.month &&
      localTimestamp.day == now.day) {
    return DateFormat('HH:mm').format(localTimestamp);
  }

  if (localTimestamp.year == now.year) {
    return DateFormat('d MMM').format(localTimestamp);
  }

  return DateFormat('d MMM yyyy').format(localTimestamp);
}
