# ACP Usage Tracking: Problem & Solution

This document describes the gaps in ACP's usage/cost tracking compared to CC-Insights' current SDK-based implementation, and outlines the approach to solve them.

---

## Problem Statement

CC-Insights is named for its **insights** into Claude's context windows and cost tracking. The current SDK-based implementation provides rich telemetry including:

- Per-turn token usage (input, output, cached)
- Cumulative session cost in USD
- Context window utilization (used vs available)
- Per-model usage breakdown
- Compaction notifications (auto and manual)
- Context cleared events

When migrating to ACP for multi-agent support, we risk losing these core features because:

1. **ACP's usage tracking is still an RFD** (Request for Discussion) - not yet in the stable spec
2. **`claude-code-acp` doesn't implement it** - even the proposed fields aren't forwarded
3. **Some features have no ACP equivalent** - per-model breakdown, compaction events

Losing these features would undermine the core value proposition of CC-Insights.

---

## Current Implementation (SDK-based)

### Data Sources

The current `SdkMessageHandler` extracts usage data from SDK messages:

#### From `assistant` messages (`message.usage`):
```json
{
  "type": "assistant",
  "message": {
    "usage": {
      "input_tokens": 1500,
      "output_tokens": 500,
      "cache_read_input_tokens": 1000,
      "cache_creation_input_tokens": 200
    }
  }
}
```

#### From `result` messages:
```json
{
  "type": "result",
  "subtype": "success",
  "total_cost_usd": 0.045,
  "usage": {
    "input_tokens": 35000,
    "output_tokens": 12000,
    "cache_read_input_tokens": 5000,
    "cache_creation_input_tokens": 1000
  },
  "modelUsage": {
    "claude-sonnet-4-20250514": {
      "inputTokens": 30000,
      "outputTokens": 10000,
      "cacheReadInputTokens": 5000,
      "cacheCreationInputTokens": 1000,
      "costUSD": 0.04,
      "contextWindow": 200000
    },
    "claude-haiku-3-5-20241022": {
      "inputTokens": 5000,
      "outputTokens": 2000,
      "costUSD": 0.005,
      "contextWindow": 200000
    }
  }
}
```

#### From `system` messages:
```json
{
  "type": "system",
  "subtype": "compact_boundary",
  "compact_metadata": {
    "trigger": "auto",
    "pre_tokens": 180000
  }
}
```

```json
{
  "type": "system",
  "subtype": "context_cleared"
}
```

### Features Provided

| Feature | Source | UI Display |
|---------|--------|------------|
| Context % used | `usage.input_tokens` / `contextWindow` | Progress bar, percentage |
| Tokens this turn | `assistant.message.usage` | Per-message display |
| Cumulative cost | `result.total_cost_usd` | Session total |
| Per-model breakdown | `result.modelUsage` | Which model used how much |
| Compaction alert | `system.compact_boundary` | "Context compacted" notification |
| Context cleared | `system.context_cleared` | "Context cleared" notification |

---

## ACP Specification Gap Analysis

### What ACP Proposes (RFD - Not Yet Stable)

The [session-usage RFD](../packages/agent-client-protocol/docs/rfds/session-usage.mdx) proposes:

#### Token Usage in `PromptResponse`:
```json
{
  "result": {
    "stopReason": "end_turn",
    "usage": {
      "total_tokens": 53000,
      "input_tokens": 35000,
      "output_tokens": 12000,
      "thought_tokens": 5000,
      "cached_read_tokens": 5000,
      "cached_write_tokens": 1000
    }
  }
}
```

#### Context Window & Cost via `session/update`:
```json
{
  "method": "session/update",
  "params": {
    "sessionId": "sess_abc123",
    "update": {
      "sessionUpdate": "usage_update",
      "used": 53000,
      "size": 200000,
      "cost": {
        "amount": 0.045,
        "currency": "USD"
      }
    }
  }
}
```

### What's Missing from ACP Spec

