import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../audio/audio_engine.dart';
import '../audio/metronome.dart';
import '../audio/tuner.dart';
import 'app_state.dart';
import 'settings.dart';
import 'storage.dart';

/// Servicios compartidos.
class Services {
  const Services({required this.settings, required this.state, required this.store, required this.engine, required this.metronome, required this.tuner});

  final AppSettings settings;
  final AppState state;
  final JsonStore store;
  final AudioEngine engine;
  final Metronome metronome;
  final Tuner tuner;
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
String t(BuildContext context, String es, String en) => AppScope.of(context).settings.spanish ? es : en;

/// Formato de minutos como "1 h 05 min" / "12 min".
String formatMinutes(int seconds, {bool spanish = true}) {
  final int m = seconds ~/ 60;
  if (m < 60) {
    return '$m min';
  }
  final int h = m ~/ 60;
  final int r = m % 60;
  return '$h h ${r.toString().padLeft(2, '0')} min';
}

String formatClock(int ms) {
  final int s = ms ~/ 1000;
  final int m = s ~/ 60;
  final int r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
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
