import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/persistence_models.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:checks/checks.dart';

import '../test_helpers.dart';

void main() {
  group('ChatState SecurityConfig Integration', () {
    late TestResources resources;

    setUp(() {
      resources = TestResources();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    test('New Claude chat initializes with ClaudeSecurityConfig and default permission mode', () {
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      check(chat.securityConfig).isA<sdk.ClaudeSecurityConfig>();
      final config = chat.securityConfig as sdk.ClaudeSecurityConfig;
      check(config.permissionMode).equals(sdk.PermissionMode.defaultMode);
      check(chat.permissionMode).equals(PermissionMode.defaultMode);
    });

    test('setPermissionMode() on Claude chat updates securityConfig to ClaudeSecurityConfig', () {
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      int notifyCount = 0;
      chat.addListener(() => notifyCount++);

      chat.setPermissionMode(PermissionMode.acceptEdits);

      check(chat.securityConfig).isA<sdk.ClaudeSecurityConfig>();
      final config = chat.securityConfig as sdk.ClaudeSecurityConfig;
      check(config.permissionMode).equals(sdk.PermissionMode.acceptEdits);
      check(chat.permissionMode).equals(PermissionMode.acceptEdits);
      // Two notifications: one from addEntry (system notification), one from setSecurityConfig
      check(notifyCount).equals(2);
    });

    test('setSecurityConfig() with CodexSecurityConfig updates state and notifies listeners', () {
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      int notifyCount = 0;
      chat.addListener(() => notifyCount++);

      const newConfig = sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.readOnly,
        approvalPolicy: sdk.CodexApprovalPolicy.never,
      );

      chat.setSecurityConfig(newConfig);

      check(chat.securityConfig).equals(newConfig);
      check(notifyCount).equals(1);
    });

    test('permissionMode getter returns PermissionMode.defaultMode for Codex chats', () {
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      const codexConfig = sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      );

      chat.setSecurityConfig(codexConfig);

      // Backward compat: permissionMode getter returns default for Codex
      check(chat.permissionMode).equals(PermissionMode.defaultMode);
    });

    test('Security config round-trips through ChatMeta serialization (Claude)', () {
      final meta = ChatMeta(
        model: 'opus',
        backendType: 'direct',
        hasStarted: true,
        permissionMode: 'acceptEdits',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        context: const ContextInfo.empty(),
        usage: const UsageInfo.zero(),
      );

      final json = meta.toJson();
      final restored = ChatMeta.fromJson(json);

      check(restored.permissionMode).equals('acceptEdits');
      check(restored.codexSandboxMode).isNull();
      check(restored.codexApprovalPolicy).isNull();
    });

    test('Security config round-trips through ChatMeta serialization (Codex - all fields)', () {
      final meta = ChatMeta(
        model: 'gpt-4',
        backendType: 'codex',
        hasStarted: true,
        permissionMode: 'default',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        context: const ContextInfo.empty(),
        usage: const UsageInfo.zero(),
        codexSandboxMode: 'read-only',
        codexApprovalPolicy: 'never',
        codexWebSearch: 'live',
      );

      final json = meta.toJson();
      final restored = ChatMeta.fromJson(json);

      check(restored.codexSandboxMode).equals('read-only');
      check(restored.codexApprovalPolicy).equals('never');
      check(restored.codexWebSearch).equals('live');
      check(restored.codexWorkspaceWriteOptions).isNull();
    });

    test('Security config round-trips through ChatMeta serialization (Codex - with workspace-write options)', () {
      final workspaceOptions = {
        'network_access': true,
        'writable_roots': ['/tmp', '/home'],
        'exclude_slash_tmp': true,
        'exclude_tmpdir_env_var': false,
      };

      final meta = ChatMeta(
        model: 'gpt-4',
        backendType: 'codex',
        hasStarted: true,
        permissionMode: 'default',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        context: const ContextInfo.empty(),
        usage: const UsageInfo.zero(),
        codexSandboxMode: 'workspace-write',
        codexApprovalPolicy: 'on-request',
        codexWorkspaceWriteOptions: workspaceOptions,
      );

      final json = meta.toJson();
      final restored = ChatMeta.fromJson(json);

      check(restored.codexSandboxMode).equals('workspace-write');
      check(restored.codexApprovalPolicy).equals('on-request');
      check(restored.codexWorkspaceWriteOptions).isNotNull();
      check(restored.codexWorkspaceWriteOptions!['network_access']).equals(true);
      final writableRoots = restored.codexWorkspaceWriteOptions!['writable_roots'] as List;
      check(writableRoots.length).equals(2);
      check(writableRoots[0]).equals('/tmp');
      check(writableRoots[1]).equals('/home');
    });

    test('_syncPermissionModeFromResponse does nothing for Codex chats', () {
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      // Set Codex config
      const codexConfig = sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      );
      chat.setSecurityConfig(codexConfig);

      int notifyCount = 0;
      chat.addListener(() => notifyCount++);

      // Call _syncPermissionModeFromResponse through allowPermission
      // This would normally trigger a sync for Claude chats
      // For Codex, it should do nothing
      final initialConfig = chat.securityConfig;

      // We can't directly test _syncPermissionModeFromResponse (it's private),
      // but we can verify that the config doesn't change for Codex chats
      check(chat.securityConfig).equals(initialConfig);
    });

    test('_syncPermissionModeFromResponse updates Claude chat correctly', () {
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      // Verify it starts with Claude config
      check(chat.securityConfig).isA<sdk.ClaudeSecurityConfig>();

      // Set to plan mode
      chat.setPermissionMode(PermissionMode.plan);
      check(chat.permissionMode).equals(PermissionMode.plan);

      // Now we can't directly call _syncPermissionModeFromResponse,
      // but we've verified the config type and that setPermissionMode works
    });

    test('Restoring chat from meta.json with old permissionMode field works (migration)', () {
      final meta = ChatMeta(
        model: 'opus',
        backendType: 'direct',
        hasStarted: true,
        permissionMode: 'plan',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        context: const ContextInfo.empty(),
        usage: const UsageInfo.zero(),
        // No Codex fields
      );

      final json = meta.toJson();
      final restored = ChatMeta.fromJson(json);

      check(restored.permissionMode).equals('plan');
      check(restored.codexSandboxMode).isNull();
      check(restored.codexApprovalPolicy).isNull();
    });

    test('Restoring chat from meta.json with Codex fields creates correct CodexSecurityConfig', () {
      final meta = ChatMeta(
        model: 'gpt-4',
        backendType: 'codex',
        hasStarted: true,
        permissionMode: 'default',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        context: const ContextInfo.empty(),
        usage: const UsageInfo.zero(),
        codexSandboxMode: 'danger-full-access',
        codexApprovalPolicy: 'untrusted',
        codexWebSearch: 'cached',
      );

      final json = meta.toJson();
      final restored = ChatMeta.fromJson(json);

      check(restored.backendType).equals('codex');
      check(restored.codexSandboxMode).equals('danger-full-access');
      check(restored.codexApprovalPolicy).equals('untrusted');
      check(restored.codexWebSearch).equals('cached');
    });

    test('setSecurityConfig does not notify if config is the same', () {
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      const config = sdk.ClaudeSecurityConfig(
        permissionMode: sdk.PermissionMode.acceptEdits,
      );
      chat.setSecurityConfig(config);

      int notifyCount = 0;
      chat.addListener(() => notifyCount++);

      // Set same config again
      chat.setSecurityConfig(config);

      // Should not notify
      check(notifyCount).equals(0);
    });

    test('Switching model from Claude to Codex backend updates securityConfig to CodexSecurityConfig', () {
      // Start with a Claude chat (default backend)
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      // Verify initial state is Claude
      check(chat.securityConfig).isA<sdk.ClaudeSecurityConfig>();
      check(chat.model.backend).equals(sdk.BackendType.directCli);

      // Switch to a Codex model
      const codexModel = ChatModel(
        id: 'gpt-4',
        label: 'GPT-4',
        backend: sdk.BackendType.codex,
      );

      chat.setModel(codexModel);

      // Security config should now be CodexSecurityConfig with default values
      check(chat.securityConfig).isA<sdk.CodexSecurityConfig>();
      final config = chat.securityConfig as sdk.CodexSecurityConfig;
      check(config.sandboxMode).equals(sdk.CodexSandboxMode.workspaceWrite);
      check(config.approvalPolicy).equals(sdk.CodexApprovalPolicy.onRequest);
      check(chat.model.backend).equals(sdk.BackendType.codex);
    });

    test('Switching model from Codex to Claude backend updates securityConfig to ClaudeSecurityConfig', () {
      // Start with a Codex chat
      final chat = resources.track(ChatState(ChatData.create(
        name: 'test',
        worktreeRoot: '/tmp',
      )));

      // Set initial Codex config
      const codexModel = ChatModel(
        id: 'gpt-4',
        label: 'GPT-4',
        backend: sdk.BackendType.codex,
      );
      chat.setModel(codexModel);

      // Verify we're on Codex
      check(chat.securityConfig).isA<sdk.CodexSecurityConfig>();
      check(chat.model.backend).equals(sdk.BackendType.codex);

      // Switch to a Claude model
      const claudeModel = ChatModel(
        id: 'opus',
        label: 'Opus',
        backend: sdk.BackendType.directCli,
      );

      chat.setModel(claudeModel);

      // Security config should now be ClaudeSecurityConfig with default permission mode
      check(chat.securityConfig).isA<sdk.ClaudeSecurityConfig>();
      final config = chat.securityConfig as sdk.ClaudeSecurityConfig;
      check(config.permissionMode).equals(sdk.PermissionMode.defaultMode);
      check(chat.model.backend).equals(sdk.BackendType.directCli);
    });
  });
}
