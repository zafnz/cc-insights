# Feature Request: Drag-and-Drop Panel System

## Overview

Implement a flexible drag-and-drop panel system that allows users to rearrange panels by dragging their headers. Panels can be moved between stacks (vertical groups), reordered within stacks, and placed in new columns.

## Current State

The app currently has a fixed layout system with three modes:
- `verticalPanel`: Sessions | Agents | Conversation (3 fixed columns)
- `verticalPanelStacked`: Sessions + Agents stacked | Conversation (2 columns)
- `horizontalToolbar`: Sessions | Conversation with agent toolbar

Panel positions are not user-configurable beyond these presets. The existing `ResizablePanelContainer` handles drag-to-resize dividers but not drag-to-reorder.

## Interactive Mock

An interactive HTML mock demonstrating this feature is available at:
`docs/features/draggable-panels-mock.html`

Open it in a browser to try the drag-and-drop interaction:
```bash
open docs/features/draggable-panels-mock.html
```

## Desired Behavior

### Core Interaction

1. **Drag Initiation**: User clicks and drags a panel header
2. **Ghost Panel**: A semi-transparent preview of the panel follows the cursor (0.85 opacity, slight scale 1.02x, shadow)
3. **Drop Targets Appear**: All valid drop zones become visible immediately as dashed purple rectangles
4. **Drop Targets Expand**: Hovering over a drop target causes it to grow larger, making it easy to hit
5. **Drop**: Releasing over an active target moves the panel to that location
6. **Persistence**: New layout persists across app restarts

### Drop Target Types

When dragging a panel, all valid drop zones appear simultaneously with dashed borders and subtle purple background:

| Target Type | Description | Visual Indicator | Size (default → hover) |
|-------------|-------------|------------------|------------------------|
| **Insert Above** | Above an existing panel | Horizontal zone at top of panel | 24px → 48px height |
| **Insert Below** | Below an existing panel | Horizontal zone at bottom of panel | 24px → 48px height |
| **New Column Left** | Create column at left screen edge | Vertical zone at left edge | 40px → 80px width |
| **New Column Right** | Create column at right screen edge | Vertical zone at right edge | 40px → 80px width |
| **Tab Merge** | Drop on another panel's header | Overlay on header area | Header height, fills on hover |

### Example Transformations

**Starting layout:**
```
+-------+-------------------------+
|       |                         |
|  P1   |                         |
|       |          main           |
+-------+                         |
|  P2   |                         |
|       |                         |
+-------+-------------------------+
```

**Drag P2 to right of main → Creates 3 columns:**
```
+-------+------------------+------+
|       |                  |      |
|  P1   |       main       |  P2  |
|       |                  |      |
+-------+------------------+------+
```

**Drag P3 into P1/P2 stack → Stack of 3:**
```
+-------+-------------------------+
|  P1   |                         |
+-------+                         |
|  P2   |          main           |
+-------+                         |
|  P3   |                         |
+-------+-------------------------+
```

**Drag P2 above P1 → Reorder within stack:**
```
+-------+-------------------------+
|  P2   |                         |
+-------+          main           |
|  P1   |                         |
+-------+-------------------------+
```

## Technical Design

### Data Model

```dart
/// Represents the entire panel layout
class PanelLayout {
  final List<PanelColumn> columns;

  /// Main content column index (always exists, cannot be removed)
  final int mainColumnIndex;
}

/// A vertical column containing one or more panels
class PanelColumn {
  final List<PanelStack> stacks;

  /// Relative width (flex factor or fixed pixels)
  final double width;
}

/// A stack of panels (can be single panel or tabbed group)
class PanelStack {
  final List<PanelDefinition> panels;

  /// Active panel index if tabbed
  final int activeIndex;

  /// Relative height within column (flex factor)
  final double height;
}

/// Definition of a single panel
class PanelDefinition {
  final PanelType type;
  final String id;

  /// Panel-specific configuration
  final Map<String, dynamic> config;
}

enum PanelType {
  sessions,
  agents,
  output,
  logs,
  // Future: custom panels
}
```

### Layout Serialization

Store in `RuntimeConfig` as JSON:

```json
{
  "panelLayout": {
    "columns": [
      {
        "width": 200,
        "stacks": [
          {
            "height": 0.5,
            "panels": [{"type": "sessions", "id": "sessions-1"}],
            "activeIndex": 0
          },
          {
            "height": 0.5,
            "panels": [{"type": "agents", "id": "agents-1"}],
            "activeIndex": 0
          }
        ]
      },
      {
        "width": -1,
        "stacks": [
          {
            "height": 1.0,
            "panels": [{"type": "output", "id": "output-1"}],
            "activeIndex": 0
          }
        ]
      }
    ],
    "mainColumnIndex": 1
  }
}
```

