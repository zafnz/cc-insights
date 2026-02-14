# Multi-Agent Configuration Refactor

## Context

CC-Insights currently hardcodes three backends: Claude (`directCli`), Codex (`codex`), and ACP (`acp`). Each has its own settings key (`session.claudeCliPath`, `session.codexCliPath`, etc.), its own availability check, and hardcoded display names throughout the UI. This makes it impossible to run two agents with the same driver (e.g., two Claude instances with different API keys) and forces code changes to add any new agent.

This refactor introduces a configurable **Agent** registry where users can add, edit, and remove agents through Settings. Each agent wraps a driver (the wire protocol) with user-specific configuration. The `BackendType` enum in `agent_sdk_core` stays unchanged — it represents protocols, not agents.

**Mockup:** `docs/mocks/agents-settings-mockup.html`

---

## AgentConfig Model

```dart
// frontend/lib/models/agent_config.dart

@immutable
class AgentConfig {
  final String id;                   // Stable UUID, used as backend key
  final String name;                 // Display name ("Claude", "My Codex", "Gemini")
  final String driver;               // "claude", "codex", "acp" → maps to BackendType
  final String cliPath;              // Executable path (empty = auto-detect via PATH)
  final String cliArgs;              // CLI arguments string
  final String environment;          // Freeform multiline KEY=VALUE\n pairs
  final String defaultModel;         // Model ID (e.g., "opus", "o3", "")
  final String defaultPermissions;   // Permission preset (driver-dependent)
  // Codex-specific permission fields (only when driver == "codex"):
  final String? codexSandboxMode;    // "readOnly", "workspaceWrite", "fullAccess"
  final String? codexApprovalPolicy; // "untrusted", "onRequest", "onFailure", "never"

  BackendType get backendType => parseBackendType(driver);

  Map<String, String> get parsedEnvironment { /* parse KEY=VALUE lines */ }
}
```

**Defaults** (created on first launch or when config has no agents):

| Name    | Driver  | Default Model | Default Permissions |
|---------|---------|---------------|---------------------|
| Claude  | claude  | opus          | default             |
| Codex   | codex   | (server)      | workspaceWrite + onRequest |
| Gemini  | acp     | (agent)       | (none)              |

---

## Persistence

### config.json

Agents are stored as a list under `agents.available`:

```json
{
  "agents.available": [
    {
      "id": "a1b2c3",
      "name": "Claude",
      "driver": "claude",
      "cliPath": "",
      "cliArgs": "",
      "environment": "",
      "defaultModel": "opus",
      "defaultPermissions": "default"
    },
    {
      "id": "d4e5f6",
      "name": "Codex",
      "driver": "codex",
      "cliPath": "",
      "cliArgs": "",
      "environment": "",
      "defaultModel": "",
      "defaultPermissions": "",
      "codexSandboxMode": "workspaceWrite",
      "codexApprovalPolicy": "onRequest"
    },
    {
      "id": "g7h8i9",
      "name": "Gemini",
      "driver": "acp",
      "cliPath": "/usr/local/bin/gemini",
      "cliArgs": "--stdio",
      "environment": "GOOGLE_API_KEY=...",
      "defaultModel": "",
      "defaultPermissions": ""
    }
  ],
  "agents.defaultAgent": "a1b2c3"
}
```

The old flat settings (`session.claudeCliPath`, etc.) are migrated to agents on first load and then removed.

### ChatMeta (per-chat persistence)

Add `agentId` field alongside existing `backendType`:

```json
{
  "model": "opus",
  "backendType": "direct",
  "agentId": "a1b2c3",
  ...
}
```

Old chats without `agentId` are migrated during restore by matching `backendType` to the first agent with a matching driver.

---

## BackendService Changes

### Key decision: One backend instance per agent (not per driver)

**Why:** Two agents with the same driver but different CLI paths or API keys need separate subprocess instances. If one crashes, it shouldn't affect the other. Clean lifecycle — disposing an agent disposes exactly one backend.

### Current → New

