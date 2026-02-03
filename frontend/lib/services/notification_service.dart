import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// Data emitted when a user clicks a desktop notification.
///
/// Contains the worktree path and chat ID needed to navigate
/// the UI to the relevant chat.
@immutable
class NotificationNavigationEvent {
  /// The worktree root path where the chat lives.
  final String worktreeRoot;

  /// The unique ID of the chat that triggered the notification.
  final String chatId;

  const NotificationNavigationEvent({
    required this.worktreeRoot,
    required this.chatId,
  });
}

/// Service for sending desktop notifications.
///
/// Used to notify the user when a permission request is pending,
/// especially when the app is in the background.
///
/// When the user clicks a notification, a [NotificationNavigationEvent]
/// is emitted on [navigationEvents] so the app can navigate to the
/// relevant worktree and chat.
class NotificationService {
  static NotificationService? _instance;

  /// Gets the singleton instance of the notification service.
  static NotificationService get instance {
    _instance ??= NotificationService._();
    return _instance!;
  }

  NotificationService._();

  bool _isInitialized = false;

  final StreamController<NotificationNavigationEvent> _navigationController =
      StreamController<NotificationNavigationEvent>.broadcast();

  /// Stream of navigation events triggered by notification clicks.
  ///
  /// Listen to this stream to navigate the UI when the user clicks
  /// a desktop notification.
  Stream<NotificationNavigationEvent> get navigationEvents =>
      _navigationController.stream;

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
  /// The [worktreeRoot] and [chatId] are used for navigation when clicked.
  Future<void> notifyPermissionRequest({
    required String toolName,
    required String chatName,
    required String worktreeRoot,
    required String chatId,
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

      notification.onClick = () {
        _navigationController.add(
          NotificationNavigationEvent(
            worktreeRoot: worktreeRoot,
            chatId: chatId,
          ),
        );
      };

      await notification.show();
    } catch (_) {
      // Notification failed - ignore
    }
  }

  /// Sends a notification for a user question from Claude.
  ///
  /// The [chatName] is the name of the chat where Claude asked a question.
  /// The [worktreeRoot] and [chatId] are used for navigation when clicked.
  Future<void> notifyUserQuestion({
    required String chatName,
    required String worktreeRoot,
    required String chatId,
  }) async {
    if (!_isInitialized) return;

    try {
      final notification = LocalNotification(
        title: 'Question from Claude',
        body: '$chatName: Claude is asking a question',
      );

      notification.onClick = () {
        _navigationController.add(
          NotificationNavigationEvent(
            worktreeRoot: worktreeRoot,
            chatId: chatId,
          ),
        );
      };

      await notification.show();
    } catch (_) {
      // Notification failed - ignore
    }
  }

  /// Disposes the navigation stream controller.
  void dispose() {
    _navigationController.close();
  }
}
