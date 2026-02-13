import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    BackendRegistry.resetForTesting();
  });

  tearDown(() {
    BackendRegistry.resetForTesting();
  });

  group('ClaudeCliBackend.register', () {
    test('registers directCli in BackendRegistry', () {
      expect(BackendRegistry.isRegistered(BackendType.directCli), isFalse);

      ClaudeCliBackend.register();

      expect(BackendRegistry.isRegistered(BackendType.directCli), isTrue);
    });
  });

  group('BackendRegistry.create with ClaudeCliBackend', () {
    setUp(() {
      ClaudeCliBackend.register();
    });

    test('creates ClaudeCliBackend for directCli', () async {
      final backend = await BackendRegistry.create(
        type: BackendType.directCli,
      );

      expect(backend, isA<ClaudeCliBackend>());
      expect(backend, isA<AgentBackend>());
      expect(backend.isRunning, isTrue);

      await backend.dispose();
    });

    test('passes executablePath through', () async {
      final backend = await BackendRegistry.create(
        type: BackendType.directCli,
        executablePath: '/custom/path/to/claude',
      );

      expect(backend, isA<ClaudeCliBackend>());
      expect(backend.isRunning, isTrue);

      await backend.dispose();
    });

    test('created backend implements AgentBackend interface', () async {
      final backend = await BackendRegistry.create(
        type: BackendType.directCli,
      );

      expect(backend.isRunning, isA<bool>());
      expect(backend.errors, isA<Stream<BackendError>>());
      expect(backend.logs, isA<Stream<String>>());
      expect(backend.sessions, isA<List<AgentSession>>());

      await backend.dispose();
    });

    test('throws StateError for unregistered type', () {
      expect(
        () => BackendRegistry.create(type: BackendType.codex),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Backend lifecycle via registry', () {
    setUp(() {
      ClaudeCliBackend.register();
    });

    test('created backend can be disposed', () async {
      final backend = await BackendRegistry.create();
      expect(backend.isRunning, isTrue);

      await backend.dispose();
      expect(backend.isRunning, isFalse);
    });

    test('dispose is idempotent', () async {
      final backend = await BackendRegistry.create();

      await backend.dispose();
      await backend.dispose();
      await backend.dispose();

      expect(backend.isRunning, isFalse);
    });

    test('created backend has empty sessions list', () async {
      final backend = await BackendRegistry.create();

      expect(backend.sessions, isEmpty);

      await backend.dispose();
    });

    test('created backend streams are accessible', () async {
      final backend = await BackendRegistry.create();

      final errorsSub = backend.errors.listen((_) {});
      final logsSub = backend.logs.listen((_) {});

      await errorsSub.cancel();
      await logsSub.cancel();
      await backend.dispose();
    });

    test('multiple backends can be created', () async {
      final backend1 = await BackendRegistry.create();
      final backend2 = await BackendRegistry.create();

      expect(backend1, isNot(same(backend2)));
      expect(backend1.isRunning, isTrue);
      expect(backend2.isRunning, isTrue);

      await backend1.dispose();
      await backend2.dispose();
    });
  });

  group('Polymorphic usage via registry', () {
    setUp(() {
      ClaudeCliBackend.register();
    });

    test('returned backend can be used as AgentBackend', () async {
      AgentBackend backend = await BackendRegistry.create();

      expect(backend.isRunning, isTrue);
      expect(backend.sessions, isEmpty);

      await backend.dispose();
      expect(backend.isRunning, isFalse);
    });

    test('factory return type is AgentBackend', () async {
      final Future<AgentBackend> futureBackend = BackendRegistry.create();
      final backend = await futureBackend;

      expect(backend, isA<AgentBackend>());

      await backend.dispose();
    });
  });
}
