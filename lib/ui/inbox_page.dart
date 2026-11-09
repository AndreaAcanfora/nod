import 'package:flutter/material.dart';

import '../app.dart';
import '../core/models.dart';
import '../services/demo.dart';
import '../state.dart';
import 'pair_page.dart';
import 'request_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

class InboxPage extends StatelessWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final waiting = state.waiting;
    final recent = state.recent;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Logo(), SizedBox(width: 10), Text('nod')]),
        actions: [
          if (state.refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: !state.ready
          ? const Center(child: CircularProgressIndicator())
          : state.accounts.isEmpty
          ? const _Welcome()
          : RefreshIndicator(
              onRefresh: state.refresh,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      if (state.s.demo) const _DemoBanner(),
                      for (final a in state.accounts)
                        if (state.errors[a.deviceId] case final err?) _ErrorCard(host: a.host, message: err),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                        child: Text(
                          waiting.isEmpty ? 'Waiting for you' : 'Waiting for you · ${waiting.length}',
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (waiting.isEmpty) const _AllClear(),
                      for (final e in waiting) Padding(padding: const EdgeInsets.only(bottom: 12), child: _WaitingCard(e)),
                      if (recent.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
                          child: Text('Recent', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      if (recent.isNotEmpty)
                        Card(
                          child: Column(
                            children: [
                              for (final (i, e) in recent.indexed) ...[
                                if (i > 0) Divider(height: 1, indent: 56, color: scheme.outlineVariant.withValues(alpha: .5)),
                                _RecentTile(e),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

void openRequest(BuildContext context, Entry e) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => RequestPage(deviceId: e.account.deviceId, interactionId: e.item.interactionId),
  ),
);

class _WaitingCard extends StatelessWidget {
  const _WaitingCard(this.e);
  final Entry e;

  @override
  Widget build(BuildContext context) {
    final it = e.item;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final many = AppScope.of(context).accounts.length > 1;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openRequest(context, e),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IntentBadge(it),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [if (it.agentId.isNotEmpty) it.agentId, if (many) e.account.host].join(' · '),
                      style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (it.expiresAt != null) TimeLeft(it.expiresAt!),
                ],
              ),
              const SizedBox(height: 12),
              Text(it.heading, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (it.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  it.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(ago(it.createdAt), style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  Text(
                    it.type == Intents.collect ? 'Answer' : 'Review',
                    style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile(this.e);
  final Entry e;

  @override
  Widget build(BuildContext context) {
    final it = e.item;
    final (icon, color, label) = outcome(context, it);
    return ListTile(
      onTap: () => openRequest(context, e),
      leading: Icon(icon, color: color),
      title: Text(it.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$label · ${ago(it.decidedAt ?? it.createdAt)}${it.agentId.isEmpty ? '' : ' · ${it.agentId}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          children: [
            Icon(Icons.spa_outlined, size: 36, color: scheme.primary),
            const SizedBox(height: 10),
            Text('All clear', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'When an agent needs you, its request shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.host, required this.message});
  final String host;
  final String message;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: Icon(Icons.cloud_off_rounded, color: scheme.onErrorContainer),
          title: Text(
            host,
            style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.science_outlined, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Demo with sample requests. Nothing here is real.', style: TextStyle(color: scheme.onTertiaryContainer)),
              ),
              TextButton(onPressed: () => state.addDemoItem((a) => (state.s.backend as DemoBackend).simulate(a)), child: const Text('New request')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget step(int n, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              '$n',
              style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          shrinkWrap: true,
          children: [
            const Center(child: Logo(size: 64)),
            const SizedBox(height: 24),
            Text(
              'Approve what your AI agents want to do',
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Agents ask before they push, deploy, pay or delete. You answer here, with your fingerprint, wherever you are.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            step(1, 'Run an A2H gateway', 'a2h-gateway is open source and self-hosted: your requests never touch our servers (there are none).'),
            step(2, 'Create a pairing code', 'On the server: a2h pair -principal you'),
            step(3, 'Scan it here', 'nod creates a key that never leaves this phone and signs every answer with it.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairPage())),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Pair a gateway'),
            ),
          ],
        ),
      ),
    );
  }
}
