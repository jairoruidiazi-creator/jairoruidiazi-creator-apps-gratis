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
import 'ui/widgets/adaptive.dart';

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
  Services? _services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
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
    // Cierra la sesión de práctica (y su temporizador) al desmontar la app.
    _services?.state.endPractice();
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
    // En tabletas (600 dp o más de ancho) las herramientas van en un riel lateral.
    final bool wide = isWideLayout(context);
    void select(int i) {
      setState(() => _index = i);
      _applyWakelock();
    }

    final List<_Dest> dests = <_Dest>[
      _Dest(Icons.graphic_eq_rounded, t(context, 'Afinador', 'Tuner')),
      _Dest(Icons.timer_outlined, t(context, 'Metrónomo', 'Metronome')),
      _Dest(Icons.piano_rounded, t(context, 'Tono', 'Drone')),
      _Dest(Icons.mic_none_rounded, t(context, 'Grabar', 'Record')),
      _Dest(Icons.insights_rounded, t(context, 'Práctica', 'Practice')),
    ];
    final Widget stack = IndexedStack(index: _index, children: pages);
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
      body: wide
          ? Row(
              children: <Widget>[
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: select,
                    labelType: NavigationRailLabelType.all,
                    destinations: <NavigationRailDestination>[
                      for (final _Dest d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: stack),
              ],
            )
          : stack,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: select,
              destinations: <NavigationDestination>[
                for (final _Dest d in dests) NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.label);

  final IconData icon;
  final String label;
}
