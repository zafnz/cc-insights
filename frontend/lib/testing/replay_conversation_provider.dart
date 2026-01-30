import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/conversation.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import 'message_log_player.dart';

/// A conversation provider that replays messages from a log file.
///
/// Use this to test UI rendering with real message data without
/// requiring an actual backend connection.
class ReplayConversationProvider extends ChangeNotifier {
  final MessageLogPlayer _player;
  final ChatState _chat;

  bool _isPlaying = false;
  bool _isLoaded = false;
  int _currentIndex = 0;
  List<OutputEntry> _entries = [];
  double _speedMultiplier = 1.0;

  ReplayConversationProvider({
    required String logFilePath,
    ChatState? chat,
  })  : _player = MessageLogPlayer(logFilePath),
        _chat = chat ?? _createDefaultChat();

  /// Whether the log file has been loaded.
  bool get isLoaded => _isLoaded;

  /// Whether messages are currently being replayed.
  bool get isPlaying => _isPlaying;

  /// Current playback position.
  int get currentIndex => _currentIndex;

  /// Total number of entries to replay.
  int get totalEntries => _entries.length;

  /// Playback speed multiplier.
  double get speedMultiplier => _speedMultiplier;
  set speedMultiplier(double value) {
    _speedMultiplier = value;
    notifyListeners();
  }

  /// The chat being populated with replayed messages.
  ChatState get chat => _chat;

  /// Statistics about the loaded log file.
  Map<String, dynamic> get stats => _player.stats;

  /// Load the log file.
  Future<void> load() async {
    await _player.load();
    _entries = _player.toOutputEntries();
    _isLoaded = true;
    notifyListeners();
  }

  /// Start replaying messages with timing.
  Future<void> play() async {
    if (!_isLoaded || _isPlaying) return;
    if (_currentIndex >= _entries.length) {
      _currentIndex = 0;
      _chat.clearEntries();
    }

    _isPlaying = true;
    notifyListeners();

    try {
      await for (final entry in _replayFrom(_currentIndex)) {
        if (!_isPlaying) break;
        _chat.addEntry(entry);
        _currentIndex++;
        notifyListeners();
      }
    } finally {
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Pause playback.
  void pause() {
    _isPlaying = false;
    notifyListeners();
  }

  /// Stop playback and reset to beginning.
  void stop() {
    _isPlaying = false;
    _currentIndex = 0;
    _chat.clearEntries();
    notifyListeners();
  }

  /// Add all remaining entries instantly.
  void playAllInstantly() {
    if (!_isLoaded) return;
    _isPlaying = false;

    while (_currentIndex < _entries.length) {
      _chat.addEntry(_entries[_currentIndex]);
      _currentIndex++;
    }
    notifyListeners();
  }

  /// Step forward one entry.
  void stepForward() {
    if (!_isLoaded || _currentIndex >= _entries.length) return;
    _chat.addEntry(_entries[_currentIndex]);
    _currentIndex++;
    notifyListeners();
  }

  /// Replay from a specific index with timing.
  Stream<OutputEntry> _replayFrom(int startIndex) async* {
    if (startIndex >= _entries.length) return;

    DateTime? lastTimestamp;
    for (var i = startIndex; i < _entries.length; i++) {
      final entry = _entries[i];
      if (lastTimestamp != null) {
        final delay = entry.timestamp.difference(lastTimestamp);
        final adjustedDelay = Duration(
          microseconds: (delay.inMicroseconds / _speedMultiplier).round(),
        );
        // Cap the delay at 2 seconds for practical testing
        final cappedDelay = adjustedDelay.inSeconds > 2
            ? const Duration(seconds: 2)
            : adjustedDelay;
        if (cappedDelay.inMilliseconds > 0) {
          await Future.delayed(cappedDelay);
        }
      }
      yield entry;
      lastTimestamp = entry.timestamp;
    }
  }

  static ChatState _createDefaultChat() {
    // Create a minimal project/worktree/chat structure for testing
    return ChatState(
      const ChatData(
        id: 'replay-chat',
        name: 'Replay Session',
        createdAt: null,
        primaryConversation: ConversationData.primary(
          id: 'replay-conversation',
        ),
      ),
    );
  }
}

/// Creates a mock project with a replay chat for testing.
ProjectState createReplayProject() {
  final worktree = WorktreeState(
    const WorktreeData(
      worktreeRoot: '/tmp/replay-test',
      isPrimary: true,
      branch: 'main',
    ),
  );

  final chat = ChatState(
    const ChatData(
      id: 'replay-chat',
      name: 'Replay Session',
      createdAt: null,
      primaryConversation: ConversationData.primary(
        id: 'replay-conversation',
      ),
    ),
  );

  worktree.addChat(chat, select: true);

  return ProjectState(
    const ProjectData(
      name: 'Replay Test',
      repoRoot: '/tmp/replay-test',
    ),
    worktree,
  );
}
