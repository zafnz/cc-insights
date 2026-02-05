# Logging System

This document describes the comprehensive logging system for debugging the backend.

## Architecture

### Dart SDK

**CLI Process** (`claude_dart_sdk/lib/src/cli_process.dart`):
- Captures all stderr from the Claude CLI process
- Exposes stderr as a `Stream<String>` via `AgentBackend.logs`
- Writes logs to `~/tmp/claude-agent-insights/dart-sdk-*.log`
- Prints all CLI logs to Flutter console with `[backend]` prefix

### Flutter App

**BackendService** (`flutter_app/lib/services/backend_service.dart`):
- Exposes `logs` stream and `logFilePath` from the Dart SDK
- Makes logs accessible throughout the app

**LogViewer Widget** (`flutter_app/lib/widgets/log_viewer.dart`):
- Real-time log display with auto-scroll
- Color coding for errors (red) and warnings (orange)
- Copy log file path to clipboard
- Open log file directory in Finder
- Clear logs button
- Access via the document icon in the top-right of the app

## Where Logs Go

### 1. **Console Output** (stdout/stderr of the app)
All backend logs are printed to the Flutter app's console with the `[backend]` prefix. When you run the app with `flutter run -d macos`, you'll see logs in the terminal.

Example:
```
[backend] [2024-01-22T10:30:45.123Z] [INFO] Backend process starting {"pid":12345}
[backend] [2024-01-22T10:30:45.234Z] [INFO] Backend process ready {"logFile":"/tmp/claude-agent-insights/backend-2024-01-22T10-30-45.log"}
```

### 2. **Log Files** (persistent)
Logs are also written to files for debugging later:
- Backend logs: `/tmp/claude-agent-insights/backend-<timestamp>.log`
- Dart SDK logs: `/tmp/claude-agent-insights/dart-sdk-<timestamp>.log`

To find the log file path:
1. Click the document icon in the app's title bar
2. The log file path is shown at the top
3. Click "Copy" to copy the path or "Open Folder" to view in Finder

### 3. **In-App Log Viewer**
Click the document icon (📄) in the top-right of the app to open the log viewer. This shows:
- Real-time log stream
- Auto-scroll to latest logs
- Color-coded errors and warnings
- Search/filter capabilities
- Links to open log files

## Log Levels

### Backend
- **DEBUG**: Message parsing, SDK message types, callback details
- **INFO**: Session lifecycle, major operations, successful completions
- **WARN**: Unknown messages, session not found, timeouts
- **ERROR**: Failures, exceptions with stack traces

### Changing Log Level
Set the `DEBUG` environment variable to enable debug logging:
```bash
DEBUG=true flutter run -d macos
```

Or set environment variable `LOG_LEVEL=debug` before starting the app.

## Examples

### Debugging Session Creation
Look for these log entries:
```
[INFO] Creating session {"sessionId":"...","cwd":"...","promptLength":123}
[DEBUG] Starting SDK query {"sessionId":"..."}
[INFO] Session created successfully {"sessionId":"...","totalSessions":1}
[INFO] Processing SDK messages {"sessionId":"..."}
```

### Debugging Errors
Errors include full context:
```
[ERROR] Failed to create session {"sessionId":"...","error":"..."}
[ERROR] SDK error during message processing {"sessionId":"...","error":"...","stack":"..."}
```

### Debugging Permissions
```
[INFO] Requesting permission {"sessionId":"...","callbackId":"...","toolName":"Read"}
[INFO] Permission callback resolved {"sessionId":"...","callbackId":"...","behavior":"allow"}
```

## Tips

1. **Enable debug logging** for detailed message tracing during development
2. **Use the in-app log viewer** for real-time debugging while the app is running
3. **Check log files** after crashes or for historical debugging
4. **Filter logs** by searching for session IDs to trace specific conversations
5. **Look for ERROR entries** first when debugging issues

## Troubleshooting

### No logs appearing?
- Check that the backend is running (green indicator in title bar)
- Verify the log file path exists
- Try restarting the app

### Log files too large?
- Log files are created per session (new file each time app starts)
- Manually delete old files from `/tmp/claude-agent-insights/`
- Consider adding log rotation if needed

### Missing debug logs?
- Ensure `DEBUG=true` is set when running the app
