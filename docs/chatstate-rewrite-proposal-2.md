# ChatState Subsystem Rewrite — Combined Proposal

**Date:** 2026-02-16
**Status:** Proposal
**Scope:** Subsystem rewrite of ChatState and its direct consumers (~35-50 files)

---

## Problem

`ChatState` (`frontend/lib/models/chat.dart`) is a 2150+ line god object with 58+ fields, 100+ methods, and 10+ responsibilities. It conflates:

- **Data container** — holds ChatData, conversations, entries
- **Runtime controller** — manages session, transport, permissions, working state
- **Side-effect executor** — file I/O, timers, desktop notifications
- **Universal notification source** — one `notifyListeners()` for everything

Additionally, `EventHandler` uses shared mutable maps (`_toolCallIndex`, `_agentIdToConversationId`, `_toolUseIdToAgentId`) that persist across sessions, creating cross-chat contamination risk. And persistence writes are fire-and-forget with no retry or failure reporting.

A delegation approach (extracting logic into plain helper classes while keeping ChatState as a facade) would reduce line count but preserve the same design risks: ChatState would still be the coordination center, the single notification bottleneck, and the coupling point for all concerns.

---

## Decision

This is a **subsystem rewrite**, not a light refactor.

Reasons:

- The current API shape encourages direct cross-layer mutation
- There are multiple duplicated cleanup and lifecycle paths
- Event routing state is split across global maps and chat-local fields
- Persistence and runtime flow are interleaved, making failure handling weak
- A single `notifyListeners()` causes unnecessary rebuilds across unrelated UI

If we do not change the subsystem boundaries, we will preserve the same design risks even after extraction work.

---

## Scope

**In scope:**

- `frontend/lib/models/chat.dart` — decompose into sub-states
- `frontend/lib/services/event_handler.dart` and part files — per-session pipeline
- `frontend/lib/services/chat_session_service.dart` — cross-concern orchestration
- Provider wiring in `main.dart` — expose sub-states
- UI call sites that currently access `ChatState` directly
- Tests that assume monolithic behavior
- Migration inventory and execution tracking for the current 40+ `ChatState` references across `frontend/lib` and `frontend/test`

**Out of scope:**

- Project/worktree domain model redesign
- Global app state architecture changes
- Provider strategy changes for unrelated features
- EventTransport abstraction or SDK integration changes

---

## Architecture Goals

1. `ChatState` is no longer the execution engine — it is replaced by a plain `Chat` container
2. Side effects (transport, timers, file writes, notifications) are isolated in owning subsystems
3. Session-scoped runtime state is per-session, not shared through global mutable maps
4. UI-ephemeral state is separated from domain/runtime state
5. Teardown is single-path and idempotent
6. Persistence writes are serialized, retriable, and observable
7. Each sub-state is an independent ChangeNotifier — widgets watch only what they need

---

## Target Architecture

### Overview

```
Chat (plain class — identity + sub-state references)
├── ChatData                (immutable, already exists)
├── ChatSessionState        (ChangeNotifier — lifecycle, transport, working state)
├── ChatPermissionState     (ChangeNotifier — permission queue)
├── ChatSettingsState       (ChangeNotifier — model, security, ACP, reasoning)
├── ChatMetricsState        (ChangeNotifier — usage, timing, context)
├── ChatAgentState          (ChangeNotifier — agents, agent config)
├── ChatConversationState   (ChangeNotifier — entries, selected conversation)
├── ChatPersistence         (plain class — serialized writes, retry, no notification)
└── ChatViewState           (ChangeNotifier — draftText, unread, viewed — UI layer)

SessionEventPipeline (per-session instance, replaces shared EventHandler maps)
├── Tool invocation/completion pairing for that session
├── Streaming state for that session
├── Conversation routing for that session
└── Disposed with session teardown
```

---

### Sub-State Ownership

#### Chat (plain class — not a ChangeNotifier)

The composition root. Holds references to all sub-states. No business logic, no notification, no side effects.

