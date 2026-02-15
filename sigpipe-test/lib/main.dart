import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  debugPrint('=== About to call Process.start("no-such-command") ===');
  Process.start('no-such-command', []).then((process) {
    debugPrint('=== Process started (unexpected): pid=${process.pid} ===');
  }).catchError((error) {
    debugPrint('=== Process.start error: $error ===');
  });

  runApp(const SigpipeTestApp());
}

class SigpipeTestApp extends StatelessWidget {
  const SigpipeTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGPIPE Test',
      home: Scaffold(
        appBar: AppBar(title: const Text('SIGPIPE Test')),
        body: const Center(
          child: Text('App is running. If SIGPIPE hits, this will exit.'),
        ),
      ),
    );
  }
}
