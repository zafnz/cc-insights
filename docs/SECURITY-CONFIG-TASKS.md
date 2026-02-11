# Security Configuration — Agent Task Breakdown

This document breaks the security configuration plan (`SECURITY-CONFIG-PLAN.md`) into discrete, self-contained tasks that can each be implemented by an agent. Each task includes full context, the exact prompt to give the agent, required tests, and a definition of done.

**Dependency graph:**

```
Task 1 (Core types) ──────────────────────────────┐
                                                   ├── Task 3 (ChatState integration)
Task 2 (Codex config JSON-RPC) ──┬── Task 4 ──────┘         │
                                 │  (Thread start)           │
                                 └── Task 5 ─────────────────┤
                                   (Read config on connect)  │
                                                             ├── Task 6 (SecurityConfigGroup widget)
                                                             ├── Task 7 (ConversationHeader update)
                                                             ├── Task 8 (WorkspaceSettingsPanel)
                                                             ├── Task 9 (Permission dialog Codex)
                                                             ├── Task 10 (Security badge + notifications)
                                                             └── Task 11 (Cleanup)
```

Tasks 1 and 2 can run in parallel. Tasks 6–10 can run in parallel after Task 3 is complete. Task 11 runs last.

---

## Task 1: SecurityConfig and SecurityCapabilities Core Types

### Context

The codebase has a shared types package at `agent_sdk_core/lib/src/types/` that defines types used by all backends. Currently, there is a `PermissionMode` enum in `agent_sdk_core/lib/src/types/session_options.dart` (line 342) with four Claude-specific modes. The Codex backend has a fundamentally different security model with two axes (sandbox mode + approval policy) and enterprise constraints.

This task creates the new sealed type hierarchies that will underpin all security configuration across the app. These are pure data types with serialization — no behavioral changes.

### Existing Files to Understand

- `agent_sdk_core/lib/agent_sdk_core.dart` — barrel export file, currently exports 13 files
- `agent_sdk_core/lib/src/types/session_options.dart` — contains `PermissionMode` enum (lines 342-365) with `fromString` factory and `value` getter
- `agent_sdk_core/test/types/backend_commands_test.dart` — example of the test pattern used in this package (uses `package:test/test.dart`, no Flutter dependency)

### Test Pattern

Tests in `agent_sdk_core/test/` use `package:test/test.dart` (not `flutter_test`). Run with `dart test` from the `agent_sdk_core/` directory. Tests are grouped with `group()` and use standard `expect()` assertions.

### Agent Prompt

```
You are implementing Task 1 of the CC-Insights security configuration revamp. Your job is to create new type definitions in the `agent_sdk_core` package. Read FLUTTER.md first for coding standards.

**What to create:**

1. **New file: `agent_sdk_core/lib/src/types/security_config.dart`**

   Define these types:

   a) `CodexSandboxMode` enum with three values:
      - `readOnly` with wire value `'read-only'`
      - `workspaceWrite` with wire value `'workspace-write'`
      - `dangerFullAccess` with wire value `'danger-full-access'`
      Each value has a `wireValue` string field. Add a `fromWire(String value)` static factory that returns the matching enum value, falling back to `workspaceWrite` for unknown strings.

   b) `CodexApprovalPolicy` enum with four values:
      - `untrusted` / `'untrusted'`
      - `onRequest` / `'on-request'`
      - `onFailure` / `'on-failure'`
      - `never` / `'never'`
      Same pattern as CodexSandboxMode. Fallback: `onRequest`.

   c) `CodexWebSearchMode` enum with three values:
      - `disabled` / `'disabled'`
      - `cached` / `'cached'`
      - `live` / `'live'`
      Same pattern. Fallback: `cached`.

   d) `CodexWorkspaceWriteOptions` immutable class:
      - `bool networkAccess` (default: false)
      - `List<String> writableRoots` (default: const [])
      - `bool excludeSlashTmp` (default: false)
      - `bool excludeTmpdirEnvVar` (default: false)
      - `fromJson(Map<String, dynamic>)` factory using snake_case keys: `network_access`, `writable_roots`, `exclude_slash_tmp`, `exclude_tmpdir_env_var`
      - `toJson()` method returning snake_case keys
      - `copyWith(...)` method
      - Override `==` and `hashCode`

   e) `SecurityConfig` sealed class with `toJson()` method and `fromJson(Map<String, dynamic>)` static factory:
      - `ClaudeSecurityConfig` subclass with `PermissionMode permissionMode` field
        (import PermissionMode from `session_options.dart`)
        - `toJson()` returns `{'type': 'claude', 'permissionMode': permissionMode.value}`
        - Override `==` and `hashCode`
      - `CodexSecurityConfig` subclass with:
        - `CodexSandboxMode sandboxMode`
        - `CodexApprovalPolicy approvalPolicy`
        - `CodexWorkspaceWriteOptions? workspaceWriteOptions`
        - `CodexWebSearchMode? webSearch`
        - `copyWith(...)` method
        - `toJson()` returns `{'type': 'codex', 'sandboxMode': sandboxMode.wireValue, ...}`
        - Static `defaultConfig` const: `CodexSecurityConfig(sandboxMode: workspaceWrite, approvalPolicy: onRequest)`
        - Override `==` and `hashCode`
      - `SecurityConfig.fromJson` dispatches on `json['type']`: `'claude'` → `ClaudeSecurityConfig`, `'codex'` → `CodexSecurityConfig`

2. **New file: `agent_sdk_core/lib/src/types/security_capabilities.dart`**

   Define:

   a) `SecurityCapabilities` sealed class:
      - `ClaudeSecurityCapabilities` subclass:
        - `bool supportsPermissionModeChange` (default: true)
        - `bool supportsSuggestions` (default: true)
      - `CodexSecurityCapabilities` subclass:
        - `List<CodexSandboxMode>? allowedSandboxModes` (null = all allowed)
        - `List<CodexApprovalPolicy>? allowedApprovalPolicies` (null = all allowed)
        - `bool supportsMidSessionChange` (default: true)
        - Method: `bool isSandboxModeAllowed(CodexSandboxMode mode)` — returns true if allowedSandboxModes is null OR contains the mode
        - Method: `bool isApprovalPolicyAllowed(CodexApprovalPolicy policy)` — returns true if allowedApprovalPolicies is null OR contains the policy

3. **Modify: `agent_sdk_core/lib/agent_sdk_core.dart`**
   Add two new exports:
   ```dart
   export 'src/types/security_config.dart';
   export 'src/types/security_capabilities.dart';
   ```

**Tests to create: `agent_sdk_core/test/types/security_config_test.dart`**

Write tests using `package:test/test.dart` (NOT flutter_test). Groups:

1. `CodexSandboxMode.fromWire`:
   - Round-trips all three values (fromWire(wireValue) == original)
   - Returns `workspaceWrite` for unknown string `'unknown'`

2. `CodexApprovalPolicy.fromWire`:
   - Round-trips all four values
   - Returns `onRequest` for unknown string

3. `CodexWebSearchMode.fromWire`:
   - Round-trips all three values
   - Returns `cached` for unknown string

4. `CodexWorkspaceWriteOptions`:
   - `fromJson`/`toJson` round-trip with all fields set
   - Default constructor has expected defaults (networkAccess=false, writableRoots=empty, etc.)
   - `copyWith` preserves unchanged fields and updates specified fields

5. `SecurityConfig` serialization:
   - `CodexSecurityConfig.toJson`/`fromJson` round-trip
   - `ClaudeSecurityConfig.toJson`/`fromJson` round-trip
   - `SecurityConfig.fromJson` dispatches to correct subclass based on `type` field

6. `CodexSecurityConfig.defaultConfig`:
   - Has sandboxMode == workspaceWrite
   - Has approvalPolicy == onRequest

**Tests to create: `agent_sdk_core/test/types/security_capabilities_test.dart`**

1. `CodexSecurityCapabilities.isSandboxModeAllowed`:
   - Returns true for all modes when `allowedSandboxModes` is null
   - Returns true for allowed mode, false for disallowed mode when list is set

2. `CodexSecurityCapabilities.isApprovalPolicyAllowed`:
   - Returns true for all policies when `allowedApprovalPolicies` is null
   - Returns true for allowed policy, false for disallowed policy when list is set

**After implementation:**
- Run `cd agent_sdk_core && dart test` to verify all tests pass
- Run `cd frontend && dart analyze` to check for any analysis errors in downstream packages
```

