import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/runtime_config.dart';

/// A file path widget that displays file info and supports Cmd/Ctrl+click to open.
class FilePathWidget extends StatelessWidget {
  final String filePath;
  final IconData icon;
  final String? projectDir;
  final List<String>? extraInfo;

  const FilePathWidget({
    super.key,
    required this.filePath,
    required this.icon,
    this.projectDir,
    this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: ClickableFilePath(
            filePath: filePath,
            extraInfo: extraInfo,
            projectDir: projectDir,
            onOpen: () => _openFile(filePath),
          ),
        ),
      ],
    );
  }

  void _openFile(String path) {
    // Resolve relative paths using projectDir if available
    String fullPath = path;
    if (!path.startsWith('/') && projectDir != null) {
      fullPath = '$projectDir/$path';
    }

    final uri = Uri.file(fullPath);
    launchUrl(uri);
  }
}

/// A file path widget that is selectable and Cmd/Ctrl+clickable.
///
/// Shows a hand cursor when the modifier key is pressed.
class ClickableFilePath extends StatefulWidget {
  final String filePath;
  final List<String>? extraInfo;
  final String? projectDir;
  final VoidCallback onOpen;

  const ClickableFilePath({
    super.key,
    required this.filePath,
    required this.onOpen,
    this.extraInfo,
    this.projectDir,
  });

  @override
  State<ClickableFilePath> createState() => ClickableFilePathState();
}

class ClickableFilePathState extends State<ClickableFilePath> {
  bool _isHovering = false;
  bool _modifierPressed = false;
  int _lastPointerDevice = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // Only update if we're hovering over this widget
    if (!_isHovering) return false;

    final isModifierKey = Platform.isMacOS
        ? event.logicalKey == LogicalKeyboardKey.metaLeft ||
            event.logicalKey == LogicalKeyboardKey.metaRight
        : event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight;

    if (isModifierKey) {
      final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
      if (_modifierPressed != isDown) {
        setState(() => _modifierPressed = isDown);
        // Directly set the system cursor via method channel
        final cursorKind = isDown ? 'click' : 'text';
        SystemChannels.mouseCursor.invokeMethod<void>(
          'activateSystemCursor',
          <String, dynamic>{
            'device': _lastPointerDevice,
            'kind': cursorKind,
          },
        );
      }
    }
    return false;
  }

  void _updateModifierState() {
    final isPressed = Platform.isMacOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (_modifierPressed != isPressed) {
      setState(() => _modifierPressed = isPressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return MouseRegion(
      cursor: _modifierPressed
          ? SystemMouseCursors.click
          : SystemMouseCursors.text,
      onEnter: (event) {
        _isHovering = true;
        _lastPointerDevice = event.device;
        _updateModifierState();
      },
      onExit: (_) {
        _isHovering = false;
        if (_modifierPressed) {
          setState(() => _modifierPressed = false);
        }
      },
      onHover: (event) {
        _lastPointerDevice = event.device;
        _updateModifierState();
      },
      child: Listener(
        onPointerDown: (event) {
          final isModifierPressed = Platform.isMacOS
              ? HardwareKeyboard.instance.isMetaPressed
              : HardwareKeyboard.instance.isControlPressed;

          if (isModifierPressed && event.buttons == kPrimaryButton) {
            widget.onOpen();
          }
        },
        child: SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: widget.filePath,
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              ),
              if (widget.extraInfo != null &&
                  widget.extraInfo!.isNotEmpty) ...[
                TextSpan(
                  text: ' (${widget.extraInfo!.join(", ")})',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
