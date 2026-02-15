import 'dart:async';
import 'dart:io';
import 'dart:isolate';

void main() async {
  print('PID: $pid');
  print('=== Spawning failed Process.start calls ===');

  // Fire off many failed Process.start calls concurrently
  final futures = <Future>[];
  for (var i = 0; i < 50; i++) {
    futures.add(
      Process.start('no-such-command-$i', []).then((p) {
        print('unexpected success: $i');
      }).catchError((e) {
        // silently catch
      }),
    );
  }

  // Concurrent async I/O work to keep threads busy
  final httpServer = await HttpServer.bind('127.0.0.1', 0);
  final port = httpServer.port;
  print('=== HTTP server on port $port ===');
  httpServer.listen((req) {
    req.response
      ..write('ok')
      ..close();
  });

  // Hit the server from an isolate to generate cross-thread I/O
  for (var i = 0; i < 10; i++) {
    unawaited(
      HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:$port/'))
          .then((req) => req.close())
          .then((resp) => resp.drain<void>())
          .catchError((_) {}),
    );
  }

  // Also spawn some isolates doing Process.start
  for (var i = 0; i < 5; i++) {
    unawaited(Isolate.spawn(_isolateWork, i));
  }

  await Future.wait(futures);
  print('=== All Process.start calls completed ===');

  // Keep running
  print('=== Sleeping 10 seconds (watching for SIGPIPE)... ===');
  await Future<void>.delayed(const Duration(seconds: 10));

  httpServer.close();
  print('=== Done, exiting normally ===');
}

void _isolateWork(int id) async {
  for (var i = 0; i < 20; i++) {
    try {
      await Process.start('no-such-command-isolate-$id-$i', []);
    } catch (_) {}
  }
  // Do some stdout writing to exercise pipes
  for (var i = 0; i < 100; i++) {
    stdout.writeln('isolate $id writing line $i');
  }
}
