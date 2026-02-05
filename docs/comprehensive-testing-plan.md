# Comprehensive Testing Plan - Focus Management

## Overview

This document outlines the testing strategy for validating the app's sophisticated focus management system, particularly around user input handling and the AskUserQuestion feature.

### The Focus Management Problem

The app had significant challenges ensuring proper focus behavior:

1. **MessageInput Focus Persistence**: After starting the UI and connecting to a session, the MessageInput normally has focus. However, if the user clicks outside (e.g., on the session list), it loses focus. The challenge was ensuring that even after losing focus, typing anywhere in the window would automatically refocus and send input to the MessageInput.

2. **AskUserQuestion Focus Priority**: When Claude uses the AskUserQuestion tool, a question box appears and must take focus priority. If the user clicks anywhere else in the window and then starts typing, the input must go back to the question box (not the MessageInput).

### Current Implementation

The focus management system works as follows:

- **HomeScreen** (`lib/screens/home_screen.dart`) contains a `KeyboardListener` with a `FocusNode` that listens for keyboard events
- The listener detects typing keys (alphanumeric, symbols) using `_isTypingKey()`
- When typing is detected, it checks if `_desiredFocusNode` has focus; if not, it requests focus
- **InputPanel** and **AskUserQuestionWidget** register their focus nodes via the `onFocusChange` callback
- This callback sets `_desiredFocusNode` in HomeScreen's state
- **MessageInput** (`lib/widgets/message_input.dart`) has public `requestFocus()` method and exposes its `FocusNode` via the callback
- **AskUserQuestionWidget** appears when `agent.pendingPermissionRequest.toolName == 'AskUserQuestion'`
- MessageInput's `autofocus` is disabled when a question is pending (line 97 in input_panel.dart)

## Test Structure

```
flutter_app/test/
├── integration/
│   ├── mocks/
│   │   ├── mock_backend.dart           # MockAgentBackend
│   │   ├── mock_session.dart           # MockAgentSession
│   │   └── mock_protocol.dart          # Helper for SDK message creation
│   ├── focus_management_test.dart      # MessageInput focus behavior tests
│   ├── ask_user_question_test.dart     # AskUserQuestion focus tests
│   └── test_helpers.dart               # Shared test utilities
└── widget/
    ├── message_input_test.dart         # Unit test for MessageInput widget
    └── input_panel_test.dart           # Unit test for InputPanel widget
```

## Test Cases

### Test 1: MessageInput Focus Persistence

**File**: `integration/focus_management_test.dart`

**Scenario**: Normal session operation where MessageInput should capture all typing

**Steps**:
1. Start app with mock backend
2. Create a session (triggers MessageInput to be rendered)
3. Wait for MessageInput to appear
4. Verify MessageInput has focus initially (autofocus = true when no question pending)
5. Tap outside MessageInput (e.g., on the session list or empty area)
6. Wait for focus to move away from MessageInput
7. Verify MessageInput no longer has focus
8. Simulate pressing a typing key (e.g., 'h')
9. Wait for focus redirection
10. Verify focus automatically returned to MessageInput
11. Verify the character 'h' appears in the MessageInput text field

**Expected Behavior**: Typing anywhere in the window sends input to MessageInput after it loses focus

**Key Assertions**:
- `expect(find.byType(MessageInput), findsOneWidget)`
- `expect(messageInput.focusNode.hasFocus, isTrue)` (initial)
- `expect(messageInput.focusNode.hasFocus, isFalse)` (after tap outside)
- `expect(messageInput.focusNode.hasFocus, isTrue)` (after typing key)
- `expect(controller.text, equals('h'))`

---

### Test 2: AskUserQuestion Focus Priority

**File**: `integration/ask_user_question_test.dart`

**Scenario**: When AskUserQuestion appears, it should take focus priority over MessageInput

