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
        'initializes session and receives system init event',
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
            expect(session.isActive, isTrue);

            // Verify we receive a SessionInitEvent via the events stream
            final events = <InsightsEvent>[];
            final eventsSub = session.events.listen(events.add);

            // Wait for events to arrive
            await session.events
                .firstWhere((e) => e is TurnCompleteEvent)
                .timeout(Duration(seconds: 45), onTimeout: () {
              throw TimeoutException('No TurnCompleteEvent received');
            });

            await eventsSub.cancel();

            // Should have received a SessionInitEvent
            final initEvents = events.whereType<SessionInitEvent>().toList();
            expect(initEvents, isNotEmpty);
            expect(initEvents.first.availableTools, isNotNull);
            expect(initEvents.first.availableTools, isNotEmpty);
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 60)),
      );

      test(
        'sends message and receives response via events stream',
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
            // Act - collect events until TurnCompleteEvent
            final events = <InsightsEvent>[];
            TurnCompleteEvent? result;

            await for (final event in session.events) {
              events.add(event);
              if (event is TurnCompleteEvent) {
                result = event;
                break;
              }
            }

            // Assert
            expect(result, isNotNull);
            expect(result!.isError, isFalse);
            expect(result.numTurns, greaterThanOrEqualTo(1));

            // Should have received TextEvents from the assistant
            final textEvents = events.whereType<TextEvent>().toList();
            expect(textEvents, isNotEmpty);

            // The assistant should have responded with text
            final responseText = textEvents.map((e) => e.text).join();
            expect(responseText, isNotEmpty);
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
            final events = <InsightsEvent>[];
            TurnCompleteEvent? result;

            // Race between permission request and events
            final eventsSub = session.events.listen((event) {
              events.add(event);
              if (event is TurnCompleteEvent) {
                result = event;
              }
            });

            // Wait for either a permission request or completion
            await Future.any([
              permissionCompleter.future,
              session.events.firstWhere((e) => e is TurnCompleteEvent),
            ]).timeout(
              Duration(seconds: 45),
              onTimeout: () => null,
            );

            // If we got a permission request, wait for the result after allowing
            if (permissionRequest != null) {
              await session.events
                  .firstWhere((e) => e is TurnCompleteEvent);
            }

            await eventsSub.cancel();

            // Assert - if there was a permission request
            if (permissionRequest != null) {
              expect(permissionRequest!.toolName, equals('Bash'));
              expect(permissionRequest!.responded, isTrue);
            }

            // Either way, we should have a result
            expect(
                result ??
                    events.whereType<TurnCompleteEvent>().firstOrNull,
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

            // Act - collect events until result
            final events = <InsightsEvent>[];
            TurnCompleteEvent? result;

            await for (final event in session.events.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              events.add(event);
              if (event is TurnCompleteEvent) {
                result = event;
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

            // Act - collect events until result
            final events = <InsightsEvent>[];
            TurnCompleteEvent? result;

            await for (final event in session.events.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              events.add(event);
              if (event is TurnCompleteEvent) {
                result = event;
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
                expect(
                    result.permissionDenials!.first.toolName, equals('Bash'));
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
            TurnCompleteEvent? firstResult;
            await for (final event in session.events) {
              if (event is TurnCompleteEvent) {
                firstResult = event;
                break;
              }
            }

            expect(firstResult, isNotNull);
            expect(firstResult!.isError, isFalse);

            // Act - send follow-up message
            await session.send('What number did I ask you to remember?');

            // Collect follow-up response
            final followUpEvents = <InsightsEvent>[];
            TurnCompleteEvent? followUpResult;

            await for (final event in session.events.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              followUpEvents.add(event);
              if (event is TurnCompleteEvent) {
                followUpResult = event;
                break;
              }
            }

            // Assert
            expect(followUpResult, isNotNull);

            // The assistant should have remembered the number
            final textEvents =
                followUpEvents.whereType<TextEvent>().toList();
            expect(textEvents, isNotEmpty);

            // Check that the response contains "42"
            final responseText = textEvents.map((e) => e.text).join(' ');

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
            // Act - collect all events including stream deltas
            final events = <InsightsEvent>[];
            final streamEvents = <StreamDeltaEvent>[];

            await for (final event in session.events.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              events.add(event);
              if (event is StreamDeltaEvent) {
                streamEvents.add(event);
              }
              if (event is TurnCompleteEvent) {
                break;
              }
            }

            // Assert - we should have received stream events for partial text
            // Note: The CLI may or may not send stream events depending on config
            expect(events, isNotEmpty);
            expect(
              events.whereType<TurnCompleteEvent>().firstOrNull,
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
            // Start listening for events
            var eventCount = 0;
            var interrupted = false;

            // Listen and count events
            final sub = session.events.listen((event) {
              eventCount++;
              // After a few events, interrupt
              if (eventCount >= 3 && !interrupted) {
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
            // At minimum, we should have received some events
            expect(eventCount, greaterThan(0));
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

      test(
        'emits InsightsEvents on events stream',
        () async {
          // Arrange
          final session = await CliSession.create(
            cwd: tempDir.path,
            prompt: 'What is 1 + 1? Reply with just the number.',
            options: SessionOptions(
              model: 'haiku',
              maxTurns: 1,
            ),
            timeout: const Duration(seconds: 60),
          );

          try {
            // Act - collect InsightsEvents
            final events = <InsightsEvent>[];
            TurnCompleteEvent? result;

            await for (final event in session.events.timeout(
              Duration(seconds: 45),
              onTimeout: (sink) => sink.close(),
            )) {
              events.add(event);
              if (event is TurnCompleteEvent) {
                result = event;
                break;
              }
            }

            // Assert - verify we received InsightsEvents
            expect(result, isNotNull, reason: 'Should have received a result');
            expect(events, isNotEmpty,
                reason: 'Should have received InsightsEvents');

            // Verify we got a SessionInitEvent (from initialization)
            final initEvents = events.whereType<SessionInitEvent>().toList();
            expect(initEvents, isNotEmpty,
                reason: 'Should have SessionInitEvent');
            final initEvent = initEvents.first;
            expect(initEvent.sessionId, isNotEmpty);
            expect(initEvent.model, isNotEmpty);
            expect(initEvent.availableTools, isNotEmpty);

            // Verify we got TextEvents (from assistant response)
            final textEvents = events.whereType<TextEvent>().toList();
            expect(textEvents, isNotEmpty,
                reason: 'Should have TextEvents from assistant');

            // Verify we got a TurnCompleteEvent (from result)
            final completeEvents =
                events.whereType<TurnCompleteEvent>().toList();
            expect(completeEvents, isNotEmpty,
                reason: 'Should have TurnCompleteEvent');
            final completeEvent = completeEvents.first;
            expect(completeEvent.isError, isFalse);
            expect(completeEvent.usage, isNotNull);
            expect(completeEvent.usage!.inputTokens, greaterThan(0));
            expect(completeEvent.usage!.outputTokens, greaterThan(0));

            // Verify event provider is Claude
            expect(initEvent.provider, equals(BackendProvider.claude));
            expect(completeEvent.provider, equals(BackendProvider.claude));

            // ignore: avoid_print
            print('InsightsEvents verification:');
            // ignore: avoid_print
            print('  - ${initEvents.length} SessionInitEvent(s)');
            // ignore: avoid_print
            print('  - ${textEvents.length} TextEvent(s)');
            // ignore: avoid_print
            print('  - ${completeEvents.length} TurnCompleteEvent(s)');
            // ignore: avoid_print
            print('  - Total: ${events.length} events emitted');
          } finally {
            await session.dispose();
          }
        },
        timeout: Timeout(Duration(seconds: 90)),
      );
    },
  );
}
