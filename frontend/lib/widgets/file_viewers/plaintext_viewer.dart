import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/runtime_config.dart';

/// Displays plaintext files with monospace font.
///
/// This viewer displays text content in a selectable, scrollable area
/// using JetBrains Mono font at 13px. It's used for generic text files
/// that don't have special syntax highlighting requirements.
class PlaintextFileViewer extends StatelessWidget {
  const PlaintextFileViewer({super.key, required this.content});

  /// The text content to display.
  final String content;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectionArea(
          child: Text(
            content,
            style: GoogleFonts.getFont(
              RuntimeConfig.instance.monoFontFamily,
              fontSize: 13,
              color: colorScheme.onSurface,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
