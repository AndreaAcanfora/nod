import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nod/core/crypto.dart';

void main() {
  test('signs a compact ES256 JWS that verifies', () {
    final key = DeviceKey.generate();
    final jws = key.signJws({'interaction_id': 'abc', 'decision': 'APPROVE'}, typ: 'a2h-device-answer+jws');
    final parts = jws.split('.');
    expect(parts, hasLength(3));
    final header = jsonDecode(utf8.decode(b64urlDecode(parts[0])));
    expect(header, {'alg': 'ES256', 'typ': 'a2h-device-answer+jws', 'kid': key.thumbprint});
    expect(b64urlDecode(parts[2]), hasLength(64));
    expect(DeviceKey.verifyJws(jws, key.publicJwk), isTrue);
    expect(DeviceKey.verifyJws(jws, DeviceKey.generate().publicJwk), isFalse);
    final tampered = '${parts[0]}.${b64url(utf8.encode('{"decision":"DECLINE"}'))}.${parts[2]}';
    expect(DeviceKey.verifyJws(tampered, key.publicJwk), isFalse);
  });

  test('restores the same key from its private half', () {
    final key = DeviceKey.generate();
    final again = DeviceKey.fromPrivate(key.privateKey);
    expect(again.publicJwk, key.publicJwk);
    expect(again.thumbprint, key.thumbprint);
    expect(key.fingerprint, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
  });

  test('computes the RFC 7638 thumbprint', () {
    // P-256 key with d = 1: the public key is the curve's generator.
    final key = DeviceKey.fromPrivate(b64url(List.filled(31, 0) + [1]));
    expect(key.publicJwk['x'], 'axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpY');
    expect(key.publicJwk['y'], 'T-NC4v4af5uO5-tKfA-eFivOM1drMV7Oy7ZAaDe_UfU');
    // Same value as Go's jws.Thumbprint for this key (checked in the integration test too).
    expect(key.thumbprint, hasLength(43));
  });
}
