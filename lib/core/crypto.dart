import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final _curve = ECCurve_secp256r1();

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List b64urlDecode(String s) => base64Url.decode(base64Url.normalize(s));

Uint8List _bigIntTo32(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

BigInt _bytesToBigInt(List<int> b) => b.fold(BigInt.zero, (acc, v) => (acc << 8) | BigInt.from(v));

SecureRandom _secureRandom() {
  final rnd = Random.secure();
  final seed = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
  return FortunaRandom()..seed(KeyParameter(seed));
}

/// The P-256 key that identifies this phone to one gateway. Its private half
/// never leaves the phone's secure storage.
class DeviceKey {
  DeviceKey._(this._private, this._public);

  final ECPrivateKey _private;
  final ECPublicKey _public;

  /// Creates a new random key.
  factory DeviceKey.generate() {
    final gen = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), _secureRandom()));
    final pair = gen.generateKeyPair();
    return DeviceKey._(pair.privateKey, pair.publicKey);
  }

  /// Restores a key from [privateKey], the base64url "d" value.
  factory DeviceKey.fromPrivate(String privateKey) {
    final d = _bytesToBigInt(b64urlDecode(privateKey));
    final q = _curve.G * d;
    return DeviceKey._(ECPrivateKey(d, _curve), ECPublicKey(q, _curve));
  }

  /// The private scalar, base64url, for storage.
  String get privateKey => b64url(_bigIntTo32(_private.d!));

  /// The public key as a JWK (RFC 7517).
  Map<String, String> get publicJwk => {
    'kty': 'EC',
    'crv': 'P-256',
    'x': b64url(_bigIntTo32(_public.Q!.x!.toBigInteger()!)),
    'y': b64url(_bigIntTo32(_public.Q!.y!.toBigInteger()!)),
  };

  /// The RFC 7638 thumbprint of the public key, used as "kid".
  String get thumbprint {
    final jwk = publicJwk;
    // Members in lexicographic order, no whitespace: the RFC 7638 input.
    final input = '{"crv":"P-256","kty":"EC","x":"${jwk['x']}","y":"${jwk['y']}"}';
    return b64url(SHA256Digest().process(Uint8List.fromList(utf8.encode(input))));
  }

  /// A short fingerprint people can compare, e.g. "3F2A-91C0-7B4E".
  String get fingerprint {
    final hex = b64urlDecode(thumbprint).take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
  }

  /// Signs [payload] as a compact JWS with ES256 (RFC 7515, RFC 7518).
  String signJws(Map<String, Object?> payload, {required String typ}) {
    final header = {'alg': 'ES256', 'typ': typ, 'kid': thumbprint};
    final input = '${b64url(utf8.encode(jsonEncode(header)))}.${b64url(utf8.encode(jsonEncode(payload)))}';
    // Deterministic ECDSA (RFC 6979): no randomness needed at signing time.
    final signer = Signer('SHA-256/DET-ECDSA')..init(true, PrivateKeyParameter<ECPrivateKey>(_private));
    final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(input))) as ECSignature;
    final raw = Uint8List(64)
      ..setAll(0, _bigIntTo32(sig.r))
      ..setAll(32, _bigIntTo32(sig.s));
    return '$input.${b64url(raw)}';
  }

  /// Verifies a compact JWS made by [signJws]. Used by tests and the demo.
  static bool verifyJws(String jws, Map<String, String> jwk) {
    final parts = jws.split('.');
    if (parts.length != 3) return false;
    final x = _bytesToBigInt(b64urlDecode(jwk['x']!));
    final y = _bytesToBigInt(b64urlDecode(jwk['y']!));
    final q = _curve.curve.createPoint(x, y);
    final sig = b64urlDecode(parts[2]);
    if (sig.length != 64) return false;
    final verifier = Signer('SHA-256/ECDSA')..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, _curve)));
    return verifier.verifySignature(
      Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
      ECSignature(_bytesToBigInt(sig.sublist(0, 32)), _bytesToBigInt(sig.sublist(32))),
    );
  }
}