### Definition of Done

- [x] `security_config.dart` contains all enums, `CodexWorkspaceWriteOptions`, `SecurityConfig` sealed class with both subclasses
- [x] `security_capabilities.dart` contains `SecurityCapabilities` sealed class with both subclasses
- [x] Both files are exported from `agent_sdk_core.dart`
- [x] All 15+ tests pass in `security_config_test.dart` and `security_capabilities_test.dart`
- [x] `dart analyze` shows no errors in `agent_sdk_core/`
- [x] Running `./frontend/run-flutter-test.sh` still passes all existing tests (no regressions)

---

## Task 2: Codex Config JSON-RPC Reader and Writer

### Context

The Codex backend communicates via JSON-RPC through `CodexProcess`. The process already has a `sendRequest(method, params)` method (at `codex_dart_sdk/lib/src/codex_process.dart:112`) that sends arbitrary JSON-RPC requests and returns the result map.

This task adds two new classes for reading and writing Codex security configuration via the `config/read`, `config/write`, `config/batchWrite`, and `config/requirementsRead` JSON-RPC methods. It also handles the `config/warning` notification in `CodexSession`.

### Prerequisite

Task 1 must be complete (the security config types must exist).

### Existing Files to Understand

- `codex_dart_sdk/lib/src/codex_process.dart` — `CodexProcess.sendRequest(String method, Map<String, dynamic> params)` returns `Future<Map<String, dynamic>>`
- `codex_dart_sdk/lib/src/codex_session.dart` — `CodexSession` handles notifications via `_handleNotification(JsonRpcNotification)` which switches on `notification.method`. It has an `_eventsController` for emitting `InsightsEvent` instances. It uses `CodexSession.forTesting(threadId:)` constructor for tests.
- `codex_dart_sdk/test/codex_session_events_test.dart` — test pattern: create `CodexSession.forTesting()`, inject notifications with `session.injectNotification(JsonRpcNotification(...))`, wait with `Future.delayed`, check captured events
- `agent_sdk_core/lib/src/types/insights_events.dart` — `SystemMessageEvent` class with fields: `id`, `timestamp`, `provider`, `raw`, `sessionId`, `message`. There's no `severity` field currently — check if it exists before adding.
- `docs/insights-protocol/11-security-config.md` lines 154-220 — wire format for all config JSON-RPC methods

### Agent Prompt

```
You are implementing Task 2 of the CC-Insights security configuration revamp. Your job is to add Codex config read/write JSON-RPC support to the `codex_dart_sdk` package. Read FLUTTER.md first for coding standards.

**Important:** Task 1 (core types) must be completed already. Verify by checking that `agent_sdk_core/lib/src/types/security_config.dart` exists with `CodexSandboxMode`, `CodexApprovalPolicy`, `CodexWebSearchMode`, `CodexWorkspaceWriteOptions`, and `CodexSecurityConfig`.

**What to create:**

1. **New file: `codex_dart_sdk/lib/src/codex_config.dart`**

   `CodexConfigReader` class:
   - Constructor takes `CodexProcess` instance
   - `Future<CodexSecurityConfig> readSecurityConfig()`:
     - Calls `_process.sendRequest('config/read', {})`
     - Parses `result['config']` map
     - Extracts `sandbox_mode` → `CodexSandboxMode.fromWire()`
     - Extracts `approval_policy` → `CodexApprovalPolicy.fromWire()`
     - Extracts `sandbox_workspace_write` → `CodexWorkspaceWriteOptions.fromJson()` (if present)
     - Extracts `web_search` → `CodexWebSearchMode.fromWire()` (if present)
     - Returns `CodexSecurityConfig`
   - `Future<CodexSecurityCapabilities> readCapabilities()`:
     - Calls `_process.sendRequest('config/requirementsRead', {})`
     - Parses `result['requirements']` map (may be null)
     - Extracts `allowedSandboxModes` list (if present) → map each string to `CodexSandboxMode.fromWire()`
     - Extracts `allowedApprovalPolicies` list (if present) → map each string to `CodexApprovalPolicy.fromWire()`
     - Returns `CodexSecurityCapabilities` with parsed lists (or null if no requirements)

2. **New file: `codex_dart_sdk/lib/src/codex_config_writer.dart`**

   `CodexConfigWriteResult` class:
   - Fields: `String status`, `String? filePath`, `String? version`, `String? overrideMessage`, `dynamic effectiveValue`
   - Computed: `bool get wasOverridden => status == 'okOverridden'`
   - Factory `fromJson(Map<String, dynamic>)`:
     - `status` from `json['status']`
     - `filePath` from `json['filePath']`
     - `version` from `json['version']`
     - `overrideMessage` from `json['overriddenMetadata']?['message']`
     - `effectiveValue` from `json['overriddenMetadata']?['effectiveValue']`

   `CodexConfigEdit` class:
   - Fields: `String keyPath`, `dynamic value`, `String mergeStrategy` (default: 'replace')
   - `toJson()` returns `{'keyPath': keyPath, 'value': value, 'mergeStrategy': mergeStrategy}`

   `CodexConfigWriter` class:
   - Constructor takes `CodexProcess`
   - `Future<CodexConfigWriteResult> writeValue({required String keyPath, required dynamic value, String mergeStrategy = 'replace'})`:
     - Calls `_process.sendRequest('config/write', {'keyPath': keyPath, 'value': value, 'mergeStrategy': mergeStrategy})`
     - Returns `CodexConfigWriteResult.fromJson(result)`
   - `Future<CodexConfigWriteResult> batchWrite(List<CodexConfigEdit> edits)`:
     - Calls `_process.sendRequest('config/batchWrite', {'edits': edits.map((e) => e.toJson()).toList()})`
   - Convenience methods:
     - `setSandboxMode(CodexSandboxMode mode)` → writeValue with keyPath 'sandbox_mode'
     - `setApprovalPolicy(CodexApprovalPolicy policy)` → writeValue with keyPath 'approval_policy'
     - `setWorkspaceWriteOptions(CodexWorkspaceWriteOptions options)` → writeValue with keyPath 'sandbox_workspace_write', mergeStrategy 'upsert'

3. **Modify: `codex_dart_sdk/lib/src/codex_session.dart`**

   In `_handleNotification()`, add a case for `'config/warning'`:
   ```dart
   case 'config/warning':
     _handleConfigWarning(notification.params);
   ```

   Add method:
   ```dart
   void _handleConfigWarning(Map<String, dynamic> params) {
     final summary = params['summary'] as String? ?? '';
     _eventsController.add(SystemMessageEvent(
       id: _nextEventId(),
       timestamp: DateTime.now(),
       provider: BackendProvider.codex,
       raw: params,
       sessionId: threadId,
       message: summary,
     ));
   }
   ```

   Note: Check what `SystemMessageEvent` looks like in `agent_sdk_core/lib/src/types/insights_events.dart`. If it doesn't have a `message` field, look for the correct event type or field name. The goal is to emit an event that surfaces the warning text to the frontend.

4. **Modify: `codex_dart_sdk/lib/codex_sdk.dart`** (barrel export)
   Export the new files:
   ```dart
   export 'src/codex_config.dart';
   export 'src/codex_config_writer.dart';
   ```

**Tests to create: `codex_dart_sdk/test/codex_config_test.dart`**

Use `package:test/test.dart`. For testing, you'll need a mock CodexProcess. Look at how existing tests in `codex_dart_sdk/test/codex_session_events_test.dart` work — they use `CodexSession.forTesting()`. For config tests, you'll need to mock `sendRequest`. Create a minimal `MockCodexProcess` that implements only `sendRequest` to return canned responses.

Tests:

1. `CodexConfigReader.readSecurityConfig` — parses full config response with all fields
2. `CodexConfigReader.readSecurityConfig` — handles missing fields, falls back to defaults
3. `CodexConfigReader.readSecurityConfig` — parses workspace-write options
4. `CodexConfigReader.readCapabilities` — returns default capabilities when no requirements
5. `CodexConfigReader.readCapabilities` — parses restricted sandbox modes and approval policies
6. `CodexConfigWriter.writeValue` — constructs correct JSON-RPC params
7. `CodexConfigWriter.batchWrite` — sends array of edits
8. `CodexConfigWriter.setSandboxMode` — sends correct keyPath and value
9. `CodexConfigWriter.setApprovalPolicy` — sends correct keyPath and value
10. `CodexConfigWriteResult.fromJson` — parses 'ok' status correctly
11. `CodexConfigWriteResult.fromJson` — parses 'okOverridden' status with metadata
12. `CodexConfigWriter.setWorkspaceWriteOptions` — sends correct structure

**Test: `codex_dart_sdk/test/codex_session_config_warning_test.dart`**

Using the existing `CodexSession.forTesting()` pattern:
1. Inject a `config/warning` notification → verify a SystemMessageEvent (or appropriate event type) is emitted with the warning summary text

**After implementation:**
- Run `cd codex_dart_sdk && dart test` to verify all tests pass
- Run `cd agent_sdk_core && dart test` to verify no regressions
- Run `./frontend/run-flutter-test.sh` to verify no frontend regressions
```

