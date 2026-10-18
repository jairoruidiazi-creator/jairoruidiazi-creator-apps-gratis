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
        date: DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Registro de una sesión de juego (para el informe de padres y docentes).
///
/// [seconds] cuenta solo el tiempo en primer plano. Mientras la sesión está
/// abierta, [lastActive] es la última vez que contó tiempo; una sesión se
/// cierra tras 10 minutos sin jugar.
class SessionLog {
  SessionLog({
    required this.start,
    this.seconds = 0,
    this.rounds = 0,
    this.correct = 0,
    Map<String, int>? gameRounds,
    DateTime? lastActive,
    this.extraSeconds = 0,
  })  : gameRounds = gameRounds ?? <String, int>{},
        lastActive = lastActive ?? start;

  final DateTime start;
  int seconds;
  int rounds;

  /// Rondas acertadas al primer intento.
  int correct;

  /// Rondas por juego dentro de la sesión (también las de juego libre).
  final Map<String, int> gameRounds;

  /// Última vez que la sesión contó tiempo de juego.
  DateTime lastActive;

  /// Tiempo extra que un adulto concedió en esta sesión.
  int extraSeconds;

  /// Se guarda en el informe si duró algo o tuvo rondas.
  bool get meaningful => seconds >= 10 || rounds > 0 || gameRounds.isNotEmpty;

  SessionLog copy() => SessionLog(
        start: start,
        seconds: seconds,
        rounds: rounds,
        correct: correct,
        gameRounds: Map<String, int>.from(gameRounds),
        lastActive: lastActive,
        extraSeconds: extraSeconds,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'start': start.toIso8601String(),
        'seconds': seconds,
        'rounds': rounds,
        'correct': correct,
        'gameRounds': gameRounds,
        'lastActive': lastActive.toIso8601String(),
        if (extraSeconds > 0) 'extraSeconds': extraSeconds,
      };

