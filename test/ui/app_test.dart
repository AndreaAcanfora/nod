import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nod/app.dart';
import 'package:nod/core/api.dart';
import 'package:nod/core/models.dart';
import 'package:nod/services/demo.dart';
import 'package:nod/services/services.dart';
import 'package:nod/state.dart';
import 'package:nod/ui/request_page.dart';

class CountingAuth implements Authenticator {
  CountingAuth(this.answer);
  bool answer;
  int asked = 0;
  @override
  Future<bool> get available async => true;
  @override
  Future<bool> confirm(String reason) async {
    asked++;
    return answer;
  }
}

Services services({Authenticator? auth, List<Account>? accounts, DemoBackend? backend}) => Services(
  backend: backend ?? DemoBackend(),
  store: MemoryStore()..accounts = accounts ?? [DemoBackend.demoAccount()],
  auth: auth ?? DemoAuthenticator(),
  push: NoPush(),
  notifier: NoNotifier(),
  openUrl: (_) async => true,
  deviceName: 'Test',
);

Future<AppState> pump(WidgetTester t, Services s) async {
  // A tall phone, so whole forms fit without scrolling.
  t.view.physicalSize = const Size(420, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final state = AppState(s);
  await state.init();
  await t.pumpWidget(NodApp(services: s, state: state));
  await t.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('shows the welcome screen before pairing', (t) async {
    await pump(t, services(accounts: []));
    expect(find.text('Approve what your AI agents want to do'), findsOneWidget);
    await t.tap(find.text('Pair a gateway'));
    await t.pumpAndSettle();
    expect(find.text('Pairing link'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'not a link');
    await t.tap(find.widgetWithText(FilledButton, 'Pair'));
    await t.pumpAndSettle();
    expect(find.textContaining('That is not a pairing link'), findsOneWidget);
  });

  testWidgets('approves after the fingerprint check', (t) async {
    final auth = CountingAuth(false);
    final state = await pump(t, services(auth: auth));
    expect(find.text('Waiting for you · 3'), findsOneWidget);
    await t.tap(find.text('Force-push to main?'));
    await t.pumpAndSettle();
    expect(find.text('Why the agent asks'), findsOneWidget);

    await t.tap(find.text('Approve'));
    await t.pumpAndSettle();
    expect(auth.asked, 1);
    expect(find.text('Not confirmed. Nothing was sent.'), findsOneWidget);
    expect(state.waiting.length, 3);

    auth.answer = true;
    await t.tap(find.text('Approve'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Approved'), findsOneWidget);
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(state.waiting.length, 2);
    expect(state.recent.first.item.decision, 'APPROVE');
    expect(find.text('Waiting for you · 2'), findsOneWidget);
  });

  testWidgets('declines without the fingerprint check', (t) async {
    final auth = CountingAuth(true);
    final state = await pump(t, services(auth: auth));
    await t.tap(find.text('Force-push to main?'));
    await t.pumpAndSettle();
    await t.tap(find.text('Decline'));
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(auth.asked, 0);
    expect(state.recent.first.item.decision, 'DECLINE');
  });

  testWidgets('fills in a form and shows the gateway problems', (t) async {
    final state = await pump(t, services());
    await t.tap(find.text('Where should I deploy v2.3.0?'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '42');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('required'), findsOneWidget);
    expect(find.text('must be between 1 and 10'), findsOneWidget);

    await t.tap(find.text('Production'));
    await t.enterText(find.byType(TextField), '3');
    await t.tap(find.text('Post in #releases when done'));
    await t.tap(find.text('Send'));
    await t.pumpAndSettle(const Duration(seconds: 2));
    final done = state.recent.firstWhere((e) => e.item.interactionId == 'demo-env').item;
    expect(done.data, {'env': 'production', 'replicas': '3', 'notify': true});
  });

  testWidgets('sends passkey requests to the browser', (t) async {
    Uri? opened;
    final s = services();
    final withOpener = Services(
      backend: s.backend,
      store: s.store,
      auth: s.auth,
      push: s.push,
      notifier: s.notifier,
      deviceName: 'Test',
      openUrl: (u) async {
        opened = u;
        return true;
      },
    );
    await pump(t, withOpener);
    await t.tap(find.text('Pay invoice INV-2291?'));
    await t.pumpAndSettle();
    expect(find.text('Needs a passkey'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await t.tap(find.text('Open in browser'));
    expect(opened, isNotNull);
  });

  test('recognizes commands in request text', () {
    expect(RequestBody.looksLikeCode('git push --force origin main'), isTrue);
    expect(RequestBody.looksLikeCode(r'$ make deploy'), isTrue);
    expect(RequestBody.looksLikeCode('Rewrites 3 commits already on GitHub.'), isFalse);
    expect(RequestBody.looksLikeCode('€4,800.00 to ACME Hosting Ltd, due tomorrow.'), isFalse);
    expect(RequestBody.looksLikeCode('payments-worker has been at 100% CPU for 12 minutes.'), isFalse);
  });

  test('pairing adds a gateway and unpairing removes it', () async {
    final state = AppState(services(accounts: []));
    await state.init();
    expect(state.accounts, isEmpty);
    await state.pair(PairingLinkFor.demo);
    expect(state.accounts, hasLength(1));
    expect(state.waiting, hasLength(3));
    await state.unpair(state.accounts.single);
    expect(state.accounts, isEmpty);
    expect(state.waiting, isEmpty);
    state.dispose();
  });
}

extension PairingLinkFor on Never {
  static final demo = PairingLink.parse('https://gw.example.com/pair/0123456789abcdef0123')!;
}