| Feature | ACP Status | Impact |
|---------|------------|--------|
| Per-model usage breakdown | ❌ Not proposed | Can't show which model consumed what |
| Compaction events | ❌ Not proposed | No notification when context compacts |
| Context cleared events | ❌ Not proposed | No feedback for `/clear` command |
| Pre-compaction token count | ❌ Not proposed | Can't show "was X tokens" |

### What `claude-code-acp` Implements

Currently: **Nothing**

The `prompt()` method returns only `{ stopReason: "end_turn" }` with no usage data. The SDK's `result` message is processed for error handling but usage fields are discarded.

Relevant code (`acp-agent.ts` lines 290-326):
```typescript
case "result": {
  switch (message.subtype) {
    case "success": {
      // Usage data available in `message` but not extracted
      return { stopReason: "end_turn" };
    }
    // ...
  }
}
```

---

## Proposed Solution

### Approach: Patch `claude-code-acp` with Extensions

Use ACP's [extensibility mechanism](https://agentclientprotocol.com/docs/protocol/extensibility) to add Claude-specific data in `_meta` fields while implementing the proposed RFD fields for forward compatibility.

### Implementation Plan

#### 1. Fork `claude-code-acp`

Create a fork to develop and test patches before submitting upstream PRs.

#### 2. Extract Usage from SDK `result` Messages

Modify the `result` message handler to capture usage data:

```typescript
case "result": {
  switch (message.subtype) {
    case "success": {
      // Extract usage data
      const usage = message.usage ? {
        total_tokens: (message.usage.input_tokens ?? 0) +
                      (message.usage.output_tokens ?? 0),
        input_tokens: message.usage.input_tokens ?? 0,
        output_tokens: message.usage.output_tokens ?? 0,
        cached_read_tokens: message.usage.cache_read_input_tokens,
        cached_write_tokens: message.usage.cache_creation_input_tokens,
      } : undefined;

      return {
        stopReason: "end_turn",
        usage,  // Add to PromptResponse (per RFD)
      };
    }
  }
}
```

#### 3. Send `usage_update` Notifications

After each prompt completes, send context/cost update:

```typescript
// After prompt completes successfully
await this.client.sessionUpdate({
  sessionId,
  update: {
    sessionUpdate: "usage_update",
    used: message.usage?.input_tokens ?? 0,
    size: contextWindow,  // From modelUsage or default 200000
    cost: message.total_cost_usd ? {
      amount: message.total_cost_usd,
      currency: "USD",
    } : undefined,
    _meta: {
      claudeCode: {
        modelUsage: message.modelUsage,
      },
    },
  },
});
```

#### 4. Forward Compaction Events

Handle `system.compact_boundary` messages:

```typescript
case "system": {
  switch (message.subtype) {
    case "compact_boundary": {
      await this.client.sessionUpdate({
        sessionId,
        update: {
          sessionUpdate: "usage_update",  // Or custom type
          _meta: {
            claudeCode: {
              compaction: {
                trigger: message.compact_metadata?.trigger ?? "auto",
                preTokens: message.compact_metadata?.pre_tokens,
              },
            },
          },
        },
      });
      break;
    }
    case "context_cleared": {
      await this.client.sessionUpdate({
        sessionId,
        update: {
          sessionUpdate: "usage_update",
          used: 0,
          size: contextWindow,
          _meta: {
            claudeCode: {
              contextCleared: true,
            },
          },
        },
      });
      break;
    }
  }
}
```

#### 5. Track Context Window Size

The context window size comes from `modelUsage` in result messages. Need to track the current model's context window:

```typescript
class ClaudeAcpAgent implements Agent {
  // Add to class state
  private contextWindowBySession: Map<string, number> = new Map();

  // Update when result received
  private updateContextWindow(sessionId: string, modelUsage: any) {
    if (modelUsage) {
      // Get context window from first model (or current model)
      const firstModel = Object.values(modelUsage)[0] as any;
      if (firstModel?.contextWindow) {
        this.contextWindowBySession.set(sessionId, firstModel.contextWindow);
      }
    }
  }
}
```

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Claude Agent SDK                            │
│                                                                 │
│  result message:                                                │
│  - total_cost_usd                                              │
│  - usage { input_tokens, output_tokens, cache_* }              │
│  - modelUsage { model: { tokens, cost, contextWindow } }       │
│                                                                 │
│  system message:                                                │
│  - compact_boundary { trigger, pre_tokens }                    │
│  - context_cleared                                             │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   claude-code-acp (patched)                     │
│                                                                 │
│  Extracts and forwards:                                         │
│  1. PromptResponse.usage (per RFD spec)                        │
│  2. session/update with usage_update (per RFD spec)            │
│  3. _meta.claudeCode.modelUsage (extension)                    │
│  4. _meta.claudeCode.compaction (extension)                    │
│  5. _meta.claudeCode.contextCleared (extension)                │
└────────────────────────────┬────────────────────────────────────┘
                             │ ACP Protocol
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CC-Insights Client                         │
│                                                                 │
│  Handles:                                                       │
│  - Standard ACP usage fields (works with any agent)            │
│  - Claude-specific _meta fields (enhanced experience)          │
│  - Graceful degradation for non-Claude agents                  │
└─────────────────────────────────────────────────────────────────┘
```

### CC-Insights Client Handling

The Dart client should handle both standard ACP fields and Claude extensions:

```dart
void _handleUsageUpdate(UsageUpdateSessionUpdate update) {
  // Standard ACP fields (all agents)
  if (update.used != null && update.size != null) {
    _contextTracker.update(
      used: update.used!,
      total: update.size!,
    );
  }

  if (update.cost != null) {
    _cumulativeCost = update.cost!.amount;
  }

  // Claude-specific extensions
  final claudeMeta = update.meta?['claudeCode'];
  if (claudeMeta != null) {
    // Per-model breakdown
    if (claudeMeta['modelUsage'] != null) {
      _modelUsage = _parseModelUsage(claudeMeta['modelUsage']);
    }

    // Compaction event
    if (claudeMeta['compaction'] != null) {
      _handleCompaction(claudeMeta['compaction']);
    }

    // Context cleared
    if (claudeMeta['contextCleared'] == true) {
      _handleContextCleared();
    }
  }
}
```

---

## Upstream Contribution Strategy

### Phase 1: Fork and Patch (Immediate)

1. Fork `claude-code-acp` to `anthropics/claude-code-acp` or personal repo
2. Implement all patches described above
3. Test with CC-Insights
4. Publish as npm package (e.g., `@anthropic-ai/claude-code-acp-extended`)

### Phase 2: Upstream PRs (Short-term)

1. **PR to `claude-code-acp`**: Implement RFD-proposed fields
   - `usage` in `PromptResponse`
   - `usage_update` notifications
   - Claude-specific `_meta` extensions

2. **Issue/Discussion on ACP spec**: Propose additions
   - Per-model usage breakdown
   - Compaction events
   - Context management notifications

### Phase 3: Spec Stabilization (Medium-term)

1. Monitor ACP RFD progress
2. Adjust implementation as spec stabilizes
3. Remove `_meta` workarounds if features are added to core spec

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Upstream rejects patches | Medium | High | Maintain fork, document extensions |
| ACP spec changes incompatibly | Low | Medium | Use `_meta` for non-standard fields |
| Other agents don't provide data | High | Low | Graceful degradation in UI |
| Maintenance burden of fork | Medium | Medium | Keep patches minimal, upstream quickly |

---

## Success Criteria

1. **Feature parity**: All current usage/cost features work with ACP
2. **Multi-agent support**: Non-Claude agents work (with reduced features)
3. **Upstream acceptance**: Patches merged to `claude-code-acp`
4. **Spec influence**: Usage features added to stable ACP spec

---

## References

- [ACP Session Usage RFD](../packages/agent-client-protocol/docs/rfds/session-usage.mdx)
- [ACP Extensibility](https://agentclientprotocol.com/docs/protocol/extensibility)
- [claude-code-acp source](../packages/claude-code-acp/src/acp-agent.ts)
- [Current SdkMessageHandler](../frontend/lib/services/sdk_message_handler.dart)
- [Current ChatState usage tracking](../frontend/lib/models/chat.dart)
