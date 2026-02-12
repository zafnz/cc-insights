**ACP Backend Overview**

This folder defines the concrete plan and design decisions for adding ACP as a third backend alongside Claude and Codex. ACP is JSON-RPC 2.0 over stdio and provides a general integration path for Gemini and other ACP agents.

**Decisions**
- Tool naming: use ACP `title` as the tool name when present, otherwise fall back to `kind`.
- Eventing: add new InsightsEvent types for ACP config and command updates. Do not keep ACP UI state inside the session.
- Safety: enforce repo-root and allowlisted directories for ACP filesystem and terminal requests. For out-of-scope paths, request permission and default to deny.
- UI: surface ACP config options on the conversation toolbar, prioritizing `category: model` and `category: mode`.

**Scope**
- Add an `acp_dart_sdk` package with ACP process, session, and backend implementations.
- Implement ACP client-side methods for filesystem and terminal access.
- Map ACP events to InsightsEvents with parity to Claude/Codex behaviors.
- Update UI to expose ACP session config options and display ACP permission options.

**Deliverables**
- ACP backend implementation and session lifecycle.
- New InsightsEvent types for ACP updates.
- UI toolbar integration for ACP config options.
- ACP security and permission handling.
- Updated mapping doc in `docs/insights-protocol/05-gemini-acp-mapping.md`.
