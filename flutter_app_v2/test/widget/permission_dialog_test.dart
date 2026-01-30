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
    }) {
      return MaterialApp(
        home: Scaffold(
          body: PermissionDialog(
            request: request,
            onAllow: onAllow ?? ({updatedInput, updatedPermissions}) {},
            onDeny: onDeny ?? (_) {},
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
      testWidgets('shows plan content in scrollable box', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {
            'plan': '## Implementation Plan\n\n1. First step\n2. Second step',
          },
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify plan header is displayed
        expect(find.text('Plan for Approval'), findsOneWidget);
        // Verify plan content is displayed
        expect(find.textContaining('Implementation Plan'), findsOneWidget);
      });

      testWidgets('shows expand button', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# My Plan\nStep 1'},
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Verify expand icon is present
        expect(
          find.byKey(PermissionDialogKeys.expandPlanButton),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.open_in_full), findsOneWidget);
      });

      testWidgets('expand button shows expanded markdown view', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {
            'plan': '# My Plan\n\n- Item 1\n- Item 2\n- Item 3',
          },
        );

        // Need to wrap in Scaffold with Expanded to handle expanded view
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PermissionDialog(
                request: request,
                onAllow: ({updatedInput, updatedPermissions}) {},
                onDeny: (_) {},
              ),
            ),
          ),
        ));
        await safePumpAndSettle(tester);

        // Tap expand button
        await tester.tap(find.byIcon(Icons.open_in_full));
        await tester.pumpAndSettle();

        // Verify collapse button is now visible (replaces expand)
        expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);
        // Verify plan content is still visible
        expect(find.textContaining('My Plan'), findsOneWidget);
        // Allow/Deny buttons should still be present
        expect(find.text('Allow'), findsOneWidget);
        expect(find.text('Deny'), findsOneWidget);
      });

      testWidgets('collapse button returns to compact view', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Test Plan'},
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PermissionDialog(
                request: request,
                onAllow: ({updatedInput, updatedPermissions}) {},
                onDeny: (_) {},
              ),
            ),
          ),
        ));
        await safePumpAndSettle(tester);

        // Expand
        await tester.tap(find.byIcon(Icons.open_in_full));
        await tester.pumpAndSettle();

        // Verify expanded state
        expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);

        // Collapse
        await tester.tap(find.byIcon(Icons.close_fullscreen));
        await tester.pumpAndSettle();

        // Verify compact state restored
        expect(find.byIcon(Icons.open_in_full), findsOneWidget);
        expect(find.text('Plan for Approval'), findsOneWidget);
      });

      testWidgets('allow works from expanded view', (tester) async {
        var allowCalled = false;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PermissionDialog(
                request: request,
                onAllow: ({updatedInput, updatedPermissions}) {
                  allowCalled = true;
                },
                onDeny: (_) {},
              ),
            ),
          ),
        ));
        await safePumpAndSettle(tester);

        // Expand
        await tester.tap(find.byIcon(Icons.open_in_full));
        await tester.pumpAndSettle();

        // Tap Allow
        await tester.tap(find.text('Allow'));
        await tester.pump();

        check(allowCalled).isTrue();
      });

      testWidgets('deny works from expanded view', (tester) async {
        String? denyMessage;
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': '# Plan'},
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PermissionDialog(
                request: request,
                onAllow: ({updatedInput, updatedPermissions}) {},
                onDeny: (msg) => denyMessage = msg,
              ),
            ),
          ),
        ));
        await safePumpAndSettle(tester);

        // Expand
        await tester.tap(find.byIcon(Icons.open_in_full));
        await tester.pumpAndSettle();

        // Tap Deny
        await tester.tap(find.text('Deny'));
        await tester.pump();

        check(denyMessage).isNotNull();
        check(denyMessage!).contains('denied');
      });

      testWidgets('handles empty plan gracefully', (tester) async {
        final request = createFakeRequest(
          toolName: 'ExitPlanMode',
          toolInput: {'plan': ''},
        );

        await tester.pumpWidget(createTestApp(request: request));
        await safePumpAndSettle(tester);

        // Should render without errors
        expect(find.text('Plan for Approval'), findsOneWidget);
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
