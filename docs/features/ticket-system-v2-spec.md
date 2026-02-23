# Ticket System V2 — Feature Specification

## Overview

Revamp the ticket system to follow a GitHub Issues-style model. The current system uses a multi-status workflow (draft, ready, active, blocked, needsInput, inReview, completed, cancelled, split) with fixed enum metadata (kind, priority, effort). The new system simplifies to **Open/Closed** status, replaces fixed enums with **free-form customisable tags**, introduces a **comment thread with activity timeline**, and adds **image attachments** and **author attribution**.

### Design Goals

- Simple, familiar UX modelled on GitHub Issues
- Free-form tags replace rigid kind/priority/effort enums
- Chronological activity timeline shows all ticket history
- Comments support rich text and images from both users and agents
- Sidebar displays linked chats, worktrees, and dependencies
- Full-text search across titles, bodies, comments, and tags

### Mockup References

All mockups are in `docs/mocks/` and use the app's existing design tokens:

| Mockup | File | Shows |
|--------|------|-------|
| Detail view | `ticket-detail-v2-mock.html` | GitHub-style issue view with body, timeline, comments, sidebar |
| List panel | `ticket-list-v2-mock.html` | Open/Closed tabs, tag chips, search, filter chips (two variants) |
| Full layout | `ticket-screen-v2-mock.html` | Complete app frame: nav rail + list panel + detail view |

---

## 1. Data Model

### 1.1 TicketData (revised)

The core model changes substantially. Fields removed: `status` (enum with 9 values), `kind`, `priority`, `effort`, `category`, `costStats`. Fields added: `isOpen`, `body`, `author`, `activityLog`, `closedAt`. The `description` field is renamed to `body`. The `comments` model is enriched with images and author information.

```
TicketData
  id: int                          // unique numeric ID
  title: String                    // short title
  body: String                     // markdown body (was 'description')
  author: String                   // who created this ticket ("zaf", "agent <chatname>")
  isOpen: bool                     // true = open, false = closed  (replaces TicketStatus enum)
  tags: Set<String>                // free-form tags (replaces kind, priority, effort, category)
  dependsOn: List<int>             // ticket IDs this depends on
  linkedWorktrees: List<LinkedWorktree>
  linkedChats: List<LinkedChat>
  comments: List<TicketComment>    // comment thread (enriched, see below)
  activityLog: List<ActivityEvent> // chronological activity timeline (NEW)
  bodyImages: List<TicketImage>    // images attached to the body (NEW)
  sourceConversationId: String?    // conversation that created this ticket
  createdAt: DateTime
  updatedAt: DateTime
  closedAt: DateTime?              // when the ticket was closed (NEW)
```

### 1.2 TicketComment (revised)

Comments are enriched with proper author attribution and image support.

```
TicketComment
  id: String                       // unique ID (uuid)
  text: String                     // markdown content
  author: String                   // "zaf", "agent <chatname>", etc.
  authorType: AuthorType           // user | agent
  images: List<TicketImage>        // images attached to this comment
  createdAt: DateTime
  updatedAt: DateTime?             // if edited
```

### 1.3 AuthorType (new)

```
enum AuthorType { user, agent }
```

### 1.4 TicketImage (new)

Images are stored as file paths relative to a ticket-specific image directory. The storage layout is `<project-dir>/ticket-images/<ticket-id>/`.

```
TicketImage
  id: String                       // unique ID (uuid)
  fileName: String                 // original file name
  path: String                     // absolute path on disk
  mimeType: String                 // e.g. "image/png"
  createdAt: DateTime
```

### 1.5 ActivityEvent (new)

Every mutation to a ticket generates an activity event displayed on the timeline between the body and comments. Events are stored chronologically.

```
ActivityEvent
  id: String                       // unique ID (uuid)
  type: ActivityEventType
  actor: String                    // who performed the action
  actorType: AuthorType            // user | agent
  timestamp: DateTime
  data: Map<String, dynamic>       // type-specific payload
```

#### ActivityEventType enum

```
enum ActivityEventType {
  tagAdded,          // data: { "tag": "feature" }
  tagRemoved,        // data: { "tag": "todo" }
  worktreeLinked,    // data: { "branch": "feat/xyz", "worktreeRoot": "/path" }
  worktreeUnlinked,  // data: { "branch": "feat/xyz" }
  chatLinked,        // data: { "chatId": "abc", "chatName": "auth-refactor" }
  chatUnlinked,      // data: { "chatId": "abc", "chatName": "auth-refactor" }
  dependencyAdded,   // data: { "ticketId": 5 }
  dependencyRemoved, // data: { "ticketId": 5 }
  closed,            // data: {} (ticket closed)
  reopened,          // data: {} (ticket reopened)
  titleEdited,       // data: { "oldTitle": "...", "newTitle": "..." }
  bodyEdited,        // data: {}
}
```

