import 'package:flutter/material.dart';

import '../app.dart';
import '../core/api.dart';
import '../core/crypto.dart';
import '../core/models.dart';

class PairPage extends StatefulWidget {
  const PairPage({super.key});
  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final _link = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pair(String text) async {
    if (_busy) return;
    final link = PairingLink.parse(text);
    if (link == null) {
      setState(() => _error = 'That is not a pairing link. It looks like https://your-gateway/pair/…');
      return;
    }
    if (link.insecure && !await _confirmInsecure(link)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.read(context);
    try {
      final account = await state.pair(link);
      if (!mounted) return;
      await _paired(account);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on GatewayException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach ${Uri.parse(link.baseUrl).host}. Check the address and your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmInsecure(PairingLink link) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.lock_open_rounded),
          title: const Text('Unencrypted gateway'),
          content: Text('${link.baseUrl} uses plain HTTP. Anyone on the network could read your requests. Use it only for local testing.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pair anyway')),
          ],
        ),
      ) ??
      false;

  Future<void> _paired(Account a) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.verified_rounded, size: 40),
      title: const Text('Paired'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Requests for ${a.principalId} on ${a.host} now come to this phone.'),
          const SizedBox(height: 16),
          Text('Key fingerprint', style: Theme.of(context).textTheme.labelMedium),
          SelectableText(
            DeviceKey.fromPrivate(a.privateKey).fingerprint,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          const Text('The private key stays on this phone. Every answer is signed with it.'),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scanner = state.s.scanner;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pair a gateway')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text('On the gateway, run', style: text.bodyLarge),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: const SelectableText(r'a2h pair -principal <your-id>', style: TextStyle(fontFamily: 'monospace')),
              ),
              const SizedBox(height: 8),
              Text('then scan the code it shows, or paste the link.', style: text.bodyLarge),
              const SizedBox(height: 20),
              if (scanner != null)
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: _busy
                        ? const ColoredBox(
                            color: Colors.black,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : scanner(context, _pair),
                  ),
                ),
              if (scanner != null) const SizedBox(height: 20),
              TextField(
                controller: _link,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(labelText: 'Pairing link', hintText: 'https://a2h.example.com/pair/…', errorText: _error, errorMaxLines: 3),
                onSubmitted: _pair,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : () => _pair(_link.text),
                child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text('Pair'),
              ),
              if (state.s.demo) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => _pair('https://a2h.example.com/pair/demo-pairing-token-0123456789'),
                  child: const Text('Use a demo gateway'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
