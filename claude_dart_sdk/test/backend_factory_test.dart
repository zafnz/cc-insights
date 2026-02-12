
import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('BackendType enum', () {
    test('has directCli value', () {
      expect(BackendType.directCli, isA<BackendType>());
      expect(BackendType.directCli.name, equals('directCli'));
    });

    test('has codex value', () {
      expect(BackendType.codex, isA<BackendType>());
      expect(BackendType.codex.name, equals('codex'));
    });

    test('has acp value', () {
      expect(BackendType.acp, isA<BackendType>());
      expect(BackendType.acp.name, equals('acp'));
    });

    test('has exactly three values', () {
      expect(BackendType.values, hasLength(3));
      expect(BackendType.values, contains(BackendType.directCli));
      expect(BackendType.values, contains(BackendType.codex));
      expect(BackendType.values, contains(BackendType.acp));
    });

    test('values have distinct indices', () {
      expect(BackendType.directCli.index, isNot(BackendType.codex.index));
      expect(BackendType.directCli.index, isNot(BackendType.acp.index));
      expect(BackendType.codex.index, isNot(BackendType.acp.index));
    });
  });

  group('BackendFactory.parseType', () {
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

    test('parses "codex" to BackendType.codex', () {
      expect(BackendFactory.parseType('codex'), equals(BackendType.codex));
    });

    test('parses "acp" to BackendType.acp', () {
      expect(BackendFactory.parseType('acp'), equals(BackendType.acp));
    });

    test('returns null for legacy "nodejs" and "node" values', () {
      expect(BackendFactory.parseType('nodejs'), isNull);
      expect(BackendFactory.parseType('node'), isNull);
    });

    test('is case insensitive', () {
      expect(BackendFactory.parseType('DIRECT'), equals(BackendType.directCli));
      expect(BackendFactory.parseType('CLI'), equals(BackendType.directCli));
      expect(BackendFactory.parseType('CODEX'), equals(BackendType.codex));
      expect(BackendFactory.parseType('ACP'), equals(BackendType.acp));
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