### Definition of Done

- [x] `codex_config.dart` contains `CodexConfigReader` with `readSecurityConfig()` and `readCapabilities()`
- [x] `codex_config_writer.dart` contains `CodexConfigWriter`, `CodexConfigWriteResult`, `CodexConfigEdit`
- [x] `codex_session.dart` handles `config/warning` notifications
- [x] Both new files are exported from `codex_sdk.dart`
- [x] All 13 tests pass in config tests
- [x] `dart test` passes in both `codex_dart_sdk/` and `agent_sdk_core/`
- [x] `./frontend/run-flutter-test.sh` passes

---

## Task 3: ChatState Security Config Integration and Persistence

### Context

`ChatState` (at `frontend/lib/models/chat.dart`) currently has a `_permissionMode` field (line 276) of type `PermissionMode`. This field is:
- Initialized from `RuntimeConfig.instance.defaultPermissionMode`
- Set via `setPermissionMode(PermissionMode mode)` (line 611)
- Sent to the backend in `startSession()` via `SessionOptions(permissionMode: _sdkPermissionMode)` (line 902)
- Persisted to `ChatMeta.permissionMode` (a string field) in `_saveMeta()` (line 1684)
- Synced from permission responses via `_syncPermissionModeFromResponse()` (line 1204)
- Converted to SDK type via `_sdkPermissionMode` getter (line 1336)

`ChatMeta` (at `frontend/lib/services/persistence_models.dart:98`) has a `permissionMode` string field that is serialized/deserialized in `toJson()`/`fromJson()`.

This task replaces the single `_permissionMode` field with a backend-aware `SecurityConfig` while maintaining backward compatibility for Claude chats.

### Prerequisites

Task 1 must be complete.

### Existing Files to Modify

- `frontend/lib/models/chat.dart` — `ChatState` class
- `frontend/lib/services/persistence_models.dart` — `ChatMeta` class
- `agent_sdk_core/lib/src/types/session_options.dart` — `SessionOptions` class (add `codexSecurityConfig` field)

### Agent Prompt

```
You are implementing Task 3 of the CC-Insights security configuration revamp. Your job is to integrate backend-aware SecurityConfig into ChatState and persistence. Read FLUTTER.md and TESTING.md first for coding standards and test patterns.

**Important:** Task 1 (core types) must be completed already. Verify that `agent_sdk_core/lib/src/types/security_config.dart` exists.

**Understanding the current code:**

Read these files thoroughly before making changes:
- `frontend/lib/models/chat.dart` — Focus on:
  - `_permissionMode` field (line ~276)
  - `setPermissionMode()` method (line ~611)
  - `_sdkPermissionMode` getter (line ~1336)
  - `startSession()` method (line ~841), specifically how SessionOptions is constructed (line ~900)
  - `_saveMeta()` method (line ~1677), specifically how ChatMeta is created (line ~1680)
  - `_syncPermissionModeFromResponse()` (line ~1204)
  - `restoreFromMeta()` (line ~1576)
- `frontend/lib/services/persistence_models.dart` — `ChatMeta` class (line ~98)
- `agent_sdk_core/lib/src/types/session_options.dart` — `SessionOptions` class

**Changes to make:**

1. **`agent_sdk_core/lib/src/types/session_options.dart`** — Add optional Codex security config to SessionOptions:

   Add a new field `CodexSecurityConfig? codexSecurityConfig` to the `SessionOptions` constructor. Import `security_config.dart`. This field will be used by the Codex backend to pass sandbox/approval settings to thread/start. It should NOT be added to `toJson()` (SessionOptions.toJson is for Claude CLI only). Add it to `validateForCodex()` warnings if relevant fields conflict.

2. **`frontend/lib/models/chat.dart`** — Replace `_permissionMode` with `SecurityConfig`:

   a) Add a new field:
   ```dart
   /// Backend-specific security configuration.
   late SecurityConfig _securityConfig;
   ```

   b) Initialize it in the constructor body based on the default backend:
   ```dart
   ChatState(this._data) {
     final defaultBackend = RuntimeConfig.instance.defaultBackend;
     if (defaultBackend == sdk.BackendType.codex) {
       _securityConfig = const sdk.CodexSecurityConfig(
         sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
         approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
       );
     } else {
       _securityConfig = sdk.ClaudeSecurityConfig(
         permissionMode: sdk.PermissionMode.fromString(
           RuntimeConfig.instance.defaultPermissionMode,
         ),
       );
     }
   }
   ```

   c) Add getter:
   ```dart
   SecurityConfig get securityConfig => _securityConfig;
   ```

   d) Keep `permissionMode` getter for backward compatibility (the conversation header still uses it for Claude):
   ```dart
   PermissionMode get permissionMode {
     if (_securityConfig case sdk.ClaudeSecurityConfig(:final permissionMode)) {
       return PermissionMode.fromApiName(permissionMode.value);
     }
     return PermissionMode.defaultMode;
   }
   ```

   e) Keep `setPermissionMode()` working — it should delegate to `setSecurityConfig`:
   ```dart
   void setPermissionMode(PermissionMode mode) {
     final sdkMode = _toSdkPermissionMode(mode);
     setSecurityConfig(sdk.ClaudeSecurityConfig(permissionMode: sdkMode));
   }
   ```

   f) Add new `setSecurityConfig(SecurityConfig config)` method:
   ```dart
   void setSecurityConfig(sdk.SecurityConfig config) {
     if (_securityConfig == config) return;
     _securityConfig = config;
     _scheduleMetaSave();

     switch (config) {
       case sdk.ClaudeSecurityConfig(:final permissionMode):
         if (_capabilities.supportsPermissionModeChange && _transport != null) {
           final sessionId = _transport!.sessionId ?? '';
           _transport!.send(sdk.SetPermissionModeCommand(
             sessionId: sessionId,
             mode: permissionMode.value,
           ));
         }
       case sdk.CodexSecurityConfig():
         // Mid-session Codex config changes will be handled in a future task
         break;
     }

     notifyListeners();
   }
   ```

   g) Remove `_permissionMode` field entirely. Remove `_sdkPermissionMode` getter. Refactor any references to use `_securityConfig` instead.

   h) Update `_syncPermissionModeFromResponse()` to check backend type:
   ```dart
   void _syncPermissionModeFromResponse(
     String? toolName,
     List<dynamic>? updatedPermissions,
   ) {
     // Only applies to Claude chats
     if (_securityConfig is! sdk.ClaudeSecurityConfig) return;

     if (updatedPermissions != null) {
       for (final perm in updatedPermissions) {
         if (perm is Map<String, dynamic> && perm['type'] == 'setMode') {
           final mode = perm['mode'] as String?;
           if (mode != null) {
             _securityConfig = sdk.ClaudeSecurityConfig(
               permissionMode: sdk.PermissionMode.fromString(mode),
             );
             _scheduleMetaSave();
             return;
           }
         }
       }
     }

     if (toolName == 'ExitPlanMode') {
       _securityConfig = const sdk.ClaudeSecurityConfig(
         permissionMode: sdk.PermissionMode.defaultMode,
       );
       _scheduleMetaSave();
     }
   }
   ```

   i) Update `startSession()` — pass codexSecurityConfig in SessionOptions:
   ```dart
   options: sdk.SessionOptions(
     model: model.id.isEmpty ? null : model.id,
     permissionMode: _securityConfig is sdk.ClaudeSecurityConfig
         ? (_securityConfig as sdk.ClaudeSecurityConfig).permissionMode
         : null,
     codexSecurityConfig: _securityConfig is sdk.CodexSecurityConfig
         ? _securityConfig as sdk.CodexSecurityConfig
         : null,
     resume: _lastSessionId,
     // ... rest unchanged
   ),
   ```

3. **`frontend/lib/services/persistence_models.dart`** — Add Codex fields to ChatMeta:

   Add new optional fields to `ChatMeta`:
   ```dart
   final String? codexSandboxMode;
   final String? codexApprovalPolicy;
   final Map<String, dynamic>? codexWorkspaceWriteOptions;
   final String? codexWebSearch;
   ```

   Update `toJson()` to include them when non-null.
   Update `fromJson()` to read them.
   Update `copyWith()` to support them.

4. **`frontend/lib/models/chat.dart`** — Update `_saveMeta()`:

   When creating ChatMeta, include the Codex security fields:
   ```dart
   final meta = ChatMeta(
     model: _model.id,
     backendType: _backendTypeValue,
     hasStarted: _hasStarted,
     permissionMode: _securityConfig is sdk.ClaudeSecurityConfig
         ? (_securityConfig as sdk.ClaudeSecurityConfig).permissionMode.value
         : 'default',
     // Add Codex fields
     codexSandboxMode: _securityConfig is sdk.CodexSecurityConfig
         ? (_securityConfig as sdk.CodexSecurityConfig).sandboxMode.wireValue
         : null,
     codexApprovalPolicy: _securityConfig is sdk.CodexSecurityConfig
         ? (_securityConfig as sdk.CodexSecurityConfig).approvalPolicy.wireValue
         : null,
     codexWorkspaceWriteOptions: _securityConfig is sdk.CodexSecurityConfig
         ? (_securityConfig as sdk.CodexSecurityConfig).workspaceWriteOptions?.toJson()
         : null,
     codexWebSearch: _securityConfig is sdk.CodexSecurityConfig
         ? (_securityConfig as sdk.CodexSecurityConfig).webSearch?.wireValue
         : null,
     // ... rest unchanged
   );
   ```

5. **Add a method to restore security config from meta** — either in the constructor or as a new `restoreSecurityConfig` method:

   When loading a chat from persistence, determine the security config from meta fields:
   - If `backendType == 'codex'` and `codexSandboxMode` is present → create `CodexSecurityConfig`
   - Otherwise → create `ClaudeSecurityConfig` from `permissionMode`

   Find where ChatState is restored from persisted data and integrate this. Look for how `_permissionMode` is currently set during restoration.

**Tests to create/modify:**

File: `frontend/test/models/chat_security_config_test.dart`

Use the existing test patterns from `frontend/test/`. Import `test_helpers.dart` for `safePumpAndSettle` etc. These are unit tests (no widget tests needed).

Tests:

1. New Claude chat initializes with `ClaudeSecurityConfig` and default permission mode
2. New Codex chat initializes with `CodexSecurityConfig.defaultConfig` when default backend is codex
3. `setPermissionMode()` on Claude chat updates `securityConfig` to `ClaudeSecurityConfig`
4. `setSecurityConfig()` with `CodexSecurityConfig` updates state and notifies listeners
5. `permissionMode` getter returns `PermissionMode.defaultMode` for Codex chats (backward compat)
6. Security config round-trips through ChatMeta serialization (Claude)
7. Security config round-trips through ChatMeta serialization (Codex — all fields)
8. Security config round-trips through ChatMeta serialization (Codex — with workspace-write options)
9. `_syncPermissionModeFromResponse` does nothing for Codex chats
10. `_syncPermissionModeFromResponse` updates Claude chat correctly
11. Restoring chat from meta.json with old `permissionMode` field works (migration)
12. Restoring chat from meta.json with Codex fields creates correct CodexSecurityConfig

**Important test considerations:**
- Use `frontend/test/test_helpers.dart` helpers (it re-exports from `lib/testing/test_helpers.dart`)
- ChatState can be created with `ChatState(ChatData.create(name: 'test', worktreeRoot: '/tmp'))` for unit tests
- Use `addListener` with a counter to verify `notifyListeners()` is called

**After implementation:**
- Run `./frontend/run-flutter-test.sh` to verify ALL tests pass (both new and existing)
- Run `dart analyze` in `frontend/` directory
- Verify the existing permission_dialog_test.dart still passes (it creates ChatState instances)
```

