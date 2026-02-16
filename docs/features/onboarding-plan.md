# Onboarding Implementation Plan

Reference: `docs/features/onboarding.md` (spec), `docs/mocks/onboarding-flow-mockup.html` (mockups)

---

## Chunk 1: Onboarding Screen Scaffold & Scanning Phase

**Objective:** Create the new `OnboardingScreen` widget with the scanning phase UI. Wire it into `main.dart` so it appears on first run instead of `CliRequiredScreen`.

### Tasks

1. Create `frontend/lib/screens/onboarding_screen.dart` as a `StatefulWidget`
   - Internal state enum: `scanning`, `results`, `agentSetup`, `advanced`
   - Hold a `Map<String, AgentScanResult>` keyed by onboarding scan target (`claude`, `codex`, `gemini`, `acpCompatible`) with status (`scanning`, `found`, `notFound`) and resolved path
   - On `initState`, kick off parallel probes using a new `CliAvailabilityService.probeExecutable(...)` helper (uses `Process.start(..., ['--version'])` with timeout)
2. Build the scanning phase UI (mockup section 1):
   - Header icon (`search`, primary color, 56px)
   - Title: "Setting up for the first time"
   - Subtitle: "Looking for AI agents on your system..."
   - Agent row list — Claude, Codex, Gemini CLI — each showing name + "Scanning..." + spinner
   - Cancel button at bottom
3. Wire into `main.dart`:
   - Add a `_shouldShowOnboarding()` method:
     - `!_projectSelected`
     - app not launched with project path via CLI
     - AND (`!settings.hasCompletedOnboarding` OR `!settings.hasExplicitlyConfiguredAgents`)
   - Replace the `!cliAvailability.claudeAvailable` gate in `_buildScreen()` with a call to `_shouldShowOnboarding()` that shows the new `OnboardingScreen`
   - Pass `CliAvailabilityService`, `SettingsService`, and an `onComplete` callback
4. Add onboarding helpers to `SettingsService`:
   - `onboarding.completed` key persisted in `config.json`
   - `hasCompletedOnboarding` getter
   - `hasExplicitlyConfiguredAgents` getter (checks raw `agents.available`, not fallback defaults)

### Definition of Done

- App launches and shows the scanning screen with spinners on first run (when no `onboarding.completed` flag in config.json)
- Existing users with explicit configured agents and completed onboarding skip to WelcomeScreen
- If no explicit agents are configured, onboarding still shows (even if `onboarding.completed` is true)
- Cancel button transitions to WelcomeScreen and sets `onboarding.completed = true`
- `CliRequiredScreen` is no longer referenced from `main.dart`
- All existing tests pass (`./frontend/run-flutter-test.sh`)

---

## Chunk 2: Results Phase

**Objective:** When scanning completes, transition to the results screen showing found/not-found status for each agent, with the correct variant (none found, some found, all found).

### Tasks

1. Build the results phase UI (mockup sections 2, 3, 4, 8):
   - Determine variant from scan results:
     - None found → `search_off` icon (orange), title "No AI agents found", Continue disabled
     - Some found, Claude missing → `manage_search` icon (orange), title "Found some AI agents", warning banner, Continue enabled
     - Some/all found, Claude present → `check_circle` icon (green), title "Found some AI agents", Continue enabled
   - Agent row list — Claude, Codex, Gemini CLI, ACP Compatible — each showing:
     - Found: green border, green `check_circle` icon, "Found at /path/to/cli"
     - Not found: default border, clickable with `chevron_right`, "Not found" (or "Not configured" for ACP)
   - Warning banner widget (orange background, warning icon, text about Claude)
   - Action row: "Advanced..." button (outlined), "Continue" button (filled, conditionally disabled)
2. Implement Continue button:
   - Save `onboarding.completed = true` to settings
   - If no explicit agents exist yet, seed `agents.available` from onboarding results/manual setup (create entries only for configured/found targets)
   - Re-run `cliAvailability.checkAgents(RuntimeConfig.instance.agents)` for configured agents
   - Call `backendService.discoverModelsForAllAgents()` when at least one configured agent is available
   - Transition to WelcomeScreen via `onComplete` callback
3. Clicking a not-found agent row sets internal state to `agentSetup` with the selected agent (implemented in Chunk 3)
4. Clicking "Advanced..." sets internal state to `advanced` (implemented in Chunk 4)

### Definition of Done

- After scanning completes, the correct results variant is displayed
- Found agents show green tick and resolved path; not-found agents show chevron
- Warning banner appears only when Claude is missing but others are found
- Continue button is disabled when no agents are found/configured, enabled otherwise
- Continue proceeds to WelcomeScreen and persists the onboarding-completed flag
- All existing tests pass

---

## Chunk 3: Agent Setup Screens

**Objective:** Clicking a not-found agent's chevron navigates to a per-agent setup screen with install instructions and manual path entry.

### Tasks

