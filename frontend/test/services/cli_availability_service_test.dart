import 'dart:io';

import 'package:cc_insights_v2/models/agent_config.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('custom path expands tilde and finds executable', () async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return;
    }

    final tempDir = Directory(
      p.join(home, 'ccinsights_cli_test_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await tempDir.create(recursive: true);
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final executable = File(p.join(tempDir.path, 'acp'));
    await executable.writeAsString('#!/bin/sh\necho ok\n');
    await Process.run('chmod', ['+x', executable.path]);

    final tildePath = executable.path.replaceFirst(home, '~');
    final service = CliAvailabilityService();
    final agent = AgentConfig(
      id: 'test-acp',
      name: 'Test ACP',
      driver: 'acp',
      cliPath: tildePath,
    );
    await service.checkAgents([agent]);

    expect(service.isAgentAvailable('test-acp'), isTrue);
  });

  test('custom path can be a directory containing the executable', () async {
    final tempDir = await Directory.systemTemp.createTemp('cli-dir-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final executable = File(p.join(tempDir.path, 'acp'));
    await executable.writeAsString('#!/bin/sh\necho ok\n');
    await Process.run('chmod', ['+x', executable.path]);

    final service = CliAvailabilityService();
    final agent = AgentConfig(
      id: 'test-acp',
      name: 'Test ACP',
      driver: 'acp',
      cliPath: tempDir.path,
    );
    await service.checkAgents([agent]);

    expect(service.isAgentAvailable('test-acp'), isTrue);
  });

  test('checkClaude sets claudeAvailable', () async {
    final service = CliAvailabilityService();
    // Without a valid claude path, this should still work (just may not find it)
    await service.checkClaude(customPath: '/nonexistent/path');
    expect(service.claudeAvailable, isFalse);
    expect(service.checked, isTrue);
  });

  test('checkAgents sets claudeAvailable from claude-driver agents', () async {
    final service = CliAvailabilityService();
    // Non-existent path — claude should not be available
    final agent = AgentConfig(
      id: 'test-claude',
      name: 'Test Claude',
      driver: 'claude',
      cliPath: '/nonexistent/claude',
    );
    await service.checkAgents([agent]);

    expect(service.claudeAvailable, isFalse);
    expect(service.isAgentAvailable('test-claude'), isFalse);
  });
}
