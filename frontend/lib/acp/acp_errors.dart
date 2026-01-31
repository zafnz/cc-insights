/// Error types for ACP (Agent Client Protocol) operations.
///
/// This file defines custom exception types for various error conditions
/// that can occur during ACP communication, including connection failures,
/// protocol errors, and timeouts.

/// Base class for all ACP-related errors.
///
/// This provides a common type for catching any ACP error while also
/// allowing specific error types to be caught individually.
sealed class ACPError implements Exception {
  /// Creates an ACP error with the given [message].
  const ACPError(this.message);

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Error thrown when the agent process fails to start or crashes.
///
/// This error occurs when:
/// - The agent command is not found or cannot be executed
/// - The agent process exits unexpectedly during operation
/// - The agent process crashes with a non-zero exit code
///
/// The [exitCode] is available when the process has exited.
class ACPConnectionError extends ACPError {
  /// Creates a connection error with the given [message].
  ///
  /// Optionally includes the [exitCode] if the process exited,
  /// and the [command] that was attempted.
  const ACPConnectionError(
    super.message, {
    this.exitCode,
    this.command,
  });

  /// Creates a connection error for when the agent command is not found.
  factory ACPConnectionError.commandNotFound(String command) {
    return ACPConnectionError(
      'Agent command not found: $command',
      command: command,
    );
  }

  /// Creates a connection error for when the agent process crashes.
  factory ACPConnectionError.processCrashed(int exitCode, {String? command}) {
    return ACPConnectionError(
      'Agent process crashed with exit code $exitCode',
      exitCode: exitCode,
      command: command,
    );
  }

  /// Creates a connection error for when the agent fails to start.
  factory ACPConnectionError.failedToStart(String reason, {String? command}) {
    return ACPConnectionError(
      'Failed to start agent: $reason',
      command: command,
    );
  }

  /// The exit code of the agent process, if it has exited.
  final int? exitCode;

  /// The command that was attempted, if known.
  final String? command;

  /// Whether the error is due to the command not being found.
  bool get isCommandNotFound => message.contains('not found');

  /// Whether the error is due to a process crash.
  bool get isProcessCrash => exitCode != null;
}

/// Error thrown when there is a protocol-level error in ACP communication.
///
/// This error occurs when:
/// - The agent sends a malformed message
/// - The message cannot be parsed as valid JSON
/// - Required fields are missing from a message
/// - The message type is unknown or unexpected
///
/// Protocol errors are logged but typically don't crash the application.
/// Instead, the malformed message is skipped and processing continues.
class ACPProtocolError extends ACPError {
  /// Creates a protocol error with the given [message].
  ///
  /// Optionally includes the [rawMessage] that caused the error
  /// and the underlying [cause] if available.
  const ACPProtocolError(
    super.message, {
    this.rawMessage,
    this.cause,
  });

  /// Creates a protocol error for JSON parsing failure.
  factory ACPProtocolError.invalidJson(String rawMessage, Object cause) {
    return ACPProtocolError(
      'Invalid JSON in message',
      rawMessage: rawMessage,
      cause: cause,
    );
  }

  /// Creates a protocol error for missing required fields.
  factory ACPProtocolError.missingField(String fieldName, {String? rawMessage}) {
    return ACPProtocolError(
      'Missing required field: $fieldName',
      rawMessage: rawMessage,
    );
  }

  /// Creates a protocol error for unknown message types.
  factory ACPProtocolError.unknownMessageType(String type) {
    return ACPProtocolError(
      'Unknown message type: $type',
    );
  }

  /// The raw message that caused the error, if available.
  ///
  /// This is useful for debugging protocol issues.
  final String? rawMessage;

  /// The underlying cause of the error, if available.
  ///
  /// This is typically a JSON parsing exception or similar.
  final Object? cause;
}

/// Error thrown when an ACP operation times out.
///
/// This error occurs when:
/// - Connection initialization takes too long
/// - A request doesn't receive a response within the timeout period
/// - The agent becomes unresponsive
class ACPTimeoutError extends ACPError {
  /// Creates a timeout error with the given [message].
  ///
  /// The [timeout] duration that was exceeded and the [operation]
  /// that timed out can be provided for context.
  const ACPTimeoutError(
    super.message, {
    this.timeout,
    this.operation,
  });

  /// Creates a timeout error for connection initialization.
  factory ACPTimeoutError.connectionTimeout(Duration timeout) {
    return ACPTimeoutError(
      'Connection timed out after ${timeout.inSeconds} seconds',
      timeout: timeout,
      operation: 'connect',
    );
  }

  /// Creates a timeout error for a specific operation.
  factory ACPTimeoutError.operationTimeout(
    String operation,
    Duration timeout,
  ) {
    return ACPTimeoutError(
      '$operation timed out after ${timeout.inSeconds} seconds',
      timeout: timeout,
      operation: operation,
    );
  }

  /// The duration that was exceeded.
  final Duration? timeout;

  /// The operation that timed out.
  final String? operation;
}

/// Error thrown when an operation is attempted in an invalid state.
///
/// For example, trying to create a session when not connected.
class ACPStateError extends ACPError {
  /// Creates a state error with the given [message].
  ///
  /// The [currentState] and [requiredState] provide context about
  /// what state transition was attempted.
  const ACPStateError(
    super.message, {
    this.currentState,
    this.requiredState,
  });

  /// Creates a state error for operations requiring connection.
  factory ACPStateError.notConnected() {
    return const ACPStateError(
      'Not connected to agent. Call connect() first.',
      currentState: 'disconnected',
      requiredState: 'connected',
    );
  }

  /// Creates a state error for double connection attempts.
  factory ACPStateError.alreadyConnected() {
    return const ACPStateError(
      'Already connected. Call disconnect() first.',
      currentState: 'connected',
      requiredState: 'disconnected',
    );
  }

  /// The current state when the error occurred.
  final String? currentState;

  /// The state that was required for the operation.
  final String? requiredState;
}
