import 'dart:developer' as developer;

import '../models/chat.dart';
import 'ask_ai_service.dart';
import 'runtime_config.dart';

/// Service for generating AI-powered chat titles.
///
/// Extracted from [EventHandler] — this is an independent feature with its own
/// state and dependency ([AskAiService]) that has no interaction with event
/// processing.
class ChatTitleService {
  final AskAiService? _askAiService;

  /// Set of chat IDs currently having their title generated.
  final Set<String> _pendingTitleGenerations = {};

  /// Set of chat IDs that have already had title generation attempted.
  final Set<String> _titlesGenerated = {};

  ChatTitleService({AskAiService? askAiService}) : _askAiService = askAiService;

  /// Generates an AI-powered title for a chat based on the user's message.
  ///
  /// Call this when creating a new chat and sending the first message.
  /// The title generation is fire-and-forget - failures are logged but don't
  /// affect the user experience.
  ///
  /// The method is idempotent - it tracks which chats have had title generation
  /// attempted and won't generate twice for the same chat.
  void generateChatTitle(Chat chat, String userMessage) {
    _generateChatTitleAsync(chat, userMessage);
  }

  Future<void> _generateChatTitleAsync(Chat chat, String userMessage) async {
    if (_askAiService == null) return;

    final config = RuntimeConfig.instance;
    if (!config.aiChatLabelsEnabled) return;

    if (_titlesGenerated.contains(chat.data.id)) return;
    if (_pendingTitleGenerations.contains(chat.data.id)) return;
    if (userMessage.isEmpty) return;

    final workingDirectory = chat.data.worktreeRoot;
    if (workingDirectory == null) return;

    // Mark as generated (even before we start, to prevent duplicate attempts)
    _titlesGenerated.add(chat.data.id);
    _pendingTitleGenerations.add(chat.data.id);

    try {
      final prompt =
          '''Read the following and produce a short 3-5 word statement succiciently summing up what the request is. It should be concise, do not worry about grammer.
Your reply should be between ==== marks. eg:
=====
Automatic Chat Summary
=====

User's message:
$userMessage''';

      final result = await _askAiService.ask(
        prompt: prompt,
        workingDirectory: workingDirectory,
        model: config.aiChatLabelModel,
        allowedTools: [],
        maxTurns: 1,
        timeoutSeconds: 30,
      );

      if (result != null && !result.isError && result.result.isNotEmpty) {
        final rawResult = result.result;
        final titleMatch = RegExp(
          r'=+\s*\n(.+?)\n\s*=+',
          dotAll: true,
        ).firstMatch(rawResult);

        String title;
        if (titleMatch != null) {
          title = titleMatch.group(1)?.trim() ?? rawResult.trim();
        } else {
          title = rawResult.trim();
        }

        title = title
            .replaceAll(RegExp(r'^=+'), '')
            .replaceAll(RegExp(r'=+$'), '')
            .trim();
        if (title.length > 50) {
          title = '${title.substring(0, 47)}...';
        }

        if (title.isNotEmpty) {
          chat.conversations.rename(title);
        }
      }
    } catch (e) {
      developer.log(
        'Failed to generate chat title: $e',
        name: 'ChatTitleService',
        level: 900,
      );
    } finally {
      _pendingTitleGenerations.remove(chat.data.id);
    }
  }

  /// Removes tracking state for a specific chat.
  void clearChat(String chatId) {
    _pendingTitleGenerations.remove(chatId);
    _titlesGenerated.remove(chatId);
  }

  /// Clears all internal state.
  void clear() {
    _pendingTitleGenerations.clear();
    _titlesGenerated.clear();
  }
}
