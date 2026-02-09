# InsightsEvent Protocol - Overview

The InsightsEvent protocol is a provider-neutral event model that unifies communication between multiple AI coding agent backends (Claude CLI, Codex CLI, ACP-compatible agents) and the CC-Insights frontend. Rather than forcing each backend into a lowest-common-denominator format, it preserves the full richness of each provider while giving the frontend a single typed interface to consume.

---

## High-Level Architecture

```mermaid
graph TB
    subgraph "AI Backends"
        Claude["Claude CLI<br/>(stream-json)"]
        Codex["Codex CLI<br/>(JSON-RPC 2.0)"]
        ACP["ACP Agent<br/>(JSON-RPC 2.0)"]
    end

    subgraph "Backend SDKs"
        CS["CliSession<br/>claude_dart_sdk"]
        CxS["CodexSession<br/>codex_dart_sdk"]
        AS["AcpSession<br/>(future)"]
    end

    subgraph "Transport Layer"
        IPT["InProcessTransport"]
        WST["WebSocketTransport<br/>(future)"]
        DT["DockerTransport<br/>(future)"]
    end

    subgraph "Frontend"
        EH["EventHandler"]
        CS2["ChatState"]
        UI["UI Panels"]
    end

    Claude -->|"stdin/stdout"| CS
    Codex -->|"JSON-RPC"| CxS
    ACP -->|"JSON-RPC"| AS

    CS -->|"InsightsEvents"| IPT
    CxS -->|"InsightsEvents"| IPT
    AS -->|"InsightsEvents"| WST

    IPT -->|"Stream&lt;InsightsEvent&gt;"| EH
    WST -->|"Stream&lt;InsightsEvent&gt;"| EH
    DT -->|"Stream&lt;InsightsEvent&gt;"| EH

    CS2 -->|"BackendCommand"| IPT
    CS2 -->|"BackendCommand"| WST

    EH -->|"OutputEntry"| CS2
    CS2 --> UI
```

---

## Event Flow

This diagram shows the lifecycle of a single user turn - from the user sending a message to the turn completing.

```mermaid
sequenceDiagram
    participant User
    participant UI as Frontend UI
    participant CS as ChatState
    participant T as EventTransport
    participant S as Session (Claude/Codex)
    participant CLI as Backend CLI

    User->>UI: Types message
    UI->>CS: sendMessage()
    CS->>T: send(SendMessageCommand)
    T->>S: session.send()
    S->>CLI: stdin (wire format)
    CLI-->>S: streaming response

    loop Content Streaming
        S-->>T: StreamDeltaEvent
        T-->>CS: event stream
        CS-->>UI: update output entry
    end

    S-->>T: TextEvent (finalized)
    T-->>CS: event stream

    opt Tool Use
        S-->>T: ToolInvocationEvent
        T-->>CS: event stream
        CS-->>UI: show tool card

        opt Needs Permission
            S-->>T: PermissionRequestEvent
            T-->>CS: event stream
            CS-->>UI: show permission dialog
            User->>UI: approve/deny
            UI->>CS: respondToPermission()
            CS->>T: send(PermissionResponseCommand)
            T->>S: completePermission()
        end

        S-->>T: ToolCompletionEvent
        T-->>CS: event stream
        CS-->>UI: update tool card with result
    end

    S-->>T: TurnCompleteEvent
    T-->>CS: event stream
    CS-->>UI: update cost/usage indicators
```

---

## InsightsEvent Type Hierarchy

All events share a common base with `id`, `timestamp`, `provider`, and optional `raw`/`extensions` fields.

