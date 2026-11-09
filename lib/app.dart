import 'package:flutter/material.dart';

import 'services/services.dart';
import 'state.dart';
import 'ui/inbox_page.dart';
import 'ui/theme.dart';

/// Gives widgets the app state.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class NodApp extends StatefulWidget {
  const NodApp({super.key, required this.services, this.state});
  final Services services;
  final AppState? state;

  @override
  State<NodApp> createState() => _NodAppState();
}

class _NodAppState extends State<NodApp> with WidgetsBindingObserver {
  late final AppState state = widget.state ?? (AppState(widget.services)..init());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => state.setForeground(s == AppLifecycleState.resumed);

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: MaterialApp(
      title: 'nod',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const InboxPage(),
    ),
  );
}
