# WebSocket Backend Architecture

## Overview

This document describes an alternative architecture where the Flutter frontend connects to the backend via WebSocket instead of spawning it as a subprocess. This enables:

- **LLM-driven testing** via iOS Simulator MCP
- **Cross-platform deployment** (iOS, Android, Web, Desktop)
- **Remote backend** capability
- **Multiple simultaneous clients**

## Current Architecture (Subprocess)

```
┌─────────────────────────────────────────────────────┐
│  Flutter App (macOS)                                │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  Dart SDK                                   │    │
│  │  - Spawns Node.js subprocess                │    │
│  │  - Communicates via stdin/stdout            │    │
│  │  - JSON lines protocol                      │    │
│  └─────────────────────────────────────────────┘    │
│         ↑                                           │
│         │ stdin/stdout                              │
│         ↓                                           │
│  ┌─────────────────────────────────────────────┐    │
│  │  backend-node (subprocess)                  │    │
│  │  - Claude Agent SDK                         │    │
│  │  - Session management                       │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Limitations:**
- macOS only (subprocess spawning)
- Cannot run on iOS/Android (no subprocess support)
- LLM cannot interact with GUI (no simulator access)
- Backend lifecycle tied to app lifecycle

## Proposed Architecture (WebSocket)

```
┌─────────────────────────────────────────────────────┐
│  Any Device (iOS Simulator, iPad, Mac, Web)         │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  Flutter App (UI only)                      │    │
│  │                                             │    │
│  │  WebSocket Client                           │    │
│  │  connects to ws://localhost:8080            │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
└─────────────────────────────────────────────────────┘
         ↑
         │ WebSocket
         ↓
┌─────────────────────────────────────────────────────┐
│  Host Machine                                       │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  Backend Server                             │    │
│  │  - WebSocket server on :8080                │    │
│  │  - Spawns Claude SDK subprocess             │    │
│  │  - Bridges SDK ↔ WebSocket                  │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## LLM Testing Workflow

With the WebSocket architecture, an LLM (Claude) can drive the app via iOS Simulator MCP:

```
┌─────────────────────────────────────────────────────┐
│  Host Machine                                       │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  iOS Simulator                              │    │
│  │  ┌─────────────────────────────────────┐    │    │
│  │  │  Flutter App                        │    │    │
│  │  │  WebSocket → ws://localhost:8080    │    │    │
│  │  └─────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────┘    │
│         ↑                                           │
│         │ iOS Simulator MCP                         │
│         │ (screenshot, tap, type)                   │
│         ↓                                           │
│  ┌─────────────────────────────────────────────┐    │
│  │  Claude                                     │    │
│  │  - Screenshots simulator                    │    │
│  │  - Taps UI elements                         │    │
│  │  - Types text                               │    │
│  │  - Verifies behavior                        │    │
│  │  - Debugs issues interactively              │    │
│  └─────────────────────────────────────────────┘    │
│         ↑                                           │
│         │ WebSocket                                 │
│         ↓                                           │
│  ┌─────────────────────────────────────────────┐    │
│  │  Backend Server (:8080)                     │    │
│  │  Claude Agent SDK                           │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Implementation

### 1. Backend: WebSocket Server

Add a WebSocket server mode to `backend-node`:

```typescript
// backend-node/src/websocket-server.ts
import { WebSocketServer, WebSocket } from 'ws';
import { SessionManager } from './session-manager';

const wss = new WebSocketServer({ port: 8080 });

wss.on('connection', (ws: WebSocket) => {
  console.log('Client connected');

  const sessionManager = new SessionManager();

  ws.on('message', async (data: Buffer) => {
    const message = JSON.parse(data.toString());

    // Same protocol as stdin/stdout, just over WebSocket
    switch (message.type) {
      case 'session.create':
        const session = await sessionManager.create(message.options);
        ws.send(JSON.stringify({ type: 'session.created', sessionId: session.id }));
        break;

      case 'session.send':
        await sessionManager.send(message.sessionId, message.text);
        break;

      case 'session.interrupt':
        await sessionManager.interrupt(message.sessionId);
        break;

      case 'session.kill':
        await sessionManager.kill(message.sessionId);
        break;

      case 'callback.response':
        await sessionManager.respondToCallback(
          message.sessionId,
          message.callbackId,
          message.response
        );
        break;
    }
  });

  // Forward SDK messages to client
  sessionManager.on('message', (msg) => {
    ws.send(JSON.stringify(msg));
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    sessionManager.dispose();
  });
});

