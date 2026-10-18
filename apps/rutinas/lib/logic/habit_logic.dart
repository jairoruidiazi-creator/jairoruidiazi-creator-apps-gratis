import 'dart:math' as math;

import '../core/dates.dart';
import '../model/habit.dart';

/// Estado de un periodo de un hábito (un día, un bloque, una semana o un mes).
/// - met: se cumplió la meta del periodo.
/// - excused: no se cumplió, pero los días saltados a propósito cubren lo que
///   faltó, o el periodo empezó antes de que existiera el hábito.
/// - missed: periodo cerrado sin cumplir.
/// - open: el periodo de hoy, todavía sin cumplir (no rompe nada).
enum SlotState { met, excused, missed, open }

/// En qué se cuenta la racha según la frecuencia.
enum StreakUnit { days, times, weeks, months }

/// Estado de un día para pintar el calendario.
enum DayStatus { beforeStart, future, done, partial, skipped, missed, notDue, pending, relapse, clean }

class HabitSlot {
  const HabitSlot({required this.start, required this.end, required this.target, required this.done, required this.skipped, required this.state, this.partial = false});

  final DateTime start;

  /// Último día del periodo (incluido).
  final DateTime end;
  final int target;
  final int done;
  final int skipped;
  final SlotState state;

  /// El periodo empezó antes del hábito (primera semana o primer mes a medias).
  final bool partial;

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
}

class StreakInfo {
  const StreakInfo({required this.current, required this.best, required this.unit, required this.completions, required this.met, required this.missed});

  final int current;
  final int best;
  final StreakUnit unit;

  /// Días hechos (o días sin recaer en los hábitos negativos).
  final int completions;
  final int met;
  final int missed;

  /// Cumplimiento: periodos cumplidos sobre periodos cerrados (sin contar los
  /// saltados ni el de hoy si no se ha cumplido). Null si todavía no hay datos.
  double? get rate => met + missed == 0 ? null : met / (met + missed);
}

class HabitLogic {
  HabitLogic._();

  /// ¿Se dio por hecho el día? (meta diaria alcanzada).
  static bool isDone(Habit h, HabitEntry? e) {
    if (e == null || h.isNegative) {
      return false;
    }
    return e.value >= h.target;
  }

  /// Primer día que cuenta: el inicio del hábito o el primer registro, si hay
  /// uno anterior (por ejemplo, si se anotaron días pasados).
  static DateTime effectiveStart(Habit h, Map<String, HabitEntry> entries) {
    final DateTime start = dateOnly(h.startDate);
    // Las claves `aaaa-mm-dd` se ordenan igual como texto que como fecha.
    String first = dayKey(start);
    for (final MapEntry<String, HabitEntry> e in entries.entries) {
      if (e.key.compareTo(first) < 0 && !e.value.isEmpty) {
        first = e.key;
      }
    }
    return parseDayKey(first) ?? start;
  }

  static StreakUnit unitFor(Habit h) {
    if (h.isNegative) {
      return StreakUnit.days;
    }
    switch (h.frequency.type) {
      case FrequencyType.daily:
      case FrequencyType.weekdays:
        return StreakUnit.days;
      case FrequencyType.everyN:
        return StreakUnit.times;
      case FrequencyType.perWeek:
        return StreakUnit.weeks;
      case FrequencyType.perMonth:
        return StreakUnit.months;
    }
  }