```dart
class Chat {
  final ChatConversationState conversations;
  final ChatSessionState session;
  final ChatPermissionState permissions;
  final ChatSettingsState settings;
  final ChatMetricsState metrics;
  final ChatAgentState agents;
  final ChatViewState viewState;
  final ChatPersistence persistence;

  // Convenience accessors for ChatData
  ChatData get data => conversations.data;
  String get id => data.id;
  String get name => data.name;

  void dispose() {
    session.dispose();
    permissions.dispose();
    settings.dispose();
    metrics.dispose();
    agents.dispose();
    conversations.dispose();
    viewState.dispose();
    persistence.dispose();
  }
}
```

#### ChatSessionState (ChangeNotifier)

**Owns:** `_transport`, `_session`, `_eventSubscription`, `_permissionSubscription`, `_pipeline` (SessionEventPipeline), `_lastSessionId`, `_hasStarted`, `_capabilities`, `_isWorking`, `_isCompacting`, `_workingStopwatch`, `_sessionPhase`

**Key design: explicit session state machine.**

```dart
enum SessionPhase { idle, starting, active, stopping, ended, errored }
```

State transitions are enforced — calling `sendMessage()` in `stopping` phase throws. No more boolean flag soup (`_isWorking && _hasStarted && hasActiveSession`).

**Getters:** `hasActiveSession`, `isWorking`, `isCompacting`, `workingStopwatch`, `lastSessionId`, `hasStarted`, `capabilities`, `sessionPhase`

**Methods:** `start()`, `stop()`, `interrupt()`, `sendMessage()`, `setWorking()`, `setCompacting()`, `pauseStopwatch()`, `resumeStopwatch()`, `clearSession()`

**Hard rule:** There is exactly one teardown path. `stop()`, `interrupt()`, `_handleError()`, and `_handleSessionEnd()` all converge to a single `_teardown()` method that is idempotent.

**Watched by:** `ConversationPanel`, `ContentPanel`, `WelcomeCard`

#### ChatPermissionState (ChangeNotifier)

**Owns:** `_pendingPermissions`

**Getters:** `isWaitingForPermission`, `pendingPermission`, `pendingPermissionCount`, `hasPending`

**Methods:** `add()`, `popFront()`, `removeByToolUseId()`, `clear()`

**Hard rule:** Permission queue is testable without active transport. No transport or session references.

**Watched by:** `ConversationPanel` (permission dialog), `ChatsPanel` (badge)

#### ChatSettingsState (ChangeNotifier)

**Owns:** `_model`, `_reasoningEffort`, `_securityConfig`, `_acpConfigOptions`, `_acpAvailableCommands`, `_acpCurrentModeId`, `_acpAvailableModes`

**Getters:** `model`, `securityConfig`, `permissionMode`, `reasoningEffort`, `acpConfigOptions`, `acpAvailableCommands`, `acpCurrentModeId`, `acpAvailableModes`

**Methods:** `setModel()`, `setPermissionMode()`, `setSecurityConfig()`, `setReasoningEffort()`, `syncModelFromServer()`, `syncReasoningEffortFromServer()`, `syncFromTransport()`, all ACP methods, `clearAcpMetadata()`, `syncPermissionModeFromResponse()`

**Hard rule:** Settings mutations that need to send commands to the transport do so via a callback/interface, not by holding a transport reference directly.

**Watched by:** `ConversationHeader` (settings display)

#### ChatMetricsState (ChangeNotifier)

**Owns:** `_cumulativeUsage`, `_inTurnOutputTokens`, `_modelUsage`, `_baseModelUsage`, `_timingStats`, `_contextTracker`, `_permissionRequestTimes`

**Getters:** `cumulativeUsage`, `modelUsage`, `timingStats`, `contextTracker`

**Methods:** `addInTurnOutputTokens()`, `updateCumulativeUsage()`, `updateContextFromUsage()`, `resetContext()`, `restoreFromMeta()`, `recordPermissionRequestTime()`, `recordPermissionResponseTime()`

**Hard rule:** Usage/timing state updates do not touch transport or persistence directly. Read-only value objects exposed to UI.

**Watched by:** `ConversationHeader` (usage display, context indicator)

#### ChatAgentState (ChangeNotifier)

**Owns:** `_activeAgents`, `_agentId`, `_agentRemoved`, `_missingAgentMessage`

**Getters:** `activeAgents`, `agentId`, `agentRemoved`, `missingAgentMessage`, `agentName`

**Methods:** `updateAgent()`, `findAgentByResumeId()`, `markAgentMissing()`, `clearAll()`

