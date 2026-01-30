# Implementation Plan: Drag-and-Drop Panel System

## Overview

Transform the current fixed layout system (3 preset modes) into a flexible drag-and-drop panel system where users can freely rearrange panels by dragging headers, create new columns, and stack panels.

**Key Design Principle:** This feature replaces the existing rigid layout system while maintaining backward compatibility through migration.

**Note:** Tab merging (dropping panels on headers to create tabbed groups) is deferred to the backlog and not included in this MVP implementation.

---

## Current State Analysis

### Existing Layout System (home_screen.dart:232-469)

The app currently has **three fixed layout modes**:

1. **verticalPanel** - Sessions | Agents | Conversation (3 columns)
2. **verticalPanelStacked** - (Sessions + Agents stacked) | Conversation (2 columns)
3. **horizontalToolbar** - Sessions | Conversation (with agent toolbar overlay)

**Configuration stored in RuntimeConfig:**
- `agentsListLocation` (enum) - which layout mode
- `sidePanelWidth` (double) - sessions panel width
- `agentsPanelWidth` (double) - agents panel width in 3-column mode
- `stackedDividerFraction` (double) - sessions/agents split in stacked mode

**Current Resizing System:**
- `ResizablePanelContainer` widget handles drag-to-resize dividers
- Saves divider positions to RuntimeConfig
- Does NOT support drag-to-reorder

### Panel Types Available

- **SessionList** (`session_list.dart`) - List of active sessions
- **AgentTree** (`agent_tree.dart`) - Hierarchical agent view
- **ConversationPanel** (`conversation_panel.dart`) - Main chat interface
- **LogViewer** (`log_viewer.dart`) - Backend logs (currently accessible but not in main layout)

---

## Phase 1: Data Model & Serialization (Foundation)

**Goal:** Define the layout data structure and integrate with RuntimeConfig.

### 1.1 Create Panel Layout Models

**File:** `flutter_app/lib/models/panel_layout.dart`

```dart
/// Represents the entire panel layout configuration
class PanelLayout {
  final List<PanelColumn> columns;
  final int mainColumnIndex; // Index of column containing ConversationPanel (cannot be removed)

  const PanelLayout({
    required this.columns,
    required this.mainColumnIndex,
  });

  // JSON serialization
  Map<String, dynamic> toJson();
  factory PanelLayout.fromJson(Map<String, dynamic> json);

  // Default layouts (replaces current 3 presets)
  factory PanelLayout.verticalPanel();
  factory PanelLayout.verticalPanelStacked();
  factory PanelLayout.horizontalToolbar();
}

/// A vertical column containing one or more panel stacks
class PanelColumn {
  final String id;
  final List<PanelStack> stacks;
  final double width; // Pixels if > 0, -1 means flex (fill remaining space)

  // JSON serialization
  Map<String, dynamic> toJson();
  factory PanelColumn.fromJson(Map<String, dynamic> json);
}

/// A stack of panels (single panel in MVP - tab support deferred to backlog)
class PanelStack {
  final String id;
  final PanelDefinition panel; // Single panel per stack in MVP
  final double height; // Flex factor within column (0.0-1.0, default 1.0)

  // JSON serialization
  Map<String, dynamic> toJson();
  factory PanelStack.fromJson(Map<String, dynamic> json);
}

/// Definition of a single panel instance
class PanelDefinition {
  final PanelType type;
  final String id; // Unique instance ID
  final Map<String, dynamic> config; // Panel-specific configuration

  // JSON serialization
  Map<String, dynamic> toJson();
  factory PanelDefinition.fromJson(Map<String, dynamic> json);
}

enum PanelType {
  sessions,
  agents,
  conversation,
  logs,
}
```

### 1.2 Integrate with RuntimeConfig

**File:** `flutter_app/lib/services/runtime_config.dart`

**Add to ConfigKey enum:**
```dart
/// Panel layout configuration (replaces agentsListLocation)
panelLayout,
```

**Add to _defaults:**
```dart
ConfigKey.panelLayout: null, // null means use default from PanelLayout.horizontalToolbar()
```

