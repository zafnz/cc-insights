import 'dart:async';
import 'dart:convert';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('initialize sends protocolVersion and client capabilities', () async {
    final input = StreamController<String>();
    final sentMessages = <String>[];
    final client = JsonRpcClient(
      input: input.stream,
      output: sentMessages.add,
    );

    final future = AcpProcess.initializeForTesting(
      client: client,
      protocolVersion: 1,
      clientName: 'cc-insights',
      clientVersion: '0.1.0',
      clientCapabilities: {
        'streaming': true,
      },
    );

    expect(sentMessages, hasLength(1));
    final sent = jsonDecode(sentMessages.single) as Map<String, dynamic>;
    expect(sent['method'], 'initialize');

    final params = sent['params'] as Map<String, dynamic>;
    expect(params['protocolVersion'], 1);
    expect(params['clientCapabilities'], {'streaming': true});

    final clientInfo = params['clientInfo'] as Map<String, dynamic>;
    expect(clientInfo['name'], 'cc-insights');
    expect(clientInfo['version'], '0.1.0');

    final id = sent['id'];
    input.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'protocolVersion': 1,
        'agentCapabilities': {'loadSession': true},
      },
    }));

    final result = await future;
    expect(result.protocolVersion, 1);
    expect(result.agentCapabilities, {'loadSession': true});

    await client.dispose();
    await input.close();
  });
}