```
Current:  Map<BackendType, AgentBackend>  _backends
          BackendType                     _backendType

New:      Map<String, AgentBackend>       _backends     // keyed by agent ID
          String?                         _activeAgentId
```

### API changes

```dart
// Current
Future<void> start({BackendType type, String? executablePath, ...})
BackendCapabilities capabilitiesFor(BackendType type)
Future<EventTransport> createTransport({required BackendType type, ...})

// New
Future<void> startAgent(String agentId, {AgentConfig? config})
BackendCapabilities capabilitiesForAgent(String agentId)
Future<EventTransport> createTransportForAgent({required String agentId, ...})
```

The agent config is resolved from the registry. CLI path, args, and environment variables are passed to the backend factory. The `BackendType` is derived from `agentConfig.backendType` internally.

### Data flow

```
AgentConfig (name, driver, cliPath, env, ...)
  → BackendService.startAgent(agentId)
  → BackendRegistry.create(type: config.backendType,
      executablePath: config.cliPath,
      arguments: config.cliArgs,
      environment: config.parsedEnvironment)
  → AgentBackend instance stored in _backends[agentId]
```

---

## ChatState Changes

### New fields

```dart
String _agentId;        // References AgentConfig.id
String get agentId;     // Public getter
String get agentName;   // Resolved from agent registry, falls back to driver label
```

### Behavioral changes

- `backendLabel` returns `agentName` instead of hardcoded "claude"/"codex"/"acp"
- `_backendTypeValue` stays unchanged (still persists "direct"/"codex"/"acp" for SDK compatibility)
- Session startup resolves agent config → derives BackendType → creates SDK session
- `model.backend` still used for all SDK-level operations (security config, capabilities, etc.)

---

## UI Changes

### Settings Screen — Agents Category

New custom renderer `_AgentsSettingsContent` (same pattern as `_TagsSettingsContent`):

- **Top section:** Agent list (cards with icon, name, driver badge, default model)
- **Add Agent button:** Appends a new agent with defaults, selects it
- **Bottom section:** Selected agent detail form with fields:
  - Name (text input)
  - Driver (dropdown: claude/codex/acp)
  - CLI (text input + browse button)
  - CLI Args (text input)
  - Environment (multiline textarea)
  - Default Model (dropdown, driver-dependent — see mockup)
  - Default Permissions (driver-dependent — see mockup)
  - Remove Agent (danger zone)

The category uses `id: 'agents'` with `icon: Icons.smart_toy_outlined`.

### Conversation Header

Replace hardcoded agent list:

```dart
// Current
final agentItems = ['Claude', if (codexAvailable) 'Codex', if (acpAvailable) 'ACP'];

// New
final agents = context.read<AgentRegistry>().availableAgents;
final agentItems = agents.map((a) => a.name).toList();
```

`agentLabel()` and `backendFromAgent()` are replaced with lookups against the agent registry.

### Welcome Card

Same pattern — agent dropdown populated from registry instead of hardcoded list.

### Cost Indicator

`agentLabel` parameter changes from hardcoded backend label to the chat's `agentName`. The `~` prefix for Codex cost estimation is keyed off `model.backend == BackendType.codex` (driver-level, not agent-level), so it still works correctly.

---

## Agent Removal & Chat Termination

When an agent is removed from settings:

1. Kill all active sessions for that agent (call `session.kill()` on each)
2. Mark affected chats as **terminated** — a new `ChatState` flag: `bool _agentRemoved = false`
3. Terminated chats:
   - Remain visible in the chat list (history preserved)
   - Show a banner: "Agent removed — this chat can no longer send messages"
   - Message input is disabled
   - No session can be started
4. The backend instance for that agent is disposed

---

## Migration from Old Config

On `SettingsService.load()`, if `agents.available` is absent but old `session.*` keys exist:

