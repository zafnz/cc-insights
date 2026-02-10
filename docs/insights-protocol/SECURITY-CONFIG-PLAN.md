# Security Configuration — Implementation Plan

Multi-part implementation plan for the unified security configuration system described in `11-security-config.md`. See `docs/mocks/security-config-mockups.html` for visual mockups.

## Dependency Graph

```
Phase 1: Core Types (no UI, no breaking changes)
  ├── Task 1A: SecurityConfig types in agent_sdk_core
  └── Task 1B: Codex config JSON-RPC methods in codex_dart_sdk
              ↓
Phase 2: Backend Integration
  ├── Task 2A: Pass security config to thread/start and thread/resume
  └── Task 2B: Read config + requirements on Codex backend connect
              ↓
Phase 3: Frontend State
  └── Task 3A: ChatState security config integration + persistence
              ↓
Phase 4: UI
  ├── Task 4A: SecurityConfigGroup widget (Codex header dropdowns)
  ├── Task 4B: ConversationHeader backend-aware rendering
  ├── Task 4C: WorkspaceSettingsPanel widget
  ├── Task 4D: Permission dialog Codex adaptation
  └── Task 4E: Security badge + change notifications
              ↓
Phase 5: Cleanup
  └── Task 5A: Remove old PermissionMode for Codex paths, update docs
```

Phases 1A and 1B can run in parallel. Within Phase 4, tasks 4A–4E can be done in any order (they share the same state layer from Phase 3).

---

## Phase 1: Core Types

### Task 1A: SecurityConfig Types in agent_sdk_core

**Goal:** Define the sealed type hierarchies for security configuration and capabilities. No behavioral changes — pure type definitions.

**Files to create/modify:**

1. **New file: `agent_sdk_core/lib/src/types/security_config.dart`**

```dart
/// Codex sandbox enforcement modes.
enum CodexSandboxMode {
  readOnly('read-only'),
  workspaceWrite('workspace-write'),
  dangerFullAccess('danger-full-access');

  const CodexSandboxMode(this.wireValue);
  final String wireValue;

  static CodexSandboxMode fromWire(String value) =>
      values.firstWhere((e) => e.wireValue == value,
          orElse: () => workspaceWrite);
}

/// Codex approval policy — when to prompt the user.
enum CodexApprovalPolicy {
  untrusted('untrusted'),
  onRequest('on-request'),
  onFailure('on-failure'),
  never('never');

  const CodexApprovalPolicy(this.wireValue);
  final String wireValue;

  static CodexApprovalPolicy fromWire(String value) =>
      values.firstWhere((e) => e.wireValue == value,
          orElse: () => onRequest);
}

/// Codex web search mode.
enum CodexWebSearchMode {
  disabled('disabled'),
  cached('cached'),
  live('live');

  const CodexWebSearchMode(this.wireValue);
  final String wireValue;

  static CodexWebSearchMode fromWire(String value) =>
      values.firstWhere((e) => e.wireValue == value,
          orElse: () => cached);
}

/// Fine-grained options for workspace-write sandbox mode.
class CodexWorkspaceWriteOptions {
  const CodexWorkspaceWriteOptions({
    this.networkAccess = false,
    this.writableRoots = const [],
    this.excludeSlashTmp = false,
    this.excludeTmpdirEnvVar = false,
  });

  final bool networkAccess;
  final List<String> writableRoots;
  final bool excludeSlashTmp;
  final bool excludeTmpdirEnvVar;

  factory CodexWorkspaceWriteOptions.fromJson(Map<String, dynamic> json) => ...;
  Map<String, dynamic> toJson() => ...;

  CodexWorkspaceWriteOptions copyWith({...}) => ...;
}

/// Backend-specific security configuration.
sealed class SecurityConfig {
  const SecurityConfig();

  Map<String, dynamic> toJson();
  static SecurityConfig fromJson(Map<String, dynamic> json) => ...;
}

class ClaudeSecurityConfig extends SecurityConfig {
  const ClaudeSecurityConfig({required this.permissionMode});

  final PermissionMode permissionMode;

  // PermissionMode is the existing enum from session_options.dart
}

class CodexSecurityConfig extends SecurityConfig {
  const CodexSecurityConfig({
    required this.sandboxMode,
    required this.approvalPolicy,
    this.workspaceWriteOptions,
    this.webSearch,
  });

  final CodexSandboxMode sandboxMode;
  final CodexApprovalPolicy approvalPolicy;
  final CodexWorkspaceWriteOptions? workspaceWriteOptions;
  final CodexWebSearchMode? webSearch;

  CodexSecurityConfig copyWith({...}) => ...;

  /// Default config for new Codex chats.
  static const defaultConfig = CodexSecurityConfig(
    sandboxMode: CodexSandboxMode.workspaceWrite,
    approvalPolicy: CodexApprovalPolicy.onRequest,
  );
}
```

2. **New file: `agent_sdk_core/lib/src/types/security_capabilities.dart`**

