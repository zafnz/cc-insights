import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final cwd = options['cwd'] ?? Directory.current.path;
  final filePath = options['file'];
  final expectedContent =
      filePath != null ? File(filePath).readAsStringSync() : '';

  final pending = <int, Completer<Map<String, dynamic>>>{};
  var nextId = 1;
  String? sessionId;

  void sendMessage(Map<String, dynamic> message) {
    stdout.writeln(jsonEncode(message));
  }

  void sendResponse(Object id, Map<String, dynamic> result) {
    sendMessage({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });
  }

  void sendError(Object id, int code, String message) {
    sendMessage({
      'jsonrpc': '2.0',
      'id': id,
      'error': {
        'code': code,
        'message': message,
      },
    });
  }

  void sendNotification(String method, Map<String, dynamic> params) {
    sendMessage({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = nextId++;
    final completer = Completer<Map<String, dynamic>>();
    pending[id] = completer;
    sendMessage({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future.timeout(const Duration(seconds: 4), onTimeout: () {
      stderr.writeln('Timeout waiting for response to $method');
      exit(1);
    });
  }

  Future<void> handlePrompt(Object id, Map<String, dynamic> params) async {
    final promptSessionId =
        params['sessionId'] as String? ?? sessionId ?? 'sess-stub';
    sessionId = promptSessionId;

    sendNotification('session/update', {
      'sessionId': promptSessionId,
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {
          'type': 'text',
          'text': 'Stub agent received prompt.',
        },
      },
    });

    sendNotification('session/update', {
      'sessionId': promptSessionId,
      'update': {
        'sessionUpdate': 'plan',
        'entries': [
          {'text': 'Step one'},
          {'text': 'Step two'},
        ],
      },
    });

    sendNotification('session/update', {
      'sessionId': promptSessionId,
      'update': {
        'sessionUpdate': 'config_option_update',
        'configOptions': [
          {
            'id': 'model',
            'values': ['stub-model-a', 'stub-model-b'],
          },
        ],
      },
    });

    sendNotification('session/update', {
      'sessionId': promptSessionId,
      'update': {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          {'id': 'help', 'name': 'Help'},
        ],
      },
    });

    sendNotification('session/update', {
      'sessionId': promptSessionId,
      'update': {
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'fast',
      },
    });

    sendNotification('session/update', {
      'sessionId': promptSessionId,
      'update': {
        'sessionUpdate': 'tool_call_update',
        'toolCall': {
          'toolCallId': 'call-1',
          'title': 'Read input file',
          'kind': 'read',
          'status': 'pending',
          'rawInput': {'path': filePath ?? ''},
          'content': {
            'type': 'content',
            'content': {
              'type': 'text',
              'text': 'Reading file...',
            },
          },
          'locations': [filePath ?? ''],
        },
      },
    });

    final permission = await sendRequest('session/request_permission', {
      'sessionId': promptSessionId,
      'toolCall': {
        'toolCallId': 'call-1',
        'title': 'Read input file',
        'kind': 'read',
        'rawInput': {'path': filePath ?? ''},
      },
      'options': [
        {'optionId': 'allow_once', 'name': 'Allow once', 'kind': 'allow_once'},
        {'optionId': 'reject_once', 'name': 'Reject', 'kind': 'reject_once'},
      ],
    });

    final outcome = permission['outcome'] as Map<String, dynamic>?;
    if (outcome == null || outcome['outcome'] != 'selected') {
      stderr.writeln('Permission denied by client.');
      exit(1);
    }

    if (filePath != null) {
      final response = await sendRequest('fs/read_text_file', {
        'sessionId': promptSessionId,
        'path': filePath,
        'line': 1,
        'limit': 10,
      });
      if (response['content'] != expectedContent) {
        stderr.writeln('File content mismatch.');
        exit(1);
      }
    }

    final terminalCreate = await sendRequest('terminal/create', {
      'sessionId': promptSessionId,
      'command': 'echo',
      'args': ['stub-terminal-ok'],
      'cwd': cwd,
      'outputByteLimit': 1024,
    });
    final terminalId = terminalCreate['terminalId'] as String?;
    if (terminalId == null || terminalId.isEmpty) {
      stderr.writeln('Missing terminalId.');
      exit(1);
    }

    await sendRequest('terminal/wait_for_exit', {
      'sessionId': promptSessionId,
      'terminalId': terminalId,
    });

    final output = await sendRequest('terminal/output', {
      'sessionId': promptSessionId,
      'terminalId': terminalId,
    });
    final outputText = output['output'] as String? ?? '';
    if (!outputText.contains('stub-terminal-ok')) {
      stderr.writeln('Terminal output mismatch.');
      exit(1);
    }

    await sendRequest('terminal/kill', {
      'sessionId': promptSessionId,
      'terminalId': terminalId,
    });
    await sendRequest('terminal/release', {
      'sessionId': promptSessionId,
      'terminalId': terminalId,
    });

    sendNotification('session/update', {
      'sessionId': promptSessionId,
      'update': {
        'sessionUpdate': 'tool_call_update',
        'toolCall': {
          'toolCallId': 'call-1',
          'title': 'Read input file',
          'kind': 'read',
          'status': 'completed',
          'rawInput': {'path': filePath ?? ''},
          'rawOutput': {'ok': true},
          'content': {
            'type': 'diff',
            'path': filePath ?? '',
            'oldText': expectedContent,
            'newText': expectedContent,
          },
          'locations': [filePath ?? ''],
        },
      },
    });

    sendResponse(id, {'stopReason': 'end_turn'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    exit(0);
  }

  final lineStream =
      stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lineStream) {
    if (line.trim().isEmpty) continue;
    final message = jsonDecode(line) as Map<String, dynamic>;

    if (message.containsKey('method')) {
      final method = message['method'] as String;
      final params = message['params'] as Map<String, dynamic>? ?? const {};
      final id = message['id'];

      if (id == null) {
        if (method == 'session/cancel') {
          exit(0);
        }
        continue;
      }

      switch (method) {
        case 'initialize':
          sendResponse(id, {
            'protocolVersion': 1,
            'agentCapabilities': {
              'streaming': true,
              'loadSession': false,
            },
          });
          break;
        case 'session/new':
          sessionId = 'sess-stub-1';
          sendResponse(id, {
            'sessionId': sessionId,
            'configOptions': [
              {
                'id': 'model',
                'values': ['stub-model-a', 'stub-model-b'],
              },
            ],
          });
          break;
        case 'session/prompt':
          unawaited(handlePrompt(id, params));
          break;
        default:
          sendError(id, -32601, 'Unsupported method: $method');
      }
      continue;
    }

    final id = message['id'];
    if (id is int && pending.containsKey(id)) {
      final completer = pending.remove(id)!;
      if (message['error'] != null) {
        stderr.writeln('Received error for request $id: ${message['error']}');
        exit(1);
      }
      final result = message['result'];
      if (result is Map<String, dynamic>) {
        completer.complete(result);
      } else if (result is Map) {
        completer.complete(Map<String, dynamic>.from(result));
      } else {
        completer.complete(<String, dynamic>{});
      }
    }
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final parsed = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--') && i + 1 < args.length) {
      parsed[arg.substring(2)] = args[i + 1];
      i++;
    }
  }
  return parsed;
}
