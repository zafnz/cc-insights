# CC-Insights Flutter Engineer Memory

## Project Structure
- Frontend: `frontend/` - Flutter desktop app (macOS)
- SDK: `claude_dart_sdk/` - Dart SDK for Claude CLI
- Tests: `frontend/test/` with subdirs `models/`, `services/`, `widget/`, `panels/`, `fakes/`
- Integration tests: `frontend/integration_test/app_test.dart`

## Key Patterns
- **Models**: `@immutable` classes with `copyWith`, `toJson`, `fromJson`, `==`, `hashCode`, `toString`
- **Nullable fields in copyWith**: Use `clearX` boolean param pattern (e.g. `clearUserActions`, `clearDefaultBase`, `clearBaseOverride`) to allow setting nullable fields to null
- **JSON keys**: kebab-case in ProjectConfig (`default-base`, `user-actions`), camelCase in persistence_models (`baseOverride`, `lastSessionId`)
- **toJson**: Only include non-null/non-empty fields with `if` guards
- **fromJson**: Type-check JSON values (e.g. `json['key'] is String`) in ProjectConfig; use `as String?` in persistence_models
- **Tests**: Use `package:checks` for assertions, Arrange-Act-Assert pattern
- **Test helpers**: `test/test_helpers.dart` has `safePumpAndSettle`, `pumpUntil`, `TestResources`
- **Fakes**: Located in `test/fakes/` (e.g. `FakeProjectConfigService`, `FakePersistenceService`, `FakeGitService`)
- **State**: `ChangeNotifier` + `Provider` pattern

## Persistence Architecture
- `persistence_models.dart`: Immutable data classes (`WorktreeInfo`, `ChatReference`, `ProjectInfo`, `ProjectsIndex`)
- `persistence_service.dart`: File I/O for projects.json and chat files
- `project_restore_service.dart`: Restores `WorktreeState` from `WorktreeInfo` during app startup
- Fire-and-forget persistence methods: log errors but don't throw (e.g. `updateWorktreeTags`, `updateWorktreeBaseOverride`)
- Worktree state initialization: `WorktreeState` constructor accepts persisted fields (`tags`, `baseOverride`)
- Per-worktree override: `WorktreeInfo.baseOverride` / `WorktreeState.baseOverride`

## WorktreeState Pattern
- Setter methods: early-return if same value, then `notifyListeners()`
- Same pattern used for `welcomeModel`, `welcomePermissionMode`, `setBaseOverride`

## Config System
- `ProjectConfig` model in `frontend/lib/models/project_config.dart`
- `ProjectConfigService` in `frontend/lib/services/project_config_service.dart`
- Config stored at `{projectRoot}/.ccinsights/config.json`
- Fields: `actions` (lifecycle hooks), `userActions` (button commands), `defaultBase` (base branch ref)
- Per-worktree override: `WorktreeInfo.baseOverride` / `WorktreeState.baseOverride`

## WorktreeWatcherService
- File: `frontend/lib/services/worktree_watcher_service.dart`
- Constructor requires: `gitService`, `project`, `configService`
- Base ref resolution chain: worktree.baseOverride -> ProjectConfig.defaultBase -> auto-detect
- Auto-detect: remote main (if upstream exists) -> local main
- `resolveBaseRef` exposed as @visibleForTesting for direct testing
- `_isRemoteRef` checks for `origin/` or `remotes/` prefix
- "auto" value in defaultBase falls through to auto-detect
- `ProjectConfigService` must be registered BEFORE `WorktreeWatcherService` in provider list
- Periodic fetch: `_fetchTimer` fires every 2min, calls `gitService.fetch(repoRoot)` then `forceRefreshAll()`
- `fetchOrigin()` and `lastFetchTime` exposed as @visibleForTesting
- Fetch disabled when `enablePeriodicPolling: false`
- Adding new periodic timers affects existing tests that count poll calls at 2min intervals

## Dialog Widget Patterns
- Top-level `showXxxDialog()` convenience function wrapping `showDialog`
- `XxxDialogKeys` class with static `Key` constants for test access
- `StatefulWidget` with controllers disposed in `dispose()`
- `AlertDialog` with `actions: [TextButton(Cancel), FilledButton(Save/Apply)]`
- Width constraint via `SizedBox(width: N)` in `content:`
- Sentinel value pattern for null vs cancel distinction in dialog results

## ProjectSettingsPanel
- File: `frontend/lib/panels/project_settings_panel.dart`
- Categories: Lifecycle Hooks, User Actions, Git (sidebar navigation)
- Accepts optional `configService` param for test injection
- `_CategoryTile` text wrapped in `Flexible` to prevent overflow
- Git section: DropdownButton with auto/main/origin-main/custom options + text field for custom ref
- Tests: `frontend/test/panels/project_settings_panel_test.dart`

## BaseSelectorDialog (Phase 3, Task 7)
- File: `frontend/lib/widgets/base_selector_dialog.dart`
- Test: `frontend/test/widget/base_selector_dialog_test.dart` (20 tests)
- Per-worktree base ref override selector dialog
- Options: Use project default (null), main, origin/main, Custom (text field)
- Uses sentinel `__project_default__` to distinguish null (project default) from cancel
- `showBaseSelectorDialog()` top-level convenience function

