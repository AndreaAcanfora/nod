import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

String ago(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

String left(Duration d) {
  if (d.isNegative) return 'expired';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min left';
  if (d.inMinutes >= 1) return '${d.inMinutes} min left';
  return '${d.inSeconds} s left';
}

/// Rebuilds every second, for countdowns.
class Ticker extends StatefulWidget {
  const Ticker({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// "12 min left", turning red in the last two minutes.
class TimeLeft extends StatelessWidget {
  const TimeLeft(this.expiresAt, {super.key, this.style});
  final DateTime expiresAt;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Ticker(
    builder: (context) {
      final d = expiresAt.difference(DateTime.now());
      final urgent = d.inMinutes < 2;
      final scheme = Theme.of(context).colorScheme;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 15, color: urgent ? scheme.error : scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(left(d), style: (style ?? Theme.of(context).textTheme.labelMedium)?.copyWith(color: urgent ? scheme.error : scheme.onSurfaceVariant)),
        ],
      );
    },
  );
}

class IntentBadge extends StatelessWidget {
  const IntentBadge(this.item, {super.key});
  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon) = switch (item.type) {
      Intents.authorize when item.needsBrowser => ('Passkey', Icons.key_rounded),
      Intents.authorize => ('Approval', Icons.verified_user_outlined),
      Intents.collect => ('Form', Icons.edit_note_rounded),
      Intents.escalate => ('Escalation', Icons.support_agent_rounded),
      _ => ('Info', Icons.info_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// How a closed request ended: icon, color and words.
(IconData, Color, String) outcome(BuildContext context, InboxItem it) {
  final scheme = Theme.of(context).colorScheme;
  return switch (it.state) {
    States.answered when it.decision == 'APPROVE' => (Icons.check_circle_rounded, scheme.approve, 'Approved'),
    States.answered when it.decision == 'DECLINE' => (Icons.cancel_rounded, scheme.error, 'Declined'),
    States.answered => (Icons.task_alt_rounded, scheme.primary, 'Answered'),
    States.expired => (Icons.timer_off_outlined, scheme.onSurfaceVariant, 'Expired'),
    States.cancelled => (Icons.block_rounded, scheme.onSurfaceVariant, 'Cancelled by the agent'),
    States.failed => (Icons.error_outline_rounded, scheme.error, 'Failed'),
    _ => (Icons.notifications_none_rounded, scheme.primary, 'Delivered'),
  };
}

/// Where an answer was given, from its evidence factor.
String factorLabel(String? factor) => switch (factor) {
  'device_key.es256.v1' => 'signed on a phone',
  'passkey.webauthn.v1' => 'with a passkey',
  'email_link.v1' => 'from an email link',
  'link.v1' => 'from a link',
  _ => '',
};

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(size * .3)),
      child: Icon(Icons.done_rounded, size: size * .72, color: scheme.onPrimary),
    );
  }
}
