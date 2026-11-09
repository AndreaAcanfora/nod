import 'package:flutter/material.dart';

import '../app.dart';
import '../core/crypto.dart';
import '../core/models.dart';
import '../services/services.dart';
import 'pair_page.dart';

const repoUrl = 'https://github.com/AndreaAcanfora/nod';
const appVersion = '0.1.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        t,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: [
              header('Gateways'),
              for (final a in state.accounts) _AccountTile(a),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(state.accounts.isEmpty ? 'Pair a gateway' : 'Pair another gateway'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairPage())),
              ),
              header('Security'),
              FutureBuilder<bool>(
                future: state.s.auth.available,
                builder: (context, snap) {
                  final available = snap.data ?? false;
                  return SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Confirm approvals with fingerprint or face'),
                    subtitle: Text(
                      available
                          ? 'Asked before approving or sending a form. Declining never needs it.'
                          : 'This device has no screen lock, so nod cannot ask for it.',
                    ),
                    value: state.requireAuth && available,
                    onChanged: available ? state.setRequireAuth : null,
                  );
                },
              ),
              header('Notifications'),
              ValueListenableBuilder<PushStatus>(
                valueListenable: state.s.push.status,
                builder: (context, status, _) {
                  final (icon, title, body, link) = switch (status) {
                    PushStatus.ready => (
                      Icons.notifications_active_outlined,
                      'Push is on',
                      'Through UnifiedPush. The push only says “something new”; nod fetches the request from your gateway.',
                      null,
                    ),
                    PushStatus.registering => (Icons.hourglass_top_rounded, 'Connecting to push…', '', null),
                    PushStatus.noDistributor => (
                      Icons.notifications_off_outlined,
                      'No push app installed',
                      'Install a UnifiedPush distributor such as ntfy (free, no Google account) to get notified. Until then, nod checks for requests when you open it.',
                      'https://unifiedpush.org/users/distributors/',
                    ),
                    PushStatus.failed => (Icons.error_outline_rounded, 'Push failed to start', 'nod checks for requests when you open it.', null),
                    PushStatus.unsupported => (
                      Icons.notifications_paused_outlined,
                      'Checks while open',
                      state.s.demo ? 'The web demo has no push.' : 'On this device nod checks for requests every 15 seconds while it is open.',
                      null,
                    ),
                  };
                  return ListTile(
                    leading: Icon(icon),
                    title: Text(title),
                    subtitle: body.isEmpty ? null : Text(body),
                    trailing: link == null ? null : const Icon(Icons.open_in_new_rounded),
                    onTap: link == null ? null : () => state.s.openUrl(Uri.parse(link)),
                  );
                },
              ),
              header('About'),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Source code'),
                subtitle: const Text('Open source, MIT license. No servers, no tracking, no accounts.'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => state.s.openUrl(Uri.parse(repoUrl)),
              ),
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: const Text('How it works'),
                subtitle: const Text('The A2H protocol and the gateway'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => state.s.openUrl(Uri.parse('https://github.com/AndreaAcanfora/a2h-gateway/blob/master/docs/app-api.md')),
              ),
              const ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('Version'), subtitle: Text(appVersion)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile(this.a);
  final Account a;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final err = state.errors[a.deviceId];
    final fp = DeviceKey.fromPrivate(a.privateKey).fingerprint;
    return ListTile(
      leading: Icon(err == null ? Icons.dns_rounded : Icons.cloud_off_rounded, color: err == null ? null : Theme.of(context).colorScheme.error),
      title: Text(a.host),
      subtitle: Text(['as ${a.principalId} · key $fp', (a.pushUrl?.isNotEmpty ?? false) ? 'push on' : 'no push', ?err].join('\n')),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Unpair',
        icon: const Icon(Icons.link_off_rounded),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Unpair ${a.host}?'),
              content: const Text('Requests will stop coming to this phone, and its key is deleted. You can pair again with a new code.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unpair')),
              ],
            ),
          );
          if (ok ?? false) await state.unpair(a);
        },
      ),
    );
  }
}