### Definition of Done

- [x] `_permissionMode` field removed from ChatState, replaced with `_securityConfig`
- [x] `setSecurityConfig()` method exists and works for both Claude and Codex configs
- [x] `setPermissionMode()` still works (delegates to `setSecurityConfig`)
- [x] `permissionMode` getter returns correct value for both backends
- [x] `SessionOptions` has `codexSecurityConfig` field
- [x] `ChatMeta` has Codex security fields, serializes/deserializes correctly
- [x] `_saveMeta()` persists correct fields for both backends
- [x] `_syncPermissionModeFromResponse()` only affects Claude chats
- [x] All 12+ new tests pass
- [x] ALL existing tests pass with no regressions (run `./frontend/run-flutter-test.sh`)

---

## Task 4: Pass Security Config to Codex Thread Start

### Context

When a Codex session is created, `CodexBackend._startThread()` (at `codex_dart_sdk/lib/src/codex_backend.dart`) sends a `thread/start` or `thread/resume` JSON-RPC request. Currently it only passes `cwd` and `model`. The Codex protocol supports `sandbox` and `approvalPolicy` parameters in these requests, but they are never sent.

### Prerequisites

Tasks 1 and 3 must be complete.

### Agent Prompt

```
You are implementing Task 4 of the CC-Insights security configuration revamp. Your job is to pass Codex security config to thread/start and thread/resume. Read FLUTTER.md first.

**Read these files first:**
- `codex_dart_sdk/lib/src/codex_backend.dart` — Focus on `_startThread()` method and `createSession()`
- `agent_sdk_core/lib/src/types/session_options.dart` — `SessionOptions` class, specifically the `codexSecurityConfig` field (added in Task 3)

**Changes to make:**

1. **`codex_dart_sdk/lib/src/codex_backend.dart`** — Modify `_startThread()` to extract and pass security config:

   Read the `SessionOptions.codexSecurityConfig` field. If present, add `'sandbox'` and `'approvalPolicy'` to the JSON-RPC params:

   ```dart
   final securityConfig = options?.codexSecurityConfig;

   // In thread/start params:
   result = await _process.sendRequest('thread/start', {
     'cwd': cwd,
     if (resolvedModel != null) 'model': resolvedModel,
     if (securityConfig != null) ...{
       'sandbox': securityConfig.sandboxMode.wireValue,
       'approvalPolicy': securityConfig.approvalPolicy.wireValue,
     },
   });

   // Same for thread/resume params
   ```

   Import the security config types from agent_sdk_core.

**Tests to create: `codex_dart_sdk/test/codex_backend_security_test.dart`**

You'll need to test that `_startThread` includes the right params. Since `_startThread` is private, test via the public `createSession()` method. You'll need a mock `CodexProcess` that captures the params sent to `sendRequest`. Look at how existing tests create mock processes.

If mocking is too complex, write integration-style tests that verify the params structure at the `sendRequest` level.

Tests:
1. `thread/start` includes `sandbox` and `approvalPolicy` when `codexSecurityConfig` is provided in `SessionOptions`
2. `thread/start` omits `sandbox` and `approvalPolicy` when `codexSecurityConfig` is null
3. `thread/resume` includes `sandbox` and `approvalPolicy` when config provided
4. SessionOptions without `codexSecurityConfig` is backward compatible (params unchanged)

**After implementation:**
- Run `cd codex_dart_sdk && dart test`
- Run `./frontend/run-flutter-test.sh`
```

### Definition of Done

- [x] `_startThread()` passes `sandbox` and `approvalPolicy` in thread/start when `codexSecurityConfig` is provided
- [x] `_startThread()` passes `sandbox` and `approvalPolicy` in thread/resume when `codexSecurityConfig` is provided
- [x] Params are omitted when `codexSecurityConfig` is null
- [x] All 4 tests pass
- [x] `dart test` passes in `codex_dart_sdk/`
- [x] `./frontend/run-flutter-test.sh` passes