  /// Periodos del hábito desde su inicio hasta el que contiene a [today].
  static List<HabitSlot> slots(Habit h, Map<String, HabitEntry> entries, DateTime today, {required int weekStart}) {
    final DateTime end = dateOnly(today);
    final DateTime start = effectiveStart(h, entries);
    final List<HabitSlot> out = <HabitSlot>[];
    if (h.isNegative || start.isAfter(end)) {
      return out;
    }
    final Frequency f = h.frequency.normalized();
    HabitSlot build(DateTime a, DateTime b, int target, bool partial) {
      int done = 0;
      int skipped = 0;
      for (DateTime d = a; !d.isAfter(b) && !d.isAfter(end); d = addDays(d, 1)) {
        if (d.isBefore(start)) {
          continue;
        }
        final HabitEntry? e = entries[dayKey(d)];
        if (isDone(h, e)) {
          done++;
        } else if (e != null && e.skipped) {
          skipped++;
        }
      }
      SlotState state;
      if (done >= target) {
        state = SlotState.met;
      } else if (!b.isBefore(end)) {
        state = SlotState.open;
      } else if (partial || done + skipped >= target) {
        state = SlotState.excused;
      } else {
        state = SlotState.missed;
      }
      return HabitSlot(start: a, end: b, target: target, done: done, skipped: skipped, state: state, partial: partial);
    }

    switch (f.type) {
      case FrequencyType.daily:
        for (DateTime d = start; !d.isAfter(end); d = addDays(d, 1)) {
          out.add(build(d, d, 1, false));
        }
        break;
      case FrequencyType.weekdays:
        for (DateTime d = start; !d.isAfter(end); d = addDays(d, 1)) {
          if (f.weekdays.contains(d.weekday)) {
            out.add(build(d, d, 1, false));
          }
        }
        break;
      case FrequencyType.everyN:
        for (DateTime a = start; !a.isAfter(end); a = addDays(a, f.n)) {
          out.add(build(a, addDays(a, f.n - 1), 1, false));
        }
        break;
      case FrequencyType.perWeek:
        for (DateTime a = startOfWeek(start, weekStart); !a.isAfter(end); a = addDays(a, 7)) {
          out.add(build(a, addDays(a, 6), f.n, a.isBefore(start)));
        }
        break;
      case FrequencyType.perMonth:
        for (DateTime a = startOfMonth(start); !a.isAfter(end); a = DateTime(a.year, a.month + 1)) {
          final int target = math.min(f.n, daysInMonth(a.year, a.month));
          out.add(build(a, endOfMonth(a), target, a.isBefore(start)));
        }
        break;
    }
    return out;
  }

  /// Racha actual y mejor racha. La racha no se rompe por los días que no
  /// tocan, por los saltados a propósito ni por el periodo de hoy sin terminar.
  static StreakInfo streak(Habit h, Map<String, HabitEntry> entries, DateTime today, {required int weekStart}) {
    if (h.isNegative) {
      return negativeStreak(h, entries, today);
    }
    int run = 0;
    int best = 0;
    int met = 0;
    int missed = 0;
    for (final HabitSlot s in slots(h, entries, today, weekStart: weekStart)) {
      switch (s.state) {
        case SlotState.met:
          run++;
          met++;
          best = math.max(best, run);
          break;
        case SlotState.missed:
          run = 0;
          missed++;
          break;
        case SlotState.excused:
        case SlotState.open:
          break;
      }
    }
    int completions = 0;
    final DateTime end = dateOnly(today);
    for (final MapEntry<String, HabitEntry> e in entries.entries) {
      final DateTime? d = parseDayKey(e.key);
      if (d != null && !d.isAfter(end) && isDone(h, e.value)) {
        completions++;
      }
    }
    return StreakInfo(current: run, best: best, unit: unitFor(h), completions: completions, met: met, missed: missed);
  }

  /// Días de recaída (con al menos una recaída), en orden, hasta [today].
  static List<DateTime> relapseDays(Habit h, Map<String, HabitEntry> entries, DateTime today) {
    final DateTime end = dateOnly(today);
    final List<DateTime> days = <DateTime>[];
    for (final MapEntry<String, HabitEntry> e in entries.entries) {
      final DateTime? d = parseDayKey(e.key);
      if (d != null && !d.isAfter(end) && e.value.value > 0) {
        days.add(d);
      }
    }
    days.sort();
    return days;
  }

  /// Hábitos negativos: días completos sin recaer. Hoy no cuenta hasta que
  /// termina (el día que se empieza o se recae, la racha es 0).
  static StreakInfo negativeStreak(Habit h, Map<String, HabitEntry> entries, DateTime today) {
    final DateTime end = dateOnly(today);
    final DateTime start = effectiveStart(h, entries);
    DateTime cleanStart = start;
    int best = 0;
    final List<DateTime> relapses = relapseDays(h, entries, today).where((DateTime d) => !d.isBefore(start)).toList();
    for (final DateTime r in relapses) {
      best = math.max(best, daysBetween(cleanStart, r));
      cleanStart = addDays(r, 1);
    }
    final int current = math.max(0, daysBetween(cleanStart, end));
    best = math.max(best, current);
    final int elapsed = math.max(0, daysBetween(start, end));
    final int relapsedPast = relapses.where((DateTime d) => d.isBefore(end)).length;
    final int clean = math.max(0, elapsed - relapsedPast);
    return StreakInfo(current: current, best: best, unit: StreakUnit.days, completions: clean, met: clean, missed: relapsedPast);
  }

