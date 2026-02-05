# Mock Backend for Integration Testing

## Overview

This document outlines the plan for implementing a **command-driven mock backend** that allows integration tests to programmatically control SDK behavior without making real API calls.

## Current Architecture

```
Flutter App
    ↓ (Provider)
SessionProvider
    ↓
AgentSession (Dart SDK)
    ↓ (stdout/stdin - JSON lines)
Claude CLI Process
    ↓
Claude API
```

### Existing Mock Infrastructure

The project already has a mock infrastructure in `flutter_app/test/integration/mocks/`:

| File | Purpose |
|------|---------|
| `mock_backend.dart` | `MockAgentBackend` - creates mock sessions without subprocess |
| `mock_session.dart` | `MockAgentSession` - simulates SDK message streams |
| `mock_protocol.dart` | `MockProtocol` - factory helpers for creating SDK messages |

**Current Usage**: Tests programmatically call methods like:
```dart
mockSession.sendTextContent('Hello!');
mockSession.sendPermissionRequest(requestId: 'req-1', toolName: 'Write', ...);
```

## Problem Statement

The existing mock infrastructure works for **unit/widget tests** where test code directly controls the mock. However, for **integration tests** that run against the real app, we need a way to:

1. Send commands through the normal message flow (user input)
2. Trigger specific SDK behaviors (tool invocations, permission requests, compaction events)
3. Simulate complex scenarios (multi-turn conversations, subagents, error conditions)

## Proposed Solution: Command-Driven Mock Mode

### Approach: Extend MockAgentSession with Command Protocol

Add a **command interpreter** to `MockAgentSession` that intercepts messages sent via `send()` and executes mock commands instead of forwarding them.

### Command Protocol

Commands are JSON objects with a `__mock__` wrapper:

```json
{
  "__mock__": {
    "command": "tool_permission_request",
    "params": {
      "tool_name": "Write",
      "tool_input": {"file_path": "/tmp/test.txt", "content": "Hello"},
      "suggestions": ["Bash(git *)"]
    }
  }
}
```

### Supported Commands

#### 1. SDK Message Simulation

| Command | Description | Parameters |
|---------|-------------|------------|
| `text_response` | Send assistant text | `text`, `agent_id?` |
| `thinking_response` | Send thinking block | `thinking`, `agent_id?` |
| `tool_use` | Send tool invocation | `tool_name`, `tool_input`, `tool_use_id?`, `agent_id?` |
| `tool_result` | Send tool result | `tool_use_id`, `result?`, `error?` |
| `result` | End turn with result | `duration_ms?`, `cost?`, `is_error?` |
| `stream_delta` | Send text delta | `text`, `agent_id?` |
| `error` | Send error message | `message`, `code?` |

#### 2. Permission/Callback Simulation

| Command | Description | Parameters |
|---------|-------------|------------|
| `permission_request` | Request tool permission | `tool_name`, `tool_input`, `suggestions?`, `agent_id?` |
| `ask_user_question` | Send AskUserQuestion | `questions` (array of question objects) |
| `hook_request` | Send hook callback | `event`, `input`, `tool_use_id?` |

#### 3. System Events

| Command | Description | Parameters |
|---------|-------------|------------|
| `system_init` | Send init message | `cwd?`, `model?`, `permission_mode?`, `tools?` |
| `system_status` | Send status update | `status` (e.g., "compacting") |
| `compact_boundary` | Send compaction event | `trigger` ("manual"|"auto"), `pre_tokens?` |

#### 4. Complex Scenarios

| Command | Description | Parameters |
|---------|-------------|------------|
| `scenario` | Run predefined scenario | `name` (e.g., "simple_conversation", "tool_with_permission") |
| `sequence` | Run multiple commands | `commands` (array of command objects) |
| `delay` | Wait before next command | `ms` |

### Implementation Plan

#### Phase 1: Extend MockAgentSession (Core)

**File**: `flutter_app/test/integration/mocks/mock_session.dart`

1. Add command parsing in `send()` method
2. Implement command dispatch to existing simulation methods
3. Add new simulation methods for missing functionality:
   - `sendSystemInit()`
   - `sendSystemStatus()`
   - `sendCompactBoundary()`
   - `sendStreamDelta()`
   - `sendHookRequest()`