Note: `width: -1` means "flex to fill remaining space" (the main content area).

### Widget Architecture

```
PanelLayoutRoot
├── PanelDragController (InheritedWidget - manages drag state)
│   └── Row (columns)
│       ├── PanelColumnWidget
│       │   └── Column (stacks)
│       │       ├── PanelStackWidget
│       │       │   ├── PanelHeader (draggable, shows tabs if multiple)
│       │       │   └── PanelContent
│       │       ├── ResizableDivider
│       │       └── PanelStackWidget
│       │           └── ...
│       ├── ResizableDivider
│       └── PanelColumnWidget
│           └── ...
└── DragOverlay (positioned layer for ghost panel + drop targets)
```

### Drag State Management

```dart
class PanelDragController extends ChangeNotifier {
  /// Currently dragging panel, null if not dragging
  PanelDefinition? draggingPanel;

  /// Source location of dragging panel
  PanelLocation? dragSource;

  /// Current cursor position (global coordinates)
  Offset? cursorPosition;

  /// Currently hovered drop target
  DropTarget? hoveredTarget;

  /// All valid drop targets for current drag
  List<DropTarget> validTargets;

  void startDrag(PanelDefinition panel, PanelLocation source);
  void updatePosition(Offset position);
  void hoverTarget(DropTarget? target);
  void endDrag(); // Cancel
  void completeDrop(DropTarget target); // Execute move
}
```

### Drop Target Detection

Use `RenderBox` hit testing to detect drop zones:

```dart
class DropTarget {
  final DropTargetType type;
  final Rect bounds;
  final PanelLocation targetLocation;

  /// Visual feedback position (where to draw indicator)
  final Offset indicatorPosition;
  final Axis indicatorAxis;
}

enum DropTargetType {
  stackTop,      // Drop above first panel in stack
  stackBottom,   // Drop below last panel in stack
  stackBetween,  // Drop between two panels in stack
  columnLeft,    // Drop to left of column
  columnRight,   // Drop to right of column
  tabMerge,      // Drop on panel header to create tabs
}
```

### Drop Target Zones

Drop targets are overlaid on each panel and at screen edges. They are invisible until a drag begins, then all appear simultaneously:

```
+---------------------------+
|  ┌─────────────────────┐  |
|  │   INSERT ABOVE      │  |  ← 24px zone, grows to 48px on hover
|  │   (dashed border)   │  |
|  └─────────────────────┘  |
+---------------------------+
|  ┌─────────────────────┐  |
|  │   TAB MERGE         │  |  ← Overlays header area
|  │   (on header)       │  |
|  └─────────────────────┘  |
+---------------------------+
|                           |
|    [content area]         |  ← No drop target here
|                           |
+---------------------------+
|  ┌─────────────────────┐  |
|  │   INSERT BELOW      │  |  ← 24px zone, grows to 48px on hover
|  │   (dashed border)   │  |
|  └─────────────────────┘  |
+---------------------------+
```

Screen edges (fixed position, always visible during drag):
```
┌──────┐                              ┌──────┐
│      │                              │      │
│  +   │   ← 40px zone                │  +   │   ← 40px zone
│ COL  │     grows to 80px            │ COL  │     grows to 80px
│      │                              │      │
└──────┘                              └──────┘
 LEFT EDGE                            RIGHT EDGE
```

### Visual Feedback

**During Drag - Panel Dimming:**
- All panels dim to 0.7 opacity to make drop targets more visible
- The source panel (being dragged) dims further to 0.4 opacity

**Ghost Panel:**
- Semi-transparent (0.85 opacity) clone of panel header + truncated content
- Slight scale up (1.02x) with drop shadow
- Follows cursor with offset from grab point
- Header uses accent color (primary-container) background
- Max width capped at 300px

**Drop Targets (Idle State):**
- Dashed 2px border in accent color (purple)
- Subtle semi-transparent background (`rgba(208, 188, 255, 0.15)`)
- Labels hidden until hover

**Drop Targets (Hover/Active State):**
- Target expands to larger size (see table above)
- Brighter background (`rgba(208, 188, 255, 0.35)`)
- Glow effect: `box-shadow: 0 0 20px` with accent color
- Label appears: "Insert Above", "Insert Below", "Merge as Tab", "+ Column"
- Label styled: uppercase, small font, text-shadow glow

**Cursor:**
- Changes to `grabbing` during entire drag operation
- No "not-allowed" state - targets simply don't activate if invalid

### Constraints

1. **Main panel cannot be removed** - The output/conversation panel must always exist
2. **Minimum panel size** - Panels have minimum width (150px) and height (100px)
3. **Maximum columns** - Limit to 4 columns to prevent unusable layouts
4. **Maximum stack depth** - Limit to 5 panels per stack
5. **No empty columns** - Removing last panel from column removes the column

### Animation & Transitions

