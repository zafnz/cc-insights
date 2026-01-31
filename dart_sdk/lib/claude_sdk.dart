/// Dart SDK for Claude Code Agent.
///
/// This library provides a native Dart/Flutter interface to the Claude Agent SDK
/// via a thin Node.js backend that communicates over stdin/stdout JSON lines.
library claude_sdk;

// Core classes
export 'src/core.dart' show ClaudeBackend, ClaudeSession;

// Single request (one-shot CLI)
export 'src/single_request.dart';

// Types
export 'src/types/sdk_messages.dart';
export 'src/types/content_blocks.dart';
export 'src/types/session_options.dart';
export 'src/types/callbacks.dart';
export 'src/types/permission_suggestion.dart';
export 'src/types/usage.dart';
export 'src/types/errors.dart';
