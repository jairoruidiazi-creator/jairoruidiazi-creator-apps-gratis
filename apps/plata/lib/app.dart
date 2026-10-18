import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/reminders.dart';
import 'model/models.dart';
import 'ui/budgets/budgets_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/more/more_screen.dart';
import 'ui/reports/reports_screen.dart';
import 'ui/transactions/tx_editor.dart';
import 'ui/transactions/tx_list_screen.dart';
import 'ui/widgets/adaptive.dart';

class PlataColors {
  PlataColors._();

  static const Color verde = Color(0xFF0B3D2E);
  static const Color menta = Color(0xFF2E7D32);
  static const Color oro = Color(0xFFF2B33D);
}

class PlataApp extends StatelessWidget {
  const PlataApp({super.key, required this.services, this.startup = true});

  final Services services;

  /// Falso en pruebas: no se procesan programados ni se hacen copias ni se
  /// consultan tasas al arrancar.
  final bool startup;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (BuildContext context, Widget? _) {
          final String mode = services.settings.themeMode;
          ThemeData theme(Brightness b) => ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: PlataColors.verde, brightness: b, secondary: PlataColors.oro),
                // Flechas y marcas que Roboto no trae (subconjunto de DejaVu Sans).
                fontFamilyFallback: const <String>['Simbolos'],
                cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: const EdgeInsets.symmetric(vertical: 4)),
                filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(56, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
                inputDecorationTheme: const InputDecorationTheme(isDense: true),
              );
          return MaterialApp(
            title: 'Plata',
            debugShowCheckedModeBanner: false,
            theme: theme(Brightness.light),
            darkTheme: theme(Brightness.dark),
            themeMode: mode == 'light' ? ThemeMode.light : (mode == 'dark' ? ThemeMode.dark : ThemeMode.system),
            locale: Locale(services.settings.language),
            supportedLocales: const <Locale>[Locale('es'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (BuildContext context, Widget? child) => _LockGate(child: child ?? const SizedBox.shrink()),
            home: HomeShell(startup: startup),
          );
        },
      ),
    );
  }
}

/// Cubre la app con la pantalla de bloqueo mientras [AppLock.locked].
class _LockGate extends StatelessWidget {
  const _LockGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.lock,
      builder: (BuildContext context, Widget? _) => Stack(
        children: <Widget>[
          child,
          if (s.lock.locked) const Positioned.fill(child: LockScreen()),
        ],
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0, this.startup = true});

  final int initialIndex;
  final bool startup;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _index = widget.initialIndex;
  Services? _s;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _s ??= AppScope.of(context);
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startup()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_s?.notices.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final Services? s = _s;
    if (s == null) {
      return;
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      s.lock.onBackground();
      unawaited(s.ledger.flush());
    } else if (state == AppLifecycleState.resumed) {
      s.lock.onForeground();
      if (widget.startup) {
        unawaited(_resume(s));
      }
    }
  }

  /// Tareas de arranque: programados vencidos, avisos pendientes, copia
  /// diaria, tasas y recordatorios.
  Future<void> _startup() async {
    final Services? s = _s;
    if (s == null || !widget.startup) {
      return;
    }
    try {
      final List<Tx> posted = s.ledger.processScheduled();
      if (posted.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.settings.spanish ? 'Se anotaron ${posted.length} movimientos programados.' : '${posted.length} scheduled transactions were logged.')));
      }
    } catch (e) {
      debugPrint('Programados: $e');
    }
    await _resume(s);
    try {
      if (s.settings.autoBackup) {
        await s.backups.autoBackup();
      }
    } catch (e) {
      debugPrint('Copia automática: $e');
    }
    await _refreshRates(s);
    try {
      await s.notifier.init();
      await Reminders.sync(ledger: s.ledger, settings: s.settings, notifier: s.notifier, spanish: s.settings.spanish);
    } catch (e) {
      debugPrint('Recordatorios: $e');
    }
  }

  Future<void> _resume(Services s) async {
    try {
      s.ledger.processScheduled();
      await s.notices.start();
    } catch (e) {
      debugPrint('Avisos: $e');
    }
  }

  Future<void> _refreshRates(Services s) async {
    final Set<String> foreign = <String>{...s.settings.extraCurrencies, ...s.ledger.accounts.map((Account a) => a.currency)}..remove(s.ledger.baseCurrency);
    if (!s.settings.ratesAuto || foreign.isEmpty) {
      return;
    }
    final DateTime? last = s.settings.lastRatesAttempt;
    if (last != null && clock.now().difference(last).inHours < 20) {
      return;
    }
    s.settings.lastRatesAttempt = clock.now();
    await s.settings.save();
    try {
      if (await s.rates.refresh(s.ledger.rates, base: s.ledger.baseCurrency, currencies: foreign)) {
        s.ledger.save();
      }
    } catch (e) {
      debugPrint('Tasas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      HomeScreen(onGoTo: (int i) => setState(() => _index = i)),
      const TxListScreen(),
      const BudgetsScreen(),
      const ReportsScreen(),
      const MoreScreen(),
    ];
    final List<_Dest> items = <_Dest>[
      _Dest(Icons.home_outlined, Icons.home, t(context, 'Inicio', 'Home')),
      _Dest(Icons.receipt_long_outlined, Icons.receipt_long, t(context, 'Movimientos', 'Transactions')),
      _Dest(Icons.savings_outlined, Icons.savings, t(context, 'Presupuestos', 'Budgets')),
      _Dest(Icons.bar_chart_outlined, Icons.bar_chart, t(context, 'Informes', 'Reports')),
      _Dest(Icons.more_horiz, Icons.more_horiz, t(context, 'Más', 'More')),
    ];
    void add() => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TxEditor()));
    final Widget body = IndexedStack(index: _index, children: pages);
    if (isWideLayout(context)) {
      // Tableta: menú lateral con el botón de anotar arriba.
      return Scaffold(
        body: Row(
          children: <Widget>[
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (int i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: FloatingActionButton(heroTag: null, elevation: 0, tooltip: t(context, 'Anotar movimiento', 'Log transaction'), onPressed: add, child: const Icon(Icons.add)),
                ),
                destinations: <NavigationRailDestination>[
                  for (final _Dest it in items) NavigationRailDestination(icon: Icon(it.icon), selectedIcon: Icon(it.selected), label: Text(it.label)),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      floatingActionButton: _index <= 1
          ? FloatingActionButton(heroTag: null, tooltip: t(context, 'Anotar movimiento', 'Log transaction'), onPressed: add, child: const Icon(Icons.add))
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          for (final _Dest it in items) NavigationDestination(icon: Icon(it.icon), selectedIcon: Icon(it.selected), label: it.label),
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
