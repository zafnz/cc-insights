import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'keyboard_focus_manager.dart';

/// Test keys for EditableLabel widget.
class EditableLabelKeys {
  EditableLabelKeys._();

  /// The text field (editing mode).
  static const textField = Key('editable_label_field');
}

/// A text label that switches to an editable TextField on double-click.
///
/// This widget displays text normally, but when double-clicked (two clicks
/// within 300ms), it switches to an inline text field allowing the user to
/// edit the text. The edit is submitted on Enter or when focus is lost, and
/// cancelled on Escape.
///
/// The first click triggers [onTap] immediately for instant selection feedback.
/// The second click (if within 300ms) enters edit mode.
///
/// Example:
/// ```dart
/// EditableLabel(
///   text: chat.name,
///   style: textTheme.bodyMedium,
///   onTap: () => selectChat(chat),
///   onSubmit: (newName) => chat.rename(newName),
/// )
/// ```
class EditableLabel extends StatefulWidget {
  const EditableLabel({
    super.key,
    required this.text,
    required this.onSubmit,
    this.onTap,
    this.style,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines = 1,
    this.validator,
  });

  /// The text to display.
  final String text;

  /// Called when the user submits a new value (Enter or focus lost).
  /// Only called if the text has changed and passes validation.
  final ValueChanged<String> onSubmit;

  /// Called on single tap. If a second tap occurs within 300ms, edit mode
  /// is entered instead.
  final VoidCallback? onTap;

  /// Text style for both display and edit modes.
  final TextStyle? style;

  /// How to handle text overflow in display mode.
  final TextOverflow overflow;

  /// Maximum lines in display mode.
  final int maxLines;

  /// Optional validator. Return null if valid, or an error message if invalid.
  /// If validation fails, the edit is cancelled and original text is restored.
  final String? Function(String)? validator;

  @override
  State<EditableLabel> createState() => _EditableLabelState();
}

class _EditableLabelState extends State<EditableLabel> {
  bool _isEditing = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  String _originalText = '';

  /// Callback to resume keyboard interception when editing ends.
  VoidCallback? _resumeKeyboardInterception;

  /// Whether we're awaiting a second tap to trigger edit mode.
  bool _awaitingSecondTap = false;

  /// Timer for double-click detection window.
  Timer? _doubleTapTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(EditableLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller if text changed externally while not editing
    if (!_isEditing && widget.text != oldWidget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    // Ensure keyboard interception is resumed if we're disposed while editing
    _resumeKeyboardInterception?.call();
    _doubleTapTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Submit when focus is lost (clicking elsewhere)
    if (!_focusNode.hasFocus && _isEditing) {
      _submitEdit();
    }
  }

  void _enterEditMode() {
    // Suspend global keyboard interception while editing
    _resumeKeyboardInterception =
        KeyboardFocusManager.maybeOf(context)?.suspend();

    setState(() {
      _isEditing = true;
      _originalText = widget.text;
      _controller.text = widget.text;
    });

    // Focus and select all text after the frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _submitEdit() {
    if (!_isEditing) return;

    final newText = _controller.text.trim();

    // Validate: non-empty and passes custom validator
    if (newText.isEmpty) {
      _cancelEdit();
      return;
    }

    if (widget.validator != null) {
      final error = widget.validator!(newText);
      if (error != null) {
        _cancelEdit();
        return;
      }
    }

    // Capture the value before exiting edit mode
    final shouldSubmit = newText != _originalText;

    // Set _isEditing = false BEFORE unfocusing to prevent _onFocusChange
    // from calling _submitEdit() again
    _isEditing = false;

    // Unfocus and resume keyboard interception
    _focusNode.unfocus();
    _resumeKeyboardInterception?.call();
    _resumeKeyboardInterception = null;

    // Trigger rebuild
    setState(() {});

    // Call onSubmit after state update if text actually changed
    if (shouldSubmit) {
      widget.onSubmit(newText);
    }
  }

  void _cancelEdit() {
    // Set _isEditing = false BEFORE unfocusing to prevent _onFocusChange
    // from calling _submitEdit() again
    _isEditing = false;

    // Unfocus and resume keyboard interception
    _focusNode.unfocus();
    _resumeKeyboardInterception?.call();
    _resumeKeyboardInterception = null;

    // Restore original text and trigger rebuild
    _controller.text = _originalText;
    setState(() {});
  }

  /// Handle key events - only Escape needs special handling.
  /// Enter is handled by TextField.onSubmitted.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelEdit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleTap() {
    if (_awaitingSecondTap) {
      // Double-click detected - enter edit mode
      _doubleTapTimer?.cancel();
      _awaitingSecondTap = false;
      _enterEditMode();
    } else {
      // First tap - trigger onTap and start waiting for second tap
      _awaitingSecondTap = true;
      _doubleTapTimer = Timer(const Duration(milliseconds: 300), () {
        _awaitingSecondTap = false;
      });
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Focus(
        onKeyEvent: _handleKeyEvent,
        child: TextField(
          key: EditableLabelKeys.textField,
          controller: _controller,
          focusNode: _focusNode,
          style: widget.style,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _submitEdit(),
        ),
      );
    }

    // Display mode: handle single tap immediately, double-click for edit
    return GestureDetector(
      onTap: _handleTap,
      child: Text(
        widget.text,
        style: widget.style,
        overflow: widget.overflow,
        maxLines: widget.maxLines,
      ),
    );
  }
}
