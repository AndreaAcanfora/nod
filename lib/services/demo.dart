import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/crypto.dart';
import '../core/models.dart';
import 'services.dart';

/// An in-memory gateway with sample requests, for the web demo and tests.
class DemoBackend implements Backend {
  DemoBackend({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  final _items = <String, List<InboxItem>>{};
  var _seq = 0;

  static Account demoAccount([String host = 'a2h.example.com']) => Account(
    deviceId: 'dev_demo_${host.hashCode}',
    deviceToken: 'demo',
    baseUrl: 'https://$host',
    principalId: 'you',
    privateKey: DeviceKey.generate().privateKey,
    deviceName: 'This browser',
  );

  List<InboxItem> _for(Account a) => _items.putIfAbsent(a.deviceId, () => samples(now()));

  /// Adds a new waiting request, as if an agent had just asked.
  InboxItem simulate(Account a) {
    _seq++;
    final t = now();
    final pick = _seq % 3;
    final item = switch (pick) {
      1 => InboxItem(
        interactionId: 'demo-new-$_seq',
        type: Intents.authorize,
        state: States.waiting,
        agentId: 'claude-code',
        title: 'Run database migration?',
        body: 'npm run migrate -- --env production\n\nAdds column `orders.refunded_at` (nullable). 2.4M rows, ~40 s lock.',
        why: 'The refund feature you asked for needs this column.',
        createdAt: t,
        expiresAt: t.add(const Duration(minutes: 10)),
      ),
      2 => InboxItem(
        interactionId: 'demo-new-$_seq',
        type: Intents.authorize,
        state: States.waiting,
        agentId: 'ops-bot',
        title: 'Restart the payments worker?',
        body: 'payments-worker-7f9c has been at 100% CPU for 12 minutes. Restarting drops 3 in-flight jobs (they are retried).',
        createdAt: t,
        expiresAt: t.add(const Duration(minutes: 5)),
      ),
      _ => InboxItem(
        interactionId: 'demo-new-$_seq',
        type: Intents.inform,
        state: States.sent,
        agentId: 'research-agent',
        title: 'Report ready',
        body: 'The competitor pricing report is ready: 14 sources, 3 charts. Nothing to approve.',
        createdAt: t,
      ),
    };
    _for(a).insert(0, item);
    return item;
  }

  static List<InboxItem> samples(DateTime t) => [
    InboxItem(
      interactionId: 'demo-push',
      type: Intents.authorize,
      state: States.waiting,
      agentId: 'claude-code',
      title: 'Force-push to main?',
      body: 'git push --force-with-lease origin main\n\nRewrites 3 commits already on GitHub (squashed "wip" commits).',
      why: 'You asked me to clean up the history before the release.',
      footer: 'Repository: acme/storefront',
      createdAt: t.subtract(const Duration(minutes: 2)),
      expiresAt: t.add(const Duration(minutes: 13)),
    ),
    InboxItem(
      interactionId: 'demo-env',
      type: Intents.collect,
      state: States.waiting,
      agentId: 'deploy-agent',
      title: 'Where should I deploy v2.3.0?',
      body: 'The build passed. Pick the target and how many replicas to start.',
      components: const [
        Component(
          type: 'RADIO',
          name: 'env',
          label: 'Environment',
          required: true,
          options: [Option('staging', 'Staging'), Option('production', 'Production')],
        ),
        Component(type: 'NUMBER', name: 'replicas', label: 'Replicas', validation: {'min': 1, 'max': 10}),
        Component(type: 'CHECKBOX', name: 'notify', label: 'Post in #releases when done'),
      ],
      createdAt: t.subtract(const Duration(minutes: 6)),
      expiresAt: t.add(const Duration(hours: 1)),
    ),
    InboxItem(
      interactionId: 'demo-wire',
      type: Intents.authorize,
      state: States.waiting,
      agentId: 'finance-agent',
      title: 'Pay invoice INV-2291?',
      body: '€4,800.00 to ACME Hosting Ltd (IBAN …4471), due tomorrow.',
      why: 'Matches the purchase order PO-118 you approved in October.',
      createdAt: t.subtract(const Duration(minutes: 20)),
      expiresAt: t.add(const Duration(hours: 3)),
      requiredFactor: 'passkey.webauthn.v1',
      webUrl: 'https://github.com/AndreaAcanfora/a2h-gateway#passkeys-for-high-stakes-approvals',
    ),
    InboxItem(
      interactionId: 'demo-deploy',
      type: Intents.authorize,
      state: States.answered,
      agentId: 'deploy-agent',
      title: 'Deploy v2.2.1 to production?',
      body: 'Hotfix for the checkout timeout.',
      createdAt: t.subtract(const Duration(hours: 3)),
      decision: 'APPROVE',
      decidedAt: t.subtract(const Duration(hours: 3, minutes: -1)),
      factor: 'device_key.es256.v1',
    ),
    InboxItem(
      interactionId: 'demo-delete',
      type: Intents.authorize,
      state: States.answered,
      agentId: 'claude-code',
      title: 'Delete 214 files in /var/backups?',
      body: 'rm -rf /var/backups/2024-*',
      createdAt: t.subtract(const Duration(hours: 26)),
      decision: 'DECLINE',
      decidedAt: t.subtract(const Duration(hours: 26)),
      factor: 'device_key.es256.v1',
    ),
    InboxItem(
      interactionId: 'demo-expired',
      type: Intents.authorize,
      state: States.expired,
      agentId: 'ops-bot',
      title: 'Scale the cluster to 12 nodes?',
      body: 'Traffic is 3× the usual for a Tuesday.',
      createdAt: t.subtract(const Duration(days: 2)),
      error: 'Request expired before response received',
    ),
  ];

  @override
  NodClient client(Account account) => _DemoClient(this, account);

  @override
  Future<Account> pair(PairingLink link, {required String deviceName, String? pushUrl}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return demoAccount(Uri.parse(link.baseUrl).host);
  }
}

class _DemoClient implements NodClient {
  _DemoClient(this.b, this.a);
  final DemoBackend b;
  final Account a;

  @override
  Future<List<InboxItem>> inbox() async {
    final items = b._for(a);
    final now = b.now();
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.waiting && it.expiresAt != null && it.expiresAt!.isBefore(now)) {
        items[i] = _with(it, state: States.expired, error: 'Request expired before response received');
      }
    }
    return List.of(items);
  }

