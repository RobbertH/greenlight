import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'app_state.dart';
import 'constants.dart';
import 'data/db.dart';
import 'data/light_repository.dart';
import 'screens/map_screen.dart';
import 'screens/record_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await HomeWidget.setAppGroupId(appGroupId);
  } catch (_) {}
  final repo = LightRepository(await AppDatabase.open());
  final state = AppState(repo);
  // Pull in anything the widget recorded while the app was dead, before the
  // first frame reads counts.
  await state.syncWithWidget();
  await state.load();
  runApp(GreenlightApp(state: state));
}

class GreenlightApp extends StatefulWidget {
  final AppState state;

  const GreenlightApp({super.key, required this.state});

  @override
  State<GreenlightApp> createState() => _GreenlightAppState();
}

class _GreenlightAppState extends State<GreenlightApp>
    with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wireWidgetLaunches();
  }

  /// On iOS <17 the widget can't record in place; tapping it deep-links here
  /// and we land the user straight on the record screen. Same for tapping the
  /// non-button area of the Android widget.
  Future<void> _wireWidgetLaunches() async {
    try {
      final launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (launchUri != null) _openRecordScreen();
      _widgetClicks = HomeWidget.widgetClicked.listen((uri) {
        if (uri != null) _openRecordScreen();
      });
    } catch (_) {}
  }

  void _openRecordScreen() {
    final nav = _navKey.currentState;
    if (nav == null || widget.state.activeLight == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.pushNamed(kRecordRoute);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      widget.state.syncWithWidget();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClicks?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Greenlight',
      navigatorKey: _navKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A651),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A651),
        brightness: Brightness.dark,
      ),
      home: MapScreen(state: widget.state),
      routes: {
        kRecordRoute: (_) => RecordScreen(state: widget.state),
      },
    );
  }
}
