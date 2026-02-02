# Agent Howto

Concise reference for AI agents using the Claude Dart SDK.

## Quick Reference

### Create Backend & Session

```dart
import 'package:claude_sdk/claude_sdk.dart';

final backend = await BackendFactory.create();
final session = await backend.createSession(
  prompt: 'Your task here',
  cwd: '/working/directory',
  options: SessionOptions(
    model: 'sonnet',  // 'opus', 'haiku', 'default'
    permissionMode: PermissionMode.acceptEdits,
  ),
);
```

### Listen for Messages

```dart
session.messages.listen((msg) {
  switch (msg) {
    case SDKAssistantMessage():
      print(msg.textContent);  // Claude's response text
    case SDKResultMessage():
      print('Done. Cost: \$${msg.totalCostUsd}');
    case SDKErrorMessage():
      print('Error: ${msg.error}');
  }
});
```

### Handle Permissions

```dart
session.permissionRequests.listen((req) {
  // req.toolName - 'Bash', 'Write', 'Edit', etc.
  // req.toolInput - tool parameters
  req.allow();  // or req.deny('reason');
});
```

### Send Follow-up

```dart
await session.send('Follow-up message');
```

### Cleanup

```dart
await session.kill();
await backend.dispose();
```

---

## Key Classes

| Class | Purpose |
|-------|---------|
| `BackendFactory` | Creates backend instances |
| `AgentBackend` | Manages sessions |
| `AgentSession` | Active conversation |
| `SDKMessage` | Base message type |
| `PermissionRequest` | Tool permission request |
| `SessionOptions` | Session configuration |

---

## Message Types

| Type | When | Key Fields |
|------|------|------------|
| `SDKSystemMessage` | Session init | `tools`, `model`, `permissionMode` |
| `SDKAssistantMessage` | Claude speaks | `textContent`, `message.content` |
| `SDKUserMessage` | Tool results | `toolUseResult` |
| `SDKResultMessage` | Turn ends | `totalCostUsd`, `numTurns`, `result` |
| `SDKErrorMessage` | Errors | `error`, `code` |

---

## Permission Modes

| Mode | Effect |
|------|--------|
| `PermissionMode.defaultMode` | Prompts for most tools |
| `PermissionMode.acceptEdits` | Auto-allows file operations |
| `PermissionMode.bypassPermissions` | Allows everything (dangerous) |
| `PermissionMode.plan` | Planning only, no execution |

---

## Common Patterns

### Wait for Completion

```dart
final completer = Completer<String>();
session.messages.listen((msg) {
  if (msg is SDKResultMessage) {
    completer.complete(msg.result ?? '');
  }
});
final result = await completer.future;
```

### Auto-Approve Safe Tools

```dart
session.permissionRequests.listen((req) {
  const safeTool = ['Read', 'Glob', 'Grep'];
  if (safeTools.contains(req.toolName)) {
    req.allow();
  } else {
    req.deny('Not allowed');
  }
});
```

### Send Image

```dart
await session.sendWithContent([
  TextBlock(text: 'Describe this:'),
  ImageBlock(source: ImageSource(
    type: 'base64',
    mediaType: 'image/png',
    data: base64Data,
  )),
]);
```

---

## Detailed Documentation

| Topic | Document |
|-------|----------|
| Setup & Installation | [GETTING_STARTED.md](GETTING_STARTED.md) |
| Full API Reference | [API_REFERENCE.md](API_REFERENCE.md) |
| CLI Protocol Details | [PROTOCOL.md](PROTOCOL.md) |
| Code Examples | [EXAMPLES.md](EXAMPLES.md) |

---

## File Locations

```
claude_dart_sdk/
├── lib/
│   ├── claude_sdk.dart           # Main export - import this
│   └── src/
│       ├── backend_factory.dart  # BackendFactory
│       ├── backend_interface.dart # AgentBackend, AgentSession
│       ├── cli_backend.dart      # CLI backend implementation
│       ├── cli_session.dart      # Session implementation
│       ├── cli_process.dart      # CLI process management
│       └── types/
│           ├── sdk_messages.dart # Message types
│           ├── callbacks.dart    # Permission types
│           └── session_options.dart # Options
```

---

## Protocol Quick Reference

### Initialize

```json
→ {"type":"control_request","request_id":"...","request":{"subtype":"initialize",...}}
← {"type":"control_response","response":{"subtype":"success",...}}
→ {"type":"user","message":{"role":"user","content":"prompt"}}
← {"type":"system","subtype":"init","session_id":"...","tools":[...],...}
```

### Messages

```json
← {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
← {"type":"result","total_cost_usd":0.01,"num_turns":2}
```

### Permissions

```json
← {"type":"callback.request","id":"cb1","payload":{"callback_type":"can_use_tool","tool_name":"Bash",...}}
→ {"type":"callback.response","id":"cb1","payload":{"behavior":"allow",...}}
```

---

## Error Handling

```dart
try {
  final session = await backend.createSession(...);
} on BackendProcessError catch (e) {
  // CLI process failed
} on SessionCreateError catch (e) {
  // Session creation failed
} on BackendError catch (e) {
  // General backend error
}
```

---

## Tips

1. **Always dispose**: Call `backend.dispose()` to clean up
2. **Handle permissions**: Unhandled requests timeout after 60s
3. **Check message types**: Use pattern matching for type safety
4. **Track costs**: Use `SDKResultMessage.totalCostUsd`
5. **Use acceptEdits**: For file-heavy workflows to reduce prompts