  /// Periodo que contiene a [day], o null si es anterior al hábito o el día no toca.
  static HabitSlot? slotFor(Habit h, Map<String, HabitEntry> entries, DateTime day, DateTime today, {required int weekStart}) {
    final DateTime d = dateOnly(day);
    for (final HabitSlot s in slots(h, entries, today, weekStart: weekStart).reversed) {
      if (s.contains(d)) {
        return s;
      }
      if (s.end.isBefore(d)) {
        return null;
      }
    }
    return null;
  }

  /// ¿Le toca algo al hábito el día [day]? Para la lista de hoy: los de
  /// frecuencia por bloque, semana o mes tocan mientras su periodo no se cumpla.
  static bool isDueOn(Habit h, Map<String, HabitEntry> entries, DateTime day, DateTime today, {required int weekStart}) {
    final DateTime d = dateOnly(day);
    if (h.archived || d.isBefore(effectiveStart(h, entries))) {
      return false;
    }
    if (h.isNegative) {
      return true;
    }
    final Frequency f = h.frequency.normalized();
    switch (f.type) {
      case FrequencyType.daily:
        return true;
      case FrequencyType.weekdays:
        return f.weekdays.contains(d.weekday);
      case FrequencyType.everyN:
      case FrequencyType.perWeek:
      case FrequencyType.perMonth:
        if (isDone(h, entries[dayKey(d)])) {
          return true;
        }
        final HabitSlot? s = slotFor(h, entries, d, d.isAfter(today) ? d : today, weekStart: weekStart);
        return s == null || s.done < s.target;
    }
  }

  /// Estado de un día para el calendario del hábito.
  static DayStatus dayStatus(Habit h, Map<String, HabitEntry> entries, DateTime day, DateTime today, {required int weekStart}) {
    final DateTime d = dateOnly(day);
    final DateTime t = dateOnly(today);
    if (d.isAfter(t)) {
      return DayStatus.future;
    }
    if (d.isBefore(effectiveStart(h, entries))) {
      return DayStatus.beforeStart;
    }
    final HabitEntry? e = entries[dayKey(d)];
    if (h.isNegative) {
      if (e != null && e.value > 0) {
        return DayStatus.relapse;
      }
      return sameDay(d, t) ? DayStatus.pending : DayStatus.clean;
    }
    if (isDone(h, e)) {
      return DayStatus.done;
    }
    if (e != null && e.skipped) {
      return DayStatus.skipped;
    }
    final bool started = e != null && e.value > 0;
    final Frequency f = h.frequency.normalized();
    switch (f.type) {
      case FrequencyType.daily:
      case FrequencyType.weekdays:
        if (f.type == FrequencyType.weekdays && !f.weekdays.contains(d.weekday)) {
          return started ? DayStatus.partial : DayStatus.notDue;
        }
        if (sameDay(d, t)) {
          return started ? DayStatus.partial : DayStatus.pending;
        }
        return started ? DayStatus.partial : DayStatus.missed;
      case FrequencyType.everyN:
      case FrequencyType.perWeek:
      case FrequencyType.perMonth:
        // En estos hábitos ningún día suelto falla: cuenta el periodo entero.
        if (started) {
          return DayStatus.partial;
        }
        return sameDay(d, t) ? DayStatus.pending : DayStatus.notDue;
    }
  }

  /// Progreso del periodo actual (bloque, semana o mes): hechos y meta.
  static HabitSlot? currentSlot(Habit h, Map<String, HabitEntry> entries, DateTime today, {required int weekStart}) {
    final List<HabitSlot> all = slots(h, entries, today, weekStart: weekStart);
    if (all.isEmpty) {
      return null;
    }
    final HabitSlot last = all.last;
    return last.contains(dateOnly(today)) ? last : null;
  }
}
