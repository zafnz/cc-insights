import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Creates a minimal RequestPermissionRequest for testing.
  RequestPermissionRequest createTestRequest() {
    return RequestPermissionRequest(
      sessionId: 'test-session-id',
      options: [
        PermissionOption(
          optionId: 'allow_once',
          name: 'Allow Once',
          kind: PermissionOptionKind.allowOnce,
        ),
        PermissionOption(
          optionId: 'allow_always',
          name: 'Allow Always',
          kind: PermissionOptionKind.allowAlways,
        ),
      ],
      toolCall: ToolCallUpdate(
        toolCallId: 'test-tool-call-id',
        title: 'Test Tool',
      ),
    );
  }

  group('PendingPermission', () {
    test('allow completes with SelectedOutcome', () async {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // Act
      pending.allow('option1');

      // Assert
      final response = await completer.future;
      expect(response.outcome, isA<SelectedOutcome>());
      final selectedOutcome = response.outcome as SelectedOutcome;
      expect(selectedOutcome.optionId, 'option1');
    });

    test('cancel completes with CancelledOutcome', () async {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // Act
      pending.cancel();

      // Assert
      final response = await completer.future;
      expect(response.outcome, isA<CancelledOutcome>());
    });

    test('isResolved returns false initially and true after resolution', () {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // Assert - initially not resolved
      expect(pending.isResolved, isFalse);

      // Act - resolve via allow
      pending.allow('allow_once');

      // Assert - now resolved
      expect(pending.isResolved, isTrue);
    });

    test('isResolved returns true after cancel', () {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // Assert - initially not resolved
      expect(pending.isResolved, isFalse);

      // Act - resolve via cancel
      pending.cancel();

      // Assert - now resolved
      expect(pending.isResolved, isTrue);
    });

    test('allow throws if already resolved', () {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // First call succeeds
      pending.allow('option1');

      // Second call should throw
      expect(
        () => pending.allow('option2'),
        throwsA(isA<StateError>()),
      );
    });

    test('cancel throws if already resolved', () {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // First call succeeds via allow
      pending.allow('option1');

      // Cancel should throw since already resolved
      expect(
        () => pending.cancel(),
        throwsA(isA<StateError>()),
      );
    });

    test('cancel then allow throws', () {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // First cancel
      pending.cancel();

      // Allow should throw since already resolved
      expect(
        () => pending.allow('option1'),
        throwsA(isA<StateError>()),
      );
    });

    test('cancel then cancel throws', () {
      // Arrange
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: createTestRequest(),
        completer: completer,
      );

      // First cancel
      pending.cancel();

      // Second cancel should throw
      expect(
        () => pending.cancel(),
        throwsA(isA<StateError>()),
      );
    });

    test('request property returns the original request', () {
      // Arrange
      final request = createTestRequest();
      final completer = Completer<RequestPermissionResponse>();
      final pending = PendingPermission(
        request: request,
        completer: completer,
      );

      // Assert
      expect(pending.request, same(request));
      expect(pending.request.sessionId, 'test-session-id');
      expect(pending.request.options.length, 2);
      expect(pending.request.toolCall.toolCallId, 'test-tool-call-id');
    });
  });
}
