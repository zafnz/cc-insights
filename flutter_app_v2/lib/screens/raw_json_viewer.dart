import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Keys for testing the RawJsonViewer.
class RawJsonViewerKeys {
  static const copyAllButton = Key('rawJsonViewer_copyAllButton');
  static const emptyState = Key('rawJsonViewer_emptyState');
  static const messageList = Key('rawJsonViewer_messageList');

  /// Returns the key for a message item at the given index.
  static Key messageItem(int index) => Key('rawJsonViewer_messageItem_$index');

  /// Returns the key for a message copy button at the given index.
  static Key copyButton(int index) => Key('rawJsonViewer_copyButton_$index');

  /// Returns the key for a type badge at the given index.
  static Key typeBadge(int index) => Key('rawJsonViewer_typeBadge_$index');
}

/// Screen for viewing raw JSON messages for debugging.
///
/// Displays a list of raw JSON messages with pretty-printing,
/// type-colored badges, and copy functionality.
class RawJsonViewer extends StatelessWidget {
  /// The raw JSON messages to display.
  final List<Map<String, dynamic>> rawMessages;

  /// The title shown in the app bar.
  final String title;

  const RawJsonViewer({
    super.key,
    required this.rawMessages,
    this.title = 'Raw JSON',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final encoder = const JsonEncoder.withIndent('  ');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            key: RawJsonViewerKeys.copyAllButton,
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all to clipboard',
            onPressed: () {
              final allJson =
                  rawMessages.map((m) => encoder.convert(m)).join('\n\n---\n\n');
              Clipboard.setData(ClipboardData(text: allJson));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: rawMessages.isEmpty
          ? Center(
              key: RawJsonViewerKeys.emptyState,
              child: Text(
                'No raw messages available',
                style: TextStyle(color: colorScheme.outline),
              ),
            )
          : ListView.separated(
              key: RawJsonViewerKeys.messageList,
              padding: const EdgeInsets.all(16),
              itemCount: rawMessages.length,
              separatorBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child:
                    Divider(color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
              itemBuilder: (context, index) {
                final message = rawMessages[index];
                final prettyJson = encoder.convert(message);
                final messageType = message['type'] as String? ?? 'unknown';

                return Column(
                  key: RawJsonViewerKeys.messageItem(index),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Message header
                    Row(
                      children: [
                        Container(
                          key: RawJsonViewerKeys.typeBadge(index),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getTypeColor(messageType, colorScheme),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            messageType.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          key: RawJsonViewerKeys.copyButton(index),
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Copy this message',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: prettyJson));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // JSON content
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: SelectableText(
                        prettyJson,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Color _getTypeColor(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'assistant':
        return colorScheme.primary;
      case 'user':
        return colorScheme.secondary;
      case 'system':
        return colorScheme.tertiary;
      case 'result':
        return Colors.green;
      case 'error':
        return colorScheme.error;
      default:
        return colorScheme.outline;
    }
  }
}
