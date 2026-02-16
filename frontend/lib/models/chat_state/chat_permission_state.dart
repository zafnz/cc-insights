part of 'package:cc_insights_v2/models/chat.dart';

class ChatPermissionState extends ChangeNotifier {
  ChatPermissionState._(this._chat);

  final _ChatCore _chat;

  bool get isWaitingForPermission => _chat.isWaitingForPermission;
  sdk.PermissionRequest? get pendingPermission => _chat.pendingPermission;
  int get pendingPermissionCount => _chat.pendingPermissionCount;
  bool get hasPending => _chat.pendingPermissionCount > 0;

  List<sdk.PermissionRequest> get pendingPermissions =>
      List.unmodifiable(_chat._pendingPermissions);

  void add(sdk.PermissionRequest request) {
    LogService.instance.notice(
      'Permission',
      'Permission requested: tool=${request.toolName}',
      meta: {'chat': _chat._data.name},
    );

    final wasEmpty = _chat._pendingPermissions.isEmpty;
    _chat._pendingPermissions.add(request);
    if (wasEmpty) {
      _chat.session.pauseStopwatchForPermissionWait();
    }

    _chat.metrics.recordPermissionRequestTime(request.toolUseId);
    notifyListeners();

    final worktreeRoot = _chat._data.worktreeRoot;
    if (worktreeRoot != null) {
      NotificationService.instance.notifyPermissionRequest(
        toolName: request.toolName,
        chatName: _chat._data.name,
        worktreeRoot: worktreeRoot,
        chatId: _chat._data.id,
      );
    }
  }

  sdk.PermissionRequest? popFront() {
    if (_chat._pendingPermissions.isEmpty) {
      return null;
    }
    final request = _chat._pendingPermissions.removeAt(0);
    notifyListeners();
    return request;
  }

  void allow({
    Map<String, dynamic>? updatedInput,
    List<dynamic>? updatedPermissions,
  }) {
    if (_chat._pendingPermissions.isEmpty) return;

    final request = _chat._pendingPermissions.removeAt(0);
    _chat.metrics.recordPermissionResponseTime(request.toolUseId);

    LogService.instance.info(
      'Permission',
      'Permission allowed: tool=${request.toolName}',
      meta: {'chat': _chat._data.name},
    );
    request.allow(
      updatedInput: updatedInput,
      updatedPermissions: updatedPermissions,
    );

    _resumeStopwatchIfNoPermissions();
    _chat._eventHandler?.handlePermissionResponse(_chat._facade);
    notifyListeners();
  }

  void deny(String message, {bool interrupt = false}) {
    if (_chat._pendingPermissions.isEmpty) return;

    final request = _chat._pendingPermissions.removeAt(0);
    _chat.metrics.recordPermissionResponseTime(request.toolUseId);

    LogService.instance.info(
      'Permission',
      'Permission denied: tool=${request.toolName}',
      meta: {'chat': _chat._data.name},
    );
    request.deny(message, interrupt: interrupt);

    _resumeStopwatchIfNoPermissions();
    _chat._eventHandler?.handlePermissionResponse(_chat._facade);
    notifyListeners();
  }

  void removeByToolUseId(String toolUseId) {
    final before = _chat._pendingPermissions.length;
    _chat._pendingPermissions.removeWhere((req) => req.toolUseId == toolUseId);
    _chat._permissionRequestTimes.remove(toolUseId);
    if (_chat._pendingPermissions.length == before) return;

    _resumeStopwatchIfNoPermissions();
    notifyListeners();
  }

  void clear() {
    if (_chat._pendingPermissions.isEmpty &&
        _chat._permissionRequestTimes.isEmpty) {
      return;
    }
    _clearInternal();
    notifyListeners();
  }

  void _resumeStopwatchIfNoPermissions() {
    if (_chat._pendingPermissions.isEmpty) {
      _chat.session.resumeStopwatchAfterPermissionWait();
    }
  }

  void _clearInternal() {
    _chat._pendingPermissions.clear();
    _chat._permissionRequestTimes.clear();
  }
}
