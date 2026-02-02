# Getting Started with Claude Dart SDK

This guide covers installation, configuration, and basic usage of the Claude Dart SDK.

## Prerequisites

### 1. Dart/Flutter SDK

Ensure you have Dart SDK >= 3.0.0 installed:

```bash
dart --version
```

### 2. Claude CLI

The SDK communicates with Claude through the Claude CLI. Install it via npm:

```bash
npm install -g @anthropic-ai/claude-cli
```

Or download from the [Claude Code releases](https://github.com/anthropics/claude-code/releases).

Verify installation:

```bash
claude --version
```

### 3. Authentication

The Claude CLI handles authentication. You can use:

- **Claude Max subscription**: Authenticate via `claude login`
- **API Key**: Set the `ANTHROPIC_API_KEY` environment variable

## Installation

Add the SDK to your `pubspec.yaml`:

```yaml
dependencies:
  claude_sdk:
    path: path/to/claude_dart_sdk
```

Then run:

```bash
dart pub get
# or for Flutter:
flutter pub get
```

## Basic Usage

### Creating a Backend

The backend manages CLI processes and sessions:

```dart
import 'package:claude_sdk/claude_sdk.dart';

void main() async {
  // Create with defaults
  final backend = await BackendFactory.create();

  // Or specify custom CLI path
  final backend = await BackendFactory.create(
    executablePath: '/usr/local/bin/claude',
  );
}
```

### Creating a Session

A session represents an ongoing conversation:

```dart
final session = await backend.createSession(
  prompt: 'Help me understand this codebase',
  cwd: '/path/to/project',
  options: SessionOptions(
    model: 'sonnet',
    permissionMode: PermissionMode.default,
  ),
);
```

### Listening for Messages

Messages are delivered via streams:

```dart
session.messages.listen((message) {
  switch (message) {
    case SDKSystemMessage():
      print('System: ${message.subtype}');
      if (message.subtype == 'init') {
        print('Model: ${message.model}');
        print('Tools: ${message.tools}');
      }

    case SDKAssistantMessage():
      print('Claude: ${message.textContent}');
      // Check for tool uses
      for (final block in message.message.content) {
        if (block is ToolUseBlock) {
          print('Using tool: ${block.name}');
        }
      }

    case SDKUserMessage():
      // Tool results or user input
      if (message.toolUseResult != null) {
        print('Tool result received');
      }

    case SDKResultMessage():
      // Turn complete
      print('Result: ${message.result}');
      print('Cost: \$${message.totalCostUsd}');
      print('Turns: ${message.numTurns}');

    case SDKErrorMessage():
      print('Error: ${message.error}');

    default:
      // Handle other message types
  }
});
```

### Handling Permission Requests

When Claude wants to use a tool that requires approval:

```dart
session.permissionRequests.listen((request) {
  print('Tool: ${request.toolName}');
  print('Input: ${request.toolInput}');

  // Check the tool and decide
  if (request.toolName == 'Bash') {
    final command = request.toolInput['command'] as String?;
    if (command != null && command.contains('rm')) {
      // Dangerous command - deny
      request.deny('Delete operations not allowed');
      return;
    }
  }

  // Allow the operation
  request.allow();
});
```

### Sending Follow-up Messages

Continue the conversation:

```dart
// Send text
await session.send('Now create a test file');

// Send with multi-modal content
await session.sendWithContent([
  TextBlock(text: 'What is in this image?'),
  ImageBlock(
    source: ImageSource(
      type: 'base64',
      mediaType: 'image/png',
      data: base64EncodedImageData,
    ),
  ),
]);
```

### Changing Session Settings

Adjust settings mid-session:

```dart
// Switch models
await session.setModel('opus');

// Change permission mode
await session.setPermissionMode('acceptEdits');
```

### Interrupting and Stopping

Control session execution:

```dart
// Interrupt current operation (allows graceful stop)
await session.interrupt();

// Kill session immediately
await session.kill();
```

### Cleanup

Always dispose resources when done:

```dart
// Kill session
await session.kill();

// Dispose backend (kills all sessions)
await backend.dispose();
```

## Complete Example

```dart
import 'package:claude_sdk/claude_sdk.dart';

Future<void> main() async {
  // Create backend
  final backend = await BackendFactory.create();

  try {
    // Create session
    final session = await backend.createSession(
      prompt: 'List the files in the current directory',
      cwd: '/tmp',
      options: SessionOptions(
        model: 'sonnet',
        permissionMode: PermissionMode.acceptEdits,
      ),
    );

    // Track completion
    final completer = Completer<void>();

    // Handle permissions
    session.permissionRequests.listen((request) {
      print('Permission requested for: ${request.toolName}');
      request.allow();
    });

    // Handle messages
    session.messages.listen(
      (message) {
        if (message is SDKAssistantMessage) {
          print('Claude: ${message.textContent}');
        } else if (message is SDKResultMessage) {
          print('\n--- Session Complete ---');
          print('Total cost: \$${message.totalCostUsd?.toStringAsFixed(4)}');
          print('Turns: ${message.numTurns}');
          completer.complete();
        }
      },
      onError: (error) {
        print('Error: $error');
        completer.completeError(error);
      },
    );

    // Wait for completion
    await completer.future;

  } finally {
    await backend.dispose();
  }
}
```

## Configuration Options

### SessionOptions

| Option | Type | Description |
|--------|------|-------------|
| `model` | `String?` | Model to use: `'sonnet'`, `'opus'`, `'haiku'`, `'default'` |
| `permissionMode` | `PermissionMode?` | Permission handling mode |
| `systemPrompt` | `SystemPromptConfig?` | Custom or preset system prompt |
| `mcpServers` | `Map<String, McpServerConfig>?` | MCP server configurations |
| `maxTurns` | `int?` | Maximum conversation turns |
| `maxBudgetUsd` | `double?` | Maximum cost budget |
| `maxThinkingTokens` | `int?` | Extended thinking token limit |
| `allowedTools` | `List<String>?` | Tools to allow without prompting |
| `disallowedTools` | `List<String>?` | Tools to block |
| `additionalDirectories` | `List<String>?` | Extra directories to allow access |
| `resume` | `String?` | Session ID to resume |

### Permission Modes

| Mode | Description |
|------|-------------|
| `PermissionMode.defaultMode` | Requires permission for most operations |
| `PermissionMode.acceptEdits` | Auto-approves file operations in project |
| `PermissionMode.bypassPermissions` | Approves everything (use with caution) |
| `PermissionMode.plan` | Planning mode with restricted tools |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_SDK_DEBUG` | Set to `true` for debug logging |
| `CLAUDE_SDK_LOG_FILE` | Path for log file output |

## Debugging

### Enable Debug Logging

```dart
// Programmatically
SdkLogger.instance.debugEnabled = true;

// Subscribe to logs
SdkLogger.instance.logs.listen((entry) {
  print('[${entry.level}] ${entry.message}');
  if (entry.data != null) {
    print('  Data: ${jsonEncode(entry.data)}');
  }
});

// Write to file
SdkLogger.instance.enableFileLogging('/tmp/sdk-debug.log');
```

### Environment Variable

```bash
export CLAUDE_SDK_DEBUG=true
export CLAUDE_SDK_LOG_FILE=/tmp/sdk-debug.log
```

## Error Handling

```dart
try {
  final session = await backend.createSession(
    prompt: 'Hello',
    cwd: '/nonexistent',
  );
} on BackendProcessError catch (e) {
  print('Process error: ${e.message}');
} on BackendError catch (e) {
  print('Backend error: ${e.code} - ${e.message}');
} catch (e) {
  print('Unexpected error: $e');
}
```

## Next Steps

- See [API Reference](API_REFERENCE.md) for complete API documentation
- See [Protocol](PROTOCOL.md) for CLI communication details
- See [Examples](EXAMPLES.md) for more code patterns
