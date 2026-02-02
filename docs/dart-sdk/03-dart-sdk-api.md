# Dart SDK API Design

This document defines the public API for the Dart SDK.

## Package Structure

```
claude_dart_sdk/
├── lib/
│   ├── claude_sdk.dart              # Public exports
│   └── src/
│       ├── backend.dart             # ClaudeBackend
│       ├── session.dart             # ClaudeSession
│       ├── single_request.dart      # ClaudeSingleRequest (one-shot CLI)
│       ├── protocol.dart            # JSON line I/O
│       └── types/
│           ├── sdk_messages.dart    # All SDK message types
│           ├── session_options.dart # Configuration options
│           ├── callbacks.dart       # Permission/hook requests
│           ├── content_blocks.dart  # Text, tool use, etc.
│           ├── tool_types.dart      # Tool input/output
│           └── usage.dart           # Usage, costs
├── pubspec.yaml
└── test/
```

## Public Exports

```dart
// claude_sdk.dart
library claude_sdk;

// Core classes
export 'src/backend.dart' show ClaudeBackend;
export 'src/session.dart' show ClaudeSession;

// Single request (one-shot CLI)
export 'src/single_request.dart';

// Types
export 'src/types/sdk_messages.dart';
export 'src/types/session_options.dart';
export 'src/types/callbacks.dart';
export 'src/types/content_blocks.dart';
export 'src/types/usage.dart';
```

---

## ClaudeBackend

Manages the backend process and session lifecycle. This is the legacy Node.js
backend implementation. For new code, prefer using `BackendFactory` with
`BackendType.directCli` (the default) which communicates directly with the
Claude CLI.

```dart
/// Manages the Node.js backend process (legacy implementation).
/// See BackendFactory for the recommended direct CLI approach.
class ClaudeBackend {
  /// Spawn a new backend process.
  ///
  /// [backendPath] is the path to the backend executable or script.
  /// If not provided, attempts to find it relative to the application.
  static Future<ClaudeBackend> spawn({String? backendPath});

  /// Whether the backend process is running.
  bool get isRunning;

  /// Stream of errors from the backend process.
  Stream<BackendError> get errors;

  /// Create a new Claude session.
  ///
  /// Returns a [ClaudeSession] that can be used to interact with Claude.
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
  });

  /// List all active sessions.
  List<ClaudeSession> get sessions;

  /// Dispose of the backend and all sessions.
  ///
  /// This kills the backend process and cleans up resources.
  Future<void> dispose();
}
```

### Usage Example

```dart
// Spawn the backend
final backend = await ClaudeBackend.spawn();

// Create a session
final session = await backend.createSession(
  prompt: 'Help me refactor this code',
  cwd: '/path/to/project',
  options: SessionOptions(
    model: 'sonnet',
    permissionMode: PermissionMode.acceptEdits,
  ),
);

// Use the session...

// Clean up
await backend.dispose();
```

---

## ClaudeSession

Represents an active Claude session.

```dart
/// An active Claude session.
class ClaudeSession {
  /// Unique session identifier.
  String get sessionId;

  /// SDK's internal session ID (used for resume).
  String? get sdkSessionId;

  /// Whether the session is currently processing.
  bool get isRunning;

  /// Session configuration.
  SessionOptions get options;

  // ═══════════════════════════════════════════════════════════════════════════
  // Message Streams
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stream of all SDK messages.
  ///
  /// This is the primary way to receive output from Claude.
  /// Messages are forwarded verbatim from the SDK.
  Stream<SDKMessage> get messages;

  /// Stream of assistant messages only.
  Stream<SDKAssistantMessage> get assistantMessages;

  /// Stream of result messages (turn completion).
  Stream<SDKResultMessage> get resultMessages;

  /// Stream of partial messages (when streaming enabled).
  ///
  /// Only emits if [SessionOptions.includePartialMessages] is true.
  Stream<SDKStreamEvent> get streamEvents;

  // ═══════════════════════════════════════════════════════════════════════════
  // Callback Streams
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stream of permission requests.
  ///
  /// Each [PermissionRequest] must be responded to by calling
  /// [PermissionRequest.allow] or [PermissionRequest.deny].
  Stream<PermissionRequest> get permissionRequests;

  /// Stream of hook callbacks.
  ///
  /// Each [HookRequest] must be responded to by calling
  /// [HookRequest.respond].
  Stream<HookRequest> get hookRequests;

  // ═══════════════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send a follow-up message.
  ///
  /// This resumes the session with a new user message.
  Future<void> send(String message);

  /// Interrupt the current execution.
  ///
  /// Claude will stop processing and the turn will end.
  Future<void> interrupt();

  /// Terminate the session.
  ///
  /// The session cannot be used after this.
  Future<void> kill();

  // ═══════════════════════════════════════════════════════════════════════════
  // Query Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get available models.
  Future<List<ModelInfo>> supportedModels();

  /// Get available slash commands.
  Future<List<SlashCommand>> supportedCommands();

  /// Get MCP server status.
  Future<List<McpServerStatus>> mcpServerStatus();

  /// Get account information.
  Future<AccountInfo> accountInfo();

  /// Change the model.
  Future<void> setModel(String model);

  /// Change the permission mode.
  Future<void> setPermissionMode(PermissionMode mode);

  /// Change max thinking tokens.
  Future<void> setMaxThinkingTokens(int? tokens);

  /// Rewind files to a previous state.
  ///
  /// Requires [SessionOptions.enableFileCheckpointing] to be true.
  Future<void> rewindFiles(String userMessageUuid);
}
```