---

## Task 5: Read Config and Requirements on Codex Backend Connect

### Context

When a `CodexBackend` is created (via `CodexBackend.create()` at `codex_dart_sdk/lib/src/codex_backend.dart`), it should read the current Codex configuration and enterprise requirements so the frontend knows what security settings are active and which options are locked.

### Prerequisites

Tasks 1 and 2 must be complete.

### Agent Prompt

```
You are implementing Task 5 of the CC-Insights security configuration revamp. Your job is to read Codex config and enterprise requirements when the backend connects. Read FLUTTER.md first.

**Read these files first:**
- `codex_dart_sdk/lib/src/codex_backend.dart` — Focus on `create()` factory and class structure
- `codex_dart_sdk/lib/src/codex_config.dart` — `CodexConfigReader` (created in Task 2)
- `frontend/lib/services/backend_service.dart` — How backends are created and managed

**Changes to make:**

1. **`codex_dart_sdk/lib/src/codex_backend.dart`**:

   Add fields:
   ```dart
   CodexSecurityConfig? _currentConfig;
   CodexSecurityCapabilities? _capabilities;

   /// Current security configuration read from the Codex app-server.
   CodexSecurityConfig? get currentSecurityConfig => _currentConfig;

   /// Security capabilities (enterprise restrictions).
   CodexSecurityCapabilities get securityCapabilities =>
       _capabilities ?? const CodexSecurityCapabilities();
   ```

   Modify `create()` to read config after process starts:
   ```dart
   static Future<CodexBackend> create({String? executablePath}) async {
     final process = await CodexProcess.start(
       CodexProcessConfig(executablePath: executablePath),
     );
     final backend = CodexBackend._(process: process);
     await backend._readInitialConfig();
     return backend;
   }

   Future<void> _readInitialConfig() async {
     try {
       final reader = CodexConfigReader(_process);
       _currentConfig = await reader.readSecurityConfig();
       _capabilities = await reader.readCapabilities();
     } catch (e) {
       // Config read is best-effort; fall back to defaults
       SdkLogger.instance.warning('Failed to read Codex config: $e');
       _currentConfig = CodexSecurityConfig.defaultConfig;
       _capabilities = const CodexSecurityCapabilities();
     }
   }
   ```

   Also expose a `CodexConfigWriter` getter for mid-session config writes:
   ```dart
   /// Config writer for mid-session changes.
   CodexConfigWriter get configWriter => CodexConfigWriter(_process);
   ```

2. **`frontend/lib/services/backend_service.dart`**:

   Add convenience methods to surface Codex security info:
   ```dart
   /// Returns the current security config for the Codex backend.
   CodexSecurityConfig? get codexSecurityConfig {
     final backend = _backends[BackendType.codex];
     if (backend is CodexBackend) {
       return backend.currentSecurityConfig;
     }
     return null;
   }

   /// Returns security capabilities for the Codex backend.
   CodexSecurityCapabilities get codexSecurityCapabilities {
     final backend = _backends[BackendType.codex];
     if (backend is CodexBackend) {
       return backend.securityCapabilities;
     }
     return const CodexSecurityCapabilities();
   }
   ```

   Import the necessary types from codex_sdk.

**Tests:**

Since `CodexBackend.create()` spawns a real process, the config read tests need a mock process approach. Create tests in `codex_dart_sdk/test/codex_backend_config_test.dart`:

1. If CodexBackend has a test constructor (check!), use it. Otherwise, test `_readInitialConfig` logic by testing `CodexConfigReader` directly (already tested in Task 2).

2. For `BackendService`, create a unit test in `frontend/test/services/backend_service_security_test.dart`:
   - Test that `codexSecurityConfig` returns null when no Codex backend is active
   - Test that `codexSecurityCapabilities` returns default capabilities when no Codex backend

**After implementation:**
- Run `cd codex_dart_sdk && dart test`
- Run `./frontend/run-flutter-test.sh`
```

### Definition of Done

- [x] `CodexBackend` reads config and requirements on creation
- [x] Config read failure falls back to defaults gracefully
- [x] `currentSecurityConfig` and `securityCapabilities` getters expose the read values
- [x] `configWriter` getter provides write access
- [x] `BackendService` has convenience methods for Codex security info
- [x] Tests pass in both `codex_dart_sdk/` and `frontend/`
- [x] `./frontend/run-flutter-test.sh` passes

---

## Task 6: SecurityConfigGroup Widget

### Context

The conversation header currently shows a single `CompactDropdown` for permissions regardless of backend. For Codex, this needs to be replaced with a grouped widget containing two dropdowns: sandbox mode and approval policy.

The `CompactDropdown` widget is at `frontend/lib/panels/compact_dropdown.dart`. The mockups at `docs/mocks/security-config-mockups.html` show the visual design (sections 2-4, 8).

### Prerequisites

Task 3 must be complete (ChatState has `securityConfig`).

### Agent Prompt

```
You are implementing Task 6 of the CC-Insights security configuration revamp. Your job is to create the SecurityConfigGroup widget — the grouped Codex security dropdowns. Read FLUTTER.md and TESTING.md first.

**Study these files first:**
- `docs/mocks/security-config-mockups.html` — Visual reference (sections 2, 3, 4, 8)
- `docs/insights-protocol/11-security-config.md` — lines 248-302 for dropdown specs
- `frontend/lib/panels/compact_dropdown.dart` — The existing dropdown widget pattern to match
- `frontend/lib/panels/conversation_header.dart` — Where this widget will be used

**What to create:**

**New file: `frontend/lib/widgets/security_config_group.dart`**

A stateless widget that renders the Codex sandbox mode and approval policy dropdowns inside a grouped container with a shield icon.

```dart
/// Grouped Codex security dropdowns: sandbox mode + approval policy.
///
/// Renders as: [ 🛡 Sandbox Mode ▾ | Ask: Policy ▾ ]
///
/// Visual states:
/// - Normal: outline-variant border
/// - Danger (dangerFullAccess or never): red border, red text
/// - Disabled: reduced opacity, no interaction
class SecurityConfigGroup extends StatelessWidget {
  const SecurityConfigGroup({
    super.key,
    required this.config,
    required this.capabilities,
    required this.onConfigChanged,
    this.isEnabled = true,
  });

  final CodexSecurityConfig config;
  final CodexSecurityCapabilities capabilities;
  final ValueChanged<CodexSecurityConfig> onConfigChanged;
  final bool isEnabled;
}
```

**Layout structure:**
```
Container (rounded border, inline-flex)
├── Icon(Icons.shield, size: 14)  // Shield icon
├── _SandboxModeDropdown          // Left dropdown
├── VerticalDivider               // Thin divider
└── _ApprovalPolicyDropdown       // Right dropdown
```

**_SandboxModeDropdown** — Uses PopupMenuButton or similar:
- Shows current mode label: "Read Only", "Workspace Write", "Full Access"
- Popup items with icons and descriptions:
  | Icon | Label | Description |
  |------|-------|-------------|
  | Icons.visibility | Read Only | No edits, no commands |
  | Icons.edit_note | Workspace Write | Edits + commands in workspace |
  | Icons.lock_open | Full Access | No restrictions (dangerous) |
- Enterprise-locked items: grayed out (opacity 0.35), not selectable, show lock icon + "Admin" badge
- Separator, then "Workspace settings..." entry (onTap will be wired in Task 8)
- Selected item shown with primary color

**_ApprovalPolicyDropdown** — Uses PopupMenuButton:
- Shows current policy: "Ask: Untrusted", "Ask: On Request", "Ask: On Failure", "Ask: Never"
- Popup items with icons and descriptions:
  | Icon | Label | Description |
  |------|-------|-------------|
  | Icons.gpp_good | Untrusted | Prompt before commands |
  | Icons.front_hand | On Request | Prompt for outside workspace |
  | Icons.replay | On Failure | Only prompt on failure |
  | Icons.dangerous | Never | Skip all prompts (red text) |
- Enterprise-locked items: grayed out, not selectable, show lock badge

**Danger state styling:**
- Border turns red when `config.sandboxMode == dangerFullAccess` OR `config.approvalPolicy == never`
- Text turns red + bold for the dangerous dropdown value
- Shield icon turns red

**Interaction:**
- Selecting a sandbox mode calls `onConfigChanged` with a new `CodexSecurityConfig` (using `config.copyWith(sandboxMode: newMode)`)
- Selecting an approval policy calls `onConfigChanged` with `config.copyWith(approvalPolicy: newPolicy)`
- Locked items are not selectable

**Colors and sizes:**
- Match the existing `CompactDropdown` styling (11px font, same padding/gap pattern)
- Use `colorScheme.outlineVariant` for normal border
- Use `Colors.red` or `colorScheme.error` for danger state
- Use `colorScheme.primary` for selected items

**Test keys:**
Define a `SecurityConfigGroupKeys` class with const Key values for:
- `group` — the container
- `sandboxDropdown`, `approvalDropdown`
- `sandboxMenuItem(CodexSandboxMode)`, `approvalMenuItem(CodexApprovalPolicy)`

**Tests to create: `frontend/test/widget/security_config_group_test.dart`**

Use flutter_test with `safePumpAndSettle` from test_helpers.

1. Renders sandbox mode label and approval policy label
2. Tapping sandbox dropdown shows all three mode options
3. Selecting a sandbox mode calls `onConfigChanged` with updated config (verify sandboxMode changed, approvalPolicy unchanged)
4. Enterprise-locked sandbox mode is not selectable (tap doesn't call onConfigChanged)
5. Enterprise-locked sandbox mode shows lock icon
6. Tapping approval dropdown shows all four policy options
7. Selecting a policy calls `onConfigChanged` with updated config
8. Danger state (dangerFullAccess) shows red border on container
9. Danger state (never policy) shows red text on the "Never" label
10. Disabled state (isEnabled=false) prevents interaction

**After implementation:**
- Run `./frontend/run-flutter-test.sh` to verify ALL tests pass
```

