import 'dart:math' as math;

import '../core/dates.dart';
import '../model/habit.dart';

/// Estado de un periodo de un hábito (un día, un bloque, una semana o un mes).
/// - met: se cumplió la meta del periodo.
/// - excused: no se cumplió, pero los días saltados a propósito cubren lo que
///   faltó, el periodo quedó partido (empezó antes que el hábito o cambió la
///   regla en medio) o cae en un tramo archivado.
/// - missed: periodo cerrado sin cumplir.
/// - open: el periodo de hoy, todavía sin cumplir (no rompe nada).
enum SlotState { met, excused, missed, open }

/// En qué se cuenta la racha según la frecuencia.
enum StreakUnit { days, times, weeks, months }

/// Estado de un día para pintar el calendario.
enum DayStatus { beforeStart, future, done, partial, skipped, missed, notDue, pending, relapse, clean, paused }

class HabitSlot {
  const HabitSlot({required this.start, required this.end, required this.target, required this.done, required this.skipped, required this.state, required this.frequency, this.partial = false});

  final DateTime start;

  /// Último día del periodo (incluido).
  final DateTime end;
  final int target;
  final int done;
  final int skipped;
  final SlotState state;

  /// Regla con que se evalúa el periodo.
  final Frequency frequency;

  /// El periodo quedó partido: empezó antes del hábito o cambió la regla en medio.
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

/// Un tramo de días con la misma estructura de periodos (días sueltos,
/// bloques de N días, semanas o meses).
class _Run {
  _Run(this.start, this.end, this.frequency);

  final DateTime start;
  DateTime end;

  /// Frecuencia al empezar el tramo (la estructura es la misma en todo el tramo).
  final Frequency frequency;
}

class HabitLogic {
  HabitLogic._();

  /// ¿Se dio por hecho el día [day]? (la meta de ese día alcanzada).
  static bool isDone(Habit h, HabitEntry? e, DateTime day) {
    if (e == null || h.isNegative) {
      return false;
    }
    return e.value >= h.targetOn(day);
  }

  /// Primer día que cuenta: el inicio del hábito o el primer día con algo
  /// anotado (hecho o a medias), si es anterior. Una nota o un día saltado
  /// solos no adelantan el inicio, y en los hábitos de dejar algo una recaída
  /// anotada antes de empezar tampoco.
  static DateTime effectiveStart(Habit h, Map<String, HabitEntry> entries) {
    final DateTime start = dateOnly(h.startDate);
    if (h.isNegative) {
      return start;
    }
    // Las claves `aaaa-mm-dd` se ordenan igual como texto que como fecha.
    String first = dayKey(start);
    for (final MapEntry<String, HabitEntry> e in entries.entries) {
      if (e.key.compareTo(first) < 0 && e.value.value > 0 && parseDayKey(e.key) != null) {
        first = e.key;
      }
    }
    return parseDayKey(first) ?? start;
  }