**Steps**:
1. Start session with mock backend
2. Verify MessageInput initially has focus
3. Mock backend sends AskUserQuestion permission request:
   ```dart
   mockSession.sendPermissionRequest(PermissionRequest(
     id: 'req-1',
     toolName: 'AskUserQuestion',
     toolInput: {
       'questions': [
         {
           'question': 'Which option do you prefer?',
           'header': 'Choice',
           'options': [
             {'label': 'Option A', 'description': 'First option'},
             {'label': 'Option B', 'description': 'Second option'},
           ],
           'multiSelect': false,
         }
       ]
     },
   ));
   ```
4. Wait for AskUserQuestionWidget to appear in output panel
5. Verify the question input field exists
6. Verify question input field has focus (not MessageInput)
7. Verify MessageInput autofocus is disabled (line 97: `autofocus: !hasPendingQuestion`)
8. Tap outside the question widget (e.g., on session list)
9. Wait for focus to move
10. Press a typing key (e.g., 'a')
11. Wait for focus redirection
12. Verify focus returned to the question input field (not MessageInput)
13. Verify the character 'a' appears in the question input (not MessageInput)

**Expected Behavior**: When AskUserQuestion is active, all typing goes to the question input field

**Key Assertions**:
- `expect(find.byType(_AskUserQuestionWidget), findsOneWidget)`
- `expect(questionInputFocusNode.hasFocus, isTrue)` (after question appears)
- `expect(messageInputFocusNode.hasFocus, isFalse)` (question takes priority)
- `expect(questionInputFocusNode.hasFocus, isTrue)` (after typing outside)
- Question input contains typed character, MessageInput does not

---

### Test 3: Focus Returns to MessageInput After Question Answered

**File**: `integration/ask_user_question_test.dart`

**Scenario**: After answering a question, focus should return to MessageInput

**Steps**:
1. Start with AskUserQuestion displayed and focused (continuation of Test 2)
2. Select an answer option (simulate tap on option button)
3. Tap the "Submit" button
4. Mock backend responds with permission approval
5. Wait for AskUserQuestionWidget to disappear
6. Wait for UI to settle
7. Verify MessageInput is visible
8. Verify MessageInput has autofocus enabled again
9. Verify MessageInput has focus
10. Type a character (e.g., 'm')
11. Verify it appears in MessageInput field

**Expected Behavior**: After question is answered, normal MessageInput focus behavior resumes

**Key Assertions**:
- `expect(find.byType(_AskUserQuestionWidget), findsNothing)` (question gone)
- `expect(find.byType(MessageInput), findsOneWidget)`
- `expect(messageInputFocusNode.hasFocus, isTrue)`
- `expect(messageInputController.text, contains('m'))`

---

### Test 4: Multiple Sequential Questions

**File**: `integration/ask_user_question_test.dart`

**Scenario**: Focus management works correctly with multiple sequential questions

**Steps**:
1. Create session
2. Mock backend sends first AskUserQuestion
3. Verify first question has focus
4. Answer first question
5. Wait for first question to disappear
6. Mock backend sends second AskUserQuestion (different question)
7. Wait for second question to appear
8. Verify second question input has focus (not MessageInput)
9. Tap outside
10. Type a character
11. Verify character goes to second question input
12. Answer second question
13. Wait for second question to disappear
14. Verify MessageInput has focus

**Expected Behavior**: Focus correctly transfers between questions and back to MessageInput

**Key Assertions**:
- Each question gets focus when it appears
- Typing always goes to active question
- MessageInput only regains focus after all questions answered

---

## Mock Architecture

### Mock Backend (`integration/mocks/mock_backend.dart`)

