import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:cc_insights_v2/widgets/security_badge.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecurityBadge', () {
    testWidgets('read-only sandbox shows green Read Only badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.readOnly,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.green.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Read Only'));
      check(textWidget.style?.color).equals(Colors.green);

      expect(find.byIcon(Icons.verified_user), findsOneWidget);
    });

    testWidgets('workspace-write + on-request shows green Sandboxed badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.green.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Sandboxed'));
      check(textWidget.style?.color).equals(Colors.green);

      expect(find.byIcon(Icons.verified_user), findsOneWidget);
    });

    testWidgets('workspace-write + untrusted shows green Sandboxed badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.untrusted,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.green.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Sandboxed'));
      check(textWidget.style?.color).equals(Colors.green);

      expect(find.byIcon(Icons.verified_user), findsOneWidget);
    });

    testWidgets('workspace-write + never shows orange Auto-approve badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.never,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.orange.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Auto-approve'));
      check(textWidget.style?.color).equals(Colors.orange);

      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('workspace-write + on-failure shows orange Auto-approve badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.workspaceWrite,
        approvalPolicy: CodexApprovalPolicy.onFailure,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.orange.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Auto-approve'));
      check(textWidget.style?.color).equals(Colors.orange);

      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('full access + on-request shows orange Unrestricted badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.dangerFullAccess,
        approvalPolicy: CodexApprovalPolicy.onRequest,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.orange.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Unrestricted'));
      check(textWidget.style?.color).equals(Colors.orange);

      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('full access + untrusted shows orange Unrestricted badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.dangerFullAccess,
        approvalPolicy: CodexApprovalPolicy.untrusted,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.orange.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Unrestricted'));
      check(textWidget.style?.color).equals(Colors.orange);

      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('full access + never shows red Unrestricted badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.dangerFullAccess,
        approvalPolicy: CodexApprovalPolicy.never,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.red.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Unrestricted'));
      check(textWidget.style?.color).equals(Colors.red);

      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('full access + on-failure shows red Unrestricted badge', (tester) async {
      // Arrange
      const config = CodexSecurityConfig(
        sandboxMode: CodexSandboxMode.dangerFullAccess,
        approvalPolicy: CodexApprovalPolicy.onFailure,
      );

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityBadge(config: config),
          ),
        ),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(SecurityBadgeKeys.badge),
      );
      final decoration = badge.decoration as BoxDecoration;
      check(decoration.color).equals(Colors.red.withValues(alpha: 0.15));

      final textWidget = tester.widget<Text>(find.text('Unrestricted'));
      check(textWidget.style?.color).equals(Colors.red);

      expect(find.byIcon(Icons.warning), findsOneWidget);
    });
  });
}
