/// Regla de dominio: en cada ventana de [MasteryRule.window] rondas, con
/// [MasteryRule.toAdvance] aciertos al primer intento se abre el siguiente
/// nivel; con menos de [MasteryRule.toStay] dos ventanas seguidas se baja un
/// nivel sin anunciarlo.
enum MasteryEvent { none, levelKept, levelUp, levelDown, levelMastered }

extension MasteryEventX on MasteryEvent {
  /// Se completó un nivel (subió o dominó el último).
  bool get completedLevel => this == MasteryEvent.levelUp || this == MasteryEvent.levelMastered;
}

/// Cuántas rondas mira la regla y cuántos aciertos pide.
///
/// - Juegos de elegir: 5 de 6 aciertos al primer intento. Con tres opciones,
///   tocar al azar sube de nivel en menos del 2 % de las ventanas (la prueba
///   test/random_player_test.dart lo calcula juego por juego; el umbral es 5 %).
/// - Ordenar y trazar: 4 de 5 rondas sin ningún error.
/// - Tableros (memoria, laberintos, sudoku, rompecabezas, pixel, colorear por
///   números): 2 de 3 tableros terminados con eficiencia.
class MasteryRule {
  const MasteryRule({required this.window, required this.toAdvance, required this.toStay});

  final int window;
  final int toAdvance;
  final int toStay;

  static const MasteryRule eleccion = MasteryRule(window: 6, toAdvance: 5, toStay: 3);
  static const MasteryRule ordenar = MasteryRule(window: 5, toAdvance: 4, toStay: 2);
  static const MasteryRule tablero = MasteryRule(window: 3, toAdvance: 2, toStay: 1);
}

class MasteryState {
  MasteryState({
    this.level = 1,
    List<bool>? recent,
    this.failStreak = 0,
    this.roundsPlayed = 0,
    this.roundsCorrect = 0,
    this.maxLevelReached = 1,
    this.levelsCompleted = 0,
  }) : recent = recent ?? <bool>[];

  int level;
  final List<bool> recent;
  int failStreak;
  int roundsPlayed;

  /// Rondas acertadas al primer intento.
  int roundsCorrect;
  int maxLevelReached;

  /// Cuántas veces se completó un nivel (sube de nivel o llega al tope con dominio).
  int levelsCompleted;

  double get accuracy => roundsPlayed == 0 ? 0 : roundsCorrect / roundsPlayed;

  /// Registra el resultado de una ronda y devuelve qué pasó con el nivel.
  MasteryEvent record(bool success, int maxLevel, {MasteryRule rule = MasteryRule.eleccion}) {
    roundsPlayed += 1;
    if (success) {
      roundsCorrect += 1;
    }
    recent.add(success);
    if (recent.length < rule.window) {
      return MasteryEvent.none;
    }
    final int successes = recent.where((bool s) => s).length;
    recent.clear();
    if (successes >= rule.toAdvance) {
      failStreak = 0;
      levelsCompleted += 1;
      if (level < maxLevel) {
        level += 1;
        if (level > maxLevelReached) {
          maxLevelReached = level;
        }
        return MasteryEvent.levelUp;
      }
      return MasteryEvent.levelMastered;
    }
    if (successes >= rule.toStay) {
      failStreak = 0;
      return MasteryEvent.levelKept;
    }
    failStreak += 1;
    if (failStreak >= 2) {
      failStreak = 0;
      if (level > 1) {
        level -= 1;
        return MasteryEvent.levelDown;
      }
    }
    return MasteryEvent.levelKept;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'level': level,
        'recent': recent,
        'failStreak': failStreak,
        'roundsPlayed': roundsPlayed,
        'roundsCorrect': roundsCorrect,
        'maxLevelReached': maxLevelReached,
        'levelsCompleted': levelsCompleted,
      };

  static MasteryState fromJson(Map<String, dynamic> json) {
    final List<dynamic> rec = (json['recent'] as List<dynamic>?) ?? <dynamic>[];
    return MasteryState(
      level: (json['level'] as num?)?.toInt() ?? 1,
      recent: rec.map((dynamic e) => e == true).toList(),
      failStreak: (json['failStreak'] as num?)?.toInt() ?? 0,
      roundsPlayed: (json['roundsPlayed'] as num?)?.toInt() ?? 0,
      roundsCorrect: (json['roundsCorrect'] as num?)?.toInt() ?? 0,
      maxLevelReached: (json['maxLevelReached'] as num?)?.toInt() ?? 1,
      levelsCompleted: (json['levelsCompleted'] as num?)?.toInt() ?? 0,
    );
  }
}
