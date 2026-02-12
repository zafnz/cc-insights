import 'dart:io';

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
    await service.checkAll(acpPath: tildePath);

    expect(service.acpAvailable, isTrue);
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
    await service.checkAll(acpPath: tempDir.path);

    expect(service.acpAvailable, isTrue);
  });
}
