# Onboarding — First Run Agent Discovery

## Context

CC-Insights currently shows a `CliRequiredScreen` when Claude CLI is not found on first launch. This is a hard gate: the app cannot proceed without Claude. With multi-agent support (Claude, Codex, Gemini, ACP), this needs to change. The new onboarding flow scans for all known agents, shows results, and lets the user set up missing agents or proceed with what's available.

**Mockup:** `docs/mocks/onboarding-flow-mockup.html`

**Replaces:** `CliRequiredScreen` (`frontend/lib/screens/cli_required_screen.dart`)

---

## Overview

The onboarding flow has three phases:

1. **Scan** — Detect all known agent CLIs on the system simultaneously
2. **Results** — Show what was found, let the user set up missing agents
3. **Continue** — Proceed to the Welcome/project selection screen

The flow is a single screen that transitions between states. It replaces the old `CliRequiredScreen` and the `!cliAvailability.claudeAvailable` gate in `main.dart`.

---

## Known Agents

The onboarding scan checks these canonical targets (independent of current
`agents.available` settings):

| Name           | Driver (when created) | Probe executable | Color   | Icon |
|----------------|-----------------------|------------------|---------|------|
| Claude         | `claude`              | `claude`         | Primary (deep purple) | `smart_toy` |
| Codex          | `codex`               | `codex`          | Green   | `smart_toy` |
| Gemini CLI     | `acp`                 | `gemini`         | Blue    | `smart_toy` |
| ACP Compatible | `acp`                 | (none)           | Orange  | `smart_toy` |

ACP Compatible is never scanned — it always shows as "Not configured" with a setup chevron, since there's no standard CLI name to detect.

---

## Phase 1: Scanning

Shown on first launch or when no agents have been configured yet.

### Layout

```
         [search icon, 56px, primary color]

       Setting up for the first time
    Looking for AI agents on your system...

  +-------------------------------------------+
  | [icon] Claude                             |
  |        Scanning...              [spinner] |
  +-------------------------------------------+
  +-------------------------------------------+
  | [icon] Codex                              |
  |        Scanning...              [spinner] |
  +-------------------------------------------+
  +-------------------------------------------+
  | [icon] Gemini CLI                         |
  |        Scanning...              [spinner] |
  +-------------------------------------------+

                  [ Cancel ]
```

### Behavior

- All scan targets run simultaneously (parallel probe calls)
- Each row shows a spinner while its scan is in progress
- As each scan completes, the row updates to show the result (found/not found) in place
- When all scans complete, the screen transitions to Phase 2
- Cancel returns to the Welcome screen without configuring agents

### Detection Strategy

Uses `CliAvailabilityService` executable probing (new helper for onboarding):

1. If a custom path is provided for this onboarding row, try that first
2. Otherwise probe the canonical executable name (e.g., `claude`, `codex`, `gemini`)
3. Probe by attempting `Process.start(executable, ['--version'])` with timeout (5s)
4. If process launch succeeds, treat as found and capture resolved executable path if available
5. If launch fails/times out, treat as not found

This onboarding probe is target-based; the existing `checkAgents()` path remains used
for availability refresh of configured agents after onboarding.

---

## Phase 2: Results

A single screen with three visual variants based on what was found. The layout is the same in all cases — only the title, header icon, warning banner, and Continue button state change.

### Agent Row States

Each agent row has two possible states:

**Found** — Green border, green check_circle icon, shows resolved path:
```
  +------------------------------------------+
  | [icon] Claude                            |
  |        Found at /usr/bin/claude   [tick] |
  +------------------------------------------+
```

**Not found** — Default border, clickable, chevron arrow navigates to setup:
```
  +------------------------------------------+
  | [icon] Codex                        [>]  |
  |        Not found                         |
  +------------------------------------------+
```