```mermaid
classDiagram
    class InsightsEvent {
        <<sealed>>
        +String id
        +DateTime timestamp
        +BackendProvider provider
        +Map~String,dynamic~? raw
        +Map~String,dynamic~? extensions
    }

    class SessionInitEvent {
        +String? model
        +String? cwd
        +List~String~? tools
        +List~String~? mcpServers
        +Map? accountInfo
    }

    class SessionStatusEvent {
        +SessionStatus status
        +String? message
    }

    class TextEvent {
        +String text
        +TextKind kind
        +String? agentId
    }

    class ToolInvocationEvent {
        +String callId
        +ToolKind kind
        +String toolName
        +Map~String,dynamic~ input
        +List~String~? locations
        +String? agentId
    }

    class ToolCompletionEvent {
        +String callId
        +ToolCompletionStatus status
        +String? output
        +bool isError
        +List? contentBlocks
    }

    class TurnCompleteEvent {
        +double? costUsd
        +int? inputTokens
        +int? outputTokens
        +Duration? duration
        +Map? modelUsage
    }

    class PermissionRequestEvent {
        +String requestId
        +String toolName
        +Map~String,dynamic~ toolInput
        +List? suggestions
        +String? blockedPath
    }

    class StreamDeltaEvent {
        +StreamDeltaKind kind
        +String delta
        +String? callId
    }

    class SubagentSpawnEvent {
        +String parentCallId
        +String agentId
        +String? description
    }

    class SubagentCompleteEvent {
        +String agentId
        +String parentCallId
    }

    class ContextCompactionEvent {
        +String? trigger
        +int? preTokens
        +int? postTokens
        +String? summary
    }

    class UserInputEvent {
        +String text
        +List? images
    }

    InsightsEvent <|-- SessionInitEvent
    InsightsEvent <|-- SessionStatusEvent
    InsightsEvent <|-- TextEvent
    InsightsEvent <|-- ToolInvocationEvent
    InsightsEvent <|-- ToolCompletionEvent
    InsightsEvent <|-- TurnCompleteEvent
    InsightsEvent <|-- PermissionRequestEvent
    InsightsEvent <|-- StreamDeltaEvent
    InsightsEvent <|-- SubagentSpawnEvent
    InsightsEvent <|-- SubagentCompleteEvent
    InsightsEvent <|-- ContextCompactionEvent
    InsightsEvent <|-- UserInputEvent
```

---

## ToolKind Categories (ACP-Aligned)

Tools are classified using ACP's `kind` vocabulary, enabling consistent UI rendering regardless of backend.

```mermaid
graph LR
    subgraph "File System"
        read["read<br/>Read, cat"]
        edit["edit<br/>Edit, Write"]
        delete["delete"]
        move["move"]
    end

    subgraph "Execution"
        execute["execute<br/>Bash, Shell"]
        search["search<br/>Grep, Glob"]
        fetch["fetch<br/>WebFetch"]
        browse["browse<br/>WebSearch"]
    end

    subgraph "Agent"
        think["think<br/>Task, subagent"]
        ask["ask<br/>AskUserQuestion"]
        memory["memory<br/>TodoWrite"]
    end

    subgraph "External"
        mcp["mcp<br/>MCP server tools"]
        other["other<br/>Unknown/custom"]
    end
```

---

## Backend Command Flow

Commands flow from the frontend to the backend through the transport layer.

```mermaid
classDiagram
    class BackendCommand {
        <<sealed>>
        +toJson() Map
        +fromJson()$ BackendCommand
    }

    class SendMessageCommand {
        +String text
        +List? images
    }

    class PermissionResponseCommand {
        +String requestId
        +bool allowed
        +Map? updatedInput
    }

    class InterruptCommand
    class KillCommand

    class SetModelCommand {
        +String model
    }

    class SetPermissionModeCommand {
        +String mode
    }

    class SetReasoningEffortCommand {
        +String effort
    }

    BackendCommand <|-- SendMessageCommand
    BackendCommand <|-- PermissionResponseCommand
    BackendCommand <|-- InterruptCommand
    BackendCommand <|-- KillCommand
    BackendCommand <|-- SetModelCommand
    BackendCommand <|-- SetPermissionModeCommand
    BackendCommand <|-- SetReasoningEffortCommand
```

---

## Transport Abstraction

The `EventTransport` interface decouples the frontend from session implementation details, enabling future remote backends without frontend changes.

