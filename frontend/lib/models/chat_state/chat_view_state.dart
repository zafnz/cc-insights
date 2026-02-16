part of 'package:cc_insights_v2/models/chat.dart';

class ChatViewState extends ChangeNotifier {
  ChatViewState._(this._chat);

  final _ChatCore _chat;

  String _draftText = '';
  int _unreadCount = 0;
  bool _isBeingViewed = false;

  String get draftText => _draftText;
  set draftText(String value) {
    _draftText = value;
  }

  int get unreadCount => _unreadCount;
  bool get hasUnreadMessages => _unreadCount > 0;
  bool get isBeingViewed => _isBeingViewed;

  /// Marks this chat as being viewed and clears unread count.
  ///
  /// Preserves existing behavior by only notifying when unread count changes.
  void markAsViewed() {
    final hadUnread = _unreadCount > 0;
    _unreadCount = 0;
    _isBeingViewed = true;
    if (hadUnread) {
      notifyListeners();
    }
  }

  /// Marks this chat as no longer being viewed.
  ///
  /// Preserves existing behavior by not notifying listeners.
  void markAsNotViewed() {
    _isBeingViewed = false;
  }

  /// Increments unread count only when the chat is not currently viewed.
  ///
  /// Calls Chat notify to preserve existing compatibility behavior.
  void incrementUnread() {
    if (_isBeingViewed) return;
    _unreadCount++;
    notifyListeners();
  }
}