```dart
@override
Future<void> send(String message) async {
  if (_disposed) throw StateError('Session disposed');

  // Check for mock command
  final decoded = _tryParseJson(message);
  if (decoded != null && decoded['__mock__'] != null) {
    await _executeCommand(decoded['__mock__'] as Map<String, dynamic>);
    return;
  }

  // Normal message handling
  _sentMessages.add(message);
}

Future<void> _executeCommand(Map<String, dynamic> command) async {
  final cmd = command['command'] as String;
  final params = command['params'] as Map<String, dynamic>? ?? {};

  switch (cmd) {
    case 'text_response':
      sendTextContent(params['text'] as String, agentId: params['agent_id']);
      break;
    case 'permission_request':
      sendPermissionRequest(
        requestId: 'req-${DateTime.now().millisecondsSinceEpoch}',
        toolName: params['tool_name'] as String,
        toolInput: params['tool_input'] as Map<String, dynamic>,
        suggestions: (params['suggestions'] as List?)?.cast<String>(),
      );
      break;
    // ... other commands
  }
}
```

#### Phase 2: Add Missing Simulation Methods

Extend `MockAgentSession` with:

```dart
/// Send system init message
void sendSystemInit({
  String? cwd,
  String? model,
  String? permissionMode,
  List<String>? tools,
}) {
  _messagesController.add(SDKSystemMessage(
    subtype: 'init',
    uuid: _nextId(),
    sessionId: sessionId,
    cwd: cwd,
    model: model,
    permissionMode: permissionMode,
    tools: tools,
  ));
}

/// Send system status (e.g., compacting)
void sendSystemStatus(String status) {
  _messagesController.add(SDKSystemMessage(
    subtype: 'status',
    uuid: _nextId(),
    sessionId: sessionId,
    status: status,
  ));
}

/// Send compact boundary event
void sendCompactBoundary({
  String trigger = 'auto',
  int preTokens = 0,
}) {
  _messagesController.add(SDKSystemMessage(
    subtype: 'compact_boundary',
    uuid: _nextId(),
    sessionId: sessionId,
    compactMetadata: CompactMetadata(
      trigger: trigger,
      preTokens: preTokens,
    ),
  ));
}

/// Send stream delta event
void sendStreamDelta(String text, {String? agentId}) {
  _messagesController.add(SDKStreamEvent(
    uuid: _nextId(),
    sessionId: sessionId,
    event: {
      'type': 'content_block_delta',
      'delta': {'type': 'text_delta', 'text': text},
    },
    parentToolUseId: agentId,
  ));
}

/// Send hook request
void sendHookRequest({
  required String requestId,
  required String event,
  required dynamic input,
  String? toolUseId,
}) {
  final completer = Completer<HookResponse>();
  _hooksController.add(HookRequest(
    id: requestId,
    sessionId: sessionId,
    event: event,
    input: input,
    toolUseId: toolUseId,
    completer: completer,
  ));
}
```

#### Phase 3: Add Scenario Support

Create predefined scenarios for common test patterns:

```dart
/// Execute a predefined scenario
Future<void> executeScenario(String name) async {
  switch (name) {
    case 'simple_conversation':
      sendTextContent('I understand your request. Let me help you with that.');
      await Future.delayed(Duration(milliseconds: 100));
      sendResult();
      break;

    case 'tool_with_permission':
      sendTextContent('I need to read a file to help you.');
      sendToolUse(
        toolName: 'Read',
        toolUseId: 'tool-1',
        input: {'file_path': '/tmp/test.txt'},
      );
      sendPermissionRequest(
        requestId: 'req-1',
        toolName: 'Read',
        toolInput: {'file_path': '/tmp/test.txt'},
      );
      // Wait for permission response before continuing
      break;

    case 'compaction_event':
      sendSystemStatus('compacting');
      await Future.delayed(Duration(milliseconds: 500));
      sendCompactBoundary(trigger: 'auto', preTokens: 150000);
      break;

    case 'subagent_task':
      // Simulate Task tool creating a subagent
      sendTextContent('Let me use a specialized agent for this.');
      sendToolUse(
        toolName: 'Task',
        toolUseId: 'task-1',
        input: {
          'description': 'Search codebase',
          'prompt': 'Find all TODO comments',
          'subagent_type': 'Explore',
        },
      );
      // Subagent messages would have agentId: 'task-1'
      break;
  }
}
```

#### Phase 4: Integration Test Helpers

Add helpers to make writing tests easier:

**File**: `flutter_app/test/integration/test_helpers.dart`

```dart
extension MockSessionTestHelpers on MockAgentSession {
  /// Send a mock command via the normal message flow
  Future<void> executeCommand(Map<String, dynamic> command) async {
    await send(jsonEncode({'__mock__': command}));
  }

  /// Convenience: Request permission with suggestions
  Future<void> requestPermissionWithSuggestions({
    required String toolName,
    required Map<String, dynamic> toolInput,
    required List<String> suggestions,
  }) async {
    await executeCommand({
      'command': 'permission_request',
      'params': {
        'tool_name': toolName,
        'tool_input': toolInput,
        'suggestions': suggestions,
      },
    });
  }
}
```

