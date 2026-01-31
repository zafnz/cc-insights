import 'dart:async';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';

import 'handlers/terminal_handler.dart';
import 'pending_permission.dart';

/// Implements the acp_dart [Client] interface for CC-Insights.
///
/// This class bridges the callback-based ACP protocol to stream-based APIs
/// that integrate well with Flutter's reactive state management patterns.
/// It handles all agent-to-client requests including:
///
/// - **Session updates**: Forwarded to a stream for UI consumption
/// - **Permission requests**: Creates [PendingPermission] objects that the UI
///   can resolve when the user makes a decision
/// - **File system operations**: Reads and writes files on the local filesystem
/// - **Terminal operations**: Delegates to [TerminalHandler] for command execution
///
/// Example usage:
/// ```dart
/// final updateController = StreamController<SessionNotification>.broadcast();
/// final permissionController = StreamController<PendingPermission>.broadcast();
/// final terminalHandler = TerminalHandler();
///
/// final client = CCInsightsACPClient(
///   updateController: updateController,
///   permissionController: permissionController,
///   terminalHandler: terminalHandler,
/// );
///
/// // Use with ClientSideConnection
/// final connection = ClientSideConnection((_) => client, stream);
/// ```
class CCInsightsACPClient implements Client {
  /// Creates a new CC-Insights ACP client.
  ///
  /// The [updateController] receives session update notifications from the agent.
  /// The [permissionController] receives permission requests that the UI must resolve.
  /// The [terminalHandler] manages terminal sessions for command execution.
  CCInsightsACPClient({
    required this.updateController,
    required this.permissionController,
    required this.terminalHandler,
  });

  /// Stream controller for session update notifications.
  ///
  /// Session updates include agent messages, tool calls, plans, and mode changes.
  /// The UI listens to this stream to display real-time progress.
  final StreamController<SessionNotification> updateController;

  /// Stream controller for pending permission requests.
  ///
  /// When the agent requests permission for a tool operation, a [PendingPermission]
  /// is added to this stream. The UI should display the request and call
  /// [PendingPermission.allow] or [PendingPermission.cancel] to resolve it.
  final StreamController<PendingPermission> permissionController;

  /// Handler for terminal operations.
  ///
  /// Manages the lifecycle of terminal sessions including creation, output
  /// retrieval, and cleanup.
  final TerminalHandler terminalHandler;

  /// Handles session update notifications from the agent.
  ///
  /// This is called for each streaming update, including message chunks,
  /// tool calls, execution plans, and mode changes. The update is forwarded
  /// to [updateController] for UI consumption.
  @override
  Future<void> sessionUpdate(SessionNotification params) async {
    updateController.add(params);
  }

  /// Handles permission requests from the agent.
  ///
  /// When the agent needs authorization for a tool operation (such as writing
  /// a file or executing a command), this method is called. It creates a
  /// [PendingPermission] with a [Completer] and adds it to the permission
  /// stream. The method returns a [Future] that completes when the UI
  /// resolves the permission via [PendingPermission.allow] or
  /// [PendingPermission.cancel].
  ///
  /// If the client cancels the prompt turn via `session/cancel`, it should
  /// call [PendingPermission.cancel] to respond with [CancelledOutcome].
  @override
  Future<RequestPermissionResponse> requestPermission(
    RequestPermissionRequest params,
  ) async {
    final completer = Completer<RequestPermissionResponse>();

    permissionController.add(PendingPermission(
      request: params,
      completer: completer,
    ));

    return completer.future;
  }

  /// Reads content from a text file.
  ///
  /// Called when the agent needs to access file contents within the client's
  /// environment. Only available if the client advertises the `fs.readTextFile`
  /// capability during initialization.
  ///
  /// Throws [RequestError.resourceNotFound] if the file does not exist.
  /// Throws [RequestError.internalError] for other file read errors.
  @override
  Future<ReadTextFileResponse> readTextFile(ReadTextFileRequest params) async {
    try {
      final file = File(params.path);

      if (!await file.exists()) {
        throw RequestError.resourceNotFound(params.path);
      }

      final content = await file.readAsString();
      return ReadTextFileResponse(content: content);
    } on RequestError {
      rethrow;
    } catch (e) {
      throw RequestError.internalError('Failed to read file: $e');
    }
  }