1. Create `_AgentSetupView` widget within `onboarding_screen.dart` (or as a separate private widget):
   - Back button: "Back to agent selection" — returns to results phase
   - Agent header: colored icon (48px) + "Set Up <AgentName>"
   - Subtitle: "Install the <AgentName> CLI or provide the path to an existing installation."
   - Install instructions section with `_CommandBlock` widgets (reuse or extract from `CliRequiredScreen`):
     - Claude: `brew install --cask claude-code` or `curl -fsSL https://claude.ai/install.sh | bash`
     - Codex: `npm install -g @openai/codex`
     - Gemini CLI: `npm install -g @google/gemini-cli`
     - ACP Compatible: no install commands, just manual path entry
   - Documentation link per agent
   - Manual path entry: TextField (mono font) + browse button
   - Hint text about argument auto-separation
   - Action buttons: "Retry Detection" (outlined) + "Verify & Continue" (filled)
2. Implement path-with-arguments splitting:
   - When the user submits a path containing spaces after the executable (e.g., `/usr/bin/claude --model X`), split into `cliPath` and `cliArgs`
   - Support quoted executable paths; parse first command token as executable, remainder as args
   - Save both to the agent's `AgentConfig` via `SettingsService.updateAgent()`
3. Implement Verify & Continue:
   - Save custom path (+ args) to agent config (create/update agent entry for target)
   - Probe this target via `CliAvailabilityService.probeExecutable(...)`
   - If found: return to results phase (agent now shows as found with tick)
   - If not found: show error message in red
4. Implement Retry Detection:
   - Clear custom path override for that target, re-run probe detection
   - Update UI based on result

### Definition of Done

- Clicking a not-found agent row navigates to its setup screen
- Each agent shows correct install instructions
- Manual path entry works — entering a valid path and clicking Verify marks the agent as found
- Entering `/usr/bin/claude --model X` correctly splits into path `/usr/bin/claude` and args `--model X`
- Back button returns to results screen
- Error message shown for invalid paths
- All existing tests pass

---

## Chunk 4: Advanced Setup Screen

**Objective:** The "Advanced..." button opens a sidebar agent editor allowing full agent CRUD — similar to Settings > Agents but with the agent list on the left.

### Tasks

1. Create `_AdvancedSetupView` widget within `onboarding_screen.dart`:
   - Two-pane layout: sidebar (180px) + content area
   - Sidebar:
     - "Agents" header with icon
     - List of configured agents with colored dots, selected state
     - "Add New" button
     - "Done" button at bottom (returns to results phase, re-scans onboarding targets)
   - Content area (agent config form):
     - Title: agent name
     - Form fields: Name, Driver (dropdown), CLI Path (input + browse), Args, Environment (multiline), Model (dropdown), Permissions (dropdown)
     - Driver-specific fields (Codex sandbox/approval, ACP no-permissions notice)
2. Reuse logic from `_AgentsSettingsContentState` in `settings_screen.dart`:
   - Extract shared form-building logic into a reusable helper or mixin, OR
   - Duplicate the form fields with simplified layout (labels on the left instead of above)
   - Auto-save on blur/submit, same as settings
3. Add New: creates an agent with `AgentConfig.generateId()` and default values
4. Done button:
   - Re-run onboarding target probes to update results list
   - Return to results phase with updated agent list

### Definition of Done

- "Advanced..." button opens the sidebar editor
- Agents appear in the sidebar, clicking one shows its config form
- All form fields work: name, driver, CLI path, args, environment, model, permissions
- Add New creates a new agent in the sidebar
- Done returns to results with updated scan results
- Changes are persisted via SettingsService
- All existing tests pass

---

## Chunk 5: Tests & Cleanup

**Objective:** Add test coverage for the onboarding flow, remove the old `CliRequiredScreen`, and ensure everything is clean.

### Tasks

1. Write widget tests for `OnboardingScreen`:
   - Test scanning phase renders correctly (spinners, agent names)
   - Test transition to results phase after scan completes
   - Test all three results variants (none found, some found no Claude, some found with Claude)
   - Test Continue button disabled when no agents found
   - Test Continue button enabled when agents found
   - Test clicking a not-found agent navigates to setup screen
   - Test setup screen back button returns to results
   - Test Verify & Continue with valid/invalid paths
   - Test path-with-arguments splitting
   - Test warning banner appears only when Claude missing but others found
2. Update `FakeCliAvailabilityService` if needed to support per-agent scan simulation
3. Add tests for onboarding gate conditions:
   - first run (`onboarding.completed` missing/false)
   - no explicitly configured agents
   - launched-from-CLI bypass
4. Delete `frontend/lib/screens/cli_required_screen.dart`
5. Remove any remaining references to `CliRequiredScreen` in the codebase
6. Update `main.dart` tests that may reference the old Claude-only gate
7. Run full test suite: `./frontend/run-flutter-test.sh`
8. Run integration tests: `./frontend/run-flutter-test.sh integration_test/app_test.dart -d macos`

### Definition of Done

- Widget tests cover all onboarding phases and variants
- `CliRequiredScreen` is deleted, no references remain
- All tests pass (unit, widget, integration)
- No regressions in existing functionality
