import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'services/demo.dart';
import 'services/services.dart';

/// The web demo: sample requests, no gateway, nothing leaves the browser.
void main() {
  final store = MemoryStore()..accounts = [DemoBackend.demoAccount()];
  runApp(
    NodApp(
      services: Services(
        backend: DemoBackend(),
        store: store,
        auth: DemoAuthenticator(),
        push: NoPush(),
        notifier: NoNotifier(),
        openUrl: (u) => launchUrl(u, webOnlyWindowName: '_blank'),
        deviceName: 'Browser',
        demo: true,
      ),
    ),
  );
}