  /// Writes content to a text file.
  ///
  /// Called when the agent needs to create or modify files within the client's
  /// environment. Only available if the client advertises the `fs.writeTextFile`
  /// capability during initialization.
  ///
  /// Creates parent directories if they don't exist.
  /// Throws [RequestError.internalError] for file write errors.
  @override
  Future<WriteTextFileResponse> writeTextFile(
    WriteTextFileRequest params,
  ) async {
    try {
      final file = File(params.path);

      // Create parent directories if they don't exist
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      await file.writeAsString(params.content);
      return WriteTextFileResponse();
    } catch (e) {
      throw RequestError.internalError('Failed to write file: $e');
    }
  }

  /// Creates a new terminal session and executes a command.
  ///
  /// The command is executed using the shell, supporting features like
  /// pipes, redirects, and environment variable expansion.
  ///
  /// The agent must call [releaseTerminal] when done with the terminal
  /// to free resources.
  @override
  Future<CreateTerminalResponse> createTerminal(
    CreateTerminalRequest params,
  ) async {
    try {
      return await terminalHandler.create(params);
    } on TerminalNotFoundError catch (e) {
      throw RequestError.resourceNotFound(e.terminalId);
    } catch (e) {
      throw RequestError.internalError('Failed to create terminal: $e');
    }
  }

  /// Gets the current output from a terminal session.
  ///
  /// Returns immediately without waiting for the command to complete.
  /// If the command has already exited, the exit status is included.
  @override
  Future<TerminalOutputResponse> terminalOutput(
    TerminalOutputRequest params,
  ) async {
    try {
      return await terminalHandler.output(params);
    } on TerminalNotFoundError catch (e) {
      throw RequestError.resourceNotFound(e.terminalId);
    } catch (e) {
      throw RequestError.internalError('Failed to get terminal output: $e');
    }
  }

  /// Releases a terminal session and cleans up resources.
  ///
  /// The command is killed if it hasn't exited yet. After release,
  /// the terminal ID becomes invalid for all other terminal methods.
  ///
  /// Tool calls that already contain the terminal ID continue to
  /// display its output.
  @override
  Future<ReleaseTerminalResponse?> releaseTerminal(
    ReleaseTerminalRequest params,
  ) async {
    try {
      return await terminalHandler.release(params);
    } on TerminalNotFoundError catch (e) {
      throw RequestError.resourceNotFound(e.terminalId);
    } catch (e) {
      throw RequestError.internalError('Failed to release terminal: $e');
    }
  }

  /// Waits for a terminal command to exit.
  ///
  /// This method blocks until the command completes, then returns the
  /// exit code and/or signal that terminated the process.
  @override
  Future<WaitForTerminalExitResponse> waitForTerminalExit(
    WaitForTerminalExitRequest params,
  ) async {
    try {
      return await terminalHandler.waitForExit(params);
    } on TerminalNotFoundError catch (e) {
      throw RequestError.resourceNotFound(e.terminalId);
    } catch (e) {
      throw RequestError.internalError('Failed to wait for terminal exit: $e');
    }
  }

  /// Kills a terminal command without releasing the terminal.
  ///
  /// While [releaseTerminal] also kills the command, this method keeps
  /// the terminal ID valid so it can be used with other methods.
  ///
  /// Useful for implementing command timeouts that terminate the command
  /// and then retrieve the final output.
  ///
  /// Note: Call [releaseTerminal] when the terminal is no longer needed.
  @override
  Future<KillTerminalCommandResponse?> killTerminal(
    KillTerminalCommandRequest params,
  ) async {
    try {
      return await terminalHandler.kill(params);
    } on TerminalNotFoundError catch (e) {
      throw RequestError.resourceNotFound(e.terminalId);
    } catch (e) {
      throw RequestError.internalError('Failed to kill terminal: $e');
    }
  }

  /// Handles extension method requests from the agent.
  ///
  /// Extension methods allow the agent to send arbitrary requests that are
  /// not part of the standard ACP specification. CC-Insights does not
  /// currently support any extension methods.
  ///
  /// Returns `null` to indicate the method is not implemented, which will
  /// cause a "method not found" error to be sent back to the agent.
  @override
  Future<Map<String, dynamic>>? extMethod(
    String method,
    Map<String, dynamic> params,
  ) {
    // CC-Insights does not currently support any extension methods
    // Returning null indicates the method is not implemented
    return null;
  }

  /// Handles extension notification from the agent.
  ///
  /// Extension notifications allow the agent to send arbitrary notifications
  /// that are not part of the standard ACP specification. CC-Insights
  /// currently ignores extension notifications.
  @override
  Future<void>? extNotification(
    String method,
    Map<String, dynamic> params,
  ) {
    // CC-Insights currently ignores extension notifications
    // Could add logging here if needed for debugging
    return null;
  }
}
