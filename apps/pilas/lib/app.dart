import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/app_state.dart';
import 'core/settings.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'ui/profiles_screen.dart';
import 'ui/rest_screen.dart';

/// Escala de letra de la app: la del sistema por la del ajuste "Texto
/// grande", con un tope para que todo siga cabiendo.
TextScaler pilasTextScaler(TextScaler system, {required bool largeText}) {
  final double sys = system.scale(16) / 16;
  final double factor = (sys * (largeText ? AppSettings.largeTextFactor : 1.0)).clamp(0.8, Dim.maxTextScale).toDouble();
  return TextScaler.linear(factor);
}

/// Raíz de la app: servicios, tema, tiempo de juego y pantalla inicial.
class PilasApp extends StatefulWidget {
  const PilasApp({super.key, required this.services});

  final Services services;

  @override
  State<PilasApp> createState() => _PilasAppState();
}

class _PilasAppState extends State<PilasApp> {
  final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _life;
  bool _restShown = false;

  AppState get _state => widget.services.state;

  @override
  void initState() {
    super.initState();
    _state.sessionLimitMinutes = () => widget.services.settings.sessionLimitMinutes;
    _state.onRestStarted = _showRest;
    // Solo cuenta el tiempo en primer plano: cualquier otro estado (inactiva,
    // oculta, en segundo plano) detiene el reloj de la sesión y la voz.
    _life = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  @override
  void dispose() {
    _life.dispose();
    if (_state.onRestStarted == _showRest) {
      _state.onRestStarted = null;
    }
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      unawaited(_state.resumeClock());
    } else {
      unawaited(widget.services.voice.stop());
      unawaited(_state.pauseClock());
    }
  }

  /// El límite de la sesión se cumplió: la pantalla de descanso tapa todo.
  void _showRest() {
    if (_restShown) {
      return;
    }
    _restShown = true;
    unawaited(widget.services.voice.stop());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final NavigatorState? nav = _nav.currentState;
      if (nav == null) {
        _restShown = false;
        return;
      }
      unawaited(nav.push(RestScreen.route()).whenComplete(() => _restShown = false));
    });
  }

  @override
  Widget build(BuildContext context) {
    final Services services = widget.services;
    return AppScope(
      services: services,
      state: services.state,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (BuildContext context, Widget? _) {
          final ThemeData theme = PilasTheme.light(highContrast: services.settings.highContrast, dyslexiaFont: services.settings.dyslexiaFont);
          return MaterialApp(
            navigatorKey: _nav,
            title: S.appName,
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('es', 'CO'),
            supportedLocales: const <Locale>[Locale('es', 'CO'), Locale('es')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (BuildContext context, Widget? child) {
              final MediaQueryData mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: pilasTextScaler(mq.textScaler, largeText: services.settings.largeText)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const ProfilesScreen(),
          );
        },
      ),
    );
  }
}
