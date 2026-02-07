import 'package:agent_sdk_core/agent_sdk_core.dart' show ToolKind;
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolKind.fromToolName', () {
    test('maps Bash to execute', () {
      check(ToolKind.fromToolName('Bash')).equals(ToolKind.execute);
    });

    test('maps Read to read', () {
      check(ToolKind.fromToolName('Read')).equals(ToolKind.read);
    });

    test('maps Write to edit', () {
      check(ToolKind.fromToolName('Write')).equals(ToolKind.edit);
    });

    test('maps Edit to edit', () {
      check(ToolKind.fromToolName('Edit')).equals(ToolKind.edit);
    });

    test('maps NotebookEdit to edit', () {
      check(ToolKind.fromToolName('NotebookEdit')).equals(ToolKind.edit);
    });

    test('maps Glob to search', () {
      check(ToolKind.fromToolName('Glob')).equals(ToolKind.search);
    });

    test('maps Grep to search', () {
      check(ToolKind.fromToolName('Grep')).equals(ToolKind.search);
    });

    test('maps WebFetch to fetch', () {
      check(ToolKind.fromToolName('WebFetch')).equals(ToolKind.fetch);
    });

    test('maps WebSearch to browse', () {
      check(ToolKind.fromToolName('WebSearch')).equals(ToolKind.browse);
    });

    test('maps Task to think', () {
      check(ToolKind.fromToolName('Task')).equals(ToolKind.think);
    });

    test('maps AskUserQuestion to ask', () {
      check(ToolKind.fromToolName('AskUserQuestion')).equals(ToolKind.ask);
    });

    test('maps TodoWrite to memory', () {
      check(ToolKind.fromToolName('TodoWrite')).equals(ToolKind.memory);
    });

    test('maps mcp__ prefixed tools to mcp', () {
      check(ToolKind.fromToolName('mcp__server__tool'))
          .equals(ToolKind.mcp);
    });

    test('maps mcp__ with various suffixes to mcp', () {
      check(ToolKind.fromToolName('mcp__flutter-test__run_tests'))
          .equals(ToolKind.mcp);
      check(ToolKind.fromToolName('mcp__a__b')).equals(ToolKind.mcp);
    });

    test('maps unknown tool names to other', () {
      check(ToolKind.fromToolName('UnknownTool')).equals(ToolKind.other);
      check(ToolKind.fromToolName('CustomTool')).equals(ToolKind.other);
      check(ToolKind.fromToolName('')).equals(ToolKind.other);
    });

    test('is case-sensitive', () {
      check(ToolKind.fromToolName('bash')).equals(ToolKind.other);
      check(ToolKind.fromToolName('BASH')).equals(ToolKind.other);
      check(ToolKind.fromToolName('read')).equals(ToolKind.other);
    });

    test('covers all mapped tool names', () {
      final mappings = <String, ToolKind>{
        'Bash': ToolKind.execute,
        'Read': ToolKind.read,
        'Write': ToolKind.edit,
        'Edit': ToolKind.edit,
        'NotebookEdit': ToolKind.edit,
        'Glob': ToolKind.search,
        'Grep': ToolKind.search,
        'WebFetch': ToolKind.fetch,
        'WebSearch': ToolKind.browse,
        'Task': ToolKind.think,
        'AskUserQuestion': ToolKind.ask,
        'TodoWrite': ToolKind.memory,
      };

      for (final entry in mappings.entries) {
        check(ToolKind.fromToolName(entry.key))
            .has((k) => k, 'for ${entry.key}')
            .equals(entry.value);
      }
    });
  });
}