```dart
import 'package:claude_sdk/claude_sdk.dart';
import 'dart:async';

/// Mock implementation of AgentBackend for testing
class MockAgentBackend implements AgentBackend {
  final StreamController<BackendError> _errorsController =
      StreamController<BackendError>.broadcast();
  final StreamController<String> _logsController =
      StreamController<String>.broadcast();

  final List<MockAgentSession> _sessions = [];
  bool _disposed = false;

  @override
  Stream<BackendError> get errors => _errorsController.stream;

  @override
  Stream<String> get logs => _logsController.stream;

  @override
  String? get logFilePath => '/tmp/test-backend.log';

  @override
  bool get isRunning => !_disposed;

  /// Create a mock session with controllable behavior
  @override
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
  }) async {
    final session = MockAgentSession(
      sessionId: 'session-${_sessions.length + 1}',
      sdkSessionId: 'sdk-${_sessions.length + 1}',
      prompt: prompt,
      cwd: cwd,
    );

    _sessions.add(session);
    return session;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final session in _sessions) {
      await session.dispose();
    }
    _sessions.clear();

    await _errorsController.close();
    await _logsController.close();
  }

  // Test control methods

  /// Simulate an error from the backend
  void simulateError(BackendError error) {
    _errorsController.add(error);
  }

  /// Simulate a log message from the backend
  void simulateLog(String log) {
    _logsController.add(log);
  }

  /// Get a created session by index for test control
  MockAgentSession? getSession(int index) {
    if (index < 0 || index >= _sessions.length) return null;
    return _sessions[index];
  }

  /// Get the most recently created session
  MockAgentSession? get latestSession =>
      _sessions.isEmpty ? null : _sessions.last;
}
```

### Mock Session (`integration/mocks/mock_session.dart`)

```dart
import 'package:claude_sdk/claude_sdk.dart';
import 'dart:async';

/// Mock implementation of AgentSession for testing
class MockAgentSession implements AgentSession {
  @override
  final String sessionId;

  @override
  final String sdkSessionId;

  final String prompt;
  final String cwd;

  final StreamController<SDKMessage> _messagesController =
      StreamController<SDKMessage>.broadcast();
  final StreamController<PermissionRequest> _permissionsController =
      StreamController<PermissionRequest>.broadcast();
  final StreamController<HookRequest> _hooksController =
      StreamController<HookRequest>.broadcast();

  bool _disposed = false;
  final List<String> _sentMessages = [];
  final List<String> _permissionResponses = [];

  MockAgentSession({
    required this.sessionId,
    required this.sdkSessionId,
    required this.prompt,
    required this.cwd,
  });

  @override
  Stream<SDKMessage> get messages => _messagesController.stream;

  @override
  Stream<PermissionRequest> get permissionRequests =>
      _permissionsController.stream;

  @override
  Stream<HookRequest> get hookRequests => _hooksController.stream;

  @override
  Future<void> send(String message) async {
    if (_disposed) throw StateError('Session disposed');
    _sentMessages.add(message);
  }

  @override
  Future<void> interrupt() async {
    if (_disposed) throw StateError('Session disposed');
    // Simulate interrupt
  }

  @override
  Future<void> kill() async {
    await dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _messagesController.close();
    await _permissionsController.close();
    await _hooksController.close();
  }

  // Test control methods

  /// Send a text content message to the session
  void sendTextContent(String text, {String agentId = 'main'}) {
    _messagesController.add(SDKTextMessage(
      text: text,
      sessionId: sessionId,
      agentId: agentId,
    ));
  }

  /// Send a thinking content message
  void sendThinkingContent(String thinking, {String agentId = 'main'}) {
    _messagesController.add(SDKThinkingMessage(
      thinking: thinking,
      sessionId: sessionId,
      agentId: agentId,
    ));
  }

  /// Send a tool use message
  void sendToolUse({
    required String toolName,
    required String toolUseId,
    required Map<String, dynamic> input,
    String agentId = 'main',
  }) {
    _messagesController.add(SDKToolUseMessage(
      toolName: toolName,
      toolUseId: toolUseId,
      input: input,
      sessionId: sessionId,
      agentId: agentId,
    ));
  }

  /// Send a tool result message
  void sendToolResult({
    required String toolUseId,
    String? result,
    String? error,
    String agentId = 'main',
  }) {
    _messagesController.add(SDKToolResultMessage(
      toolUseId: toolUseId,
      result: result,
      error: error,
      sessionId: sessionId,
      agentId: agentId,
    ));
  }

  /// Send an AskUserQuestion as a permission request
  void sendAskUserQuestion({
    required String requestId,
    required List<Map<String, dynamic>> questions,
    String agentId = 'main',
  }) {
    _permissionsController.add(PermissionRequest(
      id: requestId,
      toolName: 'AskUserQuestion',
      toolInput: {'questions': questions},
      agentId: agentId,
    ));
  }

  /// Send a generic permission request (e.g., for Write, Edit, etc.)
  void sendPermissionRequest({
    required String requestId,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String agentId = 'main',
    List<String>? suggestions,
  }) {
    _permissionsController.add(PermissionRequest(
      id: requestId,
      toolName: toolName,
      toolInput: toolInput,
      agentId: agentId,
      suggestions: suggestions,
    ));
  }

  /// Approve a permission request (simulates user approval)
  void approvePermission(String requestId) {
    _permissionResponses.add('approve:$requestId');
  }

  /// Get all messages sent by the app to this session
  List<String> get sentMessages => List.unmodifiable(_sentMessages);

  /// Check if a specific message was sent
  bool hasSentMessage(String message) => _sentMessages.contains(message);

  /// Clear sent messages history (for multi-step tests)
  void clearSentMessages() => _sentMessages.clear();
}
```