### Definition of Done

- [x] `security_config_group.dart` renders both dropdowns with icons and descriptions
- [x] Enterprise-locked items are visually distinct and not selectable
- [x] Danger state shows red visual indicators
- [x] `onConfigChanged` is called with correct updated config on selection
- [x] Test keys defined for testability
- [x] All 10 widget tests pass
- [x] `./frontend/run-flutter-test.sh` passes (no regressions)

---

## Task 7: ConversationHeader Backend-Aware Rendering

### Context

The conversation header (at `frontend/lib/panels/conversation_header.dart`) currently always shows a single `CompactDropdown` for permissions (lines 175-188). It needs to show the `SecurityConfigGroup` widget for Codex chats and keep the existing dropdown for Claude chats.

### Prerequisites

Tasks 3 and 6 must be complete.

### Agent Prompt

```
You are implementing Task 7 of the CC-Insights security configuration revamp. Your job is to make the ConversationHeader render backend-specific security controls. Read FLUTTER.md first.

**Read these files first:**
- `frontend/lib/panels/conversation_header.dart` — The full file, especially lines 113-201 where the Row children are built
- `frontend/lib/widgets/security_config_group.dart` — The widget created in Task 6
- `frontend/lib/models/chat.dart` — `ChatState.securityConfig`, `ChatState.setSecurityConfig()`, `ChatState.setPermissionMode()`, `ChatState.model.backend`

**Changes to make:**

**`frontend/lib/panels/conversation_header.dart`**:

Replace the single permissions CompactDropdown (lines ~175-188) with backend-conditional rendering:

```dart
// Backend-specific security controls
if (chat.model.backend == sdk.BackendType.codex) ...[
  Builder(
    builder: (context) {
      final config = chat.securityConfig;
      if (config is! sdk.CodexSecurityConfig) {
        return const SizedBox.shrink();
      }
      return SecurityConfigGroup(
        config: config,
        capabilities: backendService.codexSecurityCapabilities,
        isEnabled: true,
        onConfigChanged: (newConfig) {
          chat.setSecurityConfig(newConfig);
        },
      );
    },
  ),
] else ...[
  // Claude: existing single dropdown (unchanged)
  CompactDropdown(
    value: chat.permissionMode.label,
    items: PermissionMode.values.map((m) => m.label).toList(),
    tooltip: 'Permissions',
    onChanged: (value) {
      final mode = PermissionMode.values.firstWhere(
        (m) => m.label == value,
        orElse: () => PermissionMode.defaultMode,
      );
      chat.setPermissionMode(mode);
    },
  ),
],
```

Import `SecurityConfigGroup` and the SDK types needed.

Note: `backendService` is already available at the top of the build method (line 83).

**Tests to create: `frontend/test/widget/conversation_header_test.dart`**

These are widget tests. You'll need to create a minimal test widget wrapping ConversationHeader with the required providers (BackendService, CliAvailabilityService). Look at how other widget tests in `frontend/test/widget/` set up providers.

1. Claude chat shows single permissions dropdown (find CompactDropdown with tooltip 'Permissions')
2. Codex chat shows SecurityConfigGroup widget (find SecurityConfigGroup)
3. Claude dropdown changes call setPermissionMode (verify via mock or listener)
4. Codex group changes call setSecurityConfig (verify via mock or listener)

**After implementation:**
- Run `./frontend/run-flutter-test.sh` to verify ALL tests pass
```

### Definition of Done

- [x] Codex chats render `SecurityConfigGroup` instead of single permissions dropdown
- [x] Claude chats still render the existing permissions dropdown (unchanged)
- [x] Correct callbacks are wired (setSecurityConfig for Codex, setPermissionMode for Claude)
- [x] All 4 tests pass
- [x] `./frontend/run-flutter-test.sh` passes (no regressions)

---

## Task 8: WorkspaceSettingsPanel Widget

### Context

When the user clicks "Workspace settings..." in the sandbox mode dropdown, a panel/dialog should appear with fine-grained workspace-write settings: network access toggle, temp directory exclusions, additional writable paths, and web search mode.

The mockup is at `docs/mocks/security-config-mockups.html` section 5.

### Prerequisites

Task 6 must be complete (SecurityConfigGroup exists with the "Workspace settings..." item).

### Agent Prompt

```
You are implementing Task 8 of the CC-Insights security configuration revamp. Your job is to create the WorkspaceSettingsPanel widget. Read FLUTTER.md and TESTING.md first.

**Study these files first:**
- `docs/mocks/security-config-mockups.html` — Section 5: Workspace Write Settings
- `docs/insights-protocol/11-security-config.md` — lines 304-311
- `frontend/lib/widgets/security_config_group.dart` — Where the "Workspace settings..." action is triggered

**What to create:**

**New file: `frontend/lib/widgets/workspace_settings_panel.dart`**

A StatefulWidget shown as a dialog or bottom sheet when "Workspace settings..." is clicked.

```dart
/// Fine-grained Codex workspace-write sandbox settings panel.
///
/// Shows toggles and controls for:
/// - Network access
/// - Temp directory exclusions
/// - Additional writable paths
/// - Web search mode
class WorkspaceSettingsPanel extends StatefulWidget {
  const WorkspaceSettingsPanel({
    super.key,
    required this.options,
    required this.webSearch,
    required this.onOptionsChanged,
    required this.onWebSearchChanged,
  });

  final CodexWorkspaceWriteOptions options;
  final CodexWebSearchMode? webSearch;
  final ValueChanged<CodexWorkspaceWriteOptions> onOptionsChanged;
  final ValueChanged<CodexWebSearchMode> onWebSearchChanged;
}
```

**Layout (matching the mockup):**
```
Dialog/Panel
├── Header: "Workspace Write Settings" with tune icon
├── Network section:
│   ├── Label: "Network"
│   └── Row: "Network access" | Switch toggle | "Enabled/Disabled"
│   └── Hint: "Allow commands to access the network"
├── Divider
├── Temp directories section:
│   ├── Label: "Temp directories"
│   ├── Row: "Exclude /tmp" | Switch toggle
│   └── Row: "Exclude $TMPDIR" | Switch toggle
├── Divider
├── Writable paths section:
│   ├── Label: "Additional writable paths"
│   ├── List of paths with remove (X) button each
│   └── "Add path..." row with add (+) button
├── Divider
└── Web search section:
    ├── Label: "Web search"
    └── Row: "Search mode" | Dropdown (Disabled/Cached/Live)
