# Token and Cost Tracking

This document covers how the Claude Agent SDK reports token usage and costs, how our implementation handles it, and considerations for tracking per-subagent costs.

## What the SDK Provides

The SDK provides usage data at multiple levels:

### 1. Per-Message Usage (`SDKAssistantMessage.message.usage`)

Each assistant message includes usage for that API turn:

```dart
class Usage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;
}
```

**Important**: Multiple content blocks (text + tool_use + tool_use) from the same API response share the same message ID and report identical usage. Deduplicate by `message.id` to avoid double-counting.

### 2. Result Message (`SDKResultMessage`)

When a turn completes, the result message provides:

```dart
class SDKResultMessage {
  final double? totalCostUsd;           // Cumulative cost (all turns + subagents)
  final Usage? usage;                    // Last turn only (NOT cumulative)
  final Map<String, ModelUsage>? modelUsage;  // Per-model breakdown
}
```

### 3. Per-Model Breakdown (`modelUsage`)

The `modelUsage` map is keyed by model name and provides cumulative stats per model:

```dart
class ModelUsage {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
  final int webSearchRequests;
  final double costUsd;        // Per-model cost (calculated by SDK)
  final int contextWindow;     // Model's context limit
}
```

Example with Sonnet main agent + Haiku subagent:
```
modelUsage = {
  "claude-sonnet-4-20250514": ModelUsage(inputTokens: 5000, outputTokens: 1200, costUsd: 0.05),
  "claude-haiku-3-5-20241022": ModelUsage(inputTokens: 2000, outputTokens: 800, costUsd: 0.002),
}
```

## Current Implementation

### Cost Tracking (`session_provider.dart`)

```dart
void _handleResultMessage(Session session, SDKResultMessage msg) {
  final usage = UsageInfo(
    inputTokens: msg.usage?.inputTokens ?? 0,      // LAST TURN ONLY
    outputTokens: msg.usage?.outputTokens ?? 0,     // LAST TURN ONLY
    cacheReadTokens: msg.usage?.cacheReadInputTokens ?? 0,
    cacheCreationTokens: msg.usage?.cacheCreationInputTokens ?? 0,
    costUsd: msg.totalCostUsd ?? 0.0,               // CUMULATIVE (correct)
  );
  session.complete(usage);
}
```

**Status**:
- `costUsd` is correct - uses cumulative `totalCostUsd` which includes all turns and subagents
- Token counts are misleading - only reflect the last turn, not cumulative totals
- `modelUsage` is available but unused for token totals

### Context Window Tracking (`session.dart`)

```dart
class ContextTracker {
  void updateFromAssistantMessage(SDKAssistantMessage message) {
    // Skip subagent messages - they have their own context
    if (message.parentToolUseId != null) return;

    final usage = message.message.usage;
    _currentTokens = usage.inputTokens +
        (usage.cacheCreationInputTokens ?? 0) +
        (usage.cacheReadInputTokens ?? 0);
    _model = message.message.model;
  }

  void updateFromResultMessage(SDKResultMessage message) {
    // Get context window limit from modelUsage for the active model
    final usage = message.modelUsage?[_model];
    if (usage != null) {
      _maxTokens = usage.contextWindow;
    }
  }
}
```

**Status**: Correctly tracks main agent context only. Subagent messages are skipped intentionally.

## Subagent Context Independence

Subagents have their own independent context windows. Each subagent spawned via the Task tool:

1. Starts a fresh conversation (not inheriting parent's history)
2. Gets only the task prompt as initial context
3. Builds its own conversation as it works
4. Returns only its final result to the parent

From the parent's perspective, a subagent only consumes:
- The `tool_use` block (Task tool invocation with prompt)
- The `tool_result` block (subagent's final response)

The parent does NOT see the subagent's intermediate messages, tool calls, or internal context growth.

### Tracking Subagent Context

To track context per subagent, modify the Agent class and message handling:

```dart
class Agent {
  int currentContextTokens = 0;
  int maxContextTokens = 200000;
  String? model;
}

void _handleAssistantMessage(Session session, SDKAssistantMessage msg) {
  final agentId = msg.parentToolUseId ?? 'main';
  final agent = session.agents[agentId];

  if (agent != null && msg.message.usage != null) {
    final usage = msg.message.usage!;
    agent.currentContextTokens = usage.inputTokens +
        (usage.cacheCreationInputTokens ?? 0) +
        (usage.cacheReadInputTokens ?? 0);
    agent.model = msg.message.model;
  }
}
```

## Subagent Cost Tracking

### The Challenge

The SDK provides:
- `totalCostUsd` - single cumulative number for entire session
- `modelUsage` - per-model breakdown (NOT per-agent)

If multiple subagents use the same model, their costs are combined in `modelUsage` and cannot be separated using SDK data alone.

### Option 1: Different Models = Clean Split

If subagents use different models than the main agent, `modelUsage` provides exact per-model costs:

```dart
// Main agent uses Sonnet, subagent uses Haiku
final mainCost = msg.modelUsage?["claude-sonnet-4-..."]?.costUsd ?? 0;
final subagentCost = msg.modelUsage?["claude-haiku-3-5-..."]?.costUsd ?? 0;
```

This is the cleanest approach when applicable.

### Option 2: Calculate Cost from Token Counts

Track per-agent token usage and calculate cost using model pricing:

```dart
class Agent {
  final Set<String> _seenMessageIds = {};
  int totalInputTokens = 0;
  int totalOutputTokens = 0;
  int totalCacheReadTokens = 0;
  double calculatedCostUsd = 0.0;
}

void _handleAssistantMessage(Session session, SDKAssistantMessage msg) {
  final agentId = msg.parentToolUseId ?? 'main';
  final agent = session.agents[agentId];
  final messageId = msg.message.id;

  // Deduplicate by message ID
  if (agent != null &&
      messageId != null &&
      !agent._seenMessageIds.contains(messageId)) {

    agent._seenMessageIds.add(messageId);

    final usage = msg.message.usage;
    if (usage != null) {
      agent.totalInputTokens += usage.inputTokens;
      agent.totalOutputTokens += usage.outputTokens;
      agent.totalCacheReadTokens += usage.cacheReadInputTokens ?? 0;

      agent.calculatedCostUsd += _calculateCost(msg.message.model, usage);
    }
  }
}

double _calculateCost(String? model, Usage usage) {
  // Pricing per million tokens - VERIFY CURRENT PRICES AT anthropic.com/pricing
  final (inputPrice, outputPrice, cacheReadPrice) = switch (model) {
    String m when m.contains('opus') => (15.0, 75.0, 1.5),
    String m when m.contains('sonnet') => (3.0, 15.0, 0.3),
    String m when m.contains('haiku') => (0.25, 1.25, 0.025),
    _ => (3.0, 15.0, 0.3), // default to sonnet pricing
  };

  return (usage.inputTokens * inputPrice / 1000000) +
         (usage.outputTokens * outputPrice / 1000000) +
         ((usage.cacheReadInputTokens ?? 0) * cacheReadPrice / 1000000);
}
```

**Caveats**:
- Requires maintaining pricing tables (prices change)
- May not match `totalCostUsd` exactly due to rounding, cache tiers, web search costs
- Extended thinking tokens may have different pricing

### Option 3: Show Tokens Per-Agent, Cost Per-Model

The pragmatic approach - track what you can accurately:

- **Per-agent**: Show token counts (input, output, cache) - always accurate
- **Per-model**: Show cost from `modelUsage` - SDK-calculated, accurate
- **Total**: Show `totalCostUsd` - authoritative

Accept that same-model subagents cannot have their costs separated without hardcoding prices.

### Why Proportional Splitting Doesn't Work

You cannot proportionally split `modelUsage.costUsd` by token count because input and output tokens have different prices.

Example with two Sonnet subagents:
- Subagent A: 10 input, 1000 output → ~$0.015 (mostly output cost)
- Subagent B: 500 input, 10 output → ~$0.0016 (mostly input cost)

Combined `modelUsage` shows ~$0.017, but splitting by total tokens (1010 vs 510) would give wrong proportions. You need the actual pricing rates to calculate correctly.

## Message ID Deduplication

Per the SDK documentation, all messages with the same `id` field report identical usage. When Claude sends multiple content blocks in one turn (text + tool_use + tool_use), they share the same message ID.

**Rule**: Track processed message IDs and only count usage once per unique ID.

```dart
final Set<String> processedMessageIds = {};

void processMessage(SDKAssistantMessage msg) {
  final messageId = msg.message.id;
  if (messageId == null || processedMessageIds.contains(messageId)) {
    return; // Skip duplicate
  }

  processedMessageIds.add(messageId);
  // Now safe to accumulate usage
}
```

## Recommendations

1. **For accurate total cost**: Use `totalCostUsd` from the result message (already implemented)

2. **For accurate token totals**: Sum across `modelUsage` entries instead of using last-turn `usage`

3. **For per-model breakdown**: Display `modelUsage` entries - useful when subagents use different models

4. **For per-agent tokens**: Track per-agent with message ID deduplication

5. **For per-agent cost**: Either use different models per agent (clean split) or calculate from tokens (requires price maintenance)

## Related Files

- `claude_dart_sdk/lib/src/types/usage.dart` - Usage and ModelUsage types
- `claude_dart_sdk/lib/src/types/sdk_messages.dart` - SDKResultMessage with modelUsage
- `flutter_app/lib/models/session.dart` - ContextTracker, Agent, UsageInfo
- `flutter_app/lib/providers/session_provider.dart` - Message handling and cost tracking
- `docs/sdk/cost-tracking.md` - SDK documentation reference
