# Examples

Practical code examples for common SDK usage patterns.

## Table of Contents

- [Basic Usage](#basic-usage)
- [Permission Handling](#permission-handling)
- [Multi-Modal Content](#multi-modal-content)
- [Session Control](#session-control)
- [Cost Tracking](#cost-tracking)
- [Error Handling](#error-handling)
- [Subagent Handling](#subagent-handling)
- [Streaming](#streaming)
- [Single Request](#single-request)
- [Flutter Integration](#flutter-integration)

---

## Basic Usage

### Simple Conversation

```dart
import 'package:claude_sdk/claude_sdk.dart';

Future<void> simpleConversation() async {
  final backend = await BackendFactory.create();

  try {
    final session = await backend.createSession(
      prompt: 'What is the capital of France?',
      cwd: '/tmp',
    );

    await for (final message in session.messages) {
      if (message is SDKAssistantMessage) {
        print('Claude: ${message.textContent}');
      } else if (message is SDKResultMessage) {
        print('Completed in ${message.numTurns} turns');
        break;
      }
    }
  } finally {
    await backend.dispose();
  }
}
```

### Multi-Turn Conversation

```dart
Future<void> multiTurnConversation() async {
  final backend = await BackendFactory.create();

  try {
    final session = await backend.createSession(
      prompt: 'I want to learn about Dart programming.',
      cwd: '/tmp',
    );

    // Collect first response
    await for (final message in session.messages) {
      if (message is SDKAssistantMessage) {
        print('Claude: ${message.textContent}');
      } else if (message is SDKResultMessage) {
        break;
      }
    }

    // Send follow-up
    await session.send('Can you show me an example of a class?');

    // Collect second response
    await for (final message in session.messages) {
      if (message is SDKAssistantMessage) {
        print('Claude: ${message.textContent}');
      } else if (message is SDKResultMessage) {
        break;
      }
    }
  } finally {
    await backend.dispose();
  }
}
```

### With Session Options

```dart
Future<void> withOptions() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Help me refactor this code',
    cwd: '/path/to/project',
    options: SessionOptions(
      model: 'opus',
      permissionMode: PermissionMode.acceptEdits,
      maxTurns: 10,
      maxBudgetUsd: 5.0,
      allowedTools: ['Read', 'Edit', 'Write', 'Glob', 'Grep'],
      additionalDirectories: ['/shared/libs'],
    ),
  );

  // ... use session
}
```

---

## Permission Handling

### Basic Permission Approval

```dart
Future<void> handlePermissions() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Create a test file',
    cwd: '/tmp',
    options: SessionOptions(
      permissionMode: PermissionMode.defaultMode,
    ),
  );

  // Handle permission requests
  session.permissionRequests.listen((request) {
    print('Permission requested for: ${request.toolName}');
    print('Input: ${request.toolInput}');

    // Always allow (for demo purposes)
    request.allow();
  });

  // Handle messages
  await for (final message in session.messages) {
    if (message is SDKResultMessage) {
      print('Done');
      break;
    }
  }
}
```

### Selective Permission Approval

```dart
void handleSelectivePermissions(PermissionRequest request) {
  final toolName = request.toolName;
  final input = request.toolInput;

  switch (toolName) {
    case 'Bash':
      final command = input['command'] as String? ?? '';

      // Block dangerous commands
      if (command.contains('rm -rf') ||
          command.contains('sudo') ||
          command.contains('chmod 777')) {
        request.deny('Dangerous command not allowed');
        return;
      }

      // Allow safe commands
      request.allow();

    case 'Write':
    case 'Edit':
      final filePath = input['file_path'] as String? ?? '';

      // Only allow edits in specific directories
      if (filePath.startsWith('/tmp/') ||
          filePath.startsWith('/home/user/project/')) {
        request.allow();
      } else {
        request.deny('File outside allowed directories');
      }

    case 'Read':
    case 'Glob':
    case 'Grep':
      // Allow read-only operations
      request.allow();

    default:
      // Deny unknown tools
      request.deny('Unknown tool');
  }
}
```

### Permission with Modified Input

```dart
void handleWithModifiedInput(PermissionRequest request) {
  if (request.toolName == 'Bash') {
    final command = request.toolInput['command'] as String;

    // Add timeout to all commands
    final modifiedInput = Map<String, dynamic>.from(request.toolInput);
    modifiedInput['timeout'] = 30000; // 30 seconds

    // Sandbox paths
    modifiedInput['command'] = command.replaceAll('/tmp', '/tmp/sandbox');

    request.allow(updatedInput: modifiedInput);
  } else {
    request.allow();
  }
}
```

### Handle AskUserQuestion

```dart
void handleClarifyingQuestions(PermissionRequest request) {
  if (request.toolName == 'AskUserQuestion') {
    final questions = request.toolInput['questions'] as List;
    final answers = <String, String>{};

    for (final q in questions) {
      final question = q['question'] as String;
      final options = q['options'] as List;

      // Simulate user selecting first option
      final firstOption = options[0];
      answers[question] = firstOption['label'] as String;

      print('Q: $question');
      print('A: ${answers[question]}');
    }

    request.allow(
      updatedInput: {
        'questions': questions,
        'answers': answers,
      },
    );
  }
}
```

---

## Multi-Modal Content

### Sending Images

```dart
import 'dart:convert';
import 'dart:io';

Future<void> sendImage() async {
  final backend = await BackendFactory.create();

  // Read and encode image
  final imageBytes = await File('/path/to/image.png').readAsBytes();
  final base64Image = base64Encode(imageBytes);

  final session = await backend.createSession(
    prompt: '',  // Prompt included in content
    cwd: '/tmp',
    content: [
      TextBlock(text: 'What do you see in this image?'),
      ImageBlock(
        source: ImageSource(
          type: 'base64',
          mediaType: 'image/png',
          data: base64Image,
        ),
      ),
    ],
  );

  await for (final message in session.messages) {
    if (message is SDKAssistantMessage) {
      print('Claude: ${message.textContent}');
    } else if (message is SDKResultMessage) {
      break;
    }
  }
}
```

### Follow-up with Image

```dart
Future<void> followUpWithImage(AgentSession session) async {
  final imageBytes = await File('/path/to/screenshot.png').readAsBytes();

  await session.sendWithContent([
    TextBlock(text: 'Here is the error screenshot:'),
    ImageBlock(
      source: ImageSource(
        type: 'base64',
        mediaType: 'image/png',
        data: base64Encode(imageBytes),
      ),
    ),
    TextBlock(text: 'How do I fix this?'),
  ]);
}
```

---

## Session Control

### Changing Model Mid-Session

```dart
Future<void> switchModel() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Start with a simple task',
    cwd: '/tmp',
    options: SessionOptions(model: 'haiku'),
  );

  // Wait for first response
  await for (final message in session.messages) {
    if (message is SDKResultMessage) break;
  }

  // Switch to more capable model for complex task
  await session.setModel('opus');

  // Send complex follow-up
  await session.send('Now analyze this codebase architecture');
}
```

### Interrupting a Session

```dart
Future<void> interruptExample() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Write a very long story',
    cwd: '/tmp',
  );

  // Start a timer to interrupt after 10 seconds
  Timer(Duration(seconds: 10), () async {
    print('Interrupting session...');
    await session.interrupt();
  });

  await for (final message in session.messages) {
    if (message is SDKAssistantMessage) {
      print('Claude: ${message.textContent?.substring(0, 100)}...');
    } else if (message is SDKResultMessage) {
      print('Session ended: ${message.subtype}');
      break;
    }
  }
}
```

### Graceful Shutdown

```dart
class SessionManager {
  AgentBackend? _backend;
  AgentSession? _session;

  Future<void> startSession(String prompt, String cwd) async {
    _backend = await BackendFactory.create();
    _session = await _backend!.createSession(
      prompt: prompt,
      cwd: cwd,
    );
  }

  Future<void> shutdown() async {
    if (_session != null) {
      try {
        await _session!.interrupt();
        await Future.delayed(Duration(seconds: 2));
        await _session!.kill();
      } catch (e) {
        print('Error during shutdown: $e');
      }
    }

    if (_backend != null) {
      await _backend!.dispose();
    }
  }
}
```

---

## Cost Tracking

### Basic Cost Tracking

```dart
Future<void> trackCost() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Analyze this codebase',
    cwd: '/path/to/project',
  );

  double totalCost = 0;
  int totalInputTokens = 0;
  int totalOutputTokens = 0;

  await for (final message in session.messages) {
    if (message is SDKResultMessage) {
      totalCost = message.totalCostUsd ?? 0;

      final usage = message.usage;
      if (usage != null) {
        totalInputTokens = usage.inputTokens ?? 0;
        totalOutputTokens = usage.outputTokens ?? 0;
      }

      print('--- Cost Summary ---');
      print('Total cost: \$${totalCost.toStringAsFixed(4)}');
      print('Input tokens: $totalInputTokens');
      print('Output tokens: $totalOutputTokens');

      // Per-model breakdown
      message.modelUsage?.forEach((model, usage) {
        print('$model: \$${usage.costUsd.toStringAsFixed(4)}');
      });

      break;
    }
  }
}
```

### Cost Tracking Service

```dart
class CostTracker {
  final Map<String, double> _sessionCosts = {};
  final Set<String> _processedMessageIds = {};

  void onMessage(SDKMessage message) {
    if (message is SDKResultMessage) {
      // Use result message for final cost
      _sessionCosts[message.sessionId] = message.totalCostUsd ?? 0;
    }
  }

  double getSessionCost(String sessionId) {
    return _sessionCosts[sessionId] ?? 0;
  }

  double getTotalCost() {
    return _sessionCosts.values.fold(0.0, (sum, cost) => sum + cost);
  }

  Map<String, double> getCostsBySession() {
    return Map.unmodifiable(_sessionCosts);
  }
}
```

---

## Error Handling

### Comprehensive Error Handling

```dart
Future<void> withErrorHandling() async {
  AgentBackend? backend;

  try {
    backend = await BackendFactory.create();

    final session = await backend.createSession(
      prompt: 'Hello',
      cwd: '/tmp',
    );

    await for (final message in session.messages) {
      if (message is SDKErrorMessage) {
        print('Error: ${message.error}');
        print('Code: ${message.code}');
        break;
      } else if (message is SDKResultMessage) {
        if (message.isError) {
          print('Result error: ${message.result}');
        } else {
          print('Success: ${message.result}');
        }
        break;
      }
    }
  } on BackendProcessError catch (e) {
    print('Failed to start backend: ${e.message}');
  } on SessionCreateError catch (e) {
    print('Failed to create session: ${e.message}');
  } on BackendError catch (e) {
    print('Backend error [${e.code}]: ${e.message}');
  } catch (e, stack) {
    print('Unexpected error: $e');
    print(stack);
  } finally {
    await backend?.dispose();
  }
}
```

### Retry Logic

```dart
Future<AgentSession?> createSessionWithRetry({
  required AgentBackend backend,
  required String prompt,
  required String cwd,
  int maxRetries = 3,
}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await backend.createSession(
        prompt: prompt,
        cwd: cwd,
      );
    } on BackendError catch (e) {
      print('Attempt $attempt failed: ${e.message}');

      if (attempt < maxRetries) {
        final delay = Duration(seconds: attempt * 2);
        print('Retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
      } else {
        print('Max retries exceeded');
        rethrow;
      }
    }
  }
  return null;
}
```

---

## Subagent Handling

### Tracking Subagent Messages

```dart
Future<void> trackSubagents() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Use a subagent to analyze this file',
    cwd: '/path/to/project',
  );

  final Map<String, List<SDKMessage>> subagentMessages = {};

  await for (final message in session.messages) {
    // Check if message is from a subagent
    final parentToolUseId = switch (message) {
      SDKAssistantMessage m => m.parentToolUseId,
      SDKUserMessage m => m.parentToolUseId,
      _ => null,
    };

    if (parentToolUseId != null) {
      subagentMessages.putIfAbsent(parentToolUseId, () => []);
      subagentMessages[parentToolUseId]!.add(message);
      print('[Subagent $parentToolUseId] ${message.runtimeType}');
    } else if (message is SDKAssistantMessage) {
      print('[Main] Claude: ${message.textContent}');
    }

    if (message is SDKResultMessage) break;
  }

  print('Subagent conversations: ${subagentMessages.length}');
}
```

---

## Streaming

### Handle Stream Events

```dart
Future<void> handleStreaming() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Tell me a story',
    cwd: '/tmp',
    options: SessionOptions(
      // Enable streaming if available
    ),
  );

  final StringBuffer currentText = StringBuffer();

  await for (final message in session.messages) {
    if (message is SDKStreamEvent) {
      final textDelta = message.textDelta;
      if (textDelta != null) {
        stdout.write(textDelta);
        currentText.write(textDelta);
      }

      final thinkingDelta = message.thinkingDelta;
      if (thinkingDelta != null) {
        stdout.write('[Thinking: $thinkingDelta]');
      }
    } else if (message is SDKAssistantMessage) {
      // Final message with full content
      print('\n\n--- Full response ---');
      print(message.textContent);
    } else if (message is SDKResultMessage) {
      break;
    }
  }
}
```

---

## Single Request

### One-Shot Request

```dart
Future<void> singleRequest() async {
  final claude = ClaudeSingleRequest(
    claudePath: 'claude',
    onLog: (msg, {isError = false}) {
      if (isError) {
        stderr.writeln(msg);
      } else {
        print(msg);
      }
    },
  );

  final result = await claude.request(
    prompt: 'Generate a commit message for the staged changes',
    workingDirectory: '/path/to/repo',
    options: SingleRequestOptions(
      model: 'sonnet',
      maxTurns: 3,
      allowedTools: ['Bash', 'Read'],
      permissionMode: 'acceptEdits',
      timeoutSeconds: 30,
    ),
  );

  if (result != null && !result.isError) {
    print('Result: ${result.result}');
    print('Cost: \$${result.totalCostUsd}');
    print('Duration: ${result.durationMs}ms');
  } else {
    print('Request failed');
    result?.errors?.forEach(print);
  }
}
```

---

## Flutter Integration

### Using with Provider

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:claude_sdk/claude_sdk.dart';

class ClaudeService extends ChangeNotifier {
  AgentBackend? _backend;
  AgentSession? _session;
  List<String> _messages = [];
  bool _isLoading = false;
  double _totalCost = 0;

  List<String> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  double get totalCost => _totalCost;

  Future<void> initialize() async {
    _backend = await BackendFactory.create();
  }

  Future<void> startChat(String prompt, String cwd) async {
    _isLoading = true;
    _messages = [];
    notifyListeners();

    try {
      _session = await _backend!.createSession(
        prompt: prompt,
        cwd: cwd,
        options: SessionOptions(
          permissionMode: PermissionMode.acceptEdits,
        ),
      );

      _session!.permissionRequests.listen((request) {
        request.allow();
      });

      await for (final message in _session!.messages) {
        if (message is SDKAssistantMessage) {
          final text = message.textContent;
          if (text != null) {
            _messages.add(text);
            notifyListeners();
          }
        } else if (message is SDKResultMessage) {
          _totalCost = message.totalCostUsd ?? 0;
          break;
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String message) async {
    if (_session == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _session!.send(message);

      await for (final msg in _session!.messages) {
        if (msg is SDKAssistantMessage) {
          final text = msg.textContent;
          if (text != null) {
            _messages.add(text);
            notifyListeners();
          }
        } else if (msg is SDKResultMessage) {
          _totalCost = msg.totalCostUsd ?? 0;
          break;
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> dispose() async {
    await _session?.kill();
    await _backend?.dispose();
    super.dispose();
  }
}

// Usage in widget:
class ChatScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ClaudeService>(
      builder: (context, service, child) {
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: service.messages.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(service.messages[index]),
                  );
                },
              ),
            ),
            if (service.isLoading)
              CircularProgressIndicator(),
            Text('Cost: \$${service.totalCost.toStringAsFixed(4)}'),
          ],
        );
      },
    );
  }
}
```

### Permission Dialog

```dart
class PermissionDialog extends StatelessWidget {
  final PermissionRequest request;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const PermissionDialog({
    required this.request,
    required this.onAllow,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Permission Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tool: ${request.toolName}'),
          SizedBox(height: 8),
          Text('Input:'),
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Text(
              request.toolInput.toString(),
              style: TextStyle(fontFamily: 'monospace'),
            ),
          ),
          if (request.blockedPath != null) ...[
            SizedBox(height: 8),
            Text('Path: ${request.blockedPath}'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDeny,
          child: Text('Deny'),
        ),
        ElevatedButton(
          onPressed: onAllow,
          child: Text('Allow'),
        ),
      ],
    );
  }
}

// Show dialog:
void showPermissionDialog(BuildContext context, PermissionRequest request) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => PermissionDialog(
      request: request,
      onAllow: () {
        request.allow();
        Navigator.of(context).pop();
      },
      onDeny: () {
        request.deny('User denied');
        Navigator.of(context).pop();
      },
    ),
  );
}
```

---

## Session Resume

### Resume a Previous Session

```dart
Future<void> resumeSession() async {
  final backend = await BackendFactory.create();

  // Store session ID from a previous session
  final previousSessionId = 'ee5e97bf-0000-0000-0000-000000000001';

  // Resume the session
  final session = await backend.createSession(
    prompt: 'Continue where we left off',
    cwd: '/path/to/project',
    options: SessionOptions(
      resume: previousSessionId,  // Resume from previous session
    ),
  );

  await for (final message in session.messages) {
    if (message is SDKAssistantMessage) {
      print('Claude: ${message.textContent}');
    } else if (message is SDKResultMessage) {
      // Save session ID for future resumption
      print('Session ID: ${message.sessionId}');
      break;
    }
  }
}
```

---

## Extended Thinking

### Configure Extended Thinking

```dart
Future<void> extendedThinking() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Solve this complex problem step by step',
    cwd: '/tmp',
    options: SessionOptions(
      model: 'opus',  // Extended thinking works best with Opus
      maxThinkingTokens: 50000,  // Budget for thinking
    ),
  );

  await for (final message in session.messages) {
    if (message is SDKStreamEvent) {
      // Capture thinking process
      final thinking = message.thinkingDelta;
      if (thinking != null) {
        print('[Thinking] $thinking');
      }

      // Capture regular output
      final text = message.textDelta;
      if (text != null) {
        stdout.write(text);
      }
    } else if (message is SDKAssistantMessage) {
      // Check for thinking blocks in final message
      for (final block in message.message.content) {
        if (block is ThinkingBlock) {
          print('\n--- Thinking Process ---');
          print(block.thinking);
        }
      }
    } else if (message is SDKResultMessage) {
      print('\nThinking tokens used: Check modelUsage');
      break;
    }
  }
}
```

---

## AskUserQuestion Interactive Example

### Interactive Question Handler

```dart
import 'dart:io';

Future<void> interactiveQuestionHandler() async {
  final backend = await BackendFactory.create();

  final session = await backend.createSession(
    prompt: 'Help me plan a new feature for my app',
    cwd: '/path/to/project',
    options: SessionOptions(
      permissionMode: PermissionMode.plan,  // Plan mode uses questions more
    ),
  );

  session.permissionRequests.listen((request) {
    if (request.toolName == 'AskUserQuestion') {
      final questions = request.toolInput['questions'] as List;
      final answers = <String, String>{};

      for (final q in questions) {
        final question = q['question'] as String;
        final header = q['header'] as String;
        final options = q['options'] as List;
        final multiSelect = q['multiSelect'] as bool? ?? false;

        print('\n=== $header ===');
        print(question);
        print('');

        for (int i = 0; i < options.length; i++) {
          final opt = options[i];
          print('  ${i + 1}. ${opt['label']} - ${opt['description']}');
        }

        if (multiSelect) {
          print('\nEnter numbers separated by commas (e.g., 1,3):');
        } else {
          print('\nEnter number or type custom answer:');
        }

        final input = stdin.readLineSync() ?? '1';

        // Parse response
        String answer;
        if (int.tryParse(input.split(',').first) != null) {
          final indices = input.split(',').map((s) => int.tryParse(s.trim()) ?? 0);
          final labels = indices
              .where((i) => i > 0 && i <= options.length)
              .map((i) => options[i - 1]['label'] as String);
          answer = labels.join(', ');
        } else {
          answer = input;  // Free-text answer
        }

        answers[question] = answer;
        print('Selected: $answer');
      }

      request.allow(
        updatedInput: {
          'questions': questions,
          'answers': answers,
        },
      );
    } else {
      request.allow();
    }
  });

  await for (final message in session.messages) {
    if (message is SDKAssistantMessage) {
      print('\nClaude: ${message.textContent}');
    } else if (message is SDKResultMessage) {
      break;
    }
  }
}
```