### Example Test Usage

```dart
testWidgets('handles permission request with suggestions', (tester) async {
  final mockBackend = MockAgentBackend();
  await tester.pumpWidget(createTestApp(mockBackend));

  // Create session through normal UI flow
  await tester.enterText(find.byType(TextField), 'Read /tmp/test.txt');
  await tester.tap(find.byKey(Key('submit_button')));
  await tester.pumpAndSettle();

  final mockSession = mockBackend.latestSession!;

  // Trigger permission request via mock command
  await mockSession.executeCommand({
    'command': 'permission_request',
    'params': {
      'tool_name': 'Read',
      'tool_input': {'file_path': '/tmp/test.txt'},
      'suggestions': ['Read(/tmp/*)', 'Read(**/*.txt)'],
    },
  });
  await tester.pumpAndSettle();

  // Verify permission dialog appears with suggestions
  expect(find.text('Permission Request'), findsOneWidget);
  expect(find.text('Read'), findsOneWidget);
  expect(find.textContaining('suggestions'), findsOneWidget);

  // Approve with suggestion
  await tester.tap(find.text('Allow'));
  await tester.pumpAndSettle();

  // Verify response was correct
  expect(mockSession.permissionResponses, isNotEmpty);
});

testWidgets('handles compaction event', (tester) async {
  final mockBackend = MockAgentBackend();
  await tester.pumpWidget(createTestApp(mockBackend));

  // ... setup session ...

  final mockSession = mockBackend.latestSession!;

  // Trigger compaction via mock command
  await mockSession.executeCommand({
    'command': 'sequence',
    'params': {
      'commands': [
        {'command': 'system_status', 'params': {'status': 'compacting'}},
        {'command': 'delay', 'params': {'ms': 100}},
        {'command': 'compact_boundary', 'params': {'trigger': 'auto', 'pre_tokens': 150000}},
      ],
    },
  });
  await tester.pumpAndSettle();

  // Verify compaction indicator appeared
  expect(find.textContaining('Compacting'), findsOneWidget);
});
```

## Alternative Approaches Considered

### 1. Separate Mock Backend Process

**Approach**: Create a separate mock backend process that understands mock commands.

**Pros**:
- Tests the full communication stack
- Could be used for manual testing too

**Cons**:
- More complex to maintain two backends
- Slower test execution (subprocess overhead)
- Already have Dart-level mocking that works well

**Decision**: Not recommended. The Dart SDK mock approach is simpler and sufficient.

### 2. Mock at Protocol Level

**Approach**: Create a `MockProtocol` that intercepts all stdin/stdout.

**Pros**:
- Tests more of the real code path

**Cons**:
- More complex to implement
- Still need to generate mock messages somehow
- The current `MockAgentSession` already handles this layer

**Decision**: Not recommended. `MockAgentSession` provides the right abstraction.

### 3. HTTP Interception (for real API mocking)

**Approach**: Use a tool like `nock` or `msw` to mock HTTP requests to Claude API.

**Pros**:
- Tests the entire real backend
- Most realistic testing

**Cons**:
- Very complex to maintain
- Brittle (depends on API contract details)
- Slow execution
- Not needed for frontend testing

**Decision**: Not recommended for this use case. Better suited for SDK testing itself.

## Implementation Summary

| Phase | Effort | Deliverable |
|-------|--------|-------------|
| Phase 1 | Low | Command parsing in `MockAgentSession.send()` |
| Phase 2 | Medium | Missing simulation methods (system, stream, hook) |
| Phase 3 | Medium | Predefined scenarios for common patterns |
| Phase 4 | Low | Test helper extensions |

**Recommended approach**: Implement Phases 1-4 as they build on each other and provide comprehensive testing capability with minimal changes to existing code.

## Files to Modify

1. `flutter_app/test/integration/mocks/mock_session.dart`
   - Add command parsing in `send()`
   - Add new simulation methods
   - Add scenario execution

2. `flutter_app/test/integration/mocks/mock_protocol.dart`
   - Add command builder helpers

3. `flutter_app/test/integration/test_helpers.dart`
   - Add convenience extensions for mock commands

## Testing the Mock Infrastructure

Create tests for the mock infrastructure itself:

```dart
// test/integration/mocks/mock_session_test.dart
void main() {
  test('executes text_response command', () async {
    final session = MockAgentSession(...);
    final messages = <SDKMessage>[];
    session.messages.listen(messages.add);

    await session.send(jsonEncode({
      '__mock__': {
        'command': 'text_response',
        'params': {'text': 'Hello!'},
      },
    }));

    expect(messages.length, 1);
    expect((messages[0] as SDKAssistantMessage).message.content[0], isA<TextBlock>());
  });
}
```