  @override
  Future<InboxItem> answer(String interactionId, String decision, {Map<String, Object?>? data}) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final items = b._for(a);
    final i = items.indexWhere((x) => x.interactionId == interactionId);
    final it = items[i];
    if (!it.waiting) throw GatewayException(410, 'closed', 'This request is no longer waiting for an answer.', item: it);
    if (decision == 'APPROVE' && it.needsBrowser) {
      throw GatewayException(403, 'passkey_required', 'This request must be approved with a passkey in the browser.');
    }
    if (decision == 'SUBMIT') {
      final problems = validate(it.components, data ?? {});
      if (problems.isNotEmpty) throw GatewayException(422, 'invalid_data', 'Please check the highlighted fields.', problems: problems);
    }
    final done = _with(
      it,
      state: States.answered,
      decision: decision == 'SUBMIT' ? null : decision,
      data: data,
      decidedAt: b.now(),
      factor: 'device_key.es256.v1',
    );
    items[i] = done;
    return done;
  }

  @override
  Future<void> setPushUrl(String url) async {}

  @override
  Future<void> unpair() async {}
}

InboxItem _with(InboxItem it, {String? state, String? decision, Object? data, DateTime? decidedAt, String? factor, String? error}) => InboxItem.fromJson({
  ...it.toJson(),
  'state': ?state,
  'decision': ?decision,
  'data': ?data,
  if (decidedAt != null) 'decided_at': decidedAt.toUtc().toIso8601String(),
  'factor': ?factor,
  'error': ?error,
});

/// The same checks the gateway makes, so the demo behaves like the real thing.
Map<String, String> validate(List<Component> cs, Map<String, Object?> data) {
  final problems = <String, String>{};
  for (final c in cs) {
    final v = data[c.name];
    final empty = v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);
    if (c.type == 'CHECKBOX') continue;
    if (empty) {
      if (c.required) problems[c.name] = 'required';
      continue;
    }
    if (c.type == 'NUMBER') {
      final n = num.tryParse('$v');
      final min = c.validation['min'] as num?, max = c.validation['max'] as num?;
      if (n == null) {
        problems[c.name] = 'not a number';
      } else if ((min != null && n < min) || (max != null && n > max)) {
        problems[c.name] = 'must be between ${min ?? '…'} and ${max ?? '…'}';
      }
    }
  }
  return problems;
}

class MemoryStore implements Store {
  List<Account> accounts = [];
  final values = <String, String>{};
  @override
  Future<List<Account>> loadAccounts() async => List.of(accounts);
  @override
  Future<void> saveAccounts(List<Account> a) async => accounts = List.of(a);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class DemoAuthenticator implements Authenticator {
  @override
  Future<bool> get available async => true;
  @override
  Future<bool> confirm(String reason) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return true;
  }
}

class NoPush implements Push {
  @override
  final status = ValueNotifier(PushStatus.unsupported);
  @override
  final endpoint = ValueNotifier<String?>(null);
  @override
  Stream<void> get pings => const Stream.empty();
  @override
  Future<void> start() async {}
}

class NoNotifier implements Notifier {
  @override
  Future<void> init() async {}
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> show(InboxItem item, {required String host}) async {}
  @override
  Future<void> cancel(String interactionId) async {}
}
