# Config Screen Redesign

## Overview

Redesign the settings screen to follow desktop-native patterns like VSCode's settings UI. Replace mobile-style navigation patterns (tap → navigate → select → go back) with inline controls that work directly on the settings page.

## Current Problems

1. **Mobile-style navigation**: Clicking a setting opens a dialog/new screen to pick from options, then navigates back. This is slow and clunky for desktop.
2. **Too much vertical space**: Each setting takes significant height with large touch targets designed for mobile.
3. **Dialog-based selection**: Enum settings use `AlertDialog` with `RadioListTile` - requires multiple clicks for simple changes.
4. **Inconsistent density**: Switch tiles are compact but selection tiles are oversized.

## Design Goals

- **Inline editing**: All controls visible and usable directly on the settings page
- **Compact layout**: Reduce vertical space per setting; more settings visible without scrolling
- **Clear descriptions**: VSCode-style descriptions that explain what each setting does
- **Logical sections**: Group related settings with clear section headers
- **Keyboard accessible**: Support keyboard navigation and tab focus

## Visual Reference

VSCode settings pattern:
```
Section Name
────────────────────────────────────────

Setting Category: **Setting Name**
Description explaining what this setting does and when you might want
to change it.

[Dropdown ▼] or [Toggle] or [Text Input]

────────────────────────────────────────
```

## Layout Structure

### Sections

Organize settings into these sections (collapsible with disclosure triangles):

1. **Appearance** - Visual display options
2. **Behavior** - How the app responds to events
3. **Session Defaults** - Default values for new sessions
4. **Developer** - Debug and advanced options

### Setting Row Layout

Each setting row:
```
┌─────────────────────────────────────────────────────────────────┐
│ Section: **Setting Name**                        [Control]      │
│ Description text that wraps to multiple lines if needed.        │
│ Can include inline `code` formatting for values.                │
└─────────────────────────────────────────────────────────────────┘
```

- **Label**: "Section: **Name**" format (like "Appearance: Agents List Location")
- **Description**: Muted text below the label explaining the setting
- **Control**: Right-aligned, inline with the label
  - Dropdown for enums
  - Toggle switch for booleans
  - Text field for strings/numbers

### Spacing

- Section header: 24px top margin, 8px bottom margin
- Between settings within section: 16px
- Setting label to description: 4px
- Description to control: 8px (if control is below) or inline with label

## Component Specifications

### Section Header

```dart
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;

  // Renders:
  // ▼ Section Name
  // ─────────────────
}
```

- Disclosure triangle (▼/▶) for collapse/expand
- Section name in medium weight
- Subtle divider line below
- Click anywhere on header to toggle

### Setting Row

```dart
class _SettingRow extends StatelessWidget {
  final String category;    // e.g., "Appearance"
  final String name;        // e.g., "Agents List Location"
  final String description;
  final Widget control;
}
```

- Category + name in "Category: **Name**" format
- Description in smaller, muted text
- Control widget passed in (dropdown, switch, text field)

### Dropdown Control

For enum settings (AgentsListLocation, BashToolSummary, DefaultModel):

```dart
DropdownButton<T>(
  value: currentValue,
  items: options.map((opt) => DropdownMenuItem(
    value: opt.value,
    child: Text(opt.label),
  )).toList(),
  onChanged: (value) => config.set(key, value),
)
```

- Fixed width (200px) to prevent layout shifts
- Shows current selection
- Opens overlay menu (not dialog) on click
- Menu items show option name only (description in setting row)

### Toggle Control

For boolean settings:

```dart
Switch(
  value: config.get(key),
  onChanged: (value) => config.set(key, value),
)
```

- Standard macOS-style toggle switch
- No additional label (label is in setting row)

### Text/Number Input

For string and integer settings:

```dart
SizedBox(
  width: 80,  // narrow for numbers, wider for strings
  child: TextField(
    controller: _controller,
    decoration: InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    ),
    onSubmitted: (value) => config.set(key, parse(value)),
  ),
)
```

- Compact input field
- Submit on Enter or blur
- Validate input before saving

## Settings Organization

### Appearance

| Setting | Type | Description |
|---------|------|-------------|
| Agents List Location | Dropdown | Where to display the agents panel. **Vertical Panel** shows agents in a side panel. **Stacked** splits the side panel between sessions and agents. **Horizontal Toolbar** shows agents above the conversation. |
| Bash Tool Summary | Dropdown | How to display bash commands in the conversation. **Description** shows what the command does. **Command** shows the actual command text. |
| Relative File Paths | Toggle | Show file paths relative to the project directory instead of absolute paths. Makes tool output more readable for project files. |
| Show Timestamps | Toggle | Display timestamps in the conversation view. Helps track when messages were sent during long sessions. |
| Timestamp Idle Threshold | Number | Only show timestamps after this many minutes of inactivity. Set to `0` to show timestamps on every message. |

### Behavior

| Setting | Type | Description |
|---------|------|-------------|
| Auto-scroll on Message | Toggle | Automatically scroll to the bottom when new messages arrive. Disable to stay at your current scroll position while reviewing output. |
| Notify on Prompt | Toggle | Show a system notification when Claude asks for input. Useful when running long tasks in the background. |

### Session Defaults

| Setting | Type | Description |
|---------|------|-------------|
| Default Model | Dropdown | The model to use for new sessions. **Sonnet** is faster and cheaper. **Opus** is more capable for complex tasks. **Haiku** is fastest for simple queries. |

### Developer

| Setting | Type | Description |
|---------|------|-------------|
| Debug Logging | Toggle | Write debug information to the console. Enable when troubleshooting issues with the app. |
| Show Raw Messages | Toggle | Show a debug button on messages to inspect the raw JSON from the SDK. Useful for understanding the protocol. |

## Implementation Notes

### Remove Dialog-based Pickers

Replace `_showOptionsDialog()` calls with inline `DropdownButton` widgets. The dialog approach requires:
1. Tap setting tile
2. Wait for dialog animation
3. Select option
4. Wait for dialog dismiss
5. See updated value

With dropdown:
1. Click dropdown
2. Select option
3. Done

### Preserve Reset Functionality

Keep the "Reset to Defaults" button at the bottom, but style it more subtly:
- Text button instead of outlined button
- "Reset all settings to defaults" with confirmation dialog

### Search (Future Enhancement)

Consider adding a search field at the top to filter settings (like VSCode). Not required for initial implementation.

### Width Constraints

Settings panel should have a max-width constraint (~700px) and center in the available space. This prevents settings from stretching uncomfortably wide on large displays.

## Migration Path

1. Create new `_SettingRow` widget with inline controls
2. Create new `_SectionHeader` with collapse/expand
3. Refactor settings screen to use new components
4. Remove `_SettingsTile` and `_showOptionsDialog()`
5. Update tests for new widget structure
