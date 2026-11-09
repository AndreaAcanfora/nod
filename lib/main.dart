import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/real.dart';
import 'services/services.dart';
import 'state.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // UnifiedPush starts the app headless (--unifiedpush-bg) when a push
  // arrives while it is closed: fetch the requests and notify, no UI.
  final background = args.contains('--unifiedpush-bg');
  final notifier = LocalNotifier();
  await notifier.init();
  final services = Services(
    backend: GatewayBackend(),
    store: SecureStore(),
    auth: DeviceAuthenticator(),
    push: UnifiedPushService(background: background),
    notifier: notifier,
    openUrl: openExternal,
    deviceName: deviceName(),
    scanner: qrScanner,
  );
  final state = AppState(services)..inForeground = !background;
  await services.push.start();
  if (background) {
    await state.init();
    await state.refresh(notify: true);
    return;
  }
  runApp(NodApp(services: services, state: state..init()));
}
