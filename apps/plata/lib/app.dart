import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/reminders.dart';
import 'model/models.dart';
import 'ui/budgets/budgets_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/more/backup_screen.dart';
import 'ui/more/more_screen.dart';
import 'ui/reports/reports_screen.dart';
import 'ui/transactions/tx_editor.dart';
import 'ui/transactions/tx_list_screen.dart';
import 'ui/widgets/adaptive.dart';
import 'ui/widgets/live.dart';

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

/// Cubre la app con la pantalla de bloqueo mientras [AppLock.locked], o con
/// una cubierta mientras [AppLock.obscured]. Lo que queda detrás no se lee con
/// TalkBack ni VoiceOver, no recibe el foco del teclado y no recibe toques. El
/// árbol de abajo es siempre el mismo (solo cambian las banderas), así que la
/// navegación y lo que se estaba escribiendo se conservan.
class _LockGate extends StatelessWidget {
  const _LockGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.lock,
      builder: (BuildContext context, Widget? _) {
        final bool covered = s.lock.locked || s.lock.obscured;
        return Stack(
          children: <Widget>[
            ExcludeSemantics(
              excluding: covered,
              child: ExcludeFocus(
                excluding: covered,
                child: AbsorbPointer(
                  absorbing: covered,
                  child: TickerMode(enabled: !covered, child: child),
                ),
              ),
            ),
            // El candado va encima del Navigator: su propio Overlay deja que
            // funcionen las ayudas emergentes de sus botones.
            if (s.lock.locked)
              Positioned.fill(child: BlockSemantics(child: Overlay.wrap(child: const LockScreen())))
            else if (s.lock.obscured)
              const Positioned.fill(child: BlockSemantics(child: PrivacyCover())),
          ],
        );
      },
    );
  }
}

/// Lo que se ve mientras la app está fuera de primer plano con clave activa.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: PlataColors.verde,
      child: Center(child: Icon(Icons.lock, size: 56, color: Colors.white)),
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
  ReminderScheduler? _reminders;

  /// Las pestañas se crean una sola vez: cambiar de pestaña no las
  /// reconstruye. Cada una escucha el libro y los ajustes (idioma, saldos
  /// ocultos, centavos) con LiveBuilder y se redibuja solo si se está viendo.
  List<Widget>? _pages;

  List<Widget> _pagesFor() => _pages ??= <Widget>[
        HomeScreen(onGoTo: _goTo),
        const TxListScreen(),
        const BudgetsScreen(),
        const ReportsScreen(),
        const MoreScreen(),
      ];

  void _goTo(int i) => setState(() => _index = i);

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
    _reminders?.stop();
    unawaited(_s?.notices.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final Services? s = _s;
    if (s == null) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      // En iOS la vista de apps recientes se toma al dejar de estar activa.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        s.lock.onInactive();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      s.lock.onBackground();
      unawaited(s.ledger.flush().catchError((Object e) => debugPrint('Guardar al salir: $e')));
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
        final int n = posted.length;
        final String message = s.settings.spanish
            ? (n == 1 ? 'Se anotó 1 movimiento programado.' : 'Se anotaron $n movimientos programados.')
            : (n == 1 ? '1 scheduled transaction was logged.' : '$n scheduled transactions were logged.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      _reminders = ReminderScheduler(ledger: s.ledger, settings: s.settings, notifier: s.notifier)..start();
      await _reminders!.syncNow();
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
    // El día pudo cambiar mientras la app estaba en el fondo.
    unawaited(_reminders?.syncNow());
  }

  Future<void> _refreshRates(Services s) async {
    final Set<String> foreign = <String>{...s.settings.extraCurrencies, ...s.ledger.accounts.map((Account a) => a.currency)}..remove(s.ledger.baseCurrency);
    if (!s.settings.ratesAuto || foreign.isEmpty || s.ledger.readOnly) {
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
    final Services s = AppScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: s.ledger.readOnlyState,
      builder: (BuildContext context, bool readOnly, Widget? _) => readOnly ? const BackupScreen(recovery: true) : _tabs(context),
    );
  }

  Widget _tabs(BuildContext context) {
    final List<Widget> pages = _pagesFor();
    final List<_Dest> items = <_Dest>[
      _Dest(Icons.home_outlined, Icons.home, t(context, 'Inicio', 'Home')),
      _Dest(Icons.receipt_long_outlined, Icons.receipt_long, t(context, 'Movimientos', 'Transactions')),
      _Dest(Icons.savings_outlined, Icons.savings, t(context, 'Presupuestos', 'Budgets')),
      _Dest(Icons.bar_chart_outlined, Icons.bar_chart, t(context, 'Informes', 'Reports')),
      _Dest(Icons.more_horiz, Icons.more_horiz, t(context, 'Más', 'More')),
    ];
    void add() => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TxEditor()));
    final Widget body = IndexedStack(
      index: _index,
      children: <Widget>[
        // Las pestañas ocultas no se redibujan con cada cambio del libro: se
        // ponen al día al volver a mostrarse (ver LiveBuilder).
        for (int i = 0; i < pages.length; i++) TabVisibility(visible: i == _index, child: TickerMode(enabled: i == _index, child: pages[i])),
      ],
    );
    if (isWideLayout(context)) {
      // Tableta: menú lateral con el botón de anotar arriba.
      return Scaffold(
        body: Row(
          children: <Widget>[
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _goTo,
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
        onDestinationSelected: _goTo,
        labelTextStyle: _navLabelStyle(context, items),
        destinations: <NavigationDestination>[
          for (final _Dest it in items) NavigationDestination(icon: Icon(it.icon), selectedIcon: Icon(it.selected), label: it.label),
        ],
      ),
    );
  }
}