**Add typed getter:**
```dart
PanelLayout? get panelLayout => get(ConfigKey.panelLayout);
```

**Add serialization support:**
- Update `_serializeValue()` to handle `PanelLayout` → JSON
- Update `_deserializeValue()` to handle JSON → `PanelLayout`

### 1.3 Migration Logic

**File:** `flutter_app/lib/services/runtime_config.dart`

Add migration in `_loadFromFile()`:

```dart
// After loading from file, check if we need to migrate old layout settings
if (!_overrides.containsKey(ConfigKey.panelLayout)) {
  // Migrate from old agentsListLocation setting
  final oldLocation = get<AgentsListLocation>(ConfigKey.agentsListLocation);
  final oldSideWidth = get<double>(ConfigKey.sidePanelWidth);
  final oldAgentsWidth = get<double>(ConfigKey.agentsPanelWidth);
  final oldStackedFraction = get<double>(ConfigKey.stackedDividerFraction);

  // Create PanelLayout from old settings
  final migratedLayout = _migrateFromOldLayout(
    oldLocation, oldSideWidth, oldAgentsWidth, oldStackedFraction
  );

  _overrides[ConfigKey.panelLayout] = migratedLayout;

  // Remove old keys
  _overrides.remove(ConfigKey.agentsListLocation);
  _overrides.remove(ConfigKey.sidePanelWidth);
  _overrides.remove(ConfigKey.agentsPanelWidth);
  _overrides.remove(ConfigKey.stackedDividerFraction);

  _saveToFile(); // Persist migration
}
```

### 1.4 Acceptance Criteria - Phase 1

- [ ] `PanelLayout` model classes serialize/deserialize to/from JSON correctly
- [ ] RuntimeConfig can save and load `PanelLayout`
- [ ] Migration converts old layout settings to new `PanelLayout` on first load
- [ ] Default layouts (verticalPanel, verticalPanelStacked, horizontalToolbar) can be instantiated
- [ ] Unit tests verify round-trip serialization
- [ ] Unit tests verify migration from all 3 old layout modes

---

## Phase 2: Render Layout from Model (Display)

**Goal:** Build widgets that render the layout from the PanelLayout model (no dragging yet).

### 2.1 Create Layout Rendering Widgets

**File:** `flutter_app/lib/widgets/panel_layout_root.dart`

Root widget that renders the entire panel layout:

```dart
class PanelLayoutRoot extends StatelessWidget {
  const PanelLayoutRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.read<RuntimeConfig>();
    final layout = config.panelLayout ?? PanelLayout.horizontalToolbar();

    return Row(
      children: [
        for (int i = 0; i < layout.columns.length; i++) ...[
          PanelColumnWidget(
            column: layout.columns[i],
            columnIndex: i,
          ),
          if (i < layout.columns.length - 1)
            _ResizableDivider(
              direction: Axis.vertical,
              columnIndex: i,
            ),
        ],
      ],
    );
  }
}
```

**File:** `flutter_app/lib/widgets/panel_column_widget.dart`

Renders a single column of panel stacks:

```dart
class PanelColumnWidget extends StatelessWidget {
  final PanelColumn column;
  final int columnIndex;

  const PanelColumnWidget({
    super.key,
    required this.column,
    required this.columnIndex,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: column.width > 0 ? column.width : null,
      child: Column(
        children: [
          for (int i = 0; i < column.stacks.length; i++) ...[
            Expanded(
              flex: (column.stacks[i].height * 100).toInt(),
              child: PanelStackWidget(
                stack: column.stacks[i],
                columnIndex: columnIndex,
                stackIndex: i,
              ),
            ),
            if (i < column.stacks.length - 1)
              _ResizableDivider(
                direction: Axis.horizontal,
                columnIndex: columnIndex,
                stackIndex: i,
              ),
          ],
        ],
      ),
    );
  }
}
```

**File:** `flutter_app/lib/widgets/panel_stack_widget.dart`

Renders a single panel with header:

