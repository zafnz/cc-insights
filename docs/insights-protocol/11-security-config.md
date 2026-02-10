# Unified Security Configuration

This document specifies how CC-Insights handles security configuration across backends. Claude, Codex, and future backends (ACP/Gemini) each implement security differently. Rather than forcing a lowest-common-denominator model, the app exposes backend-native security controls with a consistent UI pattern.

## Problem Statement

The current app applies Claude's four-mode permission model (`default`, `acceptEdits`, `plan`, `bypassPermissions`) to **all** backends. This is wrong for Codex, which has a fundamentally different two-axis security system (sandbox mode + approval policy). The mismatch means:

1. The Codex dropdown shows Claude modes that map to nothing on the Codex side
2. Neither `sandbox` nor `approvalPolicy` are passed to Codex `thread/start`
3. The app never reads or writes Codex's config, so it can't discover or change security settings
4. The permission dialog shows Claude-style suggestions UI for Codex (which doesn't support suggestions)
5. Enterprise constraints (`requirements.toml`) are completely ignored

## Design Principles

**1. Backend-native controls, not a unified abstraction.** Each backend gets its own security model types and UI. We don't try to map Codex sandbox modes onto Claude permission modes — they're different concepts.

**2. Feature detection over backend detection.** The frontend checks what capabilities are available rather than hard-coding backend names. A `SecurityCapabilities` object describes what a backend supports.

**3. Settings flow at thread/session start.** Security configuration is set when creating a session and can optionally be changed mid-session (where supported).

**4. Respect enterprise constraints.** Admin requirements restrict which options are available. The UI disables locked options and shows why.

## Security Models by Backend

### Claude CLI

Claude has a **single-axis** model: a permission mode that determines which tools require user approval.

| Mode | Description | Auto-approved |
|------|-------------|---------------|
| `default` | Most restrictive | Read-only tools |
| `acceptEdits` | Allows file operations | Read + write within project |
| `plan` | Planning mode | Limited tool set |
| `bypassPermissions` | No restrictions | Everything (dangerous) |

Additional features:
- **Permission suggestions**: Rules, directories, mode changes proposed with each request
- **Blocked path**: Shows which filesystem path triggered the request
- **Updated input**: User can modify tool input when allowing
- **Setting persistence**: Suggestions can save to user/project/local settings

### Codex

Codex has a **two-axis** model with OS-level sandbox enforcement plus user consent policy.

**Axis 1: Sandbox Mode** (what the agent can physically do)

| Mode | Description | File ops | Commands | Network |
|------|-------------|----------|----------|---------|
| `read-only` | Observe only | Read | No | No |
| `workspace-write` | Work within workspace | Read + Write (workspace) | Yes (workspace) | Configurable |
| `danger-full-access` | Unrestricted | All | All | All |

**Axis 2: Approval Policy** (when to ask the user)

| Policy | Description | Prompts for |
|--------|-------------|-------------|
| `untrusted` | Cautious | Commands (file edits auto-approved) |
| `on-request` | Standard | Edits outside workspace, network |
| `on-failure` | Minimal | Only failed operations |
| `never` | None | Nothing (dangerous) |

**Workspace-write sub-options:**
- `network_access: bool` — Allow network from commands
- `writable_roots: List<String>` — Additional writable paths beyond workspace
- `exclude_slash_tmp: bool` — Remove /tmp from writable set
- `exclude_tmpdir_env_var: bool` — Remove $TMPDIR from writable set

**Web search:** `disabled`, `cached` (default), `live`

**Enterprise requirements** (`requirements.toml` / MDM):
- `allowedSandboxModes` — Restricts which sandbox modes are available
- `allowedApprovalPolicies` — Restricts which approval policies are available
- `enforceResidency` — Data residency enforcement

### ACP (Future)

ACP agents define their own security capabilities at initialization. The `session/capabilities` response includes:
- Available permission modes (agent-defined)
- Supported approval options (`allow_once`, `allow_always`, `reject_once`, `reject_always`)

The ACP security config will be implemented when ACP support is added. The architecture accommodates it via the `SecurityCapabilities` pattern.

## Architecture

### Type Hierarchy

```
SecurityConfig (sealed)
├── ClaudeSecurityConfig
│   └── permissionMode: ClaudePermissionMode
└── CodexSecurityConfig
    ├── sandboxMode: CodexSandboxMode
    ├── approvalPolicy: CodexApprovalPolicy
    ├── workspaceWriteOptions: CodexWorkspaceWriteOptions?
    └── webSearch: CodexWebSearchMode?
```

```
SecurityCapabilities (sealed)
├── ClaudeSecurityCapabilities
│   └── supportsPermissionModeChange: bool
│   └── supportsSuggestions: bool
└── CodexSecurityCapabilities
    ├── allowedSandboxModes: List<CodexSandboxMode>?
    ├── allowedApprovalPolicies: List<CodexApprovalPolicy>?
    └── supportsMidSessionChange: bool
```

### Data Flow

```
                    ┌─────────────────┐
                    │   ChatState     │
                    │                 │
                    │ securityConfig ─┼─── SecurityConfig (sealed)
                    │ securityCaps  ──┼─── SecurityCapabilities (sealed)
                    └───────┬─────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
     ┌────────────┐  ┌───────────┐  ┌──────────┐
     │ Thread     │  │ Config    │  │ UI       │
     │ Start      │  │ Write     │  │ Header   │
     │ Params     │  │ (mid-     │  │ Dropdown │
     │ (session   │  │  session) │  │ Render   │
     │  create)   │  │           │  │          │
     └────────────┘  └───────────┘  └──────────┘
```

**At session start:**
1. `ChatState.securityConfig` holds the user's chosen settings
2. `BackendService.createTransport()` passes config to the backend
3. `CodexBackend._startThread()` includes `sandbox` and `approvalPolicy` in `thread/start`
4. `CliBackend.createSession()` includes `permissionMode` in session options

**Mid-session changes:**
1. User changes a dropdown value in the header
2. `ChatState.setSecurityConfig(newConfig)` updates local state
3. For Claude: `SetPermissionModeCommand` sent via transport (existing flow)
4. For Codex: `config/write` JSON-RPC sent to update `sandbox_mode` or `approval_policy`
5. UI updates immediately; toast notification confirms the change

**On session connect (Codex):**
1. `CodexBackend` calls `config/read` to discover current config
2. Enterprise requirements read via `config/requirementsRead`
3. `SecurityCapabilities` populated with allowed modes/policies
4. UI dropdowns restrict to allowed options

### Wire Format: Codex Config JSON-RPC

**Read current config:**
```json
→ {"jsonrpc": "2.0", "id": 1, "method": "config/read", "params": {}}
← {"jsonrpc": "2.0", "id": 1, "result": {
    "config": {
      "sandbox_mode": "workspace-write",
      "approval_policy": "on-request",
      "sandbox_workspace_write": {
        "network_access": false,
        "writable_roots": [],
        "exclude_slash_tmp": false,
        "exclude_tmpdir_env_var": false
      },
      "web_search": "cached"
    },
    "origins": { ... }
  }}
```

**Write config value:**
```json
→ {"jsonrpc": "2.0", "id": 2, "method": "config/write", "params": {
    "keyPath": "sandbox_mode",
    "value": "read-only",
    "mergeStrategy": "replace"
  }}
← {"jsonrpc": "2.0", "id": 2, "result": {
    "status": "ok",
    "filePath": "/Users/zaf/.codex/config.toml",
    "version": "abc123"
  }}
```

**Write with enterprise override:**
```json
← {"jsonrpc": "2.0", "id": 3, "result": {
    "status": "okOverridden",
    "filePath": "/Users/zaf/.codex/config.toml",
    "version": "abc124",
    "overriddenMetadata": {
      "effectiveValue": "workspace-write",
      "message": "Admin policy restricts sandbox modes",
      "overridingLayer": { "type": "mdm", "domain": "com.openai.codex", "key": "sandbox_mode" }
    }
  }}
```

**Read enterprise requirements:**
```json
→ {"jsonrpc": "2.0", "id": 4, "method": "config/requirementsRead", "params": {}}
← {"jsonrpc": "2.0", "id": 4, "result": {
    "requirements": {
      "allowedSandboxModes": ["read-only", "workspace-write"],
      "allowedApprovalPolicies": ["untrusted", "on-request", "on-failure"],
      "enforceResidency": null
    }
  }}
```

**Config warning notification (server → client):**
```json
← {"jsonrpc": "2.0", "method": "config/warning", "params": {
    "summary": "sandbox_mode 'danger-full-access' is restricted by admin policy",
    "details": "Allowed modes: read-only, workspace-write",
    "path": "/Users/zaf/.codex/config.toml"
  }}
```

### Thread Start Params

The `thread/start` and `thread/resume` JSON-RPC methods already accept `sandbox` and `approvalPolicy` parameters (see `ThreadStartParams.json` and `ThreadResumeParams.json`). These are currently not sent by the app.

**New thread/start with security:**
```json
→ {"jsonrpc": "2.0", "id": 5, "method": "thread/start", "params": {
    "cwd": "/Users/zaf/projects/cc-insights",
    "model": "o3",
    "sandbox": "workspace-write",
    "approvalPolicy": "on-request"
  }}
```

## UI Design

See `docs/mocks/security-config-mockups.html` for visual mockups. Key decisions:

### Conversation Header

The header renders **backend-specific** security controls:

**Claude backend:** Single "Permissions" dropdown (unchanged from current behavior).
```
[ Claude ▾ ] [ Sonnet 4.5 ▾ ] [ Accept Edits ▾ ]          [ ⊞ 62% ] [ $ 0.42 ]
```

**Codex backend:** Security group with shield icon containing two dropdowns.
```
[ Codex ▾ ] [ o3 ▾ ] [ 🛡 Workspace Write ▾ | Ask: On Request ▾ ] [ Reasoning ▾ ]   [ ✓ Sandboxed ] [ ⊞ 45% ]
```

The security group has:
- A shield icon prefix identifying the group
- Sandbox mode dropdown (left)
- Approval policy dropdown (right)
- Thin divider between the two
- Visual border around the group to show they're related

**Danger state:** When dangerous settings are active (`danger-full-access` or `never`), the group border turns red and text highlights in red.

**Narrow width (< 500px):** The security group collapses to a shield icon + abbreviated badge (`WS + Ask`). Clicking opens the full workspace settings panel.

### Security Badge

A small colored badge in the header right section summarizes the effective security posture:

| Posture | Badge | Color |
|---------|-------|-------|
| Read-only sandbox | `✓ Read Only` | Green |
| Workspace-write with approval | `✓ Sandboxed` | Green |
| Workspace-write without approval | `⚠ Auto-approve` | Orange |
| Full access with approval | `⚠ Unrestricted` | Orange |
| Full access without approval | `⚠ Unrestricted` | Red |

This badge is Codex-only (Claude's permission mode is self-explanatory in its dropdown).

### Sandbox Mode Dropdown

Items with icons and descriptions:

| Icon | Label | Description |
|------|-------|-------------|
| 👁 | Read Only | No edits, no commands |
| ✏ | Workspace Write | Edits + commands in workspace |
| 🔓 | Full Access | No restrictions (dangerous) |

Separator, then: **Workspace settings...** opens the fine-grained settings panel.

Enterprise-locked items are grayed out with a 🔒 Admin badge.

### Approval Policy Dropdown

| Icon | Label | Description |
|------|-------|-------------|
| 🛡 | Untrusted | Prompt before commands |
| ✋ | On Request | Prompt for outside workspace |
| 🔄 | On Failure | Only prompt on failure |
| ⛔ | Never | Skip all prompts (red) |

### Workspace Write Settings Panel

Accessed via "Workspace settings..." in the sandbox dropdown. Shows:

1. **Network access** — Toggle
2. **Temp directories** — Exclude /tmp, Exclude $TMPDIR toggles
3. **Additional writable paths** — List with add/remove
4. **Web search** — Dropdown: Disabled / Cached / Live

This panel writes via `config/batchWrite` to update multiple workspace-write sub-options atomically.

### Permission Dialog

The dialog adapts based on backend:

**Claude:** Full existing dialog with suggestions chips, blocked path, input modification, allow/deny buttons. No changes.

**Codex:** Simplified dialog with:
- Tool name and content preview (command text, file path)
- `commandActions` info when available (read, search, listFiles, unknown)
- `reason` text when the agent provides one
- Three buttons: **Cancel Turn** (cancel), **Decline** (decline), **Accept** (accept)
- No suggestions section, no input modification

### Security Change Notifications

When security settings change mid-session, a toast notification appears:
- "Sandbox changed to Read Only" (neutral)
- "Approval policy set to Never — all actions auto-approved" (warning, red border)

## Persistence

### chat.meta.json

Security config is persisted per-chat alongside existing fields:

**Claude chat:**
```json
{
  "backendType": "directCli",
  "permissionMode": "acceptEdits",
  ...
}
```

**Codex chat:**
```json
{
  "backendType": "codex",
  "codexSandboxMode": "workspace-write",
  "codexApprovalPolicy": "on-request",
  "codexWorkspaceWriteOptions": {
    "networkAccess": false,
    "writableRoots": [],
    "excludeSlashTmp": false,
    "excludeTmpdirEnvVar": false
  },
  "codexWebSearch": "cached",
  ...
}
```

The existing `permissionMode` field is kept for Claude chats. A new set of `codex*` fields stores Codex security config. This avoids breaking existing persistence.

### RuntimeConfig Defaults

`RuntimeConfig` gains new fields for Codex defaults:
- `defaultCodexSandboxMode` (default: `workspace-write`)
- `defaultCodexApprovalPolicy` (default: `on-request`)

These are used when creating new Codex chats.

## Relationship to Existing Documents

This document **supersedes the security-related sections** of `08-permissions.md`. Specifically:
- The "Permission Mode" section in 08 is replaced by the Claude security model here
- The "Codex: Accept/Decline/Cancel" section in 08 is expanded with full security config
- The permission dialog mockups in 08 are replaced by the HTML mockups

The permission request/response flow (Completer pattern, transport correlation) documented in 08 remains valid and unchanged.

## Summary of Changes

| Component | Change |
|-----------|--------|
| `agent_sdk_core` | New `SecurityConfig`, `SecurityCapabilities` sealed types |
| `codex_dart_sdk` | Add `config/read`, `config/write`, `config/requirementsRead` JSON-RPC methods; pass `sandbox`/`approvalPolicy` to `thread/start` |
| `frontend/models/chat.dart` | Replace single `PermissionMode` with backend-specific `SecurityConfig`; new persistence fields |
| `frontend/panels/conversation_header.dart` | Backend-aware security controls: single dropdown for Claude, grouped dropdowns for Codex |
| `frontend/widgets/permission_dialog.dart` | Adapt Codex dialog: remove suggestions, add command actions, reason, cancel turn |
| `frontend/services/backend_service.dart` | Read Codex config on connect, surface `SecurityCapabilities` |
| New: `frontend/widgets/security_config_group.dart` | The grouped security dropdowns widget for Codex |
| New: `frontend/widgets/workspace_settings_panel.dart` | Fine-grained workspace-write settings |