```dart
/// Describes what security features a backend supports.
/// Used by the frontend to determine which UI elements to show.
sealed class SecurityCapabilities {
  const SecurityCapabilities();
}

class ClaudeSecurityCapabilities extends SecurityCapabilities {
  const ClaudeSecurityCapabilities({
    this.supportsPermissionModeChange = true,
    this.supportsSuggestions = true,
  });

  final bool supportsPermissionModeChange;
  final bool supportsSuggestions;
}

class CodexSecurityCapabilities extends SecurityCapabilities {
  const CodexSecurityCapabilities({
    this.allowedSandboxModes,
    this.allowedApprovalPolicies,
    this.supportsMidSessionChange = true,
  });

  /// Null means all modes allowed (no enterprise restrictions).
  final List<CodexSandboxMode>? allowedSandboxModes;

  /// Null means all policies allowed.
  final List<CodexApprovalPolicy>? allowedApprovalPolicies;

  /// Whether config/write can change settings mid-session.
  final bool supportsMidSessionChange;

  /// Returns true if the given mode is allowed by enterprise policy.
  bool isSandboxModeAllowed(CodexSandboxMode mode) =>
      allowedSandboxModes == null || allowedSandboxModes!.contains(mode);

  bool isApprovalPolicyAllowed(CodexApprovalPolicy policy) =>
      allowedApprovalPolicies == null || allowedApprovalPolicies!.contains(policy);
}
```

3. **Modify: `agent_sdk_core/lib/agent_sdk_core.dart`** — Export new files.

**Tests (`agent_sdk_core/test/types/`):**

| # | Test | Validates |
|---|------|-----------|
| 1 | `CodexSandboxMode.fromWire` round-trips all values | Wire format fidelity |
| 2 | `CodexSandboxMode.fromWire` returns default for unknown string | Graceful fallback |
| 3 | `CodexApprovalPolicy.fromWire` round-trips all values | Wire format fidelity |
| 4 | `CodexApprovalPolicy.fromWire` returns default for unknown string | Graceful fallback |
| 5 | `CodexWebSearchMode.fromWire` round-trips all values | Wire format fidelity |
| 6 | `CodexWorkspaceWriteOptions.fromJson`/`toJson` round-trip | Serialization |
| 7 | `CodexWorkspaceWriteOptions` default values are correct | Defaults |
| 8 | `CodexWorkspaceWriteOptions.copyWith` preserves unchanged fields | Immutability |
| 9 | `CodexSecurityConfig.toJson`/`fromJson` round-trip | Serialization |
| 10 | `ClaudeSecurityConfig.toJson`/`fromJson` round-trip | Serialization |
| 11 | `SecurityConfig.fromJson` dispatches to correct subclass by type | Sealed dispatch |
| 12 | `CodexSecurityCapabilities.isSandboxModeAllowed` with null (all allowed) | No restrictions |
| 13 | `CodexSecurityCapabilities.isSandboxModeAllowed` with restricted list | Enterprise lock |
| 14 | `CodexSecurityCapabilities.isApprovalPolicyAllowed` with restricted list | Enterprise lock |
| 15 | `CodexSecurityConfig.defaultConfig` has expected values | Default config |

**Estimated scope:** ~200 lines new code, ~5 lines modifications, ~250 lines tests.

---

### Task 1B: Codex Config JSON-RPC Methods

**Goal:** Add `config/read`, `config/write`, `config/batchWrite`, and `config/requirementsRead` to `CodexProcess`. Add `config/warning` notification handling to `CodexSession`.

**Files to modify:**

1. **`codex_dart_sdk/lib/src/codex_process.dart`**

No changes needed — `sendRequest` already supports arbitrary JSON-RPC method calls. The new methods will be called via existing `_process.sendRequest()`.

2. **New file: `codex_dart_sdk/lib/src/codex_config.dart`**

