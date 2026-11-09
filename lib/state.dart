import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core/api.dart';
import 'core/models.dart';
import 'services/services.dart';

/// A request and the gateway it came from.
class Entry {
  const Entry(this.account, this.item);
  final Account account;
  final InboxItem item;
}

/// The app's state: paired gateways and their requests.
class AppState extends ChangeNotifier {
  AppState(this.s);

  final Services s;
  List<Account> accounts = [];
  final _items = <String, List<InboxItem>>{};
  final errors = <String, String>{};
  final _notified = <String>{};
  bool ready = false;
  bool refreshing = false;
  bool requireAuth = true;
  bool inForeground = true;
  Timer? _poll;
  StreamSubscription<void>? _pings;

  static const _requireAuthKey = 'require_auth';

  Future<void> init() async {
    accounts = await s.store.loadAccounts();
    requireAuth = (await s.store.read(_requireAuthKey)) != 'false';
    ready = true;
    notifyListeners();
    _pings = s.push.pings.listen((_) => refresh(notify: !inForeground));
    s.push.endpoint.addListener(_syncPush);
    _syncPush();
    await refresh();
    if (inForeground) _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pings?.cancel();
    s.push.endpoint.removeListener(_syncPush);
    super.dispose();
  }

  /// While the app is open, check every 15 seconds: that is how requests
  /// arrive on phones without push (iOS, or Android without a distributor).
  void _startPolling() {
    _poll?.cancel();
    if (accounts.isEmpty) return;
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (inForeground) refresh();
    });
  }

  void setForeground(bool value) {
    inForeground = value;
    if (value) refresh();
  }

  /// Tells every gateway the current push endpoint.
  Future<void> _syncPush() async {
    final url = s.push.endpoint.value;
    if (url == null) return;
    var changed = false;
    for (var i = 0; i < accounts.length; i++) {
      final a = accounts[i];
      if ((a.pushUrl ?? '') == url) continue;
      try {
        await s.backend.client(a).setPushUrl(url);
        accounts[i] = a.copyWith(pushUrl: url);
        changed = true;
      } catch (_) {
        // Retried at the next start.
      }
    }
    if (changed) await s.store.saveAccounts(accounts);
  }

  List<Entry> _entries(bool Function(InboxItem) test) {
    final out = <Entry>[];
    for (final a in accounts) {
      for (final it in _items[a.deviceId] ?? const <InboxItem>[]) {
        if (test(it)) out.add(Entry(a, it));
      }
    }
    return out;
  }

  /// Requests waiting for an answer, the ones expiring first on top.
  List<Entry> get waiting {
    final w = _entries((it) => it.waiting);
    final far = DateTime(9999);
    w.sort((x, y) => (x.item.expiresAt ?? far).compareTo(y.item.expiresAt ?? far));
    return w;
  }

  /// Everything else, newest first.
  List<Entry> get recent {
    final r = _entries((it) => !it.waiting);
    r.sort((x, y) => (y.item.decidedAt ?? y.item.createdAt).compareTo(x.item.decidedAt ?? x.item.createdAt));
    return r;
  }

  Entry? find(String deviceId, String interactionId) {
    for (final e in _entries((it) => it.interactionId == interactionId)) {
      if (e.account.deviceId == deviceId) return e;
    }
    return null;
  }

  /// Fetches every gateway's inbox. With [notify], shows a notification for
  /// each request that was not waiting before.
  Future<void> refresh({bool notify = false}) async {
    if (refreshing) return;
    refreshing = true;
    notifyListeners();
    await Future.wait([for (final a in List.of(accounts)) _refreshOne(a, notify)]);
    refreshing = false;
    notifyListeners();
  }

  Future<void> _refreshOne(Account a, bool notify) async {
    try {
      final items = await s.backend.client(a).inbox();
      _items[a.deviceId] = items;
      errors.remove(a.deviceId);
      for (final it in items) {
        final key = '${a.deviceId}/${it.interactionId}';
        if (it.waiting && _notified.add(key) && notify) {
          await s.notifier.show(it, host: a.host);
        } else if (!it.waiting && _notified.remove(key)) {
          await s.notifier.cancel(it.interactionId);
        }
      }
    } on GatewayException catch (e) {
      errors[a.deviceId] = e.unpaired ? 'This phone was unpaired on the gateway.' : e.message;
    } catch (e) {
      errors[a.deviceId] = 'Cannot reach ${a.host}. Check the connection.';
    }
  }

  /// Sends an answer. Throws [GatewayException] when the gateway refuses it.
  Future<InboxItem> answer(Entry e, String decision, {Map<String, Object?>? data}) async {
    try {
      final done = await s.backend.client(e.account).answer(e.item.interactionId, decision, data: data);
      _replace(e.account, done);
      await s.notifier.cancel(done.interactionId);
      return done;
    } on GatewayException catch (err) {
      if (err.item != null) _replace(e.account, err.item!);
      rethrow;
    }
  }

  void _replace(Account a, InboxItem item) {
    final list = _items[a.deviceId];
    if (list == null) return;
    final i = list.indexWhere((x) => x.interactionId == item.interactionId);
    if (i >= 0) list[i] = item;
    notifyListeners();
  }

  /// Pairs with a gateway. Throws [GatewayException] on failure.
  Future<Account> pair(PairingLink link) async {
    final push = s.push.endpoint.value;
    final a = await s.backend.pair(link, deviceName: s.deviceName, pushUrl: (push?.isEmpty ?? true) ? null : push);
    accounts = [...accounts, a];
    await s.store.saveAccounts(accounts);
    notifyListeners();
    _startPolling();
    unawaited(s.notifier.requestPermission());
    await refresh();
    return a;
  }

  /// Unpairs from a gateway, also when it cannot be reached.
  Future<void> unpair(Account a) async {
    try {
      await s.backend.client(a).unpair();
    } catch (_) {}
    accounts = accounts.where((x) => x.deviceId != a.deviceId).toList();
    _items.remove(a.deviceId);
    errors.remove(a.deviceId);
    await s.store.saveAccounts(accounts);
    _startPolling();
    notifyListeners();
  }

  Future<void> setRequireAuth(bool value) async {
    requireAuth = value;
    await s.store.write(_requireAuthKey, '$value');
    notifyListeners();
  }

  /// For the demo: an agent asks something now.
  void addDemoItem(InboxItem Function(Account) make) {
    if (accounts.isEmpty) return;
    make(accounts.first);
    refresh();
  }
}
