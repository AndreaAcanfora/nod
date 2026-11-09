/// Data the gateway sends about requests (see a2h-gateway docs/app-api.md).
library;

class Option {
  const Option(this.value, this.label);
  final String value;
  final String label;

  factory Option.fromJson(Map<String, dynamic> j) =>
      Option(j['value'] as String, (j['label'] as String?)?.isNotEmpty == true ? j['label'] as String : j['value'] as String);

  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// One input of a COLLECT form.
class Component {
  const Component({required this.type, required this.name, this.label, this.required = false, this.options = const [], this.validation = const {}});
  final String type; // TEXT, TEXTAREA, NUMBER, DATE, TIME, DATETIME, SELECT, MULTISELECT, RADIO, CHECKBOX
  final String name;
  final String? label;
  final bool required;
  final List<Option> options;
  final Map<String, dynamic> validation;

  String get displayLabel => (label?.isNotEmpty ?? false) ? label! : name;

  factory Component.fromJson(Map<String, dynamic> j) => Component(
    type: j['type'] as String,
    name: j['name'] as String,
    label: j['label'] as String?,
    required: j['required'] as bool? ?? false,
    options: [for (final o in (j['options'] as List? ?? [])) Option.fromJson(o as Map<String, dynamic>)],
    validation: (j['validation'] as Map<String, dynamic>?) ?? const {},
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    if (label != null) 'label': label,
    'required': required,
    'options': [for (final o in options) o.toJson()],
    'validation': validation,
  };
}

abstract final class Intents {
  static const authorize = 'AUTHORIZE';
  static const collect = 'COLLECT';
  static const inform = 'INFORM';
  static const result = 'RESULT';
  static const escalate = 'ESCALATE';
}

abstract final class States {
  static const waiting = 'WAITING_INPUT';
  static const answered = 'ANSWERED';
  static const expired = 'EXPIRED';
  static const cancelled = 'CANCELLED';
  static const failed = 'FAILED';
  static const sent = 'SENT';
}

/// A request as the inbox shows it.
class InboxItem {
  const InboxItem({
    required this.interactionId,
    required this.type,
    required this.state,
    required this.agentId,
    required this.body,
    required this.createdAt,
    this.title,
    this.footer,
    this.why,
    this.components = const [],
    this.expiresAt,
    this.requiredFactor,
    this.webUrl,
    this.decision,
    this.decidedAt,
    this.factor,
    this.data,
    this.error,
  });

  final String interactionId;
  final String type;
  final String state;
  final String agentId;
  final String? title;
  final String body;
  final String? footer;
  final String? why;
  final List<Component> components;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? requiredFactor;
  final String? webUrl;
  final String? decision;
  final DateTime? decidedAt;
  final String? factor;
  final Object? data;
  final String? error;

  bool get waiting => state == States.waiting;

  /// Approving needs a factor this app does not have (a passkey).
  bool get needsBrowser => requiredFactor != null;

  String get heading {
    if (title != null && title!.isNotEmpty) return title!;
    return switch (type) {
      Intents.authorize => 'Approval needed',
      Intents.collect => 'Information needed',
      Intents.escalate => 'Continue elsewhere',
      _ => 'Message from ${agentId.isEmpty ? 'your agent' : agentId}',
    };
  }

  static DateTime? _time(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
    interactionId: j['interaction_id'] as String,
    type: j['type'] as String,
    state: j['state'] as String,
    agentId: j['agent_id'] as String? ?? '',
    title: j['title'] as String?,
    body: j['body'] as String? ?? '',
    footer: j['footer'] as String?,
    why: j['why'] as String?,
    components: [for (final c in (j['components'] as List? ?? [])) Component.fromJson(c as Map<String, dynamic>)],
    createdAt: _time(j['created_at']) ?? DateTime.now(),
    expiresAt: _time(j['expires_at']),
    requiredFactor: j['required_factor'] as String?,
    webUrl: j['web_url'] as String?,
    decision: j['decision'] as String?,
    decidedAt: _time(j['decided_at']),
    factor: j['factor'] as String?,
    data: j['data'],
    error: j['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'interaction_id': interactionId,
    'type': type,
    'state': state,
    'agent_id': agentId,
    if (title != null) 'title': title,
    'body': body,
    if (footer != null) 'footer': footer,
    if (why != null) 'why': why,
    'components': [for (final c in components) c.toJson()],
    'created_at': createdAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
    if (requiredFactor != null) 'required_factor': requiredFactor,
    if (webUrl != null) 'web_url': webUrl,
    if (decision != null) 'decision': decision,
    if (decidedAt != null) 'decided_at': decidedAt!.toUtc().toIso8601String(),
    if (factor != null) 'factor': factor,
    if (data != null) 'data': data,
    if (error != null) 'error': error,
  };
}

/// A gateway this phone is paired with.
class Account {
  const Account({
    required this.deviceId,
    required this.deviceToken,
    required this.baseUrl,
    required this.principalId,
    required this.privateKey,
    this.deviceName = 'Phone',
    this.pushUrl,
  });

  final String deviceId;
  final String deviceToken;
  final String baseUrl;
  final String principalId;
  final String privateKey;
  final String deviceName;
  final String? pushUrl;

  /// The gateway's host, for display.
  String get host => Uri.tryParse(baseUrl)?.host ?? baseUrl;

  Account copyWith({String? pushUrl}) => Account(
    deviceId: deviceId,
    deviceToken: deviceToken,
    baseUrl: baseUrl,
    principalId: principalId,
    privateKey: privateKey,
    deviceName: deviceName,
    pushUrl: pushUrl ?? this.pushUrl,
  );

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    deviceId: j['device_id'] as String,
    deviceToken: j['device_token'] as String,
    baseUrl: j['base_url'] as String,
    principalId: j['principal_id'] as String,
    privateKey: j['private_key'] as String,
    deviceName: j['device_name'] as String? ?? 'Phone',
    pushUrl: j['push_url'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_token': deviceToken,
    'base_url': baseUrl,
    'principal_id': principalId,
    'private_key': privateKey,
    'device_name': deviceName,
    if (pushUrl != null) 'push_url': pushUrl,
  };
}
