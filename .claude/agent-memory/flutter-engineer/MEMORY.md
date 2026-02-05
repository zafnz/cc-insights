# CC-Insights Flutter Engineer Memory

## Project Structure
- Frontend: `frontend/` - Flutter desktop app (macOS)
- SDK: `claude_dart_sdk/` - Dart SDK for Claude CLI
- Tests: `frontend/test/` with subdirs `models/`, `services/`, `widget/`, `fakes/`
- Integration tests: `frontend/integration_test/app_test.dart`

## Key Patterns
- **Models**: `@immutable` classes with `copyWith`, `toJson`, `fromJson`, `==`, `hashCode`, `toString`
- **Nullable fields in copyWith**: Use `clearX` boolean param pattern (e.g. `clearUserActions`, `clearDefaultBase`) to allow setting nullable fields to null
- **JSON keys**: Use kebab-case (`default-base`, `user-actions`) not camelCase
- **toJson**: Only include non-null/non-empty fields with `if` guards
- **fromJson**: Type-check JSON values (e.g. `json['key'] is String`) before using
- **Tests**: Use `package:checks` for assertions, Arrange-Act-Assert pattern
- **Test helpers**: `test/test_helpers.dart` has `safePumpAndSettle`, `pumpUntil`, `TestResources`
- **Fakes**: Located in `test/fakes/` (e.g. `FakeProjectConfigService`)
- **State**: `ChangeNotifier` + `Provider` pattern

## Config System
- `ProjectConfig` model in `frontend/lib/models/project_config.dart`
- `ProjectConfigService` in `frontend/lib/services/project_config_service.dart`
- Config stored at `{projectRoot}/.ccinsights/config.json`
- Fields: `actions` (lifecycle hooks), `userActions` (button commands), `defaultBase` (base branch ref)

## Persistence Architecture
- `persistence_models.dart`: Immutable data classes (`WorktreeInfo`, `ChatReference`, `ProjectInfo`, `ProjectsIndex`)
- `persistence_service.dart`: File I/O for projects.json and chat files
- Fire-and-forget persistence methods: log errors but don't throw
- Per-worktree override: `WorktreeInfo.baseOverride` / `WorktreeState.baseOverride`

## InformationPanel (Phase 4 Rewrite)
- File: `frontend/lib/panels/information_panel.dart`
- Test: `frontend/test/panels/information_panel_test.dart` (24 tests)
- State-driven layout based on `data.isRemoteBase` and `data.upstreamBranch`
- `InformationPanelKeys` class with static Key constants for test access
- Sections: Working Tree, Base, Upstream, Actions, Conflict

## Widget Testing Tips - RichText
- `find.textContaining()` only searches `Text` widgets, NOT `RichText`
- To test `RichText`: `find.byType(RichText)` then `.text.toPlainText()`

## Narrow Panel Overflow Prevention
- Navigation integration tests render panels at ~122px wide
- Put buttons on separate rows from icon + text to prevent overflow
- Use `Flexible` for text widgets in `Row`s
