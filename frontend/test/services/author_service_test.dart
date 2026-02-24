import 'package:flutter_test/flutter_test.dart';
import 'package:cc_insights_v2/services/author_service.dart';

void main() {
  group('AuthorService', () {
    tearDown(() {
      AuthorService.resetForTesting();
    });

    group('currentUser', () {
      test('returns a non-empty string from the OS environment', () {
        // Platform.environment is hard to mock, but on any real OS
        // either USER or USERNAME should be set.
        final user = AuthorService.currentUser;
        expect(user, isNotEmpty);
      });

      test('caches the resolved value', () {
        final first = AuthorService.currentUser;
        final second = AuthorService.currentUser;
        expect(identical(first, second), isTrue);
      });

      test('setForTesting overrides the cached value', () {
        AuthorService.setForTesting('testuser');
        expect(AuthorService.currentUser, 'testuser');
      });

      test('resetForTesting clears the cache', () {
        AuthorService.setForTesting('override');
        expect(AuthorService.currentUser, 'override');

        AuthorService.resetForTesting();
        // After reset, it re-resolves from the environment.
        final user = AuthorService.currentUser;
        expect(user, isNotEmpty);
        expect(user, isNot('override'));
      });
    });

    group('agentAuthor', () {
      test('formats with "agent " prefix', () {
        expect(AuthorService.agentAuthor('my-chat'), 'agent my-chat');
      });

      test('handles empty chat name', () {
        expect(AuthorService.agentAuthor(''), 'agent ');
      });

      test('preserves special characters in chat name', () {
        expect(
          AuthorService.agentAuthor('feat/dark-mode'),
          'agent feat/dark-mode',
        );
      });
    });

    group('authorTypeFor', () {
      test('returns agent for strings starting with "agent "', () {
        expect(
          AuthorService.authorTypeFor('agent my-chat'),
          AuthorType.agent,
        );
      });

      test('returns user for plain usernames', () {
        expect(AuthorService.authorTypeFor('zaf'), AuthorType.user);
      });

      test('returns user for "user" fallback', () {
        expect(AuthorService.authorTypeFor('user'), AuthorType.user);
      });

      test('returns user for "agent" without trailing space', () {
        // "agent" alone (no space) is not an agent author format.
        expect(AuthorService.authorTypeFor('agent'), AuthorType.user);
      });

      test('returns agent for "agent " with empty chat name', () {
        expect(AuthorService.authorTypeFor('agent '), AuthorType.agent);
      });

      test('returns user for empty string', () {
        expect(AuthorService.authorTypeFor(''), AuthorType.user);
      });
    });
  });
}
