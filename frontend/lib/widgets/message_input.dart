import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/output_entry.dart';
import '../services/image_utils.dart';
import 'keyboard_focus_manager.dart';

/// Maximum number of images that can be attached to a single message.
const _maxImages = 5;

/// A message input widget for typing messages with image attachment support.
///
/// This widget handles:
/// - Multi-line text input with shift+enter for new lines
/// - Enter to submit (without shift)
/// - Auto-focus on mount
/// - Focus restoration when the app regains focus
/// - Optional interrupt button when Claude is working
/// - Image paste handling (Cmd+V)
/// - Drag and drop images
/// - Image picker button
///
/// Focus management for keyboard interception is handled at the app level
/// by [KeyboardFocusManager].
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSubmit,
    this.onInterrupt,
    this.onTextChanged,
    this.initialText = '',
    this.placeholder = 'Type a message...',
    this.enabled = true,
    this.autofocus = true,
    this.isWorking = false,
  });

  /// Called when the user submits a message (Enter without Shift).
  /// Includes any attached images.
  final void Function(String text, List<AttachedImage> images) onSubmit;

  /// Called when the user clicks the interrupt button.
  /// If null, the interrupt button is hidden.
  final VoidCallback? onInterrupt;

  /// Called when the text changes (for saving drafts).
  final ValueChanged<String>? onTextChanged;

  /// Initial text to populate the input with.
  final String initialText;

  /// Placeholder text shown when the input is empty.
  final String placeholder;

  /// Whether the input is enabled.
  final bool enabled;

  /// Whether to automatically focus on mount.
  final bool autofocus;

  /// Whether Claude is currently working.
  /// When true, shows an interrupt button.
  final bool isWorking;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<AttachedImage> _pendingImages = [];
  bool _isDragging = false;
  bool _isProcessingImage = false;

  /// Reference to the keyboard focus manager for safe unregistration.
  KeyboardFocusManagerState? _keyboardFocusManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Restore initial text (e.g., draft from previous session)
    if (widget.initialText.isNotEmpty) {
      _controller.text = widget.initialText;
      // Move cursor to end
      _controller.selection = TextSelection.collapsed(
        offset: widget.initialText.length,
      );
    }

    // Listen for text changes to save drafts
    _controller.addListener(_onTextChanged);

    // Auto-focus after the first frame
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _onTextChanged() {
    widget.onTextChanged?.call(_controller.text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register with the keyboard focus manager and save reference
    _keyboardFocusManager = KeyboardFocusManager.maybeOf(context);
    _keyboardFocusManager?.registerMessageInput(_focusNode, _controller);
  }

  @override
  void dispose() {
    // Unregister from the keyboard focus manager using saved reference
    _keyboardFocusManager?.unregisterMessageInput(_focusNode);
    _controller.removeListener(_onTextChanged);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-focus when app comes back to foreground
    if (state == AppLifecycleState.resumed && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _handleSubmit() {
    final text = _controller.text;
    if (text.trim().isEmpty && _pendingImages.isEmpty) return;

    widget.onSubmit(text, List.from(_pendingImages));
    _controller.clear();
    _pendingImages.clear();
    setState(() {});

    // Keep focus after submit
    _focusNode.requestFocus();
  }

  /// Handle key events - Enter submits, Shift+Enter adds newline, Cmd+V pastes.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Handle Enter key
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

        if (!isShiftPressed) {
          // Enter without shift - submit
          _handleSubmit();
          return KeyEventResult.handled;
        }
        // Shift+Enter - let the TextField handle it (inserts newline)
      }

      // Handle Cmd+V (paste) on macOS or Ctrl+V on other platforms
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
        final isControlPressed = HardwareKeyboard.instance.isControlPressed;
        final isPasteShortcut =
            (Platform.isMacOS && isMetaPressed) ||
            (!Platform.isMacOS && isControlPressed);

        if (isPasteShortcut) {
          _handlePaste();
          // Don't mark as handled - let text paste through if no image
          return KeyEventResult.ignored;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  /// Handle paste from clipboard - checks for images.
  Future<void> _handlePaste() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final reader = await clipboard.read();

    // Check for image formats in priority order
    for (final format in [Formats.png, Formats.jpeg, Formats.gif]) {
      if (reader.canProvide(format)) {
        // getFile uses a callback pattern
        reader.getFile(format, (file) async {
          final stream = file.getStream();
          final chunks = <List<int>>[];
          await for (final chunk in stream) {
            chunks.add(chunk);
          }
          final data = Uint8List.fromList(
            chunks.expand((chunk) => chunk).toList(),
          );
          final mediaType = _formatToMediaType(format);
          await _addImageData(data, mediaType);
        });
        return;
      }
    }
  }

  /// Convert super_clipboard format to MIME type.
  String _formatToMediaType(DataFormat format) {
    if (format == Formats.png) return 'image/png';
    if (format == Formats.jpeg) return 'image/jpeg';
    if (format == Formats.gif) return 'image/gif';
    return 'image/png'; // Default
  }

  /// Handle drag and drop files.
  Future<void> _handleDrop(DropDoneDetails details) async {
    for (final file in details.files) {
      final path = file.path;
      if (path.isEmpty) continue;

      final extension = path.split('.').last;
      if (!isSupportedImageExtension(extension)) continue;

      final bytes = await File(path).readAsBytes();
      final mediaType = getMimeTypeFromExtension(extension);
      await _addImageData(bytes, mediaType);
    }
  }

  /// Pick images from file system.
  Future<void> _pickImages() async {
    if (_pendingImages.length >= _maxImages) {
      _showMaxImagesWarning();
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result == null) return;

    for (final file in result.files) {
      if (_pendingImages.length >= _maxImages) {
        _showMaxImagesWarning();
        break;
      }

      if (file.bytes != null && file.extension != null) {
        final mediaType = getMimeTypeFromExtension(file.extension!);
        await _addImageData(file.bytes!, mediaType);
      }
    }
  }

  /// Add image data with processing/compression.
  Future<void> _addImageData(Uint8List data, String mediaType) async {
    if (_pendingImages.length >= _maxImages) {
      _showMaxImagesWarning();
      return;
    }

    setState(() => _isProcessingImage = true);

    try {
      final result = await processImage(data, mediaType);
      if (!mounted) return;

      setState(() {
        _pendingImages.add(AttachedImage(
          data: result.data,
          mediaType: result.mediaType,
        ));
        _isProcessingImage = false;
      });
    } on ImageProcessingError catch (e) {
      if (!mounted) return;
      setState(() => _isProcessingImage = false);
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessingImage = false);
      _showError('Failed to process image');
    }
  }

  /// Remove an image at the given index.
  void _removeImage(int index) {
    setState(() {
      _pendingImages.removeAt(index);
    });
  }

  /// Show warning when max images is reached.
  void _showMaxImagesWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Maximum $_maxImages images per message'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Show an error message.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _handleDrop(details);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: _isDragging
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: _isDragging ? 2 : 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image previews
            if (_pendingImages.isNotEmpty) ...[
              _ImagePreviewRow(
                images: _pendingImages,
                onRemove: _removeImage,
              ),
              const SizedBox(height: 8),
            ],
            // Processing indicator
            if (_isProcessingImage) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Interrupt button - shown when Claude is working
                if (widget.isWorking && widget.onInterrupt != null)
                  _InterruptButton(onPressed: widget.onInterrupt!),
                // Image attachment button
                _ImageAttachButton(
                  onPressed: widget.enabled ? _pickImages : null,
                  imageCount: _pendingImages.length,
                  maxImages: _maxImages,
                ),
                const SizedBox(width: 8),
                // Text input field
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleKeyEvent,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      style: textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: _isDragging
                            ? 'Drop images here...'
                            : widget.placeholder,
                        hintStyle: textTheme.bodyMedium?.copyWith(
                          color:
                              colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color:
                                colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color:
                                colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color:
                                colorScheme.outlineVariant.withValues(
                                  alpha: 0.3,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                _SendButton(
                  onPressed: widget.enabled ? _handleSubmit : null,
                  isEmpty:
                      _controller.text.trim().isEmpty &&
                      _pendingImages.isEmpty,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of image previews with remove buttons.
class _ImagePreviewRow extends StatelessWidget {
  const _ImagePreviewRow({
    required this.images,
    required this.onRemove,
  });

  final List<AttachedImage> images;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return _ImagePreviewTile(
            image: images[index],
            onRemove: () => onRemove(index),
          );
        },
      ),
    );
  }
}

