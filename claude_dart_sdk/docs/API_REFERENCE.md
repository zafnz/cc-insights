# API Reference

Complete API documentation for the Claude Dart SDK.

## Table of Contents

- [BackendFactory](#backendfactory)
- [AgentBackend Interface](#agentbackend-interface)
- [AgentSession Interface](#agentsession-interface)
- [Message Types](#message-types)
- [Content Blocks](#content-blocks)
- [Permission Handling](#permission-handling)
- [Hooks](#hooks)
- [Session Options](#session-options)
- [Usage & Cost Tracking](#usage--cost-tracking)
- [Logging](#logging)
- [Errors](#errors)
- [Single Request](#single-request)

---

## BackendFactory

Factory for creating backend instances.

### Methods

#### `create()`

Creates a new backend instance.

```dart
static Future<AgentBackend> create({
  String? executablePath,
})
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `executablePath` | `String?` | `'claude'` | Path to Claude CLI executable |

**Returns:** `Future<AgentBackend>` - The created backend instance

**Example:**

```dart
// Default
final backend = await BackendFactory.create();

// With custom path
final backend = await BackendFactory.create(
  executablePath: '/usr/local/bin/claude',
);
```

---

## AgentBackend Interface

Abstract interface for managing agent sessions.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isRunning` | `bool` | Whether the backend is operational |
| `errors` | `Stream<BackendError>` | Stream of backend errors |
| `logs` | `Stream<String>` | Stream of log messages |
| `sessions` | `List<AgentSession>` | List of active sessions |

### Methods

#### `createSession()`

Creates a new agent session.

```dart
Future<AgentSession> createSession({
  required String prompt,
  required String cwd,
  SessionOptions? options,
  List<ContentBlock>? content,
})
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `prompt` | `String` | Initial prompt/message for Claude |
| `cwd` | `String` | Working directory for the session |
| `options` | `SessionOptions?` | Session configuration options |
| `content` | `List<ContentBlock>?` | Multi-modal content blocks |

**Returns:** `Future<AgentSession>` - The created session

#### `dispose()`

Disposes the backend and all sessions.

```dart
Future<void> dispose()
```

---

## AgentSession Interface

Abstract interface for an active Claude session.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `sessionId` | `String` | Unique session identifier |
| `isActive` | `bool` | Whether the session is running |
| `messages` | `Stream<SDKMessage>` | Stream of session messages |
| `permissionRequests` | `Stream<PermissionRequest>` | Stream of permission requests |
| `hookRequests` | `Stream<HookRequest>` | Stream of hook requests |

### Methods

#### `send()`

Sends a text message to the session.

```dart
Future<void> send(String message)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `message` | `String` | Text message to send |

#### `sendWithContent()`

Sends multi-modal content to the session.

```dart
Future<void> sendWithContent(List<ContentBlock> content)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `content` | `List<ContentBlock>` | Content blocks (text, images, etc.) |

**Example:**

```dart
await session.sendWithContent([
  TextBlock(text: 'Describe this image:'),
  ImageBlock(
    source: ImageSource(
      type: 'base64',
      mediaType: 'image/png',
      data: base64Data,
    ),
  ),
]);
```

#### `interrupt()`

Interrupts the current operation.

```dart
Future<void> interrupt()
```

Sends an interrupt signal to gracefully stop the current operation. Claude will attempt to complete its current step.

#### `kill()`

Immediately terminates the session.

```dart
Future<void> kill()
```

#### `setModel()`

Changes the model mid-session.

```dart
Future<void> setModel(String? model)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | `String?` | Model name: `'sonnet'`, `'opus'`, `'haiku'`, `null` for default |

#### `setPermissionMode()`

Changes the permission mode mid-session.

```dart
Future<void> setPermissionMode(String? mode)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `mode` | `String?` | Permission mode name |

---

## Message Types

All messages extend the sealed `SDKMessage` class.

### SDKMessage (Base)

```dart
sealed class SDKMessage {
  String get uuid;
  String get sessionId;
}
```

### SDKSystemMessage

System initialization and status messages.

```dart
class SDKSystemMessage extends SDKMessage {
  String subtype;        // 'init', 'status', 'compact_boundary'
  String? cwd;           // Working directory
  List<String>? tools;   // Available tools
  List<McpServer>? mcpServers;  // MCP server status
  String? model;         // Current model
  String? permissionMode;       // Current permission mode
  List<String>? slashCommands;  // Available slash commands
  String? apiKeySource;         // API key source
  String? claudeCodeVersion;    // CLI version
  List<String>? agents;         // Available agents
}
```

### SDKAssistantMessage

Claude's response messages.

```dart
class SDKAssistantMessage extends SDKMessage {
  APIAssistantMessage message;  // The message content
  String? parentToolUseId;      // If this is a subagent message

  // Convenience getters
  String? get textContent;      // Concatenated text blocks
  List<ContentBlock> get content; // All content blocks
}
```

### SDKUserMessage

User messages and tool results.

```dart
class SDKUserMessage extends SDKMessage {
  APIUserMessage message;       // The message content
  String? parentToolUseId;      // Parent tool use (for subagents)
  ToolUseResult? toolUseResult; // Tool execution result
}
```

### SDKResultMessage

Turn completion with usage data.

```dart
class SDKResultMessage extends SDKMessage {
  String subtype;           // 'success' or 'error'
  bool isError;
  int durationMs;           // Total duration
  int durationApiMs;        // API call duration
  int numTurns;             // Conversation turns
  String? result;           // Final result text
  double? totalCostUsd;     // Total cost in USD
  Usage? usage;             // Token usage
  Map<String, ModelUsage>? modelUsage;  // Per-model usage
  List<dynamic>? permissionDenials;     // Denied permissions
}
```

### SDKStreamEvent

Streaming content deltas.

```dart
class SDKStreamEvent extends SDKMessage {
  String eventType;         // Event type (content_block_delta, etc.)
  Map<String, dynamic> event;  // Event data

  // Convenience getters
  String? get textDelta;    // Text delta if present
  String? get thinkingDelta; // Thinking delta if present
}
```

### SDKControlRequest

Control requests (e.g., permission requests).

```dart
class SDKControlRequest extends SDKMessage {
  String id;                // Request ID
  String callbackType;      // 'can_use_tool', etc.
  String? toolName;         // Tool requesting permission
  Map<String, dynamic>? toolInput;  // Tool input
  String? blockedPath;      // Path that triggered permission
  List<dynamic>? suggestions;       // Permission suggestions
  String? toolUseId;        // Tool use ID
}
```

### SDKControlResponse

Control response messages.

```dart
class SDKControlResponse extends SDKMessage {
  String requestId;
  String subtype;           // 'success' or 'error'
  Map<String, dynamic>? response;  // Response data
}
```

### SDKErrorMessage

Error messages.

```dart
class SDKErrorMessage extends SDKMessage {
  String error;             // Error message
  String? code;             // Error code
  Map<String, dynamic>? details;   // Additional details
}
```

### SDKUnknownMessage

Fallback for unrecognized message types.

```dart
class SDKUnknownMessage extends SDKMessage {
  String type;
  Map<String, dynamic> data;
}
```

---

## Content Blocks

Content blocks represent different types of content in messages.

### ContentBlock (Base)

```dart
sealed class ContentBlock {
  String get type;
}
```

### TextBlock

Plain text content.

```dart
class TextBlock extends ContentBlock {
  String text;
}
```

### ToolUseBlock

Tool invocation.

```dart
class ToolUseBlock extends ContentBlock {
  String id;                    // Unique tool use ID
  String name;                  // Tool name
  Map<String, dynamic> input;   // Tool parameters
}
```

### ToolResultBlock

Tool execution result.

```dart
class ToolResultBlock extends ContentBlock {
  String toolUseId;             // Matching tool use ID
  dynamic content;              // Result content
  bool? isError;                // Whether it's an error result
}
```

### ImageBlock

Image content.

```dart
class ImageBlock extends ContentBlock {
  ImageSource source;
}

class ImageSource {
  String type;          // 'base64' or 'url'
  String mediaType;     // 'image/png', 'image/jpeg', etc.
  String data;          // Base64 data or URL
}
```

### ThinkingBlock

Extended thinking content.

```dart
class ThinkingBlock extends ContentBlock {
  String thinking;      // Thinking text
  String? signature;    // Verification signature
}
```

### UnknownBlock

Fallback for unrecognized block types.

```dart
class UnknownBlock extends ContentBlock {
  Map<String, dynamic> data;
}
```

---

## Permission Handling

### PermissionRequest

Represents a permission request from Claude.

```dart
abstract class PermissionRequest {
  String get id;
  String get sessionId;
  String get toolName;
  Map<String, dynamic> get toolInput;
  String? get toolUseId;
  String? get blockedPath;
  List<dynamic>? get suggestions;
  List<PermissionSuggestion>? get parsedSuggestions;

  void allow({
    Map<String, dynamic>? updatedInput,
    List<PermissionSuggestion>? updatedPermissions,
  });

  void deny(String reason);
}
```

### Usage

```dart
session.permissionRequests.listen((request) {
  print('Tool: ${request.toolName}');
  print('Input: ${request.toolInput}');
  print('Blocked path: ${request.blockedPath}');

  // Approve with original input
  request.allow();

  // Or approve with modified input
  request.allow(
    updatedInput: {'command': 'ls -la'},
    updatedPermissions: request.parsedSuggestions,
  );

  // Or deny
  request.deny('User declined this operation');
});
```

### PermissionSuggestion

Suggested permission rules.

```dart
class PermissionSuggestion {
  String type;          // 'addRules', 'setMode', etc.
  String? behavior;     // 'allow', 'deny', 'ask'
  String? destination;  // 'session', 'project', 'global'
  List<PermissionRule>? rules;
  String? mode;         // For setMode type
  List<String>? directories;  // For directory types
}

class PermissionRule {
  String toolName;
  String? ruleContent;
}
```

### PermissionMode Enum

```dart
enum PermissionMode {
  defaultMode,       // Requires permission for most operations
  acceptEdits,       // Auto-approves file operations
  bypassPermissions, // Approves everything (dangerous)
  plan,              // Planning mode, restricted tools
}
```

---

## Hooks

Hooks allow you to intercept and respond to events during session execution.

### HookRequest

Represents a hook event from the CLI.

```dart
abstract class HookRequest {
  String get id;
  String get sessionId;
  String get hookType;      // 'PreToolUse', 'PostToolUse', etc.
  Map<String, dynamic> get data;

  void respond(HookResponse response);
}
```

### HookResponse

Response to a hook request.

```dart
class HookResponse {
  HookDecision decision;    // approve, block
  String? message;          // Optional message
  Map<String, dynamic>? modifiedData;  // Modified tool input
}

enum HookDecision { approve, block }
```

### Hook Types

| Hook | When | Use Case |
|------|------|----------|
| `PreToolUse` | Before tool executes | Modify input, block dangerous operations |
| `PostToolUse` | After tool completes | Log results, trigger side effects |
| `SessionStart` | Session begins | Initialize resources |
| `SessionEnd` | Session ends | Cleanup resources |

### Usage

```dart
session.hookRequests.listen((request) {
  if (request.hookType == 'PreToolUse') {
    final toolName = request.data['tool_name'];
    final toolInput = request.data['tool_input'];

    // Approve with optional modifications
    request.respond(HookResponse(
      decision: HookDecision.approve,
      modifiedData: toolInput,
    ));

    // Or block
    request.respond(HookResponse(
      decision: HookDecision.block,
      message: 'Operation not allowed',
    ));
  }
});
```

---

## Session Options

### SessionOptions

Configuration options for creating a session.

```dart
class SessionOptions {
  String? model;                    // Model selection
  PermissionMode? permissionMode;   // Permission mode
  SystemPromptConfig? systemPrompt; // System prompt configuration
  Map<String, McpServerConfig>? mcpServers;  // MCP servers
  Map<String, dynamic>? agents;     // Subagent configuration
  Map<String, dynamic>? hooks;      // Hook configuration
  int? maxTurns;                    // Maximum turns
  double? maxBudgetUsd;             // Maximum cost
  int? maxThinkingTokens;           // Extended thinking budget
  List<String>? allowedTools;       // Auto-approved tools
  List<String>? disallowedTools;    // Blocked tools
  List<String>? additionalDirectories;  // Extra allowed directories
  String? resume;                   // Session ID to resume
  Map<String, dynamic>? outputFormat;   // Output format options
}
```

### SystemPromptConfig

```dart
// Custom system prompt
class CustomSystemPrompt implements SystemPromptConfig {
  String prompt;
}

// Preset with additions
class PresetSystemPrompt implements SystemPromptConfig {
  String? append;  // Text to append to preset
}
```

### MCP Server Configuration

```dart
// Stdio-based MCP server
class McpStdioServerConfig implements McpServerConfig {
  String command;
  List<String>? args;
  Map<String, String>? env;
}

// SSE-based MCP server
class McpSseServerConfig implements McpServerConfig {
  String url;
  Map<String, String>? headers;
}

// HTTP-based MCP server
class McpHttpServerConfig implements McpServerConfig {
  String url;
}
```

---

## Usage & Cost Tracking

### Usage

Token usage for a message.

```dart
class Usage {
  int? inputTokens;
  int? outputTokens;
  int? cacheCreationInputTokens;
  int? cacheReadInputTokens;

  int get totalTokens => (inputTokens ?? 0) + (outputTokens ?? 0);
}
```

### ModelUsage

Per-model usage breakdown.

```dart
class ModelUsage {
  int inputTokens;
  int outputTokens;
  int? cacheReadInputTokens;
  int? cacheCreationInputTokens;
  int? webSearchRequests;
  double costUsd;
  int contextWindow;
  int? maxOutputTokens;
}
```

### Accessing Usage Data

```dart
session.messages.listen((msg) {
  if (msg is SDKResultMessage) {
    // Total cost
    print('Total cost: \$${msg.totalCostUsd}');

    // Token usage
    final usage = msg.usage;
    if (usage != null) {
      print('Input tokens: ${usage.inputTokens}');
      print('Output tokens: ${usage.outputTokens}');
      print('Cache read: ${usage.cacheReadInputTokens}');
      print('Cache creation: ${usage.cacheCreationInputTokens}');
    }

    // Per-model breakdown
    msg.modelUsage?.forEach((model, usage) {
      print('$model:');
      print('  Cost: \$${usage.costUsd}');
      print('  Input: ${usage.inputTokens}');
      print('  Output: ${usage.outputTokens}');
    });
  }
});
```

---

## Logging

### SdkLogger

Centralized logging for the SDK.

```dart
class SdkLogger {
  static SdkLogger get instance;

  bool debugEnabled;                // Enable debug logging
  Stream<LogEntry> get logs;        // Log stream

  void enableFileLogging(String path);
  Future<void> disableFileLogging();
  Future<void> dispose();

  void debug(String message, {String? sessionId, Map<String, dynamic>? data});
  void info(String message, {String? sessionId, Map<String, dynamic>? data});
  void warning(String message, {String? sessionId, Map<String, dynamic>? data});
  void error(String message, {String? sessionId, Map<String, dynamic>? data});
}
```

### LogEntry

```dart
class LogEntry {
  LogLevel level;           // debug, info, warning, error
  String message;
  DateTime timestamp;
  LogDirection? direction;  // stdin, stdout, stderr, internal
  String? sessionId;
  Map<String, dynamic>? data;
  String? text;
}

enum LogLevel { debug, info, warning, error }
enum LogDirection { stdin, stdout, stderr, internal }
```

### Usage

```dart
// Enable debug logging
SdkLogger.instance.debugEnabled = true;

// Subscribe to logs
SdkLogger.instance.logs.listen((entry) {
  print('[${entry.level.name}] ${entry.message}');
});

// Write to file
SdkLogger.instance.enableFileLogging('/tmp/sdk.log');
```

---

## Errors

### Error Classes

```dart
class ClaudeError implements Exception {
  String message;
}

class BackendError extends ClaudeError {
  String code;
  String? details;
}

class BackendProcessError extends BackendError {
  // Process spawn/management errors
}

class SessionCreateError extends BackendError {
  // Session creation failures
}

class SessionNotFoundError extends BackendError {
  String sessionId;
}

class CommunicationError extends BackendError {
  // Protocol/communication errors
}
```

### Error Handling

```dart
try {
  final session = await backend.createSession(
    prompt: 'Hello',
    cwd: '/tmp',
  );
} on SessionCreateError catch (e) {
  print('Failed to create session: ${e.message}');
} on BackendProcessError catch (e) {
  print('Backend process error: ${e.message}');
} on BackendError catch (e) {
  print('Backend error [${e.code}]: ${e.message}');
}
```

---

## Single Request

For one-shot CLI execution without session management.

### ClaudeSingleRequest

```dart
class ClaudeSingleRequest {
  ClaudeSingleRequest({
    String claudePath = 'claude',
    void Function(String, {bool isError})? onLog,
  });

  Future<SingleRequestResult?> request({
    required String prompt,
    String? workingDirectory,
    SingleRequestOptions? options,
  });
}
```

### SingleRequestOptions

```dart
class SingleRequestOptions {
  String? model;
  int? maxTurns;
  List<String>? allowedTools;
  String? permissionMode;
  int? timeoutSeconds;
}
```

### SingleRequestResult

```dart
class SingleRequestResult {
  String? result;           // Response text
  bool isError;
  int? durationMs;
  int? durationApiMs;
  int? numTurns;
  double? totalCostUsd;
  Usage? usage;
  Map<String, ModelUsage>? modelUsage;
  List<String>? errors;
}
```

### Usage

```dart
final claude = ClaudeSingleRequest(
  claudePath: 'claude',
  onLog: (msg, {isError = false}) => print(msg),
);

final result = await claude.request(
  prompt: 'Generate a commit message for the current changes',
  workingDirectory: '/path/to/repo',
  options: SingleRequestOptions(
    model: 'sonnet',
    maxTurns: 5,
    allowedTools: ['Bash', 'Read'],
    permissionMode: 'acceptEdits',
    timeoutSeconds: 60,
  ),
);

if (result != null && !result.isError) {
  print('Result: ${result.result}');
  print('Cost: \$${result.totalCostUsd}');
}
```

---

## Testing Support

### Test Sessions

For unit testing without actual CLI connections.

```dart
// Create a test session
final session = ClaudeSession.forTesting(sessionId: 'test-123');

// Emit test messages
session.emitTestMessage(SDKAssistantMessage(
  uuid: 'msg-1',
  sessionId: 'test-123',
  message: APIAssistantMessage(
    role: 'assistant',
    content: [TextBlock(text: 'Test response')],
  ),
));

// Check sent messages
expect(session.testSentMessages, hasLength(1));

// Emit permission request and get response
final responseFuture = session.emitTestPermissionRequest(
  id: 'perm-1',
  toolName: 'Bash',
  toolInput: {'command': 'ls'},
);

// Get the request from the stream and respond
final request = await session.permissionRequests.first;
request.allow();

final response = await responseFuture;
expect(response, isA<PermissionAllowResponse>());
```
