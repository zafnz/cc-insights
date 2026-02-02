# Permission approval crash (Bash: T.includes)

## Summary
When a user approved a permission request, the SDK crashed with:

```
undefined is not an object (evaluating 'T.includes')
```

The crash happened immediately after the permission callback resolved for tools
like `Bash`.

## Root cause
The Dart SDK was sending an empty `updated_input: {}` when approving a tool
request. In the TypeScript SDK, an "allow" response is required to include the
full tool input. Sending `{}` overwrote the original tool input, so required
fields (like `command` for `Bash`) became `undefined`, triggering the
`T.includes` error in the SDK.

This showed up in backend logs as:

```
Resolving permission callback with result {"behavior":"allow","updatedInput":{}}
```

## Fix
Default `updatedInput` to the original tool input when approving and no custom
input is provided.

Implementation:
- `claude_dart_sdk/lib/src/types/callbacks.dart`
  - `PermissionRequest.allow()` now passes `updatedInput: updatedInput ?? toolInput`.

## Verification
1. Start a session with `permissionMode` that triggers approval prompts.
2. Approve a `Bash` tool request.
3. Confirm the backend logs show `updatedInput` populated (not `{}`).
4. Ensure the tool executes without the `T.includes` crash.
