# Archived Documentation

This directory contains historical documentation that no longer reflects the current architecture but is preserved for reference.

## Why These Documents Are Archived

The application has undergone significant architectural changes:

**Old Architectures (Archived):**
1. Python backend with WebSocket server
2. Node.js/TypeScript backend with Dart SDK wrapper
3. Direct claude-cli protocol approach

**Current Architecture (See `CLAUDE.md`):**
- ACP (Agent Client Protocol) for agent communication
- `acp_dart` package for protocol handling
- `claude-code-acp` adapter for Claude Code integration
- Multi-agent support (Claude Code, Gemini CLI, Codex CLI)

## Archived Documents

### dart-sdk/ - Removed Dart SDK Documentation

These documents describe the removed `dart_sdk/` and `backend-node/` architecture:

- **`00-overview.md`** - Original Dart SDK architecture overview
- **`01-implementation-plan.md`** - Implementation plan for Node.js backend + Dart SDK
- **`02-protocol.md`** - JSON protocol between Dart and Node.js
- **`03-dart-sdk-api.md`** - Dart SDK public API (now replaced by acp_dart)
- **`04-node-backend.md`** - Node.js backend implementation details
- **`05-flutter-integration.md`** - Flutter app integration with old SDK
- **`06-sdk-message-types.md`** - Old SDK message type reference
- **`07-quick-reference.md`** - Quick reference for old SDK

### legacy-architecture/ - Superseded Architecture Documents

- **`sdk-message-handling.md`** - Old SDK message types (SDKSystemMessage, SDKAssistantMessage, etc.)
- **`direct-claude-cli-protocol.md`** - Direct claude-cli protocol approach (superseded by ACP)
- **`protocol-comparison.md`** - Comparison of Dart↔Node.js↔TS SDK layers (all removed)
- **`sdk-wiring-plan.md`** - Plan for BackendService/ClaudeSession wiring (replaced by AgentService)
- **`cc-insights-v2-implementation-plan.md`** - V2 implementation plan (completed, historical)
- **`mock-backend-plan.md`** - Mock backend plan for Node.js pattern
- **`real-mock-backend-plan.md`** - Real mock backend implementation
- **`websocket-architecture.md`** - WebSocket approach (replaced by subprocess/ACP)

### Root Archive - Original Architecture

- **`websocket-protocol.md`** - Old WebSocket protocol specification
- **`TECHNICAL_PLAN.md`** - Original technical plan for Python backend
- **`PRODUCT_REQUIREMENTS.md`** - Product requirements referencing old architecture
- **`distribution-plan.md`** - Distribution plan for TypeScript backend with Bun
- **`ERROR_HANDLING.md`** - Error handling for old WebSocket system
- **`STREAMING_MODE_REFACTOR.md`** - Streaming mode transition in Node backend
- **`INPUT_FOCUS_SOLUTION.md`** - Flutter input focus management solution
- **`permission-approval-bug.md`** - Bug fix for Dart SDK permission handling

## Current Documentation

For up-to-date information, refer to:

- **`/CLAUDE.md`** - Complete current architecture and development guide (includes ACP documentation)
- **`/README.md`** - Project setup and running instructions
- **`/docs/architecture/acp-implementation-plan.md`** - ACP integration plan (completed)
- **`/docs/architecture/acp.md`** - ACP protocol reference
- **`/docs/sdk/`** - Claude Agent SDK reference documentation

## Migration History

1. **Initial Implementation**: Python backend with WebSocket server
2. **TypeScript Migration**: Migrated to Node.js/TypeScript backend using `@anthropic-ai/agent-sdk`
3. **Dart SDK Layer**: Added Dart SDK wrapper for Flutter integration
4. **Protocol Change**: Replaced WebSocket with stdin/stdout JSON-line protocol
5. **ACP Integration** (Current): Replaced custom Node.js backend with ACP protocol
   - Removed `backend-node/` directory
   - Removed `dart_sdk/` directory
   - Added `acp_dart` package for protocol handling
   - Added `claude-code-acp` adapter in `packages/`
   - Multi-agent support via `AgentRegistry` and `AgentService`

These archived documents provide insight into the project's evolution and past architectural decisions.
