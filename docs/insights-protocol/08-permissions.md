# Permission Model Deep Dive

> **Note:** For security configuration (permission modes, sandbox settings, approval policies), see [11-security-config.md](./11-security-config.md). This document focuses on runtime permission request handling.

Permissions are the most complex cross-backend concern because every backend implements them differently, yet the frontend needs a unified experience.

## Current State

### Three Different Permission Flows

| Backend | Mechanism | Request Format | Response Format |
|---------|-----------|----------------|-----------------|
| Claude CLI | `control_request`/`control_response` JSON Lines | `{subtype: 'can_use_tool', tool_name, input, tool_use_id, permission_suggestions, blocked_path}` | `{behavior: 'allow'/'deny', toolUseID, updatedInput, updatedPermissions, message}` |
| Codex | JSON-RPC server request/response | `{command, cwd, itemId}` or `{grantRoot, itemId}` or `{questions, itemId}` | `{decision: 'accept'/'decline'/'cancel'}` or `{answers: {...}}` |
| ACP | `session/request_permission` JSON-RPC | `{kind, message, options: [{id, name, kind}]}` | `{optionId: "..."}` or `{outcome: "cancelled"}` |

### Unified via PermissionRequest (Already Done)

The existing `PermissionRequest` in `agent_sdk_core` already unifies these:

```dart
class PermissionRequest {
  final String id;
  final String sessionId;
  final String toolName;
  final Map<String, dynamic> toolInput;
  final String? toolUseId;
  final List<dynamic>? suggestions;
  final String? blockedPath;
  final String? decisionReason;
  final Completer<PermissionResponse> _completer;

  void allow({Map<String, dynamic>? updatedInput, ...});
  void deny(String message, {bool interrupt = false});
}
```

Each backend creates a `PermissionRequest` and wires the `Completer` to send the appropriate response format when resolved. **This pattern is good and should continue.**

## What Changes with InsightsEvent

### PermissionRequestEvent Adds Context

The `PermissionRequestEvent` extends the current `PermissionRequest` with:

1. **`toolKind: ToolKind`** — Semantic categorization so the UI can render appropriate icons and context without parsing tool names.

2. **`reason: String?`** — Why the permission was requested. Claude provides `decisionReason`, Codex provides `reason`, ACP provides `message`.

3. **`provider: BackendProvider`** — So the permission dialog can show provider-specific options.

### The Completer Problem

`PermissionRequest` uses a `Completer<PermissionResponse>` for in-process response delivery. This doesn't serialize across a transport boundary.

**Solution:** For transport separation, permissions use request ID correlation:

```
Backend                       Transport                    Frontend
   │                              │                            │
   ├─ PermissionRequest ──────────┼─ PermissionRequestEvent ──►│
   │  (Completer waiting)         │  (requestId: "req-42")     │
   │                              │                            │ User decides
   │                              │◄─ PermissionResponseCmd ───┤
   │  (Completer resolved) ◄──────┤  (requestId: "req-42")    │
   │                              │                            │
```

The `PermissionRequestEvent` serializes everything except the Completer. The frontend sends a `PermissionResponseCommand` with the matching `requestId`. The backend-side bridge resolves the Completer.

For in-process use, the existing Completer pattern continues to work directly.

## Permission Features by Backend

### Claude CLI: The Richest Permission Model

Claude provides features no other backend has:

#### Permission Suggestions

When requesting permission, Claude may include suggestions for auto-approval rules:

```json
"permission_suggestions": [
  {"type": "allow_tool", "tool_name": "Bash", "description": "Allow all Bash commands"},
  {"type": "allow_directory", "directory": "/Users/zaf/project", "description": "Allow writes in project dir"},
  {"type": "set_mode", "mode": "acceptEdits", "description": "Switch to accept-edits mode"}
]
```

These map to `PermissionRequestEvent.suggestions: List<PermissionSuggestion>`.

The UI shows these as one-click buttons alongside Allow/Deny:
- "Always allow Bash" → sends `updatedPermissions` with the rule
- "Allow writes in /project" → sends `updatedPermissions` with directory grant
- "Switch to accept-edits" → sends `updatedPermissions` with mode change

**Other backends get null suggestions**, and the UI simply doesn't show these buttons.

#### Permission Mode

Claude has four permission modes that affect which tools need approval:

| Mode | Auto-Approved |
|------|---------------|
| `default` | Read-only tools |
| `acceptEdits` | Read + write + edit (within project) |
| `plan` | Limited tools (planning mode) |
| `bypassPermissions` | Everything (dangerous) |

The frontend sends `SetPermissionModeCommand` to change modes mid-session.

**Codex** manages permissions server-side; `setPermissionMode` is a no-op.
**ACP** uses `session/set_mode` which may or may not affect permissions (agent-dependent).

#### Blocked Path

Claude reports which filesystem path triggered the permission request:

```
blockedPath: "/Users/zaf/project/node_modules"
```

This helps the user understand exactly what's being protected. The UI can highlight the path.

**Other backends don't provide this.**

#### Updated Input

When allowing a permission, the user can modify the tool's input:

```dart
request.allow(updatedInput: {'command': 'npm test -- --no-cache'});
```

This is transmitted back to Claude CLI and replaces the original tool input.

**Codex** doesn't support input modification.
**ACP** doesn't support input modification (allow/reject only).

### Codex: Accept/Decline/Cancel

Codex uses a simpler three-option model:

| Decision | Meaning | Maps To |
|----------|---------|---------|
| `accept` | Proceed with the action | `PermissionAllowResponse()` |
| `decline` | Skip this action, continue turn | `PermissionDenyResponse(interrupt: false)` |
| `cancel` | Abort the entire turn | `PermissionDenyResponse(interrupt: true)` |

Codex also has `commandActions` in approval requests, which list the specific actions available. These go in `extensions['codex.commandActions']`.

### ACP: Option-Based Permissions

ACP uses named options with semantic kinds:

```json
"options": [
  {"id": "opt-1", "name": "Allow", "kind": "allow_once"},
  {"id": "opt-2", "name": "Always Allow", "kind": "allow_always"},
  {"id": "opt-3", "name": "Deny", "kind": "reject_once"},
  {"id": "opt-4", "name": "Always Deny", "kind": "reject_always"}
]
```

| ACP Option Kind | Meaning | Maps To |
|----------------|---------|---------|
| `allow_once` | Allow this specific call | `PermissionAllowResponse()` |
| `allow_always` | Allow all future calls of this type | `PermissionAllowResponse(updatedPermissions: ...)` |
| `reject_once` | Deny this call | `PermissionDenyResponse(interrupt: false)` |
| `reject_always` | Deny all future calls of this type | `PermissionDenyResponse(interrupt: false, ...)` |

This is semantically richer than Codex but less rich than Claude (no input modification, no specific path blocking, no mode changes).

## Permission Dialog: Unified but Adaptive

The permission dialog renders the same base UI for all backends but adapts based on available data:

```
┌──────────────────────────────────────────────────┐
│  🔒 Permission Request                  [Claude] │
│                                                  │
│  Bash wants to run:                              │
│  ┌──────────────────────────────────────────┐    │
│  │  $ npm test --coverage                    │    │
│  │  in /Users/zaf/project                    │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  Blocked path: /Users/zaf/project     ← Claude   │
│                                                  │
│  ┌─────────────────────────────────────────┐     │
│  │ Suggestions:                     ← Claude│    │
│  │  [Always allow Bash]                     │    │
│  │  [Allow writes in /project]              │    │
│  └─────────────────────────────────────────┘     │
│                                                  │
│        [Deny]  [Edit Input]  [Allow]             │
│                  ↑ Claude only                    │
└──────────────────────────────────────────────────┘
```

For Codex:

```
┌──────────────────────────────────────────────────┐
│  🔒 Permission Request                  [Codex]  │
│                                                  │
│  Bash wants to run:                              │
│  ┌──────────────────────────────────────────┐    │
│  │  $ npm test --coverage                    │    │
│  │  in /Users/zaf/project                    │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│      [Cancel Turn]  [Decline]  [Accept]          │
└──────────────────────────────────────────────────┘
```

For ACP:

```
┌──────────────────────────────────────────────────┐
│  🔒 Permission Request                    [ACP]  │
│                                                  │
│  Agent wants to run: npm test --coverage         │
│                                                  │
│  [Always Deny]  [Deny]  [Allow]  [Always Allow]  │
└──────────────────────────────────────────────────┘
```

### Implementation Pattern

```dart
class PermissionDialog extends StatelessWidget {
  final PermissionRequestEvent event;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Common: tool name + input display
      _ToolPreview(event: event),

      // Claude-specific: blocked path
      if (event.blockedPath != null)
        _BlockedPathIndicator(path: event.blockedPath!),

      // Claude-specific: suggestions
      if (event.suggestions != null && event.suggestions!.isNotEmpty)
        _SuggestionChips(suggestions: event.suggestions!),

      // Actions: adapt based on what's available
      _ActionButtons(event: event),
    ]);
  }
}

class _ActionButtons extends StatelessWidget {
  final PermissionRequestEvent event;

  @override
  Widget build(BuildContext context) {
    // ACP: show all options from the agent
    if (event.extensions?['acp.permissionOptions'] != null) {
      return _AcpOptionButtons(options: event.extensions!['acp.permissionOptions']);
    }

    // Codex: accept/decline/cancel
    if (event.provider == BackendProvider.codex) {
      return _CodexActionButtons(event: event);
    }

    // Claude (default): allow/deny with optional edit
    return _ClaudeActionButtons(event: event);
  }
}
```

## Permission Timeout

The frontend may implement a permission timeout: if the user doesn't respond within N seconds, auto-deny.

This works identically across all backends because the Completer-based pattern is the same — the timeout resolves the Completer with a `PermissionDenyResponse`.

For transport separation, the timeout can live on either side:
- **Frontend-side timeout**: Frontend sends `PermissionResponseCommand(allowed: false)` after timeout
- **Backend-side timeout**: Backend resolves the Completer with deny after timeout, emits a `ToolCompletionEvent(status: cancelled)`