```dart
class PanelStackWidget extends StatelessWidget {
  final PanelStack stack;
  final int columnIndex;
  final int stackIndex;

  const PanelStackWidget({
    super.key,
    required this.stack,
    required this.columnIndex,
    required this.stackIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Panel header (draggable in Phase 3)
        PanelHeader(
          panel: stack.panel,
          columnIndex: columnIndex,
          stackIndex: stackIndex,
        ),
        // Panel content
        Expanded(
          child: _buildPanelContent(stack.panel),
        ),
      ],
    );
  }

  Widget _buildPanelContent(PanelDefinition panel) {
    switch (panel.type) {
      case PanelType.sessions:
        return const SessionList();
      case PanelType.agents:
        return Consumer<SessionProvider>(
          builder: (context, provider, _) {
            final session = provider.selectedSession;
            if (session == null) return const SizedBox();
            return AgentTree(session: session);
          },
        );
      case PanelType.conversation:
        return Consumer<SessionProvider>(
          builder: (context, provider, _) {
            // Use existing logic from home_screen.dart _buildMainPanel
            return _buildConversationContent(provider);
          },
        );
      case PanelType.logs:
        return const LogViewer();
    }
  }
}
```

**File:** `flutter_app/lib/widgets/panel_header.dart`

Panel header with title (simplified for MVP - no tabs):

```dart
class PanelHeader extends StatelessWidget {
  final PanelDefinition panel;
  final int columnIndex;
  final int stackIndex;

  const PanelHeader({
    super.key,
    required this.panel,
    required this.columnIndex,
    required this.stackIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(_getPanelIcon(panel.type), size: 16),
            const SizedBox(width: 8),
            Text(
              _getPanelTitle(panel.type),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 2.2 Update home_screen.dart

Replace `_buildMainContent()` to use new layout system:

```dart
Widget _buildMainContent(BuildContext context) {
  return Row(
    children: [
      const VerticalNavBar(),
      Expanded(
        child: PanelLayoutRoot(),
      ),
    ],
  );
}
```

Remove old layout methods:
- `_buildVerticalPanelLayout()`
- `_buildVerticalPanelStackedLayout()`
- `_buildHorizontalToolbarLayout()`
- `_buildStackedSidePanel()`

### 2.3 Acceptance Criteria - Phase 2

- [ ] App renders layout from `PanelLayout` model
- [ ] All 3 default layouts display correctly
- [ ] Panels show correct content (sessions, agents, conversation, logs)
- [ ] Resizable dividers still work (inherited from ResizablePanelContainer)
- [ ] Visual regression tests pass for all 3 default layouts

---

## Phase 3: Drag & Drop - Basic Reordering

**Goal:** Enable drag-to-reorder panels within stacks and between stacks in the same column.

### 3.1 Create Drag State Management

**File:** `flutter_app/lib/providers/panel_drag_controller.dart`

```dart
class PanelDragController extends ChangeNotifier {
  // Currently dragging panel
  PanelDefinition? draggingPanel;

  // Source location
  int? sourceColumnIndex;
  int? sourceStackIndex;
  int? sourcePanelIndex;

  // Current cursor position (for ghost panel)
  Offset? cursorPosition;

  // Currently hovered drop target
  DropTarget? hoveredTarget;

  // All valid drop targets for current drag
  List<DropTarget> validTargets = [];

  bool get isDragging => draggingPanel != null;

  void startDrag({
    required PanelDefinition panel,
    required int columnIndex,
    required int stackIndex,
    required int panelIndex,
    required Offset initialPosition,
  }) {
    draggingPanel = panel;
    sourceColumnIndex = columnIndex;
    sourceStackIndex = stackIndex;
    sourcePanelIndex = panelIndex;
    cursorPosition = initialPosition;

    // Calculate valid drop targets
    _calculateDropTargets();

    notifyListeners();
  }

  void updatePosition(Offset position) {
    cursorPosition = position;
    notifyListeners();
  }

  void hoverTarget(DropTarget? target) {
    hoveredTarget = target;
    notifyListeners();
  }

