import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'audio/take_recorder.dart';
import 'core/app_scope.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'ui/drone/drone_screen.dart';
import 'ui/metronome/metronome_screen.dart';
import 'ui/practice/practice_screen.dart';
import 'ui/recorder/recorder_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/tuner/tuner_screen.dart';

/// Sabe cuándo una pantalla (hoja, diálogo o página) tapa la principal.
final RouteObserver<ModalRoute<dynamic>> claveRouteObserver = RouteObserver<ModalRoute<dynamic>>();

class ClaveApp extends StatelessWidget {
  const ClaveApp({super.key, required this.services, this.initialIndex = 0});

  final Services services;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      // Solo el idioma y el tema reconstruyen la app entera.
      child: ListenableBuilder(
        listenable: services.settings.appearance,
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
            navigatorObservers: <NavigatorObserver>[claveRouteObserver],
            home: HomeShell(initialIndex: initialIndex),
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver, RouteAware {
  late int _index = widget.initialIndex;
  Services? _services;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _covered = false;
  bool _subscribed = false;
  bool _noticesShown = false;
  bool? _wakelock;
  String? _pendingMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Services s = AppScope.of(context);
    if (!identical(_services, s)) {
      _services?.recorder.removeListener(_applyWakelock);
      _services = s;
      s.recorder.addListener(_applyWakelock);
      s.recorder.onAutoStop = _onTakeAutoStop;
    }
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (!_subscribed && route != null) {
      _subscribed = true;
      claveRouteObserver.subscribe(this, route);
    }
    _applyActivity();
    if (!_noticesShown) {
      _noticesShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showStartupNotices());
    }
  }

