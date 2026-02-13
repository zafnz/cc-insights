import 'package:agent_sdk_core/agent_sdk_core.dart';
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

  group('parseBackendType', () {
    test('parses "direct" to BackendType.directCli', () {
      expect(parseBackendType('direct'), equals(BackendType.directCli));
    });

    test('parses "directcli" to BackendType.directCli', () {
      expect(parseBackendType('directcli'), equals(BackendType.directCli));
    });

    test('parses "cli" to BackendType.directCli', () {
      expect(parseBackendType('cli'), equals(BackendType.directCli));
    });

    test('parses "claude" to BackendType.directCli', () {
      expect(parseBackendType('claude'), equals(BackendType.directCli));
    });

    test('parses "codex" to BackendType.codex', () {
      expect(parseBackendType('codex'), equals(BackendType.codex));
    });

    test('parses "acp" to BackendType.acp', () {
      expect(parseBackendType('acp'), equals(BackendType.acp));
    });

    test('is case insensitive', () {
      expect(parseBackendType('DIRECT'), equals(BackendType.directCli));
      expect(parseBackendType('CLI'), equals(BackendType.directCli));
      expect(parseBackendType('CODEX'), equals(BackendType.codex));
      expect(parseBackendType('ACP'), equals(BackendType.acp));
    });

    test('returns null for unrecognized values', () {
      expect(parseBackendType('unknown'), isNull);
      expect(parseBackendType('invalid'), isNull);
      expect(parseBackendType('python'), isNull);
    });

    test('returns null for empty string', () {
      expect(parseBackendType(''), isNull);
    });

    test('returns null for null', () {
      expect(parseBackendType(null), isNull);
    });

    test('returns null for legacy values', () {
      expect(parseBackendType('nodejs'), isNull);
      expect(parseBackendType('node'), isNull);
    });
  });

  group('BackendRegistry', () {
    setUp(() {
      BackendRegistry.resetForTesting();
    });

    tearDown(() {
      BackendRegistry.resetForTesting();
    });

    test('starts with no registered types', () {
      expect(BackendRegistry.registeredTypes, isEmpty);
    });

    test('register makes type available', () {
      BackendRegistry.register(
        BackendType.directCli,
        ({String? executablePath, List<String> arguments = const [], String? workingDirectory}) async {
          throw UnimplementedError();
        },
      );
      expect(BackendRegistry.isRegistered(BackendType.directCli), isTrue);
      expect(BackendRegistry.isRegistered(BackendType.codex), isFalse);
      expect(BackendRegistry.registeredTypes, [BackendType.directCli]);
    });

    test('create throws if type not registered', () {
      expect(
        () => BackendRegistry.create(type: BackendType.codex),
        throwsA(isA<StateError>()),
      );
    });

    test('resetForTesting clears all registrations', () {
      BackendRegistry.register(
        BackendType.directCli,
        ({String? executablePath, List<String> arguments = const [], String? workingDirectory}) async {
          throw UnimplementedError();
        },
      );
      expect(BackendRegistry.isRegistered(BackendType.directCli), isTrue);

      BackendRegistry.resetForTesting();

      expect(BackendRegistry.isRegistered(BackendType.directCli), isFalse);
      expect(BackendRegistry.registeredTypes, isEmpty);
    });

    test('envVarName is CLAUDE_BACKEND', () {
      expect(BackendRegistry.envVarName, equals('CLAUDE_BACKEND'));
    });

    test('getEnvOverride returns current value without throwing', () {
      final value = BackendRegistry.getEnvOverride();
      expect(value, anyOf(isNull, isA<String>()));
    });
  });
}
