import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dialog_observer.dart';

/// Manages keyboard focus for the application.
///
/// Intercepts keyboard input at the app level and redirects typing keys
/// to the message input when it doesn't have focus. This provides a
/// terminal-like experience where you can start typing from anywhere
/// and the input receives the keystrokes.
///
/// Keys that are intercepted (when message input doesn't have focus):
/// - Letters (a-z, A-Z)
/// - Numbers (0-9)
/// - Symbols and punctuation
/// - Space
///
/// Keys that are NOT intercepted:
/// - Modifier keys alone (Cmd, Ctrl, Alt, Shift)
/// - Keyboard shortcuts (Cmd+C, Cmd+V, etc.)
/// - Arrow keys
/// - Function keys (F1-F12)
/// - Escape, Tab
/// - Enter (handled by the input itself)
class KeyboardFocusManager extends StatefulWidget {
  const KeyboardFocusManager({
    super.key,
    required this.child,
    this.dialogObserver,
    this.onEscapePressed,
    this.onNewChatShortcut,
    this.onNewWorktreeShortcut,
  });

  final Widget child;

  /// Optional [DialogObserver] to automatically suspend keyboard interception
  /// while dialogs are open.
  ///
  /// When provided, keyboard interception is automatically suspended when
  /// a dialog opens and resumed when it closes.
  final DialogObserver? dialogObserver;

  /// Called when the Escape key is pressed (no modifiers).
  /// Typically used to interrupt the active chat session.
  final VoidCallback? onEscapePressed;

  /// Called when Cmd+Shift+N (macOS) or Ctrl+Shift+N is pressed.
  /// Typically used to create a new chat session.
  final VoidCallback? onNewChatShortcut;

  /// Called when Cmd+N (macOS) or Ctrl+N is pressed.
  /// Typically used to show the create worktree panel.
  final VoidCallback? onNewWorktreeShortcut;

  /// Find the nearest [KeyboardFocusManagerState] in the widget tree.
  static KeyboardFocusManagerState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<KeyboardFocusManagerState>();
  }

  @override
  State<KeyboardFocusManager> createState() => KeyboardFocusManagerState();
}

class KeyboardFocusManagerState extends State<KeyboardFocusManager> {
  /// The focus node for the message input that should receive typing keys.
  FocusNode? _messageInputFocusNode;

  /// The text controller for the message input (for inserting characters).
  TextEditingController? _messageInputController;

  /// Track physical keys we've handled to avoid duplicate KeyDown events.
  /// This prevents Flutter's "key already pressed" warnings.
  final Set<PhysicalKeyboardKey> _handledKeys = {};

  /// Count of active suspensions. Keyboard interception is disabled when > 0.
  /// Using a counter allows nested suspensions (multiple widgets can suspend).
  int _suspendCount = 0;

  /// Whether keyboard interception is currently suspended.
  bool get isSuspended => _suspendCount > 0;

  /// Suspend keyboard interception temporarily.
  ///
  /// Call this when another widget needs to capture keyboard input
  /// (e.g., inline text editing). Must be paired with [resume].
  ///
  /// Returns a [VoidCallback] that can be used to resume, for convenience
  /// with cleanup patterns.
  ///
  /// Example:
  /// ```dart
  /// final resume = KeyboardFocusManager.maybeOf(context)?.suspend();
  /// // ... do something that needs keyboard input ...
  /// resume?.call();
  /// ```
  VoidCallback suspend() {
    _suspendCount++;
    final caller = _callerFromStack(StackTrace.current);
    debugPrint(
      '[KeyboardFocusManager] SUSPENDED by $caller '
      '(suspendCount=$_suspendCount)',
    );
    var resumed = false;
    return () {
      if (!resumed) {
        resumed = true;
        resume(caller);
      }
    };
  }

  /// Resume keyboard interception after a [suspend] call.
  void resume([String? caller]) {
    if (_suspendCount > 0) {
      _suspendCount--;
      debugPrint(
        '[KeyboardFocusManager] RESUMED by ${caller ?? _callerFromStack(StackTrace.current)} '
        '(suspendCount=$_suspendCount)',
      );
    }
  }

