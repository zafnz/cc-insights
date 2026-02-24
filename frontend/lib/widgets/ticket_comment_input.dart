import 'package:flutter/material.dart';

import '../models/ticket.dart';
import '../services/author_service.dart';

/// A comment input widget for the ticket detail timeline.
///
/// Displays an avatar header, expandable markdown text area, and action buttons
/// for submitting comments and toggling ticket open/closed status.
class TicketCommentInput extends StatefulWidget {
  const TicketCommentInput({
    super.key,
    required this.ticket,
    required this.onComment,
    required this.onToggleStatus,
  });

  /// The ticket this comment input is for.
  final TicketData ticket;

  /// Called when the user submits a comment with text.
  final void Function(String text) onComment;

  /// Called when the user toggles the ticket open/closed status.
  final VoidCallback onToggleStatus;

  @override
  State<TicketCommentInput> createState() => _TicketCommentInputState();
}

class _TicketCommentInputState extends State<TicketCommentInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _submitComment() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onComment(text);
    _controller.clear();
  }

  void _toggleStatus() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onComment(text);
      _controller.clear();
    }
    widget.onToggleStatus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = AuthorService.currentUser;
    final initial = user.isNotEmpty ? user[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: avatar + placeholder label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: colorScheme.primary,
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Add a comment',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Text area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              minLines: 3,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Leave a comment...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          // Divider
          Divider(height: 1, color: colorScheme.outlineVariant),

          // Footer: action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _toggleStatus,
                  child: Text(
                    widget.ticket.isOpen ? 'Close ticket' : 'Reopen ticket',
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _hasText ? _submitComment : null,
                  child: const Text('Comment'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
