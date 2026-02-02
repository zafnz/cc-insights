# Error Handling Improvements

## Changes Made

### 1. Dart SDK - Error Message Routing
**File:** `claude_dart_sdk/lib/src/backend.dart`

- Modified `_handleError()` to detect session-specific errors
- Session-specific errors (those with a `session_id`) are now emitted as `SDKErrorMessage` to the session's message stream instead of only to the global error stream
- This allows sessions to handle their own errors independently

**File:** `claude_dart_sdk/lib/src/types/sdk_messages.dart`

- Added new `SDKErrorMessage` class to represent error messages in the SDK message stream
- Allows errors to flow through the same stream as other session messages

### 2. Flutter App - Error Display
**File:** `flutter_app/lib/providers/session_provider.dart`

- Added `_handleErrorMessage()` to process `SDKErrorMessage`
- Sets `session.error` field and marks session as not running
- Marks main agent status as 'error'

**File:** `flutter_app/lib/widgets/output_panel.dart`

- Added `_ErrorIndicator` widget to display errors in a red alert box
- Updated output panel logic to check for errors before showing "Claude is working..." spinner
- Priority: Error > Permission Request > Working Indicator

### 3. Visual Error Display

When an error occurs, users now see:
- Red alert box with error icon
- "Error" header in bold
- Error message text
- No more infinite "Claude is working..." spinner on errors

### Testing

To test error handling:
1. Trigger a backend error (e.g., kill the backend process, or cause SDK error)
2. The UI should display a red error box instead of the working spinner
3. Full error details are still available in the console and log files
4. Users can see immediately that something went wrong without having to check logs

### Log Files

Error details are still logged to:
- Backend logs: `/tmp/claude-agent-insights/backend-*.log`
- Dart SDK logs: `/tmp/claude-agent-insights/dart-sdk-*.log`
- Flutter console output
- In-app log viewer (document icon in title bar)