  void endDrag() {
    draggingPanel = null;
    sourceColumnIndex = null;
    sourceStackIndex = null;
    sourcePanelIndex = null;
    cursorPosition = null;
    hoveredTarget = null;
    validTargets = [];
    notifyListeners();
  }

  Future<void> completeDrop(DropTarget target) async {
    if (draggingPanel == null) return;

    // Execute the drop operation (update layout in RuntimeConfig)
    await _executeDropOperation(target);

    endDrag();
  }

  void _calculateDropTargets() {
    // Generate list of valid drop zones
    // - Insert above each panel
    // - Insert below each panel
  }

  Future<void> _executeDropOperation(DropTarget target) async {
    // Update PanelLayout in RuntimeConfig
    final config = RuntimeConfig.instance;
    final currentLayout = config.panelLayout ?? PanelLayout.horizontalToolbar();

    // Clone layout and apply mutation
    final newLayout = _applyDropOperation(currentLayout, target);

    // Save to config
    config.set(ConfigKey.panelLayout, newLayout);
  }
}

class DropTarget {
  final DropTargetType type;
  final Rect bounds; // Position on screen
  final int targetColumnIndex;
  final int targetStackIndex;
  final int targetPanelIndex;

  const DropTarget({
    required this.type,
    required this.bounds,
    required this.targetColumnIndex,
    required this.targetStackIndex,
    required this.targetPanelIndex,
  });
}

enum DropTargetType {
  insertAbove,
  insertBelow,
  newColumnLeft,
  newColumnRight,
}
```

### 3.2 Make Panel Headers Draggable

**Update:** `flutter_app/lib/widgets/panel_header.dart`

```dart
class PanelHeader extends StatelessWidget {
  // ... existing code ...

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        final controller = context.read<PanelDragController>();
        controller.startDrag(
          panel: panel,
          columnIndex: columnIndex,
          stackIndex: stackIndex,
          panelIndex: 0, // Single panel per stack in MVP
          initialPosition: details.globalPosition,
        );
      },
      onPanUpdate: (details) {
        final controller = context.read<PanelDragController>();
        controller.updatePosition(details.globalPosition);
      },
      onPanEnd: (details) {
        final controller = context.read<PanelDragController>();
        if (controller.hoveredTarget != null) {
          controller.completeDrop(controller.hoveredTarget!);
        } else {
          controller.endDrag();
        }
      },
      child: Container(
        // ... existing header UI with cursor: grabbing style during drag
      ),
    );
  }
}
```

### 3.3 Create Drag Overlay with Ghost Panel and Drop Targets

**File:** `flutter_app/lib/widgets/panel_drag_overlay.dart`

```dart
class PanelDragOverlay extends StatelessWidget {
  const PanelDragOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PanelDragController>(
      builder: (context, controller, _) {
        if (!controller.isDragging) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            // Dim all panels during drag
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),

            // Drop targets
            ...controller.validTargets.map((target) {
              return Positioned.fromRect(
                rect: target.bounds,
                child: _DropTargetIndicator(target: target),
              );
            }),

            // Ghost panel following cursor
            if (controller.cursorPosition != null)
              Positioned(
                left: controller.cursorPosition!.dx - 150,
                top: controller.cursorPosition!.dy - 18,
                child: _GhostPanel(panel: controller.draggingPanel!),
              ),
          ],
        );
      },
    );
  }
}

class _DropTargetIndicator extends StatelessWidget {
  final DropTarget target;

