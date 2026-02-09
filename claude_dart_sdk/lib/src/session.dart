import 'dart:async';

import 'package:meta/meta.dart';

import 'backend_interface.dart';
import 'types/callbacks.dart';
import 'types/content_blocks.dart';
import 'types/insights_events.dart';

/// A test-only session for use in widget and integration tests.
///
/// This class implements [AgentSession] and provides controllable message
/// streams for testing without a real backend process.
///
/// Test sessions can receive messages via [emitTestMessage] and track
/// sent messages via [testSentMessages].
///
/// Example:
/// ```dart
/// final session = TestSession(sessionId: 'test-123');
/// session.emitTestMessage(SDKAssistantMessage(...));
/// ```
class TestSession implements AgentSession {
  /// Creates a test session that is not connected to a real backend.
  @visibleForTesting
  TestSession({
    required this.sessionId,
    this.sdkSessionId,
  });

  /// The session ID (Dart-side).
  @override
  final String sessionId;

  /// The SDK session ID (from Claude Code).
  String? sdkSessionId;

  /// Session ID suitable for resume.
  @override
  String? get resolvedSessionId => sdkSessionId ?? sessionId;

  final _eventsController = StreamController<InsightsEvent>.broadcast();
  final _permissionRequestsController =
      StreamController<PermissionRequest>.broadcast();
  final _hookRequestsController = StreamController<HookRequest>.broadcast();

  /// Stream of insights events.
  @override
  Stream<InsightsEvent> get events => _eventsController.stream;

  /// Stream of permission requests.
  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionRequestsController.stream;

  /// Stream of hook requests.
  @override
  Stream<HookRequest> get hookRequests => _hookRequestsController.stream;

  bool _disposed = false;

  /// Whether the session is active.
  @override
  bool get isActive => !_disposed;

  /// Messages sent via [send].
  @visibleForTesting
  final List<String> testSentMessages = [];

  /// Callback invoked when [send] is called.
  ///
  /// Use this to trigger mock responses when the session receives a message.
  /// Returns a Future to support async operations like permission requests.
  @visibleForTesting
  Future<void> Function(String message)? onTestSend;

  /// Send a follow-up message to the session.
  @override
  Future<void> send(String message) async {
    if (_disposed) return;
    testSentMessages.add(message);
    await onTestSend?.call(message);
  }

  /// Send a message with content blocks (text and images).
  @override
  Future<void> sendWithContent(List<ContentBlock> content) async {
    if (_disposed) return;
    final textParts = content.whereType<TextBlock>().map((b) => b.text);
    testSentMessages.add(textParts.join('\n'));
    await onTestSend?.call(textParts.join('\n'));
  }

  /// Interrupt the current execution (no-op for test sessions).
  @override
  Future<void> interrupt() async {}

  /// Kill the session.
  @override
  Future<void> kill() async {
    if (_disposed) return;
    _dispose();
  }

  /// Set the model (no-op for test sessions).
  @override
  Future<void> setModel(String? model) async {}

  /// Set the permission mode (no-op for test sessions).
  @override
  Future<void> setPermissionMode(String? mode) async {}

  /// Set the reasoning effort level (no-op for test sessions).
  @override
  Future<void> setReasoningEffort(String? effort) async {}

  // ═══════════════════════════════════════════════════════════════════════════
  // Test Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Emits an event to the [events] stream.
  @visibleForTesting
  void emitTestEvent(InsightsEvent event) {
    if (_disposed) return;
    _eventsController.add(event);
  }

  /// Emits a permission request to the [permissionRequests] stream.
  ///
  /// Returns the completer's future so tests can verify the response.
  @visibleForTesting
  Future<PermissionResponse> emitTestPermissionRequest({
    required String id,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? toolUseId,
  }) {
    final completer = Completer<PermissionResponse>();
    final request = PermissionRequest(
      id: id,
      sessionId: sessionId,
      toolName: toolName,
      toolInput: toolInput,
      toolUseId: toolUseId,
      completer: completer,
    );
    _permissionRequestsController.add(request);
    return completer.future;
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _eventsController.close();
    _permissionRequestsController.close();
    _hookRequestsController.close();
  }
}