```mermaid
graph TB
    subgraph "EventTransport Interface"
        events["events: Stream&lt;InsightsEvent&gt;"]
        send["send(BackendCommand)"]
        status["status: Stream&lt;TransportStatus&gt;"]
        perms["permissionRequests: Stream&lt;PermissionRequestEvent&gt;"]
        caps["capabilities: BackendCapabilities?"]
    end

    subgraph "Implementations"
        IPT["InProcessTransport<br/>(wraps AgentSession)"]
        WST["WebSocketTransport<br/>(future)"]
        DT["DockerTransport<br/>(future)"]
    end

    IPT -.-> events
    IPT -.-> send
    WST -.-> events
    WST -.-> send
    DT -.-> events
    DT -.-> send

    subgraph "InProcessTransport Internals"
        session["AgentSession"]
        completers["Permission Completers<br/>(requestId → Completer)"]
    end

    IPT --- session
    IPT --- completers
```

---

## Backend Capability Comparison

Each backend provides different levels of detail. The frontend adapts its UI based on what data is available.

```mermaid
graph TD
    subgraph "Claude CLI (richest)"
        c1["Cost tracking (USD)"]
        c2["Context window metrics"]
        c3["Streaming deltas"]
        c4["Subagent hierarchy"]
        c5["Permission suggestions"]
        c6["Per-model usage breakdown"]
        c7["Account metadata"]
        c8["MCP server status"]
    end

    subgraph "Codex CLI"
        x1["File diffs (unified)"]
        x2["Plan/Reasoning output"]
        x3["Command execution"]
        x4["Token counts (no cost)"]
        x5["Reasoning effort control"]
    end

    subgraph "Shared (all backends)"
        s1["Text output"]
        s2["Tool invocation/completion"]
        s3["Permission requests"]
        s4["Session lifecycle"]
        s5["Turn completion"]
    end

    style c1 fill:#e8f5e9
    style c2 fill:#e8f5e9
    style c3 fill:#e8f5e9
    style c4 fill:#e8f5e9
    style c5 fill:#e8f5e9
    style c6 fill:#e8f5e9
    style c7 fill:#e8f5e9
    style c8 fill:#e8f5e9
    style x1 fill:#e3f2fd
    style x2 fill:#e3f2fd
    style x3 fill:#e3f2fd
    style x4 fill:#e3f2fd
    style x5 fill:#e3f2fd
```

---

## Frontend Event Processing

The `EventHandler` converts `InsightsEvent` objects into `OutputEntry` models for the UI.

```mermaid
flowchart LR
    subgraph "InsightsEvent Stream"
        TE[TextEvent]
        TIE[ToolInvocationEvent]
        TCE[ToolCompletionEvent]
        TuCE[TurnCompleteEvent]
        PRE[PermissionRequestEvent]
        SDE[StreamDeltaEvent]
        SSE[SubagentSpawnEvent]
    end

    subgraph "EventHandler"
        EH["handleEvent()<br/>switch(event)"]
        TCI["_toolCallIndex<br/>(callId → index)"]
        ACI["_agentIdToConvId<br/>(agentId → convId)"]
    end

    subgraph "OutputEntry Models"
        TOE[TextOutputEntry]
        TUO[ToolUseOutputEntry]
        QOE[QuestionOutputEntry]
    end

    subgraph "Chat State"
        CT[Cost Tracking]
        CX[Context Tracker]
        WK[Working Flag]
    end

    TE --> EH
    TIE --> EH
    TCE --> EH
    TuCE --> EH
    PRE --> EH
    SDE --> EH
    SSE --> EH

    EH --> TOE
    EH --> TUO
    EH --> QOE
    EH --> CT
    EH --> CX
    EH --> WK
```

---

## Permission Flow (Cross-Backend)

Each backend handles permissions differently, but the frontend presents a unified dialog.