**CSS Transitions (all 0.2s ease):**
- Drop target opacity (0 → 1 on drag start)
- Drop target size expansion on hover
- Drop target background color change
- Label opacity (0 → 1 on hover)

**Drag Start:**
- Ghost panel appears instantly at cursor
- All drop targets fade in simultaneously
- Source panel dims

**Drop Target Hover:**
- Target smoothly expands to larger size
- Background brightens
- Glow effect appears
- Label fades in

**Drop Complete:**
- Ghost panel disappears
- Layout re-renders with panel in new position
- All drop targets fade out

## Implementation Phases

### Phase 1: Layout Model & Persistence
- [ ] Define `PanelLayout`, `PanelColumn`, `PanelStack`, `PanelDefinition` classes
- [ ] Add JSON serialization/deserialization
- [ ] Add to `RuntimeConfig` with migration from old layout settings
- [ ] Build `PanelLayoutWidget` that renders from model (no drag yet)

### Phase 2: Basic Drag & Drop
- [ ] Create `PanelDragController` state management
- [ ] Make panel headers draggable (GestureDetector + Draggable)
- [ ] Implement ghost panel overlay
- [ ] Basic drop target detection (stack reordering only)
- [ ] Execute drops and update model

### Phase 3: Column Operations
- [ ] Add column edge drop targets
- [ ] Add screen edge drop targets for new columns
- [ ] Handle column creation and removal
- [ ] Maintain column width ratios on reflow

### Phase 4: Tab Merging
- [ ] Add tab merge drop target (header hover)
- [ ] Render tabbed panel headers
- [ ] Tab selection and switching
- [ ] Drag tabs out to unmerge

### Phase 5: Polish
- [ ] Animations (drag start, drop, reflow)
- [ ] Keyboard support (Escape to cancel drag)
- [ ] Touch support (long-press to initiate)
- [ ] Undo support (Cmd+Z to revert last move)
- [ ] Layout presets (save/load named layouts)

## Testing Requirements

### Unit Tests
- Layout model serialization round-trip
- Drop target calculation for various layouts
- Constraint validation (min sizes, max columns)
- Layout mutation operations (move, merge, split)

### Widget Tests
- Drag initiation from panel header
- Drop target highlighting on hover
- Drop execution updates layout
- Ghost panel follows cursor
- Cancel drag with Escape key

### Integration Tests
- Full drag-and-drop flow
- Layout persistence across restart
- Migration from old layout settings

## Open Questions

1. **Locked panels?** Should some panels be lockable (non-draggable)?
2. **Panel duplication?** Can a panel type appear multiple times (e.g., two log viewers)?
3. **Collapse to icon?** Should panels be collapsible to just an icon in a dock?
4. **Floating panels?** Should panels be detachable to floating windows?
5. **Reset layout?** Easy way to return to default layout?

## Files to Create/Modify

### New Files
- `lib/models/panel_layout.dart` - Data model
- `lib/widgets/panel_layout_root.dart` - Root layout widget
- `lib/widgets/panel_column_widget.dart` - Column container
- `lib/widgets/panel_stack_widget.dart` - Stack container
- `lib/widgets/panel_header.dart` - Draggable header
- `lib/widgets/panel_drag_overlay.dart` - Ghost + targets overlay
- `lib/providers/panel_drag_controller.dart` - Drag state
- `test/widget/panel_drag_test.dart` - Widget tests
- `test/integration/panel_layout_test.dart` - Integration tests

### Modified Files
- `lib/services/runtime_config.dart` - Add panelLayout config
- `lib/screens/home_screen.dart` - Replace fixed layout with PanelLayoutRoot
- `lib/widgets/session_list.dart` - Wrap with panel header
- `lib/widgets/agent_tree.dart` - Wrap with panel header
- `lib/widgets/output_panel.dart` - Wrap with panel header

## Acceptance Criteria

- [ ] User can drag any panel header and see ghost preview (0.85 opacity, 1.02x scale, shadow)
- [ ] All valid drop targets appear immediately when drag starts (dashed purple borders)
- [ ] Drop targets expand when cursor hovers over them
- [ ] Drop target labels appear on hover ("Insert Above", "Insert Below", etc.)
- [ ] Panels dim during drag (0.7 opacity, source panel 0.4)
- [ ] Dropping on "Insert Above/Below" inserts panel at that position
- [ ] Dropping on screen edge "New Column" zones creates new column
- [ ] Dropping on panel header merges panels (tab merge)
- [ ] Tabs can be reordered by dragging within header
- [ ] Tab can be dragged out to separate from group
- [ ] Layout persists across app restart
- [ ] Escape key cancels drag operation
- [ ] Main content panel cannot be closed
- [ ] Minimum panel sizes are enforced
- [ ] All transitions animate smoothly (0.2s ease)
