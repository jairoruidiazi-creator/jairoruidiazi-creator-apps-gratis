import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/dates.dart';
import 'core/notifications.dart';
import 'model/habit.dart';
import 'model/reminder.dart';
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
    _dayTimer = Timer.periodic(const Duration(seconds: 30), (Timer _) => _checkDay());
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
      s.timer.setForeground(true);
      s.notices.background = false;
      s.reminders.rollOverAll();
      unawaited(s.notices.sync());
      // El día pudo cambiar mientras la app estaba en segundo plano.
      _checkDay();
    }
  }

  /// Toques en las notificaciones y sus botones.
  void _onNotice(NoticeResponse r) {
    final Services? s = _services;
    if (s == null || !mounted) {
      return;
    }
    final String route = r.route;
    if (route.startsWith('reminder:')) {
      final Reminder? rem = s.reminders.byId(route.substring('reminder:'.length));
      if (rem != null && r.actionId == 'done') {
        final DateTime alert = rem.alertAt;
        s.reminders.complete(rem.id);
        unawaited(s.notices.dismissReminder(rem, alert));
      } else if (rem != null && r.actionId == 'snooze') {
        final DateTime alert = rem.alertAt;
        s.reminders.snooze(rem.id, 10);
        unawaited(s.notices.dismissReminder(rem, alert));
      }
      _select(1);
    } else if (route.startsWith('habit:')) {
      final List<String> parts = route.split(':');
      final Habit? h = parts.length >= 2 ? s.habits.byId(parts[1]) : null;
      final DateTime day = (parts.length >= 3 ? parseDayKey(parts[2]) : null) ?? dateOnly(clock.now());
      if (h != null && r.actionId == 'done') {
        if ((s.habits.entry(h.id, day)?.value ?? 0) < h.target) {
          s.habits.setValue(h.id, day, h.target);
        }
        unawaited(s.notices.dismissHabit(h, day));
      } else if (h != null && r.actionId == 'plus') {
        s.habits.addValue(h.id, day, 1);
        unawaited(s.notices.dismissHabit(h, day));
      }
      _select(0);
    } else if (route == 'timer') {
      _select(2);
      if (s.timer.run != null || s.timer.finished != null) {
        unawaited(RunnerScreen.open(context));
      }
    }
  }

  void _select(int i) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
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
          const RunBar(),
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
