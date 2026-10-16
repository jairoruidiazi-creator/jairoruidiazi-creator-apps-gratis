import '../engine/mastery.dart';
import 'age_band.dart';

/// Una pegatina ganada al completar un nivel.
class StickerAward {
  const StickerAward({
    required this.gameId,
    required this.band,
    required this.level,
    required this.emoji,
    required this.date,
  });

  final String gameId;
  final AgeBand band;
  final int level;
  final String emoji;
  final DateTime date;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'gameId': gameId,
        'band': band.id,
        'level': level,
        'emoji': emoji,
        'date': date.toIso8601String(),
      };

  static StickerAward fromJson(Map<String, dynamic> json) => StickerAward(
        gameId: json['gameId'] as String,
        band: AgeBandX.fromId(json['band'] as String?) ?? AgeBand.b3a4,
        level: (json['level'] as num?)?.toInt() ?? 1,
        emoji: (json['emoji'] as String?) ?? '2b50',
        date: DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      );
}

/// Registro de una sesión de juego (para el informe de padres y docentes).
class SessionLog {
  SessionLog({
    required this.start,
    this.seconds = 0,
    this.rounds = 0,
    this.correct = 0,
    Map<String, int>? gameRounds,
  }) : gameRounds = gameRounds ?? <String, int>{};

  final DateTime start;
  int seconds;
  int rounds;
  int correct;

  /// Rondas por juego dentro de la sesión.
  final Map<String, int> gameRounds;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'start': start.toIso8601String(),
        'seconds': seconds,
        'rounds': rounds,
        'correct': correct,
        'gameRounds': gameRounds,
      };

  static SessionLog fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> gr = (json['gameRounds'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return SessionLog(
      start: DateTime.tryParse((json['start'] as String?) ?? '') ?? DateTime.now(),
      seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      rounds: (json['rounds'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      gameRounds: gr.map((String k, dynamic v) => MapEntry<String, int>(k, (v as num).toInt())),
    );
  }
}

/// Todo el progreso de un perfil.
class ProfileProgress {
  ProfileProgress({
    Map<String, MasteryState>? mastery,
    Map<String, DateTime>? skillsAchieved,
    List<StickerAward>? stickers,
    List<SessionLog>? sessions,
  })  : mastery = mastery ?? <String, MasteryState>{},
        skillsAchieved = skillsAchieved ?? <String, DateTime>{},
        stickers = stickers ?? <StickerAward>[],
        sessions = sessions ?? <SessionLog>[];

  /// Clave: '<gameId>|<bandId>'.
  final Map<String, MasteryState> mastery;
  final Map<String, DateTime> skillsAchieved;
  final List<StickerAward> stickers;
  final List<SessionLog> sessions;

  static String masteryKey(String gameId, AgeBand band) => '$gameId|${band.id}';

  MasteryState masteryFor(String gameId, AgeBand band) {
    return mastery.putIfAbsent(masteryKey(gameId, band), () => MasteryState());
  }

  bool hasSticker(String gameId, AgeBand band, int level) {
    for (final StickerAward s in stickers) {
      if (s.gameId == gameId && s.band == band && s.level == level) {
        return true;
      }
    }
    return false;
  }

  int secondsOn(DateTime day) {
    int total = 0;
    for (final SessionLog s in sessions) {
      if (s.start.year == day.year && s.start.month == day.month && s.start.day == day.day) {
        total += s.seconds;
      }
    }
    return total;
  }

  int secondsSince(DateTime from) {
    int total = 0;
    for (final SessionLog s in sessions) {
      if (!s.start.isBefore(from)) {
        total += s.seconds;
      }
    }
    return total;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mastery': mastery.map((String k, MasteryState v) => MapEntry<String, dynamic>(k, v.toJson())),
        'skillsAchieved': skillsAchieved.map((String k, DateTime v) => MapEntry<String, dynamic>(k, v.toIso8601String())),
        'stickers': stickers.map((StickerAward s) => s.toJson()).toList(),
        'sessions': sessions.map((SessionLog s) => s.toJson()).toList(),
      };

  static ProfileProgress fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> m = (json['mastery'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> sk = (json['skillsAchieved'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<dynamic> st = (json['stickers'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> se = (json['sessions'] as List<dynamic>?) ?? <dynamic>[];
    return ProfileProgress(
      mastery: m.map((String k, dynamic v) => MapEntry<String, MasteryState>(k, MasteryState.fromJson(v as Map<String, dynamic>))),
      skillsAchieved: sk.map((String k, dynamic v) => MapEntry<String, DateTime>(k, DateTime.tryParse(v as String) ?? DateTime.now())),
      stickers: st.map((dynamic e) => StickerAward.fromJson(e as Map<String, dynamic>)).toList(),
      sessions: se.map((dynamic e) => SessionLog.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
