import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../state.dart';
import 'theme.dart';
import 'widgets.dart';

class RequestPage extends StatefulWidget {
  const RequestPage({super.key, required this.deviceId, required this.interactionId});
  final String deviceId;
  final String interactionId;

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  final _values = <String, Object?>{};
  final _controllers = <String, TextEditingController>{};
  Map<String, String> _problems = {};
  String? _busy; // the decision being sent
  String? _done; // shown in the success overlay

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String name) => _controllers.putIfAbsent(name, () => TextEditingController());

  Map<String, Object?> _formData(InboxItem it) {
    final data = <String, Object?>{};
    for (final c in it.components) {
      switch (c.type) {
        case 'CHECKBOX':
          data[c.name] = _values[c.name] == true;
        case 'MULTISELECT':
          data[c.name] = List<String>.from((_values[c.name] as Set<String>?) ?? const <String>{});
        case 'RADIO' || 'SELECT':
          if (_values[c.name] != null) data[c.name] = _values[c.name];
        default:
          final v = _controller(c.name).text.trim();
          if (v.isNotEmpty) data[c.name] = v;
      }
    }
    return data;
  }

  Future<void> _send(Entry e, String decision) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final it = e.item;
    if (decision != 'DECLINE' && state.requireAuth && await state.s.auth.available) {
      final what = decision == 'APPROVE' ? 'Approve' : 'Send';
      if (!await state.s.auth.confirm('$what: ${it.heading}')) {
        messenger.showSnackBar(const SnackBar(content: Text('Not confirmed. Nothing was sent.')));
        return;
      }
    }
    setState(() {
      _busy = decision;
      _problems = {};
    });
    try {
      await state.answer(e, decision, data: decision == 'SUBMIT' ? _formData(it) : null);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(
        () => _done = switch (decision) {
          'APPROVE' => 'Approved',
          'DECLINE' => 'Declined',
          _ => 'Sent',
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (mounted) Navigator.of(context).maybePop();
    } on GatewayException catch (err) {
      if (!mounted) return;
      setState(() => _problems = err.problems);
      messenger.showSnackBar(SnackBar(content: Text(err.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not reach the gateway. Nothing was sent; try again.')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.find(widget.deviceId, widget.interactionId);
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This request is gone.')),
      );
    }
    final it = e.item;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Row(
          children: [
            IntentBadge(it),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [if (it.agentId.isNotEmpty) it.agentId, e.account.host].join(' · '),
                style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(it.heading, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            Text('Asked ${ago(it.createdAt)}', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            if (it.waiting && it.expiresAt != null) TimeLeft(it.expiresAt!),
          ],
        ),
        if (!it.waiting) ...[const SizedBox(height: 16), _Outcome(it)],
        if (it.body.isNotEmpty) ...[
          const SizedBox(height: 18),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: RequestBody(it.body)),
          ),
        ],
        if (it.why?.isNotEmpty ?? false) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: scheme.primary, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why the agent asks',
                  style: text.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(it.why!, style: text.bodyMedium),
              ],
            ),
          ),
        ],
        if (it.footer?.isNotEmpty ?? false) ...[const SizedBox(height: 14), Text(it.footer!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))],
        if (it.waiting && it.needsBrowser) ...[
          const SizedBox(height: 18),
          Material(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              leading: Icon(Icons.key_rounded, color: scheme.onSecondaryContainer),
              title: Text(
                'Needs a passkey',
                style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'The agent asked for the strongest proof. Approve in the browser with your passkey, or decline here.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ),
        ],
        if (it.waiting && it.type == Intents.collect) ...[const SizedBox(height: 8), for (final c in it.components) _field(c)],
      ],
    );

    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: content),
          ),
          if (_done != null) _DoneOverlay(_done!),
        ],
      ),
      bottomNavigationBar: it.waiting && (it.type == Intents.authorize || it.type == Intents.collect) && _done == null ? _actions(e) : null,
    );
  }

  Widget _actions(Entry e) {
    final it = e.item;
    final scheme = Theme.of(context).colorScheme;
    final busy = _busy != null;
    Widget spin(Color c) => SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c));
    final decline = OutlinedButton(
      onPressed: busy ? null : () => _send(e, 'DECLINE'),
      child: _busy == 'DECLINE' ? spin(scheme.primary) : const Text('Decline'),
    );
    final Widget primary;
    if (it.type == Intents.collect) {
      primary = FilledButton.icon(
        onPressed: busy ? null : () => _send(e, 'SUBMIT'),
        icon: _busy == 'SUBMIT' ? spin(scheme.onPrimary) : const Icon(Icons.send_rounded),
        label: const Text('Send'),
      );
    } else if (it.needsBrowser) {
      primary = FilledButton.icon(
        onPressed: busy || it.webUrl == null ? null : () => AppScope.read(context).s.openUrl(Uri.parse(it.webUrl!)),
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Open in browser'),
      );
    } else {
      primary = FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: scheme.approve, foregroundColor: scheme.onApprove),
        onPressed: busy ? null : () => _send(e, 'APPROVE'),
        icon: _busy == 'APPROVE' ? spin(scheme.onApprove) : const Icon(Icons.fingerprint_rounded),
        label: const Text('Approve'),
      );
    }
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5))),
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Row(
              children: [
                Expanded(flex: 2, child: decline),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(Component c) {
    final problem = _problems[c.name];
    final label = '${c.displayLabel}${c.required ? ' *' : ''}';
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget labelled(Widget child) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          child,
          if (problem != null) Text(problem, style: TextStyle(color: scheme.error)),
        ],
      ),
    );
    switch (c.type) {
      case 'CHECKBOX':
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _values[c.name] == true,
            onChanged: (v) => setState(() => _values[c.name] = v),
            title: Text(c.displayLabel),
          ),
        );
      case 'RADIO':
        return labelled(
          RadioGroup<String>(
            groupValue: _values[c.name] as String?,
            onChanged: (v) => setState(() => _values[c.name] = v),
            child: Column(
              children: [for (final o in c.options) RadioListTile<String>(contentPadding: EdgeInsets.zero, value: o.value, title: Text(o.label))],
            ),
          ),
        );
      case 'MULTISELECT':
        final picked = (_values[c.name] as Set<String>?) ?? <String>{};
        return labelled(
          Wrap(
            spacing: 8,
            children: [
              for (final o in c.options)
                FilterChip(
                  label: Text(o.label),
                  selected: picked.contains(o.value),
                  onSelected: (on) => setState(() => _values[c.name] = on ? ({...picked, o.value}) : ({...picked}..remove(o.value))),
                ),
            ],
          ),
        );
      case 'SELECT':
        return labelled(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<String>(
              initialValue: _values[c.name] as String?,
              items: [for (final o in c.options) DropdownMenuItem(value: o.value, child: Text(o.label))],
              onChanged: (v) => setState(() => _values[c.name] = v),
            ),
          ),
        );
      default:
        final picker = switch (c.type) {
          'DATE' || 'TIME' || 'DATETIME' => true,
          _ => false,
        };
        return labelled(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _controller(c.name),
              readOnly: picker,
              onTap: picker ? () => _pick(c) : null,
              maxLines: c.type == 'TEXTAREA' ? 4 : 1,
              keyboardType: c.type == 'NUMBER' ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
              decoration: InputDecoration(
                hintText: switch (c.type) {
                  'DATE' => 'Pick a date',
                  'TIME' => 'Pick a time',
                  'DATETIME' => 'Pick a date and time',
                  _ => null,
                },
                suffixIcon: picker ? const Icon(Icons.event_rounded) : null,
              ),
            ),
          ),
        );
    }
  }

  Future<void> _pick(Component c) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    DateTime? date;
    TimeOfDay? time;
    if (c.type != 'TIME') {
      date = await showDatePicker(context: context, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10), initialDate: now);
      if (date == null) return;
    }
    if (c.type != 'DATE' && mounted) {
      time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (time == null) return;
    }
    final d = date == null ? '' : '${date.year}-${two(date.month)}-${two(date.day)}';
    final t = time == null ? '' : '${two(time.hour)}:${two(time.minute)}';
    _controller(c.name).text = switch (c.type) {
      'DATE' => d,
      'TIME' => t,
      _ => '${d}T$t',
    };
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome(this.it);
  final InboxItem it;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = outcome(context, it);
    final how = factorLabel(it.factor);
    final when = it.decidedAt == null ? '' : ago(it.decidedAt!);
    final details = [when, how].where((s) => s.isNotEmpty).join(', ');
    final data = it.data;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  details.isEmpty ? label : '$label · $details',
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
          if (it.error != null && it.state != States.answered) Padding(padding: const EdgeInsets.only(top: 6), child: Text(it.error!)),
          if (data is Map && data.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final MapEntry(:key, :value) in data.entries) Text('$key: ${value is List ? value.join(', ') : value}')],
              ),
            ),
        ],
      ),
    );
  }
}

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final approve = label != 'Declined';
    final color = approve ? scheme.approve : scheme.onSurfaceVariant;
    return Positioned.fill(
      child: ColoredBox(
        color: scheme.surface.withValues(alpha: .94),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .6, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(approve ? Icons.check_circle_rounded : Icons.do_not_disturb_on_rounded, size: 96, color: color),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 4),
                Text('Signed on this phone. The agent has been told.', style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The request's text. Paragraphs that look like a command (one line, no
/// sentence punctuation, not capitalized) are shown in monospace: that is
/// what people most need to read exactly.
class RequestBody extends StatelessWidget {
  const RequestBody(this.body, {super.key});
  final String body;

  static bool looksLikeCode(String p) {
    final t = p.trim();
    if (t.isEmpty || t.contains('\n') || t.length > 240) return false;
    final first = t.characters.first;
    final last = t.characters.last;
    return first.toLowerCase() == first && first.toUpperCase() != first && !'.!?:)'.contains(last) || t.startsWith(r'$ ');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paragraphs = body.split(RegExp(r'\n\s*\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in paragraphs.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          if (looksLikeCode(p))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(
                p.trim(),
                style: text.bodyMedium?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'Courier'], height: 1.4),
              ),
            )
          else
            SelectableText(p.trim(), style: text.bodyLarge?.copyWith(height: 1.45)),
        ],
      ],
    );
  }
}
