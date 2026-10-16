/// Regla de dominio: tres aciertos de las últimas cuatro rondas abren el
/// siguiente nivel; dos niveles seguidos con un acierto o ninguno bajan
/// un nivel sin anunciarlo.
enum MasteryEvent { none, levelKept, levelUp, levelDown, levelMastered }

extension MasteryEventX on MasteryEvent {
  /// Se completó un nivel (subió o dominó el último).
  bool get completedLevel => this == MasteryEvent.levelUp || this == MasteryEvent.levelMastered;
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

  static const int window = 4;
  static const int successesToAdvance = 3;
  static const int successesToStay = 2;

  int level;
  final List<bool> recent;
  int failStreak;
  int roundsPlayed;
  int roundsCorrect;
  int maxLevelReached;

  /// Cuántas veces se completó un nivel (sube de nivel o llega al tope con dominio).
  int levelsCompleted;

  double get accuracy => roundsPlayed == 0 ? 0 : roundsCorrect / roundsPlayed;

  /// Registra el resultado de una ronda y devuelve qué pasó con el nivel.
  MasteryEvent record(bool success, int maxLevel) {
    roundsPlayed += 1;
    if (success) {
      roundsCorrect += 1;
    }
    recent.add(success);
    if (recent.length < window) {
      return MasteryEvent.none;
    }
    final int successes = recent.where((bool s) => s).length;
    recent.clear();
    if (successes >= successesToAdvance) {
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
    if (successes >= successesToStay) {
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
