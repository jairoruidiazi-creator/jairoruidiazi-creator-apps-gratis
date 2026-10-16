import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/app_scope.dart';
import 'core/theme.dart';
import 'ui/drone/drone_screen.dart';
import 'ui/metronome/metronome_screen.dart';
import 'ui/practice/practice_screen.dart';
import 'ui/recorder/recorder_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/tuner/tuner_screen.dart';

class ClaveApp extends StatelessWidget {
  const ClaveApp({super.key, required this.services});

  final Services services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (BuildContext context, Widget? _) {
          final String mode = services.settings.themeMode;
          return MaterialApp(
            title: 'Clave',
            debugShowCheckedModeBanner: false,
            theme: ClaveTheme.light(),
            darkTheme: ClaveTheme.dark(),
            themeMode: mode == 'light' ? ThemeMode.light : (mode == 'dark' ? ThemeMode.dark : ThemeMode.system),
            locale: Locale(services.settings.language),
            supportedLocales: const <Locale>[Locale('es'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

/// Pantalla principal con las cinco herramientas.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyWakelock();
  }

  void _applyWakelock() {
    final Services s = AppScope.of(context);
    final bool on = s.settings.keepAwake && (_index == 0 || _index == 1);
    WakelockPlus.toggle(enable: on).catchError((Object e) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      AppScope.of(context).state.endPractice();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      const TunerScreen(),
      const MetronomeScreen(),
      const DroneScreen(),
      const RecorderScreen(),
      const PracticeScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(<String>[t(context, 'Afinador', 'Tuner'), t(context, 'Metrónomo', 'Metronome'), t(context, 'Tono y teclado', 'Drone & keyboard'), t(context, 'Grabadora', 'Recorder'), t(context, 'Práctica', 'Practice')][_index]),
        actions: <Widget>[
          IconButton(
            tooltip: t(context, 'Ajustes', 'Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) {
          setState(() => _index = i);
          _applyWakelock();
        },
        destinations: <NavigationDestination>[
          NavigationDestination(icon: const Icon(Icons.graphic_eq_rounded), label: t(context, 'Afinador', 'Tuner')),
          NavigationDestination(icon: const Icon(Icons.timer_outlined), label: t(context, 'Metrónomo', 'Metronome')),
          NavigationDestination(icon: const Icon(Icons.piano_rounded), label: t(context, 'Tono', 'Drone')),
          NavigationDestination(icon: const Icon(Icons.mic_none_rounded), label: t(context, 'Grabar', 'Record')),
          NavigationDestination(icon: const Icon(Icons.insights_rounded), label: t(context, 'Práctica', 'Practice')),
        ],
      ),
    );
  }
}