The ACP Compatible row is always present and always shows as "Not configured" with a chevron (it's never auto-detected).

### Variant A: None Found

Header icon: `search_off` (orange)

```
           [search_off icon, orange]

          No AI agents found
       Select one or more to set up:

  +------------------------------------------+
  | [icon] Claude                        [>] |
  |        Not found                         |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] Codex                         [>] |
  |        Not found                         |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] Gemini CLI                    [>] |
  |        Not found                         |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] ACP Compatible                [>] |
  |        Not configured                    |
  +------------------------------------------+

           [ Advanced... ] [ Continue ]
                            (disabled)
```

- Title: **"No AI agents found"**
- Subtitle: "Select one or more to set up:"
- Continue button is **disabled** — at least one agent must be configured
- All rows are clickable (chevron arrows)

### Variant B: Some Found, Claude Missing

Header icon: `manage_search` (orange)

```
         [manage_search icon, orange]

         Found some AI agents
  Agents with a tick were found on your system.
         Click others to set them up.

  +------------------------------------------+
  | [icon] Claude                        [>] |
  |        Not found                         |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] Codex                      [tick] |
  |        Found at /usr/local/bin/codex     |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] Gemini CLI                 [tick] |
  |        Found at /usr/local/bin/gemini    |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] ACP Compatible               [>] |
  |        Not configured                    |
  +------------------------------------------+

  +------------------------------------------+
  | [!] Claude has not been found, but       |
  |     other agents have. You can run this  |
  |     app without Claude, but currently    |
  |     it's recommended to have Claude as   |
  |     the app works best with Claude.      |
  +------------------------------------------+

           [ Advanced... ] [ Continue ]
```

- Title: **"Found some AI agents"**
- Warning banner shown because Claude specifically is missing
- Continue button is **enabled** — other agents are available
- Not-found rows are clickable, found rows are static

### Variant C: Some/All Found, Claude Present

Header icon: `check_circle` (green)

```
          [check_circle icon, green]

         Found some AI agents
  Agents with a tick were found on your system.
         Click others to set them up.

  +------------------------------------------+
  | [icon] Claude                     [tick] |
  |        Found at /usr/local/bin/claude    |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] Codex                         [>] |
  |        Not found                         |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] Gemini CLI                    [>] |
  |        Not found                         |
  +------------------------------------------+
  +------------------------------------------+
  | [icon] ACP Compatible                [>] |
  |        Not configured                    |
  +------------------------------------------+

           [ Advanced... ] [ Continue ]
```

- Title: **"Found some AI agents"**
- No warning banner (Claude is present)
- Continue button is **enabled**
- If ALL agents are found, subtitle changes to "All known agents were found on your system." and there are no clickable rows (all ticks)

### Header Icon Summary

| Condition | Icon | Color |
|-----------|------|-------|
| Scanning in progress | `search` | Primary (purple) |
| None found | `search_off` | Orange |
| Some found, Claude missing | `manage_search` | Orange |
| Some/all found, Claude present | `check_circle` | Green |

### Continue Button State

| Condition | State |
|-----------|-------|
| No agents found or configured | Disabled |
| At least one agent found or configured | Enabled |

---

## Agent Setup Screen

Shown when the user clicks a not-found agent row (chevron arrow). Each agent gets a dedicated setup screen with install instructions and manual path entry. This is similar to the existing `CliRequiredScreen` but scoped to a single agent.

### Layout

```
  [<- Back to agent selection]

  [agent icon, 48px]  Set Up <AgentName>

  Install the <AgentName> CLI or provide the path
  to an existing installation.

  Install <AgentName> CLI
  +------------------------------------------+
  | <install command>                 [copy] |
  +------------------------------------------+
                     or
  +------------------------------------------+
  | <alt install command>             [copy] |
  +------------------------------------------+

  Learn more at <docs-url>

  Or specify the path manually
  +---------------------------------------+--+
  | /usr/local/bin/<cli>                  |[]|
  +---------------------------------------+--+
  Tip: If you include arguments (e.g.,
  "/usr/bin/claude --model X"), they'll be
  separated automatically.

         [ Retry Detection ] [ Verify & Continue ]
```

### Per-Agent Install Instructions

**Claude:**
- `brew install --cask claude-code` or `curl -fsSL https://claude.ai/install.sh | bash`
- Docs: code.claude.com/docs

**Codex:**
- `npm install -g @openai/codex`
- Docs: github.com/openai/codex

**Gemini CLI:**
- `npm install -g @google/gemini-cli`
- Docs: appropriate URL

**ACP Compatible:**
- No standard install command — just the manual path entry and environment config

### Path with Arguments

If the user enters a path that contains arguments (e.g., `/usr/bin/claude --model X`), the app must:

1. Parse command-like input and split executable vs args (support quoted executable paths)
2. Store the executable portion in `AgentConfig.cliPath`
3. Store the remainder in `AgentConfig.cliArgs`
4. Show a brief confirmation (e.g., "Separated into path and arguments")

This handles the common case where users copy-paste a full command line.

### Verify & Continue

1. Save the custom path to the agent's `AgentConfig.cliPath` (and parsed args to `cliArgs`)
2. Re-run onboarding probe for that target via `CliAvailabilityService.probeExecutable(...)`
3. If found: return to the results screen with this agent now showing a tick
4. If not found: show error message in red below the input

### Retry Detection

Re-runs the onboarding executable probe for that target without a custom path override. Useful if the user just installed the CLI in another terminal.

---

## Advanced Setup Screen

Opened from the "Advanced..." button on the results screen. Provides a full agent configuration editor similar to Settings > Agents, but with the agent list in a sidebar on the left instead of above.

### Layout

```
+-----------+--------------------------------------+
| Agents    |                                      |
+-----------+ Claude                               |
|           | Configure the Claude agent backend   |
| * Claude  |                                      |
|   Codex   | Name:        [Claude              ]  |
|   Gemini  | Driver:      [claude           v  ]  |
|           | CLI Path:    [                 ][B]  |
| + Add New | Args:        [                    ]  |
|           | Environment: [                    ]  |
|           |              [                    ]  |
|           | Model:       [Opus 4.6         v  ]  |
|           | Permissions: [Default          v  ]  |
|           |                                      |
|  [Done]   |                                      |
+-----------+--------------------------------------+
```

### Behavior

- Sidebar lists all configured agents with a colored dot
- Clicking an agent shows its config form on the right
- "Add New" creates a new agent with default values
- The form fields match Settings > Agents: Name, Driver, CLI Path (with browse), CLI Args, Environment, Default Model, Default Permissions
- Driver-specific fields appear/hide based on the selected driver (e.g., Codex shows sandbox mode and approval policy)
- "Done" returns to the results screen
- Changes auto-save as the user edits (same behavior as Settings)

---

## Integration with Existing Code

### What Changes

| Component | Change |
|-----------|--------|
| `main.dart` `_buildScreen()` | Replace `!cliAvailability.claudeAvailable` gate with onboarding gate |
| `CliRequiredScreen` | Remove (replaced by agent setup screens within onboarding) |
| `CliAvailabilityService` | Add onboarding probe helper based on `Process.start` + timeout; keep `checkAgents()` for configured agents |
| `SettingsService` | Add onboarding completion flag and helper for "has explicitly configured agents" |
| `AgentConfig` | No changes — already has all needed fields |

### When to Show Onboarding

Show the onboarding screen when **all** of these are true:
- No project is selected (`!_projectSelected`)
- App not launched with a project path via CLI argument
- `onboarding.completed` is false/missing **OR** no agents are explicitly configured in `agents.available`

Do NOT show onboarding when:
- The app was launched with a project path via CLI argument
- A project is already selected

### After Onboarding

When the user clicks Continue:
1. Persist `onboarding.completed = true`
2. If no explicit agents are configured yet, create agent configs for discovered targets (and/or those manually configured during onboarding)
3. Refresh configured-agent availability via `checkAgents()`
4. Run `discoverModelsForAllAgents()` if at least one configured agent is available
5. Transition to the `WelcomeScreen` (project selection)

---

## Edge Cases

- **All scans timeout**: Treat as not found. Keep a 5-second timeout per probe.
- **User installs agent during onboarding**: Clicking "Retry Detection" on a setup screen or returning to the results screen re-scans.
- **Cancel during scan**: Return to Welcome screen. The app can still function if agents are configured later via Settings.
- **Only ACP configured**: Valid state — the user manually configured an ACP agent. Continue should be enabled.
- **Settings already exist from previous version**: Legacy migration in `SettingsService` converts old per-backend CLI paths to `AgentConfig` entries. If migration produced valid agents, skip onboarding.
- **No explicit agents configured but onboarding previously completed**: still show onboarding (requested behavior) until at least one agent is configured.
