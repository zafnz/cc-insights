# Fix: Lazy Gitignore Checking

## Problem

`_getIgnoredPaths` in `file_system_service.dart` causes a SIGPIPE crash (exit code 141) in macOS release builds. It eagerly collects **all** file paths in the worktree (tens of thousands) via `_collectAllPaths`, then pipes them all through stdin to `git check-ignore --stdin -z`. This works in debug mode but kills the process in release builds.

Currently disabled — `_getIgnoredPaths` returns `{}` immediately, so no files are filtered.

## Solution: Lazy Per-Directory Gitignore Checking

Instead of checking the entire tree at startup, check gitignore status **per directory** when the user expands it. If the user never opens the file manager, nothing is checked. If they do, only the immediate children of each expanded directory are checked — a small set of files that stdin piping handles safely.

## Changes

### 1. `FileSystemService` — New method: `getIgnoredChildren`

Add a new method to the abstract class and both implementations:

```dart
/// Checks which paths in [childPaths] are ignored by .gitignore.
/// Returns the subset of paths that ARE ignored.
/// Uses stdin piping with git check-ignore --stdin -z.
Future<Set<String>> getIgnoredChildren(String repoRoot, List<String> childPaths);
```

- `RealFileSystemService`: Reuses the existing `_getIgnoredPaths` logic (Process.start, stdin pipe, NUL-separated) but only for a small list of paths (one directory's children).
- `FakeFileSystemService`: Returns intersection of `childPaths` with `_ignoredPaths`.

### 2. `FileSystemService.buildFileTree` — Stop doing gitignore at build time

- Remove the `respectGitignore` parameter from `buildFileTree`.
- Remove `_collectAllPaths` and the call to `_getIgnoredPaths` inside `buildFileTree`.
- `buildFileTree` becomes a pure directory scan — no gitignore filtering.
- Keep `_getIgnoredPaths` alive (renamed/refactored into `getIgnoredChildren`) for the lazy path.

### 3. `FileManagerState.toggleExpanded` — Trigger lazy ignore check

When a directory is expanded:

```
toggleExpanded(path):
  if collapsing → just remove from _expandedPaths, notify
  if expanding  → add to _expandedPaths, notify
                → if not already checked, call getIgnoredChildren for that directory's children
                → update tree: remove ignored children from the node
                → notify again
```

Track which directories have been checked in a `Set<String> _ignoreCheckedPaths` so we don't re-check on collapse/re-expand.

The tree update means we need a helper to find a node by path and replace its children. Since `FileTreeNode` is immutable, this rebuilds the path from root to the target node (similar to how immutable tree updates work).

### 4. `FileManagerState` — Tree node update helper

Add a private method to replace a node's children at a given path:

```dart
FileTreeNode _updateNodeChildren(
  FileTreeNode node,
  String targetPath,
  List<FileTreeNode> newChildren,
)
```

Walks the tree, finds the node at `targetPath`, returns a new tree with that node's children replaced. All other nodes are unchanged (structural sharing via the immutable model).

### 5. `FileManagerState.refreshFileTree` — Reset ignore tracking

When the tree is refreshed (worktree change, manual refresh), clear `_ignoreCheckedPaths` so directories get re-checked on next expand.

### 6. Test updates

- **Remove the `skip:` from the gitignore integration test** and update it to test the lazy path:
  - Build tree (no filtering)
  - Expand a directory → verify ignored files are removed
- **Add unit tests** for `getIgnoredChildren` in `FakeFileSystemService`
- **Add unit tests** for `FileManagerState.toggleExpanded` verifying lazy ignore behavior

### 7. Clean up dead code

- Remove `_collectAllPaths` method
- Remove the disabled `_getIgnoredPaths` (replaced by `getIgnoredChildren`)
- Remove `respectGitignore` parameter from `buildFileTree` signature and callers
- Remove `isIgnored` single-file method if no longer used

## File Summary

| File | Change |
|------|--------|
| `lib/services/file_system_service.dart` | Add `getIgnoredChildren`, remove `_collectAllPaths`, remove `respectGitignore` from `buildFileTree`, clean up dead code |
| `lib/state/file_manager_state.dart` | Add `_ignoreCheckedPaths`, update `toggleExpanded` to trigger lazy check, add tree update helper, reset on refresh |
| `test/integration/file_manager_state_integration_test.dart` | Remove skip, update test for lazy path |
| New/updated unit tests | Test `getIgnoredChildren`, test lazy expand behavior |

## Not In Scope

- Changing `FileTreeNode` model — no changes needed
- Changing `FileTreePanel` UI — it already works with `expandedPaths` and flattened tree
- Adding `signal(SIGPIPE, SIG_IGN)` to AppDelegate.swift — separate concern, may do later
