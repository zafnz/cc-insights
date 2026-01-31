import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/handlers/terminal_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalHandler', () {
    late TerminalHandler handler;

    setUp(() {
      handler = TerminalHandler();
    });

    tearDown(() async {
      await handler.disposeAll();
    });

    test('create spawns process and returns ID', () async {
      // Arrange
      final request = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'echo',
        args: ['hello'],
      );

      // Act
      final response = await handler.create(request);

      // Assert
      expect(response.terminalId, isNotEmpty);
      expect(response.terminalId, startsWith('term_'));
    });

    test('output returns command output', () async {
      // Arrange - create terminal with 'echo hello'
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'echo',
        args: ['hello'],
      );
      final createResponse = await handler.create(createRequest);
      final terminalId = createResponse.terminalId;

      // Wait for process to exit
      final waitRequest = WaitForTerminalExitRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      await handler.waitForExit(waitRequest);

      // Act - get output
      final outputRequest = TerminalOutputRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      final outputResponse = await handler.output(outputRequest);

      // Assert
      expect(outputResponse.output, contains('hello'));
      expect(outputResponse.exitStatus, isNotNull);
      expect(outputResponse.exitStatus!.exitCode, 0);
    });

    test('kill terminates running process', () async {
      // Arrange - create terminal with 'sleep 60'
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'sleep',
        args: ['60'],
      );
      final createResponse = await handler.create(createRequest);
      final terminalId = createResponse.terminalId;

      // Act - kill the process
      final killRequest = KillTerminalCommandRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      await handler.kill(killRequest);

      // Wait for exit
      final waitRequest = WaitForTerminalExitRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      final waitResponse = await handler.waitForExit(waitRequest);

      // Assert - killed processes have non-zero exit code
      // SIGTERM results in exit code 143 (128 + 15), SIGKILL in 137 (128 + 9)
      // or the exit code might be reported as -1 depending on how the process
      // is terminated
      expect(waitResponse.exitCode, isNot(0));
    });

    test('release cleans up terminal', () async {
      // Arrange - create terminal
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'echo',
        args: ['test'],
      );
      final createResponse = await handler.create(createRequest);
      final terminalId = createResponse.terminalId;

      // Wait for process to exit first
      final waitRequest = WaitForTerminalExitRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      await handler.waitForExit(waitRequest);

      // Act - release the terminal
      final releaseRequest = ReleaseTerminalRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      await handler.release(releaseRequest);

      // Assert - subsequent calls should throw TerminalNotFoundError
      final outputRequest = TerminalOutputRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      expect(
        () async => handler.output(outputRequest),
        throwsA(isA<TerminalNotFoundError>()),
      );
    });

    test('waitForExit returns exit code', () async {
      // Arrange - create terminal with 'exit 42'
      // Using /bin/sh -c 'exit 42' since that's how commands are run
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'exit 42',
      );
      final createResponse = await handler.create(createRequest);
      final terminalId = createResponse.terminalId;

      // Act
      final waitRequest = WaitForTerminalExitRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      final waitResponse = await handler.waitForExit(waitRequest);

      // Assert
      expect(waitResponse.exitCode, 42);
    });

    test('output throws for unknown terminal', () async {
      // Arrange
      final outputRequest = TerminalOutputRequest(
        sessionId: 'test-session',
        terminalId: 'nonexistent-terminal-id',
      );

      // Act & Assert
      expect(
        () async => handler.output(outputRequest),
        throwsA(isA<TerminalNotFoundError>()),
      );
    });

    test('waitForExit throws for unknown terminal', () async {
      // Arrange
      final waitRequest = WaitForTerminalExitRequest(
        sessionId: 'test-session',
        terminalId: 'nonexistent-terminal-id',
      );

      // Act & Assert
      expect(
        () async => handler.waitForExit(waitRequest),
        throwsA(isA<TerminalNotFoundError>()),
      );
    });

    test('kill throws for unknown terminal', () async {
      // Arrange
      final killRequest = KillTerminalCommandRequest(
        sessionId: 'test-session',
        terminalId: 'nonexistent-terminal-id',
      );

      // Act & Assert
      expect(
        () async => handler.kill(killRequest),
        throwsA(isA<TerminalNotFoundError>()),
      );
    });

    test('release throws for unknown terminal', () async {
      // Arrange
      final releaseRequest = ReleaseTerminalRequest(
        sessionId: 'test-session',
        terminalId: 'nonexistent-terminal-id',
      );

      // Act & Assert
      expect(
        () async => handler.release(releaseRequest),
        throwsA(isA<TerminalNotFoundError>()),
      );
    });

    test('disposeAll cleans up all terminals', () async {
      // Arrange - create multiple terminals
      final createRequest1 = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'sleep',
        args: ['60'],
      );
      final createRequest2 = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'sleep',
        args: ['60'],
      );
      final response1 = await handler.create(createRequest1);
      final response2 = await handler.create(createRequest2);

      // Act
      await handler.disposeAll();

      // Assert - both terminals should be cleaned up
      final outputRequest1 = TerminalOutputRequest(
        sessionId: 'test-session',
        terminalId: response1.terminalId,
      );
      final outputRequest2 = TerminalOutputRequest(
        sessionId: 'test-session',
        terminalId: response2.terminalId,
      );

      expect(
        () async => handler.output(outputRequest1),
        throwsA(isA<TerminalNotFoundError>()),
      );
      expect(
        () async => handler.output(outputRequest2),
        throwsA(isA<TerminalNotFoundError>()),
      );
    });

    test('create with cwd sets working directory', () async {
      // Arrange - create terminal with cwd set to /tmp
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'pwd',
        cwd: '/tmp',
      );
      final createResponse = await handler.create(createRequest);
      final terminalId = createResponse.terminalId;

      // Wait for exit
      final waitRequest = WaitForTerminalExitRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      await handler.waitForExit(waitRequest);

      // Get output
      final outputRequest = TerminalOutputRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      final outputResponse = await handler.output(outputRequest);

      // Assert - output should contain /tmp (or /private/tmp on macOS)
      expect(
        outputResponse.output.contains('/tmp') ||
            outputResponse.output.contains('/private/tmp'),
        isTrue,
      );
    });

    test('create with env sets environment variables', () async {
      // Arrange - create terminal with custom env var
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'echo \$MY_TEST_VAR',
        env: [EnvVariable(name: 'MY_TEST_VAR', value: 'test_value_123')],
      );
      final createResponse = await handler.create(createRequest);
      final terminalId = createResponse.terminalId;

      // Wait for exit
      final waitRequest = WaitForTerminalExitRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      await handler.waitForExit(waitRequest);

      // Get output
      final outputRequest = TerminalOutputRequest(
        sessionId: 'test-session',
        terminalId: terminalId,
      );
      final outputResponse = await handler.output(outputRequest);

      // Assert
      expect(outputResponse.output, contains('test_value_123'));
    });
  });
}