```dart
if (!_values.containsKey('agents.available')) {
  final agents = <Map<String, dynamic>>[];
  // Always create Claude agent
  agents.add({
    'id': _generateId(),
    'name': 'Claude',
    'driver': 'claude',
    'cliPath': _values['session.claudeCliPath'] ?? '',
    'cliArgs': '',
    'environment': '',
    'defaultModel': 'opus',
    'defaultPermissions': _values['session.defaultPermissionMode'] ?? 'default',
  });
  // Create Codex agent if path was configured
  agents.add({
    'id': _generateId(),
    'name': 'Codex',
    'driver': 'codex',
    'cliPath': _values['session.codexCliPath'] ?? '',
    ...
  });
  // Create Gemini agent if ACP path was configured
  agents.add({
    'id': _generateId(),
    'name': 'Gemini',
    'driver': 'acp',
    'cliPath': _values['session.acpCliPath'] ?? '',
    'cliArgs': _values['session.acpCliArgs'] ?? '',
    ...
  });
  _values['agents.available'] = agents;
  // Remove old keys
  _values.remove('session.claudeCliPath');
  _values.remove('session.codexCliPath');
  _values.remove('session.acpCliPath');
  _values.remove('session.acpCliArgs');
  await _save();
}
```

---

## Implementation Phases

Each phase leaves the app in a working state. Tests must pass after each phase.

### Phase 1: AgentConfig Model + Settings Persistence

**Files:**
- Create `frontend/lib/models/agent_config.dart`
- Modify `frontend/lib/services/settings_service.dart` — add `agents` category, agent CRUD methods, migration logic
- Modify `frontend/lib/services/runtime_config.dart` — add agent registry accessor

**What:**
- Define `AgentConfig` with serialization
- Add `agents.available` and `agents.defaultAgent` to settings
- Add migration from old `session.*` keys
- Add `availableAgents`, `agentById()`, `addAgent()`, `updateAgent()`, `removeAgent()` to SettingsService
- Sync agent list to RuntimeConfig

**Tests:** Unit tests for AgentConfig serialization, settings migration, agent CRUD.

### Phase 2: BackendService Agent-Keyed Backends

**Files:**
- Modify `frontend/lib/services/backend_service.dart` — change from `Map<BackendType, ...>` to `Map<String, ...>`

**What:**
- Replace `_backends` key type from `BackendType` to `String` (agent ID)
- Add `startAgent(agentId)` that resolves config from registry
- Pass agent's `cliPath`, `cliArgs`, `parsedEnvironment` to backend factory
- Keep old `start(type:)` as a compatibility shim that finds the first agent with matching driver
- Update `capabilitiesFor`, `createTransport`, `errorFor`, etc. to accept agent ID

**Tests:** Unit tests for agent-keyed backend lifecycle.

### Phase 3: ChatState Agent Tracking

**Files:**
- Modify `frontend/lib/models/chat.dart` — add `_agentId`, `agentName` getter
- Modify `frontend/lib/models/chat_model.dart` — no structural change, but update `ChatModelCatalog` to support agent-scoped queries

**What:**
- Add `_agentId` field to `ChatState`, set during construction
- `agentName` getter resolves from agent registry, falls back to driver label
- `backendLabel` returns `agentName`
- `_startSession()` uses `backendService.createTransportForAgent(agentId: _agentId, ...)`
- Model selection scoped to agent's driver: `ChatModelCatalog.forBackend(agentConfig.backendType)`

**Tests:** Unit tests for ChatState agent resolution and session routing.

### Phase 4: Persistence Migration

**Files:**
- Modify `frontend/lib/services/persistence_models.dart` — add `agentId` to `ChatMeta`
- Modify `frontend/lib/services/project_restore_service.dart` — migration logic for old chats

**What:**
- `ChatMeta.toJson()` writes `agentId`
- `ChatMeta.fromJson()` reads `agentId`, falls back to matching `backendType` → first agent with matching driver
- `ChatMeta.create()` takes `agentId` parameter
- Restore service passes `agentId` when creating ChatState from saved meta

**Tests:** Unit tests for ChatMeta serialization with and without agentId, migration from old format.

### Phase 5: UI — Agent Dropdowns

**Files:**
- Modify `frontend/lib/panels/conversation_header.dart` — agent dropdown from registry
- Modify `frontend/lib/panels/welcome_card.dart` — same
- Modify `frontend/lib/widgets/cost_indicator.dart` — use agent name

