import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_sdk_core/agent_sdk_core.dart' show ToolKind;

import '../models/output_entry.dart';

/// A log entry from the SDK message log file.
class LogEntry {
  final DateTime timestamp;
  final String direction; // 'IN' or 'OUT'
  final Map<String, dynamic> message;

  LogEntry({
    required this.timestamp,
    required this.direction,
    required this.message,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      direction: json['direction'] as String,
      message: json['message'] as Map<String, dynamic>,
    );
  }

  /// Get the message type (e.g., 'sdk.message', 'session.created')
  String get messageType => message['type'] as String? ?? 'unknown';

  /// Get the payload type for sdk.message entries
  String? get payloadType {
    final payload = message['payload'] as Map<String, dynamic>?;
    return payload?['type'] as String?;
  }

  /// Get the full payload
  Map<String, dynamic>? get payload =>
      message['payload'] as Map<String, dynamic>?;
}

/// Transforms SDK log messages into OutputEntry objects for UI display.
class MessageTransformer {
  /// Map of pending tool use entries by tool_use_id, waiting for results.
  final Map<String, ToolUseOutputEntry> _pendingToolUses = {};

  /// Transform a log entry into a list of output entries.
  ///
  /// A single SDK message may produce multiple output entries (e.g., an
  /// assistant message with both text and tool_use content blocks).
  ///
  /// Tool use/result pairing: When a tool_use is encountered, it's stored
  /// in [_pendingToolUses]. When the corresponding tool_result arrives, the
  /// pending entry is updated with the result.
  List<OutputEntry> transform(LogEntry entry) {
    if (entry.messageType != 'sdk.message') {
      return [];
    }

    final payloadType = entry.payloadType;
    final payload = entry.payload;
    if (payload == null) return [];

    return switch (payloadType) {
      'assistant' => _transformAssistantMessage(entry.timestamp, payload),
      'user' => _transformUserMessage(entry.timestamp, payload),
      'result' => _transformResultMessage(entry.timestamp, payload),
      _ => [],
    };
  }

  List<OutputEntry> _transformAssistantMessage(
    DateTime timestamp,
    Map<String, dynamic> payload,
  ) {
    final entries = <OutputEntry>[];
    final message = payload['message'] as Map<String, dynamic>?;
    if (message == null) return entries;

    final content = message['content'] as List<dynamic>?;
    if (content == null) return entries;

    for (final block in content) {
      final blockMap = block as Map<String, dynamic>;
      final blockType = blockMap['type'] as String?;

      switch (blockType) {
        case 'text':
          final text = blockMap['text'] as String? ?? '';
          if (text.isNotEmpty) {
            entries.add(TextOutputEntry(
              timestamp: timestamp,
              text: text,
              contentType: 'text',
            ));
          }

        case 'thinking':
          final thinking = blockMap['thinking'] as String? ?? '';
          if (thinking.isNotEmpty) {
            entries.add(TextOutputEntry(
              timestamp: timestamp,
              text: thinking,
              contentType: 'thinking',
            ));
          }

        case 'tool_use':
          final name = blockMap['name'] as String? ?? 'unknown';
          final toolUseEntry = ToolUseOutputEntry(
            timestamp: timestamp,
            toolName: name,
            toolKind: ToolKind.fromToolName(name),
            toolUseId: blockMap['id'] as String? ?? '',
            toolInput: blockMap['input'] as Map<String, dynamic>? ?? {},
            model: message['model'] as String?,
          );
          // Store in pending map for later pairing with tool_result
          final toolUseId = blockMap['id'] as String? ?? '';
          if (toolUseId.isNotEmpty) {
            _pendingToolUses[toolUseId] = toolUseEntry;
          }
          entries.add(toolUseEntry);
      }
    }

    return entries;
  }