**Hard rule:** Agent state is separate from conversation state. Creating a subagent conversation is a cross-concern operation handled by ChatSessionService, not by ChatAgentState directly.

**Watched by:** `ConversationHeader` (agent info), `WelcomeCard` (agent status), `AgentsPanel`

#### ChatConversationState (ChangeNotifier)

**Owns:** `_data` (ChatData reference), `_selectedConversationId`, `_historyLoaded`

**Getters:** `data`, `selectedConversation`, `isInputEnabled`, `primaryConversation`, `subagentConversations`, `hasLoadedHistory`

**Methods:** `selectConversation()`, `resetToMainConversation()`, `addEntry()`, `addOutputEntry()`, `addSubagentConversation()`, `clearEntries()`, `loadEntriesFromPersistence()`, `markHistoryAsLoaded()`, `rename()`

**Hard rule:** Conversation mutation APIs are explicit. No external in-place map/list mutation on entries. All writes go through store methods.

**Watched by:** `ConversationPanel` (entries), `ChatsPanel` (name)

#### ChatPersistence (plain class — not a ChangeNotifier)

**Owns:** `_projectId`, `_projectRoot`, `_metaSaveTimer`, `persistenceService`

**Methods:** `initPersistence()`, `persistEntry()`, `persistStreamingEntry()`, `persistToolResult()`, `scheduleMetaSave()`, `markStarted()`, `saveMeta(Chat)`, `persistSessionId()`, `persistRename()`

**Hard rules:**
- All writes use serialized queues per target path (no concurrent `FileMode.append`)
- Write failures are logged with context and retriable where safe
- `saveMeta()` reads from sub-states via the `Chat` reference — it doesn't own the data

**Not watched by anyone** — persistence is a side effect, not UI state.

#### ChatViewState (ChangeNotifier — UI layer only)

**Owns:** `draftText`, `_unreadCount`, `_isBeingViewed`

**Getters:** `unreadCount`, `hasUnreadMessages`

**Methods:** `markAsViewed()`, `markAsNotViewed()`, `incrementUnread()`

**Hard rule:** This state lives at the selection/UI layer, not in the domain model. It is tied to a chat's visual representation, not its runtime behavior.

**Watched by:** `ChatsPanel` (unread badge), `MessageInput` (draft text)

---

### SessionEventPipeline (per-session instance)

Replaces the shared `EventHandler` mutable tracking maps with a per-session object.

**Owns (per session):**
- `_toolCallIndex` — tool invocation/completion pairing
- `_agentIdToConversationId` — agent-to-conversation routing
- `_toolUseIdToAgentId` — tool-to-agent mapping
- `_activeStreamingEntries` — streaming state
- `_hasAssistantOutputThisTurn` — turn tracking
- `_expectingContextSummary` — context summary tracking

**Lifecycle:**
- Created when a session starts
- Disposed when that session ends (teardown)
- No state persists between sessions
- No shared state between chats

**Role:** Thin router. Receives `InsightsEvent`s, performs session-local bookkeeping (tool pairing, streaming accumulation), and dispatches to the appropriate sub-state:

```dart
class SessionEventPipeline {
  final Chat _chat;

  // Per-session tracking maps (not shared across sessions)
  final Map<String, ToolUseOutputEntry> _toolCallIndex = {};
  final Map<String, String> _agentIdToConversationId = {};
  // ... etc

  void handleEvent(InsightsEvent event) {
    switch (event) {
      case final TextEvent e:
        final entry = TextOutputEntry(...);
        final convId = _resolveConversationId(e.parentCallId);
        _chat.conversations.addOutputEntry(convId, entry);
        _chat.session.setWorking(true);

      case final ToolInvocationEvent e:
        final entry = ToolUseOutputEntry(...);
        _toolCallIndex[e.callId] = entry;
        final convId = _resolveConversationId(e.parentCallId);
        _chat.conversations.addOutputEntry(convId, entry);

      case final ToolCompletionEvent e:
        final entry = _toolCallIndex.remove(e.callId);
        entry?.updateResult(e.output, e.isError);
        _chat.persistence.persistToolResult(...);

      case final UsageUpdateEvent e:
        _chat.metrics.addInTurnOutputTokens(
          (e.stepUsage['output_tokens'] as num?)?.toInt() ?? 0,
        );
        _chat.metrics.updateContextFromUsage(e.stepUsage);

      case final TurnCompleteEvent e:
        _chat.session.setWorking(false);
        _chat.metrics.updateCumulativeUsage(...);

      case final SessionInitEvent e:
        _chat.settings.syncModelFromServer(...); // from e.model

      case final SubagentSpawnEvent e:
        _chat.conversations.addSubagentConversation(e.callId, e.agentType);
        _chat.agents.updateAgent(AgentStatus.working, e.callId);
        _agentIdToConversationId[e.callId] = ...;
    }
  }

  String _resolveConversationId(String? parentCallId) {
    // Per-session lookup — no stale cross-session entries
    return _agentIdToConversationId[parentCallId]
        ?? _chat.data.primaryConversation.id;
  }

  void dispose() {
    _toolCallIndex.clear();
    _agentIdToConversationId.clear();
    // All per-session state cleaned up
  }
}
```

