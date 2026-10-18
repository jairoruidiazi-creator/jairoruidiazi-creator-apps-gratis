import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/dates.dart';
import 'core/notifications.dart';
import 'logic/habit_logic.dart';
import 'model/habit.dart';
import 'model/reminder.dart';
import 'ui/habits/habit_detail.dart';
import 'ui/habits/habits_page.dart';
import 'ui/reminders/reminders_page.dart';
import 'ui/settings/settings_page.dart';
import 'ui/summary/summary_page.dart';
import 'ui/theme.dart';
import 'ui/timer/run_bar.dart';
import 'ui/timer/runner_screen.dart';
import 'ui/timer/timer_page.dart';
import 'ui/widgets/common.dart';

class RutinasApp extends StatelessWidget {
  const RutinasApp({super.key, required this.services, this.startup = true, this.initialTab = 0});

  final Services services;

  /// Falso en las pruebas: no se inicializan las notificaciones del sistema.
  final bool startup;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (BuildContext context, Widget? _) {
          final String mode = services.settings.themeMode;
          return MaterialApp(
            title: 'Rutinas',
            debugShowCheckedModeBanner: false,
            theme: RutinasTheme.build(Brightness.light, services.settings.accent),
            darkTheme: RutinasTheme.build(Brightness.dark, services.settings.accent),
            themeMode: mode == 'light' ? ThemeMode.light : (mode == 'dark' ? ThemeMode.dark : ThemeMode.system),
            locale: Locale(services.settings.language),
            supportedLocales: const <Locale>[Locale('es'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: HomeShell(startup: startup, initialTab: initialTab),
          );
        },
      ),
    );
  }
}

