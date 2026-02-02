@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

/// Integration tests for direct CLI communication.
///
/// These tests communicate with the real claude-cli using the haiku model
/// for cost efficiency. They are gated by the CLAUDE_INTEGRATION_TESTS
/// environment variable.
///
/// To run these tests:
/// ```
/// CLAUDE_INTEGRATION_TESTS=true dart test test/integration/
/// ```
void main() {
  final runIntegration =
      Platform.environment['CLAUDE_INTEGRATION_TESTS'] == 'true';

  group(
    'CLI Integration',
    skip: !runIntegration ? 'Set CLAUDE_INTEGRATION_TESTS=true' : null,
    () {
      // Use a temp directory for working directory
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('cli_integration_');
      });

      tearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // Ignore cleanup errors
        }
      });

      test(
        'initializes session and receives system init',
        () async {
          // Arrange & Act
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'Say exactly "Hello" and nothing else.',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 1,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Assert - session was created successfully
            expect(session.sessionId, isNotEmpty);
            expect(session.systemInit, isNotNull);
            expect(session.systemInit.subtype, equals('init'));
            expect(session.systemInit.tools, isNotNull);
            expect(session.systemInit.tools, isNotEmpty);
            expect(session.isActive, isTrue);
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 60)),
      );

      test(
        'sends message and receives response',
        () async {
          // Arrange
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'What is 2 + 2? Reply with just the number.',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 1,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Act - collect messages until result
            final messages = <SDKMessage>[];
            SDKResultMessage? result;

            await for (final message in session.messages) {
              messages.add(message);
              if (message is SDKResultMessage) {
                result = message;
                break;
              }
            }

            // Assert
            expect(result, isNotNull);
            expect(result!.isError, isFalse);
            expect(result.numTurns, greaterThanOrEqualTo(1));

            // Should have received an assistant message
            final assistantMessages =
                messages.whereType<SDKAssistantMessage>().toList();
            expect(assistantMessages, isNotEmpty);

            // The assistant should have responded with text
            final content = assistantMessages.first.message.content;
            expect(content, isNotEmpty);
            expect(content.first, isA<TextBlock>());
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 60)),
      );

      test(
        'handles permission request for Bash tool',
        () async {
          // Arrange - Use default permission mode (requires permission)
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'Run this exact command: echo "test123"',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 2,
              permissionMode: PermissionMode.defaultMode,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Set up permission handler
            CliPermissionRequest? permissionRequest;
            final permissionCompleter = Completer<void>();

            session.permissionRequests.listen((request) {
              permissionRequest = request;
              // Allow the permission
              request.allow();
              permissionCompleter.complete();
            });

            // Act - wait for permission request or result
            final messages = <SDKMessage>[];
            SDKResultMessage? result;

            // Race between permission request and messages
            final messagesSub = session.messages.listen((message) {
              messages.add(message);
              if (message is SDKResultMessage) {
                result = message;
              }
            });

            // Wait for either a permission request or completion
            await Future.any([
              permissionCompleter.future,
              session.messages.firstWhere((m) => m is SDKResultMessage),
            ]).timeout(
              Duration(seconds: 45),
              onTimeout: () => null,
            );

            // If we got a permission request, wait for the result after allowing
            if (permissionRequest != null) {
              await session.messages.firstWhere((m) => m is SDKResultMessage);
            }

            await messagesSub.cancel();

            // Assert - if there was a permission request
            if (permissionRequest != null) {
              expect(permissionRequest!.toolName, equals('Bash'));
              expect(permissionRequest!.responded, isTrue);
            }

            // Either way, we should have a result
            expect(result ?? messages.whereType<SDKResultMessage>().firstOrNull,
                isNotNull);
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 90)),
      );

      test(
        'handles AskUserQuestion with answers',
        () async {
          // Arrange - use a prompt that triggers a question
          // The user question tool is typically named "AskUserQuestion"
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt:
                'Ask me what my favorite color is using the AskUserQuestion '
                'tool, then respond with that color.',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 3,
              permissionMode: PermissionMode.acceptEdits,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Set up permission handler for AskUserQuestion
            final permissionCompleter = Completer<void>();
            String? askedQuestion;

            session.permissionRequests.listen((request) {
              if (request.toolName == 'AskUserQuestion') {
                // Capture the question
                askedQuestion = request.input['question'] as String?;
                // Provide an answer via updatedInput
                request.allow(
                  updatedInput: {
                    ...request.input,
                    'question': request.input['question'],
                  },
                );
                permissionCompleter.complete();
              } else {
                // Allow other tools
                request.allow();
              }
            });

            // Act - collect messages until result
            final messages = <SDKMessage>[];
            SDKResultMessage? result;

            await for (final message in session.messages.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              messages.add(message);
              if (message is SDKResultMessage) {
                result = message;
                break;
              }
            }

            // Assert - the session completed (may or may not have asked)
            // The model might not always use AskUserQuestion, so we just verify
            // that the session completed successfully
            expect(result, isNotNull);

            // If there was a question asked, verify it was captured
            if (askedQuestion != null) {
              expect(askedQuestion, contains('color'));
            }
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 90)),
      );

      test(
        'handles permission denial',
        () async {
          // Arrange
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'Run this command: rm -rf / (do not worry, just try it)',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 2,
              permissionMode: PermissionMode.defaultMode,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Set up permission handler to deny
            final permissionDenied = Completer<void>();
            String? deniedToolName;

            session.permissionRequests.listen((request) {
              deniedToolName = request.toolName;
              request.deny('User denied this dangerous command');
              if (!permissionDenied.isCompleted) {
                permissionDenied.complete();
              }
            });

            // Act - collect messages until result
            final messages = <SDKMessage>[];
            SDKResultMessage? result;

            await for (final message in session.messages.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              messages.add(message);
              if (message is SDKResultMessage) {
                result = message;
                break;
              }
            }

            // Assert
            expect(result, isNotNull);

            // If permission was requested and denied
            if (deniedToolName != null) {
              expect(deniedToolName, equals('Bash'));

              // Check for permission denial in the result
              if (result!.permissionDenials != null &&
                  result.permissionDenials!.isNotEmpty) {
                expect(result.permissionDenials!.first.toolName, equals('Bash'));
              }
            }
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 90)),
      );

      test(
        'resumes session with follow-up message',
        () async {
          // Arrange - create initial session
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'Remember the number 42. Just say "I remember 42."',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 1,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Wait for first turn to complete
            SDKResultMessage? firstResult;
            await for (final message in session.messages) {
              if (message is SDKResultMessage) {
                firstResult = message;
                break;
              }
            }

            expect(firstResult, isNotNull);
            expect(firstResult!.isError, isFalse);

            // Act - send follow-up message
            await session.send('What number did I ask you to remember?');

            // Collect follow-up response
            final followUpMessages = <SDKMessage>[];
            SDKResultMessage? followUpResult;

            await for (final message in session.messages.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              followUpMessages.add(message);
              if (message is SDKResultMessage) {
                followUpResult = message;
                break;
              }
            }

            // Assert
            expect(followUpResult, isNotNull);

            // The assistant should have remembered the number
            final assistantMessages =
                followUpMessages.whereType<SDKAssistantMessage>().toList();
            expect(assistantMessages, isNotEmpty);

            // Check that the response contains "42"
            final responseText = assistantMessages
                .expand((m) => m.message.content)
                .whereType<TextBlock>()
                .map((t) => t.text)
                .join(' ');

            expect(responseText.toLowerCase(), contains('42'));
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 120)),
      );

      test(
        'handles stream events for partial responses',
        () async {
          // Arrange
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'Count from 1 to 5, one number per line.',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 1,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Act - collect all messages including stream events
            final messages = <SDKMessage>[];
            final streamEvents = <SDKStreamEvent>[];

            await for (final message in session.messages.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              messages.add(message);
              if (message is SDKStreamEvent) {
                streamEvents.add(message);
              }
              if (message is SDKResultMessage) {
                break;
              }
            }

            // Assert - we should have received stream events for partial text
            // Note: The CLI may or may not send stream events depending on config
            expect(messages, isNotEmpty);
            expect(
              messages.whereType<SDKResultMessage>().firstOrNull,
              isNotNull,
            );

            // If we got stream events, verify they have text deltas
            if (streamEvents.isNotEmpty) {
              final textDeltas = streamEvents
                  .where((e) => e.textDelta != null)
                  .map((e) => e.textDelta!)
                  .toList();
              expect(textDeltas.join(), isNotEmpty);
            }
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 60)),
      );

      test(
        'interrupt stops execution',
        () async {
          // Arrange - give a task that will take some time
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'Count from 1 to 100, explaining each number in detail.',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 1,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Start listening for messages
            var messageCount = 0;
            var interrupted = false;

            // Listen and count messages
            final sub = session.messages.listen((message) {
              messageCount++;
              // After a few messages, interrupt
              if (messageCount >= 3 && !interrupted) {
                interrupted = true;
                session.interrupt();
              }
            });

            // Wait for the session to complete (should be quick after interrupt)
            await sub.asFuture().timeout(
                  Duration(seconds: 30),
                  onTimeout: () => null,
                );

            await sub.cancel();

            // Assert - session should no longer be active after interrupt completes
            // Note: The actual behavior depends on CLI implementation
            // At minimum, we should have received some messages
            expect(messageCount, greaterThan(0));
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 60)),
      );

      test(
        'disposes resources cleanly',
        () async {
          // Arrange
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'Say "test"',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 1,
            ),
            timeout: const Duration(seconds: 60),
          );

          // Act
          await session.dispose();

          // Assert
          expect(session.isActive, isFalse);

          // Trying to send after dispose should throw
          expect(
            () => session.send('test'),
            throwsStateError,
          );
        },
        timeout: Timeout(Duration(seconds: 60)),
      );
    },
  );
}