### Test Helpers (`integration/test_helpers.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_app/main.dart';
import 'package:flutter_app/providers/session_provider.dart';
import 'package:flutter_app/services/backend_service.dart';
import 'package:flutter_app/screens/home_screen.dart';
import 'mocks/mock_backend.dart';

class TestHelpers {
  /// Create a test app with mock backend
  static Widget createTestApp(MockAgentBackend mockBackend) {
    final backendService = BackendService();
    // Inject mock backend (requires modifying BackendService to accept mock)
    // Or wrap BackendService entirely

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: backendService),
        ChangeNotifierProxyProvider<BackendService, SessionProvider>(
          create: (context) => SessionProvider(backendService),
          update: (context, backend, previous) =>
              previous ?? SessionProvider(backend),
        ),
      ],
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }

  /// Simulate typing a single character
  static Future<void> typeCharacter(
    WidgetTester tester,
    String char,
  ) async {
    assert(char.length == 1, 'Must be a single character');

    final keyCode = char.codeUnitAt(0);
    await tester.sendKeyEvent(LogicalKeyboardKey.findKeyByKeyId(keyCode));
    await tester.pump();
  }

  /// Simulate typing a full string
  static Future<void> typeText(WidgetTester tester, String text) async {
    for (int i = 0; i < text.length; i++) {
      await typeCharacter(tester, text[i]);
    }
  }

  /// Tap outside a specific widget (tap on empty space)
  static Future<void> tapOutside(WidgetTester tester) async {
    // Find an area that's safe to tap (top-left corner usually works)
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
  }

  /// Find the MessageInput widget
  static Finder findMessageInput() {
    return find.byType(MessageInput);
  }

  /// Get the FocusNode from MessageInput
  static FocusNode? getMessageInputFocus(WidgetTester tester) {
    final widget = tester.widget<TextField>(
      find.descendant(
        of: findMessageInput(),
        matching: find.byType(TextField),
      ),
    );
    return widget.focusNode;
  }

  /// Get the TextEditingController from MessageInput
  static TextEditingController? getMessageInputController(
    WidgetTester tester,
  ) {
    final widget = tester.widget<TextField>(
      find.descendant(
        of: findMessageInput(),
        matching: find.byType(TextField),
      ),
    );
    return widget.controller;
  }

  /// Find AskUserQuestion widget
  static Finder findAskUserQuestion() {
    return find.byType(_AskUserQuestionWidget);
  }

  /// Wait for a widget to appear
  static Future<void> waitForWidget(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      await tester.pumpAndSettle();
      if (tester.any(finder)) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    throw TimeoutException('Widget not found within timeout');
  }

  /// Wait for a widget to disappear
  static Future<void> waitForWidgetToDisappear(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      await tester.pumpAndSettle();
      if (!tester.any(finder)) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    throw TimeoutException('Widget did not disappear within timeout');
  }

  /// Create a session with the mock backend
  static Future<void> createMockSession(
    WidgetTester tester, {
    String prompt = 'Test prompt',
    String cwd = '/tmp/test',
  }) async {
    final provider = tester.read<SessionProvider>();
    await provider.createSession(
      prompt: prompt,
      cwd: cwd,
      model: 'haiku',
    );
    await tester.pumpAndSettle();
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
```

## Implementation Plan with Subagents

To parallelize the work, we'll use 4 specialized agents:

### Agent 1: Mock Infrastructure
**Responsibility**: Create reusable mock infrastructure

**Tasks**:
1. Create `flutter_app/test/integration/mocks/mock_backend.dart`
   - Implement `MockAgentBackend` class
   - Include test control methods
   - Add comprehensive documentation

2. Create `flutter_app/test/integration/mocks/mock_session.dart`
   - Implement `MockAgentSession` class
   - Include methods for sending all SDK message types
   - Add test control methods

3. Create `flutter_app/test/integration/mocks/mock_protocol.dart`
   - Helper functions for creating SDK messages
   - Factory methods for common scenarios

4. Create `flutter_app/test/integration/test_helpers.dart`
   - Implement all helper functions from the design above
   - Add widget finders
   - Add keyboard simulation utilities

**Deliverables**: Complete, tested mock infrastructure ready for use by other agents

---

### Agent 2: MessageInput Focus Tests
**Responsibility**: Implement tests for MessageInput focus behavior

**Tasks**:
1. Create `flutter_app/test/integration/focus_management_test.dart`

2. Implement Test 1: MessageInput Focus Persistence
   - Test that initial focus is on MessageInput
   - Test focus loss when clicking outside
   - Test automatic refocus when typing

3. Implement Test 3: Focus Returns After Question
   - Test that MessageInput regains focus after question answered
   - Test that typing goes to MessageInput after question flow

4. Add helper methods specific to focus testing

**Dependencies**: Agent 1 (mock infrastructure)

**Deliverables**: Fully functional tests for MessageInput focus behavior

---

### Agent 3: AskUserQuestion Tests
**Responsibility**: Implement tests for AskUserQuestion focus behavior

**Tasks**:
1. Create `flutter_app/test/integration/ask_user_question_test.dart`

2. Implement Test 2: AskUserQuestion Focus Priority
   - Test that question appears when permission request sent
   - Test that question input gets focus (not MessageInput)
   - Test that typing goes to question after clicking outside

3. Implement Test 4: Multiple Sequential Questions
   - Test focus transfer between multiple questions
   - Test focus returns to MessageInput after all questions

4. Add helper methods for question interaction

**Dependencies**: Agent 1 (mock infrastructure)

**Deliverables**: Fully functional tests for AskUserQuestion focus behavior

---

### Agent 4: Widget Unit Tests
**Responsibility**: Create unit tests for individual widgets

**Tasks**:
1. Create `flutter_app/test/widget/message_input_test.dart`
   - Test `requestFocus()` method
   - Test `onFocusChange` callback fires correctly
   - Test keyboard event handling
   - Test Enter key submission

2. Create `flutter_app/test/widget/input_panel_test.dart`
   - Test focus registration with session
   - Test autofocus behavior based on pending questions
   - Test submit button functionality

3. Add widget-specific test helpers

**Dependencies**: None (unit tests don't need mocks)

**Deliverables**: Comprehensive unit tests for MessageInput and InputPanel widgets

---

## Key Testing Challenges

### 1. Focus Timing
**Challenge**: Focus changes are asynchronous and may take multiple frames

**Solution**:
- Use `tester.pumpAndSettle()` extensively
- Add explicit waits with `waitForWidget()` helper
- Use `WidgetsBinding.instance.addPostFrameCallback()` when needed

### 2. Keyboard Event Simulation
**Challenge**: Simulating realistic keyboard events in tests

**Solution**:
- Use `tester.sendKeyEvent()` for individual keys
- Create `typeCharacter()` and `typeText()` helpers
- Test both KeyDown and KeyUp events where relevant

### 3. Stream Subscriptions
**Challenge**: Mock streams must be properly managed and disposed

**Solution**:
- Use `StreamController.broadcast()` for multiple listeners
- Ensure all controllers are closed in `dispose()`
- Track subscriptions in tests and clean up in `tearDown()`

### 4. Widget Lifecycle
**Challenge**: AskUserQuestion widget mounts/unmounts based on state

**Solution**:
- Use `waitForWidget()` and `waitForWidgetToDisappear()` helpers
- Test widget presence before accessing state
- Handle race conditions with proper async/await

### 5. Provider State Management
**Challenge**: Tests need access to SessionProvider and BackendService

**Solution**:
- Create test app with `MultiProvider` wrapping
- Use `WidgetTester.read<T>()` extension to access providers
- Consider creating a `TestBackendService` that accepts mock backend

### 6. Finding Private Widgets
**Challenge**: `_AskUserQuestionWidget` is private (underscore prefix)

**Solution**:
- Use `find.byType()` with the private type (works in same library)
- Or use `find.byWidgetPredicate()` to find by properties
- Or find by descendant widgets (e.g., question text)

## Expected Outcomes

After implementing this testing plan, we will have:

✅ **Comprehensive test coverage** of the critical focus management system

✅ **Reusable mock infrastructure** that can be used for future tests:
- Permission request tests
- ToolUse display tests
- Session lifecycle tests
- Error handling tests

✅ **Fast-running tests** with no real backend dependency (no network, no SDK overhead)

✅ **High confidence** in focus regression prevention - changes to focus code will immediately show test failures

✅ **Documentation through tests** - new developers can read tests to understand how focus management works

✅ **Foundation for integration testing** - the mock architecture can be extended for end-to-end user flows

## Future Test Extensions

This mock infrastructure can be extended to test:

1. **Permission Request UI**
   - Write permission shows file path and content preview
   - Approve/deny buttons work correctly
   - Multiple permission requests queued properly

2. **Tool Use Display**
   - Tool use boxes render correctly
   - Collapsible sections work
   - Input/output formatting is correct

3. **Session Lifecycle**
   - Creating sessions
   - Stopping/interrupting sessions
   - Session state transitions
   - Error handling

4. **Agent Hierarchy**
   - Subagent spawning visualization
   - Agent selection
   - Agent output routing

5. **Cost Tracking**
   - Token usage updates
   - Cost calculations
   - Usage display in UI

## Notes for Implementation

1. **BackendService Mock Integration**: The current `BackendService` spawns a real backend. For testing, we need either:
   - A constructor parameter to inject a mock backend
   - A separate `TestBackendService` class
   - Use of dependency injection pattern

2. **Private Widget Testing**: Consider making `_AskUserQuestionWidget` public for testing, or use `@visibleForTesting` annotation.

3. **Test Organization**: Keep integration tests in `test/integration/` and unit tests in `test/widget/` for clear separation.

4. **CI/CD Integration**: These tests should run on every PR to catch focus regressions early.

5. **Test Performance**: Mock-based tests should run in <5 seconds total. If slower, optimize pumping/settling logic.
