// Datos de ejemplo de las capturas de tienda de Pilas: tres niños ficticios
// con dos semanas de juego. Todo pasa por la app de verdad: cada ronda se
// registra con AppState.recordRound (la misma regla de dominio, solo cuenta
// el primer intento) y cada sesión se abre, cuenta su tiempo en primer plano
// y se cierra con un reloj que avanza día por día. Las pegatinas, los niveles
// y las habilidades logradas son los que la app calcula, sin inventar nada.

import 'package:clock/clock.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/engine/mastery.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';

class PilasDemo {
  const PilasDemo({required this.sofia, required this.mateo, required this.valentina});

  /// 7 años (tramo 7-8).
  final Profile sofia;

  /// 5 años (tramo 5-6).
  final Profile mateo;

  /// 10 años (tramo 9-11).
  final Profile valentina;
}

/// Cuántos niveles completa en un juego; con [domina], también domina el
/// último (y logra la habilidad del juego en su tramo).
class _Meta {
  const _Meta(this.juego, this.niveles, {this.domina = false});

  final String juego;
  final int niveles;
  final bool domina;
}

/// Rondas de una ventana de la regla: las justas para subir (con un error), o
/// una ventana floja antes de subir en los niveles altos.
List<bool> _ventana(MasteryRule r, {required bool sube}) {
  final List<bool> v = List<bool>.filled(r.window, true);
  final int errores = sube ? r.window - r.toAdvance : r.window - r.toStay;
  for (int i = 0; i < errores; i++) {
    // Errores salteados (la segunda ronda, la cuarta…), sin repetir lugar.
    int pos = (1 + i * 2) % r.window;
    while (!v[pos]) {
      pos = (pos + 1) % r.window;
    }
    v[pos] = false;
  }
  return v;
}

/// Las rondas que juega un niño, en orden, para llegar a sus metas.
List<MapEntry<GameDef, bool>> _rondas(AgeBand band, List<_Meta> metas) {
  final List<MapEntry<GameDef, bool>> out = <MapEntry<GameDef, bool>>[];
  // Se juega por turnos: un nivel de cada juego por vez, como en casa.
  bool queda = true;
  int nivel = 0;
  while (queda) {
    queda = false;
    for (final _Meta m in metas) {
      final GameDef g = GameRegistry.byId(m.juego)!;
      if (!g.supports(band)) {
        continue;
      }
      final int max = g.levelsFor(band);
      final int hasta = m.domina ? max : m.niveles.clamp(0, max - 1);
      if (nivel >= hasta) {
        continue;
      }
      queda = true;
      if (nivel >= 2) {
        // En los niveles altos cuesta más: una ventana sin subir antes.
        for (final bool ok in _ventana(g.mastery, sube: false)) {
          out.add(MapEntry<GameDef, bool>(g, ok));
        }
      }
      for (final bool ok in _ventana(g.mastery, sube: true)) {
        out.add(MapEntry<GameDef, bool>(g, ok));
      }
    }
    nivel += 1;
  }
  return out;
}

Future<PilasDemo> seedPilasDemo(AppState st, {required DateTime now}) async {
  // La última sesión termina media hora antes de [now]; las demás, a la
  // misma hora de los días anteriores.
  final DateTime fin = now.subtract(const Duration(minutes: 30));
  DateTime t = fin.subtract(const Duration(days: 15));
  return withClock(Clock(() => t), () async {
    Future<Profile> add(String nombre, String avatar, int years) {
      final DateTime b = DateTime(now.year - years, now.month - 2, 1);
      return st.addProfile(nombre: nombre, avatar: avatar, birthYear: b.year, birthMonth: b.month);
    }

    final Profile sofia = await add('Sofía', '1f98a', 7);
    final Profile mateo = await add('Mateo', '1f981', 5);
    final Profile valentina = await add('Valentina', '1f43c', 10);

    Future<void> juega(Profile p, List<_Meta> metas, List<int> minutosPorDia) async {
      final List<MapEntry<GameDef, bool>> rondas = _rondas(p.bandOn(now), metas);
      int siguiente = 0;
      for (int dia = 0; dia < minutosPorDia.length; dia++) {
        final int m = minutosPorDia[dia];
        if (m == 0) {
          continue;
        }
        t = fin.subtract(Duration(days: minutosPorDia.length - 1 - dia)).subtract(Duration(minutes: m + 5));
        final DateTime cierre = t.add(Duration(minutes: m));
        await st.selectProfile(p);
        // Una ronda cada 40 segundos, más o menos; si ya no quedan, sigue
        // jugando a lo libre hasta completar el tiempo del día.
        while (t.isBefore(cierre)) {
          t = t.add(Duration(seconds: 35 + (siguiente % 3) * 5));
          await st.tick();
          if (siguiente < rondas.length && t.isBefore(cierre)) {
            final MapEntry<GameDef, bool> r = rondas[siguiente];
            siguiente += 1;
            await st.recordRound(r.key, p.bandOn(now), r.value);
          }
        }
        await st.endSession();
        await st.selectProfile(null);
      }
    }

    await juega(
      sofia,
      const <_Meta>[
        _Meta('patrones', 4, domina: true),
        _Meta('memoria', 4, domina: true),
        _Meta('cuentos', 1, domina: true),
        _Meta('clasifica', 4, domina: true),
        _Meta('emociones', 4, domina: true),
        _Meta('laberintos', 3),
        _Meta('tienda', 2),
        _Meta('reloj', 1),
        _Meta('palabra', 2),
        _Meta('oracion', 1),
        _Meta('sudoku', 1),
      ],
      <int>[18, 0, 22, 15, 0, 25, 20, 12, 0, 19, 24, 0, 16, 21],
    );
    await juega(
      mateo,
      const <_Meta>[
        _Meta('sonidos', 4, domina: true),
        _Meta('colorear_numeros', 1, domina: true),
        _Meta('rutinas', 4, domina: true),
        _Meta('memoria', 2),
        _Meta('figuras', 2),
        _Meta('tienda', 1),
        _Meta('clasifica', 1),
      ],
      <int>[10, 12, 0, 8, 14, 0, 9, 11, 0, 13, 7, 10, 0, 12],
    );
    await juega(
      valentina,
      const <_Meta>[
        _Meta('laboratorio', 4, domina: true),
        _Meta('decisiones', 4, domina: true),
        _Meta('carrera', 3),
        _Meta('cocina', 2),
        _Meta('sudoku', 3),
      ],
      <int>[0, 25, 30, 0, 20, 28, 0, 0, 26, 22, 0, 30, 18, 0],
    );
    return PilasDemo(sofia: sofia, mateo: mateo, valentina: valentina);
  });
}
