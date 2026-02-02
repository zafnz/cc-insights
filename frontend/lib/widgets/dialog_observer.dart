import 'package:flutter/material.dart';

/// Navigator observer that tracks when dialogs and popups are open.
///
/// This observer automatically detects when modal routes (dialogs, bottom sheets,
/// popup menus, etc.) are pushed or popped from the navigator stack.
///
/// Use this with [KeyboardFocusManager] to automatically suspend keyboard
/// interception while dialogs are open, allowing text fields in dialogs
/// to receive keyboard input normally.
///
/// Example usage:
/// ```dart
/// final dialogObserver = DialogObserver();
///
/// MaterialApp(
///   navigatorObservers: [dialogObserver],
///   home: KeyboardFocusManager(
///     dialogObserver: dialogObserver,
///     child: MyApp(),
///   ),
/// );
/// ```
class DialogObserver extends NavigatorObserver {
  /// Callback invoked when a dialog or popup is opened.
  VoidCallback? onDialogOpened;

  /// Callback invoked when a dialog or popup is closed.
  VoidCallback? onDialogClosed;

  /// Count of currently open dialogs/popups.
  int _dialogCount = 0;

  /// Whether any dialog or popup is currently open.
  bool get hasOpenDialog => _dialogCount > 0;

  /// Current count of open dialogs (for debugging).
  int get dialogCount => _dialogCount;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isModalRoute(route)) {
      _dialogCount++;
      onDialogOpened?.call();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isModalRoute(route)) {
      _dialogCount = (_dialogCount - 1).clamp(0, _dialogCount);
      onDialogClosed?.call();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isModalRoute(route)) {
      _dialogCount = (_dialogCount - 1).clamp(0, _dialogCount);
      onDialogClosed?.call();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    // Handle the old route being removed
    if (oldRoute != null && _isModalRoute(oldRoute)) {
      _dialogCount = (_dialogCount - 1).clamp(0, _dialogCount);
      onDialogClosed?.call();
    }

    // Handle the new route being added
    if (newRoute != null && _isModalRoute(newRoute)) {
      _dialogCount++;
      onDialogOpened?.call();
    }
  }

  /// Determines if a route is a modal route (dialog, popup, bottom sheet, etc.).
  bool _isModalRoute(Route<dynamic> route) {
    // DialogRoute is used by showDialog()
    // PopupRoute is the base class for menus, tooltips, etc.
    // ModalBottomSheetRoute is used by showModalBottomSheet()
    return route is DialogRoute ||
        route is PopupRoute ||
        route is RawDialogRoute ||
        // Check route settings name for common dialog patterns
        (route.settings.name?.contains('dialog') ?? false);
  }
}