```dart
/// Reads the current effective Codex configuration.
///
/// Calls `config/read` and returns parsed security-relevant fields.
/// Non-security fields (analytics, model, etc.) are ignored.
class CodexConfigReader {
  CodexConfigReader(this._process);

  final CodexProcess _process;

  /// Reads current security config from the Codex app-server.
  Future<CodexSecurityConfig> readSecurityConfig() async {
    final result = await _process.sendRequest('config/read', {});
    final config = result['config'] as Map<String, dynamic>? ?? {};
    return _parseSecurityConfig(config);
  }

  /// Reads enterprise requirements (admin constraints).
  /// Returns null if no requirements are configured.
  Future<CodexSecurityCapabilities> readCapabilities() async {
    final result = await _process.sendRequest(
      'config/requirementsRead', {},
    );
    final requirements = result['requirements'] as Map<String, dynamic>?;
    return _parseCapabilities(requirements);
  }

  CodexSecurityConfig _parseSecurityConfig(Map<String, dynamic> config) {
    return CodexSecurityConfig(
      sandboxMode: CodexSandboxMode.fromWire(
        config['sandbox_mode'] as String? ?? 'workspace-write',
      ),
      approvalPolicy: CodexApprovalPolicy.fromWire(
        config['approval_policy'] as String? ?? 'on-request',
      ),
      workspaceWriteOptions: _parseWorkspaceWriteOptions(
        config['sandbox_workspace_write'] as Map<String, dynamic>?,
      ),
      webSearch: config['web_search'] != null
          ? CodexWebSearchMode.fromWire(config['web_search'] as String)
          : null,
    );
  }

  CodexWorkspaceWriteOptions? _parseWorkspaceWriteOptions(
      Map<String, dynamic>? json) {
    if (json == null) return null;
    return CodexWorkspaceWriteOptions.fromJson(json);
  }

  CodexSecurityCapabilities _parseCapabilities(
      Map<String, dynamic>? requirements) {
    if (requirements == null) {
      return const CodexSecurityCapabilities();
    }
    return CodexSecurityCapabilities(
      allowedSandboxModes: _parseSandboxModes(
        requirements['allowedSandboxModes'] as List<dynamic>?,
      ),
      allowedApprovalPolicies: _parseApprovalPolicies(
        requirements['allowedApprovalPolicies'] as List<dynamic>?,
      ),
    );
  }

  // ... parsing helpers
}
```

3. **New file: `codex_dart_sdk/lib/src/codex_config_writer.dart`**

```dart
/// Writes Codex configuration values via JSON-RPC.
class CodexConfigWriter {
  CodexConfigWriter(this._process);

  final CodexProcess _process;

  /// Writes a single config value. Returns the write status.
  Future<CodexConfigWriteResult> writeValue({
    required String keyPath,
    required dynamic value,
    String mergeStrategy = 'replace',
  }) async {
    final result = await _process.sendRequest('config/write', {
      'keyPath': keyPath,
      'value': value,
      'mergeStrategy': mergeStrategy,
    });
    return CodexConfigWriteResult.fromJson(result);
  }

  /// Writes multiple config values atomically.
  Future<CodexConfigWriteResult> batchWrite(
      List<CodexConfigEdit> edits) async {
    final result = await _process.sendRequest('config/batchWrite', {
      'edits': edits.map((e) => e.toJson()).toList(),
    });
    return CodexConfigWriteResult.fromJson(result);
  }

  /// Convenience: update sandbox mode.
  Future<CodexConfigWriteResult> setSandboxMode(CodexSandboxMode mode) =>
      writeValue(keyPath: 'sandbox_mode', value: mode.wireValue);

  /// Convenience: update approval policy.
  Future<CodexConfigWriteResult> setApprovalPolicy(
          CodexApprovalPolicy policy) =>
      writeValue(keyPath: 'approval_policy', value: policy.wireValue);

  /// Convenience: update workspace-write options.
  Future<CodexConfigWriteResult> setWorkspaceWriteOptions(
      CodexWorkspaceWriteOptions options) =>
      writeValue(
        keyPath: 'sandbox_workspace_write',
        value: options.toJson(),
        mergeStrategy: 'upsert',
      );
}

/// Result of a config write operation.
class CodexConfigWriteResult {
  const CodexConfigWriteResult({
    required this.status,
    this.filePath,
    this.version,
    this.overrideMessage,
    this.effectiveValue,
  });

  /// 'ok' or 'okOverridden'
  final String status;
  final String? filePath;
  final String? version;
  final String? overrideMessage;
  final dynamic effectiveValue;

  bool get wasOverridden => status == 'okOverridden';

  factory CodexConfigWriteResult.fromJson(Map<String, dynamic> json) => ...;
}

class CodexConfigEdit {
  const CodexConfigEdit({
    required this.keyPath,
    required this.value,
    this.mergeStrategy = 'replace',
  });

  final String keyPath;
  final dynamic value;
  final String mergeStrategy;

  Map<String, dynamic> toJson() => ...;
}
```

4. **Modify: `codex_dart_sdk/lib/src/codex_session.dart`** — Handle `config/warning` notification.

