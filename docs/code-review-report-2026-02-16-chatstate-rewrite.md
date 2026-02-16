# ChatState God Object Decomposition — Proposal

**Date:** 2026-02-16
**Status:** Proposal
**Scope:** Moderate rewrite of ChatState and its direct consumers (~20 files)

---

## Problem

`ChatState` (`frontend/lib/models/chat.dart`) is a 2150+ line god object with 58+ fields, 100+ methods, and 10+ responsibilities. It conflates three roles:

1. **Data container** — holds ChatData, conversations, entries
2. **Runtime controller** — manages session, transport, permissions, working state
3. **Universal notification source** — one `notifyListeners()` for everything

A delegation approach (extracting logic into plain helper classes while keeping ChatState as a facade) would reduce line count but not fix the architecture. ChatState would still know about all delegates, orchestrate all cross-concern methods, and be the single notification bottleneck. Changing the model would still rebuild the permission dialog. It's a thinner god class, but still the god class.

---

## Solution

**ChatState stops being a ChangeNotifier.** It becomes a plain container (`Chat`) that holds independent sub-states, each its own ChangeNotifier. Consumers watch only the sub-state they need. Cross-concern coordination moves to services.

### Decomposition

```
Chat (plain class — identity + sub-state references)
├── ChatData              (immutable, already exists)
├── ChatSessionState      (ChangeNotifier — session, transport, working, compacting)
├── ChatPermissionState   (ChangeNotifier — permission queue, stopwatch)
├── ChatSettingsState     (ChangeNotifier — model, security, ACP, reasoning)
├── ChatMetricsState      (ChangeNotifier — usage, timing, context)
├── ChatAgentState        (ChangeNotifier — agents, agent config)
├── ChatConversationState (ChangeNotifier — entries, selected conversation, unread)
└── ChatPersistence       (plain class — no notification, fire-and-forget writes)
```

### Sub-State Ownership

#### ChatSessionState (ChangeNotifier)

**Owns:** `_transport`, `_session`, `_eventSubscription`, `_permissionSubscription`, `_eventHandler`, `_lastSessionId`, `_hasStarted`, `_capabilities`, `_isWorking`, `_isCompacting`, `_workingStopwatch`

**Getters:** `hasActiveSession`, `isWorking`, `isCompacting`, `workingStopwatch`, `lastSessionId`, `hasStarted`, `capabilities`

**Methods:** `start()`, `stop()`, `interrupt()`, `sendMessage()`, `setWorking()`, `setCompacting()`, `pauseStopwatch()`, `resumeStopwatch()`, `clearSession()`

**Watched by:** `ConversationPanel`, `ContentPanel`, `WelcomeCard`

#### ChatPermissionState (ChangeNotifier)

**Owns:** `_pendingPermissions`, `_permissionRequestTimes`

**Getters:** `isWaitingForPermission`, `pendingPermission`, `pendingPermissionCount`, `hasPending`

**Methods:** `addPendingPermission()`, `popFront()`, `removePendingPermissionByToolUseId()`, `recordResponseTime()`, `clear()`

**Watched by:** `ConversationPanel` (permission dialog), `ChatsPanel` (badge)

#### ChatSettingsState (ChangeNotifier)

**Owns:** `_model`, `_reasoningEffort`, `_securityConfig`, `_acpConfigOptions`, `_acpAvailableCommands`, `_acpCurrentModeId`, `_acpAvailableModes`

**Getters:** `model`, `securityConfig`, `permissionMode`, `reasoningEffort`, `acpConfigOptions`, `acpAvailableCommands`, `acpCurrentModeId`, `acpAvailableModes`

**Methods:** `setModel()`, `setPermissionMode()`, `setSecurityConfig()`, `setReasoningEffort()`, `syncModelFromServer()`, `syncReasoningEffortFromServer()`, `syncFromServer()`, all ACP methods, `clearAcpMetadata()`, `syncPermissionModeFromResponse()`

**Watched by:** `ConversationHeader` (settings display)

#### ChatMetricsState (ChangeNotifier)

**Owns:** `_cumulativeUsage`, `_inTurnOutputTokens`, `_modelUsage`, `_baseModelUsage`, `_timingStats`, `_contextTracker`

**Getters:** `cumulativeUsage`, `modelUsage`, `timingStats`, `contextTracker`

**Methods:** `addInTurnOutputTokens()`, `updateCumulativeUsage()`, `updateContextFromUsage()`, `resetContext()`, `restoreFromMeta()`, `recordPermissionResponseTime()`