### Usage Example

```dart
final session = await backend.createSession(
  prompt: 'Create a hello world program',
  cwd: '/path/to/project',
);

// Listen to messages
session.messages.listen((message) {
  switch (message) {
    case SDKAssistantMessage m:
      for (final block in m.message.content) {
        if (block is TextBlock) {
          print('Claude: ${block.text}');
        } else if (block is ToolUseBlock) {
          print('Using tool: ${block.name}');
        }
      }
    case SDKResultMessage m:
      print('Turn complete. Cost: \$${m.totalCostUsd}');
    case SDKSystemMessage m when m.subtype == 'init':
      print('Session initialized with model: ${m.model}');
  }
});

// Handle permission requests
session.permissionRequests.listen((request) async {
  print('Permission needed for ${request.toolName}');

  // Show UI, get user decision
  final approved = await showPermissionDialog(request);

  if (approved) {
    request.allow();
  } else {
    request.deny('User declined');
  }
});

// Wait for completion
await session.resultMessages.first;

// Send follow-up
await session.send('Now add error handling');
```

---

## ClaudeSingleRequest

Makes one-shot requests to Claude via the CLI. This is useful for quick utility tasks
like generating commit messages or summarizing content, where you don't need an
interactive session.

```dart
/// Makes single one-shot requests to Claude via the CLI.
class ClaudeSingleRequest {
  /// Creates a ClaudeSingleRequest instance.
  ///
  /// [claudePath] is the path to the claude CLI executable.
  /// If not provided, defaults to 'claude' (assuming it's in PATH).
  ///
  /// [onLog] is an optional callback for logging messages.
  ClaudeSingleRequest({
    String? claudePath,
    void Function(String message, {bool isError})? onLog,
  });

  /// Makes a single request to Claude and returns the result.
  ///
  /// Returns [SingleRequestResult] or null if the process failed to start.
  Future<SingleRequestResult?> request({
    required String prompt,
    required String workingDirectory,
    SingleRequestOptions options = const SingleRequestOptions(),
  });
}

/// Result from a single Claude CLI request.
class SingleRequestResult {
  /// The text result from Claude.
  final String result;

  /// Whether the request resulted in an error.
  final bool isError;

  /// Total duration in milliseconds.
  final int durationMs;

  /// API duration in milliseconds.
  final int durationApiMs;

  /// Number of conversation turns.
  final int numTurns;

  /// Total cost in USD.
  final double totalCostUsd;

  /// Token usage statistics.
  final Usage usage;

  /// Per-model usage breakdown.
  final Map<String, ModelUsage>? modelUsage;

  /// The session ID (for reference).
  final String? sessionId;

  /// Error messages if [isError] is true.
  final List<String>? errors;
}

/// Options for a single Claude CLI request.
class SingleRequestOptions {
  const SingleRequestOptions({
    this.model = 'haiku',
    this.allowedTools,
    this.disallowedTools,
    this.permissionMode,
    this.maxTurns,
    this.systemPrompt,
    this.timeoutSeconds = 60,
  });

  /// The model to use (default: 'haiku').
  final String model;

  /// List of allowed tools (e.g., ['Bash(git:*)', 'Read']).
  final List<String>? allowedTools;

  /// List of disallowed tools.
  final List<String>? disallowedTools;

  /// Permission mode ('default', 'acceptEdits', 'bypassPermissions', 'plan').
  final String? permissionMode;

  /// Maximum number of turns.
  final int? maxTurns;

  /// Custom system prompt.
  final String? systemPrompt;

  /// Timeout in seconds (default: 60).
  final int timeoutSeconds;
}
```

### Usage Example

```dart
import 'package:claude_sdk/claude_sdk.dart';

// Create the client
final claude = ClaudeSingleRequest(
  onLog: (message, {isError = false}) {
    print('${isError ? "ERROR: " : ""}$message');
  },
);

// Make a request
final result = await claude.request(
  prompt: 'Provide a good commit message for the uncommitted files',
  workingDirectory: '/path/to/repo',
  options: SingleRequestOptions(
    model: 'haiku',
    allowedTools: ['Bash(git:*)', 'Bash(gh:*)', 'Read'],
  ),
);

if (result != null && !result.isError) {
  print('Commit message: ${result.result}');
  print('Cost: \$${result.totalCostUsd.toStringAsFixed(6)}');
  print('Tokens: ${result.usage.inputTokens} in / ${result.usage.outputTokens} out');
}
```