  static SessionLog fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> gr = (json['gameRounds'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final DateTime start = DateTime.tryParse((json['start'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return SessionLog(
      start: start,
      seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      rounds: (json['rounds'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      gameRounds: gr.map((String k, dynamic v) => MapEntry<String, int>(k, (v as num).toInt())),
      lastActive: DateTime.tryParse((json['lastActive'] as String?) ?? '') ?? start,
      extraSeconds: (json['extraSeconds'] as num?)?.toInt() ?? 0,
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
    Map<String, int>? records,
    this.live,
    this.restUntil,
  })  : mastery = mastery ?? <String, MasteryState>{},
        skillsAchieved = skillsAchieved ?? <String, DateTime>{},
        stickers = stickers ?? <StickerAward>[],
        sessions = sessions ?? <SessionLog>[],
        records = records ?? <String, int>{};

  /// Clave: `<gameId>|<bandId>`.
  final Map<String, MasteryState> mastery;
  final Map<String, DateTime> skillsAchieved;
  final List<StickerAward> stickers;

  /// Sesiones cerradas. La sesión abierta va aparte en [live], para que nunca
  /// se cuente dos veces.
  final List<SessionLog> sessions;

  /// Sesión abierta (se guarda para que cerrar la app no reinicie el tiempo).
  SessionLog? live;

  /// Si hay un descanso en curso, hasta cuándo.
  DateTime? restUntil;

  /// Marcas personales, por ejemplo la mejor carrera: `<gameId>|<bandId>`.
  final Map<String, int> records;

  static const int maxSessions = 400;

  static String masteryKey(String gameId, AgeBand band) => '$gameId|${band.id}';

  MasteryState masteryFor(String gameId, AgeBand band) {
    return mastery.putIfAbsent(masteryKey(gameId, band), () => MasteryState());
  }

  /// Nivel sin crear una entrada nueva (para las pantallas que solo leen).
  MasteryState? masteryIfAny(String gameId, AgeBand band) => mastery[masteryKey(gameId, band)];

  bool hasSticker(String gameId, AgeBand band, int level) {
    for (final StickerAward s in stickers) {
      if (s.gameId == gameId && s.band == band && s.level == level) {
        return true;
      }
    }
    return false;
  }

  /// Sesiones cerradas y la abierta, sin repetir ninguna.
  List<SessionLog> get allSessions => <SessionLog>[...sessions, if (live != null) live!];

  int secondsOn(DateTime day) {
    int total = 0;
    for (final SessionLog s in allSessions) {
      if (s.start.year == day.year && s.start.month == day.month && s.start.day == day.day) {
        total += s.seconds;
      }
    }
    return total;
  }

  int secondsSince(DateTime from) {
    int total = 0;
    for (final SessionLog s in allSessions) {
      if (!s.start.isBefore(from)) {
        total += s.seconds;
      }
    }
    return total;
  }

  /// Agrega una sesión cerrada (si no estaba ya) y recorta las más viejas.
  void addSession(SessionLog s) {
    if (sessions.any((SessionLog x) => x.start == s.start)) {
      return;
    }
    sessions.add(s);
    sessions.sort((SessionLog a, SessionLog b) => a.start.compareTo(b.start));
    while (sessions.length > maxSessions) {
      sessions.removeAt(0);
    }
  }

  /// Une el progreso importado de otra tableta con este sin inflarlo. El
  /// archivo importado suele traer también lo que ya había aquí (se exportó
  /// de esta tableta, se jugó en la otra y se trajo de vuelta), así que de
  /// cada juego se queda con el registro más avanzado en lugar de sumar; las
  /// pegatinas, las habilidades y las sesiones se juntan sin repetir, y queda
  /// la mejor marca. Importar dos veces el mismo archivo no cambia nada.
  void mergeFrom(ProfileProgress other) {
    other.mastery.forEach((String k, MasteryState m) {
      final MasteryState? mine = mastery[k];
      if (mine == null) {
        mastery[k] = m;
        return;
      }
      final int maxReached = m.maxLevelReached > mine.maxLevelReached ? m.maxLevelReached : mine.maxLevelReached;
      final int completed = m.levelsCompleted > mine.levelsCompleted ? m.levelsCompleted : mine.levelsCompleted;
      if (m.level > mine.level || (m.level == mine.level && m.roundsPlayed > mine.roundsPlayed)) {
        mastery[k] = MasteryState(
          level: m.level,
          recent: List<bool>.from(m.recent),
          failStreak: m.failStreak,
          roundsPlayed: m.roundsPlayed,
          roundsCorrect: m.roundsCorrect,
          maxLevelReached: maxReached,
          levelsCompleted: completed,
        );
      } else {
        mine.maxLevelReached = maxReached;
        mine.levelsCompleted = completed;
      }
    });
    other.skillsAchieved.forEach((String k, DateTime d) {
      final DateTime? mine = skillsAchieved[k];
      if (mine == null || d.isBefore(mine)) {
        skillsAchieved[k] = d;
      }
    });
    for (final StickerAward s in other.stickers) {
      if (!hasSticker(s.gameId, s.band, s.level)) {
        stickers.add(s);
      }
    }
    for (final SessionLog s in other.allSessions) {
      addSession(s.copy());
    }
    other.records.forEach((String k, int v) {
      if ((records[k] ?? -1) < v) {
        records[k] = v;
      }
    });
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mastery': mastery.map((String k, MasteryState v) => MapEntry<String, dynamic>(k, v.toJson())),
        'skillsAchieved': skillsAchieved.map((String k, DateTime v) => MapEntry<String, dynamic>(k, v.toIso8601String())),
        'stickers': stickers.map((StickerAward s) => s.toJson()).toList(),
        'sessions': sessions.map((SessionLog s) => s.toJson()).toList(),
        if (records.isNotEmpty) 'records': records,
        if (live != null) 'live': live!.toJson(),
        if (restUntil != null) 'restUntil': restUntil!.toIso8601String(),
      };

  static ProfileProgress fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> m = (json['mastery'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> sk = (json['skillsAchieved'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<dynamic> st = (json['stickers'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> se = (json['sessions'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> rec = (json['records'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic>? live = json['live'] as Map<String, dynamic>?;
    return ProfileProgress(
      mastery: m.map((String k, dynamic v) => MapEntry<String, MasteryState>(k, MasteryState.fromJson(v as Map<String, dynamic>))),
      skillsAchieved: sk.map((String k, dynamic v) => MapEntry<String, DateTime>(k, DateTime.tryParse(v as String) ?? DateTime.fromMillisecondsSinceEpoch(0))),
      stickers: st.map((dynamic e) => StickerAward.fromJson(e as Map<String, dynamic>)).toList(),
      sessions: se.map((dynamic e) => SessionLog.fromJson(e as Map<String, dynamic>)).toList(),
      records: rec.map((String k, dynamic v) => MapEntry<String, int>(k, (v as num).toInt())),
      live: live == null ? null : SessionLog.fromJson(live),
      restUntil: DateTime.tryParse((json['restUntil'] as String?) ?? ''),
    );
  }
}