  static StreakUnit unitFor(Habit h) {
    if (h.isNegative) {
      return StreakUnit.days;
    }
    switch (h.frequency.normalized().type) {
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

  /// Clave de la estructura de periodos: dos reglas seguidas con la misma
  /// clave comparten periodos (por ejemplo, de 3 a 4 veces por semana la
  /// semana del cambio se evalúa entera con la regla nueva).
  static String structureOf(Frequency f) {
    switch (f.type) {
      case FrequencyType.daily:
      case FrequencyType.weekdays:
        return 'day';
      case FrequencyType.everyN:
        return 'every${f.n}';
      case FrequencyType.perWeek:
        return 'week';
      case FrequencyType.perMonth:
        return 'month';
    }
  }

  /// Tramos de [start] a [end] con la misma estructura de periodos, según las
  /// reglas que rigieron cada día.
  static List<_Run> _runs(Habit h, DateTime start, DateTime end) {
    final List<_Run> out = <_Run>[];
    void add(DateTime a, DateTime b, Frequency f) {
      if (b.isBefore(a)) {
        return;
      }
      if (out.isNotEmpty && structureOf(out.last.frequency) == structureOf(f) && sameDay(addDays(out.last.end, 1), a)) {
        out.last.end = b;
      } else {
        out.add(_Run(a, b, f));
      }
    }

    DateTime from = start;
    for (final PastRule p in h.pastRules) {
      if (from.isAfter(end)) {
        break;
      }
      if (!p.until.isBefore(from)) {
        add(from, p.until.isAfter(end) ? end : p.until, p.frequency.normalized());
        from = addDays(p.until, 1);
      }
    }
    if (!from.isAfter(end)) {
      add(from, end, h.frequency.normalized());
    }
    return out;
  }

  /// Periodos del hábito desde su inicio hasta el que contiene a [today].
  static List<HabitSlot> slots(Habit h, Map<String, HabitEntry> entries, DateTime today, {required int weekStart}) {
    final DateTime end = dateOnly(today);
    final DateTime start = effectiveStart(h, entries);
    final List<HabitSlot> out = <HabitSlot>[];
    if (h.isNegative || start.isAfter(end)) {
      return out;
    }

    // Un periodo de [a] a [b] (su forma natural), recortado al tramo [runA, runB].
    HabitSlot build(DateTime a, DateTime b, DateTime runA, DateTime runB, Frequency f, int Function(DateTime last) targetFor) {
      final DateTime from = a.isBefore(runA) ? runA : a;
      final DateTime to = b.isAfter(runB) ? runB : b;
      final bool cutStart = a.isBefore(runA);
      // Cortado al final por un cambio de regla (no por hoy).
      final bool cutEnd = b.isAfter(runB) && runB.isBefore(end);
      int done = 0;
      int skipped = 0;
      for (DateTime d = from; !d.isAfter(to) && !d.isAfter(end); d = addDays(d, 1)) {
        final HabitEntry? e = entries[dayKey(d)];
        if (isDone(h, e, d)) {
          done++;
        } else if (e != null && e.skipped) {
          skipped++;
        }
      }
      final DateTime last = to.isAfter(end) ? end : to;
      final int target = targetFor(last);
      SlotState state;
      if (done >= target) {
        state = SlotState.met;
      } else if (h.pausedBetween(from, last)) {
        state = SlotState.excused;
      } else if (!cutEnd && !b.isBefore(end)) {
        state = SlotState.open;
      } else if (cutStart || cutEnd || done + skipped >= target) {
        state = SlotState.excused;
      } else {
        state = SlotState.missed;
      }
      // El periodo conserva su forma natural (la semana entera) cuando lo parte
      // el inicio del hábito o el día de hoy; si lo parte un cambio de regla,
      // queda recortado para no solaparse con el periodo de la regla vecina.
      final DateTime shownStart = cutStart && !sameDay(runA, start) ? from : a;
      final DateTime shownEnd = cutEnd ? to : b;
      return HabitSlot(start: shownStart, end: shownEnd, target: target, done: done, skipped: skipped, state: state, frequency: f, partial: cutStart || cutEnd);
    }

    for (final _Run run in _runs(h, start, end)) {
      switch (run.frequency.type) {
        case FrequencyType.daily:
        case FrequencyType.weekdays:
          // Días sueltos: cada día toca o no según la regla de ese día.
          for (DateTime d = run.start; !d.isAfter(run.end); d = addDays(d, 1)) {
            final Frequency f = h.frequencyOn(d);
            if (f.type == FrequencyType.daily || (f.type == FrequencyType.weekdays && f.weekdays.contains(d.weekday))) {
              out.add(build(d, d, run.start, run.end, f, (DateTime _) => 1));
            }
          }
          break;
        case FrequencyType.everyN:
          final int n = run.frequency.n;
          for (DateTime a = run.start; !a.isAfter(run.end); a = addDays(a, n)) {
            out.add(build(a, addDays(a, n - 1), run.start, run.end, run.frequency, (DateTime _) => 1));
          }
          break;
        case FrequencyType.perWeek:
          for (DateTime a = startOfWeek(run.start, weekStart); !a.isAfter(run.end); a = addDays(a, 7)) {
            // La meta de la semana es la de la regla que rige su último día.
            out.add(build(a, addDays(a, 6), run.start, run.end, run.frequency, (DateTime last) => h.frequencyOn(last).n));
          }
          break;
        case FrequencyType.perMonth:
          for (DateTime a = startOfMonth(run.start); !a.isAfter(run.end); a = DateTime(a.year, a.month + 1)) {
            out.add(build(a, endOfMonth(a), run.start, run.end, run.frequency, (DateTime last) => math.min(h.frequencyOn(last).n, daysInMonth(a.year, a.month))));
          }
          break;
      }
    }
    return out;
  }

  /// Racha actual y mejor racha. La racha no se rompe por los días que no
  /// tocan, por los saltados a propósito, por el periodo de hoy sin terminar
  /// ni por los tramos archivados.
  ///
  /// La racha se cuenta en la unidad de la frecuencia vigente (días, veces,
  /// semanas o meses). Si la frecuencia cambió de estructura (por ejemplo, de
  /// 3 por semana a todos los días), la racha vuelve a contar desde el cambio,
  /// y la mejor racha solo mira los tramos con la estructura de ahora: así el
  /// número nunca mezcla semanas con días. Los periodos anteriores siguen en el
  /// cumplimiento y en el calendario.
  static StreakInfo streak(Habit h, Map<String, HabitEntry> entries, DateTime today, {required int weekStart}) {
    if (h.isNegative) {
      return negativeStreak(h, entries, today);
    }
    final String current = structureOf(h.frequency.normalized());
    String? previous;
    int run = 0;
    int best = 0;
    int met = 0;
    int missed = 0;
    for (final HabitSlot s in slots(h, entries, today, weekStart: weekStart)) {
      final String structure = structureOf(s.frequency.normalized());
      if (previous != null && structure != previous) {
        run = 0;
      }
      previous = structure;
      switch (s.state) {
        case SlotState.met:
          run++;
          met++;
          if (structure == current) {
            best = math.max(best, run);
          }
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
      if (d != null && !d.isAfter(end) && isDone(h, e.value, d)) {
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
  /// termina (el día que se empieza o se recae, la racha es 0). Los días
  /// archivados no suman ni rompen.
  static StreakInfo negativeStreak(Habit h, Map<String, HabitEntry> entries, DateTime today) {
    final DateTime end = dateOnly(today);
    final DateTime start = effectiveStart(h, entries);
    final Set<String> relapses = relapseDays(h, entries, today).map(dayKey).toSet();
    int run = 0;
    int best = 0;
    int clean = 0;
    int slips = 0;
    for (DateTime d = start; d.isBefore(end); d = addDays(d, 1)) {
      if (relapses.contains(dayKey(d))) {
        best = math.max(best, run);
        run = 0;
        slips++;
      } else if (!h.pausedOn(d)) {
        run++;
        clean++;
      }
    }
    best = math.max(best, run);
    final int current = relapses.contains(dayKey(end)) ? 0 : run;
    return StreakInfo(current: current, best: best, unit: StreakUnit.days, completions: clean, met: clean, missed: slips);
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
  /// frecuencia por bloque, semana o mes tocan mientras su periodo no esté
  /// cubierto (con lo hecho y lo saltado a propósito).
  static bool isDueOn(Habit h, Map<String, HabitEntry> entries, DateTime day, DateTime today, {required int weekStart}) {
    final DateTime d = dateOnly(day);
    if (h.archived || d.isBefore(effectiveStart(h, entries)) || h.pausedOn(d)) {
      return false;
    }
    if (h.isNegative) {
      return true;
    }
    final Frequency f = h.frequencyOn(d);
    switch (f.type) {
      case FrequencyType.daily:
        return true;
      case FrequencyType.weekdays:
        return f.weekdays.contains(d.weekday);
      case FrequencyType.everyN:
      case FrequencyType.perWeek:
      case FrequencyType.perMonth:
        if (isDone(h, entries[dayKey(d)], d)) {
          return true;
        }
        final HabitSlot? s = slotFor(h, entries, d, d.isAfter(today) ? d : today, weekStart: weekStart);
        return s == null || s.done + s.skipped < s.target;
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
      if (h.pausedOn(d)) {
        return DayStatus.paused;
      }
      return sameDay(d, t) ? DayStatus.pending : DayStatus.clean;
    }
    if (isDone(h, e, d)) {
      return DayStatus.done;
    }
    if (e != null && e.skipped) {
      return DayStatus.skipped;
    }
    final bool started = e != null && e.value > 0;
    if (h.pausedOn(d)) {
      return started ? DayStatus.partial : DayStatus.paused;
    }
    final Frequency f = h.frequencyOn(d);
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