  List<OutputEntry> _transformUserMessage(
    DateTime timestamp,
    Map<String, dynamic> payload,
  ) {
    final entries = <OutputEntry>[];
    final message = payload['message'] as Map<String, dynamic>?;
    if (message == null) return entries;

    // Get the content - could be a list or other structure
    final rawContent = message['content'];
    if (rawContent == null) return entries;

    // Handle different content formats
    final List<dynamic> content;
    if (rawContent is List) {
      content = rawContent;
    } else if (rawContent is String) {
      // Simple string content
      if (rawContent.isNotEmpty) {
        entries.add(UserInputEntry(timestamp: timestamp, text: rawContent));
      }
      return entries;
    } else {
      return entries;
    }

    for (final block in content) {
      if (block is String) {
        entries.add(UserInputEntry(timestamp: timestamp, text: block));
      } else if (block is Map<String, dynamic>) {
        final blockType = block['type'] as String?;
        switch (blockType) {
          case 'text':
            final text = block['text'] as String? ?? '';
            if (text.isNotEmpty) {
              entries.add(UserInputEntry(timestamp: timestamp, text: text));
            }
          case 'tool_result':
            // Pair tool_result with its corresponding tool_use entry
            final toolUseId = block['tool_use_id'] as String? ?? '';
            final pendingEntry = _pendingToolUses.remove(toolUseId);
            if (pendingEntry != null) {
              // Extract result content
              // Prefer tool_use_result from payload (has structuredPatch, etc.)
              // Fall back to content string if not available
              final toolUseResultRaw = payload['tool_use_result'];
              final toolUseResult = toolUseResultRaw is Map<String, dynamic>
                  ? toolUseResultRaw
                  : null;
              final resultContent = toolUseResult ?? block['content'];
              final isError = block['is_error'] as bool? ?? false;
              pendingEntry.updateResult(resultContent, isError);
            }
            break;
        }
      }
    }

    return entries;
  }

  List<OutputEntry> _transformResultMessage(
    DateTime timestamp,
    Map<String, dynamic> payload,
  ) {
    // Result messages contain usage info but no displayable content
    // Could be used to update conversation statistics
    return [];
  }
}

/// Plays back messages from a JSONL log file.
///
/// Can be used to test UI rendering with real message data.
class MessageLogPlayer {
  final String filePath;
  final MessageTransformer _transformer = MessageTransformer();

  List<LogEntry>? _entries;

  MessageLogPlayer(this.filePath);

  /// Load and parse the log file.
  Future<void> load() async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Log file not found', filePath);
    }

    final lines = await file.readAsLines();
    _entries = lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            return LogEntry.fromJson(json);
          } catch (e) {
            // Skip malformed lines
            return null;
          }
        })
        .whereType<LogEntry>()
        .toList();
  }

  /// Get all log entries (requires [load] first).
  List<LogEntry> get entries => _entries ?? [];

  /// Get only outgoing messages (SDK -> Backend would be IN, Backend -> SDK is OUT)
  /// Actually in this log format, OUT means messages going out to the UI
  List<LogEntry> get outgoingEntries =>
      entries.where((e) => e.direction == 'OUT').toList();

  /// Transform all log entries into output entries.
  List<OutputEntry> toOutputEntries() {
    return entries.expand((e) => _transformer.transform(e)).toList();
  }

  /// Replay messages with timing delays.
  ///
  /// [onEntry] is called for each output entry.
  /// [speedMultiplier] controls playback speed (2.0 = 2x faster).
  Stream<OutputEntry> replayWithTiming({double speedMultiplier = 1.0}) async* {
    final outputEntries = toOutputEntries();
    if (outputEntries.isEmpty) return;

    DateTime? lastTimestamp;
    for (final entry in outputEntries) {
      if (lastTimestamp != null) {
        final delay = entry.timestamp.difference(lastTimestamp);
        final adjustedDelay = Duration(
          microseconds: (delay.inMicroseconds / speedMultiplier).round(),
        );
        if (adjustedDelay.inMilliseconds > 0) {
          await Future.delayed(adjustedDelay);
        }
      }
      yield entry;
      lastTimestamp = entry.timestamp;
    }
  }

  /// Get statistics about the log file.
  Map<String, dynamic> get stats {
    if (_entries == null) {
      return {'loaded': false};
    }

    final messageTypes = <String, int>{};
    final payloadTypes = <String, int>{};

    for (final entry in _entries!) {
      final type = entry.messageType;
      messageTypes[type] = (messageTypes[type] ?? 0) + 1;

      final pType = entry.payloadType;
      if (pType != null) {
        payloadTypes[pType] = (payloadTypes[pType] ?? 0) + 1;
      }
    }

    final outputEntries = toOutputEntries();
    final entryTypes = <String, int>{};
    for (final entry in outputEntries) {
      final type = entry.runtimeType.toString();
      entryTypes[type] = (entryTypes[type] ?? 0) + 1;
    }

    return {
      'loaded': true,
      'totalLines': _entries!.length,
      'messageTypes': messageTypes,
      'payloadTypes': payloadTypes,
      'outputEntries': outputEntries.length,
      'outputEntryTypes': entryTypes,
    };
  }
}
