**ACP Permissions and Safety**

**Permission Flow**
- ACP agents call `session/request_permission` with `toolCall` and `options`.
- The backend emits `PermissionRequestEvent` with `toolUseId`, `toolName`, `toolKind`, and `reason`.
- The original ACP options are preserved in `extensions['acp.permissionOptions']` for the dialog.
- The response must return ACP `RequestPermissionOutcome`.

**Option Mapping**
- `allow_once` maps to `PermissionAllowResponse()`.
- `allow_always` maps to `PermissionAllowResponse(updatedPermissions: ...)`.
- `reject_once` maps to `PermissionDenyResponse(interrupt: false)`.
- `reject_always` maps to `PermissionDenyResponse(interrupt: false)`.
- `cancelled` maps to `PermissionDenyResponse(interrupt: true)`.

**Filesystem Safety**
- Only allow read/write within the repo root and allowlisted directories.
- Deny out-of-scope paths by default and emit a permission request for user override.
- Always normalize paths to absolute form and reject relative paths.

**Terminal Safety**
- Allow terminal commands only when `terminal` capability is advertised.
- For `cwd` outside repo root or allowlist, request permission and default deny.
- Enforce `outputByteLimit` truncation per ACP spec.

**Blocked Path UX**
- When denying due to path policy, set `PermissionRequestEvent.reason` with a clear message.
- Include the blocked path in `extensions['acp.blockedPath']` so the permission dialog can display it.
