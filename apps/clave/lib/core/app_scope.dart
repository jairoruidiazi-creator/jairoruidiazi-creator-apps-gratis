import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../audio/drone.dart';
import '../audio/metronome.dart';
import '../audio/take_recorder.dart';
import '../audio/tuner.dart';
import 'app_state.dart';
import 'platform_actions.dart';
import 'practice_log.dart';
import 'settings.dart';
import 'storage.dart';

/// Servicios compartidos.
class Services {
  const Services({
    required this.settings,
    required this.state,
    required this.practice,
    required this.store,
    required this.engine,
    required this.metronome,
    required this.tuner,
    required this.drone,
    required this.recorder,
    required this.platform,
  });

  final AppSettings settings;
  final AppState state;
  final PracticeLog practice;
  final JsonStore store;
  final AudioEngine engine;
  final Metronome metronome;
  final Tuner tuner;
  final DroneController drone;
  final TakeRecorder recorder;
  final PlatformActions platform;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final Services services;

  static Services of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No hay AppScope en el árbol');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}

/// Texto en el idioma de la app: `t(context, 'Afinador', 'Tuner')`.
///
/// Además deja al widget atado al locale de la app: al cambiar el idioma en
/// Ajustes, MaterialApp cambia de locale y todo lo que usa `t` se dibuja de
/// nuevo, también la barra superior y la de navegación.
String t(BuildContext context, String es, String en) {
  Localizations.maybeLocaleOf(context);
  return AppScope.of(context).settings.spanish ? es : en;
}

/// Si la app está en español (y depende del locale, como [t]).
bool isSpanish(BuildContext context) {
  Localizations.maybeLocaleOf(context);
  return AppScope.of(context).settings.spanish;
}

/// Formato de minutos como "1 h 05 min" / "12 min" / "2 h".
String formatMinutes(int seconds) {
  final int m = seconds ~/ 60;
  if (m < 60) {
    return '$m min';
  }
  final int h = m ~/ 60;
  final int r = m % 60;
  return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')} min';
}

/// Tiempo de práctica: segundos si no llega al minuto ("45 s"), si no como
/// [formatMinutes].
String formatPracticeTime(int seconds) => seconds > 0 && seconds < 60 ? '$seconds s' : formatMinutes(seconds);

String formatClock(int ms) {
  final int s = ms ~/ 1000;
  final int m = s ~/ 60;
  final int r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

/// Número con [decimals] decimales y la coma del español o el punto del inglés.
String formatDecimal(double v, {required bool spanish, int decimals = 1}) {
  final String s = v.toStringAsFixed(decimals);
  return spanish ? s.replaceAll('.', ',') : s;
}

/// Porcentaje con el espacio del español ("30 %") o sin él ("30%").
String formatPercent(double fraction, {required bool spanish}) {
  final int p = (fraction * 100).round();
  return spanish ? '$p %' : '$p%';
}

/// Fecha y hora cortas según el idioma de la app.
String formatDateTime(BuildContext context, DateTime d) {
  final MaterialLocalizations l = MaterialLocalizations.of(context);
  final String time = l.formatTimeOfDay(TimeOfDay.fromDateTime(d), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
  return '${l.formatShortDate(d)} $time';
}

/// Libera un controlador de texto cuando el diálogo que lo usaba ya cerró
/// (la animación de salida sigue usándolo unos cuadros).
void disposeLater(List<ChangeNotifier> controllers) {
  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final ChangeNotifier c in controllers) {
      c.dispose();
    }
  });
}
