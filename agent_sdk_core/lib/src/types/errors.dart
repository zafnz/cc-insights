/// Base class for Claude SDK errors.
class ClaudeError implements Exception {
  const ClaudeError(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final dynamic details;

  @override
  String toString() => code != null ? '[$code] $message' : message;
}

/// Error from the backend process.
class BackendError extends ClaudeError {
  const BackendError(super.message, {super.code, super.details});

  factory BackendError.fromJson(Map<String, dynamic> json) {
    return BackendError(
      json['message'] as String? ?? 'Unknown error',
      code: json['code'] as String?,
      details: json['details'],
    );
  }
}

/// Error during session creation.
class SessionCreateError extends ClaudeError {
  const SessionCreateError(super.message, {super.code, super.details});
}

/// Session not found error.
class SessionNotFoundError extends ClaudeError {
  const SessionNotFoundError(String sessionId)
      : super('Session not found: $sessionId', code: 'SESSION_NOT_FOUND');
}

/// Backend process error.
class BackendProcessError extends ClaudeError {
  const BackendProcessError(super.message, {this.exitCode})
      : super(code: 'BACKEND_PROCESS_ERROR');

  final int? exitCode;
}

/// Communication error with backend.
class CommunicationError extends ClaudeError {
  const CommunicationError(super.message) : super(code: 'COMMUNICATION_ERROR');
}

/// Query method error.
class QueryError extends ClaudeError {
  const QueryError(super.message, {super.code});
}