### 1.6 Tag System

Tags are free-form strings. There is no fixed set. A project-level tag registry stores known tags for autocomplete suggestions, but users and agents can create any tag at any time.

```
TagDefinition
  name: String                     // the tag text, e.g. "bug", "high-priority"
  color: String?                   // optional hex color override, e.g. "#ef5350"
```

The tag registry is stored per-project alongside tickets (in `tickets.json` or a separate `tags.json`). Tags that appear on at least one ticket are always included. Users can also pre-define tags via a tag management UI (future, not in this scope).

#### Default tag colours

When no explicit colour is set, tags are coloured using a deterministic hash of the tag name mapped to one of the app's existing palette colours. Some well-known tag names have built-in colour defaults:

| Tag pattern | Default colour |
|------------|---------------|
| `bug`, `bugfix` | red (#ef5350) |
| `feature` | purple (#ba68c8) |
| `todo` | orange (#ffa726) |
| `inprogress`, `in-progress` | blue (#42a5f5) |
| `done`, `completed` | green (#4caf50) |
| `high-priority`, `critical` | red (#ef5350) |
| `docs`, `documentation` | grey (#9e9e9e) |
| `test`, `testing` | teal (#4db6ac) |

### 1.7 Fields Removed

The following model types are **deleted entirely**:

- `TicketStatus` enum (replaced by `isOpen: bool`)
- `TicketKind` enum (replaced by tags)
- `TicketPriority` enum (replaced by tags)
- `TicketEffort` enum (replaced by tags)
- `TicketGroupBy` enum (replaced by tag-based grouping + Open/Closed tabs)
- `TicketCostStats` class (cost tracking moves to a separate concern, out of ticket model)
- `TicketProposal` class (revised for new model, see section 9)

### 1.8 Fields Preserved

- `LinkedWorktree` — unchanged
- `LinkedChat` — unchanged
- `TicketViewMode` — kept (list | graph)

---

## 2. Ticket List Panel

**Mockup:** `ticket-list-v2-mock.html`

### 2.1 Layout

The list panel is the left sidebar (~340px wide). Top to bottom:

1. **Panel header** — icon + "Tickets" title + drag handle
2. **Search bar** — text field with magnifying glass icon
3. **Status tabs** — "Open (N)" and "Closed (N)" tabs, GitHub-style
4. **Active filter chips** (conditional) — shown only when tag/text filters are active
5. **Ticket list** — scrollable list of ticket items

### 2.2 Status Tabs

Two tabs replace the old multi-status filter dropdown:

- **Open** tab (default): shows all tickets where `isOpen == true`. Icon: `radio_button_checked` (green).
- **Closed** tab: shows all tickets where `isOpen == false`. Icon: `check_circle` (purple).

Each tab shows the count of tickets in that state. The active tab has a bottom border highlight using the primary colour. A sort control ("Newest", "Oldest", "Recently updated") sits at the right end of the tab bar.

### 2.3 Filter Chips

When the user has applied tag filters or text search, a row of small "filter chips" appears between the tabs and the list. Each chip shows the tag name with an "x" to remove. A "Clear all" text link removes all filters.

### 2.4 Ticket List Items

Each item displays (left to right):

1. **Status icon** — green `radio_button_checked` for open, purple `check_circle` for closed
2. **Content area** (stacked):
   - **Title row**: ticket title (13px, weight 500) + inline tag chips (9px, right-aligned)
   - **Subtitle row**: `#id` (mono, 10px) + "opened/closed [date] by [author]" + comment count icon + dependency indicator icon
3. Closed tickets use dimmed title text (`onSurfaceVariant` colour)

### 2.5 Search

The search box filters tickets in real-time as the user types. Search matches against:

- Ticket title
- Ticket body
- All comment text
- Tag names
- Ticket `#id`

Search is case-insensitive and is AND-combined with the Open/Closed tab and any active tag filters.

### 2.6 Sorting

The sort dropdown offers:

- **Newest** (default) — by `createdAt` descending
- **Oldest** — by `createdAt` ascending
- **Recently updated** — by `updatedAt` descending

### 2.7 Adding a New Ticket

The `+` button in the search toolbar opens the create form in the detail panel (right side). See section 5.

---

## 3. Ticket Detail Panel

**Mockup:** `ticket-detail-v2-mock.html`, `ticket-screen-v2-mock.html`

The detail panel occupies the right side of the screen. It consists of a scrollable content area divided into two columns: a **timeline column** (left, flex) and a **sidebar column** (right, fixed ~200px).

### 3.1 Issue Header

At the top of the detail panel:

1. **Status badge** — pill-shaped badge reading "Open" (green) or "Closed" (purple) with appropriate icon
2. **Title** — large text (20-22px, weight 600) + ticket number in subdued colour (e.g. "Implement token refresh #4")
3. **Action buttons** (right-aligned) — "Edit" outlined button, "..." more menu

Below the title: a single-line meta string: `<author> opened on <date>` in subdued text, with a bottom border separator.

### 3.2 Timeline Column

The timeline is a vertical sequence of **comment blocks** and **activity events** connected by a visual timeline line.

#### 3.2.1 Body Block (First Comment)

The ticket body is rendered as the first "comment block" in the timeline:

- **Header bar**: avatar circle (initial letter) + author name + "Owner" label (if ticket creator) + timestamp
- **Body**: rendered markdown with support for:
  - Paragraphs, lists, code blocks, inline code
  - Embedded images (rendered inline, clickable to expand)

The avatar uses `user` styling (purple tint) for human authors and `agent` styling (blue tint) for agent authors.

#### 3.2.2 Activity Events

Between comment blocks, activity events are shown as compact timeline entries. Each event has:

- A **timeline dot** (22-26px circle) on the left connecting to the vertical timeline line
- The dot contains a small icon indicating the event type:
  - `sell` (tag icon) for tag add/remove
  - `account_tree` for worktree link/unlink
  - `chat_bubble_outline` for chat link/unlink
  - `check_circle` for close
  - `radio_button_checked` for reopen
  - `link` for dependency add/remove
  - `edit` for title/body edits
- **Actor name** with optional agent badge
- **Event text** describing what happened, with inline tag chips where applicable
- **Timestamp** right-aligned

Example event displays:

```
[tag icon] zaf added tag (todo)                                22 Jun
[tag icon] agent auth-refactor [agent] removed tag (todo) added (inprogress)  22 Jun
[tree icon] agent auth-refactor [agent] linked worktree feat/token-refresh    22 Jun
[check icon] zaf closed this                                   23 Jun, 16:00
```

#### 3.2.3 Comment Blocks

After the body, subsequent comments appear as additional comment blocks identical in structure to the body block but with different authors. Each has:

- **Header**: avatar + author name + agent badge (if agent) + timestamp
- **Body**: markdown content + optional images
- Comments are displayed in chronological order

#### 3.2.4 New Comment Input

At the bottom of the timeline, a "new comment" box:

- **Header**: avatar + "Add a comment" placeholder text
- **Text area**: expandable text input for markdown
- **Footer** (right-aligned buttons):
  - "Attach" button with image icon — opens file picker for images
  - "Close ticket" / "Reopen ticket" toggle button (secondary style)
  - "Comment" button (primary filled style) — submits the comment

The close/reopen button text changes based on ticket state. When clicked alongside a comment, it closes/reopens the ticket AND adds the comment atomically. When clicked alone (no comment text), it just closes/reopens.

### 3.3 Sidebar

The right sidebar shows structured metadata. Each section has an uppercase label with a bottom border.

#### 3.3.1 Tags Section

Displays all tags as coloured pill chips. Clicking the section label or a "+" button opens a tag picker to add/remove tags. Tag chips have a small "x" button on hover for removal.

#### 3.3.2 Linked Chats Section

Each linked chat shows:
- `chat_bubble_outline` icon
- Chat name (primary colour, clickable to navigate)
- Status text (e.g. "done", "active")

#### 3.3.3 Linked Worktrees Section

Each linked worktree shows:
- `account_tree` icon
- Branch name (primary colour, clickable)
- Spinner if active, checkmark if merged

#### 3.3.4 Depends On Section

Lists tickets this ticket depends on:
- Status icon (green check if closed, grey circle if open)
- `#id` in monospace
- Truncated title

Clicking navigates to that ticket.

#### 3.3.5 Blocks Section

Lists tickets that depend on this ticket (reverse dependency lookup), same format as "Depends On".

---

## 4. Ticket Create / Edit Form

### 4.1 Create Form

Triggered by the `+` button. Displayed in the detail panel area. Fields:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| Title | Text input | Yes | Single line |
| Body | Multiline text | No | Markdown supported |
| Tags | Tag input | No | Autocomplete from known tags, free text allowed |
| Dependencies | Ticket picker | No | Searchable list of existing tickets |
| Images | File picker | No | Attach to body |

Buttons: "Create" (primary) and "Cancel" (secondary).

The new ticket is created with `isOpen: true` and `author` set to "user" (the local user identity). An `ActivityEvent` is not generated for creation — the body block serves as the creation record.

### 4.2 Edit Form

Triggered by the "Edit" button on the detail header. Replaces the detail view with an edit form pre-populated with current values. Editable fields:

- **Title** — text input
- **Body** — multiline markdown editor
- **Tags** — tag input with add/remove
- **Dependencies** — ticket picker with add/remove
- **Images** — add/remove body images

Saving generates appropriate activity events:
- `titleEdited` if title changed
- `bodyEdited` if body changed
- `tagAdded` / `tagRemoved` for each tag change
- `dependencyAdded` / `dependencyRemoved` for each dependency change

---

## 5. User Stories

### 5.1 Ticket Creation

**US-1: As a user, I want to create a new ticket so I can track a unit of work.**

1. User clicks the `+` button in the ticket list toolbar
2. The detail panel switches to the create form
3. User enters a title (required), body (optional markdown), and optionally adds tags and dependencies
4. User clicks "Create"
5. A new ticket is created with `isOpen: true`, `author: "user"`, and current timestamp
6. The ticket appears at the top of the Open list
7. The detail panel switches to show the new ticket's detail view

**US-2: As a user, I want to attach an image to the ticket body when creating it.**

1. During ticket creation, user clicks the "Attach" button in the body area
2. A file picker opens, filtered to image types (png, jpg, gif, webp)
3. User selects one or more images
4. Images are copied to `<project-dir>/ticket-images/<ticket-id>/` and displayed as thumbnails below the body text area
5. Images can be removed by clicking an "x" overlay on the thumbnail
6. On ticket creation, `bodyImages` is populated with the selected images

### 5.2 Viewing Tickets

**US-3: As a user, I want to browse open tickets so I can see what work is pending.**

1. User opens the Tickets screen from the nav rail
2. The Open tab is selected by default, showing all open tickets sorted by newest first
3. Each ticket shows its title, tags, author, date, and comment count
4. User clicks a ticket to view its detail

**US-4: As a user, I want to view closed tickets so I can see completed work.**

1. User clicks the "Closed" tab in the status tabs
2. The list shows all closed tickets with the purple check icon
3. Closed ticket titles use dimmed text colour

**US-5: As a user, I want to view a ticket's full history in chronological order.**

1. User selects a ticket from the list
2. The detail panel shows:
   - Status badge (Open/Closed) + title
   - Body block (first "comment") with markdown rendered content and any images
   - Activity timeline events in chronological order
   - Comment blocks interspersed with activity events
   - Sidebar with tags, linked chats/worktrees, dependencies
3. User can scroll through the full history

### 5.3 Comments

**US-6: As a user, I want to add a comment to a ticket so I can discuss or provide updates.**

1. User scrolls to the bottom of the ticket detail timeline
2. User types in the "Add a comment" text area (supports markdown)
3. User clicks "Comment"
4. The comment appears as a new comment block at the bottom of the timeline
5. The comment has the user's avatar, name, and current timestamp
6. The ticket's `updatedAt` is set to the current time
7. The comment count in the list panel updates

**US-7: As a user, I want to attach an image to a comment.**

1. While composing a comment, user clicks the "Attach" button
2. A file picker opens for image selection
3. Selected images appear as thumbnails below the comment text area
4. On submission, images are stored in `<project-dir>/ticket-images/<ticket-id>/` and referenced in the comment's `images` list

**US-8: As an agent, I want to add a comment to a ticket so I can report progress.**

1. Agent uses the `update_ticket` MCP tool with a `comment` field
2. A comment is created with `authorType: agent` and `author: "agent <chatname>"`
3. The comment block renders with the blue agent avatar and "agent" badge
4. Activity from agents is visually distinct from user activity

### 5.4 Tags

**US-9: As a user, I want to add tags to a ticket so I can categorize it.**

1. In the sidebar "Tags" section, user clicks the "+" button (or the section label)
2. A tag picker popover appears with:
   - Text input for typing a new tag
   - List of known project tags (autocomplete filtered as user types)
   - Each suggestion shows the tag colour
3. User types or selects a tag and presses Enter
4. The tag is added to the ticket's `tags` set
5. An `ActivityEvent` of type `tagAdded` is recorded with the user as actor
6. The tag chip appears in the sidebar and on the list item

**US-10: As a user, I want to remove a tag from a ticket.**

1. User hovers over a tag chip in the sidebar
2. An "x" button appears on the chip
3. User clicks "x"
4. The tag is removed from the ticket
5. An `ActivityEvent` of type `tagRemoved` is recorded
6. The tag chip disappears from the sidebar and list item

**US-11: As an agent, I want to add/remove tags on a ticket to signal work status.**

1. Agent uses the `set_tags` MCP tool to modify a ticket's tags
2. For each added tag, a `tagAdded` activity event is recorded with the agent as actor
3. For each removed tag, a `tagRemoved` activity event is recorded
4. The timeline displays these as: `agent <chatname> [agent] added tag (inprogress)`

**US-12: As a user, I want to filter the ticket list by tag so I can focus on a category.**

1. User clicks a tag chip in the list (or uses the search bar with tag syntax)
2. A filter chip appears in the filter chips row
3. The ticket list is filtered to show only tickets that have that tag
4. Multiple tag filters are AND-combined
5. User can remove a filter chip by clicking its "x"
6. "Clear all" removes all filter chips

### 5.5 Status (Open/Close)

**US-13: As a user, I want to close a ticket to mark it as done.**

1. In the detail panel's new comment area, user clicks "Close ticket"
2. If there is comment text, both the comment and the close happen together
3. The ticket's `isOpen` is set to `false`, `closedAt` is set to now
4. An `ActivityEvent` of type `closed` is recorded with the user as actor
5. The status badge changes from "Open" (green) to "Closed" (purple)
6. The ticket moves from the Open list to the Closed list
7. The Open/Closed tab counts update

**US-14: As a user, I want to reopen a closed ticket.**

1. User views a closed ticket (from the Closed tab)
2. The new comment area shows "Reopen ticket" instead of "Close ticket"
3. User clicks "Reopen ticket" (optionally with a comment)
4. The ticket's `isOpen` is set to `true`, `closedAt` is cleared
5. An `ActivityEvent` of type `reopened` is recorded
6. The ticket moves back to the Open list

**US-15: As an agent, I want to close a ticket when work is complete.**

1. Agent uses the `update_ticket` MCP tool with `status: "closed"`
2. The ticket is closed with the agent as actor
3. A `closed` activity event is recorded
4. The timeline shows: `agent <chatname> [agent] closed this`

### 5.6 Editing

**US-16: As a user, I want to edit a ticket's title and body.**

1. User clicks "Edit" in the detail header
2. The detail panel switches to edit mode with pre-populated fields
3. User modifies the title and/or body
4. User clicks "Save"
5. Changes are applied, and appropriate activity events are recorded:
   - `titleEdited` with old and new titles
   - `bodyEdited` (no data payload, just records the event)
6. The detail panel returns to view mode

### 5.7 Dependencies

**US-17: As a user, I want to add a dependency between tickets.**

1. In the edit form, user opens the dependency picker
2. User searches for a ticket by title or ID
3. User selects a ticket from the results
4. The dependency is validated (no self-reference, no cycles)
5. If valid, the dependency is added and a `dependencyAdded` activity event is recorded
6. The dependency appears in the sidebar "Depends On" section

**US-18: As a user, I want to navigate to a dependency ticket.**

1. In the sidebar "Depends On" or "Blocks" section, user clicks a ticket entry
2. The detail panel navigates to show that ticket
3. The list panel updates selection to highlight the navigated ticket

### 5.8 Linked Work

**US-19: As a user, I want to navigate to a linked chat from a ticket.**

1. In the sidebar "Linked Chats" section, user clicks a chat name
2. The app navigates to the main screen with the appropriate worktree and chat selected
3. The chat conversation panel is displayed

**US-20: As an agent, I want to link a worktree to a ticket I'm working on.**

1. Agent uses the `create_worktree` or `link_worktree` MCP tool
2. The worktree is added to the ticket's `linkedWorktrees`
3. A `worktreeLinked` activity event is recorded with branch name
4. The timeline shows: `agent <chatname> [agent] linked worktree feat/xyz`
5. The sidebar "Linked Worktrees" section updates

### 5.9 Search and Filter

**US-21: As a user, I want to search for tickets by text across all fields.**

1. User types in the search bar
2. As they type, the list filters in real-time
3. Matches are found in: title, body, comment text, tag names, `#id`
4. Search is case-insensitive
5. Results are shown within the current Open/Closed tab

**US-22: As a user, I want to combine search with tag filters.**

1. User applies one or more tag filters
2. User types in the search bar
3. Both filters are AND-combined: tickets must match the search text AND have all selected tags
4. The filter chips row shows active tag filters, and the search bar shows the text query

---

## 6. Full Screen Layout

**Mockup:** `ticket-screen-v2-mock.html`

### 6.1 Structure

```
+--------+------------------+-------------------------------------+
| Nav    | Ticket List      | Ticket Detail                       |
| Rail   | Panel            |                                     |
| (48px) | (~340px)         | (flex)                              |
|        |                  | +-------------------+-----------+   |
|        | [Search bar]     | | Timeline          | Sidebar   |   |
|        | [Open|Closed]    | | (body, events,    | (tags,    |   |
|        | [filter chips]   | | comments, input)  | links,    |   |
|        | [ticket items]   | |                   | deps)     |   |
|        |                  | +-------------------+-----------+   |
+--------+------------------+-------------------------------------+
| Status bar                                                      |
| [dot] CC-Insights          14 tickets - 8 open - 6 closed       |
+-----------------------------------------------------------------+
```

### 6.2 Resizable Panels

The list panel and detail panel use `EditableMultiSplitView` (existing pattern). The split between list and detail is resizable. The sidebar within the detail panel is a fixed-width column that scrolls independently.

### 6.3 Status Bar

The bottom status bar shows:
- Connection status dot (green)
- App name
- Ticket summary: `N tickets - N open - N closed`

### 6.4 Empty States

- **No ticket selected**: "Select a ticket to view details" centred in the detail panel
- **No tickets exist**: Icon + "No tickets" + "Create your first ticket" link in the list panel
- **No search results**: "No matching tickets" in the list panel
- **No comments**: Only the body block and new comment input are shown (no "no comments" message needed)

---

## 7. Activity Timeline Details

### 7.1 Visual Design

The timeline uses a vertical 2px line (`--timeline-color: rgba(73,69,79,0.4)`) connecting event dots and comment blocks. The line runs along the left edge of the timeline column, offset ~13px from the left.

Event dots are 22-26px circles with a 2px border matching the timeline colour, filled with the surface colour, containing a 10-12px Material Icon. The dot colour varies by event type (tag = primary, link = blue, status = green).

Comment blocks interrupt the timeline line. They have a 1px border, rounded 8px corners, and two sections: a header bar (surface-container-high background) and a body area (surface-container-low background).

### 7.2 Event Coalescing

When multiple tag operations happen at the same time by the same actor (e.g. "removed todo, added inprogress"), they are displayed as a single timeline event with both operations inline:

```
[tag icon] agent auth-refactor [agent] removed (todo) added (inprogress)    22 Jun
```

Coalescing window: events from the same actor within 5 seconds are combined into a single display entry. The underlying `activityLog` stores them as separate events; coalescing is a display-only concern.

### 7.3 Timestamp Formatting

- Same day: "15:30"
- Same year: "22 Jun" or "22 Jun, 15:30" (if showing time for precision)
- Different year: "22 Jun 2025"

---

## 8. MCP Tool Changes

The internal MCP tools in `InternalToolsService` need to be updated to match the new model.

### 8.1 `create_ticket` (all chats)

Input schema changes:

```json
{
  "tickets": [{
    "title": "string (required)",
    "body": "string (required)",
    "tags": ["string"],
    "dependsOnIndices": [0]
  }]
}
```

Removed fields: `kind`, `priority`, `effort`, `category`.
Added fields: `body` (replaces `description`).
Changed fields: `tags` is now the primary categorisation mechanism.

### 8.2 `list_tickets` (orchestrator)

Response changes to reflect new model:

```json
[{
  "id": 1,
  "display_id": "#1",
  "title": "...",
  "is_open": true,
  "tags": ["feature", "auth"],
  "depends_on": [2]
}]
```

Filter parameter changes:
- Remove: `status[]` filter with enum values
- Add: `is_open: bool?` filter
- Add: `tags: string[]?` filter (match any)
- Keep: `depends_on`, `dependency_of`, `ids[]`

### 8.3 `get_ticket` (orchestrator)

Returns the full ticket in the new format, including comments and activity log.

### 8.4 `update_ticket` (orchestrator)

Input changes:

```json
{
  "ticket_id": 1,
  "is_open": false,
  "comment": "Work is done",
  "add_tags": ["done"],
  "remove_tags": ["inprogress"]
}
```

Removed: `status` (enum string).
Added: `is_open` (bool), `add_tags`, `remove_tags`.

Each change generates appropriate activity events.

### 8.5 `set_tags` (orchestrator)

Unchanged in interface, but now the primary way to manage ticket metadata. Generates `tagAdded`/`tagRemoved` activity events.

---

## 9. Ticket Proposals (Bulk Create)

The existing `TicketProposal` class is updated to match the new model:

```
TicketProposal
  title: String
  body: String                     // was 'description'
  tags: Set<String>                // replaces kind, priority, effort, category
  dependsOnIndices: List<int>
```

The bulk review panel (`TicketBulkReviewPanel`) is updated to show the new fields. The approval flow remains the same: agents propose tickets, the user reviews and approves/rejects.

---

## 10. Persistence

### 10.1 Storage Format

The existing `tickets.json` file is updated with the new schema. A `schemaVersion` field is added for future migration support.

```json
{
  "schemaVersion": 2,
  "nextId": 15,
  "tagRegistry": [
    { "name": "feature", "color": null },
    { "name": "bug", "color": "#ef5350" },
    { "name": "high-priority", "color": "#ef5350" }
  ],
  "tickets": [
    {
      "id": 1,
      "title": "...",
      "body": "...",
      "author": "zaf",
      "isOpen": true,
      "tags": ["feature", "auth"],
      "dependsOn": [],
      "linkedWorktrees": [],
      "linkedChats": [],
      "comments": [...],
      "activityLog": [...],
      "bodyImages": [],
      "createdAt": "2025-06-22T10:00:00Z",
      "updatedAt": "2025-06-23T15:30:00Z",
      "closedAt": null
    }
  ]
}
```

### 10.2 Image Storage

Images are stored on disk at `<project-data-dir>/ticket-images/<ticket-id>/`. Each image is copied from its source location when attached. The `TicketImage.path` field stores the absolute path. Images are cleaned up when:
- A comment containing images is deleted (future)
- A ticket is deleted — all images in that ticket's directory are removed

### 10.3 Migration

When loading `tickets.json` and `schemaVersion` is missing or `< 2`, a migration runs:

1. Map old `status` to `isOpen`:
   - `completed`, `cancelled`, `split` → `isOpen: false`
   - All others → `isOpen: true`
2. Map old enums to tags:
   - `kind: "feature"` → add tag `"feature"`
   - `kind: "bugfix"` → add tag `"bug"`
   - `kind: "research"` → add tag `"research"`
   - `kind: "test"` → add tag `"test"`
   - `kind: "docs"` → add tag `"docs"`
   - `kind: "chore"` → add tag `"chore"`
   - `kind: "question"` → add tag `"question"`
   - `priority: "high"` → add tag `"high-priority"`
   - `priority: "critical"` → add tag `"critical"`
   - `priority: "low"` → add tag `"low-priority"`
   - (medium priority adds no tag — it's the default assumption)
   - `effort: "small"` → add tag `"small"`
   - `effort: "large"` → add tag `"large"`
   - (medium effort adds no tag)
   - `category: "X"` → add tag `"X"` (lowercase)
3. Rename `description` to `body`
4. Set `author` to `"user"` for all existing tickets (since old tickets have no author)
5. Convert existing `comments` to new format with `id`, `authorType`, `images: []`
6. Set `activityLog` to `[]` for all existing tickets (no retroactive events)
7. Set `schemaVersion: 2` and save

---

## 11. State Management Changes

### 11.1 TicketRepository

Method changes:

| Old | New |
|-----|-----|
| `createTicket(title, kind, ...)` | `createTicket(title, body, tags, author, ...)` |
| `setStatus(id, TicketStatus)` | `closeTicket(id, actor)` / `reopenTicket(id, actor)` |
| `markCompleted(id)` | `closeTicket(id, actor)` |
| `markCancelled(id)` | `closeTicket(id, actor)` |
| `accumulateCostStats(...)` | Removed |
| `splitTicket(id, subtasks)` | Removed (use create + dependencies instead) |

New methods:

- `addComment(id, text, author, authorType, images)` — adds a comment, generates no activity event (comments are their own record)
- `addTag(id, tag, actor, actorType)` — adds a tag and records `tagAdded` event
- `removeTag(id, tag, actor, actorType)` — removes a tag and records `tagRemoved` event
- `closeTicket(id, actor, actorType)` — sets `isOpen: false`, records `closed` event
- `reopenTicket(id, actor, actorType)` — sets `isOpen: true`, records `reopened` event
- `linkWorktreeWithEvent(id, worktreeRoot, branch, actor, actorType)` — links worktree and records event
- `linkChatWithEvent(id, chatId, chatName, worktreeRoot, actor, actorType)` — links chat and records event

### 11.2 TicketViewState

Changes:

| Old | New |
|-----|-----|
| `statusFilter: TicketStatus?` | `isOpenFilter: bool` (default `true`) |
| `kindFilter: TicketKind?` | Removed |
| `priorityFilter: TicketPriority?` | Removed |
| `categoryFilter: String?` | Removed |
| `groupBy: TicketGroupBy` | Removed (replaced by Open/Closed tabs) |
| `groupedTickets` | Removed |
| `categoryProgress` | Removed |

New fields:

- `tagFilters: Set<String>` — active tag filters (AND-combined)
- `sortOrder: TicketSortOrder` — newest, oldest, recentlyUpdated
- `openCount: int` — computed count of open tickets
- `closedCount: int` — computed count of closed tickets

New methods:

- `setIsOpenFilter(bool)` — switch between Open/Closed tabs
- `addTagFilter(String)` — add a tag to the active filter set
- `removeTagFilter(String)` — remove a tag from the filter set
- `clearTagFilters()` — remove all tag filters
- `setSortOrder(TicketSortOrder)` — change sort order

### 11.3 TicketDetailMode

Remains: `detail`, `create`, `edit`.

---

## 12. Widget Changes

### 12.1 Files to Delete

- `widgets/ticket_visuals.dart` — `TicketStatusIcon`, `MetadataPill`, `EffortBadge`, `KindBadge` (all tied to removed enums)

### 12.2 Files to Heavily Rewrite

- `panels/ticket_detail_panel.dart` — complete rewrite for timeline/sidebar layout
- `panels/ticket_list_panel.dart` — rewrite for Open/Closed tabs, new item layout
- `panels/ticket_create_form.dart` — simplified form fields
- `panels/ticket_bulk_review_panel.dart` — updated for new proposal format
- `models/ticket.dart` — new model definitions
- `state/ticket_board_state.dart` — new methods per section 11.1
- `state/ticket_view_state.dart` — new filtering per section 11.2
- `services/internal_tools_service.dart` — MCP tool schema updates
- `services/ticket_storage_service.dart` — migration logic
- `screens/ticket_screen.dart` — minor layout adjustments

### 12.3 New Widgets

- `widgets/ticket_tag_chip.dart` — coloured tag chip with optional "x" button
- `widgets/ticket_comment_block.dart` — comment block (header + body + images)
- `widgets/ticket_activity_event.dart` — timeline event widget
- `widgets/ticket_timeline.dart` — orchestrates the full timeline (body + events + comments)
- `widgets/ticket_sidebar.dart` — right sidebar with tags, links, dependencies
- `widgets/ticket_status_badge.dart` — Open/Closed pill badge
- `widgets/ticket_image_attachment.dart` — image thumbnail with click-to-expand
- `widgets/tag_picker.dart` — popover for adding tags with autocomplete

### 12.4 Files to Preserve

- `panels/ticket_graph_view.dart` — dependency graph (needs minor adaptation for isOpen/tag display)
- `widgets/ticket_graph_layout.dart` — graph layout engine (unchanged)
- `services/ticket_dispatch_service.dart` — worktree dispatch (unchanged interface)
- `services/ticket_dispatch_factory.dart` — factory (unchanged)
- `services/ticket_event_bridge.dart` — event bridge (adapt for new model)

---

## 13. Test Impact

All existing ticket tests need updating. Key test files:

| Test file | Changes |
|-----------|---------|
| `test/models/ticket_test.dart` | New model structure, serialization, migration |
| `test/state/ticket_board_state_test.dart` | New methods (closeTicket, addTag, etc.) |
| `test/state/ticket_board_bulk_test.dart` | Updated proposals |
| `test/widget/ticket_screen_test.dart` | New layout, Open/Closed tabs |
| `test/widget/ticket_detail_panel_test.dart` | Timeline, sidebar, comments |
| `test/widget/ticket_list_panel_test.dart` | New list items, status tabs |
| `test/widget/ticket_create_form_test.dart` | Simplified form |
| `test/widget/ticket_bulk_review_panel_test.dart` | New proposal format |
| `test/widget/ticket_visuals_test.dart` | Delete (enums removed) |
| `test/widget/ticket_split_dialog_test.dart` | Delete (split removed) |

New tests needed:

- `test/widget/ticket_timeline_test.dart` — timeline rendering, event coalescing
- `test/widget/ticket_comment_block_test.dart` — comment rendering, images
- `test/widget/ticket_sidebar_test.dart` — tags, links, dependencies
- `test/widget/tag_picker_test.dart` — tag autocomplete and creation
- `test/models/activity_event_test.dart` — event types, serialization
- `test/services/ticket_migration_test.dart` — v1 to v2 migration
- `test/services/ticket_image_storage_test.dart` — image attach/delete

---

## 14. Implementation Order

Suggested phased approach:

### Phase 1: Data Model
1. Define new model types (`TicketData`, `TicketComment`, `ActivityEvent`, `TicketImage`, `AuthorType`, `ActivityEventType`)
2. Write migration logic (v1 → v2)
3. Update `TicketRepository` with new methods
4. Update `TicketViewState` with new filtering
5. Write model and state tests

### Phase 2: List Panel
1. Build status tabs (Open/Closed)
2. Build new list item layout with tags
3. Implement tag filtering with filter chips
4. Implement sort control
5. Update search to include comments and tags
6. Write list panel tests

### Phase 3: Detail Panel — Timeline
1. Build comment block widget (header, body, markdown, images)
2. Build activity event widget
3. Build timeline widget (composition of body + events + comments)
4. Build new comment input with attach/close/reopen
5. Write timeline tests

### Phase 4: Detail Panel — Sidebar
1. Build tag section with add/remove
2. Build linked chats section
3. Build linked worktrees section
4. Build dependency sections (depends on / blocks)
5. Build tag picker popover
6. Write sidebar tests

### Phase 5: Create/Edit Form
1. Update create form for new fields
2. Update edit form for new fields
3. Image attachment UI
4. Tag input with autocomplete
5. Write form tests

### Phase 6: MCP Tools + Integration
1. Update `create_ticket` tool schema
2. Update `list_tickets`, `get_ticket`, `update_ticket` tools
3. Update `set_tags` to generate activity events
4. Update `TicketProposal` and bulk review panel
5. Update ticket dispatch service
6. Integration tests

### Phase 7: Polish
1. Graph view adaptation
2. Keyboard shortcuts
3. Empty states
4. Edge cases and error handling
5. Full test pass