  /// Extract a short caller description from a stack trace.
  static String _callerFromStack(StackTrace stack) {
    final lines = stack.toString().split('\n');
    // Skip frame 0 (this method) and frame 1 (suspend/resume),
    // return frame 2 which is the actual caller.
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      // Skip frames inside this class
      if (line.contains('KeyboardFocusManagerState.suspend') ||
          line.contains('KeyboardFocusManagerState.resume') ||
          line.contains('KeyboardFocusManagerState._callerFromStack')) {
        continue;
      }
      return line;
    }
    return 'unknown';
  }

  /// Tracks if we're currently suspended due to a dialog.
  /// Used to pair suspend/resume calls from the dialog observer.
  bool _suspendedForDialog = false;

  @override
  void initState() {
    super.initState();
    // Register global keyboard handler
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);

    // Connect to dialog observer if provided
    _connectDialogObserver();
  }

  void _connectDialogObserver() {
    final observer = widget.dialogObserver;
    if (observer == null) return;

    observer.onDialogOpened = _onDialogOpened;
    observer.onDialogClosed = _onDialogClosed;

    // If a dialog is already open when we connect, suspend immediately
    if (observer.hasOpenDialog && !_suspendedForDialog) {
      _suspendedForDialog = true;
      _suspendCount++;
      debugPrint(
        '[KeyboardFocusManager] SUSPENDED by DialogObserver '
        '(already-open dialog on connect, '
        'suspendCount=$_suspendCount)',
      );
    }
  }

  void _disconnectDialogObserver() {
    final observer = widget.dialogObserver;
    if (observer == null) return;

    observer.onDialogOpened = null;
    observer.onDialogClosed = null;

    // Clean up any suspension we added
    if (_suspendedForDialog) {
      _suspendedForDialog = false;
      if (_suspendCount > 0) {
        _suspendCount--;
        debugPrint(
          '[KeyboardFocusManager] RESUMED by DialogObserver '
          '(disconnect cleanup, suspendCount=$_suspendCount)',
        );
      }
    }
  }

  void _onDialogOpened() {
    if (!_suspendedForDialog) {
      _suspendedForDialog = true;
      _suspendCount++;
      debugPrint(
        '[KeyboardFocusManager] SUSPENDED by DialogObserver '
        '(dialog opened, suspendCount=$_suspendCount)',
      );
    }
  }

  void _onDialogClosed() {
    // Only resume if we're the ones who suspended and no more dialogs are open
    final observer = widget.dialogObserver;
    if (_suspendedForDialog && (observer == null || !observer.hasOpenDialog)) {
      _suspendedForDialog = false;
      if (_suspendCount > 0) {
        _suspendCount--;
        debugPrint(
          '[KeyboardFocusManager] RESUMED by DialogObserver '
          '(dialog closed, suspendCount=$_suspendCount)',
        );
      }
    }
  }

  @override
  void didUpdateWidget(KeyboardFocusManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialogObserver != widget.dialogObserver) {
      _disconnectDialogObserver();
      _connectDialogObserver();
    }
  }

  @override
  void dispose() {
    _disconnectDialogObserver();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _handledKeys.clear();
    super.dispose();
  }

  /// Register a focus node and controller as the primary typing target.
  void registerMessageInput(FocusNode focusNode, TextEditingController controller) {
    _messageInputFocusNode = focusNode;
    _messageInputController = controller;
  }

  /// Unregister the message input.
  void unregisterMessageInput(FocusNode focusNode) {
    if (_messageInputFocusNode == focusNode) {
      _messageInputFocusNode = null;
      _messageInputController = null;
    }
  }

  /// Global keyboard event handler.
  bool _handleGlobalKeyEvent(KeyEvent event) {
    // If suspended, don't intercept any keys
    if (isSuspended) {
      _handledKeys.clear();
      return false;
    }

    // Handle app-level keyboard shortcuts before typing-key logic.
    // These work regardless of message input focus state.
    if (event is KeyDownEvent) {
      final handled = _handleShortcut(event);
      if (handled) return true;
    }

    final messageInput = _messageInputFocusNode;
    final controller = _messageInputController;
    if (messageInput == null || controller == null) return false;

    // If the message input already has focus, don't intercept
    if (messageInput.hasFocus) {
      _handledKeys.clear();
      return false;
    }

    // Track key up events to clear our handled state
    if (event is KeyUpEvent) {
      _handledKeys.remove(event.physicalKey);
      return false;
    }

    // Only handle key down events
    if (event is! KeyDownEvent) return false;

    // Ignore if we already handled this physical key (prevents duplicate events)
    if (_handledKeys.contains(event.physicalKey)) {
      return false;
    }

    // Check if this is a typing key
    if (!_isTypingKey(event)) return false;

    final key = event.logicalKey;

    // Handle backspace
    if (key == LogicalKeyboardKey.backspace) {
      _handledKeys.add(event.physicalKey);
      messageInput.requestFocus();
      final text = controller.text;
      final selection = controller.selection;

      // Handle uninitialized selection (treat as cursor at end)
      final start = selection.isValid ? selection.start : text.length;
      final end = selection.isValid ? selection.end : text.length;

      if (start > 0 || start != end) {
        final deleteStart = start == end ? start - 1 : start;
        final newText = text.replaceRange(deleteStart, end, '');
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: deleteStart),
        );
      }
      return true;
    }

    // Handle delete
    if (key == LogicalKeyboardKey.delete) {
      _handledKeys.add(event.physicalKey);
      messageInput.requestFocus();
      final text = controller.text;
      final selection = controller.selection;

      // Handle uninitialized selection (treat as cursor at end)
      final start = selection.isValid ? selection.start : text.length;
      final end = selection.isValid ? selection.end : text.length;

      if (end < text.length || start != end) {
        final deleteEnd = start == end ? end + 1 : end;
        final newText = text.replaceRange(start, deleteEnd, '');
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start),
        );
      }
      return true;
    }

    // Get the character from the event
    final character = event.character;
    if (character == null || character.isEmpty) {
      // No printable character - just focus the input
      messageInput.requestFocus();
      return false;
    }

    // Mark this key as handled before making changes
    _handledKeys.add(event.physicalKey);

    // Focus the input and insert the character
    messageInput.requestFocus();

    // Insert the character at the current cursor position
    final text = controller.text;
    final selection = controller.selection;

    // Handle uninitialized or invalid selection (append to end)
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    final newText = text.replaceRange(start, end, character);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + character.length),
    );

    // We handled the event - don't let it propagate further
    return true;
  }

  /// Handle app-level keyboard shortcuts.
  /// Returns true if a shortcut was consumed.
  bool _handleShortcut(KeyDownEvent event) {
    final key = event.logicalKey;
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isCmdOrCtrl = isMetaPressed || isControlPressed;

    // Escape (no modifiers) - interrupt active chat
    if (key == LogicalKeyboardKey.escape &&
        !isMetaPressed &&
        !isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      widget.onEscapePressed?.call();
      return widget.onEscapePressed != null;
    }

    // Cmd+N / Ctrl+N - new worktree
    if (key == LogicalKeyboardKey.keyN &&
        isCmdOrCtrl &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onNewWorktreeShortcut?.call();
      return widget.onNewWorktreeShortcut != null;
    }

    // Cmd+Shift+N / Ctrl+Shift+N - new chat
    if (key == LogicalKeyboardKey.keyN &&
        isCmdOrCtrl &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.onNewChatShortcut?.call();
      return widget.onNewChatShortcut != null;
    }

    return false;
  }

  /// Check if a key event represents a "typing" key that should be
  /// redirected to the message input.
  bool _isTypingKey(KeyEvent event) {
    final key = event.logicalKey;

    // Check for modifier keys being held
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;

    // Don't intercept keyboard shortcuts (Cmd+X, Ctrl+X, Alt+X)
    if (isMetaPressed || isControlPressed || isAltPressed) {
      return false;
    }

    // Don't intercept these keys (but allow backspace/delete for editing)
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.enter) {
      return false;
    }

    // Don't intercept arrow keys
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return false;
    }

    // Don't intercept function keys
    if (_isFunctionKey(key)) return false;

    // Don't intercept modifier keys alone
    if (_isModifierKey(key)) return false;

    // Don't intercept navigation keys
    if (key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown) {
      return false;
    }

    // Everything else (letters, numbers, symbols, space) should be typing
    return true;
  }

  bool _isFunctionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.f1 ||
        key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.f3 ||
        key == LogicalKeyboardKey.f4 ||
        key == LogicalKeyboardKey.f5 ||
        key == LogicalKeyboardKey.f6 ||
        key == LogicalKeyboardKey.f7 ||
        key == LogicalKeyboardKey.f8 ||
        key == LogicalKeyboardKey.f9 ||
        key == LogicalKeyboardKey.f10 ||
        key == LogicalKeyboardKey.f11 ||
        key == LogicalKeyboardKey.f12;
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