Add to `_handleNotification`:
```dart
case 'config/warning':
  _handleConfigWarning(params);
```

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
    severity: EventSeverity.warning,
  ));
}
```

**Tests (`codex_dart_sdk/test/`):**

| # | Test | Validates |
|---|------|-----------|
| 1 | `CodexConfigReader.readSecurityConfig` parses full config response | Happy path |
| 2 | `CodexConfigReader.readSecurityConfig` handles missing fields with defaults | Graceful degradation |
| 3 | `CodexConfigReader.readSecurityConfig` parses workspace-write options | Sub-options |
| 4 | `CodexConfigReader.readCapabilities` with no requirements | No enterprise |
| 5 | `CodexConfigReader.readCapabilities` with restricted modes | Enterprise lock |
| 6 | `CodexConfigWriter.writeValue` sends correct JSON-RPC params | Wire format |
| 7 | `CodexConfigWriter.batchWrite` sends array of edits | Batch format |
| 8 | `CodexConfigWriter.setSandboxMode` sends correct keyPath + value | Convenience method |
| 9 | `CodexConfigWriter.setApprovalPolicy` sends correct keyPath + value | Convenience method |
| 10 | `CodexConfigWriteResult.fromJson` parses 'ok' status | Happy path |
| 11 | `CodexConfigWriteResult.fromJson` parses 'okOverridden' with metadata | Enterprise override |
| 12 | `CodexSession` emits event for `config/warning` notification | Warning handling |
| 13 | `CodexConfigWriter.setWorkspaceWriteOptions` sends correct structure | Sub-options write |

**Estimated scope:** ~250 lines new code, ~20 lines modifications, ~300 lines tests.

---

## Phase 2: Backend Integration

### Task 2A: Pass Security Config to Thread Start

**Goal:** When creating a Codex session, include `sandbox` and `approvalPolicy` in the `thread/start` and `thread/resume` JSON-RPC params.

**Files to modify:**

1. **`codex_dart_sdk/lib/src/codex_backend.dart`**

Modify `_startThread` to accept and pass security config:

```dart
Future<String> _startThread(String cwd, SessionOptions? options) async {
  final model = options?.model?.trim();
  final resume = options?.resume;
  final resolvedModel = model != null && model.isNotEmpty ? model : null;

  // Extract Codex security config from options
  final securityConfig = options?.codexSecurityConfig;

  Map<String, dynamic> result;
  if (resume != null && resume.isNotEmpty) {
    result = await _process.sendRequest('thread/resume', {
      'threadId': resume,
      'cwd': cwd,
      if (resolvedModel != null) 'model': resolvedModel,
      if (securityConfig != null) ...{
        'sandbox': securityConfig.sandboxMode.wireValue,
        'approvalPolicy': securityConfig.approvalPolicy.wireValue,
      },
    });
  } else {
    result = await _process.sendRequest('thread/start', {
      'cwd': cwd,
      if (resolvedModel != null) 'model': resolvedModel,
      if (securityConfig != null) ...{
        'sandbox': securityConfig.sandboxMode.wireValue,
        'approvalPolicy': securityConfig.approvalPolicy.wireValue,
      },
    });
  }

  // ... existing thread ID extraction
}
```

2. **`agent_sdk_core/lib/src/types/session_options.dart`**

Add an optional `codexSecurityConfig` field to `SessionOptions`:

```dart
class SessionOptions {
  const SessionOptions({
    // ... existing fields
    this.codexSecurityConfig,
  });

  /// Codex-specific security configuration.
  /// Ignored by non-Codex backends.
  final CodexSecurityConfig? codexSecurityConfig;
}
```

3. **`codex_dart_sdk/lib/src/codex_session.dart`**

Expose `CodexConfigWriter` for mid-session config changes:

```dart
/// Writer for changing Codex configuration mid-session.
/// Null if the session is a test session.
CodexConfigWriter? get configWriter =>
    _process != null ? CodexConfigWriter(_process!) : null;
```

Add to `AgentSession` interface in `backend_interface.dart`:
```dart
/// Returns the config writer for mid-session config changes (Codex only).
/// Returns null if the backend doesn't support it.
CodexConfigWriter? get configWriter => null;
```

**Tests:**

| # | Test | Validates |
|---|------|-----------|
| 1 | `_startThread` includes sandbox and approvalPolicy when config provided | Thread start params |
| 2 | `_startThread` omits security fields when config is null | Backward compat |
| 3 | `thread/resume` includes sandbox and approvalPolicy | Resume params |
| 4 | `SessionOptions.codexSecurityConfig` ignored by CLI backend | Non-Codex backend |

**Estimated scope:** ~40 lines modifications, ~60 lines tests.

---

### Task 2B: Read Config + Requirements on Codex Backend Connect

**Goal:** When a `CodexBackend` is created, read the current config and enterprise requirements so the frontend knows the effective security state and what options are available.

**Files to modify:**

1. **`codex_dart_sdk/lib/src/codex_backend.dart`**

Add fields and initialization:

```dart
class CodexBackend implements AgentBackend, ModelListingBackend {
  // ... existing fields

  CodexSecurityConfig? _currentConfig;
  CodexSecurityCapabilities? _capabilities;

  /// Current security configuration read from the Codex app-server.
  CodexSecurityConfig? get currentSecurityConfig => _currentConfig;

