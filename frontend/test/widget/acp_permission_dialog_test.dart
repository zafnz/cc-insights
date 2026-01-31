import 'dart:async';

import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/pending_permission.dart';
import 'package:cc_insights_v2/widgets/acp_permission_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('AcpPermissionDialog Tests', () {
    /// Creates a fake PendingPermission for testing.
    PendingPermission createFakePermission({
      String sessionId = 'test-session',
      String toolCallId = 'test-tool-call',
      String? title,
      List<PermissionOption>? options,
      ToolKind? kind,
      Map<String, dynamic>? rawInput,
    }) {
      final completer = Completer<RequestPermissionResponse>();
      final toolCall = ToolCallUpdate(
        toolCallId: toolCallId,
        title: title,
        kind: kind,
        rawInput: rawInput,
      );
      final request = RequestPermissionRequest(
        sessionId: sessionId,
        toolCall: toolCall,
        options: options ??
            [
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
              PermissionOption(
                optionId: 'reject_once',
                name: 'Reject Once',
                kind: PermissionOptionKind.rejectOnce,
              ),
            ],
      );
      return PendingPermission(
        request: request,
        completer: completer,
      );
    }

    Widget createTestApp({
      required PendingPermission permission,
      void Function(String)? onAllow,
      VoidCallback? onCancel,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: AcpPermissionDialog(
            permission: permission,
            onAllow: onAllow ?? (_) {},
            onCancel: onCancel ?? () {},
          ),
        ),
      );
    }

    group('Displays tool info', () {
      testWidgets('shows tool title in the header', (tester) async {
        final permission = createFakePermission(title: 'Read File');

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(
          find.textContaining('Permission Required: Read File'),
          findsOneWidget,
        );
      });

      testWidgets('shows "Unknown Tool" when title is null', (tester) async {
        final permission = createFakePermission(title: null);

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(
          find.textContaining('Permission Required: Unknown Tool'),
          findsOneWidget,
        );
      });
    });

    group('Option buttons', () {
      testWidgets('shows all permission options as buttons', (tester) async {
        final permission = createFakePermission(
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
        );

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(find.text('Allow Once'), findsOneWidget);
        expect(find.text('Reject Once'), findsOneWidget);
      });

      testWidgets('allow option calls onAllow with correct optionId',
          (tester) async {
        String? capturedOptionId;
        final permission = createFakePermission(
          options: [
            PermissionOption(
              optionId: 'allow_once',
              name: 'Allow Once',
              kind: PermissionOptionKind.allowOnce,
            ),
          ],
        );

        await tester.pumpWidget(createTestApp(
          permission: permission,
          onAllow: (optionId) => capturedOptionId = optionId,
        ));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Allow Once'));
        await tester.pump();

        check(capturedOptionId).equals('allow_once');
      });

      testWidgets('reject option calls onAllow with correct optionId',
          (tester) async {
        String? capturedOptionId;
        final permission = createFakePermission(
          options: [
            PermissionOption(
              optionId: 'reject_always',
              name: 'Reject Always',
              kind: PermissionOptionKind.rejectAlways,
            ),
          ],
        );

        await tester.pumpWidget(createTestApp(
          permission: permission,
          onAllow: (optionId) => capturedOptionId = optionId,
        ));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Reject Always'));
        await tester.pump();

        check(capturedOptionId).equals('reject_always');
      });

      testWidgets('allow options use filled button style', (tester) async {
        final permission = createFakePermission(
          options: [
            PermissionOption(
              optionId: 'allow_once',
              name: 'Allow Once',
              kind: PermissionOptionKind.allowOnce,
            ),
          ],
        );

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(find.widgetWithText(FilledButton, 'Allow Once'), findsOneWidget);
      });

      testWidgets('reject options use outlined button style', (tester) async {
        final permission = createFakePermission(
          options: [
            PermissionOption(
              optionId: 'reject_once',
              name: 'Reject Once',
              kind: PermissionOptionKind.rejectOnce,
            ),
          ],
        );

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(
          find.widgetWithText(OutlinedButton, 'Reject Once'),
          findsOneWidget,
        );
      });
    });

    group('Cancel button', () {
      testWidgets('shows cancel button', (tester) async {
        final permission = createFakePermission();

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(find.text('Cancel'), findsOneWidget);
      });

      testWidgets('cancel button calls onCancel callback', (tester) async {
        var cancelCalled = false;
        final permission = createFakePermission();

        await tester.pumpWidget(createTestApp(
          permission: permission,
          onCancel: () => cancelCalled = true,
        ));
        await safePumpAndSettle(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pump();

        check(cancelCalled).isTrue();
      });
    });

    group('Raw input display', () {
      testWidgets('shows raw input when available', (tester) async {
        final permission = createFakePermission(
          title: 'Execute Command',
          rawInput: {
            'command': 'git status',
            'path': '/Users/test',
          },
        );

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(find.textContaining('command'), findsOneWidget);
        expect(find.textContaining('git status'), findsOneWidget);
      });
    });

    group('UI elements', () {
      testWidgets('displays shield icon in header', (tester) async {
        final permission = createFakePermission();

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      });

      testWidgets('renders all test keys', (tester) async {
        final permission = createFakePermission(
          options: [
            PermissionOption(
              optionId: 'allow_once',
              name: 'Allow',
              kind: PermissionOptionKind.allowOnce,
            ),
          ],
        );

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        expect(find.byKey(AcpPermissionDialogKeys.dialog), findsOneWidget);
        expect(find.byKey(AcpPermissionDialogKeys.header), findsOneWidget);
        expect(find.byKey(AcpPermissionDialogKeys.content), findsOneWidget);
        expect(find.byKey(AcpPermissionDialogKeys.optionsRow), findsOneWidget);
        expect(find.byKey(AcpPermissionDialogKeys.cancelButton), findsOneWidget);
        expect(
          find.byKey(AcpPermissionDialogKeys.optionButton('allow_once')),
          findsOneWidget,
        );
      });

      testWidgets('handles empty options list gracefully', (tester) async {
        final permission = createFakePermission(options: []);

        await tester.pumpWidget(createTestApp(permission: permission));
        await safePumpAndSettle(tester);

        // Should render without errors
        expect(find.byKey(AcpPermissionDialogKeys.dialog), findsOneWidget);
        // Cancel button should still be present
        expect(find.text('Cancel'), findsOneWidget);
      });
    });
  });
}
