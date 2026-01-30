# Draggable Panels - Feature Backlog

Features deferred from the MVP implementation, to be considered for future releases.

---

## Tab Merging (High Priority)

**Status:** Deferred from MVP
**Rationale:** Reduces MVP complexity while keeping core drag-and-drop functionality intact
**Estimated Effort:** Medium (1-2 weeks)

### Description

Enable dropping panels on other panel headers to merge them as tabbed groups. Users can:
- Drop a panel on another panel's header to create a tab group
- Switch between tabs by clicking tab headers
- Drag a tab out of a group to separate it back into a standalone panel

### Implementation Overview

#### Data Model Changes

Update `PanelStack` to support multiple panels:

```dart
class PanelStack {
  final String id;
  final List<PanelDefinition> panels; // Change from single panel to list
  final int activeIndex; // Which tab is active (0 if single panel)
  final double height;
}
```

**Migration:** Automatically convert existing single-panel stacks to `panels: [panel]` format.

#### New Drop Target Type

Add to `DropTargetType` enum:
```dart
enum DropTargetType {
  // ... existing types ...
  tabMerge, // Drop on panel header to merge as tab
}
```

#### UI Components

**Tab Header Widget:**
```dart
class _TabbedPanelHeader extends StatelessWidget {
  final PanelStack stack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < stack.panels.length; i++)
          _TabButton(
            panel: stack.panels[i],
            isActive: i == stack.activeIndex,
            onTap: () => _switchTab(i),
            onDragStart: () => _startTabDrag(i),
          ),
      ],
    );
  }
}
```

**Drop Target Zone:**
- Overlay on panel header area (36px height)
- Only visible during drag
- Expands and shows "MERGE AS TAB" label on hover

#### Drop Operation Logic

```dart
case DropTargetType.tabMerge:
  final targetStack = newColumns[target.targetColumnIndex]
      .stacks[target.targetStackIndex];

  // Insert dragged panel into target stack
  targetStack.panels.insert(
    target.targetPanelIndex + 1,
    draggingPanel!,
  );

  // Set newly added panel as active
  targetStack.activeIndex = target.targetPanelIndex + 1;
  break;
```

#### Tab Separation

Allow dragging individual tabs out of a group:
- Detect drag start on tab button (not entire header)
- Create new stack when tab is dropped outside the group
- Remove panel from original stack
- If last panel removed, delete the stack

### Acceptance Criteria

- [ ] Dropping panel on header creates tabbed group
- [ ] Tab headers display all panels in stack with icons and titles
- [ ] Active tab has visual highlight (primary container background, bottom border)
- [ ] Clicking tab switches active panel (updates `activeIndex`)
- [ ] Panel content changes when switching tabs
- [ ] Dragging tab header out of group separates it into new stack
- [ ] Removing last tab from group deletes the stack
- [ ] Tab state persists across app restarts
- [ ] Migration from single-panel stacks works seamlessly

### Testing Requirements

**Unit Tests:**
- [ ] Stack serialization with multiple panels
- [ ] Tab switching updates activeIndex
- [ ] Tab separation creates new stack

**Widget Tests:**
- [ ] Tabbed header renders all tabs
- [ ] Active tab has correct styling
- [ ] Tab click triggers state update

**Integration Tests:**
- [ ] Full tab merge flow (drag → drop → verify)
- [ ] Tab switching changes visible content
- [ ] Tab separation flow (drag tab → drop → verify new stack)
- [ ] Tab state persists after reload

### Visual Design

**Tab Header (Multiple Panels):**
```
┌─────────────────────────────────────┐
│ [📁 Sessions] [🤖 Agents*] [📊 Logs]│  ← Tabs with active indicator
├─────────────────────────────────────┤
│                                     │
│         Active Panel Content        │
│                                     │
└─────────────────────────────────────┘

* Active tab highlighted with primary-container background
```

**Drop Target on Header:**
```
┌─────────────────────────────────────┐
│ ┌─────────────────────────────────┐ │
│ │     MERGE AS TAB                │ │  ← Overlay on header
│ │  (dashed purple border + glow)  │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│         Panel Content               │
└─────────────────────────────────────┘
```

### Files to Modify

- `lib/models/panel_layout.dart` - Update `PanelStack` to support multiple panels
- `lib/widgets/panel_header.dart` - Add tabbed header variant
- `lib/widgets/panel_stack_widget.dart` - Add tab merge drop target overlay
- `lib/providers/panel_drag_controller.dart` - Add tab merge drop operation
- `test/integration/panel_tab_merge_test.dart` - New integration tests

### Risks & Mitigations

**Risk:** Migration from single-panel to multi-panel stacks breaks existing layouts
**Mitigation:** Thorough migration tests, automatic conversion of `panel` → `panels: [panel]`

**Risk:** Tab UI cluttered with many panels in one stack
**Mitigation:** Limit max tabs per stack to 5, add scroll if exceeded (future enhancement)

**Risk:** Confusing UX when dragging tabs vs dragging entire stack
**Mitigation:** Clear visual feedback - individual tab drag shows smaller ghost, whole stack drag shows full header

---

## Other Backlog Items

### Collapse to Icon (Low Priority)

**Description:** Minimize panels to icon-only mode to save space.

**Implementation Notes:**
- Add "collapsed" state to `PanelStack`
- Render vertical icon bar when collapsed
- Click icon to expand panel
- Drag icon to move collapsed panel

---

### Floating Panels (Low Priority)

**Description:** Detach panels into separate OS windows.

**Implementation Notes:**
- Requires multi-window support (platform-specific)
- macOS: Use `flutter_multi_window` package
- Panels marked as "floating" removed from main layout
- Persist floating window positions

**Blockers:**
- Multi-window support not yet stable in Flutter Desktop
- Complex state synchronization between windows

---

### Custom Panels (Medium Priority)

**Description:** Allow third-party extensions to register custom panel types.

**Implementation Notes:**
- Plugin system for panel type registration
- `PanelType` enum becomes extensible
- Custom panel widget factory pattern
- Panel metadata (icon, title, default config)

**Use Cases:**
- Custom log viewers
- API testing panels
- Database query panels
- Custom tool output visualizations

---

## Prioritization Criteria

Features are prioritized based on:
1. **User Impact** - How many users benefit?
2. **Implementation Complexity** - How much effort required?
3. **Dependency Chain** - Does it block other features?
4. **Risk** - How likely to introduce bugs?

**Current Priority Order:**
1. Tab Merging (High impact, medium complexity, no blockers)
2. Custom Panels (Medium impact, high complexity, requires plugin system)
3. Collapse to Icon (Low impact, low complexity, nice-to-have)
4. Floating Panels (Low impact, high complexity, platform blockers)
