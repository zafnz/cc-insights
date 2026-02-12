import 'dart:async';

import '../backend_interface.dart';
import '../types/backend_commands.dart';
import '../types/callbacks.dart';
import '../types/insights_events.dart';
import 'event_transport.dart';

/// Transport implementation that wraps an in-process [AgentSession].
///
/// This is the default transport used when the backend runs in the same
/// process. It delegates all commands to the wrapped session and forwards
/// the session's event and permission streams.
class InProcessTransport implements EventTransport {
  InProcessTransport({
    required AgentSession session,
    BackendCapabilities? capabilities,
  })  : _session = session,
        _capabilities = capabilities,
        _currentStatus = TransportStatus.connected {
    _eventsSubscription = _session.events.listen(
      _eventsController.add,
      onError: _eventsController.addError,
      onDone: () {
        if (!_disposed) {
          _currentStatus = TransportStatus.disconnected;
          _statusController.add(TransportStatus.disconnected);
        }
        _eventsController.close();
      },
    );

    _permissionsSubscription = _session.permissionRequests.listen(
      (request) {
        _pendingPermissions[request.id] = request;
        _permissionsController.add(request);
      },
      onError: _permissionsController.addError,
      onDone: _permissionsController.close,
    );
  }

  final AgentSession _session;
  final BackendCapabilities? _capabilities;

  final _eventsController = StreamController<InsightsEvent>.broadcast();
  final _statusController = StreamController<TransportStatus>.broadcast();
  final _permissionsController =
      StreamController<PermissionRequest>.broadcast();

  late final StreamSubscription<InsightsEvent> _eventsSubscription;
  late final StreamSubscription<PermissionRequest> _permissionsSubscription;

  final Map<String, PermissionRequest> _pendingPermissions = {};
  TransportStatus _currentStatus;
  bool _disposed = false;

  /// The current transport status.
  TransportStatus get currentStatus => _currentStatus;

  @override
  Stream<InsightsEvent> get events => _eventsController.stream;

  @override
  Stream<TransportStatus> get status => _statusController.stream;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionsController.stream;

  @override
  String? get sessionId => _session.sessionId;

  @override
  String? get resolvedSessionId => _session.resolvedSessionId;

  @override
  BackendCapabilities? get capabilities => _capabilities;

  @override
  String? get serverModel => _session.serverModel;

  @override
  String? get serverReasoningEffort => _session.serverReasoningEffort;

  @override
  Future<void> send(BackendCommand command) async {
    switch (command) {
      case SendMessageCommand(:final text, :final content):
        if (content != null) {
          // Content blocks need to be converted from raw maps to ContentBlock
          // objects. For now, the frontend will handle this conversion before
          // sending. The in-process transport receives pre-built content.
          await _session.send(text);
        } else {
          await _session.send(text);
        }
      case PermissionResponseCommand(
          :final requestId,
          :final allowed,
          :final message,
          :final updatedInput,
          :final updatedPermissions,
          :final interrupt,
        ):
        final request = _pendingPermissions.remove(requestId);
        if (request == null) return;
        if (allowed) {
          request.allow(
            updatedInput: updatedInput,
            updatedPermissions: updatedPermissions,
          );
        } else {
          request.deny(message ?? 'Denied', interrupt: interrupt ?? false);
        }
      case InterruptCommand():
        await _session.interrupt();
      case KillCommand():
        await _session.kill();
      case SetModelCommand(:final model):
        await _session.setModel(model);
      case SetPermissionModeCommand(:final mode):
        await _session.setPermissionMode(mode);
      case SetConfigOptionCommand(:final configId, :final value):
        await _session.setConfigOption(configId, value);
      case SetReasoningEffortCommand(:final effort):
        await _session.setReasoningEffort(effort);
      case CreateSessionCommand():
        // CreateSessionCommand is handled at a higher level (BackendService).
        // The InProcessTransport is already bound to a session.
        throw UnsupportedError(
          'CreateSessionCommand is not supported on InProcessTransport. '
          'Create a session via BackendService first.',
        );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventsSubscription.cancel();
    await _permissionsSubscription.cancel();
    _pendingPermissions.clear();
    _currentStatus = TransportStatus.disconnected;
    _statusController.add(TransportStatus.disconnected);
    await _eventsController.close();
    await _statusController.close();
    await _permissionsController.close();
  }
}
