import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('BackendType enum', () {
    test('has nodejs value', () {
      expect(BackendType.nodejs, isA<BackendType>());
      expect(BackendType.nodejs.name, equals('nodejs'));
    });

    test('has directCli value', () {
      expect(BackendType.directCli, isA<BackendType>());
      expect(BackendType.directCli.name, equals('directCli'));
    });

    test('has exactly two values', () {
      expect(BackendType.values, hasLength(2));
      expect(BackendType.values, contains(BackendType.nodejs));
      expect(BackendType.values, contains(BackendType.directCli));
    });

    test('values have distinct indices', () {
      expect(BackendType.nodejs.index, isNot(BackendType.directCli.index));
    });
  });

  group('BackendFactory.parseType', () {
    test('parses "nodejs" to BackendType.nodejs', () {
      expect(BackendFactory.parseType('nodejs'), equals(BackendType.nodejs));
    });

    test('parses "node" to BackendType.nodejs', () {
      expect(BackendFactory.parseType('node'), equals(BackendType.nodejs));
    });

    test('parses "direct" to BackendType.directCli', () {
      expect(BackendFactory.parseType('direct'), equals(BackendType.directCli));
    });

    test('parses "directcli" to BackendType.directCli', () {
      expect(
        BackendFactory.parseType('directcli'),
        equals(BackendType.directCli),
      );
    });

    test('parses "cli" to BackendType.directCli', () {
      expect(BackendFactory.parseType('cli'), equals(BackendType.directCli));
    });

    test('is case insensitive', () {
      expect(BackendFactory.parseType('NODEJS'), equals(BackendType.nodejs));
      expect(BackendFactory.parseType('NodeJs'), equals(BackendType.nodejs));
      expect(BackendFactory.parseType('DIRECT'), equals(BackendType.directCli));
      expect(BackendFactory.parseType('CLI'), equals(BackendType.directCli));
    });

    test('returns null for unrecognized values', () {
      expect(BackendFactory.parseType('unknown'), isNull);
      expect(BackendFactory.parseType('invalid'), isNull);
      expect(BackendFactory.parseType('python'), isNull);
    });

    test('returns null for empty string', () {
      expect(BackendFactory.parseType(''), isNull);
    });

    test('returns null for null', () {
      expect(BackendFactory.parseType(null), isNull);
    });
  });

  group('BackendFactory.envVarName', () {
    test('is CLAUDE_BACKEND', () {
      expect(BackendFactory.envVarName, equals('CLAUDE_BACKEND'));
    });
  });

  group('BackendFactory.getEnvOverride', () {
    test('returns current environment variable value', () {
      // This test just verifies the method doesn't throw
      // The actual value depends on the test environment
      final value = BackendFactory.getEnvOverride();
      expect(value, anyOf(isNull, isA<String>()));
    });
  });

  group('BackendFactory.create', () {
    group('with directCli type', () {
      test('creates ClaudeCliBackend by default', () async {
        final backend = await BackendFactory.create();

        expect(backend, isA<ClaudeCliBackend>());
        expect(backend, isA<AgentBackend>());
        expect(backend.isRunning, isTrue);

        await backend.dispose();
      });

      test('creates ClaudeCliBackend when type is directCli', () async {
        final backend = await BackendFactory.create(
          type: BackendType.directCli,
        );

        expect(backend, isA<ClaudeCliBackend>());

        await backend.dispose();
      });

      test('passes executablePath to ClaudeCliBackend', () async {
        final backend = await BackendFactory.create(
          type: BackendType.directCli,
          executablePath: '/custom/path/to/claude',
        );

        expect(backend, isA<ClaudeCliBackend>());
        expect(backend.isRunning, isTrue);

        await backend.dispose();
      });

      test('creates backend that implements AgentBackend interface', () async {
        final backend = await BackendFactory.create();

        // Verify all AgentBackend interface members are accessible
        expect(backend.isRunning, isA<bool>());
        expect(backend.errors, isA<Stream<BackendError>>());
        expect(backend.logs, isA<Stream<String>>());
        expect(backend.sessions, isA<List<AgentSession>>());

        await backend.dispose();
      });
    });

    group('with nodejs type', () {
      test('throws ArgumentError when nodeBackendPath is null', () async {
        expect(
          () => BackendFactory.create(type: BackendType.nodejs),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws ArgumentError with descriptive message', () async {
        try {
          await BackendFactory.create(type: BackendType.nodejs);
          fail('Expected ArgumentError');
        } catch (e) {
          expect(e, isA<ArgumentError>());
          expect(
            (e as ArgumentError).message,
            contains('nodeBackendPath is required'),
          );
        }
      });

      // Note: We can't easily test successful Node.js backend creation
      // without a real Node.js backend path, so we focus on error cases
    });

    group('default type', () {
      test('defaults to BackendType.directCli', () async {
        // When no type is specified, should create directCli backend
        final backend = await BackendFactory.create();

        expect(backend, isA<ClaudeCliBackend>());

        await backend.dispose();
      });
    });
  });

  group('BackendFactory backend lifecycle', () {
    test('created backend can be disposed', () async {
      final backend = await BackendFactory.create();
      expect(backend.isRunning, isTrue);

      await backend.dispose();

      expect(backend.isRunning, isFalse);
    });

    test('dispose is idempotent', () async {
      final backend = await BackendFactory.create();

      await backend.dispose();
      await backend.dispose();
      await backend.dispose();

      expect(backend.isRunning, isFalse);
    });

    test('created backend has empty sessions list', () async {
      final backend = await BackendFactory.create();

      expect(backend.sessions, isEmpty);

      await backend.dispose();
    });

    test('created backend streams are accessible', () async {
      final backend = await BackendFactory.create();

      // Should be able to listen to streams without error
      final errorsSub = backend.errors.listen((_) {});
      final logsSub = backend.logs.listen((_) {});

      await errorsSub.cancel();
      await logsSub.cancel();
      await backend.dispose();
    });
  });

  group('BackendFactory type selection', () {
    test('creates directCli when explicit type is directCli', () async {
      final backend = await BackendFactory.create(
        type: BackendType.directCli,
      );

      expect(backend, isA<ClaudeCliBackend>());

      await backend.dispose();
    });

    test('multiple backends can be created', () async {
      final backend1 = await BackendFactory.create();
      final backend2 = await BackendFactory.create();

      expect(backend1, isNot(same(backend2)));
      expect(backend1.isRunning, isTrue);
      expect(backend2.isRunning, isTrue);

      await backend1.dispose();
      await backend2.dispose();
    });
  });

  group('BackendFactory with polymorphic usage', () {
    test('returned backend can be used as AgentBackend', () async {
      // Explicitly type as AgentBackend to verify polymorphic usage
      AgentBackend backend = await BackendFactory.create();

      expect(backend.isRunning, isTrue);
      expect(backend.sessions, isEmpty);

      await backend.dispose();
      expect(backend.isRunning, isFalse);
    });

    test('factory return type is AgentBackend', () async {
      // Verify the return type is the abstract interface
      final Future<AgentBackend> futureBackend = BackendFactory.create();
      final backend = await futureBackend;

      expect(backend, isA<AgentBackend>());

      await backend.dispose();
    });
  });
}