**Hard rule:** No cross-chat map state. When a session ends, all routing state is disposed with it. A new session gets a fresh pipeline. This eliminates stale routing map bugs.

---

## Cross-Concern Coordination

Operations that span multiple sub-states live in `ChatSessionService`, not in a facade or aggregate. Each sub-state calls its own `notifyListeners()` internally — the service just orchestrates the sequence.

### startSession

```dart
class ChatSessionService {
  Future<void> startSession(Chat chat, BackendService backend, ...) async {
    final transport = await backend.createTransport(...);
    final pipeline = SessionEventPipeline(chat);

    chat.session.start(transport, pipeline);    // phase: idle → starting → active
    chat.settings.syncFromTransport(transport); // sync model, reasoning effort
    chat.metrics.reset();                       // clear in-turn tokens
    chat.persistence.markStarted();
    chat.persistence.persistSessionId(transport.sessionId);
  }
}
```

### stopSession

```dart
Future<void> stopSession(Chat chat) async {
  await chat.session.stop();       // phase: active → stopping → ended
                                   // internally disposes pipeline + subscriptions
  chat.permissions.clear();
  chat.agents.clearAll();
  chat.settings.clearAcpMetadata();
}
```

### allowPermission

```dart
void allowPermission(Chat chat, {String? toolName, List<dynamic>? updatedPermissions}) {
  final request = chat.permissions.popFront();
  request.allow();
  chat.metrics.recordPermissionResponseTime(request.toolUseId);
  chat.settings.syncPermissionModeFromResponse(toolName, updatedPermissions);
  if (!chat.permissions.hasPending) {
    chat.session.resumeStopwatch();
  }
}
```

### denyPermission

```dart
void denyPermission(Chat chat, String message, {bool interrupt = false}) {
  final request = chat.permissions.popFront();
  request.deny(message);
  chat.metrics.recordPermissionResponseTime(request.toolUseId);
  if (!chat.permissions.hasPending) {
    chat.session.resumeStopwatch();
  }
  if (interrupt) {
    chat.session.interrupt();
  }
}
```

### addPendingPermission

```dart
void addPendingPermission(Chat chat, sdk.PermissionRequest request) {
  chat.permissions.add(request);
  chat.session.pauseStopwatch();
  chat.metrics.recordPermissionRequestTime(request.toolUseId);
  NotificationService.instance.notifyPermissionRequest(chat.data);
}
```

### saveMeta

Persistence reads from sub-states via the Chat reference:

```dart
class ChatPersistence {
  Future<void> saveMeta(Chat chat) async {
    final meta = {
      'model': chat.settings.model.toJson(),
      'security': chat.settings.securityConfig.toJson(),
      'usage': chat.metrics.cumulativeUsage.toJson(),
      'modelUsage': chat.metrics.modelUsage.map((m) => m.toJson()).toList(),
      'timing': chat.metrics.timingStats.toJson(),
      'context': chat.metrics.contextTracker.toContextInfo().toJson(),
      'agentId': chat.agents.agentId,
      'lastSessionId': chat.session.lastSessionId,
      // ...
    };
    await _serializedWrite(_metaPath, jsonEncode(meta));
  }
}
```

---

## Provider Wiring

