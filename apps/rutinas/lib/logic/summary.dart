import 'dart:math' as math;

import '../core/dates.dart';
import '../model/habit.dart';
import '../model/workout.dart';
import 'habit_logic.dart';

enum SummaryRange { week, month, year }

SummaryRange summaryRangeFrom(Object? v) {
  for (final SummaryRange r in SummaryRange.values) {
    if (r.name == v) {
      return r;
    }
  }
  return SummaryRange.week;
}

/// Cumplimiento de un hábito en el periodo del resumen.
class HabitPeriodStats {
  const HabitPeriodStats({required this.habit, required this.met, required this.missed, required this.open, required this.doneDays, required this.totalValue, required this.skippedDays, required this.relapseDays, required this.cleanDays});

  final Habit habit;

  /// Periodos de la frecuencia (días, bloques, semanas o meses) que terminan
  /// dentro del resumen: cumplidos y fallados. Los saltados no cuentan.
  final int met;
  final int missed;

  /// Periodo en curso aún sin cumplir (no cuenta como fallado).
  final int open;
  final int doneDays;

  /// Suma de lo registrado: veces (count) o segundos (timed).
  final int totalValue;
  final int skippedDays;

  /// Hábitos negativos.
  final int relapseDays;
  final int cleanDays;

  double? get rate {
    if (habit.isNegative) {
      final int total = cleanDays + relapseDays;
      return total == 0 ? null : cleanDays / total;
    }
    return met + missed == 0 ? null : met / (met + missed);
  }
}

class PeriodSummary {
  const PeriodSummary({
    required this.range,
    required this.start,
    required this.end,
    required this.habits,
    required this.completions,
    required this.bestDay,
    required this.bestDayCount,
    required this.bestWeekday,
    required this.bestWeekdayAverage,
    required this.timedSeconds,
    required this.workouts,
    required this.workoutSeconds,
    required this.bars,
    required this.met,
    required this.missed,
  });

  final SummaryRange range;
  final DateTime start;

  /// Último día del periodo (incluido; puede ser posterior a hoy).
  final DateTime end;
  final List<HabitPeriodStats> habits;

  /// Días de hábito hechos en total.
  final int completions;

  /// Día con más hábitos hechos (el primero si hay empate).
  final DateTime? bestDay;
  final int bestDayCount;

  /// Día de la semana con más hábitos hechos en promedio (mes y año).
  final int? bestWeekday;
  final double bestWeekdayAverage;

  /// Minutos de los hábitos con tiempo, en segundos.
  final int timedSeconds;

  /// Entrenamientos terminados y tiempo total entrenado (también los interrumpidos).
  final int workouts;
  final int workoutSeconds;

  /// Hábitos hechos por día (semana y mes) o por mes (año).
  final List<int> bars;
  final int met;
  final int missed;

  double? get rate => met + missed == 0 ? null : met / (met + missed);
}

class Summaries {
  Summaries._();

  /// Primer y último día del periodo que contiene a [anchor].
  static List<DateTime> bounds(SummaryRange range, DateTime anchor, int weekStart) {
    final DateTime a = dateOnly(anchor);
    switch (range) {
      case SummaryRange.week:
        final DateTime s = startOfWeek(a, weekStart);
        return <DateTime>[s, addDays(s, 6)];
      case SummaryRange.month:
        return <DateTime>[startOfMonth(a), endOfMonth(a)];
      case SummaryRange.year:
        return <DateTime>[DateTime(a.year), DateTime(a.year, 12, 31)];
    }
  }

  /// El mismo periodo desplazado [steps] veces (−1 es el anterior).
  static DateTime shift(SummaryRange range, DateTime anchor, int steps) {
    switch (range) {
      case SummaryRange.week:
        return addDays(anchor, 7 * steps);
      case SummaryRange.month:
        return DateTime(anchor.year, anchor.month + steps);
      case SummaryRange.year:
        return DateTime(anchor.year + steps);
    }
  }

