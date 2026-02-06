import 'dart:async';

import 'package:cc_insights_v2/widgets/permission_dialog.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('PermissionDialog Tests', () {
    /// Creates a fake PermissionRequest for testing.
    sdk.PermissionRequest createFakeRequest({
      String id = 'test-id',
      String sessionId = 'test-session',
      String toolName = 'Bash',
      Map<String, dynamic> toolInput = const {'command': 'ls -la'},
      String? decisionReason,
    }) {
      final completer = Completer<sdk.PermissionResponse>();
      return sdk.PermissionRequest(
        id: id,
        sessionId: sessionId,
        toolName: toolName,
        toolInput: toolInput,
        decisionReason: decisionReason,
        completer: completer,
      );
    }

    Widget createTestApp({
      required sdk.PermissionRequest request,
      void Function({
        Map<String, dynamic>? updatedInput,
        List<dynamic>? updatedPermissions,
      })? onAllow,
      void Function(String)? onDeny,
      void Function(String planText)? onClearContextAndAcceptEdits,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: PermissionDialog(
            request: request,
            onAllow: onAllow ?? ({updatedInput, updatedPermissions}) {},
            onDeny: onDeny ?? (_) {},
            onClearContextAndAcceptEdits: onClearContextAndAcceptEdits,
          ),
        ),
      );
    }

    group('Displays tool name', () {
      testWidgets('shows tool name in the header', (tester) async {
        final request = createFakeRequest(toolName: 'Bash');

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify tool name is displayed in header
        expect(find.textContaining('Permission Required: Bash'), findsOneWidget);
      });

      testWidgets('shows different tool names correctly', (tester) async {
        final request = createFakeRequest(toolName: 'Read');

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('Permission Required: Read'), findsOneWidget);
      });
    });

    group('Bash tool display', () {
      testWidgets('shows command with dollar sign prefix', (tester) async {
        final request = createFakeRequest(
          toolName: 'Bash',
          toolInput: {'command': 'git status'},
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify the command is displayed with $ prefix
        expect(find.textContaining('\$ git status'), findsOneWidget);
      });

      testWidgets('shows description when provided', (tester) async {
        final request = createFakeRequest(
          toolName: 'Bash',
          toolInput: {
            'command': 'ls -la',
            'description': 'List all files in current directory',
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(
          find.text('List all files in current directory'),
          findsOneWidget,
        );
      });
    });

    group('Write tool display', () {
      testWidgets('shows file path', (tester) async {
        final request = createFakeRequest(
          toolName: 'Write',
          toolInput: {
            'file_path': '/Users/test/file.dart',
            'content': 'void main() {}',
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('/Users/test/file.dart'), findsOneWidget);
      });

      testWidgets('shows content preview', (tester) async {
        final request = createFakeRequest(
          toolName: 'Write',
          toolInput: {
            'file_path': '/Users/test/file.dart',
            'content': 'void main() { print("Hello"); }',
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('void main()'), findsOneWidget);
      });

      testWidgets('shows line count badge', (tester) async {
        final request = createFakeRequest(
          toolName: 'Write',
          toolInput: {
            'file_path': '/Users/test/file.dart',
            'content': 'line1\nline2\nline3',
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('3 lines'), findsOneWidget);
      });
    });

    group('Edit tool display', () {
      testWidgets('shows file path', (tester) async {
        final request = createFakeRequest(
          toolName: 'Edit',
          toolInput: {
            'file_path': '/Users/test/file.dart',
            'old_string': 'foo',
            'new_string': 'bar',
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('/Users/test/file.dart'), findsOneWidget);
      });

      testWidgets('shows old and new strings', (tester) async {
        final request = createFakeRequest(
          toolName: 'Edit',
          toolInput: {
            'file_path': '/Users/test/file.dart',
            'old_string': 'oldValue',
            'new_string': 'newValue',
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('oldValue'), findsOneWidget);
        expect(find.textContaining('newValue'), findsOneWidget);
      });
    });

    group('Generic tool display', () {
      testWidgets('shows key-value pairs for unknown tools', (tester) async {
        final request = createFakeRequest(
          toolName: 'CustomTool',
          toolInput: {
            'param1': 'value1',
            'param2': 42,
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('param1'), findsOneWidget);
        expect(find.textContaining('value1'), findsOneWidget);
        expect(find.textContaining('param2'), findsOneWidget);
        expect(find.textContaining('42'), findsOneWidget);
      });
    });

    group('Allow button works', () {
      testWidgets('calls onAllow callback when pressed', (tester) async {
        var allowCalled = false;
        final request = createFakeRequest();

        await tester.pumpWidget(createTestApp(
          request: request,
          onAllow: ({updatedInput, updatedPermissions}) {
            allowCalled = true;
          },
        ));
        await safePumpAndSettle(tester);

        // Find and tap the Allow button
        await tester.tap(find.text('Allow'));
        await tester.pump();

        check(allowCalled).isTrue();
      });

      testWidgets('Allow button is styled as filled button', (tester) async {
        final request = createFakeRequest();

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify Allow button exists as a FilledButton
        expect(find.widgetWithText(FilledButton, 'Allow'), findsOneWidget);
      });
    });

    group('Deny button works', () {
      testWidgets('calls onDeny callback when pressed', (tester) async {
        String? denyMessage;
        final request = createFakeRequest();

        await tester.pumpWidget(createTestApp(
          request: request,
          onDeny: (message) => denyMessage = message,
        ));
        await safePumpAndSettle(tester);

        // Find and tap the Deny button
        await tester.tap(find.text('Deny'));
        await tester.pump();

        check(denyMessage).isNotNull();
        check(denyMessage!).contains('denied');
      });

      testWidgets('Deny button is styled as outlined button', (tester) async {
        final request = createFakeRequest();

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify Deny button exists as an OutlinedButton
        expect(find.widgetWithText(OutlinedButton, 'Deny'), findsOneWidget);
      });
    });

    group('Handles empty input', () {
      testWidgets('gracefully handles empty tool input map', (tester) async {
        final request = createFakeRequest(
          toolName: 'CustomTool',
          toolInput: {},
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Should render without errors
        expect(
          find.textContaining('Permission Required: CustomTool'),
          findsOneWidget,
        );
      });

      testWidgets('renders all UI elements with empty input', (tester) async {
        final request = createFakeRequest(
          toolName: 'CustomTool',
          toolInput: {},
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Header still present
        expect(
          find.textContaining('Permission Required'),
          findsOneWidget,
        );
        // Buttons present
        expect(find.text('Allow'), findsOneWidget);
        expect(find.text('Deny'), findsOneWidget);
      });
    });

    group('ExitPlanMode tool display', () {
      /// Helper to create an ExitPlanMode test widget with proper sizing.
      /// ExitPlanMode uses LayoutBuilder which needs bounded constraints.
      Widget createPlanTestApp({
        required sdk.PermissionRequest request,
        void Function({
          Map<String, dynamic>? updatedInput,
          List<dynamic>? updatedPermissions,
        })? onAllow,
        void Function(String)? onDeny,
        void Function(String planText)? onClearContextAndAcceptEdits,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PermissionDialog(
                request: request,
                onAllow: onAllow ?? ({updatedInput, updatedPermissions}) {},
                onDeny: onDeny ?? (_) {},
                onClearContextAndAcceptEdits: onClearContextAndAcceptEdits,
              ),
            ),
          ),
        );
      }

      testWidgets('shows plan header and markdown content', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {
            'plan': '## Implementation Plan\n\n1. First step\n2. Second step',
          },
        );

        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify plan header
        expect(find.text('Plan for Approval'), findsOneWidget);
        // Verify description icon (not shield)
        expect(find.byIcon(Icons.description_outlined), findsOneWidget);
        // Verify plan content renders as markdown
        expect(find.textContaining('Implementation Plan'), findsOneWidget);
      });

      testWidgets('shows approval and reject buttons', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(
          request: request,
          onClearContextAndAcceptEdits: (_) {},
        ));
        await safePumpAndSettle(tester);

        // Verify all approval buttons are present
        expect(
          find.byKey(PermissionDialogKeys.planClearContext),
          findsOneWidget,
        );
        expect(
          find.byKey(PermissionDialogKeys.planApproveAcceptEdits),
          findsOneWidget,
        );
        expect(
          find.byKey(PermissionDialogKeys.planApproveManual),
          findsOneWidget,
        );
        // Verify reject button is present
        expect(
          find.byKey(PermissionDialogKeys.planReject),
          findsOneWidget,
        );
        // Verify button labels
        expect(find.text('Reject'), findsOneWidget);
        expect(find.text('New chat + auto-edit'), findsOneWidget);
        expect(find.text('Auto-edit'), findsOneWidget);
        expect(find.text('Approve'), findsOneWidget);
      });

      testWidgets('hides clear context button when callback not provided',
          (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        // No onClearContextAndAcceptEdits callback
        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Clear context button should NOT be present
        expect(
          find.byKey(PermissionDialogKeys.planClearContext),
          findsNothing,
        );
        // Other buttons should still be present
        expect(
          find.byKey(PermissionDialogKeys.planApproveAcceptEdits),
          findsOneWidget,
        );
        expect(
          find.byKey(PermissionDialogKeys.planApproveManual),
          findsOneWidget,
        );
      });

      testWidgets('shows feedback text input', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify feedback input exists
        expect(
          find.byKey(PermissionDialogKeys.planFeedbackInput),
          findsOneWidget,
        );
        // Verify send button exists
        expect(
          find.byKey(PermissionDialogKeys.planFeedbackSend),
          findsOneWidget,
        );
        // Verify hint text
        expect(
          find.text('Tell Claude what to change...'),
          findsOneWidget,
        );
      });

      testWidgets('Approve button calls onAllow with no updatedPermissions',
          (tester) async {
        List<dynamic>? capturedPermissions;
        var allowCalled = false;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(
          request: request,
          onAllow: ({updatedInput, updatedPermissions}) {
            allowCalled = true;
            capturedPermissions = updatedPermissions;
          },
        ));
        await safePumpAndSettle(tester);

        // Tap Approve
        await tester.tap(find.byKey(PermissionDialogKeys.planApproveManual));
        await tester.pump();

        check(allowCalled).isTrue();
        check(capturedPermissions).isNull();
      });

      testWidgets(
          'Accept edits button calls onAllow with setMode updatedPermissions',
          (tester) async {
        List<dynamic>? capturedPermissions;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(
          request: request,
          onAllow: ({updatedInput, updatedPermissions}) {
            capturedPermissions = updatedPermissions;
          },
        ));
        await safePumpAndSettle(tester);

        // Tap Accept edits
        await tester
            .tap(find.byKey(PermissionDialogKeys.planApproveAcceptEdits));
        await tester.pump();

        check(capturedPermissions).isNotNull();
        check(capturedPermissions!).length.equals(1);
        final perm = capturedPermissions!.first as Map<String, dynamic>;
        check(perm['type'] as String).equals('setMode');
        check(perm['mode'] as String).equals('acceptEdits');
        check(perm['destination'] as String).equals('session');
      });

      testWidgets(
          'Clear context button calls onClearContextAndAcceptEdits with plan text',
          (tester) async {
        String? capturedPlan;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# My Great Plan\n\n1. Do stuff'},
        );

        await tester.pumpWidget(createPlanTestApp(
          request: request,
          onClearContextAndAcceptEdits: (planText) {
            capturedPlan = planText;
          },
        ));
        await safePumpAndSettle(tester);

        // Tap Clear ctx + Accept edits
        await tester.tap(find.byKey(PermissionDialogKeys.planClearContext));
        await tester.pump();

        check(capturedPlan).isNotNull();
        check(capturedPlan!).equals('# My Great Plan\n\n1. Do stuff');
      });

      testWidgets('feedback send button is disabled when text is empty',
          (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify send button is disabled (onPressed is null)
        final sendButton = tester.widget<IconButton>(
          find.byKey(PermissionDialogKeys.planFeedbackSend),
        );
        check(sendButton.onPressed).isNull();
      });

      testWidgets('feedback send button calls onDeny with typed text',
          (tester) async {
        String? denyMessage;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(
          request: request,
          onDeny: (msg) => denyMessage = msg,
        ));
        await safePumpAndSettle(tester);

        // Type feedback
        await tester.enterText(
          find.byKey(PermissionDialogKeys.planFeedbackInput),
          'Please add error handling',
        );
        await tester.pump();

        // Tap send
        await tester.tap(find.byKey(PermissionDialogKeys.planFeedbackSend));
        await tester.pump();

        check(denyMessage).isNotNull();
        check(denyMessage!).equals('Please add error handling');
      });

      testWidgets('feedback text field submit calls onDeny',
          (tester) async {
        String? denyMessage;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(
          request: request,
          onDeny: (msg) => denyMessage = msg,
        ));
        await safePumpAndSettle(tester);

        // Type and submit via keyboard
        await tester.enterText(
          find.byKey(PermissionDialogKeys.planFeedbackInput),
          'Change step 2',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        check(denyMessage).isNotNull();
        check(denyMessage!).equals('Change step 2');
      });

      testWidgets('does not show generic Allow/Deny buttons',
          (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Generic Allow/Deny buttons should NOT be present
        expect(find.text('Allow'), findsNothing);
        expect(find.text('Deny'), findsNothing);
      });

      testWidgets('handles empty plan gracefully', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': ''},
        );

        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Should render without errors
        expect(find.text('Plan for Approval'), findsOneWidget);
        // Should show "No plan provided" message
        expect(find.text('No plan provided.'), findsOneWidget);
        // Buttons should still be present
        expect(
          find.byKey(PermissionDialogKeys.planApproveManual),
          findsOneWidget,
        );
      });

      testWidgets('handles missing plan key gracefully', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {},
        );

        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Should render without errors
        expect(find.text('Plan for Approval'), findsOneWidget);
        expect(find.text('No plan provided.'), findsOneWidget);
        // Buttons should still be present
        expect(
          find.byKey(PermissionDialogKeys.planApproveManual),
          findsOneWidget,
        );
      });

      testWidgets('Reject button calls onDeny', (tester) async {
        String? denyMessage;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(
          request: request,
          onDeny: (msg) => denyMessage = msg,
        ));
        await safePumpAndSettle(tester);

        // Tap Reject
        await tester.tap(find.byKey(PermissionDialogKeys.planReject));
        await tester.pump();

        check(denyMessage).isNotNull();
        check(denyMessage!).contains('denied');
      });

      testWidgets('does not show shield icon for ExitPlanMode',
          (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(createPlanTestApp(request: request));
        await safePumpAndSettle(tester);

        // Should show description icon, not shield
        expect(find.byIcon(Icons.description_outlined), findsOneWidget);
        expect(find.byIcon(Icons.shield_outlined), findsNothing);
      });
    });

    group('UI elements', () {
      testWidgets('displays header with title', (tester) async {
        final request = createFakeRequest();

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.textContaining('Permission Required'), findsOneWidget);
      });

      testWidgets('displays shield icon in header', (tester) async {
        final request = createFakeRequest();

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      });

      testWidgets('content is scrollable for large content', (tester) async {
        // Create a request with large content
        final largeContent = List.generate(50, (i) => 'Line $i').join('\n');
        final request = createFakeRequest(
          toolName: 'Write',
          toolInput: {
            'file_path': '/test/file.txt',
            'content': largeContent,
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Should render without overflow errors
        expect(find.textContaining('Permission Required'), findsOneWidget);
        // Verify SingleChildScrollView is present for scrolling
        expect(find.byType(SingleChildScrollView), findsWidgets);
      });

      testWidgets('tool input text is selectable', (tester) async {
        final request = createFakeRequest(
          toolName: 'Bash',
          toolInput: {'command': 'ls -la'},
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify SelectableText is used for the command
        expect(find.byType(SelectableText), findsWidgets);
      });
    });
  });
}
