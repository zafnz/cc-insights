import 'dart:io' show Platform;

/// Whether an author is a human user or an agent.
///
/// This will move to `models/ticket.dart` when TKT-040 merges.
enum AuthorType { user, agent }

/// Resolves and caches author identity for ticket attribution.
///
/// The current user's display name is resolved from the OS environment
/// at first access and cached for the session. Agent authors are formatted
/// as `"agent <chatname>"`.
class AuthorService {
  static String? _cachedUser;

  /// The current OS user's display name.
  ///
  /// Resolved from `USER` (macOS/Linux) or `USERNAME` (Windows).
  /// Falls back to `"user"` if unavailable.
  static String get currentUser => _cachedUser ??= _resolveUser();

  /// Formats an agent author string for the given [chatName].
  static String agentAuthor(String chatName) => 'agent $chatName';

  /// Determines whether [author] represents a user or an agent.
  static AuthorType authorTypeFor(String author) =>
      author.startsWith('agent ') ? AuthorType.agent : AuthorType.user;

  static String _resolveUser() {
    final env = Platform.environment;
    final name = env['USER'] ?? env['USERNAME'] ?? '';
    return name.isEmpty ? 'user' : name;
  }

  /// Resets the cached user name. Exposed for testing only.
  static void resetForTesting() {
    _cachedUser = null;
  }

  /// Sets a specific cached user name. Exposed for testing only.
  static void setForTesting(String name) {
    _cachedUser = name;
  }
}
