import 'dart:async';

import '../backend_interface.dart';
import '../types/backend_commands.dart';
import '../types/callbacks.dart';
import '../types/insights_events.dart';

/// Status of a transport connection.
enum TransportStatus {
  connecting,
  connected,
  disconnected,
  error,
}

/// Abstract interface for event transport between frontend and backend.
///
/// The transport sits between the UI layer (ChatState) and the backend
/// (AgentSession), providing a uniform interface that can be implemented
/// for in-process sessions, WebSocket connections, or other transports.
abstract class EventTransport {
  /// Incoming events from the backend.
  Stream<InsightsEvent> get events;

  /// Send a command to the backend.
  Future<void> send(BackendCommand command);

  /// Connection/session status.
  Stream<TransportStatus> get status;

  /// The session ID (available after session creation).
  String? get sessionId;

  /// The resolved session ID for resuming (may differ from [sessionId]).
  String? get resolvedSessionId;

  /// Backend capabilities.
  BackendCapabilities? get capabilities;

  /// Stream of permission requests requiring interactive response.
  ///
  /// For in-process transports, this forwards the session's
  /// [PermissionRequest] stream (with Completers for allow/deny).
  /// Remote transports will use [PermissionResponseCommand] instead.
  Stream<PermissionRequest> get permissionRequests;

  /// Clean up resources.
  Future<void> dispose();
}