console.log('WebSocket server listening on ws://localhost:8080');
```

### 2. Dart SDK: WebSocket Transport

Add a WebSocket-based backend implementation:

```dart
// dart_sdk/lib/src/websocket_backend.dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class ClaudeWebSocketBackend implements ClaudeBackend {
  WebSocketChannel? _channel;
  final String _url;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<dynamic>> _pendingRequests = {};
  int _requestId = 0;

  ClaudeWebSocketBackend._(this._url);

  static Future<ClaudeWebSocketBackend> connect(String url) async {
    final backend = ClaudeWebSocketBackend._(url);
    backend._channel = WebSocketChannel.connect(Uri.parse(url));

    // Listen for messages
    backend._channel!.stream.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      backend._handleMessage(message);
    });

    return backend;
  }

  void _handleMessage(Map<String, dynamic> message) {
    // Check if this is a response to a pending request
    final requestId = message['requestId'] as String?;
    if (requestId != null && _pendingRequests.containsKey(requestId)) {
      _pendingRequests[requestId]!.complete(message);
      _pendingRequests.remove(requestId);
      return;
    }

    // Otherwise broadcast to listeners
    _messageController.add(message);
  }

  Future<T> _request<T>(Map<String, dynamic> message) async {
    final requestId = '${_requestId++}';
    message['requestId'] = requestId;

    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;

    _channel!.sink.add(jsonEncode(message));

    final response = await completer.future;
    return response as T;
  }

  @override
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
  }) async {
    final response = await _request<Map<String, dynamic>>({
      'type': 'session.create',
      'prompt': prompt,
      'cwd': cwd,
      'options': options?.toJson(),
    });

    final sessionId = response['sessionId'] as String;
    return ClaudeWebSocketSession(
      backend: this,
      sessionId: sessionId,
    );
  }

  Stream<Map<String, dynamic>> messagesForSession(String sessionId) {
    return _messageController.stream
        .where((msg) => msg['sessionId'] == sessionId);
  }

  Future<void> send(String sessionId, String text) async {
    _channel!.sink.add(jsonEncode({
      'type': 'session.send',
      'sessionId': sessionId,
      'text': text,
    }));
  }

  Future<void> interrupt(String sessionId) async {
    _channel!.sink.add(jsonEncode({
      'type': 'session.interrupt',
      'sessionId': sessionId,
    }));
  }

  Future<void> kill(String sessionId) async {
    _channel!.sink.add(jsonEncode({
      'type': 'session.kill',
      'sessionId': sessionId,
    }));
  }

  Future<void> respondToCallback(
    String sessionId,
    String callbackId,
    dynamic response,
  ) async {
    _channel!.sink.add(jsonEncode({
      'type': 'callback.response',
      'sessionId': sessionId,
      'callbackId': callbackId,
      'response': response,
    }));
  }

  Future<void> dispose() async {
    await _channel?.sink.close();
    await _messageController.close();
  }
}

class ClaudeWebSocketSession implements ClaudeSession {
  final ClaudeWebSocketBackend _backend;

  @override
  final String sessionId;

  ClaudeWebSocketSession({
    required ClaudeWebSocketBackend backend,
    required this.sessionId,
  }) : _backend = backend;

  @override
  Stream<SDKMessage> get messages => _backend
      .messagesForSession(sessionId)
      .where((msg) => msg['type'] == 'sdk.message')
      .map((msg) => SDKMessage.fromJson(msg['data']));

  @override
  Stream<PermissionRequest> get permissionRequests => _backend
      .messagesForSession(sessionId)
      .where((msg) => msg['type'] == 'callback.request')
      .map((msg) => PermissionRequest.fromJson(msg['data']));