  const _DropTargetIndicator({required this.target});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        context.read<PanelDragController>().hoverTarget(target);
      },
      onExit: (_) {
        context.read<PanelDragController>().hoverTarget(null);
      },
      child: Consumer<PanelDragController>(
        builder: (context, controller, _) {
          final isHovered = controller.hoveredTarget == target;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              borderRadius: BorderRadius.circular(isHovered ? 8 : 4),
              color: Theme.of(context).colorScheme.primary.withOpacity(
                isHovered ? 0.35 : 0.15,
              ),
            ),
            child: isHovered
                ? Center(
                    child: Text(
                      _getDropLabel(target.type),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }

  String _getDropLabel(DropTargetType type) {
    switch (type) {
      case DropTargetType.insertAbove: return 'INSERT ABOVE';
      case DropTargetType.insertBelow: return 'INSERT BELOW';
      case DropTargetType.newColumnLeft: return '+ COLUMN';
      case DropTargetType.newColumnRight: return '+ COLUMN';
    }
  }
}

class _GhostPanel extends StatelessWidget {
  final PanelDefinition panel;

  const _GhostPanel({required this.panel});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.85,
      child: Transform.scale(
        scale: 1.02,
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getPanelIcon(panel.type), size: 16),
                const SizedBox(width: 8),
                Text(
                  _getPanelTitle(panel.type),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### 3.4 Acceptance Criteria - Phase 3

- [ ] Dragging a panel header shows ghost panel following cursor
- [ ] All valid drop targets appear immediately when drag starts
- [ ] Drop targets expand and show labels on hover
- [ ] Dropping on "Insert Above" moves panel above target
- [ ] Dropping on "Insert Below" moves panel below target
- [ ] Pressing Escape cancels drag
- [ ] Layout persists after drag-and-drop
- [ ] Widget tests verify drag gesture handling
- [ ] Integration test verifies full drag-drop-persist flow

---

## Phase 4: Column Operations

**Goal:** Enable creating new columns and moving panels between columns.

### 4.1 Add Screen Edge Drop Targets

**Update:** `flutter_app/lib/widgets/panel_drag_overlay.dart`

Add fixed-position drop targets at left and right screen edges:

```dart
// In PanelDragOverlay build method
Stack(
  children: [
    // ... existing drop targets ...

    // Screen edge targets
    Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 40,
      child: _EdgeDropTarget(type: DropTargetType.newColumnLeft),
    ),
    Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 40,
      child: _EdgeDropTarget(type: DropTargetType.newColumnRight),
    ),
  ],
);
```

### 4.2 Update Drop Operation Handler

**Update:** `flutter_app/lib/providers/panel_drag_controller.dart`

Extend `_executeDropOperation()` to handle column creation:

```dart
PanelLayout _applyDropOperation(PanelLayout layout, DropTarget target) {
  // Clone the layout
  final newColumns = List<PanelColumn>.from(layout.columns);

  // Remove panel from source
  _removePanel(newColumns, sourceColumnIndex!, sourceStackIndex!, sourcePanelIndex!);

  // Insert panel at target based on drop type
  switch (target.type) {
    case DropTargetType.newColumnLeft:
      newColumns.insert(0, PanelColumn(
        id: 'col-${DateTime.now().millisecondsSinceEpoch}',
        width: 200,
        stacks: [
          PanelStack(
            id: 'stack-${DateTime.now().millisecondsSinceEpoch}',
            panel: draggingPanel!,
            height: 1.0,
          ),
        ],
      ));
      break;

    case DropTargetType.newColumnRight:
      newColumns.add(PanelColumn(
        id: 'col-${DateTime.now().millisecondsSinceEpoch}',
        width: 200,
        stacks: [
          PanelStack(
            id: 'stack-${DateTime.now().millisecondsSinceEpoch}',
            panel: draggingPanel!,
            height: 1.0,
          ),
        ],
      ));
      break;

    // ... other drop types ...
  }

  // Clean up empty columns and stacks
  _cleanupEmptyContainers(newColumns);

  // Ensure main column still exists
  _ensureMainColumn(newColumns);

  return PanelLayout(
    columns: newColumns,
    mainColumnIndex: _findMainColumnIndex(newColumns),
  );
}
```

### 4.3 Enforce Constraints

Add constraint validation:

```dart
bool _canCreateNewColumn(PanelLayout layout) {
  return layout.columns.length < 4; // Max 4 columns
}

void _ensureMainColumn(List<PanelColumn> columns) {
  // Ensure at least one column contains a conversation panel
  final hasConversation = columns.any((col) =>
    col.stacks.any((stack) => stack.panel.type == PanelType.conversation)
  );

  if (!hasConversation) {
    // Re-add conversation panel to first column
    columns.first.stacks.add(PanelStack(
      id: 'main-stack',
      panel: PanelDefinition(
        type: PanelType.conversation,
        id: 'conversation-1',
        config: {},
      ),
      height: 1.0,
    ));
  }
}
```

### 4.4 Acceptance Criteria - Phase 4

- [ ] Dropping on left edge creates new column on left
- [ ] Dropping on right edge creates new column on right
- [ ] New columns have default width of 200px
- [ ] Removing last panel from column removes the column
- [ ] Cannot create more than 4 columns
- [ ] Main conversation panel cannot be removed from layout
- [ ] Integration test verifies column creation and cleanup

---

## Phase 5: Polish & User Experience

**Goal:** Animations, keyboard support, touch support, and quality-of-life features.

### 5.1 Add Animations

**Update:** All drag/drop widgets to use `AnimatedContainer` and `AnimatedOpacity`

```dart
// Drop target expansion
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  height: isHovered ? 48 : 24,
  ...
);

// Panel dimming during drag
AnimatedOpacity(
  duration: const Duration(milliseconds: 200),
  opacity: isDragging ? 0.7 : 1.0,
  child: panel,
);
```

### 5.2 Keyboard Support

**File:** `flutter_app/lib/widgets/panel_layout_root.dart`

Add keyboard listener:

```dart
return Focus(
  onKey: (node, event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      final controller = context.read<PanelDragController>();
      if (controller.isDragging) {
        controller.endDrag();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  },
  child: PanelLayoutRoot(...),
);
```

### 5.3 Touch Support

**Update:** `flutter_app/lib/widgets/panel_header.dart`

Add long-press gesture for touch devices:

```dart
return GestureDetector(
  onPanStart: _handleDragStart,
  onLongPressStart: _handleDragStart, // Touch support
  ...
);
```

### 5.4 Layout Presets

**File:** `flutter_app/lib/widgets/layout_preset_menu.dart`

Add UI for saving/loading named layouts:

```dart
class LayoutPresetMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      itemBuilder: (context) => [
        PopupMenuItem(
          child: Text('Save current layout as...'),
          onTap: () => _savePreset(context),
        ),
        PopupMenuItem(
          child: Text('Reset to default'),
          onTap: () => _resetToDefault(context),
        ),
        const PopupMenuDivider(),
        // List saved presets
        ...context.read<RuntimeConfig>().savedLayoutPresets.map((preset) {
          return PopupMenuItem(
            child: Text(preset.name),
            onTap: () => _loadPreset(context, preset),
          );
        }),
      ],
    );
  }
}
```

### 5.5 Acceptance Criteria - Phase 5

- [ ] All transitions animate smoothly (200ms duration)
- [ ] Escape key cancels drag in progress
- [ ] Long-press initiates drag on touch devices
- [ ] Users can save named layout presets
- [ ] Users can reset to default layout
- [ ] Animations don't degrade performance (60fps maintained)

---

## Testing Strategy

### Unit Tests

**File:** `flutter_app/test/models/panel_layout_test.dart`
- [ ] Layout serialization round-trip
- [ ] Default layout factories produce valid layouts
- [ ] Constraint validation (max columns, min sizes)

**File:** `flutter_app/test/services/runtime_config_test.dart`
- [ ] Migration from old layout settings
- [ ] PanelLayout save/load to config file

**File:** `flutter_app/test/providers/panel_drag_controller_test.dart`
- [ ] Drop target calculation
- [ ] Drop operation execution
- [ ] Layout mutation functions

### Widget Tests

**File:** `flutter_app/test/widget/panel_header_test.dart`
- [ ] Panel header renders correctly with title and icon

**File:** `flutter_app/test/widget/panel_drag_overlay_test.dart`
- [ ] Ghost panel follows cursor position
- [ ] Drop targets appear on drag start
- [ ] Drop targets highlight on hover

### Integration Tests

**File:** `flutter_app/test/integration/panel_drag_drop_test.dart`
- [ ] Full drag-and-drop flow (start → move → drop)
- [ ] Layout persistence after drop
- [ ] Column creation and removal
- [ ] Cancel drag with Escape key

---

## Migration Plan

### Backward Compatibility

Users upgrading from the old layout system will have their settings automatically migrated:

1. **First launch after update:**
   - `_loadFromFile()` detects absence of `ConfigKey.panelLayout`
   - Reads old `agentsListLocation`, `sidePanelWidth`, etc.
   - Creates equivalent `PanelLayout` from old settings
   - Saves new `PanelLayout` to config
   - Removes old keys

2. **Fallback for new users:**
   - If no config exists, uses `PanelLayout.horizontalToolbar()` as default

### Rollout Strategy

1. **Phase 1-2:** Backend changes (models, serialization, rendering)
   - Low risk: renders existing layouts from new data structure
   - Users see no visual change

2. **Phase 3-4:** Drag-and-drop core features
   - Medium risk: new interaction patterns
   - Release as opt-in beta feature flag initially

3. **Phase 5:** Polish and quality-of-life improvements
   - Low risk: animations, keyboard/touch support
   - General availability

---

## Open Questions & Future Enhancements

### Resolved in This Plan

1. **Locked panels?** - Not in MVP. Conversation panel is protected (cannot be removed entirely) but can be moved.
2. **Panel duplication?** - Not in MVP. Each panel type appears once.
3. **Reset layout?** - Yes, via layout preset menu (Phase 5).

### Deferred to Future (Backlog)

4. **Tab merging** - Dropping panels on headers to create tabbed groups. Deferred from MVP to reduce complexity.
5. **Collapse to icon?** - Nice-to-have. Not in MVP.
6. **Floating panels?** - Advanced feature. Would require window management API.
7. **Custom panels?** - Extension point exists (`PanelType` enum can be extended), but not in MVP.

---

## Success Metrics

### User Experience
- Users can rearrange panels in < 5 seconds
- 90%+ of users discover drag-and-drop without documentation
- Layouts persist reliably across restarts

### Technical
- Zero data loss during migration from old layout system
- All tests pass (unit, widget, integration)
- No performance regression (app maintains 60fps)
- Drag operations feel responsive (< 16ms frame time)

---

## Files Summary

### New Files (16 total)
- `lib/models/panel_layout.dart` - Data model
- `lib/widgets/panel_layout_root.dart` - Root layout widget
- `lib/widgets/panel_column_widget.dart` - Column container
- `lib/widgets/panel_stack_widget.dart` - Stack container
- `lib/widgets/panel_header.dart` - Draggable header
- `lib/widgets/panel_drag_overlay.dart` - Ghost + drop targets
- `lib/providers/panel_drag_controller.dart` - Drag state
- `lib/widgets/layout_preset_menu.dart` - Layout presets UI
- `test/models/panel_layout_test.dart`
- `test/providers/panel_drag_controller_test.dart`
- `test/widget/panel_header_test.dart`
- `test/widget/panel_stack_widget_test.dart`
- `test/widget/panel_drag_overlay_test.dart`
- `test/integration/panel_drag_drop_test.dart`
- `test/integration/panel_layout_migration_test.dart`
- `test/integration/panel_layout_persistence_test.dart`

### Modified Files (3 total)
- `lib/services/runtime_config.dart` - Add panelLayout config + migration
- `lib/screens/home_screen.dart` - Replace fixed layouts with PanelLayoutRoot
- `lib/main.dart` - Add PanelDragController to Provider tree

---

## Timeline Estimate

**Total:** 5 phases, estimated completion in priority order.

### Priority 1 (Core Functionality)
- **Phase 1:** Data Model & Serialization - Foundation
- **Phase 2:** Render Layout from Model - Display
- **Phase 3:** Basic Drag & Drop - Reordering

### Priority 2 (Advanced Features)
- **Phase 4:** Column Operations - Layout flexibility

### Priority 3 (Polish)
- **Phase 5:** Animations, keyboard, touch, presets

Each phase includes implementation, testing, and documentation.