  /// El afinador escucha solo con su pestaña a la vista, sin nada encima y
  /// con la app al frente.
  void _applyActivity() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    final bool foreground = _lifecycle == AppLifecycleState.resumed;
    s.tuner.setActive(foreground && !_covered && _index == 0);
    _applyWakelock();
  }

  void _applyWakelock() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    final bool foreground = _lifecycle == AppLifecycleState.resumed;
    final bool on = s.settings.keepAwake && foreground && (_index <= 2 || s.recorder.recording);
    if (_wakelock == on) {
      return;
    }
    _wakelock = on;
    unawaited(WakelockPlus.toggle(enable: on).catchError((Object e) {}));
  }

  @override
  void didPushNext() {
    _covered = true;
    _applyActivity();
  }

  @override
  void didPopNext() {
    _covered = false;
    _applyActivity();
    _services?.tuner.recheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final Services? s = _services;
    _lifecycle = state;
    _applyActivity();
    if (s == null) {
      return;
    }
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      unawaited(s.practice.checkpoint());
      // Android no deja seguir sonando ni grabando a una app en segundo plano
      // sin un servicio en primer plano (que la v1 no tiene): se detiene todo
      // de forma explícita en vez de cortarse a medias.
      if (defaultTargetPlatform == TargetPlatform.android) {
        final bool wasPlaying = s.metronome.running || s.drone.sounding;
        if (s.metronome.running) {
          unawaited(s.metronome.stop());
        }
        if (s.drone.sounding) {
          unawaited(s.drone.stopAll());
        }
        if (s.recorder.recording) {
          unawaited(s.recorder.stopForBackground());
        } else if (wasPlaying) {
          _pendingMessage = t(context, 'El metrónomo y el tono se detuvieron al salir de la app.', 'The metronome and drone stopped when you left the app.');
        }
      }
    } else if (state == AppLifecycleState.detached) {
      unawaited(s.practice.closeAll());
    } else if (state == AppLifecycleState.resumed) {
      s.tuner.recheck();
      final String? msg = _pendingMessage;
      _pendingMessage = null;
      if (msg != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _onTakeAutoStop(TakeResult? result, TakeStopReason reason) {
    final Services? s = _services;
    // La toma pasa a la lista aunque la pantalla de la grabadora no esté.
    if (s != null && result != null) {
      unawaited(s.state.addTake(result, takeWord: s.settings.spanish ? 'Toma' : 'Take'));
    }
    if (!mounted) {
      return;
    }
    final String msg = reason == TakeStopReason.background
        ? t(context, 'La grabación se detuvo y se guardó al salir de la app: Android no deja grabar en segundo plano.', 'The recording stopped and was saved when you left the app: Android does not allow recording in the background.')
        : t(context, 'Una llamada o el asistente interrumpieron la grabación; lo grabado quedó guardado.', 'A call or the assistant interrupted the recording; what was recorded is saved.');
    if (_lifecycle == AppLifecycleState.resumed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      _pendingMessage = msg;
    }
  }

  void _showStartupNotices() {
    final Services? s = _services;
    if (s == null || !mounted) {
      return;
    }
    final List<String> lines = <String>[
      for (final StoreNotice n in s.store.notices) _noticeText(n),
      if (s.state.recoveredTakes > 0)
        s.state.recoveredTakes == 1
            ? t(context, 'Se rescató una toma que quedó a medias al cerrarse la app.', 'A take left unfinished when the app closed was recovered.')
            : t(context, 'Se rescataron ${s.state.recoveredTakes} tomas que quedaron a medias.', '${s.state.recoveredTakes} unfinished takes were recovered.'),
    ];
    if (lines.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lines.join('\n')), duration: const Duration(seconds: 8)));
  }

  String _noticeText(StoreNotice n) {
    final String what = n.file.startsWith('presets')
        ? t(context, 'los preajustes', 'presets')
        : (n.file.startsWith('practice') ? t(context, 'el registro de práctica', 'the practice log') : t(context, 'la lista de grabaciones', 'the recordings list'));
    if (n.recovered) {
      return t(context, 'El archivo de $what estaba dañado: se recuperó la copia anterior.', 'The file for $what was damaged: the previous copy was restored.');
    }
    return t(context, 'El archivo de $what estaba dañado y se guardó aparte (${n.keptAs ?? ''}).', 'The file for $what was damaged and was set aside (${n.keptAs ?? ''}).');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    claveRouteObserver.unsubscribe(this);
    _services?.recorder.removeListener(_applyWakelock);
    _services?.tuner.setActive(false);
    unawaited(_services?.practice.closeAll());
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) {
      return;
    }
    setState(() => _index = i);
    _applyActivity();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> titles = <String>[
      t(context, 'Afinador', 'Tuner'),
      t(context, 'Metrónomo', 'Metronome'),
      t(context, 'Tono y teclado', 'Drone & keyboard'),
      t(context, 'Grabadora', 'Recorder'),
      t(context, 'Práctica', 'Practice'),
    ];
    final List<_Dest> dests = <_Dest>[
      _Dest(Icons.graphic_eq_rounded, t(context, 'Afinador', 'Tuner')),
      _Dest(Icons.timer_outlined, t(context, 'Metrónomo', 'Metronome')),
      _Dest(Icons.piano_rounded, t(context, 'Tono', 'Drone')),
      _Dest(Icons.mic_none_rounded, t(context, 'Grabar', 'Record')),
      _Dest(Icons.insights_rounded, t(context, 'Práctica', 'Practice')),
    ];
    final Widget stack = IndexedStack(
      index: _index,
      children: <Widget>[
        TunerScreen(active: _index == 0),
        MetronomeScreen(active: _index == 1),
        DroneScreen(active: _index == 2),
        RecorderScreen(active: _index == 3),
        PracticeScreen(active: _index == 4),
      ],
    );
    // En tabletas (600 dp o más de ancho) las herramientas van en un riel lateral.
    final bool wide = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
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
                  // Con letra grande en horizontal (un teléfono acostado), las
                  // cinco herramientas no caben a lo alto: el riel se desplaza.
                  // Si caben, se ve igual que antes.
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints c) => SingleChildScrollView(
                      primary: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            selectedIndex: _index,
                            onDestinationSelected: _select,
                            labelType: NavigationRailLabelType.all,
                            destinations: <NavigationRailDestination>[
                              for (final _Dest d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
                            ],
                          ),
                        ),
                      ),
                    ),
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
              onDestinationSelected: _select,
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