  /// Security capabilities (enterprise restrictions).
  CodexSecurityCapabilities get securityCapabilities =>
      _capabilities ?? const CodexSecurityCapabilities();

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
}
```

2. **`frontend/lib/services/backend_service.dart`**

Surface security config and capabilities from the Codex backend:

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

**Tests:**

| # | Test | Validates |
|---|------|-----------|
| 1 | `CodexBackend.create` reads config on startup | Initial config read |
| 2 | `CodexBackend.create` reads requirements on startup | Initial capabilities |
| 3 | Config read failure falls back to defaults | Error resilience |
| 4 | `currentSecurityConfig` reflects read values | State exposure |
| 5 | `securityCapabilities` reflects read values | State exposure |

**Estimated scope:** ~50 lines modifications, ~80 lines tests.

---

## Phase 3: Frontend State

### Task 3A: ChatState Security Config Integration

**Goal:** Replace the single `PermissionMode` field with a backend-aware `SecurityConfig`. Maintain backward compatibility with existing Claude chats.

**Files to modify:**

1. **`frontend/lib/models/chat.dart`**

Keep the existing `PermissionMode` enum (it's used by the Claude path). Add security config:

```dart
class ChatState extends ChangeNotifier {
  // REPLACE: PermissionMode _permissionMode = ...
  // WITH: SecurityConfig _securityConfig

  /// Backend-specific security configuration.
  late SecurityConfig _securityConfig;

  /// The security config for this chat.
  SecurityConfig get securityConfig => _securityConfig;

  /// Convenience: returns Claude permission mode if this is a Claude chat.
  /// Kept for backward compatibility with existing UI code.
  PermissionMode get permissionMode {
    if (_securityConfig case ClaudeSecurityConfig(:final permissionMode)) {
      return permissionMode;
    }
    return PermissionMode.defaultMode;
  }

  /// Set Claude permission mode (existing behavior, now delegates).
  void setPermissionMode(PermissionMode mode) {
    setSecurityConfig(ClaudeSecurityConfig(permissionMode: mode));
  }

  /// Set the full security config.
  void setSecurityConfig(SecurityConfig config) {
    if (_securityConfig == config) return;
    _securityConfig = config;
    _scheduleMetaSave();

    // Send to backend if supported
    switch (config) {
      case ClaudeSecurityConfig(:final permissionMode):
        if (_capabilities.supportsPermissionModeChange && _transport != null) {
          _transport!.send(SetPermissionModeCommand(
            mode: permissionMode.apiName,
          ));
        }
      case CodexSecurityConfig():
        // Mid-session Codex config changes sent via configWriter
        _applyCodexConfigChange(config);
    }

    notifyListeners();
  }

  Future<void> _applyCodexConfigChange(CodexSecurityConfig config) async {
    // ... use CodexConfigWriter via transport/session to write config
  }
}
```

**Initialization from meta.json:**

```dart
void _initSecurityConfig(Map<String, dynamic> meta) {
  if (meta['backendType'] == 'codex') {
    _securityConfig = CodexSecurityConfig(
      sandboxMode: CodexSandboxMode.fromWire(
        meta['codexSandboxMode'] as String? ?? 'workspace-write',
      ),
      approvalPolicy: CodexApprovalPolicy.fromWire(
        meta['codexApprovalPolicy'] as String? ?? 'on-request',
      ),
      workspaceWriteOptions: meta['codexWorkspaceWriteOptions'] != null
          ? CodexWorkspaceWriteOptions.fromJson(
              meta['codexWorkspaceWriteOptions'] as Map<String, dynamic>)
          : null,
      webSearch: meta['codexWebSearch'] != null
          ? CodexWebSearchMode.fromWire(meta['codexWebSearch'] as String)
          : null,
    );
  } else {
    _securityConfig = ClaudeSecurityConfig(
      permissionMode: PermissionMode.fromApiName(
        meta['permissionMode'] as String? ??
            RuntimeConfig.instance.defaultPermissionMode,
      ),
    );
  }
}
```

**Serialization to meta.json:**

```dart
Map<String, dynamic> _serializeSecurityConfig() {
  return switch (_securityConfig) {
    ClaudeSecurityConfig(:final permissionMode) => {
        'permissionMode': permissionMode.apiName,
      },
    CodexSecurityConfig(
      :final sandboxMode,
      :final approvalPolicy,
      :final workspaceWriteOptions,
      :final webSearch,
    ) =>
      {
        'codexSandboxMode': sandboxMode.wireValue,
        'codexApprovalPolicy': approvalPolicy.wireValue,
        if (workspaceWriteOptions != null)
          'codexWorkspaceWriteOptions': workspaceWriteOptions.toJson(),
        if (webSearch != null) 'codexWebSearch': webSearch.wireValue,
      },
  };
}
```

2. **`frontend/lib/models/chat.dart` — `startSession()`**

Pass `CodexSecurityConfig` to session options:

```dart
// In startSession(), when building SessionOptions:
options: sdk.SessionOptions(
  model: model.id.isEmpty ? null : model.id,
  permissionMode: _sdkPermissionMode,
  codexSecurityConfig: _securityConfig is CodexSecurityConfig
      ? _securityConfig as CodexSecurityConfig
      : null,
  // ... rest unchanged
),
```

3. **`frontend/lib/models/chat.dart` — `_syncPermissionModeFromResponse()`**

Update to work with `SecurityConfig`:

```dart
void _syncPermissionModeFromResponse(
  String? toolName,
  List<dynamic>? updatedPermissions,
) {
  // Only applies to Claude chats
  if (_securityConfig is! ClaudeSecurityConfig) return;

  if (updatedPermissions != null) {
    for (final perm in updatedPermissions) {
      if (perm is Map<String, dynamic> && perm['type'] == 'setMode') {
        final mode = perm['mode'] as String?;
        if (mode != null) {
          _securityConfig = ClaudeSecurityConfig(
            permissionMode: PermissionMode.fromApiName(mode),
          );
          _scheduleMetaSave();
          notifyListeners();
          return;
        }
      }
    }
  }

  if (toolName == 'ExitPlanMode') {
    _securityConfig = const ClaudeSecurityConfig(
      permissionMode: PermissionMode.defaultMode,
    );
    _scheduleMetaSave();
    notifyListeners();
  }
}
```

**Tests (`frontend/test/models/`):**

| # | Test | Validates |
|---|------|-----------|
| 1 | New Claude chat initializes with `ClaudeSecurityConfig` | Default init |
| 2 | New Codex chat initializes with `CodexSecurityConfig.defaultConfig` | Default init |
| 3 | `setPermissionMode` on Claude chat updates config | Backward compat |
| 4 | `setSecurityConfig` with `CodexSecurityConfig` updates state | Codex config |
| 5 | `securityConfig` round-trips through meta.json serialization (Claude) | Persistence |
| 6 | `securityConfig` round-trips through meta.json serialization (Codex) | Persistence |
| 7 | `securityConfig` round-trips with workspace-write options | Sub-options persist |
| 8 | `permissionMode` getter returns default for Codex chats | Cross-backend safety |
| 9 | `_syncPermissionModeFromResponse` ignores Codex chats | Backend isolation |
| 10 | `_syncPermissionModeFromResponse` updates Claude chat | Existing behavior |
| 11 | `startSession` passes `codexSecurityConfig` to options for Codex | Session creation |
| 12 | `startSession` passes null `codexSecurityConfig` for Claude | Backend isolation |
| 13 | Restoring chat from meta.json with Codex fields creates correct config | Restore path |
| 14 | Restoring chat from meta.json with old `permissionMode` field works | Migration |

**Estimated scope:** ~150 lines modifications, ~250 lines tests.

---

## Phase 4: UI

### Task 4A: SecurityConfigGroup Widget

**Goal:** Create the grouped security dropdowns widget for the Codex conversation header.

**New file: `frontend/lib/widgets/security_config_group.dart`**

```dart
/// A grouped widget showing Codex sandbox mode and approval policy dropdowns.
///
/// Renders as:  [ 🛡 Sandbox Mode ▾ | Ask: Policy ▾ ]
///
/// Adapts to danger states by changing colors.
/// Disables enterprise-locked options.
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