**Watched by:** `ConversationHeader` (usage display, context indicator)

#### ChatAgentState (ChangeNotifier)

**Owns:** `_activeAgents`, `_agentId`, `_agentRemoved`, `_missingAgentMessage`

**Getters:** `activeAgents`, `agentId`, `agentRemoved`, `missingAgentMessage`, `agentName`

**Methods:** `addSubagentConversation()`, `updateAgent()`, `findAgentByResumeId()`, `markAgentMissing()`, `clearAll()`

**Watched by:** `ConversationHeader` (agent info), `WelcomeCard` (agent status)

#### ChatConversationState (ChangeNotifier)

**Owns:** `_data` (ChatData reference for conversations), `_selectedConversationId`, `_unreadCount`, `_isBeingViewed`, `draftText`

**Getters:** `selectedConversation`, `isInputEnabled`, `unreadCount`, `hasUnreadMessages`, `data`

**Methods:** `selectConversation()`, `resetToMainConversation()`, `addEntry()`, `addOutputEntry()`, `clearEntries()`, `loadEntriesFromPersistence()`, `markHistoryAsLoaded()`, `markAsViewed()`, `markAsNotViewed()`, `rename()`

**Watched by:** `ConversationPanel` (entries), `ChatsPanel` (name, unread badge)

#### ChatPersistence (plain class — not a ChangeNotifier)

**Owns:** `_projectId`, `_projectRoot`, `_metaSaveTimer`, `_historyLoaded`, `persistenceService`

**Methods:** `initPersistence()`, `persistEntry()`, `persistStreamingEntry()`, `persistToolResult()`, `scheduleMetaSave()`, `markStarted()`, `saveMeta(Chat)`, `persistSessionId()`, `persistRename()`

**Not watched by anyone** — fire-and-forget writes, no UI representation.

#### Chat (plain class — not a ChangeNotifier)

```dart
class Chat {
  final ChatConversationState conversations;
  final ChatSessionState session;
  final ChatPermissionState permissions;
  final ChatSettingsState settings;
  final ChatMetricsState metrics;
  final ChatAgentState agents;
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
    persistence.dispose();
  }
}
```

---

## Cross-Concern Coordination

Operations that span multiple sub-states live in services, not in a facade. `ChatSessionService` already exists and becomes the orchestrator.

### startSession

```dart
class ChatSessionService {
  Future<void> startSession(Chat chat, BackendService backend, ...) async {
    final transport = await backend.createTransport(...);
    chat.session.start(transport);
    chat.settings.syncFromServer(transport);
    chat.metrics.reset();
    chat.persistence.markStarted();
    chat.persistence.persistSessionId(transport.sessionId);
  }
}
```

### allowPermission

```dart
void allowPermission(Chat chat, {String? toolName, ...}) {
  final request = chat.permissions.popFront();
  request.allow();
  chat.metrics.recordPermissionResponseTime(request.toolUseId);
  chat.settings.syncPermissionModeFromResponse(toolName, ...);
  if (!chat.permissions.hasPending) {
    chat.session.resumeStopwatch();
  }
}
```

### stopSession

```dart
Future<void> stopSession(Chat chat) async {
  await chat.session.stop();
  chat.permissions.clear();
  chat.agents.clearAll();
  chat.settings.clearAcpMetadata();
}
```

### addPendingPermission

```dart
void addPendingPermission(Chat chat, sdk.PermissionRequest request) {
  chat.permissions.addPendingPermission(request);
  chat.session.pauseStopwatch();
  chat.metrics.recordPermissionRequestTime(request.toolUseId);
  NotificationService.instance.notifyPermissionRequest(chat.data);
}
```

### saveMeta

Persistence reads from sub-states but doesn't own them:

```dart
class ChatPersistence {
  Future<void> saveMeta(Chat chat) async {
    final meta = {
      'model': chat.settings.model.toJson(),
      'security': chat.settings.securityConfig.toJson(),
      'usage': chat.metrics.cumulativeUsage.toJson(),
      'timing': chat.metrics.timingStats.toJson(),
      'context': chat.metrics.contextTracker.toContextInfo().toJson(),
      'agentId': chat.agents.agentId,
      // ...
    };
    await persistenceService.saveMeta(chat.data.id, meta);
  }
}
```

---

## EventHandler

Instead of receiving a monolithic `ChatState`, EventHandler receives a `Chat` reference and dispatches to the right sub-state:

```dart
void handleEvent(Chat chat, InsightsEvent event) {
  switch (event) {
    case AssistantMessageEvent():
      chat.conversations.addEntry(convId, TextOutputEntry(...));
      chat.session.setWorking(true);

    case ToolUseEvent():
      chat.conversations.addEntry(convId, ToolUseOutputEntry(...));

    case UsageUpdateEvent():
      chat.metrics.addInTurnOutputTokens(event.outputTokens);
      chat.metrics.updateContextFromUsage(event.usage);

    case TurnCompleteEvent():
      chat.session.setWorking(false);
      chat.metrics.updateCumulativeUsage(...);

    case ModelChangeEvent():
      chat.settings.syncModelFromServer(event.model);
  }
}
```

This is the same number of calls as today — each event maps to a specific sub-state instead of all going through one fat object.

---

## Provider Wiring

When a chat is selected, SelectionState exposes the `Chat` object. Sub-states are made available via ProxyProviders:

```dart
// SelectionState exposes the selected Chat
Chat? get selectedChat => selectedWorktree?.selectedChat;

// Provider setup:
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
```

Widgets watch only what they need:

```dart
// ConversationPanel — only rebuilds for session + permission changes
final session = context.watch<ChatSessionState?>();
final permissions = context.watch<ChatPermissionState?>();

// ConversationHeader — only rebuilds for settings + metrics changes
final settings = context.watch<ChatSettingsState?>();
final metrics = context.watch<ChatMetricsState?>();

// ChatsPanel — only rebuilds for conversation changes (name, unread count)
final conversations = context.watch<ChatConversationState?>();
```

---

## Impact Assessment

| Area | Effort | Files |
|------|--------|-------|
| ChatState → Chat + 7 sub-states | High | 8 new files, delete 1 |
| EventHandler signatures | Medium | 1 file, ~50 call sites internal |
| ChatSessionService orchestration | Medium | 1 file |
| Provider wiring in main.dart | Medium | 1 file |
| ConversationPanel, ContentPanel | Low | 2 files |
| ConversationHeader | Low | 1 file |
| ChatsPanel | Low | 1 file |
| SelectionState | Low | 1 file |
| ProjectRestoreService | Low | 1 file |
| Tests | Medium | ~5-8 test files |
| **Total** | | **~20 files** |

---

## Execution Order

Each step is independently committable and testable.

### Step 1: ChatConversationState

Extract conversation/entry management and unread tracking. This is the most self-contained concern — entries are added, selected, and displayed without complex cross-concern coupling.

### Step 2: ChatSettingsState

Extract model, security config, reasoning effort, and ACP metadata. Clean boundary — settings are read by ConversationHeader and mutated by user actions or server sync.

### Step 3: ChatMetricsState

Extract usage tracking, timing stats, and context tracker. Already partially extracted via `ContextTracker`. Move the rest (cumulative usage, model usage, timing stats, in-turn tokens).

### Step 4: ChatAgentState

Extract agent lifecycle management. Clean boundary — agents are created by subagent events, updated on status changes, and displayed in the agents panel.

### Step 5: ChatPermissionState

Extract permission queue management. Needs coordination with session state (stopwatch pause/resume) and metrics (response time tracking), but those interactions move to `ChatSessionService`.

### Step 6: ChatSessionState

Extract session/transport lifecycle, working state, and compacting state. This is the most coupled concern — session start/stop touches many other sub-states, but that coordination moves to `ChatSessionService`.

### Step 7: ChatPersistence

Extract persistence logic. Reads from all sub-states for `saveMeta()`, so it's extracted last when sub-state APIs are stable.

### Step 8: Chat container + Provider wiring

Replace `ChatState` with the plain `Chat` container class. Update `SelectionState`, `WorktreeState`, provider setup in `main.dart`, and remaining consumers.

### Step 9: Test updates

Update test files to use the new sub-state APIs. Add unit tests for each sub-state in isolation.

---

## Benefits

- **Targeted rebuilds** — changing the model doesn't rebuild the permission dialog or the unread badge
- **Independent testability** — each sub-state can be unit tested with a simple constructor, no need to set up 58 fields
- **No god class** — not even a thin facade; coordination lives in services where it belongs
- **Clear ownership** — each field and method belongs to exactly one sub-state
- **Incremental execution** — each step is independently committable and the app stays functional throughout

## Non-Goals

- This proposal does NOT restructure models, services, panels, or widgets beyond what's needed to consume the new sub-states
- This proposal does NOT change the EventTransport abstraction or SDK integration
- This proposal does NOT introduce new state management patterns (still ChangeNotifier + Provider)
