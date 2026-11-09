import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crypto.dart';
import 'models.dart';

/// The JWS "typ" of a signed answer.
const answerType = 'a2h-device-answer+jws';

/// An error answered by the gateway.
class GatewayException implements Exception {
  GatewayException(this.status, this.code, this.message, {this.problems = const {}, this.item});

  final int status;
  final String code;
  final String message;
  final Map<String, String> problems;
  final InboxItem? item;

  /// The phone was unpaired on the gateway.
  bool get unpaired => code == 'unpaired';

  @override
  String toString() => message;
}

/// A pairing link: `<base_url>/pair/<token>`, or `nod://pair?url=<link>`.
class PairingLink {
  const PairingLink(this.baseUrl, this.token);
  final String baseUrl;
  final String token;

  static PairingLink? parse(String text) {
    var uri = Uri.tryParse(text.trim());
    if (uri == null) return null;
    if (uri.scheme == 'nod') {
      final inner = uri.queryParameters['url'];
      return inner == null ? null : parse(inner);
    }
    if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final i = segs.lastIndexOf('pair');
    if (i < 0 || i != segs.length - 2 || segs.last.length < 16) return null;
    final base = uri.replace(pathSegments: segs.sublist(0, i), query: null, fragment: null).toString();
    return PairingLink(base.endsWith('/') ? base.substring(0, base.length - 1) : base, segs.last);
  }

  /// Plain http is only accepted for local development.
  bool get insecure => Uri.parse(baseUrl).scheme == 'http';
}

/// Talks to one gateway as one paired phone.
class GatewayClient {
  GatewayClient(this.account, {http.Client? client}) : _http = client ?? http.Client();

  final Account account;
  final http.Client _http;
  late final DeviceKey key = DeviceKey.fromPrivate(account.privateKey);

  static const _timeout = Duration(seconds: 20);

  /// Pairs this phone: creates a key and registers it with the gateway.
  static Future<Account> pair(PairingLink link, {required String deviceName, String? pushUrl, http.Client? client}) async {
    final key = DeviceKey.generate();
    final c = client ?? http.Client();
    final resp = await c
        .post(
          Uri.parse('${link.baseUrl}/v1/device/pair'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'pairing_token': link.token, 'name': deviceName, 'public_key': key.publicJwk, 'push_url': ?pushUrl}),
        )
        .timeout(_timeout);
    final j = _decode(resp);
    return Account(
      deviceId: j['device_id'] as String,
      deviceToken: j['device_token'] as String,
      baseUrl: link.baseUrl,
      principalId: j['principal_id'] as String,
      privateKey: key.privateKey,
      deviceName: deviceName,
      pushUrl: pushUrl,
    );
  }

  Map<String, String> get _headers => {'authorization': 'Bearer ${account.deviceToken}', 'content-type': 'application/json'};

  Uri _url(String path) => Uri.parse('${account.baseUrl}$path');

  /// Requests waiting for an answer first, then the last week's.
  Future<List<InboxItem>> inbox() async {
    final resp = await _http.get(_url('/v1/device/inbox'), headers: _headers).timeout(_timeout);
    final j = _decode(resp);
    return [for (final it in j['items'] as List) InboxItem.fromJson(it as Map<String, dynamic>)];
  }

  /// Signs and sends an answer. [decision] is APPROVE, DECLINE or SUBMIT.
  Future<InboxItem> answer(String interactionId, String decision, {Map<String, Object?>? data, DateTime? now}) async {
    final payload = <String, Object?>{
      'interaction_id': interactionId,
      'decision': decision,
      'data': ?data,
      'device_id': account.deviceId,
      'iat': (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
    };
    final jws = key.signJws(payload, typ: answerType);
    final resp = await _http.post(_url('/v1/device/answer'), headers: _headers, body: jsonEncode({'jws': jws})).timeout(_timeout);
    final j = _decode(resp);
    return InboxItem.fromJson(j['item'] as Map<String, dynamic>);
  }

  /// Sets (or clears, with "") the UnifiedPush endpoint.
  Future<void> setPushUrl(String url) async {
    final resp = await _http.patch(_url('/v1/device'), headers: _headers, body: jsonEncode({'push_url': url})).timeout(_timeout);
    _decode(resp);
  }

  /// Unpairs this phone on the gateway.
  Future<void> unpair() async {
    final resp = await _http.delete(_url('/v1/device'), headers: _headers).timeout(_timeout);
    if (resp.statusCode == 401) return; // already unpaired
    _decode(resp);
  }

  static Map<String, dynamic> _decode(http.Response resp) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw GatewayException(
        resp.statusCode,
        'bad_response',
        'The gateway answered ${resp.statusCode} with something that is not JSON. Is this the right address?',
      );
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) return j;
    throw GatewayException(
      resp.statusCode,
      j['error'] as String? ?? 'error',
      j['message'] as String? ?? 'The gateway answered ${resp.statusCode}.',
      problems: {for (final e in ((j['problems'] as Map?) ?? {}).entries) e.key as String: e.value as String},
      item: j['item'] is Map<String, dynamic> ? InboxItem.fromJson(j['item'] as Map<String, dynamic>) : null,
    );
  }
}
