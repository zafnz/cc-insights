import 'dart:async';

import 'package:acp_dart/acp_dart.dart';

import 'pending_permission.dart';

/// Wrapper around an ACP session with Provider-friendly streams.
///
/// This class filters the global update and permission request streams from
/// [ACPClientWrapper] to only include events for a specific session. It also
/// provides convenience methods for sending prompts, canceling operations,
/// and changing the session mode.
///
/// The session wrapper is created by [ACPClientWrapper.createSession] and
/// should not be instantiated directly.
///
/// Example usage:
/// ```dart
/// // Create a session through the client wrapper
/// final session = await clientWrapper.createSession(cwd: '/path/to/project');
///
/// // Listen for session updates
/// session.updates.listen((update) {
///   if (update is AgentMessageChunkSessionUpdate) {
///     print('Agent: ${(update.content as TextContentBlock).text}');
///   }
/// });
///
/// // Listen for permission requests
/// session.permissionRequests.listen((pending) {
///   // Show permission dialog, then:
///   pending.allow('allow_once');
/// });
///
/// // Send a prompt
/// final response = await session.prompt([TextContentBlock(text: 'Hello!')]);
/// print('Stop reason: ${response.stopReason}');
///
/// // Cancel if needed
/// await session.cancel();
///
/// // Clean up when done
/// session.dispose();
/// ```
class ACPSessionWrapper {
  /// Creates a session wrapper.
  ///
  /// This constructor filters the global [updates] and [permissionRequests]
  /// streams to only include events for [sessionId].
  ///
  /// Parameters:
  /// - [connection]: The underlying ACP connection for sending requests.
  /// - [sessionId]: The unique identifier for this session.
  /// - [updates]: The global stream of session notifications from the client.
  /// - [permissionRequests]: The global stream of permission requests.
  /// - [modes]: Available session modes, if provided by the agent.
  ACPSessionWrapper({
    required ClientSideConnection connection,
    required this.sessionId,
    required Stream<SessionNotification> updates,
    required Stream<PendingPermission> permissionRequests,
    this.modes,
  }) : _connection = connection {
    // Filter updates for this session only
    _updateSubscription = updates.where((n) => n.sessionId == sessionId).listen((n) => _updateController.add(n.update));

    // Filter permissions for this session only
    _permissionSubscription = permissionRequests.where((p) => p.request.sessionId == sessionId).listen((p) => _permissionController.add(p));
  }

  final ClientSideConnection _connection;

  /// The unique identifier for this session.
  ///
  /// This ID is used to route messages and filter streams for this session.
  final String sessionId;

  /// Available session modes and current mode state for this session.
  ///
  /// Modes affect the agent's behavior, tool availability, and permission
  /// settings. Common modes include "code", "architect", and "ask".
  ///
  /// The [SessionModeState] contains:
  /// - [SessionModeState.availableModes]: List of available modes
  /// - [SessionModeState.currentModeId]: The currently active mode ID
  ///
  /// This may be `null` if the agent doesn't support modes or didn't
  /// provide mode information during session creation.
  final SessionModeState? modes;

  StreamSubscription<SessionNotification>? _updateSubscription;
  StreamSubscription<PendingPermission>? _permissionSubscription;

  final _updateController = StreamController<SessionUpdate>.broadcast();
  final _permissionController = StreamController<PendingPermission>.broadcast();

  /// Stream of session updates (agent messages, tool calls, etc.)
  ///
  /// This stream includes all update types defined in the ACP protocol:
  /// - [AgentMessageChunkSessionUpdate]: Text output from the agent
  /// - [AgentThoughtChunkSessionUpdate]: Agent's internal reasoning
  /// - [ToolCallSessionUpdate]: New tool call initiated
  /// - [ToolCallUpdateSessionUpdate]: Tool call status change
  /// - [PlanSessionUpdate]: Agent's task plan/todo list
  /// - [CurrentModeUpdateSessionUpdate]: Mode changed
  /// - [UserMessageChunkSessionUpdate]: User message (for history replay)
  /// - [AvailableCommandsUpdateSessionUpdate]: Available slash commands
  ///
  /// Subscribe to this stream to receive real-time updates during prompts.
  Stream<SessionUpdate> get updates => _updateController.stream;

  /// Stream of pending permission requests for this session.
  ///
  /// When the agent needs authorization for a tool operation, a
  /// [PendingPermission] is added to this stream. The UI should display
  /// the request and call [PendingPermission.allow] or
  /// [PendingPermission.cancel] to resolve it.
  ///
  /// The agent will wait for the response before proceeding with the
  /// tool operation.
  Stream<PendingPermission> get permissionRequests => _permissionController.stream;

  /// Sends a prompt to the agent.
  ///
  /// The [content] list contains the message content blocks to send.
  /// Typically this includes a [TextContentBlock] with the user's message,
  /// but may also include images, resources, or other content types.
  ///
  /// Returns a [PromptResponse] when the agent completes processing.
  /// The response includes:
  /// - [PromptResponse.stopReason]: Why the turn ended (end_turn, cancelled, etc.)
  /// - [PromptResponse.usage]: Token usage statistics
  ///
  /// While processing, updates are streamed via [updates].
  ///
  /// Example:
  /// ```dart
  /// final response = await session.prompt([
  ///   TextContentBlock(text: 'Write a hello world function in Dart'),
  /// ]);
  /// print('Completed with: ${response.stopReason}');
  /// ```
  Future<PromptResponse> prompt(List<ContentBlock> content) async {
    return _connection.prompt(PromptRequest(
      sessionId: sessionId,
      prompt: content,
    ));
  }

  /// Cancels the current prompt turn.
  ///
  /// This sends a cancellation notification to the agent, requesting it to:
  /// - Stop all language model requests
  /// - Abort tool calls in progress
  /// - Send any pending session updates
  /// - Complete the prompt with [StopReason.cancelled]
  ///
  /// After calling cancel, continue listening to [updates] for any final
  /// notifications before the prompt completes.
  ///
  /// This is a notification, not a request, so there is no response.
  Future<void> cancel() async {
    await _connection.cancel(CancelNotification(sessionId: sessionId));
  }

  /// Sets the session mode.
  ///
  /// Modes affect the agent's behavior, available tools, and permission
  /// settings. The [modeId] must be one of the modes from [modes].
  ///
  /// This can be called at any time during a session, whether the agent
  /// is idle or actively processing a prompt.
  ///
  /// Returns a [SetSessionModeResponse], or `null` if the operation fails.
  ///
  /// Example:
  /// ```dart
  /// // Switch to architect mode
  /// await session.setMode('architect');
  /// ```
  Future<SetSessionModeResponse?> setMode(String modeId) async {
    return _connection.setSessionMode(SetSessionModeRequest(
      sessionId: sessionId,
      modeId: modeId,
    ));
  }

  /// Disposes of this session wrapper and releases resources.
  ///
  /// This cancels stream subscriptions and closes the update and permission
  /// controllers. After disposal, the session should not be used.
  ///
  /// Note: This does not end the session on the agent side. The session
  /// may still be resumed later using [ACPClientWrapper.loadSession] if
  /// the agent supports session persistence.
  void dispose() {
    _updateSubscription?.cancel();
    _permissionSubscription?.cancel();
    _updateController.close();
    _permissionController.close();
  }
}
