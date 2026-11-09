import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import 'services.dart';

class SecureStore implements Store {
  static const _storage = FlutterSecureStorage();
  static const _accounts = 'accounts.v1';

  @override
  Future<List<Account>> loadAccounts() async {
    final raw = await _storage.read(key: _accounts);
    if (raw == null) return [];
    return [for (final j in jsonDecode(raw) as List) Account.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Future<void> saveAccounts(List<Account> accounts) => _storage.write(key: _accounts, value: jsonEncode([for (final a in accounts) a.toJson()]));

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

class DeviceAuthenticator implements Authenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> get available async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> confirm(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

/// UnifiedPush: works with any distributor (ntfy, NextPush, Sunup…), no
/// Google services. iOS has no UnifiedPush; there the app refreshes while open.
class UnifiedPushService implements Push {
  UnifiedPushService({this.background = false});

  final bool background;
  final _status = ValueNotifier(PushStatus.unsupported);
  final _endpoint = ValueNotifier<String?>(null);
  final _pings = StreamController<void>.broadcast();

  @override
  ValueListenable<PushStatus> get status => _status;
  @override
  ValueListenable<String?> get endpoint => _endpoint;
  @override
  Stream<void> get pings => _pings.stream;

  @override
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    _status.value = PushStatus.registering;
    try {
      await UnifiedPush.initialize(
        onNewEndpoint: (e, _) {
          _endpoint.value = e.url;
          _status.value = PushStatus.ready;
        },
        onRegistrationFailed: (_, _) => _status.value = PushStatus.failed,
        onUnregistered: (_) {
          _endpoint.value = '';
          _status.value = PushStatus.noDistributor;
        },
        onMessage: (_, _) => _pings.add(null),
      );
      if (background) return;
      if (await UnifiedPush.tryUseCurrentOrDefaultDistributor()) {
        await UnifiedPush.register();
      } else {
        _status.value = PushStatus.noDistributor;
      }
    } catch (_) {
      _status.value = PushStatus.failed;
    }
  }
}

class LocalNotifier implements Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationDetails(
    'requests',
    'Requests from agents',
    channelDescription: 'An agent is waiting for your answer',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  @override
  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
    );
  }

  @override
  Future<void> requestPermission() async {
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true);
  }

  @override
  Future<void> show(InboxItem item, {required String host}) => _plugin.show(
    id: item.interactionId.hashCode & 0x7fffffff,
    title: item.heading,
    body: item.agentId.isEmpty ? host : '${item.agentId} · $host',
    notificationDetails: const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
    payload: item.interactionId,
  );

  @override
  Future<void> cancel(String interactionId) => _plugin.cancel(id: interactionId.hashCode & 0x7fffffff);
}

Future<bool> openExternal(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

Widget qrScanner(BuildContext context, void Function(String text) onScan) => ReaderWidget(
  codeFormat: Format.qrCode,
  tryInverted: true,
  showGallery: false,
  showToggleCamera: false,
  cropPercent: 0.7,
  onScan: (code) {
    if (code.isValid && code.text != null) onScan(code.text!);
  },
);

String deviceName() {
  if (kIsWeb) return 'Browser';
  if (Platform.isIOS) return 'iPhone';
  if (Platform.isAndroid) return 'Android phone';
  return 'Phone';
}
