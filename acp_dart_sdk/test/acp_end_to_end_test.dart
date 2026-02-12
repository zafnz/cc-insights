import 'dart:async';
import 'dart:io';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('ACP session end-to-end smoke test', () async {
    final tempDir = await Directory.systemTemp.createTemp('acp-e2e-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final inputFile = File(p.join(tempDir.path, 'input.txt'));
    await inputFile.writeAsString('stub-file-contents');

    final stubPath = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'acp_stub_agent.dart',
    );

    final backend = await AcpBackend.create(
      executablePath: Platform.resolvedExecutable,
      arguments: [
        stubPath,
        '--cwd',
        tempDir.path,
        '--file',
        inputFile.path,
      ],
    );
    addTearDown(() => backend.dispose());

    final session = await backend.createSession(
      prompt: '',
      cwd: tempDir.path,
    );

    final events = <InsightsEvent>[];
    final eventSub = session.events.listen(events.add);
    addTearDown(eventSub.cancel);

    final permissionCompleter = Completer<PermissionRequest>();
    final permissionSub = session.permissionRequests.listen((request) {
      if (!permissionCompleter.isCompleted) {
        permissionCompleter.complete(request);
      }
      request.allow(updatedInput: {'optionId': 'allow_once'});
    });
    addTearDown(permissionSub.cancel);

    await session
        .send('Run the stub flow')
        .timeout(const Duration(seconds: 5));

    await _waitForCondition(
      () => events.whereType<TextEvent>().isNotEmpty,
      'TextEvent',
    );
    await _waitForCondition(
      () => events.whereType<ConfigOptionsEvent>().isNotEmpty,
      'ConfigOptionsEvent',
    );
    await _waitForCondition(
      () => events.whereType<AvailableCommandsEvent>().isNotEmpty,
      'AvailableCommandsEvent',
    );
    await _waitForCondition(
      () => events.whereType<SessionModeEvent>().isNotEmpty,
      'SessionModeEvent',
    );
    await _waitForCondition(
      () => events.whereType<ToolInvocationEvent>().isNotEmpty,
      'ToolInvocationEvent',
    );
    await _waitForCondition(
      () => events.whereType<ToolCompletionEvent>().isNotEmpty,
      'ToolCompletionEvent',
    );

    final permission = await permissionCompleter.future
        .timeout(const Duration(seconds: 3));
    expect(permission.toolName, isNotEmpty);

    final completions = events.whereType<ToolCompletionEvent>().toList();
    expect(completions, isNotEmpty);
    final completion = completions.last;
    expect(completion.output, {'ok': true});
    expect(
      completion.extensions?['acp.toolContent'],
      isA<Map<String, dynamic>>(),
    );

    final planEvent = events
        .whereType<TextEvent>()
        .where((event) => event.kind == TextKind.plan)
        .toList();
    expect(planEvent, isNotEmpty);
  });
}

Future<void> _waitForCondition(
  bool Function() condition,
  String label, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $label');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
