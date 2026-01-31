import 'dart:async';

import 'package:acp_dart/acp_dart.dart';

/// Represents a pending permission request from an ACP agent.
///
/// When an ACP agent requests permission for a tool operation (such as
/// writing a file or executing a terminal command), a [PendingPermission]
/// is created and added to a stream for the UI to display. The UI calls
/// [allow] or [cancel] to resolve the permission request.
///
/// The [completer] ensures that the agent's request is properly resolved
/// when the user makes a decision. The agent will wait until either
/// [allow] or [cancel] is called before proceeding.
///
/// Example usage:
/// ```dart
/// // In the permission request handler:
/// final pending = PendingPermission(
///   request: permissionRequest,
///   completer: Completer<RequestPermissionResponse>(),
/// );
/// permissionController.add(pending);
///
/// // In the UI when user allows:
/// pending.allow('allow_once');
///
/// // Or when user cancels:
/// pending.cancel();
/// ```
class PendingPermission {
  /// Creates a pending permission request.
  ///
  /// The [request] contains the permission details from the agent,
  /// including the session ID, available options, and tool call information.
  ///
  /// The [completer] is used to resolve the permission request when the
  /// user makes a decision. It will be completed with a
  /// [RequestPermissionResponse] containing either a [SelectedOutcome]
  /// or [CancelledOutcome].
  PendingPermission({
    required this.request,
    required this.completer,
  });

  /// The permission request from the ACP agent.
  ///
  /// Contains the session ID, available permission options (such as
  /// "allow_once", "allow_always", "reject_once", "reject_always"),
  /// and details about the tool call that requires permission.
  final RequestPermissionRequest request;

  /// The completer used to resolve this permission request.
  ///
  /// This completer should only be completed once, either via [allow]
  /// or [cancel]. Completing it multiple times will result in an error.
  final Completer<RequestPermissionResponse> completer;

  /// Whether this permission request has been resolved.
  ///
  /// Returns `true` if either [allow] or [cancel] has been called.
  bool get isResolved => completer.isCompleted;

  /// Allow the permission with the specified option ID.
  ///
  /// The [optionId] should correspond to one of the option IDs from
  /// [request.options], such as "allow_once" or "allow_always".
  ///
  /// This completes the [completer] with a [RequestPermissionResponse]
  /// containing a [SelectedOutcome] with the given option ID.
  ///
  /// Throws a [StateError] if this permission has already been resolved.
  void allow(String optionId) {
    if (completer.isCompleted) {
      throw StateError('Permission request has already been resolved');
    }
    completer.complete(RequestPermissionResponse(
      outcome: SelectedOutcome(optionId: optionId),
    ));
  }

  /// Cancel the permission request.
  ///
  /// This completes the [completer] with a [RequestPermissionResponse]
  /// containing a [CancelledOutcome], signaling to the agent that the
  /// user declined to grant permission.
  ///
  /// Throws a [StateError] if this permission has already been resolved.
  void cancel() {
    if (completer.isCompleted) {
      throw StateError('Permission request has already been resolved');
    }
    completer.complete(RequestPermissionResponse(
      outcome: CancelledOutcome(),
    ));
  }
}
