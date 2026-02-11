# UI Mockups — Project Management / Ticket System

Interactive HTML mockups showing the ticket management feature as it would appear
in CC-Insights V2. They use the same Material 3 dark theme, colors, spacing, and
typography conventions as the existing app.

## Files

| File | Description |
|------|-------------|
| `ticket-list-panel-mock.html` | Ticket list sidebar with search, filter, group-by, category sections, and list/graph toggle |
| `ticket-detail-panel-mock.html` | Ticket detail view with metadata, dependencies, linked work, and action buttons |
| `ticket-create-form-mock.html` | Manual ticket creation form (same pattern as Create Worktree panel) |
| `ticket-graph-view-mock.html` | Dependency DAG visualization with color-coded status nodes and SVG edges |
| `ticket-bulk-review-mock.html` | Bulk review panel for agent-proposed tickets with inline editing |
| `ticket-screen-layout-mock.html` | Full app layout showing nav rail, ticket list, and detail panel composed together |
| `information-panel-mock.html` | *(Pre-existing)* Reference mock for the information/content panel |

## How to view

Open any `.html` file directly in a browser. Each file is fully self-contained with
inline CSS — no build step or dependencies needed (fonts load from Google Fonts CDN).

## Visual conventions used

- **Panel headers**: `surfaceContainerHighest` bg (#36343b), 14px icon, titleSmall text
- **List items**: 8px h-padding, 6px v-padding, `primaryContainer` 0.3 alpha when selected
- **Status colors**: green (done), blue (active), grey (ready), orange (blocked/input), red (cancelled)
- **Cards**: 8px radius, specific container colors at 0.3 alpha with matching border
- **Forms**: 600px max width, centered, 32px padding, matching field/button style
- **Monospace**: JetBrains Mono at 11px for IDs and paths
- **Theme**: Material 3 deep purple dark mode palette (`--primary: #d0bcff`, `--surface: #141218`)
