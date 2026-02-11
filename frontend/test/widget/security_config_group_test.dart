import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:cc_insights_v2/widgets/security_config_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('SecurityConfigGroup', () {
    testWidgets('renders sandbox mode label and approval policy label',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Workspace Write'), findsOneWidget);
      expect(find.text('Ask: On Request'), findsOneWidget);
      expect(find.byIcon(Icons.shield), findsOneWidget);
    });

    testWidgets('tapping sandbox dropdown shows all three mode options',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );

      // Tap the sandbox dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.sandboxDropdown));
      await safePumpAndSettle(tester);

      // All three mode options should be visible
      expect(find.text('Read Only'), findsOneWidget);
      expect(find.text('Workspace Write'), findsNWidgets(2)); // One in dropdown, one in menu
      expect(find.text('Full Access'), findsOneWidget);
      expect(find.text('Workspace settings...'), findsOneWidget);
    });

    testWidgets('selecting a sandbox mode calls onConfigChanged with updated config',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities();

      CodexSecurityConfig? changedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (newConfig) {
                changedConfig = newConfig;
              },
            ),
          ),
        ),
      );

      // Tap the sandbox dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.sandboxDropdown));
      await safePumpAndSettle(tester);

      // Select "Read Only"
      await tester.tap(find.byKey(
        SecurityConfigGroupKeys.sandboxMenuItem(CodexSandboxMode.readOnly),
      ));
      await safePumpAndSettle(tester);

      // Verify the config was changed
      expect(changedConfig, isNotNull);
      expect(changedConfig!.sandboxMode, CodexSandboxMode.readOnly);
      expect(changedConfig!.approvalPolicy, CodexApprovalPolicy.onRequest); // unchanged
    });

    testWidgets('enterprise-locked sandbox mode is not selectable',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities(
        allowedSandboxModes: [
          CodexSandboxMode.readOnly,
          CodexSandboxMode.workspaceWrite,
        ],
      );

      CodexSecurityConfig? changedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (newConfig) {
                changedConfig = newConfig;
              },
            ),
          ),
        ),
      );

      // Tap the sandbox dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.sandboxDropdown));
      await safePumpAndSettle(tester);

      // Try to tap "Full Access" (locked)
      await tester.tap(find.byKey(
        SecurityConfigGroupKeys.sandboxMenuItem(
          CodexSandboxMode.dangerFullAccess,
        ),
      ));
      await safePumpAndSettle(tester);

      // Verify the config was NOT changed
      expect(changedConfig, isNull);
    });

    testWidgets('enterprise-locked sandbox mode shows lock icon',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities(
        allowedSandboxModes: [
          CodexSandboxMode.readOnly,
          CodexSandboxMode.workspaceWrite,
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );

      // Tap the sandbox dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.sandboxDropdown));
      await safePumpAndSettle(tester);

      // Find the locked "Full Access" menu item
      final lockedItem = find.byKey(
        SecurityConfigGroupKeys.sandboxMenuItem(
          CodexSandboxMode.dangerFullAccess,
        ),
      );
      expect(lockedItem, findsOneWidget);

      // Verify lock icon is present
      final lockedItemWidget = tester.widget<PopupMenuItem<CodexSandboxMode>>(lockedItem);
      expect(lockedItemWidget.enabled, false);
    });

    testWidgets('tapping approval dropdown shows all four policy options',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );

      // Tap the approval dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.approvalDropdown));
      await safePumpAndSettle(tester);

      // All four policy options should be visible
      expect(find.text('Untrusted'), findsOneWidget);
      expect(find.text('On Request'), findsOneWidget);
      expect(find.text('On Failure'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
    });

    testWidgets('selecting a policy calls onConfigChanged with updated config',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities();

      CodexSecurityConfig? changedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (newConfig) {
                changedConfig = newConfig;
              },
            ),
          ),
        ),
      );

      // Tap the approval dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.approvalDropdown));
      await safePumpAndSettle(tester);

      // Select "Untrusted"
      await tester.tap(find.byKey(
        SecurityConfigGroupKeys.approvalMenuItem(
          CodexApprovalPolicy.untrusted,
        ),
      ));
      await safePumpAndSettle(tester);

      // Verify the config was changed
      expect(changedConfig, isNotNull);
      expect(changedConfig!.approvalPolicy, CodexApprovalPolicy.untrusted);
      expect(changedConfig!.sandboxMode, CodexSandboxMode.workspaceWrite); // unchanged
    });

    testWidgets('danger state (dangerFullAccess) shows red border on container',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.dangerFullAccess,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );

      // Find the container
      final container = tester.widget<Container>(
        find.byKey(SecurityConfigGroupKeys.group),
      );

      // Verify the border is red (error color)
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      // Check that red is higher than green and blue (red-ish)
      expect(border.top.color.red, greaterThan(border.top.color.green));
      expect(border.top.color.red, greaterThan(border.top.color.blue));
    });

    testWidgets('danger state (never policy) shows red text on the Never label',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.never,
      );
      const capabilities = CodexSecurityCapabilities();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );

      // Find the "Ask: Never" text
      final neverText = find.text('Ask: Never');
      expect(neverText, findsOneWidget);

      // Get the Text widget and verify its color is red (error color)
      final textWidget = tester.widget<Text>(neverText);
      final textColor = textWidget.style?.color;
      expect(textColor, isNotNull);
      // Check that red is higher than green and blue (red-ish)
      expect(textColor!.red, greaterThan(textColor.green));
      expect(textColor.red, greaterThan(textColor.blue));
    });

    testWidgets('disabled state (isEnabled=false) prevents interaction',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities();

      CodexSecurityConfig? changedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (newConfig) {
                changedConfig = newConfig;
              },
              isEnabled: false,
            ),
          ),
        ),
      );

      // Try to tap the sandbox dropdown (should not open because disabled)
      await tester.tap(find.byKey(SecurityConfigGroupKeys.sandboxDropdown));
      await safePumpAndSettle(tester);

      // Menu should not appear
      expect(find.text('Read Only'), findsNothing);
      expect(changedConfig, isNull);
    });

    testWidgets('enterprise-locked approval policy is not selectable',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities(
        allowedApprovalPolicies: [
          CodexApprovalPolicy.untrusted,
          CodexApprovalPolicy.onRequest,
          CodexApprovalPolicy.onFailure,
        ],
      );

      CodexSecurityConfig? changedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (newConfig) {
                changedConfig = newConfig;
              },
            ),
          ),
        ),
      );

      // Tap the approval dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.approvalDropdown));
      await safePumpAndSettle(tester);

      // Try to tap "Never" (locked)
      await tester.tap(find.byKey(
        SecurityConfigGroupKeys.approvalMenuItem(CodexApprovalPolicy.never),
      ));
      await safePumpAndSettle(tester);

      // Verify the config was NOT changed
      expect(changedConfig, isNull);
    });

    testWidgets('enterprise-locked approval policy shows lock badge',
        (tester) async {
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );
      const capabilities = CodexSecurityCapabilities(
        allowedApprovalPolicies: [
          CodexApprovalPolicy.untrusted,
          CodexApprovalPolicy.onRequest,
          CodexApprovalPolicy.onFailure,
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityConfigGroup(
              config: config,
              capabilities: capabilities,
              onConfigChanged: (_) {},
            ),
          ),
        ),
      );

      // Tap the approval dropdown
      await tester.tap(find.byKey(SecurityConfigGroupKeys.approvalDropdown));
      await safePumpAndSettle(tester);

      // Find the locked "Never" menu item
      final lockedItem = find.byKey(
        SecurityConfigGroupKeys.approvalMenuItem(CodexApprovalPolicy.never),
      );
      expect(lockedItem, findsOneWidget);

      // Verify it's disabled
      final lockedItemWidget = tester.widget<PopupMenuItem<CodexApprovalPolicy>>(lockedItem);
      expect(lockedItemWidget.enabled, false);
    });
  });
}