When a chat is selected, `SelectionState` exposes the `Chat` object. Sub-states are made available to widgets via ProxyProviders:

During Phase 1 and Phase 2 (compatibility facade active), `SelectionState` may still expose `ChatState`. In that case, provider setup should read sub-states through facade accessors (`selection.selectedChatState?.session`, etc.). The snippet below shows the post-facade end state.

```dart
// SelectionState
Chat? get selectedChat => selectedWorktree?.selectedChat;

// Provider setup in main.dart (or a ChatProviderScope widget):
ProxyProvider<SelectionState, ChatSessionState?>(
  update: (_, selection, __) => selection.selectedChat?.session,
),
ProxyProvider<SelectionState, ChatPermissionState?>(
  update: (_, selection, __) => selection.selectedChat?.permissions,
),
ProxyProvider<SelectionState, ChatSettingsState?>(
  update: (_, selection, __) => selection.selectedChat?.settings,
),
ProxyProvider<SelectionState, ChatMetricsState?>(
  update: (_, selection, __) => selection.selectedChat?.metrics,
),
ProxyProvider<SelectionState, ChatAgentState?>(
  update: (_, selection, __) => selection.selectedChat?.agents,
),
ProxyProvider<SelectionState, ChatConversationState?>(
  update: (_, selection, __) => selection.selectedChat?.conversations,
),
ProxyProvider<SelectionState, ChatViewState?>(
  update: (_, selection, __) => selection.selectedChat?.viewState,
),
```

Widgets watch only what they need:

```dart
// ConversationPanel — only rebuilds for session + permission changes
final session = context.watch<ChatSessionState?>();
final permissions = context.watch<ChatPermissionState?>();

// ConversationHeader — only rebuilds for settings + metrics changes
final settings = context.watch<ChatSettingsState?>();
final metrics = context.watch<ChatMetricsState?>();

// ChatsPanel — only rebuilds for conversation + view state changes
final conversations = context.watch<ChatConversationState?>();
final viewState = context.watch<ChatViewState?>();

// WelcomeCard — only rebuilds for agent + session changes
final agents = context.watch<ChatAgentState?>();
final session = context.watch<ChatSessionState?>();
```

---

## Migration Strategy

To avoid a big-bang swap, the rewrite uses a compatibility facade during migration:

### Phase 1: Build sub-states alongside ChatState

Create the sub-state classes. ChatState internally creates and delegates to them but continues to expose its existing API. Existing consumers keep working unchanged.

```dart
// Temporary: ChatState wraps sub-states during migration
class ChatState extends ChangeNotifier {
  late final ChatSessionState session;
  late final ChatPermissionState permissions;
  // ... etc

  // Old API still works — delegates internally
  bool get isWorking => session.isWorking;
  void setWorking(bool v) { session.setWorking(v); notifyListeners(); }
}
```

### Phase 2: Migrate consumers to sub-states

One panel/service at a time, switch from `context.watch<ChatState>()` to watching specific sub-states. ChatState facade stays available for unmigrated code.

### Phase 3: Remove ChatState facade

Once all consumers use sub-states directly, delete the ChatState class. Replace with the plain `Chat` container. Remove compatibility shims.

This allows staged rollout without freezing feature work. Each migration step is independently committable.

---

## Execution Order

Start with the least-coupled subsystem and work toward the most-coupled. Each step is independently committable and testable.

### Step 1: ChatViewState

Extract `draftText`, `_unreadCount`, `_isBeingViewed` into a UI-layer state object. Smallest extraction, zero coupling to other sub-states. Validates the migration pattern.

### Step 2: ChatConversationState

Extract conversation/entry management and selection. Self-contained — entries are added, selected, and displayed without complex cross-concern coupling. Largest consumer-facing surface but cleanest boundary.

### Step 3: ChatSettingsState

Extract model, security config, reasoning effort, and ACP metadata. Clean boundary — settings are read by ConversationHeader and mutated by user actions or server sync.

### Step 4: ChatMetricsState

Extract usage tracking, timing stats, and context tracker. Already partially extracted via `ContextTracker`. Move the rest (cumulative usage, model usage, timing stats, in-turn tokens, permission timing).

### Step 5: ChatAgentState

