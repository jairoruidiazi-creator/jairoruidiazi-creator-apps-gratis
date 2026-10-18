import 'dart:math' as math;

/// Cronómetro con vueltas. Como el temporizador, su tiempo sale del reloj
/// (hora de arranque más lo acumulado), así sigue exacto con la app cerrada.
class StopwatchState {
  StopwatchState({this.startedAt, this.accumulatedMs = 0, List<int>? laps}) : laps = laps ?? <int>[];

  /// Desde cuándo corre (null si está detenido).
  DateTime? startedAt;

  /// Tiempo acumulado antes del arranque actual.
  int accumulatedMs;

  /// Tiempo total al marcar cada vuelta.
  final List<int> laps;

  bool get running => startedAt != null;

  bool get isZero => !running && accumulatedMs == 0 && laps.isEmpty;

  int elapsedMs(DateTime now) {
    final DateTime? s = startedAt;
    return accumulatedMs + (s == null ? 0 : math.max(0, now.difference(s).inMilliseconds));
  }

  void start(DateTime now) {
    startedAt ??= now;
  }

  void pause(DateTime now) {
    final DateTime? s = startedAt;
    if (s == null) {
      return;
    }
    accumulatedMs += math.max(0, now.difference(s).inMilliseconds);
    startedAt = null;
  }

  void reset() {
    startedAt = null;
    accumulatedMs = 0;
    laps.clear();
  }

  /// Marca una vuelta (solo con el cronómetro en marcha).
  void lap(DateTime now) {
    if (!running) {
      return;
    }
    laps.add(elapsedMs(now));
  }

  /// Duración de cada vuelta marcada, de la primera a la última.
  List<int> lapDurations() {
    final List<int> out = <int>[];
    int prev = 0;
    for (final int mark in laps) {
      out.add(mark - prev);
      prev = mark;
    }
    return out;
  }

  /// Vuelta en curso (desde la última marca).
  int currentLapMs(DateTime now) => elapsedMs(now) - (laps.isEmpty ? 0 : laps.last);

  /// Índice de la vuelta más rápida (con dos vueltas o más y no todas iguales).
  int? get bestLap => _extreme(true);

  /// Índice de la vuelta más lenta.
  int? get worstLap => _extreme(false);

  int? _extreme(bool fastest) {
    final List<int> d = lapDurations();
    if (d.length < 2) {
      return null;
    }
    final int lo = d.reduce(math.min);
    final int hi = d.reduce(math.max);
    if (lo == hi) {
      return null;
    }
    return d.indexOf(fastest ? lo : hi);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'started': startedAt?.toIso8601String(),
        'accumulated': accumulatedMs,
        'laps': laps,
      };

  factory StopwatchState.fromJson(Map<String, dynamic> j) {
    final Object? laps = j['laps'];
    return StopwatchState(
      startedAt: DateTime.tryParse(j['started'] as String? ?? ''),
      accumulatedMs: (j['accumulated'] as num?)?.toInt() ?? 0,
      laps: laps is List ? laps.whereType<num>().map((num n) => n.toInt()).toList() : <int>[],
    );
  }
}