**What:**
- Replace `agentLabel()` / `backendFromAgent()` with registry lookups
- Agent dropdown populated from `settingsService.availableAgents` filtered by CLI availability
- `_handleAgentChange()` receives agent ID, calls `backendService.startAgent(agentId)`
- Cost indicator receives `agentName` from `chat.agentName`

**Tests:** Widget tests for conversation header with mock agent registry.

### Phase 6: Settings UI — Agent Management

**Files:**
- Modify `frontend/lib/screens/settings_screen.dart` — add `_AgentsSettingsContent`

**What:**
- New `_AgentsSettingsContent` StatefulWidget (pattern matches `_TagsSettingsContent`)
- Agent list with selection, detail form below divider
- Driver dropdown controls which fields appear (model, permissions)
- CLI path field with browse button (reuse `_CliPathSettingRow` pattern)
- Environment multiline textarea
- Add Agent / Remove Agent buttons
- Settings saved via `settingsService.updateAgent()` on field change

**Tests:** Widget tests for agent settings form rendering and CRUD operations.

### Phase 7: Agent Removal Chat Termination

**Files:**
- Modify `frontend/lib/models/chat.dart` — add `_agentRemoved` flag, `terminateForAgentRemoval()`
- Modify `frontend/lib/services/settings_service.dart` — removal triggers termination
- Modify `frontend/lib/panels/conversation_panel.dart` — show termination banner
- Modify `frontend/lib/widgets/message_input.dart` — disable when terminated

**What:**
- `ChatState.terminateForAgentRemoval()`: kills active session, sets flag, notifies listeners
- `SettingsService.removeAgent()` iterates all worktrees' chats, calls `terminateForAgentRemoval()` on matches
- Conversation panel shows a banner when `chat.agentRemoved`
- Message input disabled when `chat.agentRemoved`
- Backend for removed agent is disposed

**Tests:** Integration test: remove agent → verify chats terminated, input disabled, banner shown.

### Phase 8: CLI Availability Per-Agent

**Files:**
- Modify `frontend/lib/services/cli_availability_service.dart` — check per agent instead of per backend type

**What:**
- Replace `checkAll(claudePath, codexPath, acpPath)` with `checkAgents(List<AgentConfig>)`
- Store availability as `Map<String, bool>` keyed by agent ID
- Settings UI shows availability error per-agent inline
- Conversation header filters agent dropdown by availability

**Tests:** Unit tests for per-agent availability checking.

### Phase 9: Cleanup Old Settings

**Files:**
- Modify `frontend/lib/services/settings_service.dart` — remove old `session.*` CLI path definitions
- Modify `frontend/lib/services/runtime_config.dart` — remove individual CLI path fields

**What:**
- Remove `session.claudeCliPath`, `session.codexCliPath`, `session.acpCliPath`, `session.acpCliArgs` from `_sessionCategory`
- Remove `session.defaultPermissionMode` (now per-agent)
- Update `session.defaultModel` to `agents.defaultAgent` (or keep as composite for backward compat)
- Remove `RuntimeConfig.claudeCliPath`, `codexCliPath`, `acpCliPath`, `acpCliArgs` fields
- Remove `RuntimeConfig.codexAvailable`, `acpAvailable` flags (replaced by per-agent availability)
- Clean up any remaining `agentLabel()` / `backendFromAgent()` helpers

**Tests:** Full test suite pass. Run `./frontend/run-flutter-test.sh`.

---

## Verification

After all phases:

1. `./frontend/run-flutter-test.sh` — all tests pass
2. `./frontend/run-flutter-test.sh integration_test/app_test.dart -d macos` — integration tests pass
3. Manual testing:
   - Open Settings → Agents → verify 3 default agents
   - Edit Claude agent name → verify it shows new name in conversation header
   - Add a new agent with "claude" driver and different env → verify both work
   - Remove an agent with active chats → verify chats terminated, banner shown
   - Close and reopen app → verify agents persisted, old chats restored with correct agent
   - Upgrade from old config → verify migration creates 3 default agents from old settings