/// Single image preview tile with remove button.
class _ImagePreviewTile extends StatelessWidget {
  const _ImagePreviewTile({
    required this.image,
    required this.onRemove,
  });

  final AttachedImage image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.memory(
              image.data,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image,
                color: colorScheme.error,
              ),
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 14,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Image attachment button.
class _ImageAttachButton extends StatelessWidget {
  const _ImageAttachButton({
    required this.onPressed,
    required this.imageCount,
    required this.maxImages,
  });

  final VoidCallback? onPressed;
  final int imageCount;
  final int maxImages;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAtMax = imageCount >= maxImages;

    return Tooltip(
      message: isAtMax
          ? 'Maximum $maxImages images'
          : 'Attach images (${imageCount}/$maxImages)',
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(
              Icons.image_outlined,
              size: 20,
              color: isAtMax
                  ? colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Interrupt button to stop Claude while working.
class _InterruptButton extends StatelessWidget {
  const _InterruptButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Stop (preserves context)',
        child: Material(
          color: Colors.orange.shade700,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: const Icon(
                Icons.stop_circle_outlined,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Send button with visual feedback.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.onPressed,
    required this.isEmpty,
  });

  final VoidCallback? onPressed;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: onPressed == null || isEmpty
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            Icons.send,
            size: 20,
            color: onPressed == null || isEmpty
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                : colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
