import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nod/core/api.dart';
import 'package:nod/core/crypto.dart';
import 'package:nod/core/models.dart';

void main() {
  group('PairingLink', () {
    test('parses gateway links', () {
      final l = PairingLink.parse(' https://a2h.example.com/pair/RtnHWF_K5ne6lELjppW5yOVc1KMkg2rTmVOPeobOvu8 ')!;
      expect(l.baseUrl, 'https://a2h.example.com');
      expect(l.token, 'RtnHWF_K5ne6lELjppW5yOVc1KMkg2rTmVOPeobOvu8');
      expect(l.insecure, isFalse);
    });
    test('keeps a path prefix', () {
      final l = PairingLink.parse('https://example.com/a2h/pair/RtnHWF_K5ne6lELjppW5y')!;
      expect(l.baseUrl, 'https://example.com/a2h');
    });
    test('unwraps nod:// links', () {
      final inner = Uri.encodeComponent('http://localhost:8080/pair/RtnHWF_K5ne6lELjppW5y');
      final l = PairingLink.parse('nod://pair?url=$inner')!;
      expect(l.baseUrl, 'http://localhost:8080');
      expect(l.insecure, isTrue);
    });
    test('rejects other text', () {
      for (final s in [
        '',
        'hello',
        'https://example.com/',
        'https://example.com/pair/',
        'https://example.com/pair/short',
        'ftp://x/pair/RtnHWF_K5ne6lELjppW5y',
      ]) {
        expect(PairingLink.parse(s), isNull, reason: s);
      }
    });
  });

  test('answers with a JWS signed by the account key', () async {
    final key = DeviceKey.generate();
    final account = Account(deviceId: 'dev_1', deviceToken: 'tok', baseUrl: 'https://gw.example', principalId: 'alice', privateKey: key.privateKey);
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://gw.example/v1/device/answer');
      expect(req.headers['authorization'], 'Bearer tok');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'result': 'answered',
          'item': {'interaction_id': 'i1', 'type': 'AUTHORIZE', 'state': 'ANSWERED', 'body': 'x', 'created_at': '2026-11-09T10:00:00Z', 'decision': 'APPROVE'},
        }),
        200,
      );
    });
    final item = await GatewayClient(account, client: client).answer('i1', 'APPROVE', now: DateTime.utc(2026, 11, 9, 10));
    expect(item.decision, 'APPROVE');
    final jws = sent['jws'] as String;
    expect(DeviceKey.verifyJws(jws, key.publicJwk), isTrue);
    final payload = jsonDecode(utf8.decode(b64urlDecode(jws.split('.')[1])));
    expect(payload, {'interaction_id': 'i1', 'decision': 'APPROVE', 'device_id': 'dev_1', 'iat': 1794218400});
  });

  test('turns gateway errors into GatewayException', () async {
    final account = Account(deviceId: 'd', deviceToken: 't', baseUrl: 'https://gw', principalId: 'p', privateKey: DeviceKey.generate().privateKey);
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'error': 'invalid_data',
          'message': 'Please check.',
          'problems': {'reason': 'required'},
        }),
        422,
      ),
    );
    expect(
      () => GatewayClient(account, client: client).answer('i', 'SUBMIT', data: {}),
      throwsA(isA<GatewayException>().having((e) => e.problems['reason'], 'problem', 'required')),
    );
    final html = MockClient((req) async => http.Response('<html>', 404));
    expect(() => GatewayClient(account, client: html).inbox(), throwsA(isA<GatewayException>().having((e) => e.code, 'code', 'bad_response')));
  });
}