/// Pantalla principal con las cinco pestañas.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.startup = true, this.initialTab = 0});

  final bool startup;
  final int initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _index = widget.initialTab;
  Services? _services;
  bool _started = false;

  /// Día de hoy: cambia a medianoche aunque la app siga abierta.
  DateTime _today = dateOnly(clock.now());
  Timer? _dayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dayTimer = Timer.periodic(const Duration(seconds: 30), (Timer _) {
      // Con la app abierta, un recordatorio vencido pasa a la ocurrencia que
      // toca cuando llega la siguiente (como al abrir la app).
      _services?.reminders.rollOverAll();
      _checkDay();
    });
  }

  void _checkDay() {
    final DateTime now = dateOnly(clock.now());
    if (!sameDay(now, _today) && mounted) {
      setState(() => _today = now);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Services s = AppScope.of(context);
    _services = s;
    if (!_started) {
      _started = true;
      s.notices.handler = _onNotice;
      s.reminders.rollOverAll();
      s.timer.restore();
      if (widget.startup) {
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startup(s)));
      }
    }
  }

  Future<void> _startup(Services s) async {
    await s.notices.init();
    await s.notices.sync();
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _services?.notices.handler = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (!s.notices.background) {
        s.flushAll();
        s.timer.setForeground(false);
        s.notices.background = true;
        unawaited(s.notices.sync());
      }
    } else if (state == AppLifecycleState.resumed) {
      // El formato de la hora del teléfono pudo cambiar mientras tanto.
      use24HourClock = WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
      s.timer.setForeground(true);
      s.notices.background = false;
      s.reminders.rollOverAll();
      // Si se concedió o se quitó el permiso de alarmas exactas, se reprograma todo.
      unawaited(s.notices.resumed());
      // El día pudo cambiar mientras la app estaba en segundo plano.
      _checkDay();
    }
  }

  void _notify(String text) {
    if (mounted) {
      showSnack(context, text);
    }
  }

  /// Toques en las notificaciones y sus botones. Los botones de una
  /// notificación vieja (de una ocurrencia que ya pasó) solo la quitan del
  /// panel: no tocan la ocurrencia de ahora.
  void _onNotice(NoticeResponse r) {
    final Services? s = _services;
    if (s == null || !mounted) {
      return;
    }
    final bool es = s.settings.spanish;
    final String route = r.route;
    if (route.startsWith('reminder:')) {
      // Primero se pasa a la ocurrencia que toca, como al abrir la app.
      s.reminders.rollOverAll();
      final Reminder? rem = s.reminders.byId(route.substring('reminder:'.length));
      final DateTime? occ = r.occurrence;
      final bool current = rem != null && !rem.done && (occ == null || occ.millisecondsSinceEpoch == rem.dueAt.millisecondsSinceEpoch);
      _select(1);
      if (r.actionId != null && !current) {
        final int? id = r.id;
        if (id != null) {
          unawaited(s.notices.dismissOne(id));
        }
        if (rem == null) {
          _notify(es ? 'Ese recordatorio ya no existe.' : 'That reminder no longer exists.');
        } else if (rem.done) {
          _notify(es ? 'Ese recordatorio ya estaba hecho.' : 'That reminder was already done.');
        } else {
          _notify(es ? 'Ese aviso era de una vez anterior: el recordatorio de ahora sigue pendiente.' : 'That alert was from an earlier time: the current reminder is still pending.');
        }
        return;
      }
      if (rem != null && r.actionId == 'done') {
        s.reminders.complete(rem.id);
        unawaited(s.notices.dismissReminder(rem));
      } else if (rem != null && r.actionId == 'snooze') {
        s.reminders.snooze(rem.id, 10);
        unawaited(s.notices.dismissReminder(rem));
      }
    } else if (route.startsWith('habit:')) {
      final List<String> parts = route.split(':');
      final Habit? h = parts.length >= 2 ? s.habits.byId(parts[1]) : null;
      final DateTime day = (parts.length >= 3 ? parseDayKey(parts[2]) : null) ?? dateOnly(clock.now());
      _select(0);
      if (h == null) {
        return;
      }
      if (r.actionId == 'done') {
        if (!HabitLogic.isDone(h, s.habits.entry(h.id, day), day)) {
          s.habits.setValue(h.id, day, h.targetOn(day));
        }
        unawaited(s.notices.dismissHabit(h, day));
      } else if (r.actionId == 'plus') {
        s.habits.addValue(h.id, day, 1);
        unawaited(s.notices.dismissHabit(h, day));
      } else if (r.actionId == 'start' && h.kind == HabitKind.timed && sameDay(day, clock.now())) {
        unawaited(_startHabitTimer(s, h));
      } else if (h.kind == HabitKind.timed) {
        // El aviso de un hábito con tiempo abre el hábito, con su botón para empezar.
        unawaited(HabitDetailScreen.open(context, h.id));
      }
    } else if (route == 'timer') {
      _select(2);
      if (s.timer.run != null || s.timer.finished != null) {
        unawaited(RunnerScreen.open(context));
      }
    }
  }

  /// «Empezar» en el aviso de un hábito con tiempo: el temporizador con lo
  /// que falta de hoy.
  Future<void> _startHabitTimer(Services s, Habit h) async {
    final DateTime today = dateOnly(clock.now());
    final int value = s.habits.entry(h.id, today)?.value ?? 0;
    final int target = h.targetOn(today);
    final int left = value >= target ? target : target - value;
    final bool ok = await RunnerScreen.beforeStart(context);
    if (!ok || !mounted) {
      return;
    }
    s.timer.startHabit(h, left);
    unawaited(s.notices.dismissHabit(h, today));
    if (mounted) {
      unawaited(RunnerScreen.open(context));
    }
  }

  /// Va a una pestaña. Cierra lo que esté abierto encima, salvo una pantalla
  /// con cambios sin guardar (que lo pide con PopScope): esa se queda.
  void _select(int i) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst || r.popDisposition == RoutePopDisposition.doNotPop);
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      HabitsPage(today: _today),
      RemindersPage(today: _today),
      const TimerPage(),
      SummaryPage(today: _today),
      const SettingsPage(),
    ];
    final List<_Dest> dests = <_Dest>[
      _Dest(Icons.check_circle_outline, Icons.check_circle, t(context, 'Hábitos', 'Habits')),
      _Dest(Icons.notifications_none, Icons.notifications, t(context, 'Avisos', 'Reminders')),
      _Dest(Icons.timer_outlined, Icons.timer, t(context, 'Tiempo', 'Timer')),
      _Dest(Icons.insights_outlined, Icons.insights, t(context, 'Resumen', 'Summary')),
      _Dest(Icons.settings_outlined, Icons.settings, t(context, 'Ajustes', 'Settings')),
    ];
    // Cada pestaña con su propio ScaffoldMessenger: los avisos de abajo
    // (SnackBar) salen dentro de la pestaña y suben su botón flotante en vez
    // de taparlo desde la pantalla principal.
    final Widget stack = IndexedStack(index: _index, children: <Widget>[for (final Widget p in pages) ScaffoldMessenger(child: p)]);
    final bool wide = isWideLayout(context);
    void select(int i) => setState(() => _index = i);
    return Scaffold(
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
                      for (final _Dest d in dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: stack),
              ],
            )
          : stack,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // En tableta no hay barra de navegación debajo: la del temporizador
          // deja ella misma el margen de la barra del sistema.
          RunBar(bottomSafeArea: wide),
          if (!wide)
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: select,
              destinations: <NavigationDestination>[
                for (final _Dest d in dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
              ],
            ),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.selected, this.label);

  final IconData icon;
  final IconData selected;
  final String label;
}