### How It Works

`ClaudeSingleRequest` runs the Claude CLI in one-shot mode:

```bash
claude --model haiku \
       --output-format json \
       --allowedTools "Bash(git:*) Bash(gh:*) Read" \
       --print "your prompt here"
```

The JSON output is parsed into a `SingleRequestResult` containing:
- The text result
- Usage statistics (tokens, cost)
- Duration information
- Error details (if any)

### Use Cases

- **Commit message generation**: Ask Claude to suggest a commit message based on staged changes
- **Chat summarization**: Generate a brief title for a chat after the first message
- **Code review snippets**: Quick analysis of a code snippet
- **Documentation generation**: Generate docstrings or comments

---

## SessionOptions

Configuration options for creating a session.

```dart
/// Options for creating a Claude session.
class SessionOptions {
  const SessionOptions({
    this.model,
    this.permissionMode,
    this.allowedTools,
    this.disallowedTools,
    this.systemPrompt,
    this.maxTurns,
    this.maxBudgetUsd,
    this.maxThinkingTokens,
    this.includePartialMessages,
    this.enableFileCheckpointing,
    this.additionalDirectories,
    this.mcpServers,
    this.agents,
    this.hooks,
    this.sandbox,
    this.settingSources,
    this.betas,
    this.outputFormat,
    this.fallbackModel,
  });

  /// Model to use (e.g., 'sonnet', 'opus', 'haiku').
  final String? model;

  /// Permission mode for tool execution.
  final PermissionMode? permissionMode;

  /// List of allowed tool names.
  final List<String>? allowedTools;

  /// List of disallowed tool names.
  final List<String>? disallowedTools;

  /// System prompt configuration.
  final SystemPrompt? systemPrompt;

  /// Maximum conversation turns.
  final int? maxTurns;

  /// Maximum budget in USD.
  final double? maxBudgetUsd;

  /// Maximum tokens for thinking.
  final int? maxThinkingTokens;

  /// Enable partial message streaming.
  final bool? includePartialMessages;

  /// Enable file checkpointing for rewind.
  final bool? enableFileCheckpointing;

  /// Additional directories Claude can access.
  final List<String>? additionalDirectories;

  /// MCP server configurations.
  final Map<String, McpServerConfig>? mcpServers;

  /// Programmatic agent definitions.
  final Map<String, AgentDefinition>? agents;

  /// Hook configurations.
  final Map<HookEvent, List<HookConfig>>? hooks;

  /// Sandbox settings.
  final SandboxSettings? sandbox;

  /// Settings sources to load.
  final List<SettingSource>? settingSources;

  /// Beta features to enable.
  final List<String>? betas;

  /// Structured output format.
  final OutputFormat? outputFormat;

  /// Fallback model if primary fails.
  final String? fallbackModel;
}
```

### Supporting Types

```dart
/// Permission mode for tool execution.
enum PermissionMode {
  /// Standard permission behavior.
  default_,

  /// Auto-accept file edits in project directory.
  acceptEdits,

  /// Bypass all permission checks (dangerous).
  bypassPermissions,

  /// Planning mode - no execution.
  plan,
}

/// System prompt configuration.
sealed class SystemPrompt {
  const SystemPrompt();
}

class CustomSystemPrompt extends SystemPrompt {
  const CustomSystemPrompt(this.prompt);
  final String prompt;
}

class PresetSystemPrompt extends SystemPrompt {
  const PresetSystemPrompt({this.append});
  final String? append;
}

/// Settings source.
enum SettingSource { user, project, local }

/// Hook event types.
enum HookEvent {
  preToolUse,
  postToolUse,
  postToolUseFailure,
  notification,
  userPromptSubmit,
  sessionStart,
  sessionEnd,
  stop,
  subagentStart,
  subagentStop,
  preCompact,
  permissionRequest,
}
```

---

## Callback Types

### PermissionRequest

```dart
/// A permission request from canUseTool.
class PermissionRequest {
  /// Unique request ID.
  String get id;

  /// Session this request belongs to.
  String get sessionId;

  /// Tool requesting permission.
  String get toolName;

  /// Tool input parameters.
  Map<String, dynamic> get toolInput;

  /// Permission suggestions from the SDK.
  List<PermissionUpdate>? get suggestions;

  /// Allow the tool to execute.
  ///
  /// [updatedInput] optionally modifies the tool input.
  /// [updatedPermissions] optionally adds permission rules.
  void allow({
    Map<String, dynamic>? updatedInput,
    List<PermissionUpdate>? updatedPermissions,
  });

  /// Deny the tool execution.
  ///
  /// [message] explains why the tool was denied.
  /// [interrupt] if true, stops the current execution.
  void deny(String message, {bool interrupt = false});
}
```

