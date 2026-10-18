import 'package:clock/clock.dart';

import '../../engine/game_def.dart';
import '../../engine/game_registry.dart';
import '../../engine/mastery.dart';
import '../../model/age_band.dart';
import '../../model/area.dart';
import '../../model/profile.dart';
import '../../model/progress.dart';
import '../../model/skill.dart';

/// Resumen por área para informes de padres y docentes. Las habilidades se
/// cuentan siempre sobre el mismo conjunto: las del área en el tramo actual
/// del niño (logradas de esas, sobre el total de esas).
class AreaSummary {
  const AreaSummary({required this.area, required this.skillsLogradas, required this.skillsPosibles, required this.rondas, required this.aciertos, required this.juegos});

  final Area area;
  final int skillsLogradas;
  final int skillsPosibles;
  final int rondas;
  final int aciertos;

  /// Juegos del tramo actual jugados en el área, con su nivel.
  final List<GameLevel> juegos;

  double get precision => rondas == 0 ? 0 : aciertos / rondas;

  /// El área no tiene habilidades evaluadas en este tramo (solo juego libre).
  bool get soloJuegoLibre => skillsPosibles == 0;

  /// "2 de 5", o "Juego libre" si el área no evalúa nada en este tramo.
  String get logradasTexto => soloJuegoLibre ? 'Juego libre' : '$skillsLogradas de $skillsPosibles';
}

class GameLevel {
  const GameLevel({required this.game, required this.level, required this.maxLevel, required this.rondas, required this.aciertos});

  final GameDef game;
  final int level;
  final int maxLevel;
  final int rondas;
  final int aciertos;

  /// "nivel 2 de 4", o vacío si el juego no tiene niveles.
  String get nivelTexto => maxLevel > 1 ? 'nivel $level de $maxLevel' : '';

  bool get _tablero => identical(game.mastery, MasteryRule.tablero);

  /// "12 rondas · 58 % al primer intento", o en los tableros "3 tableros ·
  /// 67 % resueltos con eficiencia" (ahí el acierto es resolverlo bien).
  String get resumen {
    final String cuantas = _tablero ? (rondas == 1 ? '1 tablero' : '$rondas tableros') : (rondas == 1 ? '1 ronda' : '$rondas rondas');
    // Espacio sin corte: el número y el % no se separan de línea.
    final String pct = rondas == 0 ? '-' : '${(aciertos * 100 / rondas).round()}\u00A0%';
    return '$cuantas · $pct ${_tablero ? 'resueltos con eficiencia' : 'al primer intento'}';
  }
}

class ChildReport {
  ChildReport({required this.profile, required this.progress, DateTime? now}) : now = now ?? clock.now();

  final Profile profile;
  final ProfileProgress progress;
  final DateTime now;

  AgeBand get band => profile.bandOn(now);

  int get minutosHoy => progress.secondsOn(now) ~/ 60;

  /// Minutos de los últimos 7 días (no de la semana del calendario).
  int get minutos7Dias => progress.secondsSince(now.subtract(const Duration(days: 7))) ~/ 60;

  int get minutosTotal => progress.allSessions.fold<int>(0, (int s, SessionLog l) => s + l.seconds) ~/ 60;

  int get sesiones => progress.allSessions.length;

  /// Rondas evaluadas (los juegos libres no cuentan).
  Iterable<MasteryState> get _evaluadas sync* {
    for (final MapEntry<String, MasteryState> e in progress.mastery.entries) {
      final GameDef? g = GameRegistry.byId(e.key.split('|').first);
      if (g != null && g.roundBased) {
        yield e.value;
      }
    }
  }

  int get rondasTotal => _evaluadas.fold<int>(0, (int s, MasteryState m) => s + m.roundsPlayed);

  /// Rondas acertadas al primer intento.
  int get aciertosTotal => _evaluadas.fold<int>(0, (int s, MasteryState m) => s + m.roundsCorrect);

  String get aciertosTexto => rondasTotal == 0 ? '-' : '${(aciertosTotal * 100 / rondasTotal).round()}\u00A0%';

  /// Habilidades del tramo actual.
  List<Skill> get skillsDelTramo => SkillCatalog.forBand(band);

  int get skillsLogradasTramo => skillsDelTramo.where((Skill s) => progress.skillsAchieved.containsKey(s.id)).length;

  List<AreaSummary> get areas {
    final List<AreaSummary> out = <AreaSummary>[];
    for (final Area area in Area.values) {
      final List<Skill> posibles = SkillCatalog.forAreaAndBand(area, band);
      final int logradas = posibles.where((Skill s) => progress.skillsAchieved.containsKey(s.id)).length;
      int rondas = 0;
      int aciertos = 0;
      final List<GameLevel> juegos = <GameLevel>[];
      for (final GameDef g in GameRegistry.forAreaAndBand(area, band)) {
        if (!g.roundBased) {
          continue;
        }
        final MasteryState? m = progress.masteryIfAny(g.id, band);
        if (m == null || m.roundsPlayed == 0) {
          continue;
        }
        rondas += m.roundsPlayed;
        aciertos += m.roundsCorrect;
        juegos.add(GameLevel(game: g, level: m.level, maxLevel: g.levelsFor(band), rondas: m.roundsPlayed, aciertos: m.roundsCorrect));
      }
      out.add(AreaSummary(area: area, skillsLogradas: logradas, skillsPosibles: posibles.length, rondas: rondas, aciertos: aciertos, juegos: juegos));
    }
    return out;
  }

  /// Habilidades logradas (de cualquier tramo), de la más reciente a la más antigua.
  List<MapEntry<Skill, DateTime>> get habilidades {
    final List<MapEntry<Skill, DateTime>> out = <MapEntry<Skill, DateTime>>[];
    progress.skillsAchieved.forEach((String id, DateTime d) {
      final Skill? s = SkillCatalog.byId(id);
      if (s != null) {
        out.add(MapEntry<Skill, DateTime>(s, d));
      }
    });
    out.sort((MapEntry<Skill, DateTime> a, MapEntry<Skill, DateTime> b) => b.value.compareTo(a.value));
    return out;
  }

  /// Sesiones de los últimos 14 días, de la más reciente a la más antigua.
  List<SessionLog> get sesionesRecientes {
    final DateTime desde = now.subtract(const Duration(days: 14));
    final List<SessionLog> out = progress.allSessions.where((SessionLog s) => !s.start.isBefore(desde)).toList();
    out.sort((SessionLog a, SessionLog b) => b.start.compareTo(a.start));
    return out;
  }

  /// Una recomendación corta para las dos áreas con menos práctica.
  List<String> get sugerencias {
    final List<AreaSummary> a = areas;
    a.sort((AreaSummary x, AreaSummary y) => x.rondas.compareTo(y.rondas));
    final List<String> out = <String>[];
    for (final AreaSummary s in a) {
      if (out.length == 2) {
        break;
      }
      final List<GameDef> games = GameRegistry.forAreaAndBand(s.area, band).where((GameDef g) => g.roundBased).toList();
      if (games.isEmpty) {
        continue;
      }
      final GameDef g = games.first;
      out.add('${s.area.nombre}: prueben "${g.nombre}". En casa: ${g.enCasa}');
    }
    return out;
  }
}

String fechaCorta(DateTime d) {
  const List<String> meses = <String>['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${meses[d.month - 1]} ${d.year}';
}

String fechaHora(DateTime d) {
  final String h = d.hour.toString().padLeft(2, '0');
  final String m = d.minute.toString().padLeft(2, '0');
  return '${fechaCorta(d)} $h:$m';
}
