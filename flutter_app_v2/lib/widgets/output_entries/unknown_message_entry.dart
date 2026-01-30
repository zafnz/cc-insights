import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/output_entry.dart';
import '../../services/runtime_config.dart';

/// Displays an unknown message entry for debugging.
///
/// Shows a collapsible card with the message type and raw JSON content.
/// Helps developers identify unhandled SDK message types.
class UnknownMessageEntryWidget extends StatefulWidget {
  /// Creates an unknown message entry widget.
  const UnknownMessageEntryWidget({super.key, required this.entry});

  /// The entry data to display.
  final UnknownMessageEntry entry;

  @override
  State<UnknownMessageEntryWidget> createState() =>
      _UnknownMessageEntryWidgetState();
}

class _UnknownMessageEntryWidgetState extends State<UnknownMessageEntryWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            messageType: widget.entry.messageType,
            isExpanded: _isExpanded,
            onTap: () => setState(() => _isExpanded = !_isExpanded),
          ),
          if (_isExpanded) _JsonContent(rawMessage: widget.entry.rawMessage),
        ],
      ),
    );
  }
}

/// Header showing the message type and expand/collapse controls.
class _Header extends StatelessWidget {
  const _Header({
    required this.messageType,
    required this.isExpanded,
    required this.onTap,
  });

  final String messageType;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.help_outline,
              size: 16,
              color: colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              'Unknown Message',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                messageType,
                style: GoogleFonts.getFont(
                  RuntimeConfig.instance.monoFontFamily,
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Spacer(),
            Text(
              isExpanded ? 'Hide' : 'Show',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible JSON content display.
class _JsonContent extends StatelessWidget {
  const _JsonContent({required this.rawMessage});

  final Map<String, dynamic> rawMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final encoder = const JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(rawMessage);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
        ),
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
          child: SelectableText(
            jsonString,
            style: GoogleFonts.getFont(
              RuntimeConfig.instance.monoFontFamily,
              fontSize: 11,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
