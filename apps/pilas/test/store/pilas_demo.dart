// Datos de ejemplo de las capturas de tienda de Pilas: tres niños ficticios
// con dos semanas de juego. El avance se registra con la misma regla de
// dominio de la app (AppState.recordRound), así que las pegatinas y las
// habilidades logradas son las que la app daría.

import 'package:pilas/core/app_state.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/model/progress.dart';

class PilasDemo {
  const PilasDemo({required this.sofia, required this.mateo, required this.valentina});

  /// 7 años (tramo 7-8).
  final Profile sofia;

  /// 5 años (tramo 5-6).
  final Profile mateo;

  /// 10 años (tramo 9-11).
  final Profile valentina;
}

/// Fecha de nacimiento para tener [years] años cumplidos hace dos meses.
DateTime _born(DateTime now, int years) => DateTime(now.year - years, now.month - 2, 1);

Future<PilasDemo> seedPilasDemo(AppState st, {required DateTime now}) async {
  Future<Profile> add(String nombre, String avatar, int years) {
    final DateTime b = _born(now, years);
    return st.addProfile(nombre: nombre, avatar: avatar, birthYear: b.year, birthMonth: b.month);
  }

  final Profile sofia = await add('Sofía', '1f98a', 7);
  final Profile mateo = await add('Mateo', '1f981', 5);
  final Profile valentina = await add('Valentina', '1f43c', 10);

  // Rondas jugadas por juego: niveles que completa y alguna equivocación.
  Future<void> play(Profile p, Map<String, int> levelsByGame) async {
    await st.selectProfile(p);
    final AgeBand band = p.band;
    int miss = 0;
    for (final MapEntry<String, int> e in levelsByGame.entries) {
      final GameDef game = GameRegistry.all.firstWhere((GameDef g) => g.id == e.key);
      if (!game.supports(band)) {
        continue;
      }
      final int levels = e.value.clamp(1, game.levelsFor(band));
      for (int level = 0; level < levels; level++) {
        for (int r = 0; r < 4; r++) {
          // Una de cada cinco rondas sale mal, sin bajar de nivel (3 de 4 bastan).
          final bool ok = r != (miss++ % 5);
          await st.recordRound(game, band, ok || r == 3);
        }
      }
    }
    await st.endSession();
  }

  await play(sofia, <String, int>{'tienda': 3, 'reloj': 2, 'patrones': 4, 'memoria': 3, 'palabra': 2, 'oracion': 2, 'clasifica': 3, 'laberintos': 3, 'sudoku': 1, 'emociones': 2});
  await play(mateo, <String, int>{'memoria': 2, 'sonidos': 3, 'colorear_numeros': 1, 'figuras': 2, 'clasifica': 1});
  await play(valentina, <String, int>{'carrera': 3, 'cocina': 2, 'laboratorio': 2, 'sudoku': 3, 'decisiones': 2});

  // Dos semanas de sesiones cortas, con días sin pantalla.
  final Map<Profile, List<int>> minutes = <Profile, List<int>>{
    sofia: <int>[18, 0, 22, 15, 0, 25, 20, 12, 0, 19, 24, 0, 16, 21],
    mateo: <int>[10, 12, 0, 8, 14, 0, 9, 11, 0, 13, 7, 10, 0, 12],
    valentina: <int>[0, 25, 30, 0, 20, 28, 0, 0, 26, 22, 0, 30, 18, 0],
  };
  final DateTime day = DateTime(now.year, now.month, now.day);
  for (final MapEntry<Profile, List<int>> e in minutes.entries) {
    final ProfileProgress prog = st.progressOf(e.key.id);
    for (int i = 0; i < e.value.length; i++) {
      final int m = e.value[i];
      if (m == 0) {
        continue;
      }
      final DateTime start = day.subtract(Duration(days: 13 - i)).add(Duration(hours: 16, minutes: 10 + i * 3));
      final int rounds = m ~/ 2 + 3;
      prog.sessions.add(SessionLog(start: start, seconds: m * 60, rounds: rounds, correct: (rounds * 0.8).round()));
    }
    prog.sessions.sort((SessionLog a, SessionLog b) => a.start.compareTo(b.start));
    await st.saveProgress(e.key.id);
  }
  await st.selectProfile(null);
  return PilasDemo(sofia: sofia, mateo: mateo, valentina: valentina);
}