```mermaid
flowchart TB
    subgraph "Backend-Specific"
        Claude["Claude CLI<br/>• Permission suggestions<br/>• Blocked path info<br/>• Input modification<br/>• Permission modes"]
        Codex["Codex CLI<br/>• Accept/Decline/Cancel<br/>• Command actions<br/>• Grant root directory"]
        ACPb["ACP Agent<br/>• Named options<br/>• allow_once/always<br/>• reject_once/always"]
    end

    subgraph "Unified Event"
        PRE2["PermissionRequestEvent<br/>requestId, toolName,<br/>toolInput, suggestions?,<br/>blockedPath?"]
    end

    subgraph "Unified Dialog"
        PD["Permission Dialog<br/>(adapts to available data)"]
    end

    subgraph "Response"
        PRC["PermissionResponseCommand<br/>requestId, allowed,<br/>updatedInput?"]
    end

    Claude --> PRE2
    Codex --> PRE2
    ACPb --> PRE2
    PRE2 --> PD
    PD --> PRC
```

---

## Streaming Model

```mermaid
sequenceDiagram
    participant CLI as Backend
    participant Session
    participant Transport
    participant Handler as EventHandler
    participant UI

    Note over CLI,UI: Claude: Full SSE-style streaming
    CLI->>Session: content_block_start
    loop Every ~50ms
        CLI->>Session: content_block_delta (text)
        Session->>Transport: StreamDeltaEvent(kind: text)
        Transport->>Handler: throttled notification
        Handler->>UI: update OutputEntry.streamingText
    end
    CLI->>Session: content_block_stop
    Session->>Transport: TextEvent (finalized)
    Transport->>Handler: finalize entry
    Handler->>UI: replace streaming with final

    Note over CLI,UI: Codex: Complete items only
    CLI->>Session: item/completed (agentMessage)
    Session->>Transport: TextEvent (full text)
    Transport->>Handler: create entry
    Handler->>UI: display complete text
```

---

## Subagent Hierarchy

Claude supports nested subagents (via the Task tool). The protocol tracks parent-child relationships.

```mermaid
graph TB
    subgraph "Chat"
        PC["Primary Conversation"]
        SC1["Subagent Conv 1"]
        SC2["Subagent Conv 2"]
    end

    subgraph "Events"
        TI["ToolInvocationEvent<br/>(Task tool)"]
        SS["SubagentSpawnEvent<br/>parentCallId → agentId"]
        Events1["Events with<br/>agentId = sub1"]
        Events2["Events with<br/>agentId = sub2"]
        SC_done["SubagentCompleteEvent"]
        TC["ToolCompletionEvent<br/>(Task result)"]
    end

    PC --> TI
    TI --> SS
    SS --> SC1
    SS --> SC2
    SC1 --> Events1
    SC2 --> Events2
    Events1 --> SC_done
    Events2 --> SC_done
    SC_done --> TC
    TC --> PC
```

---

## Key Design Principles

1. **No lowest-common-denominator** - Each backend's full richness is preserved via the `extensions` map and nullable fields
2. **Backend-specific extensions welcome** - Claude's cost data, Codex's diffs, ACP's option-based permissions all coexist
3. **Typed, not stringly** - Dart sealed classes with exhaustive `switch` ensure the compiler catches missing event handling
4. **ACP-aligned semantics** - `ToolKind` uses ACP's vocabulary so future ACP backends map directly
5. **Transport-separable** - All events and commands are JSON-serializable for future WebSocket/Docker transports
6. **Raw data preserved** - The `raw` field contains original wire-format data for debugging

---

## Further Reading

| Document | Contents |
|----------|----------|
| [01-overview.md](01-overview.md) | Problem statement and design goals |
| [02-event-model.md](02-event-model.md) | Complete InsightsEvent type hierarchy |
| [03-claude-mapping.md](03-claude-mapping.md) | Claude CLI stream-json → InsightsEvent |
| [04-codex-mapping.md](04-codex-mapping.md) | Codex JSON-RPC → InsightsEvent |
| [05-gemini-acp-mapping.md](05-gemini-acp-mapping.md) | ACP/Gemini → InsightsEvent |
| [06-frontend-consumption.md](06-frontend-consumption.md) | EventHandler and UI patterns |
| [07-transport-separation.md](07-transport-separation.md) | Docker/WebSocket transport design |
| [08-permissions.md](08-permissions.md) | Permission model deep dive |
| [09-streaming.md](09-streaming.md) | Streaming across backends |
| [10-migration.md](10-migration.md) | Phased migration guide |
