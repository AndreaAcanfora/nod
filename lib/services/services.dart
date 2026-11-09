/// What the app needs from the platform. main.dart wires the real phone
/// services; main_demo.dart wires in-memory ones for the web demo and tests.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/api.dart';
import '../core/models.dart';

/// Talks to one gateway as one paired phone.
abstract interface class NodClient {
  Future<List<InboxItem>> inbox();
  Future<InboxItem> answer(String interactionId, String decision, {Map<String, Object?>? data});
  Future<void> setPushUrl(String url);
  Future<void> unpair();
}

class GatewayNodClient implements NodClient {
  GatewayNodClient(Account account) : _c = GatewayClient(account);
  final GatewayClient _c;

  @override
  Future<List<InboxItem>> inbox() => _c.inbox();
  @override
  Future<InboxItem> answer(String interactionId, String decision, {Map<String, Object?>? data}) => _c.answer(interactionId, decision, data: data);
  @override
  Future<void> setPushUrl(String url) => _c.setPushUrl(url);
  @override
  Future<void> unpair() => _c.unpair();
}

/// Creates clients and pairs phones.
abstract interface class Backend {
  NodClient client(Account account);
  Future<Account> pair(PairingLink link, {required String deviceName, String? pushUrl});
}

class GatewayBackend implements Backend {
  @override
  NodClient client(Account account) => GatewayNodClient(account);
  @override
  Future<Account> pair(PairingLink link, {required String deviceName, String? pushUrl}) => GatewayClient.pair(link, deviceName: deviceName, pushUrl: pushUrl);
}

/// Keeps accounts (with their private keys) and settings.
abstract interface class Store {
  Future<List<Account>> loadAccounts();
  Future<void> saveAccounts(List<Account> accounts);
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Asks the person to confirm with fingerprint, face or screen lock.
abstract interface class Authenticator {
  Future<bool> get available;
  Future<bool> confirm(String reason);
}

enum PushStatus { unsupported, noDistributor, registering, ready, failed }

/// Wakes the app when a gateway has something new (UnifiedPush on Android).
abstract interface class Push {
  ValueListenable<PushStatus> get status;

  /// The endpoint gateways should POST to, once registered.
  ValueListenable<String?> get endpoint;

  /// Fires when a push arrives.
  Stream<void> get pings;
  Future<void> start();
}

/// Shows system notifications.
abstract interface class Notifier {
  Future<void> init();
  Future<void> requestPermission();
  Future<void> show(InboxItem item, {required String host});
  Future<void> cancel(String interactionId);
}

/// Opens a URL outside the app.
typedef UrlOpener = Future<bool> Function(Uri url);

/// A widget that scans a QR code and calls back with its text, or null when
/// the platform has no camera scanner (web).
typedef ScannerBuilder = Widget Function(BuildContext context, void Function(String text) onScan);

class Services {
  const Services({
    required this.backend,
    required this.store,
    required this.auth,
    required this.push,
    required this.notifier,
    required this.openUrl,
    required this.deviceName,
    this.scanner,
    this.demo = false,
  });

  final Backend backend;
  final Store store;
  final Authenticator auth;
  final Push push;
  final Notifier notifier;
  final UrlOpener openUrl;
  final String deviceName;
  final ScannerBuilder? scanner;
  final bool demo;
}
