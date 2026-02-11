import 'package:agent_sdk_core/agent_sdk_core.dart' as sdk;
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatState - Security Configuration Notifications', () {
    test('changing Codex sandbox mode adds system notification', () {
      // Arrange
      final chat = ChatState.create(
        name: 'Test Chat',
        worktreeRoot: '/test',
      );
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.readOnly,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));
      final initialEntryCount = chat.data.primaryConversation.entries.length;

      // Act
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));

      // Assert
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(initialEntryCount + 1);
      final lastEntry = entries.last;
      check(lastEntry).isA<SystemNotificationEntry>();
      final notification = lastEntry as SystemNotificationEntry;
      check(notification.message).equals('Sandbox changed to Workspace Write');
    });

    test('changing Codex approval policy adds system notification', () {
      // Arrange
      final chat = ChatState.create(
        name: 'Test Chat',
        worktreeRoot: '/test',
      );
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));
      final initialEntryCount = chat.data.primaryConversation.entries.length;

      // Act
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.never,
      ));

      // Assert
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(initialEntryCount + 1);
      final lastEntry = entries.last;
      check(lastEntry).isA<SystemNotificationEntry>();
      final notification = lastEntry as SystemNotificationEntry;
      check(notification.message).equals('Approval policy set to Never');
    });

    test('changing both sandbox mode and approval policy adds combined notification', () {
      // Arrange
      final chat = ChatState.create(
        name: 'Test Chat',
        worktreeRoot: '/test',
      );
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.readOnly,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));
      final initialEntryCount = chat.data.primaryConversation.entries.length;

      // Act
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.dangerFullAccess,
        approvalPolicy: sdk.CodexApprovalPolicy.never,
      ));

      // Assert
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(initialEntryCount + 1);
      final lastEntry = entries.last;
      check(lastEntry).isA<SystemNotificationEntry>();
      final notification = lastEntry as SystemNotificationEntry;
      check(notification.message).equals('Sandbox changed to Full Access. Approval policy set to Never');
    });

    test('changing Claude permission mode adds system notification', () {
      // Arrange
      final chat = ChatState.create(
        name: 'Test Chat',
        worktreeRoot: '/test',
      );
      chat.setSecurityConfig(const sdk.ClaudeSecurityConfig(
        permissionMode: sdk.PermissionMode.defaultMode,
      ));
      final initialEntryCount = chat.data.primaryConversation.entries.length;

      // Act
      chat.setSecurityConfig(const sdk.ClaudeSecurityConfig(
        permissionMode: sdk.PermissionMode.acceptEdits,
      ));

      // Assert
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(initialEntryCount + 1);
      final lastEntry = entries.last;
      check(lastEntry).isA<SystemNotificationEntry>();
      final notification = lastEntry as SystemNotificationEntry;
      check(notification.message).equals('Permission mode changed to acceptEdits');
    });

    test('setting same config does not add notification', () {
      // Arrange
      final chat = ChatState.create(
        name: 'Test Chat',
        worktreeRoot: '/test',
      );
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));
      final initialEntryCount = chat.data.primaryConversation.entries.length;

      // Act - set the same config again
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      ));

      // Assert - no new entry
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(initialEntryCount);
    });

    test('changing only workspace write options does not add notification', () {
      // Arrange
      final chat = ChatState.create(
        name: 'Test Chat',
        worktreeRoot: '/test',
      );
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
        workspaceWriteOptions: sdk.CodexWorkspaceWriteOptions(
          networkAccess: false,
        ),
      ));
      final initialEntryCount = chat.data.primaryConversation.entries.length;

      // Act - change only workspace write options (not sandbox/approval)
      chat.setSecurityConfig(const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
        workspaceWriteOptions: sdk.CodexWorkspaceWriteOptions(
          networkAccess: true,
        ),
      ));

      // Assert - no notification since sandbox and approval didn't change
      final entries = chat.data.primaryConversation.entries;
      check(entries.length).equals(initialEntryCount);
    });
  });
}