## Testing Tips
- Panel tests that do file I/O need `tester.runAsync()` to allow async completion
- Use `setSurfaceSize(const Size(1200, 900))` in pumpAndLoad for panels needing wide layout
- `FakeProjectConfigService.configs` map is used to set up and verify config state
- `ProjectState` constructor: use `autoValidate: false, watchFilesystem: false` in tests
- `SelectionState(projectState)` - takes ProjectState, optional restoreService

## GitService Pattern
- Abstract interface + `RealGitService` implementation + `FakeGitService` for tests
- `TestGitService` in `test/panels/create_worktree_panel_test.dart` also implements GitService (must be updated when adding new methods)
- For merge/rebase/pull operations: use `Process.run` directly (not `_runGit`) to handle non-zero exit codes as conflicts
- `merge()`/`pull()` pattern: run command, then check `getStatus()` for conflicts
- `rebase()`/`pullRebase()` pattern: run command, check stderr for "CONFLICT" or "could not apply"
- Return `MergeResult` with `MergeOperationType.merge` or `.rebase` accordingly
- FakeGitService pattern: configurable result maps (`mergeResults`, `pullResults`), call tracking lists (`mergeCalls`, `pullCalls`), optional error fields (`mergeError`, `pullError`)

## InformationPanel (Phase 4 Rewrite)
- File: `frontend/lib/panels/information_panel.dart`
- Test: `frontend/test/panels/information_panel_test.dart` (24 tests)
- State-driven layout based on `data.isRemoteBase` and `data.upstreamBranch`
- Three UI states: local base, remote base no upstream, remote base has upstream
- `InformationPanelKeys` class with static Key constants for test access
- `_WorktreeInfo` is a StatelessWidget (no local state) - all state derived from WorktreeData
- Sections: Working Tree (always), Base (non-primary), Upstream (non-primary), Actions (state-driven), Conflict (replaces actions)
- Enable/disable logic for buttons computed from WorktreeData fields
- "Change..." button on its own row below base ref icon+text row to prevent overflow in narrow panels

## Widget Testing Tips - RichText
- `find.textContaining()` and `find.text()` only search `Text` widgets, NOT `RichText`
- To test `RichText` content, use: `find.byType(RichText)` then check `.text.toPlainText()`
- Pattern:
  ```dart
  final richTexts = find.byType(RichText).evaluate();
  final strings = richTexts.map((e) => (e.widget as RichText).text.toPlainText()).toList();
  check(strings).any((it) => it.contains('expected text'));
  ```

## Narrow Panel Overflow Prevention
- Navigation integration tests render panels at ~122px wide
- `Row` widgets with icons + text + buttons WILL overflow at this width
- Fix: Use `Flexible` for text widgets, put buttons on separate rows
- Avoid putting `_CompactButton` in same Row as icon + text for narrow panels
- Always test with navigation integration tests after changing panel layouts

## CliAvailabilityService
- File: `frontend/lib/services/cli_availability_service.dart`
- Fake: `frontend/test/fakes/fake_cli_availability_service.dart`
- Used by `ConversationPanel` (context.watch) and `SettingsScreen` (context.watch + context.read)
- Package name is `cc_insights_v2` (NOT `frontend`) - imports must use `package:cc_insights_v2/...`
- `CCInsightsApp` creates its own internally, so `app_providers_test.dart` does NOT need it injected
- Tests rendering `ConversationPanel`, `SettingsScreen`, or `MainScreen` need:
  ```dart
  ChangeNotifierProvider<CliAvailabilityService>.value(value: fakeCliAvailability),
  ```
- FakeCliAvailabilityService defaults: `claudeAvailable=true`, `codexAvailable=true`, `checked=true`

## Chat Archive Feature
- `ArchivedChatReference` model in `persistence_models.dart`: extends ChatReference with `originalWorktreePath` and `archivedAt`
- `ArchivedChatReference.fromChatReference()` factory, `toChatReference()` for round-trip
- `ProjectInfo.archivedChats` field: defaults to empty list, only serialized when non-empty
- Archive methods in `PersistenceService`: `archiveChat`, `restoreArchivedChat`, `archiveWorktreeChats`, `deleteArchivedChat`, `getArchivedChats`
- `_TestPersistenceService` needs `deleteChat` override + `createChatFiles`/`chatFilesExist` helpers for archive tests

## WorktreeService Methods
- `createWorktree`: Creates NEW git worktree + runs hooks + persists to projects.json
- `recoverWorktree`: Creates git worktree from EXISTING branch + runs hooks + persists
- `restoreExistingWorktree`: Re-registers EXISTING git worktree (no creation, no hooks) + persists
- Pattern for effective base: Check `config.defaultBase` is not null/empty/"auto", use as effectiveBase
- Test pattern: Use `_TrackingFakeGitService` to verify createWorktree was/wasn't called

## Test Counts (as of 2026-02-06)
- Unit/widget tests: ~2081 total (2 skipped)
- Integration tests: 9 (require macOS desktop build)
