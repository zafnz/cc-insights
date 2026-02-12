import 'dart:async';
import 'dart:convert';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('JsonRpcClient', () {
    test('pairs request and response', () async {
      final input = StreamController<String>();
      final sentMessages = <String>[];
      final client = JsonRpcClient(
        input: input.stream,
        output: sentMessages.add,
      );

      final future = client.sendRequest('test.method', {'value': 42});

      final sent = jsonDecode(sentMessages.single) as Map<String, dynamic>;
      final id = sent['id'];

      input.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'ok': true},
      }));

      final result = await future;
      expect(result, {'ok': true});

      await client.dispose();
      await input.close();
    });

    test('parses notifications', () async {
      final input = StreamController<String>();
      final client = JsonRpcClient(
        input: input.stream,
        output: (_) {},
      );

      final completer = Completer<JsonRpcNotification>();
      final sub = client.notifications.listen(completer.complete);

      input.add(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {'status': 'ok'},
      }));

      final notification = await completer.future;
      expect(notification.method, 'session/update');
      expect(notification.params, {'status': 'ok'});

      await sub.cancel();
      await client.dispose();
      await input.close();
    });

    test('parses server requests', () async {
      final input = StreamController<String>();
      final client = JsonRpcClient(
        input: input.stream,
        output: (_) {},
      );

      final completer = Completer<JsonRpcServerRequest>();
      final sub = client.serverRequests.listen(completer.complete);

      input.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'fs/read_text_file',
        'params': {'path': '/tmp/file.txt'},
      }));

      final request = await completer.future;
      expect(request.id, 7);
      expect(request.method, 'fs/read_text_file');
      expect(request.params, {'path': '/tmp/file.txt'});

      await sub.cancel();
      await client.dispose();
      await input.close();
    });

    test('handles error responses', () async {
      final input = StreamController<String>();
      final sentMessages = <String>[];
      final client = JsonRpcClient(
        input: input.stream,
        output: sentMessages.add,
      );

      final future = client.sendRequest('bad.method', null);

      final sent = jsonDecode(sentMessages.single) as Map<String, dynamic>;
      final id = sent['id'];

      input.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32000, 'message': 'boom'},
      }));

      await expectLater(
        future,
        throwsA(
          isA<JsonRpcError>().having((e) => e.message, 'message', 'boom'),
        ),
      );

      await client.dispose();
      await input.close();
    });

    test('escapes newlines in outgoing payloads', () async {
      final input = StreamController<String>();
      final sentMessages = <String>[];
      final client = JsonRpcClient(
        input: input.stream,
        output: sentMessages.add,
      );

      client.sendNotification('session/update', {
        'text': 'line1\nline2\rline3',
      });

      expect(sentMessages, hasLength(1));
      final sent = sentMessages.single;
      expect(sent.contains('\n'), isFalse);
      expect(sent.contains('\r'), isFalse);

      await client.dispose();
      await input.close();
    });
  });
}