**Internal widgets:**
- `_SandboxModeDropdown` — Shows sandbox modes with icons and descriptions. Locked items show admin badge. "Workspace settings..." option at bottom.
- `_ApprovalPolicyDropdown` — Shows approval policies with icons and descriptions. Locked items show admin badge.

**Visual behavior:**
- Normal state: `outline-variant` border
- Danger state (`dangerFullAccess` or `never`): Red border, red text
- Disabled: Reduced opacity
- Hover on dropdowns: `primary` background tint

**Tests (`frontend/test/widget/`):**

| # | Test | Validates |
|---|------|-----------|
| 1 | Renders sandbox mode and approval policy labels | Basic rendering |
| 2 | Tapping sandbox dropdown shows all three modes | Dropdown opens |
| 3 | Selecting a sandbox mode calls `onConfigChanged` with updated config | Selection callback |
| 4 | Enterprise-locked sandbox mode is not selectable | Admin restriction |
| 5 | Enterprise-locked sandbox mode shows lock icon | Visual indicator |
| 6 | Tapping approval dropdown shows all four policies | Dropdown opens |
| 7 | Selecting a policy calls `onConfigChanged` with updated config | Selection callback |
| 8 | Danger state (full access) shows red border | Visual warning |
| 9 | Danger state (never policy) shows red text | Visual warning |
| 10 | Disabled state prevents interaction | Disabled behavior |

**Estimated scope:** ~250 lines new code, ~200 lines tests.

---

### Task 4B: ConversationHeader Backend-Aware Rendering

**Goal:** Modify the conversation header to show backend-specific security controls.

**File to modify: `frontend/lib/panels/conversation_header.dart`**

Replace the current single `CompactDropdown` for permissions with:

```dart
// Backend-specific security controls
if (chat.model.backend == sdk.BackendType.codex) ...[
  const SizedBox(width: 8),
  Builder(
    builder: (context) {
      final backendService = context.watch<BackendService>();
      final config = chat.securityConfig;
      if (config is! CodexSecurityConfig) {
        return const SizedBox.shrink();
      }
      return SecurityConfigGroup(
        config: config,
        capabilities: backendService.codexSecurityCapabilities,
        isEnabled: true, // Codex supports mid-session changes
        onConfigChanged: (newConfig) {
          chat.setSecurityConfig(newConfig);
        },
      );
    },
  ),
] else ...[
  // Claude: existing single dropdown
  const SizedBox(width: 8),
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

Also add the security badge to the right side (Codex only):

```dart
if (chat.model.backend == sdk.BackendType.codex) ...[
  const SizedBox(width: 8),
  _SecurityBadge(config: chat.securityConfig as CodexSecurityConfig),
],
```

**Tests:**

| # | Test | Validates |
|---|------|-----------|
| 1 | Claude chat shows single permissions dropdown | Backend routing |
| 2 | Codex chat shows SecurityConfigGroup | Backend routing |
| 3 | Codex chat shows security badge | Badge rendering |
| 4 | Switching backend type changes the security controls | Dynamic switch |

**Estimated scope:** ~60 lines modifications, ~80 lines tests.

---

### Task 4C: WorkspaceSettingsPanel Widget

**Goal:** Create the fine-grained workspace-write settings panel, accessible from the sandbox mode dropdown.

**New file: `frontend/lib/widgets/workspace_settings_panel.dart`**

```dart
/// Panel for fine-grained Codex workspace-write sandbox settings.
///
/// Shows:
/// - Network access toggle
/// - Temp directory exclusion toggles
/// - Additional writable paths list (add/remove)
/// - Web search mode dropdown
///
/// Accessed via "Workspace settings..." in the sandbox mode dropdown.
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

This panel is shown as a popup/dialog when the user clicks "Workspace settings..." in the sandbox dropdown.

**Tests:**

| # | Test | Validates |
|---|------|-----------|
| 1 | Renders all toggle states correctly | Initial render |
| 2 | Toggling network access calls callback | Toggle interaction |
| 3 | Adding a writable path calls callback with updated list | Path add |
| 4 | Removing a writable path calls callback with updated list | Path remove |
| 5 | Changing web search mode calls callback | Web search |
| 6 | Toggling exclude_slash_tmp calls callback | Temp dir toggle |

**Estimated scope:** ~200 lines new code, ~120 lines tests.

---

### Task 4D: Permission Dialog Codex Adaptation

**Goal:** When a permission request comes from a Codex backend, show a simplified dialog without suggestions UI. Display command actions and reason when available.

**File to modify: `frontend/lib/widgets/permission_dialog.dart`**

The existing dialog already checks `request.suggestions` to decide whether to show suggestions. The main changes are:

1. **Show `commandActions` for Codex command approvals:**
```dart
// In the dialog body, after the code block:
if (_isCodexCommandApproval && request.extensions?['codex.commandActions'] != null)
  _CommandActionsRow(actions: request.extensions!['codex.commandActions']),
```

2. **Show `reason` text for Codex:**
```dart
// Codex approval requests include a reason from the agent
if (_isCodexApproval && _reason != null)
  _ReasonRow(reason: _reason!),
```

3. **Three-button layout for Codex:**
```dart
// Codex: Cancel Turn / Decline / Accept
if (provider == BackendProvider.codex) ...[
  TextButton(
    onPressed: () => widget.onDeny(message: 'cancelled', interrupt: true),
    child: const Text('Cancel Turn'),
  ),
  TextButton(
    onPressed: () => widget.onDeny(message: 'declined', interrupt: false),
    child: const Text('Decline'),
  ),
  FilledButton(
    onPressed: () => widget.onAllow(),
    child: const Text('Accept'),
  ),
] else ...[
  // Claude: existing Deny / Allow
],
```

4. **File change approval shows path, not empty:**
```dart
// Current: file_path from grantRoot (often empty string)
// New: show meaningful label
if (toolName == 'Write' && provider == BackendProvider.codex) {
  // Show "Codex wants to write files under: <path>" or
  // "Codex wants to write files" if no grantRoot
}
```

**Tests:**

| # | Test | Validates |
|---|------|-----------|
| 1 | Codex command approval shows 3 buttons (Cancel Turn, Decline, Accept) | Button layout |
| 2 | Claude permission shows 2 buttons (Deny, Allow) | Button layout |
| 3 | Codex dialog hides suggestions section | No suggestions |
| 4 | Codex dialog shows command actions when present | Actions display |
| 5 | Codex dialog shows reason text when present | Reason display |
| 6 | Cancel Turn button calls `onDeny(interrupt: true)` | Cancel behavior |
| 7 | Decline button calls `onDeny(interrupt: false)` | Decline behavior |
| 8 | Accept button calls `onAllow()` | Accept behavior |
| 9 | File change dialog shows path or generic message | File change display |

**Estimated scope:** ~80 lines modifications, ~150 lines tests.

---

### Task 4E: Security Badge + Change Notifications

**Goal:** Add a security posture badge to the header and show toast notifications when security settings change mid-session.

**1. Security badge in header right section**

Small widget that summarizes the effective security posture:

```dart
class _SecurityBadge extends StatelessWidget {
  const _SecurityBadge({required this.config});
  final CodexSecurityConfig config;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _posture();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  (String, Color, IconData) _posture() {
    final isDangerSandbox = config.sandboxMode == CodexSandboxMode.dangerFullAccess;
    final isNoApproval = config.approvalPolicy == CodexApprovalPolicy.never;
    final isReadOnly = config.sandboxMode == CodexSandboxMode.readOnly;

    if (isReadOnly) return ('Read Only', Colors.green, Icons.verified_user);
    if (isDangerSandbox && isNoApproval) return ('Unrestricted', Colors.red, Icons.warning);
    if (isDangerSandbox || isNoApproval) return ('Unrestricted', Colors.orange, Icons.warning);
    return ('Sandboxed', Colors.green, Icons.verified_user);
  }
}
```

**2. Toast notification on security change**

In `ChatState.setSecurityConfig`, after applying the change, emit a notification:

```dart
void _notifySecurityChange(SecurityConfig oldConfig, SecurityConfig newConfig) {
  // Compare and generate appropriate message
  final message = _describeSecurityChange(oldConfig, newConfig);
  if (message != null) {
    // Add a system message to the conversation output
    addSystemMessage(message);
  }
}
```

**Tests:**

| # | Test | Validates |
|---|------|-----------|
| 1 | Read-only sandbox shows green "Read Only" badge | Safe posture |
| 2 | Workspace-write + on-request shows green "Sandboxed" badge | Normal posture |
| 3 | Full access + never shows red "Unrestricted" badge | Danger posture |
| 4 | Full access + on-request shows orange "Unrestricted" badge | Mixed danger |
| 5 | Security change triggers system message in conversation | Change notification |
| 6 | Badge updates when security config changes | Reactive update |

**Estimated scope:** ~100 lines new code, ~100 lines tests.

---

## Phase 5: Cleanup

### Task 5A: Remove Old Codex Permission Mode Mapping + Update Docs

**Goal:** Clean up the now-obsolete code paths where Claude's `PermissionMode` was applied to Codex chats, and update documentation.

**Changes:**

1. **Remove `_sdkPermissionMode` from being passed to Codex sessions** — It's now handled by `codexSecurityConfig` in `SessionOptions`.

2. **Remove `supportsPermissionModeChange` from `CodexBackend.capabilities`** — Codex uses `config/write` instead. The capability was always `false` anyway.

3. **Update `08-permissions.md`** — Add cross-reference to `11-security-config.md` for the full security model. Remove the inaccurate "Codex manages permissions server-side; `setPermissionMode` is a no-op" statement.

4. **Update `CLAUDE.md`** — Add reference to the new security config spec in the documentation section.

5. **Clean up `SessionOptions.validateForCodex()`** — Update validation warnings to reference the new `codexSecurityConfig` field.

**Tests:**

| # | Test | Validates |
|---|------|-----------|
| 1 | Codex session creation doesn't include `permissionMode` in thread/start | Clean params |
| 2 | All existing tests still pass | No regression |

**Estimated scope:** ~30 lines deletions, ~20 lines modifications, ~30 lines tests.

---

## Test Summary

| Phase | Task | New Tests | Lines New | Lines Modified |
|-------|------|-----------|-----------|----------------|
| 1 | 1A: Core types | 15 | ~200 | ~5 |
| 1 | 1B: Config JSON-RPC | 13 | ~250 | ~20 |
| 2 | 2A: Thread start params | 4 | ~0 | ~40 |
| 2 | 2B: Read config on connect | 5 | ~0 | ~50 |
| 3 | 3A: ChatState integration | 14 | ~0 | ~150 |
| 4 | 4A: SecurityConfigGroup | 10 | ~250 | ~0 |
| 4 | 4B: Header rendering | 4 | ~0 | ~60 |
| 4 | 4C: WorkspaceSettingsPanel | 6 | ~200 | ~0 |
| 4 | 4D: Permission dialog | 9 | ~0 | ~80 |
| 4 | 4E: Badge + notifications | 6 | ~100 | ~0 |
| 5 | 5A: Cleanup | 2 | ~0 | ~50 |
| **Total** | | **88** | **~1000** | **~455** |

## Risk Mitigation

1. **Backward compatibility:** The `permissionMode` field in `chat.meta.json` is preserved for Claude chats. Existing chats will load correctly — the new `codex*` fields simply won't be present, and defaults will be used.

2. **Codex config/read failure:** If the Codex app-server doesn't support `config/read` (older version), we catch the error and fall back to default config. The UI still works, it just can't verify the actual server state.

3. **Enterprise overrides:** If a `config/write` returns `okOverridden`, the UI shows a warning toast explaining the admin policy and reverts the dropdown to the effective value.

4. **Mid-session sandbox changes:** Changing sandbox mode mid-session may have complex effects on the Codex sandbox. The UI allows it (Codex supports it), but shows a confirmation dialog for dangerous mode changes (`danger-full-access`).

5. **Migration:** No data migration needed. Old Codex chats without the new fields will use `CodexSecurityConfig.defaultConfig` (workspace-write + on-request), which matches the Codex default behavior.