```

**Behavior:**
- Each toggle immediately calls `onOptionsChanged` with updated `CodexWorkspaceWriteOptions` (using `copyWith`)
- "Add path..." opens a simple text input dialog
- Remove button calls `onOptionsChanged` with the path removed from `writableRoots`
- Web search dropdown calls `onWebSearchChanged`

**Presenting the panel:**
Also update `SecurityConfigGroup` to show this panel when "Workspace settings..." is tapped. Use `showDialog()` to present it. The panel should be a dialog with reasonable width (~400px) and scrollable content.

**Tests to create: `frontend/test/widget/workspace_settings_panel_test.dart`**

1. Renders all toggle states correctly from initial options
2. Toggling network access calls onOptionsChanged with updated networkAccess
3. Adding a writable path calls onOptionsChanged with updated writableRoots
4. Removing a writable path calls onOptionsChanged with updated writableRoots
5. Changing web search mode calls onWebSearchChanged
6. Toggling exclude_slash_tmp calls onOptionsChanged

**After implementation:**
- Run `./frontend/run-flutter-test.sh` to verify ALL tests pass
```

### Definition of Done

- [x] `workspace_settings_panel.dart` renders all settings sections
- [x] Toggles, path add/remove, and dropdown all call correct callbacks
- [x] "Workspace settings..." in SecurityConfigGroup opens this panel
- [x] All 6 tests pass
- [x] `./frontend/run-flutter-test.sh` passes

---

## Task 9: Permission Dialog Codex Adaptation

### Context

The permission dialog (at `frontend/lib/widgets/permission_dialog.dart`) currently shows Claude-style UI for all backends: suggestions, blocked path, and Allow/Deny buttons. For Codex, the dialog should be simplified: no suggestions, show command actions and reason text, and have three buttons (Cancel Turn / Decline / Accept).

### Prerequisites

Task 3 must be complete.

### Existing File

- `frontend/lib/widgets/permission_dialog.dart` — Current implementation
- `frontend/test/widget/permission_dialog_test.dart` — Existing tests
- `agent_sdk_core/lib/src/types/callbacks.dart` — `PermissionRequest` class with `allow()`, `deny(message, {interrupt})` methods
- `agent_sdk_core/lib/src/types/insights_events.dart` — `PermissionRequestEvent` with `provider` field

### Agent Prompt

```
You are implementing Task 9 of the CC-Insights security configuration revamp. Your job is to adapt the permission dialog for Codex backends. Read FLUTTER.md and TESTING.md first.

**Study these files first:**
- `frontend/lib/widgets/permission_dialog.dart` — Full file, especially `_buildCompactView()` and the footer with buttons
- `frontend/test/widget/permission_dialog_test.dart` — Existing test patterns
- `docs/mocks/security-config-mockups.html` — Section 6: Permission Dialog (Codex)
- `docs/insights-protocol/11-security-config.md` — lines 316-330
- `agent_sdk_core/lib/src/types/callbacks.dart` — `PermissionRequest` class, `deny(message, {interrupt})` method

**Key design:**
- The dialog needs to know whether it's showing a Claude or Codex permission
- `PermissionRequest` has a `provider` field — check if it exists. If not, you need another way to detect the backend. Options:
  a) Add a `provider` parameter to `PermissionDialog`
  b) Check `request.suggestions` — Codex requests never have suggestions
  c) Check for Codex-specific fields in `request.toolInput`

**Changes to make:**

1. **`frontend/lib/widgets/permission_dialog.dart`**:

   Add a `BackendProvider? provider` parameter to `PermissionDialog`:
   ```dart
   /// The backend provider this request came from.
   /// When null, defaults to Claude behavior.
   final BackendProvider? provider;
   ```

   In `_buildCompactView`, modify the footer to show different buttons based on provider:

   **Claude (existing, unchanged):**
   - Suggestions chips on the left
   - Enable Mode button (if setMode suggestion)
   - Deny button
   - Allow button

   **Codex (new):**
   - No suggestions section
   - Three buttons: Cancel Turn | Decline | Accept
   - "Cancel Turn" calls `widget.onDeny('cancelled')` with interrupt behavior
     - You need to update the `onDeny` callback signature to support interrupt. Currently it's `void Function(String message)`. Change it to `void Function(String message, {bool interrupt})` or add a separate `onCancelTurn` callback.

   **Codex-specific content in the body:**

   a) Show `commandActions` when available. Check `request.toolInput` for a `commandActions` or check `request` extensions. If the permission request has an `extensions` map with `'codex.commandActions'`, show it:
   ```dart
   // Actions row: "Actions: read, search"
   if (isCodex && commandActions != null)
     _buildActionsRow(commandActions),
   ```

   b) Show `reason` when available. Check `request.decisionReason`:
   ```dart
   // Reason row with chat bubble icon
   if (isCodex && request.decisionReason != null)
     _buildReasonRow(request.decisionReason!),
   ```

2. **Update callers of PermissionDialog:**

   Search for where `PermissionDialog` is instantiated. It's likely in `conversation_panel.dart`. Add the `provider` parameter. The provider can come from the `PermissionRequest`'s `provider` field if it exists, or from the `ChatState`'s backend type.

3. **Update `onDeny` to support interrupt:**

   In `ChatState.denyPermission()` (chat.dart line ~1236), the method already accepts `{bool interrupt = false}`. The dialog needs to pass this through.

   Option A: Change the callback signature to `void Function(String message, {bool interrupt})`
   Option B: Add a separate callback like `onCancelTurn`

   Choose whichever is cleaner given the existing code.

**Tests to update/create in `frontend/test/widget/permission_dialog_test.dart`:**

Add a new group for Codex permission dialog:

1. Codex command approval shows 3 buttons (Cancel Turn, Decline, Accept) — find by text
2. Claude permission shows 2 buttons (Deny, Allow) — existing behavior preserved
3. Codex dialog does NOT show suggestions section
4. Codex dialog shows reason text when `decisionReason` is set
5. Cancel Turn button calls onDeny with interrupt: true (or onCancelTurn)
6. Decline button calls onDeny with interrupt: false
7. Accept button calls onAllow

Update the `createFakeRequest` helper to accept a `provider` parameter.

**After implementation:**
- Run `./frontend/run-flutter-test.sh` to verify ALL tests pass (both new and old)
- Make sure existing Claude permission dialog tests still pass!
```

### Definition of Done

- [x] Codex permissions show Cancel Turn / Decline / Accept buttons
- [x] Claude permissions still show Deny / Allow buttons (unchanged)
- [x] Codex dialog hides suggestions section
- [x] Codex dialog shows reason and command actions when available
- [x] Cancel Turn triggers deny with interrupt
- [x] All new tests pass
- [x] All existing permission_dialog_test.dart tests still pass
- [x] `./frontend/run-flutter-test.sh` passes

---

## Task 10: Security Badge and Change Notifications

### Context

The conversation header should show a small colored badge summarizing the Codex security posture. Also, when security settings change mid-session, a notification should appear in the conversation.

The mockup shows the badge in sections 2 and 9, and the notification in section 10.

### Prerequisites

Tasks 3 and 7 must be complete.

### Agent Prompt

