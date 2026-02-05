# SDK Wiring Plan - CC-Insights V2

## Overview

This plan covers wiring up the Claude SDK so users can send messages and receive replies. The Dart SDK and Node.js backend are **already fully implemented** - this is purely a wiring/integration task.

## Current State

### What's Ready
- **Dart SDK** (`claude_dart_sdk/`): Complete API for spawning backend, creating sessions, sending messages, receiving streams
- **Node.js Backend** (`backend-node/`): Complete session management, message routing, permission callbacks
- **SdkMessageHandler** (`lib/services/sdk_message_handler.dart`): Parses SDK messages and routes to correct conversation, handles tool pairing, Task tool spawning
- **ChatState**: Data model ready, just needs session lifecycle methods
- **MessageInput**: Ready to send messages, just needs callback wiring
- **Persistence**: Saves/restores chat history

### What's Missing
1. Backend startup on app init
2. Session creation/lifecycle management
3. Message stream subscriptions
4. Permission request UI
5. Send message wiring
6. Error handling

### What Needs Refactoring
The existing `SdkMessageHandler` takes `ChatState` in its constructor, making it per-chat. The architecture docs show it should be stateless and take `ChatState` as a parameter to `handleMessage()` and `handlePermissionRequest()` so it can be shared. This is a minor refactor.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter App                                                 │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────┐    │
│  │ BackendService  │───>│ ClaudeBackend (Dart SDK)    │    │
│  │ (ChangeNotifier)│    │  - spawn()                  │    │
│  │                 │    │  - createSession()          │    │
│  │                 │    │  - dispose()                │    │
│  └────────┬────────┘    └─────────────────────────────┘    │
│           │                                                 │
│           │ createSession()                                 │
│           ▼                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ChatState (ChangeNotifier)                          │   │
│  │  - _session: ClaudeSession                          │   │
│  │  - _messageSubscription: StreamSubscription         │   │
│  │  - _permissionSubscription: StreamSubscription      │   │
│  │                                                     │   │
│  │  Methods:                                           │   │
│  │  - startSession(prompt)                             │   │
│  │  - sendMessage(text)                                │   │
│  │  - stopSession()                                    │   │
│  │  - handlePermissionRequest(req)                     │   │
│  └─────────────────────────────────────────────────────┘   │
│           │                                                 │
│           │ session.messages.listen()                       │
│           ▼                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ SdkMessageHandler (existing)                        │   │
│  │  - handleMessage(rawJson)                           │   │
│  │  - Routes to correct conversation                   │   │
│  │  - Pairs tool_use with tool_result                  │   │
│  │  - Calls chatState.addOutputEntry()                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ JSON lines (stdin/stdout)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Node.js Backend Process                                     │
│  - SessionManager handles SDK session lifecycle             │
│  - Routes messages between Dart and Claude API              │
│  - Forwards permission requests back to Dart                │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Backend Service

Create a service to manage the Node.js backend subprocess lifecycle.

**File:** `flutter_app_v2/lib/services/backend_service.dart`

```dart
class BackendService extends ChangeNotifier {
  ClaudeBackend? _backend;
  bool _isStarting = false;
  String? _error;

  bool get isReady => _backend != null;
  bool get isStarting => _isStarting;
  String? get error => _error;

  Future<void> start() async {
    if (_backend != null || _isStarting) return;

    _isStarting = true;
    _error = null;
    notifyListeners();

    try {
      _backend = await ClaudeBackend.spawn(
        backendPath: _getBackendPath(),
      );

      // Monitor backend errors
      _backend!.errors.listen((error) {
        _error = error.toString();
        notifyListeners();
      });

    } catch (e) {
      _error = e.toString();
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
  }) async {
    if (_backend == null) {
      throw StateError('Backend not started');
    }
    return _backend!.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
    );
  }

  @override
  void dispose() {
    _backend?.dispose();
    super.dispose();
  }

  String _getBackendPath() {
    // Return path to compiled backend-node executable
    // Development: use ts-node or compiled JS
    // Production: bundled executable
  }
}
```

