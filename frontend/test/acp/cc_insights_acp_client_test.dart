import 'dart:async';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/cc_insights_acp_client.dart';
import 'package:cc_insights_v2/acp/handlers/terminal_handler.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('CCInsightsACPClient', () {
    late TestResources resources;
    late TerminalHandler terminalHandler;
    late StreamController<SessionNotification> updateController;
    late StreamController<PendingPermission> permissionController;
    late CCInsightsACPClient client;
    late Directory tempDir;

    setUp(() {
      resources = TestResources();
      terminalHandler = TerminalHandler();
      updateController = resources.trackBroadcastStream<SessionNotification>();
      permissionController =
          resources.trackBroadcastStream<PendingPermission>();
      client = CCInsightsACPClient(
        updateController: updateController,
        permissionController: permissionController,
        terminalHandler: terminalHandler,
      );
      tempDir = Directory.systemTemp.createTempSync('cc_insights_test_');
    });

    tearDown(() async {
      await terminalHandler.disposeAll();
      await resources.disposeAll();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Creates a minimal SessionNotification for testing.
    SessionNotification createTestNotification() {
      return SessionNotification(
        sessionId: 'test-session-id',
        update: AgentMessageChunkSessionUpdate(
          content: TextContentBlock(text: 'Hello, world!'),
        ),
      );
    }

    /// Creates a minimal RequestPermissionRequest for testing.
    RequestPermissionRequest createTestPermissionRequest() {
      return RequestPermissionRequest(
        sessionId: 'test-session-id',
        options: [
          PermissionOption(
            optionId: 'allow_once',
            name: 'Allow Once',
            kind: PermissionOptionKind.allowOnce,
          ),
          PermissionOption(
            optionId: 'reject_once',
            name: 'Reject Once',
            kind: PermissionOptionKind.rejectOnce,
          ),
        ],
        toolCall: ToolCallUpdate(
          toolCallId: 'test-tool-call-id',
          title: 'Test Tool',
        ),
      );
    }

    test('sessionUpdate forwards to stream', () async {
      // Arrange
      final notification = createTestNotification();
      final receivedNotifications = <SessionNotification>[];
      final subscription = updateController.stream.listen((n) {
        receivedNotifications.add(n);
      });
      resources.trackSubscription(subscription);

      // Act
      await client.sessionUpdate(notification);

      // Allow stream to propagate
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(receivedNotifications, hasLength(1));
      expect(receivedNotifications.first.sessionId, 'test-session-id');
      expect(
        receivedNotifications.first.update,
        isA<AgentMessageChunkSessionUpdate>(),
      );
    });

    test('requestPermission creates pending permission', () async {
      // Arrange
      final request = createTestPermissionRequest();
      final receivedPermissions = <PendingPermission>[];
      final subscription = permissionController.stream.listen((p) {
        receivedPermissions.add(p);
      });
      resources.trackSubscription(subscription);

      // Act - start the request but don't await it yet
      final responseFuture = client.requestPermission(request);

      // Allow stream to propagate
      await Future<void>.delayed(Duration.zero);

      // Assert - verify PendingPermission appeared in stream
      expect(receivedPermissions, hasLength(1));
      expect(receivedPermissions.first.request.sessionId, 'test-session-id');
      expect(receivedPermissions.first.request.options, hasLength(2));

      // Resolve the permission
      receivedPermissions.first.allow('allow_once');

      // Now await the response
      final response = await responseFuture;

      // Assert - verify response contains SelectedOutcome
      expect(response.outcome, isA<SelectedOutcome>());
      final selectedOutcome = response.outcome as SelectedOutcome;
      expect(selectedOutcome.optionId, 'allow_once');
    });

    test('requestPermission with cancel returns CancelledOutcome', () async {
      // Arrange
      final request = createTestPermissionRequest();
      final receivedPermissions = <PendingPermission>[];
      final subscription = permissionController.stream.listen((p) {
        receivedPermissions.add(p);
      });
      resources.trackSubscription(subscription);

      // Act - start the request but don't await it yet
      final responseFuture = client.requestPermission(request);

      // Allow stream to propagate
      await Future<void>.delayed(Duration.zero);

      // Cancel the permission
      receivedPermissions.first.cancel();

      // Await the response
      final response = await responseFuture;

      // Assert - verify response contains CancelledOutcome
      expect(response.outcome, isA<CancelledOutcome>());
    });

    test('readTextFile returns file content', () async {
      // Arrange - create temp file with known content
      final testFile = File('${tempDir.path}/test_read.txt');
      const testContent = 'Hello, this is test content!\nLine 2.';
      await testFile.writeAsString(testContent);

      // Act
      final response = await client.readTextFile(
        ReadTextFileRequest(sessionId: 'test-session', path: testFile.path),
      );

      // Assert
      expect(response.content, testContent);
    });

    test('readTextFile throws for missing file', () async {
      // Arrange
      final nonExistentPath = '${tempDir.path}/nonexistent_file.txt';

      // Act & Assert
      expect(
        () async => client.readTextFile(
          ReadTextFileRequest(sessionId: 'test-session', path: nonExistentPath),
        ),
        throwsA(isA<RequestError>()),
      );
    });

    test('writeTextFile creates file', () async {
      // Arrange
      final testPath = '${tempDir.path}/test_write.txt';
      const testContent = 'Written content here.';

      // Act
      await client.writeTextFile(
        WriteTextFileRequest(
          sessionId: 'test-session',
          path: testPath,
          content: testContent,
        ),
      );

      // Assert
      final file = File(testPath);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), testContent);
    });

    test('writeTextFile creates parent directories', () async {
      // Arrange - nested path with non-existent directories
      final testPath = '${tempDir.path}/nested/deep/dir/test_write.txt';
      const testContent = 'Nested content.';

      // Act
      await client.writeTextFile(
        WriteTextFileRequest(
          sessionId: 'test-session',
          path: testPath,
          content: testContent,
        ),
      );

      // Assert - directories were created and file exists
      final file = File(testPath);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), testContent);
    });

    test('writeTextFile overwrites existing file', () async {
      // Arrange - create file first
      final testPath = '${tempDir.path}/test_overwrite.txt';
      final file = File(testPath);
      await file.writeAsString('Original content');

      const newContent = 'New overwritten content.';

      // Act
      await client.writeTextFile(
        WriteTextFileRequest(
          sessionId: 'test-session',
          path: testPath,
          content: newContent,
        ),
      );

      // Assert
      expect(file.readAsStringSync(), newContent);
    });

    test('createTerminal delegates to handler', () async {
      // Arrange
      final request = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'echo',
        args: ['hello'],
      );

      // Act
      final response = await client.createTerminal(request);

      // Assert
      expect(response.terminalId, isNotEmpty);
      expect(response.terminalId, startsWith('term_'));
    });

    test('terminalOutput delegates to handler', () async {
      // Arrange - create terminal first
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'echo',
        args: ['output test'],
      );
      final createResponse = await client.createTerminal(createRequest);

      // Wait for exit
      await client.waitForTerminalExit(
        WaitForTerminalExitRequest(
          sessionId: 'test-session',
          terminalId: createResponse.terminalId,
        ),
      );

      // Act
      final outputResponse = await client.terminalOutput(
        TerminalOutputRequest(
          sessionId: 'test-session',
          terminalId: createResponse.terminalId,
        ),
      );

      // Assert
      expect(outputResponse.output, contains('output test'));
    });

    test('releaseTerminal delegates to handler', () async {
      // Arrange - create terminal first
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'echo',
        args: ['release test'],
      );
      final createResponse = await client.createTerminal(createRequest);
      final terminalId = createResponse.terminalId;

      // Wait for exit first
      await client.waitForTerminalExit(
        WaitForTerminalExitRequest(
          sessionId: 'test-session',
          terminalId: terminalId,
        ),
      );

      // Act
      await client.releaseTerminal(
        ReleaseTerminalRequest(
          sessionId: 'test-session',
          terminalId: terminalId,
        ),
      );

      // Assert - terminal no longer exists
      expect(
        () async => client.terminalOutput(
          TerminalOutputRequest(
            sessionId: 'test-session',
            terminalId: terminalId,
          ),
        ),
        throwsA(isA<RequestError>()),
      );
    });

    test('killTerminal delegates to handler', () async {
      // Arrange - create terminal with a long-running command
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'sleep',
        args: ['60'],
      );
      final createResponse = await client.createTerminal(createRequest);
      final terminalId = createResponse.terminalId;

      // Act - kill the terminal
      await client.killTerminal(
        KillTerminalCommandRequest(
          sessionId: 'test-session',
          terminalId: terminalId,
        ),
      );

      // Wait for exit
      final exitResponse = await client.waitForTerminalExit(
        WaitForTerminalExitRequest(
          sessionId: 'test-session',
          terminalId: terminalId,
        ),
      );

      // Assert - process was killed (non-zero exit code)
      expect(exitResponse.exitCode, isNot(0));
    });

    test('waitForTerminalExit delegates to handler', () async {
      // Arrange - create terminal that exits with specific code
      final createRequest = CreateTerminalRequest(
        sessionId: 'test-session',
        command: 'exit 42',
      );
      final createResponse = await client.createTerminal(createRequest);

      // Act
      final exitResponse = await client.waitForTerminalExit(
        WaitForTerminalExitRequest(
          sessionId: 'test-session',
          terminalId: createResponse.terminalId,
        ),
      );

      // Assert
      expect(exitResponse.exitCode, 42);
    });

    test('terminal methods throw RequestError for unknown terminal', () async {
      // Arrange
      const unknownId = 'unknown-terminal-id';

      // Assert - terminalOutput throws
      expect(
        () async => client.terminalOutput(
          TerminalOutputRequest(
            sessionId: 'test-session',
            terminalId: unknownId,
          ),
        ),
        throwsA(isA<RequestError>()),
      );

      // Assert - releaseTerminal throws
      expect(
        () async => client.releaseTerminal(
          ReleaseTerminalRequest(
            sessionId: 'test-session',
            terminalId: unknownId,
          ),
        ),
        throwsA(isA<RequestError>()),
      );

      // Assert - killTerminal throws
      expect(
        () async => client.killTerminal(
          KillTerminalCommandRequest(
            sessionId: 'test-session',
            terminalId: unknownId,
          ),
        ),
        throwsA(isA<RequestError>()),
      );

      // Assert - waitForTerminalExit throws
      expect(
        () async => client.waitForTerminalExit(
          WaitForTerminalExitRequest(
            sessionId: 'test-session',
            terminalId: unknownId,
          ),
        ),
        throwsA(isA<RequestError>()),
      );
    });

    test('extMethod returns null for unknown methods', () async {
      // Act
      final result = client.extMethod('unknown_method', {'key': 'value'});

      // Assert
      expect(result, isNull);
    });

    test('extNotification returns null', () async {
      // Act
      final result = client.extNotification(
        'unknown_notification',
        {'key': 'value'},
      );

      // Assert
      expect(result, isNull);
    });
  });
}
