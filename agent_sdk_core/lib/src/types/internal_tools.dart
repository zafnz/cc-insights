import 'dart:async';

/// A tool provided by CC-Insights to agent backends.
///
/// Internal tools allow CC-Insights to expose application-level functionality
/// (like ticket management, worktree operations) directly to agents running
/// within the application. The backend injects these tools into the agent's
/// tool catalog, and the handler is invoked when the agent uses the tool.
class InternalToolDefinition {
  InternalToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });

  /// The unique name of the tool (e.g., "create_ticket").
  final String name;

  /// Human-readable description for the model's context.
  final String description;

  /// JSON Schema describing the tool's input parameters.
  ///
  /// This schema is passed to the LLM and validated by the backend.
  final Map<String, dynamic> inputSchema;

  /// Handler function invoked when the agent uses this tool.
  ///
  /// The input map contains the validated tool parameters.
  /// Returns a Future that completes with the tool's result.
  final Future<InternalToolResult> Function(Map<String, dynamic> input)
      handler;
}

/// Result of an internal tool invocation.
///
/// Contains the result content (either success data or error message)
/// and a flag indicating whether the result represents an error.
class InternalToolResult {
  const InternalToolResult._({required this.content, required this.isError});

  /// The result content (success data or error message).
  final String content;

  /// Whether this result represents an error.
  final bool isError;

  /// Create a successful tool result.
  factory InternalToolResult.text(String text) =>
      InternalToolResult._(content: text, isError: false);

  /// Create an error tool result.
  factory InternalToolResult.error(String message) =>
      InternalToolResult._(content: message, isError: true);
}