/// Estilo de las etiquetas de la barra inferior. En un teléfono de 360 dp cada
/// pestaña mide 72 dp y "Presupuestos" o "Transactions" no caben con la letra
/// estándar: se partirían en dos líneas o quedarían pegadas a la vecina. La
/// letra se reduce lo justo para que la etiqueta más larga quepa con aire, y
/// todas quedan del mismo tamaño.
WidgetStateProperty<TextStyle?> _navLabelStyle(BuildContext context, List<_Dest> items) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme cs = theme.colorScheme;
  final TextStyle base = (theme.textTheme.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(letterSpacing: 0);
  final double slot = (MediaQuery.sizeOf(context).width - MediaQuery.paddingOf(context).horizontal) / items.length;
  // La barra limita a 1,3 la escala del texto de sus etiquetas.
  final TextScaler scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
  final double room = slot - 8;
  double widestAt(double size) {
    double widest = 0;
    for (final _Dest it in items) {
      final TextPainter p = TextPainter(text: TextSpan(text: it.label, style: base.copyWith(fontSize: size)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      widest = math.max(widest, p.width);
      p.dispose();
    }
    return widest;
  }

  double size = base.fontSize ?? 12;
  // La escala del sistema puede no ser lineal: se ajusta en pocos pasos.
  for (int i = 0; i < 3 && room > 0; i++) {
    final double widest = widestAt(size);
    if (widest <= room) {
      break;
    }
    size = math.max(9.0, size * room / widest);
  }
  final TextStyle fitted = base.copyWith(fontSize: size);
  return WidgetStateProperty.resolveWith((Set<WidgetState> states) => fitted.copyWith(
        color: states.contains(WidgetState.disabled) ? cs.onSurfaceVariant.withValues(alpha: 0.38) : (states.contains(WidgetState.selected) ? cs.onSurface : cs.onSurfaceVariant),
      ));
}

class _Dest {
  const _Dest(this.icon, this.selected, this.label);

  final IconData icon;
  final IconData selected;
  final String label;
}