**Wiring in main.dart:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final backendService = BackendService();
  await backendService.start();

  // SdkMessageHandler is stateless - shared across all chats
  final messageHandler = SdkMessageHandler();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: backendService),
        Provider.value(value: messageHandler),
        // ... other providers
      ],
      child: const CCInsightsApp(),
    ),
  );
}
```

---

### Phase 2: Session Lifecycle in ChatState

Add session management methods to ChatState.

**File:** `flutter_app_v2/lib/models/chat.dart`

**New imports:**
```dart
import 'package:claude_sdk/claude_sdk.dart';
import '../services/sdk_message_handler.dart';
```

**New fields:**
```dart
class ChatState extends ChangeNotifier {
  // Existing fields...

  ClaudeSession? _session;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _permissionSubscription;

  bool get hasActiveSession => _session != null;
  bool get isWaitingForPermission => _pendingPermission != null;
  PermissionRequest? _pendingPermission;
  PermissionRequest? get pendingPermission => _pendingPermission;
```

**New methods:**
```dart
  /// Starts a new SDK session for this chat.
  Future<void> startSession({
    required BackendService backend,
    required SdkMessageHandler messageHandler,
    required String prompt,
  }) async {
    if (_session != null) {
      throw StateError('Session already active');
    }

    // Create session with current settings
    _session = await backend.createSession(
      prompt: prompt,
      cwd: _worktreeRoot,
      options: SessionOptions(
        model: model.apiName,
        permissionMode: permissionMode.apiName,
      ),
    );

    // Subscribe to message stream - handler takes ChatState as parameter
    _messageSubscription = _session!.messages.listen(
      (msg) => messageHandler.handleMessage(this, msg),
      onError: _handleError,
      onDone: _handleSessionEnd,
    );

    // Subscribe to permission requests
    _permissionSubscription = _session!.permissionRequests.listen(
      (req) => messageHandler.handlePermissionRequest(this, req),
    );

    notifyListeners();
  }

  /// Sends a message to the active session.
  Future<void> sendMessage(String text) async {
    if (_session == null) {
      throw StateError('No active session');
    }

    // Add user message to conversation
    addOutputEntry(UserInputEntry(
      timestamp: DateTime.now(),
      text: text,
    ));

    // Send to SDK (fire-and-forget)
    await _session!.send(text);
  }

  /// Stops the current session.
  Future<void> stopSession() async {
    await _messageSubscription?.cancel();
    await _permissionSubscription?.cancel();
    await _session?.kill();

    _session = null;
    _messageHandler = null;
    _messageSubscription = null;
    _permissionSubscription = null;
    _pendingPermission = null;

    notifyListeners();
  }

  void _handleError(Object error) {
    // Add error entry to conversation
    addOutputEntry(TextOutputEntry(
      timestamp: DateTime.now(),
      text: 'Error: $error',
      contentType: 'error',
    ));
  }

  void _handleSessionEnd() {
    _session = null;
    notifyListeners();
  }

  /// Called by SdkMessageHandler when a permission request arrives.
  void setPendingPermission(PermissionRequest? request) {
    _pendingPermission = request;
    notifyListeners();
  }

  /// Responds to a pending permission request.
  void respondToPermission(PermissionResponse response) {
    _pendingPermission?.completer.complete(response);
    _pendingPermission = null;
    notifyListeners();
  }
```

---

### Phase 3: Wire Message Input

Connect MessageInput's onSubmit to ChatState.sendMessage().

**File:** `flutter_app_v2/lib/panels/conversation_panel.dart`

In the ConversationPanel build method:
```dart
MessageInput(
  onSubmit: (text) async {
    final chatState = context.read<ChatState>();

    if (!chatState.hasActiveSession) {
      // First message - start a new session
      final backend = context.read<BackendService>();
      final messageHandler = context.read<SdkMessageHandler>();
      await chatState.startSession(
        backend: backend,
        messageHandler: messageHandler,
        prompt: text,
      );
    } else {
      // Subsequent message - send to existing session
      await chatState.sendMessage(text);
    }
  },
  enabled: true, // Or based on backend.isReady
)
```

---

### Phase 4: Permission Request UI

Create a widget to display permission requests and collect user response.

**File:** `flutter_app_v2/lib/widgets/permission_dialog.dart`

```dart
class PermissionDialog extends StatelessWidget {
  final PermissionRequest request;
  final void Function(PermissionResponse) onResponse;

