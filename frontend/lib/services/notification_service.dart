import 'package:local_notifier/local_notifier.dart';

/// Service for sending desktop notifications.
///
/// Used to notify the user when a permission request is pending,
/// especially when the app is in the background.
class NotificationService {
  static NotificationService? _instance;

  /// Gets the singleton instance of the notification service.
  static NotificationService get instance {
    _instance ??= NotificationService._();
    return _instance!;
  }

  NotificationService._();

  bool _isInitialized = false;

  /// Initializes the notification service.
  ///
  /// Must be called once before sending notifications.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await localNotifier.setup(
        appName: 'CC Insights',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _isInitialized = true;
    } catch (_) {
      // Initialization failed - notifications will be disabled
    }
  }

  /// Sends a notification for a pending permission request.
  ///
  /// The [toolName] is the name of the tool requesting permission.
  /// The [chatName] is the name of the chat where the request occurred.
  Future<void> notifyPermissionRequest({
    required String toolName,
    required String chatName,
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      final notification = LocalNotification(
        identifier: 'perm-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Permission Required',
        body: '$chatName: $toolName is waiting for approval',
      );

      await notification.show();
    } catch (_) {
      // Notification failed - ignore
    }
  }

  /// Sends a notification for a user question from Claude.
  ///
  /// The [chatName] is the name of the chat where Claude asked a question.
  Future<void> notifyUserQuestion({
    required String chatName,
  }) async {
    if (!_isInitialized) return;

    try {
      final notification = LocalNotification(
        title: 'Question from Claude',
        body: '$chatName: Claude is asking a question',
      );

      await notification.show();
    } catch (_) {
      // Notification failed - ignore
    }
  }
}