Extract agent lifecycle management. Clean boundary — agents are created by subagent events, updated on status changes, and displayed in the agents panel.

### Step 6: ChatPermissionState

Extract permission queue management. Needs coordination with session state (stopwatch pause/resume) and metrics (response time tracking), but those interactions move to `ChatSessionService`.

### Step 7: ChatSessionState + session state machine

Extract session/transport lifecycle, working state, and compacting state. Introduce the `SessionPhase` state machine. This is the most coupled concern — session start/stop touches many other sub-states, but that coordination is already in `ChatSessionService` by this point.

### Step 8: ChatPersistence

Extract persistence logic with serialized write queues and retry policy. Reads from all sub-states for `saveMeta()`, so it's extracted last when sub-state APIs are stable.

### Step 9: SessionEventPipeline

Replace shared `EventHandler` mutable tracking maps with per-session pipeline instances. Create pipeline in `ChatSessionService.startSession()`, dispose in teardown.

### Step 10: Chat container + Provider wiring

Replace `ChatState` compatibility facade with the plain `Chat` container. Update `SelectionState`, `WorktreeState`, provider setup in `main.dart`, and any remaining consumers.

### Step 11: Test migration

Update test files to use sub-state APIs. Add unit tests for each sub-state in isolation. Remove tests that assumed monolithic ChatState behavior.

---

## Impact Assessment

| Area | Effort | Files |
|------|--------|-------|
| ChatState → Chat + 8 sub-states + pipeline | High | 10 new files, delete 1 |
| SessionEventPipeline (replaces EventHandler maps) | High | 1 new file, 3-5 files modified |
| ChatSessionService orchestration | Medium | 1 file |
| Provider wiring in main.dart | Medium | 1 file |
| ConversationPanel, ContentPanel | Low | 2 files |
| ConversationHeader | Low | 1 file |
| ChatsPanel | Low | 1 file |
| SelectionState | Low | 1 file |
| WorktreeState (holds Chat instead of ChatState) | Low | 1 file |
| ProjectRestoreService | Low | 1 file |
| WelcomeCard, AgentsPanel | Low | 2 files |
| Other consumers with direct ChatState usage | Medium | 8-15 files |
| Tests | Medium | ~10-20 test files |
| **Total** | | **~35-50 files** |

---

## Hard Acceptance Gates

The rewrite is considered complete only when all gates are true:

1. **No god class.** `ChatState` no longer exists. `Chat` is a plain container with no business logic, no notification, and no side effects.
2. **Independent notification.** Each sub-state is a ChangeNotifier. Changing model settings does not rebuild the permission dialog or unread badge.
3. **Per-session event routing.** Tool pairing and conversation routing maps are per-session, not shared globally. No cross-chat contamination possible.
4. **Single teardown path.** Session cleanup converges to one idempotent `_teardown()` method. No duplicate cleanup branches.
5. **Session state machine.** Session phase transitions are explicit and enforced. Invalid transitions (e.g., `sendMessage` during `stopping`) are prevented.
6. **Durable persistence.** All chat writes use serialized queues. Write failures are logged with context. No silent data loss from concurrent `FileMode.append`.
7. **No UI state in domain model.** `draftText`, unread count, and viewed flag live in `ChatViewState` at the UI layer, not in any domain sub-state.
8. **Behavior preserved.** Existing user-facing chat behavior is unchanged: session resume, permissions, subagents, streaming, usage display.
9. **Facade removed.** No production compile-time references to `ChatState` remain.

---

## Risks and Tradeoffs

**Risks:**

- Temporary dual-path complexity during the compatibility facade phase
- Regression risk in event ordering and streaming finalization (mitigate: step 9 is late, after sub-states are stable)
- Test churn due to API boundary changes
- Provider wiring becomes more verbose (8 ProxyProviders vs 1)
- Migration surface is larger than it first appears because `ChatState` is referenced broadly across UI + tests

**Tradeoffs:**

- Higher near-term change cost in exchange for lower long-term defect rate and much better testability
- More Provider boilerplate in exchange for targeted rebuilds and clear ownership
- Per-session pipeline means slightly more object allocation per session in exchange for eliminating stale routing bugs

**Not doing this rewrite** keeps shipping velocity superficially high but preserves a high-risk defect surface where any ChatState change can break unrelated behavior.