  const PermissionDialog({
    super.key,
    required this.request,
    required this.onResponse,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Permission Required: ${request.toolName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Claude wants to use the ${request.toolName} tool.'),
          const SizedBox(height: 12),
          Text('Input:', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              JsonEncoder.withIndent('  ').convert(request.input),
              style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => onResponse(PermissionResponse.deny()),
          child: const Text('Deny'),
        ),
        TextButton(
          onPressed: () => onResponse(PermissionResponse.denyAll()),
          child: const Text('Deny All'),
        ),
        FilledButton(
          onPressed: () => onResponse(PermissionResponse.allow()),
          child: const Text('Allow'),
        ),
        FilledButton(
          onPressed: () => onResponse(PermissionResponse.allowAll()),
          child: const Text('Allow All'),
        ),
      ],
    );
  }
}
```

**Display in ConversationPanel:**
```dart
@override
Widget build(BuildContext context) {
  final chatState = context.watch<ChatState>();

  return Column(
    children: [
      // Existing conversation content...

      // Permission request overlay
      if (chatState.pendingPermission != null)
        PermissionDialog(
          request: chatState.pendingPermission!,
          onResponse: (response) {
            chatState.respondToPermission(response);
          },
        ),
    ],
  );
}
```

---

### Phase 5: Cleanup and Error Handling

**Session cleanup on chat deletion:**
```dart
// In WorktreeState or wherever chats are deleted
void deleteChat(ChatState chat) {
  chat.stopSession();  // Stop session first
  chat.dispose();
  _chats.remove(chat);
  notifyListeners();
}
```

**Backend error display:**
```dart
// In app scaffold or status bar
Consumer<BackendService>(
  builder: (context, backend, child) {
    if (backend.error != null) {
      return ErrorBanner(message: backend.error!);
    }
    if (backend.isStarting) {
      return const LinearProgressIndicator();
    }
    return const SizedBox.shrink();
  },
)
```

**Graceful shutdown:**
```dart
// In main.dart or app lifecycle
class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      context.read<BackendService>().dispose();
    }
  }
}
```

---

## Task Breakdown

### Phase 1: Backend Service (Foundation)
1. Create `BackendService` class
2. Add backend path resolution (dev vs prod)
3. Wire into main.dart with Provider
4. Add backend status to StatusBar

### Phase 2: Session Lifecycle (Core)
1. Add session fields to ChatState
2. Implement `startSession()` method
3. Implement `sendMessage()` method
4. Implement `stopSession()` method
5. Add message stream handling
6. Add permission request handling

### Phase 3: Message Input Wiring
1. Update ConversationPanel to pass callbacks
2. Handle first message (session creation)
3. Handle subsequent messages

### Phase 4: Permission UI
1. Create PermissionDialog widget
2. Wire into ConversationPanel
3. Handle all response types (allow/deny/all)

### Phase 5: Polish
1. Error handling and display
2. Session cleanup on chat deletion
3. Graceful app shutdown
4. Loading states during session creation

---

## Testing Strategy

### Unit Tests
- BackendService state management
- ChatState session lifecycle
- SdkMessageHandler message parsing (existing)

### Widget Tests
- MessageInput sends to ChatState
- PermissionDialog displays and responds
- Conversation updates on new entries

### Integration Tests
- Full flow: type message → session created → response displayed
- Permission flow: tool use → dialog → response → continues
- Error handling: backend crash → error displayed

---

## Files to Create/Modify

**New Files:**
- `lib/services/backend_service.dart`
- `lib/widgets/permission_dialog.dart`

**Modify:**
- `lib/models/chat.dart` - Add session lifecycle
- `lib/panels/conversation_panel.dart` - Wire message input and permissions
- `lib/main.dart` - Add BackendService provider
- `lib/widgets/status_bar.dart` - Show backend status

**Existing (no changes needed):**
- `lib/services/sdk_message_handler.dart` - Already implemented
- `lib/widgets/message_input.dart` - Already implemented
- `lib/models/output_entry.dart` - Already implemented