### HookRequest

```dart
/// A hook callback request.
class HookRequest {
  /// Unique request ID.
  String get id;

  /// Session this request belongs to.
  String get sessionId;

  /// Hook event type.
  HookEvent get event;

  /// Hook-specific input data.
  Map<String, dynamic> get input;

  /// Tool use ID (for tool-related hooks).
  String? get toolUseId;

  /// Respond to the hook.
  void respond(HookResponse response);
}

/// Response to a hook callback.
class HookResponse {
  const HookResponse({
    this.continue_ = true,
    this.decision,
    this.systemMessage,
    this.reason,
    this.hookSpecificOutput,
  });

  /// Whether to continue execution.
  final bool continue_;

  /// Block or approve decision.
  final HookDecision? decision;

  /// System message to add to transcript.
  final String? systemMessage;

  /// Feedback for Claude.
  final String? reason;

  /// Hook-specific output data.
  final Map<String, dynamic>? hookSpecificOutput;
}

enum HookDecision { approve, block }
```

---

## Result Types

```dart
/// Information about an available model.
class ModelInfo {
  final String value;
  final String displayName;
  final String description;
}

/// Information about a slash command.
class SlashCommand {
  final String name;
  final String description;
  final String argumentHint;
}

/// MCP server status.
class McpServerStatus {
  final String name;
  final McpStatus status;
  final McpServerInfo? serverInfo;
}

enum McpStatus { connected, failed, needsAuth, pending }

/// Account information.
class AccountInfo {
  final String? email;
  final String? organization;
  final String? subscriptionType;
  final String? tokenSource;
  final String? apiKeySource;
}

/// Token usage information.
class Usage {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
}

/// Per-model usage breakdown.
class ModelUsage {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
  final int webSearchRequests;
  final double costUsd;
  final int contextWindow;
}
```

---

## Error Handling

```dart
/// Base class for SDK errors.
sealed class ClaudeSdkError implements Exception {
  String get message;
}

/// Backend process error.
class BackendError extends ClaudeSdkError {
  final String code;
  final String message;
  final Map<String, dynamic>? details;
}

/// Session not found error.
class SessionNotFoundError extends ClaudeSdkError {
  final String sessionId;
  String get message => 'Session not found: $sessionId';
}

/// Callback timeout error.
class CallbackTimeoutError extends ClaudeSdkError {
  final String callbackId;
  final Duration timeout;
  String get message => 'Callback $callbackId timed out after $timeout';
}

/// Backend process died unexpectedly.
class BackendDiedError extends ClaudeSdkError {
  final int? exitCode;
  String get message => 'Backend process died with exit code: $exitCode';
}
```

---

## Complete Example

```dart
import 'package:claude_sdk/claude_sdk.dart';

Future<void> main() async {
  // Start backend
  final backend = await ClaudeBackend.spawn();

  try {
    // Create session
    final session = await backend.createSession(
      prompt: 'Create a simple web server in Python',
      cwd: '/home/user/project',
      options: SessionOptions(
        model: 'sonnet',
        permissionMode: PermissionMode.default_,
        includePartialMessages: true,
      ),
    );

    // Handle messages
    session.messages.listen((message) {
      switch (message) {
        case SDKSystemMessage m when m.subtype == 'init':
          print('Model: ${m.model}');
          print('Tools: ${m.tools.join(', ')}');

        case SDKAssistantMessage m:
          for (final block in m.message.content) {
            if (block is TextBlock) {
              print(block.text);
            } else if (block is ToolUseBlock) {
              print('→ ${block.name}');
            }
          }

        case SDKStreamEvent m:
          // Handle streaming deltas
          final event = m.event;
          if (event['type'] == 'content_block_delta') {
            stdout.write(event['delta']?['text'] ?? '');
          }

        case SDKResultMessage m:
          print('\n---');
          print('Turns: ${m.numTurns}');
          print('Cost: \$${m.totalCostUsd?.toStringAsFixed(4)}');
      }
    });

    // Handle permissions
    session.permissionRequests.listen((request) {
      print('Allow ${request.toolName}? (auto-approving)');
      request.allow();
    });

    // Wait for first turn to complete
    final result = await session.resultMessages.first;

    if (result.subtype == 'success') {
      // Send follow-up
      await session.send('Add error handling and logging');
      await session.resultMessages.first;
    }

    // Get session info
    final models = await session.supportedModels();
    print('Available models: ${models.map((m) => m.value).join(', ')}');

  } finally {
    await backend.dispose();
  }
}
```