  static PeriodSummary build({
    required SummaryRange range,
    required DateTime anchor,
    required DateTime today,
    required int weekStart,
    required List<Habit> habits,
    required Map<String, Map<String, HabitEntry>> entries,
    required List<WorkoutSession> sessions,
  }) {
    final List<DateTime> b = bounds(range, anchor, weekStart);
    final DateTime start = b[0];
    final DateTime end = b[1];
    final DateTime t = dateOnly(today);
    final DateTime lastCounted = end.isAfter(t) ? t : end;
    final List<HabitPeriodStats> stats = <HabitPeriodStats>[];
    final Map<String, int> doneByDay = <String, int>{};
    int timed = 0;
    int met = 0;
    int missed = 0;
    for (final Habit h in habits) {
      final Map<String, HabitEntry> e = entries[h.id] ?? const <String, HabitEntry>{};
      final DateTime hs = HabitLogic.effectiveStart(h, e);
      if (hs.isAfter(lastCounted)) {
        continue; // El hábito todavía no existía en este periodo.
      }
      // Un hábito archivado deja de contar desde el día en que se archivó.
      final DateTime? archivedAt = h.archived ? h.archivedAt : null;
      if (archivedAt != null && archivedAt.isBefore(start)) {
        continue;
      }
      final DateTime habitLast = archivedAt != null && archivedAt.isBefore(lastCounted) ? archivedAt : lastCounted;
      int doneDays = 0;
      int totalValue = 0;
      int skippedDays = 0;
      int relapses = 0;
      int clean = 0;
      bool tracked = false;
      for (DateTime d = start; !d.isAfter(habitLast); d = addDays(d, 1)) {
        if (d.isBefore(hs)) {
          continue;
        }
        final bool paused = h.pausedOn(d);
        tracked = tracked || !paused;
        final HabitEntry? x = e[dayKey(d)];
        if (h.isNegative) {
          if (x != null && x.value > 0) {
            relapses++;
          } else if (d.isBefore(t) && !paused) {
            clean++;
          }
          continue;
        }
        if (x != null) {
          totalValue += x.value;
          if (HabitLogic.isDone(h, x, d)) {
            doneDays++;
            doneByDay[dayKey(d)] = (doneByDay[dayKey(d)] ?? 0) + 1;
          } else if (x.skipped) {
            skippedDays++;
          }
        }
      }
      if (!tracked && doneDays == 0 && relapses == 0) {
        continue; // Archivado durante todo el periodo.
      }
      int hMet = 0;
      int hMissed = 0;
      int hOpen = 0;
      if (!h.isNegative) {
        for (final HabitSlot s in HabitLogic.slots(h, e, t, weekStart: weekStart)) {
          final bool endsInside = !s.end.isBefore(start) && !s.end.isAfter(end);
          final bool current = s.contains(t) && !t.isBefore(start) && !t.isAfter(end);
          if (!endsInside && !current) {
            continue;
          }
          if (s.state == SlotState.met) {
            hMet++;
          } else if (s.state == SlotState.missed) {
            hMissed++;
          } else if (s.state == SlotState.open) {
            hOpen++;
          }
        }
        if (h.kind == HabitKind.timed) {
          timed += totalValue;
        }
      }
      met += h.isNegative ? clean : hMet;
      missed += h.isNegative ? relapses : hMissed;
      stats.add(HabitPeriodStats(habit: h, met: hMet, missed: hMissed, open: hOpen, doneDays: doneDays, totalValue: totalValue, skippedDays: skippedDays, relapseDays: relapses, cleanDays: clean));
    }

    // Mejor día y día de la semana más constante.
    DateTime? bestDay;
    int bestCount = 0;
    final List<int> weekdayTotals = List<int>.filled(8, 0);
    final List<int> weekdayCounts = List<int>.filled(8, 0);
    for (DateTime d = start; !d.isAfter(lastCounted); d = addDays(d, 1)) {
      final int n = doneByDay[dayKey(d)] ?? 0;
      if (n > bestCount) {
        bestCount = n;
        bestDay = d;
      }
      weekdayTotals[d.weekday] += n;
      weekdayCounts[d.weekday] += 1;
    }
    int? bestWeekday;
    double bestAvg = 0;
    if (range != SummaryRange.week) {
      for (final int wd in orderedWeekdays(weekStart)) {
        if (weekdayCounts[wd] == 0) {
          continue;
        }
        final double avg = weekdayTotals[wd] / weekdayCounts[wd];
        if (avg > bestAvg + 1e-9) {
          bestAvg = avg;
          bestWeekday = wd;
        }
      }
    }

    // Barras: por día (semana y mes) o por mes (año).
    final List<int> bars = <int>[];
    if (range == SummaryRange.year) {
      for (int m = 1; m <= 12; m++) {
        int sum = 0;
        final int days = daysInMonth(start.year, m);
        for (int d = 1; d <= days; d++) {
          sum += doneByDay[dayKey(DateTime(start.year, m, d))] ?? 0;
        }
        bars.add(sum);
      }
    } else {
      for (DateTime d = start; !d.isAfter(end); d = addDays(d, 1)) {
        bars.add(doneByDay[dayKey(d)] ?? 0);
      }
    }

    // Entrenamientos que empezaron en el periodo.
    int workouts = 0;
    int workoutSeconds = 0;
    for (final WorkoutSession s in sessions) {
      final DateTime d = dateOnly(s.startedAt);
      if (d.isBefore(start) || d.isAfter(end)) {
        continue;
      }
      workoutSeconds += math.max(0, s.activeSeconds);
      if (s.completed) {
        workouts++;
      }
    }

    return PeriodSummary(
      range: range,
      start: start,
      end: end,
      habits: stats,
      completions: doneByDay.values.fold<int>(0, (int a, int b) => a + b),
      bestDay: bestDay,
      bestDayCount: bestCount,
      bestWeekday: bestWeekday,
      bestWeekdayAverage: bestAvg,
      timedSeconds: timed,
      workouts: workouts,
      workoutSeconds: workoutSeconds,
      bars: bars,
      met: met,
      missed: missed,
    );
  }
}