  @override
  Future<void> send(String message) => _backend.send(sessionId, message);

  @override
  Future<void> interrupt() => _backend.interrupt(sessionId);

  @override
  Future<void> kill() => _backend.kill(sessionId);

  @override
  Future<void> respondToCallback(String callbackId, dynamic response) =>
      _backend.respondToCallback(sessionId, callbackId, response);
}
```

### 3. Backend Abstraction

Create an interface that both subprocess and WebSocket backends implement:

```dart
// dart_sdk/lib/src/backend_interface.dart
abstract class ClaudeBackend {
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
  });

  Future<void> dispose();
}

// Factory for creating backends
class ClaudeBackendFactory {
  /// Spawn a local subprocess backend (macOS/Linux/Windows only)
  static Future<ClaudeBackend> spawnSubprocess() async {
    return ClaudeSubprocessBackend.spawn();
  }

  /// Connect to a remote WebSocket backend
  static Future<ClaudeBackend> connectWebSocket(String url) async {
    return ClaudeWebSocketBackend.connect(url);
  }
}
```

### 4. Flutter App: Platform-Aware Connection

```dart
// flutter_app/lib/main.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

Future<ClaudeBackend> createBackend() async {
  // Web or mobile: use WebSocket
  if (kIsWeb || Platform.isIOS || Platform.isAndroid) {
    // Could be configured via environment or settings
    const backendUrl = String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'ws://localhost:8080',
    );
    return ClaudeBackendFactory.connectWebSocket(backendUrl);
  }

  // Desktop: can use subprocess (existing behavior)
  return ClaudeBackendFactory.spawnSubprocess();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final backend = await createBackend();

  runApp(MyApp(backend: backend));
}
```

### 5. Enable iOS Platform

```bash
cd flutter_app
flutter create . --platforms ios
```

## Usage

### Development (Desktop - Subprocess)

```bash
# Existing workflow, no changes
cd flutter_app
flutter run -d macos
```

### Development (iOS Simulator - WebSocket)

```bash
# Terminal 1: Start backend server
cd backend-node
npm run start:websocket
# Backend listening on ws://localhost:8080

# Terminal 2: Run app in iOS Simulator
cd flutter_app
flutter run -d iPhone
```

### LLM Testing Workflow

1. Start backend server on host
2. Run Flutter app in iOS Simulator
3. Claude uses iOS Simulator MCP to:
   - Take screenshots
   - Tap UI elements
   - Type text
   - Verify responses
   - Debug issues interactively

## Comparison

| Aspect | Subprocess | WebSocket |
|--------|-----------|-----------|
| **Platforms** | Desktop only | All (iOS, Android, Web, Desktop) |
| **LLM Testing** | Cannot see GUI | iOS Simulator MCP works |
| **Deployment** | Single machine | Backend can be remote |
| **Setup** | Zero config | Requires backend server |
| **Debugging** | Single process logs | Separate UI/backend logs |
| **Latency** | Minimal | Slight network overhead |
| **Offline** | Works | Requires backend connection |

## Effort Estimate

| Component | Effort |
|-----------|--------|
| WebSocket server in backend-node | 2-3 hours |
| WebSocket transport in Dart SDK | 2-3 hours |
| Backend abstraction (interface) | 1 hour |
| Enable iOS platform + test | 1 hour |
| **Total** | **6-8 hours** |

## Future Enhancements

### Multi-Client Support

The WebSocket architecture naturally supports multiple clients:

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ iPad        │  │ Mac         │  │ Web Browser │
│ Flutter App │  │ Flutter App │  │ Flutter App │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
                        ↓
              ┌─────────────────┐
              │ Backend Server  │
              │ (shared state)  │
              └─────────────────┘
```

### Remote Backend Deployment

```bash
# Deploy backend to cloud
docker run -p 8080:8080 your-backend-image

# Connect from anywhere
flutter run --dart-define=BACKEND_URL=wss://your-server.com:8080
```

### Session Persistence

With a centralized backend, sessions can persist across app restarts and device switches.