```
You are implementing Task 10 of the CC-Insights security configuration revamp. Your job is to add the security badge and change notifications. Read FLUTTER.md first.

**Study these files first:**
- `docs/mocks/security-config-mockups.html` — Section 2 (badge in header), Section 10 (change notification)
- `docs/insights-protocol/11-security-config.md` — lines 267-278 (badge) and 328-330 (notifications)
- `frontend/lib/panels/conversation_header.dart` — Where the badge goes (right side, before context/cost indicators)
- `frontend/lib/models/chat.dart` — `setSecurityConfig()` where notification should be triggered

**What to create/modify:**

1. **New file or add to existing: Security badge widget**

   Could be in `security_config_group.dart` or a new file. Create a `SecurityBadge` widget:

   ```dart
   class SecurityBadge extends StatelessWidget {
     const SecurityBadge({super.key, required this.config});
     final CodexSecurityConfig config;
   }
   ```

   **Logic:**
   ```
   readOnly → "Read Only", green, Icons.verified_user
   workspaceWrite + (untrusted or onRequest) → "Sandboxed", green, Icons.verified_user
   workspaceWrite + (onFailure or never) → "Auto-approve", orange, Icons.warning
   dangerFullAccess + (untrusted or onRequest) → "Unrestricted", orange, Icons.warning
   dangerFullAccess + (onFailure or never) → "Unrestricted", red, Icons.warning
   ```

   **Styling:**
   - Small pill shape: `BorderRadius.circular(12)`, padding `(8, 2)`
   - Background: color with alpha ~0.15
   - Border: color with alpha ~0.3
   - Icon: size 12
   - Text: size 10, fontWeight w500

2. **`frontend/lib/panels/conversation_header.dart`** — Add badge to header right section:

   After the last SizedBox in the left side, before the right-side indicators, add (Codex only):
   ```dart
   if (chat.model.backend == sdk.BackendType.codex) ...[
     const SizedBox(width: 8),
     Builder(builder: (context) {
       final config = chat.securityConfig;
       if (config is sdk.CodexSecurityConfig) {
         return SecurityBadge(config: config);
       }
       return const SizedBox.shrink();
     }),
   ],
   ```

   Place this in the `header-right` area, before the ContextIndicator.

3. **`frontend/lib/models/chat.dart`** — Add change notification:

   In `setSecurityConfig()`, after updating the config and before `notifyListeners()`, add a system message to the conversation:

   ```dart
   void setSecurityConfig(sdk.SecurityConfig config) {
     if (_securityConfig == config) return;
     final oldConfig = _securityConfig;
     _securityConfig = config;
     _scheduleMetaSave();

     // Generate change notification
     final message = _describeSecurityChange(oldConfig, config);
     if (message != null) {
       addEntry(TextOutputEntry(
         timestamp: DateTime.now(),
         text: message,
         isSystem: true,
       ));
     }

     // ... existing backend-specific handling
     notifyListeners();
   }

   String? _describeSecurityChange(sdk.SecurityConfig old, sdk.SecurityConfig new_) {
     if (old is sdk.CodexSecurityConfig && new_ is sdk.CodexSecurityConfig) {
       final parts = <String>[];
       if (old.sandboxMode != new_.sandboxMode) {
         parts.add('Sandbox changed to ${_sandboxLabel(new_.sandboxMode)}');
       }
       if (old.approvalPolicy != new_.approvalPolicy) {
         parts.add('Approval policy set to ${_policyLabel(new_.approvalPolicy)}');
       }
       return parts.isEmpty ? null : parts.join('. ');
     }
     if (old is sdk.ClaudeSecurityConfig && new_ is sdk.ClaudeSecurityConfig) {
       if (old.permissionMode != new_.permissionMode) {
         return 'Permission mode changed to ${new_.permissionMode.value}';
       }
     }
     return null;
   }
   ```

   Check if `TextOutputEntry` supports an `isSystem` flag. If not, check what kind of entry type is used for system messages in the app and use that. Look at how other system messages are added.

**Tests to create: `frontend/test/widget/security_badge_test.dart`**

1. Read-only sandbox shows green "Read Only" badge
2. Workspace-write + on-request shows green "Sandboxed" badge
3. Full access + never shows red "Unrestricted" badge
4. Full access + on-request shows orange "Unrestricted" badge
5. Workspace-write + never shows orange "Auto-approve" badge

**Tests: `frontend/test/models/chat_security_notification_test.dart`**

1. Changing Codex sandbox mode adds a system entry to the conversation
2. Changing Claude permission mode adds a system entry
3. Setting same config does not add an entry (no change)

**After implementation:**
- Run `./frontend/run-flutter-test.sh` to verify ALL tests pass
```

### Definition of Done

- [x] Security badge renders with correct label, color, and icon for all posture combinations
- [x] Badge only appears for Codex chats
- [x] Security config changes generate system messages in the conversation
- [x] No notification when config doesn't actually change
- [x] All 8 tests pass
- [x] `./frontend/run-flutter-test.sh` passes

---

## Task 11: Cleanup — Remove Old Codex PermissionMode Mapping

### Context

After all previous tasks, there are remnants of the old approach where Claude's `PermissionMode` was applied to Codex chats. This task cleans up those paths.

### Prerequisites

All tasks 1-10 must be complete.

### Agent Prompt

```
You are implementing Task 11 (final cleanup) of the CC-Insights security configuration revamp. Your job is to remove obsolete code paths and verify everything is clean. Read FLUTTER.md first.

**What to clean up:**

1. **Review `codex_dart_sdk/lib/src/codex_backend.dart`**:
   - Check if `capabilities` still includes `supportsPermissionModeChange: false`. If it does, that's fine — it tells the frontend not to send SetPermissionModeCommand for Codex, which is correct. Do NOT change this.

2. **Review `frontend/lib/models/chat.dart`**:
   - In `startSession()`, verify that `permissionMode` in SessionOptions is only set for Claude chats:
     ```dart
     permissionMode: _securityConfig is sdk.ClaudeSecurityConfig
         ? (_securityConfig as sdk.ClaudeSecurityConfig).permissionMode
         : null,
     ```
   - Verify `_sdkPermissionMode` getter is removed (replaced by direct access to securityConfig)
   - Check that `setPermissionMode()` still works as a convenience wrapper

3. **Review `agent_sdk_core/lib/src/types/session_options.dart`**:
   - In `validateForCodex()`, check if it warns about `permissionMode` being set. If so, update the warning message to mention that `codexSecurityConfig` should be used instead.

4. **Run ALL tests:**
   - Run `cd agent_sdk_core && dart test`
   - Run `cd codex_dart_sdk && dart test`
   - Run `./frontend/run-flutter-test.sh`
   - Run integration tests if applicable: `./frontend/run-flutter-test.sh integration_test/app_test.dart -d macos`
   - Fix ANY failures found

5. **Documentation updates:**
   - Add a cross-reference note to `docs/insights-protocol/08-permissions.md` indicating that security configuration is now documented in `11-security-config.md`
   - Do NOT rewrite or restructure the existing docs — just add a note at the top

**Tests:**
No new tests needed — just verify all existing tests pass. If any test failures are found during cleanup, fix them.

**After implementation:**
- Run ALL test suites
- Run `dart analyze` in all three packages
- Verify zero analyzer warnings or errors
```

### Definition of Done

- [x] No obsolete `_sdkPermissionMode` getter or similar dead code remains
- [x] `validateForCodex()` reflects the new `codexSecurityConfig` approach
- [x] `08-permissions.md` has a cross-reference to `11-security-config.md`
- [x] ALL tests pass across all three packages
- [x] `dart analyze` is clean in all packages
- [x] Integration tests pass

---

## Summary

| Task | Description | Dependencies | Est. New Lines | Est. Test Lines |
|------|-------------|-------------|----------------|-----------------|
| 1 | Core types (SecurityConfig, SecurityCapabilities) | None | ~200 | ~250 |
| 2 | Codex config JSON-RPC reader/writer | Task 1 | ~250 | ~300 |
| 3 | ChatState security config integration + persistence | Task 1 | ~150 mod | ~250 |
| 4 | Pass security config to thread/start | Tasks 1, 3 | ~40 mod | ~60 |
| 5 | Read config + requirements on backend connect | Tasks 1, 2 | ~50 mod | ~80 |
| 6 | SecurityConfigGroup widget | Task 3 | ~250 | ~200 |
| 7 | ConversationHeader backend-aware rendering | Tasks 3, 6 | ~60 mod | ~80 |
| 8 | WorkspaceSettingsPanel widget | Task 6 | ~200 | ~120 |
| 9 | Permission dialog Codex adaptation | Task 3 | ~80 mod | ~150 |
| 10 | Security badge + change notifications | Tasks 3, 7 | ~100 | ~100 |
| 11 | Cleanup + docs | All | ~30 mod | ~30 |
| **Total** | | | **~1000+** | **~1620** |

### Parallelization Opportunities

- **Phase 1:** Tasks 1 and 2 can run in parallel (Task 2 depends on Task 1's types, so start Task 2 after Task 1 finishes)
- **Phase 2:** Tasks 4 and 5 can run in parallel (both depend on earlier tasks but not each other)
- **Phase 3:** Tasks 6, 8, 9, and 10 can run in parallel (all depend on Task 3 but not each other)
- **Phase 4:** Task 7 depends on Task 6; Task 11 runs last after everything else
