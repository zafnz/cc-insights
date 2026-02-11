# Fix Codex Permissions Dialog (Session + Persistent Allow)

## Summary
Codex permission requests can include a server-proposed execpolicy amendment that enables persistent allowlisting of specific commands. The app currently drops this data and only supports accept/decline/cancel. This proposal adds Codex-only allow options for "Once", "For session", and "Always" while leaving Claude unchanged, and splits the permission dialog into two distinct implementations.

## Goals
- Support Codex approval choices: allow once, allow for session, allow always (persistent).
- Keep Claude permissions UI and behavior unchanged.
- Avoid complex branching inside a single permission dialog widget.
- Surface Codex-specific context (command actions, reason, execpolicy proposal) in the Codex dialog.

## Non-Goals
- Changing Claude permission suggestions or behavior.
- Introducing new global settings UI for allowlists (initial scope is per-approval selection).
- Reworking the existing permission stream transport architecture.

## Current Gaps
- Codex JSON-RPC approvals support `acceptForSession` and `acceptWithExecpolicyAmendment`, but we only send `accept/decline/cancel`.
- `proposedExecpolicyAmendment` is not surfaced to the UI, so users cannot make persistent allow decisions.
- Permission UI is unified and already diverging; Codex needs a distinct UI without Claude’s suggestion controls.

## Proposed UX (Codex)
- Add a compact "Allow" selector in the Codex permission dialog.
- Options:
  - `Once` (default)
  - `For session`
  - `Always` (shown only if `proposedExecpolicyAmendment` is present)
- Buttons remain: `Cancel Turn`, `Decline`, `Accept`.
- Selecting `For session` maps to `acceptForSession`.
- Selecting `Always` maps to `acceptWithExecpolicyAmendment` using the proposed amendment from the server.

## Mockup (Codex Dialog)

```text
┌──────────────────────────────────────────────────────────────┐
│  🛡 Permission Required — Codex                               │
├──────────────────────────────────────────────────────────────┤
│ Bash wants to run:                                           │
│ $ ./frontend/run-flutter-test.sh                             │
│ cwd: /Users/zaf/projects/cc-insights                         │
│                                                              │
│ Actions: read workspace, list files                          │
│ Reason: retry without sandbox                                │
│                                                              │
│ Allow: [ Once ▾ ]   (Once | For session | Always*)            │
│                                                              │
│ [Cancel Turn]     [Decline]     [Accept]                     │
└──────────────────────────────────────────────────────────────┘
*Always only shown when proposed execpolicy amendment is present
```

## HTML Mockup
See `docs/mocks/codex-permission-dialog-mockup.html`.

## Design Decisions
- Split UI into two widgets:
  - `ClaudePermissionDialog` (existing behavior, unchanged)
  - `CodexPermissionDialog` (new behavior)
- A thin dispatcher widget selects the appropriate dialog by backend provider.
- Codex dialog reads Codex-specific fields from the permission request and shows only the features Codex supports.

## Data Flow (Codex)
1. Codex server sends `item/commandExecution/requestApproval` with optional `proposedExecpolicyAmendment`.
2. `CodexSession` emits a permission request containing:
   - `command`, `cwd`
   - `commandActions` and `reason`
   - `proposedExecpolicyAmendment`
3. Codex dialog renders the allow selector when `proposedExecpolicyAmendment` is present.
4. User picks `Once`, `For session`, or `Always`.
5. Response mapping:
   - `Once` → `{decision: "accept"}`
   - `For session` → `{decision: "acceptForSession"}`
   - `Always` → `{decision: {"acceptWithExecpolicyAmendment": {"execpolicy_amendment": [...]}}}`

## Backend Changes
- `codex_dart_sdk/lib/src/codex_session.dart`
  - Preserve `proposedExecpolicyAmendment` from request params.
  - Pass `commandActions` and `reason` to the permission request.
  - Map new allow decisions to Codex JSON-RPC response variants.

## Frontend Changes
- `frontend/lib/widgets/permission_dialog.dart`
  - Split into a dispatcher + two concrete widgets.
  - Keep Claude dialog untouched.
  - Add Codex dialog with Allow selector and new response mapping.

## Tests
- Codex approval response mapping for:
  - `accept`
  - `acceptForSession`
  - `acceptWithExecpolicyAmendment`
- Codex dialog UI:
  - Selector shows `Always` only when amendment is present.
  - Selected option maps to correct response.

## Risks / Edge Cases
- If `proposedExecpolicyAmendment` is absent, `Always` must not be shown.
- Ensure `For session` only applies to the command+cwd combination (Codex-defined behavior).
- Avoid leaking Codex fields into Claude dialog state.

## Rollout Notes
- This change is isolated to Codex-only paths and should be low-risk for Claude.
- If the server rejects execpolicy amendments due to admin policy, surface the server warning in the usual system notifications.
