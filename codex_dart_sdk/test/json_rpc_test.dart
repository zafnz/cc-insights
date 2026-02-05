import 'dart:async';
import 'dart:convert';

import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('JsonRpcClient.dispose', () {
    test('completes pending requests with error', () async {
      final input = StreamController<String>();
      final client = JsonRpcClient(
        input: input.stream,
        output: (_) {},
      );

      final future = client.sendRequest('test.method', null);

      // Attach error handler before dispose to avoid unhandled async error.
      Object? caughtError;
      unawaited(future.then<void>((_) {}, onError: (Object e) {
        caughtError = e;
      }));

      await client.dispose();
      await input.close();

      // Allow microtasks to propagate.
      await Future<void>.delayed(Duration.zero);

      expect(caughtError, isA<StateError>());
    });

    test('multiple pending requests all complete with error', () async {
      final input = StreamController<String>();
      final client = JsonRpcClient(
        input: input.stream,
        output: (_) {},
      );

      final f1 = client.sendRequest('method1', null);
      final f2 = client.sendRequest('method2', null);
      final f3 = client.sendRequest('method3', null);

      final errors = <Object?>[];
      for (final f in [f1, f2, f3]) {
        unawaited(f.then<void>((_) {}, onError: (Object e) {
          errors.add(e);
        }));
      }

      await client.dispose();
      await input.close();
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(3));
      expect(errors, everyElement(isA<StateError>()));
    });

    test('error message indicates client was disposed', () async {
      final input = StreamController<String>();
      final client = JsonRpcClient(
        input: input.stream,
        output: (_) {},
      );

      final future = client.sendRequest('slow.method', null);

      Object? caughtError;
      unawaited(future.then<void>((_) {}, onError: (Object e) {
        caughtError = e;
      }));

      await client.dispose();
      await input.close();
      await Future<void>.delayed(Duration.zero);

      expect(caughtError, isA<StateError>());
      expect((caughtError! as StateError).message, 'JSON-RPC client disposed');
    });

    test('stream close resolves pending requests', () async {
      final input = StreamController<String>();
      final client = JsonRpcClient(
        input: input.stream,
        output: (_) {},
      );

      final future = client.sendRequest('test.method', null);

      Object? caughtError;
      unawaited(future.then<void>((_) {}, onError: (Object e) {
        caughtError = e;
      }));

      // Close the stream (simulates process exit) before dispose.
      await input.close();
      await Future<void>.delayed(Duration.zero);

      expect(caughtError, isA<StateError>());
      expect(
        (caughtError! as StateError).message,
        'JSON-RPC connection closed',
      );

      await client.dispose();
    });

    test('already-completed requests are not affected by dispose', () async {
      final input = StreamController<String>();
      final sentMessages = <String>[];
      final client = JsonRpcClient(
        input: input.stream,
        output: sentMessages.add,
      );

      final future = client.sendRequest('test.method', null);

      // Send a response for the request.
      final sent = jsonDecode(sentMessages.first) as Map<String, dynamic>;
      final id = sent['id'];
      input.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'ok': true},
      }));

      final result = await future;
      expect(result, {'ok': true});

      // Dispose after response — should not throw.
      await client.dispose();
      await input.close();
    });
  });
}
