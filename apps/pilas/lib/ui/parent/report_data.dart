import '../../engine/game_def.dart';
import '../../engine/game_registry.dart';
import '../../engine/mastery.dart';
import '../../model/age_band.dart';
import '../../model/area.dart';
import '../../model/profile.dart';
import '../../model/progress.dart';
import '../../model/skill.dart';

/// Resumen por área para informes de padres y docentes.
class AreaSummary {
  const AreaSummary({required this.area, required this.skillsLogradas, required this.skillsPosibles, required this.rondas, required this.aciertos, required this.juegos});

  final Area area;
  final int skillsLogradas;
  final int skillsPosibles;
  final int rondas;
  final int aciertos;

  /// Juegos jugados en el área con su nivel actual.
  final List<GameLevel> juegos;

  double get precision => rondas == 0 ? 0 : aciertos / rondas;
}

class GameLevel {
  const GameLevel({required this.game, required this.level, required this.maxLevel, required this.rondas, required this.aciertos});

  final GameDef game;
  final int level;
  final int maxLevel;
  final int rondas;
  final int aciertos;
}

class ChildReport {
  ChildReport({required this.profile, required this.progress, DateTime? now}) : now = now ?? DateTime.now();

  final Profile profile;
  final ProfileProgress progress;
  final DateTime now;

  AgeBand get band => profile.bandOn(now);

  int get minutosHoy => progress.secondsOn(now) ~/ 60;

  int get minutosSemana => progress.secondsSince(now.subtract(const Duration(days: 7))) ~/ 60;

  int get minutosTotal => progress.sessions.fold<int>(0, (int s, SessionLog l) => s + l.seconds) ~/ 60;

  int get sesiones => progress.sessions.length;

  int get rondasTotal => progress.mastery.values.fold<int>(0, (int s, MasteryState m) => s + m.roundsPlayed);

  int get aciertosTotal => progress.mastery.values.fold<int>(0, (int s, MasteryState m) => s + m.roundsCorrect);

  List<AreaSummary> get areas {
    final List<AreaSummary> out = <AreaSummary>[];
    for (final Area area in Area.values) {
      final List<Skill> posibles = SkillCatalog.forAreaAndBand(area, band);
      final int logradas = progress.skillsAchieved.keys.where((String id) => SkillCatalog.byId(id)?.area == area).length;
      int rondas = 0;
      int aciertos = 0;
      final List<GameLevel> juegos = <GameLevel>[];
      for (final GameDef g in GameRegistry.all.where((GameDef g) => g.area == area)) {
        for (final AgeBand b in AgeBand.values) {
          final MasteryState? m = progress.mastery[ProfileProgress.masteryKey(g.id, b)];
          if (m == null || m.roundsPlayed == 0) {
            continue;
          }
          rondas += m.roundsPlayed;
          aciertos += m.roundsCorrect;
          if (b == band) {
            juegos.add(GameLevel(game: g, level: m.level, maxLevel: g.levelsFor(b), rondas: m.roundsPlayed, aciertos: m.roundsCorrect));
          }
        }
      }
      out.add(AreaSummary(area: area, skillsLogradas: logradas, skillsPosibles: posibles.length, rondas: rondas, aciertos: aciertos, juegos: juegos));
    }
    return out;
  }

  /// Habilidades logradas, de la más reciente a la más antigua.
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
    final List<SessionLog> out = progress.sessions.where((SessionLog s) => !s.start.isBefore(desde)).toList();
    out.sort((SessionLog a, SessionLog b) => b.start.compareTo(a.start));
    return out;
  }

  /// Una recomendación corta por área con menos práctica.
  List<String> get sugerencias {
    final List<AreaSummary> a = areas;
    a.sort((AreaSummary x, AreaSummary y) => x.rondas.compareTo(y.rondas));
    final List<String> out = <String>[];
    for (final AreaSummary s in a.take(2)) {
      final List<GameDef> games = GameRegistry.forAreaAndBand(s.area, band);
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
