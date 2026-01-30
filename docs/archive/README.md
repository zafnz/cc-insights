# Archived Documentation

This directory contains historical documentation that no longer reflects the current architecture but is preserved for reference.

## Why These Documents Are Archived

The application has undergone significant architectural changes:

**Old Architecture (Archived):**
- Python backend with WebSocket server
- WebSocket-based communication protocol
- Docker containerized backend

**Current Architecture (See `CLAUDE.md`):**
- Node.js/TypeScript backend as subprocess
- stdin/stdout JSON-line protocol via Dart SDK
- No Docker, direct process spawning

## Archived Documents

### Architecture Documentation

- **`websocket-protocol.md`** - Old WebSocket protocol specification (replaced by stdin/stdout protocol)
- **`TECHNICAL_PLAN.md`** - Original technical plan for Python backend with WebSocket
- **`PRODUCT_REQUIREMENTS.md`** - Product requirements referencing old Python/WebSocket architecture
- **`distribution-plan.md`** - Distribution plan for TypeScript backend with Bun compilation (not implemented)

### Implementation Notes

- **`ERROR_HANDLING.md`** - Error handling improvements for old WebSocket-based system
- **`STREAMING_MODE_REFACTOR.md`** - Documentation of the transition to streaming input mode in Node backend
- **`INPUT_FOCUS_SOLUTION.md`** - Flutter input focus management solution (still relevant but kept for history)
- **`permission-approval-bug.md`** - Bug fix documentation for Dart SDK permission handling

## Current Documentation

For up-to-date information, refer to:

- **`/CLAUDE.md`** - Complete current architecture and development guide
- **`/README.md`** - Project setup and running instructions
- **`/docs/LOGGING.md`** - Current logging system documentation
- **`/docs/sdk/`** - Claude Agent SDK reference documentation
- **`/docs/dart-sdk/`** - Dart SDK implementation documentation

## Migration History

1. **Initial Implementation**: Python backend with WebSocket server
2. **TypeScript Migration**: Migrated to Node.js/TypeScript backend using `@anthropic-ai/agent-sdk`
3. **Dart SDK Layer**: Added Dart SDK wrapper for Flutter integration
4. **Protocol Change**: Replaced WebSocket with stdin/stdout JSON-line protocol for simpler subprocess communication

These archived documents provide insight into the project's evolution and past architectural decisions.
