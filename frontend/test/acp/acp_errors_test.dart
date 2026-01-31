import 'package:cc_insights_v2/acp/acp_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ACPConnectionError', () {
    test('creates error with message', () {
      const error = ACPConnectionError('Connection failed');

      expect(error.message, 'Connection failed');
      expect(error.exitCode, isNull);
      expect(error.command, isNull);
      expect(error.toString(), 'ACPConnectionError: Connection failed');
    });

    test('creates error with exit code and command', () {
      const error = ACPConnectionError(
        'Process exited',
        exitCode: 1,
        command: '/usr/bin/agent',
      );

      expect(error.message, 'Process exited');
      expect(error.exitCode, 1);
      expect(error.command, '/usr/bin/agent');
    });

    test('commandNotFound factory creates correct error', () {
      final error = ACPConnectionError.commandNotFound('/usr/bin/missing');

      expect(error.message, contains('not found'));
      expect(error.message, contains('/usr/bin/missing'));
      expect(error.command, '/usr/bin/missing');
      expect(error.isCommandNotFound, isTrue);
      expect(error.isProcessCrash, isFalse);
    });

    test('processCrashed factory creates correct error', () {
      final error = ACPConnectionError.processCrashed(
        137,
        command: '/usr/bin/agent',
      );

      expect(error.message, contains('crashed'));
      expect(error.message, contains('137'));
      expect(error.exitCode, 137);
      expect(error.command, '/usr/bin/agent');
      expect(error.isProcessCrash, isTrue);
    });

    test('failedToStart factory creates correct error', () {
      final error = ACPConnectionError.failedToStart(
        'Permission denied',
        command: '/usr/bin/agent',
      );

      expect(error.message, contains('Failed to start'));
      expect(error.message, contains('Permission denied'));
      expect(error.command, '/usr/bin/agent');
    });
  });

  group('ACPProtocolError', () {
    test('creates error with message', () {
      const error = ACPProtocolError('Invalid message');

      expect(error.message, 'Invalid message');
      expect(error.rawMessage, isNull);
      expect(error.cause, isNull);
      expect(error.toString(), 'ACPProtocolError: Invalid message');
    });

    test('creates error with raw message and cause', () {
      final cause = FormatException('Bad JSON');
      const rawMessage = '{ invalid json }';
      final error = ACPProtocolError(
        'Parse failed',
        rawMessage: rawMessage,
        cause: cause,
      );

      expect(error.message, 'Parse failed');
      expect(error.rawMessage, rawMessage);
      expect(error.cause, cause);
    });

    test('invalidJson factory creates correct error', () {
      final cause = FormatException('Unexpected character');
      final error = ACPProtocolError.invalidJson('{ bad }', cause);

      expect(error.message, contains('Invalid JSON'));
      expect(error.rawMessage, '{ bad }');
      expect(error.cause, cause);
    });

    test('missingField factory creates correct error', () {
      final error = ACPProtocolError.missingField(
        'sessionId',
        rawMessage: '{"type": "update"}',
      );

      expect(error.message, contains('Missing required field'));
      expect(error.message, contains('sessionId'));
      expect(error.rawMessage, '{"type": "update"}');
    });

    test('unknownMessageType factory creates correct error', () {
      final error = ACPProtocolError.unknownMessageType('invalid_type');

      expect(error.message, contains('Unknown message type'));
      expect(error.message, contains('invalid_type'));
    });
  });

  group('ACPTimeoutError', () {
    test('creates error with message', () {
      const error = ACPTimeoutError('Operation timed out');

      expect(error.message, 'Operation timed out');
      expect(error.timeout, isNull);
      expect(error.operation, isNull);
      expect(error.toString(), 'ACPTimeoutError: Operation timed out');
    });

    test('creates error with timeout and operation', () {
      const error = ACPTimeoutError(
        'Timed out',
        timeout: Duration(seconds: 30),
        operation: 'initialize',
      );

      expect(error.message, 'Timed out');
      expect(error.timeout, const Duration(seconds: 30));
      expect(error.operation, 'initialize');
    });

    test('connectionTimeout factory creates correct error', () {
      final error = ACPTimeoutError.connectionTimeout(
        const Duration(seconds: 30),
      );

      expect(error.message, contains('Connection timed out'));
      expect(error.message, contains('30 seconds'));
      expect(error.timeout, const Duration(seconds: 30));
      expect(error.operation, 'connect');
    });

    test('operationTimeout factory creates correct error', () {
      final error = ACPTimeoutError.operationTimeout(
        'createSession',
        const Duration(seconds: 10),
      );

      expect(error.message, contains('createSession'));
      expect(error.message, contains('timed out'));
      expect(error.message, contains('10 seconds'));
      expect(error.timeout, const Duration(seconds: 10));
      expect(error.operation, 'createSession');
    });
  });

  group('ACPStateError', () {
    test('creates error with message', () {
      const error = ACPStateError('Invalid state');

      expect(error.message, 'Invalid state');
      expect(error.currentState, isNull);
      expect(error.requiredState, isNull);
      expect(error.toString(), 'ACPStateError: Invalid state');
    });

    test('creates error with states', () {
      const error = ACPStateError(
        'Wrong state',
        currentState: 'disconnected',
        requiredState: 'connected',
      );

      expect(error.message, 'Wrong state');
      expect(error.currentState, 'disconnected');
      expect(error.requiredState, 'connected');
    });

    test('notConnected factory creates correct error', () {
      final error = ACPStateError.notConnected();

      expect(error.message, contains('Not connected'));
      expect(error.currentState, 'disconnected');
      expect(error.requiredState, 'connected');
    });

    test('alreadyConnected factory creates correct error', () {
      final error = ACPStateError.alreadyConnected();

      expect(error.message, contains('Already connected'));
      expect(error.currentState, 'connected');
      expect(error.requiredState, 'disconnected');
    });
  });

  group('ACPError sealed class', () {
    test('all error types are ACPError', () {
      const connectionError = ACPConnectionError('test');
      const protocolError = ACPProtocolError('test');
      const timeoutError = ACPTimeoutError('test');
      const stateError = ACPStateError('test');

      expect(connectionError, isA<ACPError>());
      expect(protocolError, isA<ACPError>());
      expect(timeoutError, isA<ACPError>());
      expect(stateError, isA<ACPError>());
    });

    test('all error types implement Exception', () {
      const connectionError = ACPConnectionError('test');
      const protocolError = ACPProtocolError('test');
      const timeoutError = ACPTimeoutError('test');
      const stateError = ACPStateError('test');

      expect(connectionError, isA<Exception>());
      expect(protocolError, isA<Exception>());
      expect(timeoutError, isA<Exception>());
      expect(stateError, isA<Exception>());
    });

    test('errors can be caught as ACPError', () {
      ACPError? caught;

      try {
        throw const ACPConnectionError('test');
      } on ACPError catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught, isA<ACPConnectionError>());
    });

    test('errors can be caught by specific type', () {
      ACPConnectionError? connectionCaught;
      ACPTimeoutError? timeoutCaught;

      try {
        throw const ACPConnectionError('test');
      } on ACPConnectionError catch (e) {
        connectionCaught = e;
      }

      try {
        throw const ACPTimeoutError('test');
      } on ACPTimeoutError catch (e) {
        timeoutCaught = e;
      }

      expect(connectionCaught, isNotNull);
      expect(timeoutCaught, isNotNull);
    });
  });
}
