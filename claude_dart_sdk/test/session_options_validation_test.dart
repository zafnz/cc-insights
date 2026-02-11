import 'package:claude_sdk/claude_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('OptionsValidationResult', () {
    test('empty result has no warnings', () {
      const result = OptionsValidationResult.empty;

      expect(result.warnings, isEmpty);
      expect(result.isClean, isTrue);
    });

    test('result with warnings is not clean', () {
      const result = OptionsValidationResult(['something ignored']);

      expect(result.warnings, hasLength(1));
      expect(result.isClean, isFalse);
    });
  });

  group('SessionOptions.validateForCli', () {
    test('returns clean result for supported-only options', () {
      const options = SessionOptions(
        model: 'sonnet',
        permissionMode: PermissionMode.acceptEdits,
        settingSources: ['user', 'project', 'local'],
        maxTurns: 10,
        maxBudgetUsd: 5.0,
        resume: 'sess-123',
        includePartialMessages: true,
        systemPrompt: CustomSystemPrompt('Be helpful'),
        mcpServers: {},
      );

      final result = options.validateForCli();

      expect(result.isClean, isTrue);
    });

    test('returns clean result for empty options', () {
      const options = SessionOptions();

      final result = options.validateForCli();

      expect(result.isClean, isTrue);
    });

    test('warns about reasoningEffort', () {
      const options = SessionOptions(reasoningEffort: ReasoningEffort.high);

      final result = options.validateForCli();

      expect(result.isClean, isFalse);
      expect(result.warnings, contains(contains('reasoningEffort')));
    });

    test('warns about tools', () {
      const options = SessionOptions(
        tools: ToolListConfig(['Bash', 'Read']),
      );

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('tools')));
    });

    test('warns about plugins', () {
      final options = SessionOptions(plugins: [
        {'name': 'test'}
      ]);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('plugins')));
    });

    test('warns about hooks', () {
      final options = SessionOptions(hooks: {
        'PreToolUse': [const HookConfig(matcher: 'Bash')]
      });

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('hooks')));
    });

    test('warns about agents', () {
      final options = SessionOptions(agents: {'sub': {}});

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('agents')));
    });

    test('warns about sandbox', () {
      final options = SessionOptions(sandbox: {'type': 'docker'});

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('sandbox')));
    });

    test('does not warn about settingSources (supported by CLI)', () {
      const options = SessionOptions(settingSources: ['project']);

      final result = options.validateForCli();

      expect(result.warnings, isNot(contains(contains('settingSources'))));
    });

    test('warns about outputFormat', () {
      final options = SessionOptions(outputFormat: {'type': 'json'});

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('outputFormat')));
    });

    test('warns about fallbackModel', () {
      const options = SessionOptions(fallbackModel: 'haiku');

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('fallbackModel')));
    });

    test('warns about allowedTools', () {
      const options = SessionOptions(allowedTools: ['Bash']);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('allowedTools')));
    });

    test('warns about disallowedTools', () {
      const options = SessionOptions(disallowedTools: ['Write']);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('disallowedTools')));
    });

    test('warns about betas', () {
      const options = SessionOptions(betas: ['interleaved-thinking']);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('betas')));
    });

    test('warns about enableFileCheckpointing', () {
      const options = SessionOptions(enableFileCheckpointing: true);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('enableFileCheckpointing')));
    });

    test('warns about additionalDirectories', () {
      const options = SessionOptions(additionalDirectories: ['/tmp']);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('additionalDirectories')));
    });

    test('warns about maxThinkingTokens', () {
      const options = SessionOptions(maxThinkingTokens: 4096);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('maxThinkingTokens')));
    });

    test('warns about resumeSessionAt', () {
      const options = SessionOptions(resumeSessionAt: 'msg-uuid');

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('resumeSessionAt')));
    });

    test('warns about strictMcpConfig', () {
      const options = SessionOptions(strictMcpConfig: true);

      final result = options.validateForCli();

      expect(result.warnings, contains(contains('strictMcpConfig')));
    });

    test('warns about allowDangerouslySkipPermissions', () {
      const options = SessionOptions(allowDangerouslySkipPermissions: true);

      final result = options.validateForCli();

      expect(
        result.warnings,
        contains(contains('allowDangerouslySkipPermissions')),
      );
    });

    test('warns about permissionPromptToolName', () {
      const options = SessionOptions(permissionPromptToolName: 'my_tool');

      final result = options.validateForCli();

      expect(
        result.warnings,
        contains(contains('permissionPromptToolName')),
      );
    });

    test('accumulates multiple warnings', () {
      final options = SessionOptions(
        reasoningEffort: ReasoningEffort.high,
        tools: const ToolListConfig(['Bash']),
        hooks: {
          'PreToolUse': [const HookConfig()]
        },
        agents: {'sub': {}},
      );

      final result = options.validateForCli();

      expect(result.warnings.length, greaterThanOrEqualTo(4));
    });
  });

  group('SessionOptions.validateForCodex', () {
    test('returns clean result for supported-only options', () {
      const options = SessionOptions(
        model: 'o3-mini',
        resume: 'thread-abc',
        reasoningEffort: ReasoningEffort.high,
      );

      final result = options.validateForCodex();

      expect(result.isClean, isTrue);
    });

    test('returns clean result for empty options', () {
      const options = SessionOptions();

      final result = options.validateForCodex();

      expect(result.isClean, isTrue);
    });

    test('warns about permissionMode', () {
      const options = SessionOptions(
        permissionMode: PermissionMode.acceptEdits,
      );

      final result = options.validateForCodex();

      expect(result.isClean, isFalse);
      expect(result.warnings, contains(contains('permissionMode')));
    });

    test('does not warn about systemPrompt (now supported via baseInstructions)', () {
      const options = SessionOptions(
        systemPrompt: CustomSystemPrompt('Be helpful'),
      );

      final result = options.validateForCodex();

      expect(result.warnings, isNot(contains(contains('systemPrompt'))));
    });

    test('warns about maxTurns', () {
      const options = SessionOptions(maxTurns: 10);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('maxTurns')));
    });

    test('warns about maxBudgetUsd', () {
      const options = SessionOptions(maxBudgetUsd: 5.0);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('maxBudgetUsd')));
    });

    test('warns about includePartialMessages', () {
      const options = SessionOptions(includePartialMessages: true);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('includePartialMessages')));
    });

    test('warns about mcpServers', () {
      final options = SessionOptions(mcpServers: {
        'test': const McpStdioServerConfig(command: 'node'),
      });

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('mcpServers')));
    });

    test('warns about hooks', () {
      final options = SessionOptions(hooks: {
        'PreToolUse': [const HookConfig()]
      });

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('hooks')));
    });

    test('warns about agents', () {
      final options = SessionOptions(agents: {'sub': {}});

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('agents')));
    });

    test('warns about tools', () {
      const options = SessionOptions(
        tools: ToolListConfig(['Bash']),
      );

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('tools')));
    });

    test('warns about sandbox', () {
      final options = SessionOptions(sandbox: {'type': 'docker'});

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('sandbox')));
    });

    test('warns about settingSources', () {
      const options = SessionOptions(settingSources: ['project']);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('settingSources')));
    });

    test('warns about outputFormat', () {
      final options = SessionOptions(outputFormat: {'type': 'json'});

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('outputFormat')));
    });

    test('warns about fallbackModel', () {
      const options = SessionOptions(fallbackModel: 'haiku');

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('fallbackModel')));
    });

    test('warns about allowedTools', () {
      const options = SessionOptions(allowedTools: ['Bash']);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('allowedTools')));
    });

    test('warns about disallowedTools', () {
      const options = SessionOptions(disallowedTools: ['Write']);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('disallowedTools')));
    });

    test('warns about betas', () {
      const options = SessionOptions(betas: ['interleaved-thinking']);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('betas')));
    });

    test('warns about plugins', () {
      final options = SessionOptions(plugins: [
        {'name': 'test'}
      ]);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('plugins')));
    });

    test('warns about enableFileCheckpointing', () {
      const options = SessionOptions(enableFileCheckpointing: true);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('enableFileCheckpointing')));
    });

    test('warns about additionalDirectories', () {
      const options = SessionOptions(additionalDirectories: ['/tmp']);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('additionalDirectories')));
    });

    test('warns about maxThinkingTokens', () {
      const options = SessionOptions(maxThinkingTokens: 4096);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('maxThinkingTokens')));
    });

    test('warns about resumeSessionAt', () {
      const options = SessionOptions(resumeSessionAt: 'msg-uuid');

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('resumeSessionAt')));
    });

    test('warns about strictMcpConfig', () {
      const options = SessionOptions(strictMcpConfig: true);

      final result = options.validateForCodex();

      expect(result.warnings, contains(contains('strictMcpConfig')));
    });

    test('warns about allowDangerouslySkipPermissions', () {
      const options = SessionOptions(allowDangerouslySkipPermissions: true);

      final result = options.validateForCodex();

      expect(
        result.warnings,
        contains(contains('allowDangerouslySkipPermissions')),
      );
    });

    test('warns about permissionPromptToolName', () {
      const options = SessionOptions(permissionPromptToolName: 'my_tool');

      final result = options.validateForCodex();

      expect(
        result.warnings,
        contains(contains('permissionPromptToolName')),
      );
    });

    test('accumulates multiple warnings', () {
      const options = SessionOptions(
        permissionMode: PermissionMode.acceptEdits,
        systemPrompt: CustomSystemPrompt('test'),
        maxTurns: 10,
        maxBudgetUsd: 5.0,
        includePartialMessages: true,
      );

      final result = options.validateForCodex();

      // systemPrompt is now supported (mapped to baseInstructions),
      // so only 4 warnings: permissionMode, maxTurns, maxBudgetUsd,
      // includePartialMessages.
      expect(result.warnings.length, greaterThanOrEqualTo(4));
    });
  });

  group('cross-backend validation consistency', () {
    test('model is supported by both backends', () {
      const options = SessionOptions(model: 'sonnet');

      expect(options.validateForCli().isClean, isTrue);
      expect(options.validateForCodex().isClean, isTrue);
    });

    test('resume is supported by both backends', () {
      const options = SessionOptions(resume: 'sess-123');

      expect(options.validateForCli().isClean, isTrue);
      expect(options.validateForCodex().isClean, isTrue);
    });

    test('reasoningEffort is CLI-only unsupported', () {
      const options = SessionOptions(reasoningEffort: ReasoningEffort.high);

      expect(options.validateForCli().isClean, isFalse);
      expect(options.validateForCodex().isClean, isTrue);
    });

    test('permissionMode is Codex-only unsupported', () {
      const options = SessionOptions(
        permissionMode: PermissionMode.acceptEdits,
      );

      expect(options.validateForCli().isClean, isTrue);
      expect(options.validateForCodex().isClean, isFalse);
    });

    test('fields unsupported by both produce warnings from both', () {
      final options = SessionOptions(
        tools: const ToolListConfig(['Bash']),
        hooks: {
          'PreToolUse': [const HookConfig()]
        },
        agents: {'sub': {}},
      );

      final cliResult = options.validateForCli();
      final codexResult = options.validateForCodex();

      expect(cliResult.warnings, contains(contains('tools')));
      expect(cliResult.warnings, contains(contains('hooks')));
      expect(cliResult.warnings, contains(contains('agents')));

      expect(codexResult.warnings, contains(contains('tools')));
      expect(codexResult.warnings, contains(contains('hooks')));
      expect(codexResult.warnings, contains(contains('agents')));
    });
  });
}
