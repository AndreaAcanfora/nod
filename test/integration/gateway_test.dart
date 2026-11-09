// End-to-end test against a real a2h-gateway binary.
//
//   A2H_BIN=/path/to/a2h flutter test test/integration
//
// Skipped when A2H_BIN is not set. CI builds the gateway from source.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nod/core/api.dart';
import 'package:nod/core/crypto.dart';
import 'package:nod/core/models.dart';

const apiKey = 'nod-test-key-0123456789';

void main() {
  final bin = Platform.environment['A2H_BIN'];
  late Process gateway;
  late Directory dataDir;
  late String base;
  late Map<String, String> env;

  setUpAll(() async {
    if (bin == null) return;
    dataDir = await Directory.systemTemp.createTemp('nod-a2h-');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    base = 'http://localhost:$port';
    env = {'A2H_BASE_URL': base, 'A2H_LISTEN': '127.0.0.1:$port', 'A2H_DATA_DIR': dataDir.path, 'A2H_API_KEYS': 'tests:$apiKey', 'A2H_CONSOLE': '1'};
    gateway = await Process.start(bin, ['serve'], environment: env);
    gateway.stderr.transform(utf8.decoder).listen((_) {});
    for (var i = 0; i < 50; i++) {
      try {
        if ((await http.get(Uri.parse('$base/healthz'))).statusCode == 200) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('gateway did not start');
  });

  tearDownAll(() async {
    if (bin == null) return;
    gateway.kill();
    await gateway.exitCode;
    await dataDir.delete(recursive: true);
  });

  Future<PairingLink> pairingLink(String principal) async {
    final r = await Process.run(bin!, ['pair', '-principal', principal, '-no-qr'], environment: env);
    expect(r.exitCode, 0, reason: r.stderr as String);
    return PairingLink.parse((r.stdout as String).trim())!;
  }

  Future<String> ask(Map<String, Object?> intent) async {
    final r = await http.post(
      Uri.parse('$base/v1/intent'),
      headers: {'content-type': 'application/json', 'x-a2h-api-key': apiKey},
      body: jsonEncode({
        'message_id': 'm-${DateTime.now().microsecondsSinceEpoch}',
        'agent_id': 'test-agent',
        'principal_id': 'alice',
        'ttl_sec': 300,
        ...intent,
      }),
    );
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(r.body) as Map)['interaction_id'] as String;
  }

  Future<Map<String, dynamic>> status(String id) async {
    final r = await http.get(Uri.parse('$base/v1/status/$id'), headers: {'x-a2h-api-key': apiKey});
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<InboxItem> waitFor(GatewayClient c, String id) async {
    for (var i = 0; i < 50; i++) {
      final items = await c.inbox();
      final it = items.where((x) => x.interactionId == id && x.waiting);
      if (it.isNotEmpty) return it.first;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('request $id never reached the inbox');
  }

  test('pairs, receives a request and approves it with a signature', () async {
    final link = await pairingLink('alice');
    final account = await GatewayClient.pair(link, deviceName: 'Integration test');
    expect(account.principalId, 'alice');
    final c = GatewayClient(account);

    final id = await ask({
      'type': 'AUTHORIZE',
      'channel': {'type': 'app', 'address': 'app:alice'},
      'render': {'title': 'Deploy?', 'body': 'Deploy v2 to production'},
      'explanation_bundle': {'why': 'Tests passed'},
    });
    final item = await waitFor(c, id);
    expect(item.heading, 'Deploy?');
    expect(item.why, 'Tests passed');
    expect(item.needsBrowser, isFalse);

    final answered = await c.answer(id, 'APPROVE');
    expect(answered.decision, 'APPROVE');
    expect(answered.factor, 'device_key.es256.v1');

    final s = await status(id);
    expect(s['state'], 'ANSWERED');
    final evidence = (s['response'] as Map)['evidence'] as Map;
    final proof = evidence['proof'] as Map;
    expect(proof['device_id'], account.deviceId);
    final jwk = (proof['public_key'] as Map).cast<String, String>();
    // The gateway's thumbprint of our key matches ours.
    expect(jwk['kid'], DeviceKey.fromPrivate(account.privateKey).thumbprint);
    expect(DeviceKey.verifyJws(proof['jws'] as String, jwk), isTrue);

    await expectLater(c.answer(id, 'DECLINE'), throwsA(isA<GatewayException>().having((e) => e.code, 'code', 'closed')));
  }, skip: bin == null ? 'set A2H_BIN to run' : null);

  test('fills a form and sees passkey-only requests', () async {
    final c = GatewayClient(await GatewayClient.pair(await pairingLink('alice'), deviceName: 'Form test'));
    final id = await ask({
      'type': 'COLLECT',
      'channel': {'type': 'app', 'address': 'app:alice'},
      'render': {'body': 'Which environment?'},
      'components': [
        {
          'type': 'RADIO',
          'name': 'env',
          'required': true,
          'options': [
            {'value': 'staging'},
            {'value': 'prod'},
          ],
        },
        {
          'type': 'NUMBER',
          'name': 'replicas',
          'validation': {'min': 1, 'max': 10},
        },
      ],
    });
    final item = await waitFor(c, id);
    expect(item.components.map((x) => x.name), ['env', 'replicas']);
    await expectLater(
      c.answer(id, 'SUBMIT', data: {'replicas': '99'}),
      throwsA(isA<GatewayException>().having((e) => e.problems.keys, 'problems', containsAll(['env', 'replicas']))),
    );
    final done = await c.answer(id, 'SUBMIT', data: {'env': 'prod', 'replicas': '3'});
    expect(done.data, {'env': 'prod', 'replicas': 3});

    final high = await ask({
      'type': 'AUTHORIZE',
      'channel': {'type': 'app', 'address': 'app:alice'},
      'render': {'body': 'Wire 5000 EUR'},
      'assurance': {'level': 'HIGH'},
    });
    final h = await waitFor(c, high);
    expect(h.needsBrowser, isTrue);
    expect(h.webUrl, startsWith('$base/i/'));
    await expectLater(c.answer(high, 'APPROVE'), throwsA(isA<GatewayException>().having((e) => e.code, 'code', 'passkey_required')));
    expect((await c.answer(high, 'DECLINE')).decision, 'DECLINE');

    await c.unpair();
    await expectLater(c.inbox(), throwsA(isA<GatewayException>().having((e) => e.unpaired, 'unpaired', isTrue)));
  }, skip: bin == null ? 'set A2H_BIN to run' : null);
}
