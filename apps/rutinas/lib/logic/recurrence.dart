import 'dart:math' as math;

import '../core/dates.dart';
import '../model/reminder.dart';

/// Cálculo de las ocurrencias de los recordatorios.
class Recurrences {
  Recurrences._();

  /// Primera ocurrencia estrictamente posterior a [after], con la hora del día
  /// de [anchor]. En "cada N días" la serie arranca en [anchor]; en las demás,
  /// el día sale de la regla (día de la semana, del mes o del año).
  static DateTime? next(Recurrence rule, DateTime anchor, DateTime after) {
    final Recurrence r = rule.normalized();
    final int hh = anchor.hour;
    final int mm = anchor.minute;
    DateTime at(int y, int m, int d) => DateTime(y, m, d, hh, mm);
    switch (r.type) {
      case RecurrenceType.once:
        return null;
      case RecurrenceType.everyNDays:
        if (anchor.isAfter(after)) {
          return anchor;
        }
        // Saltos de N días de calendario desde el ancla (con la misma hora).
        int k = (daysBetween(anchor, after) ~/ r.n);
        DateTime c = at(anchor.year, anchor.month, anchor.day + k * r.n);
        while (!c.isAfter(after)) {
          k++;
          c = at(anchor.year, anchor.month, anchor.day + k * r.n);
        }
        return c;
      case RecurrenceType.weekdays:
        for (int i = 0; i <= 7; i++) {
          final DateTime c = at(after.year, after.month, after.day + i);
          if (r.weekdays.contains(c.weekday) && c.isAfter(after)) {
            return c;
          }
        }
        return null;
      case RecurrenceType.monthlyDay:
        for (int i = 0; i <= 13; i++) {
          final int y = after.year + (after.month - 1 + i) ~/ 12;
          final int m = (after.month - 1 + i) % 12 + 1;
          final DateTime c = at(y, m, math.min(r.day, daysInMonth(y, m)));
          if (c.isAfter(after)) {
            return c;
          }
        }
        return null;
      case RecurrenceType.monthlyLast:
        for (int i = 0; i <= 13; i++) {
          final int y = after.year + (after.month - 1 + i) ~/ 12;
          final int m = (after.month - 1 + i) % 12 + 1;
          final DateTime c = at(y, m, daysInMonth(y, m));
          if (c.isAfter(after)) {
            return c;
          }
        }
        return null;
      case RecurrenceType.yearly:
        for (int y = after.year; y <= after.year + 8; y++) {
          final DateTime c = at(y, r.month, math.min(r.day, daysInMonth(y, r.month)));
          if (c.isAfter(after)) {
            return c;
          }
        }
        return null;
    }
  }

  /// Ajusta la primera fecha de un recordatorio que se repite para que caiga
  /// en un día de la regla: si [first] ya cumple, se queda; si no, pasa a la
  /// siguiente ocurrencia.
  static DateTime align(Recurrence rule, DateTime first) {
    final Recurrence r = rule.normalized();
    if (r.type == RecurrenceType.once || r.type == RecurrenceType.everyNDays) {
      return first;
    }
    return next(r, first, first.subtract(const Duration(minutes: 1))) ?? first;
  }

  /// Las próximas [count] ocurrencias después de [after] (sin incluir la del ancla
  /// si ya pasó).
  static List<DateTime> upcoming(Recurrence rule, DateTime anchor, DateTime after, int count) {
    final List<DateTime> out = <DateTime>[];
    DateTime cursor = after;
    for (int i = 0; i < count; i++) {
      final DateTime? n = next(rule, anchor, cursor);
      if (n == null) {
        break;
      }
      out.add(n);
      cursor = n;
    }
    return out;
  }
}

/// Operaciones sobre un recordatorio que dependen de la hora.
class ReminderLogic {
  ReminderLogic._();

  /// Marca hecho: los que no se repiten quedan hechos; los que se repiten
  /// pasan a la siguiente ocurrencia después de ahora.
  static void complete(Reminder r, DateTime now) {
    r.completions.add(now);
    if (r.completions.length > 200) {
      r.completions.removeRange(0, r.completions.length - 200);
    }
    r.snoozedUntil = null;
    if (!r.recurrence.repeats) {
      r.doneAt = now;
      return;
    }
    final DateTime after = now.isAfter(r.dueAt) ? now : r.dueAt;
    final DateTime? next = Recurrences.next(r.recurrence, r.dueAt, after);
    if (next == null) {
      r.doneAt = now;
    } else {
      r.dueAt = next;
    }
  }

  /// Un recordatorio que se repite y no se marcó a tiempo pasa a la ocurrencia
  /// más reciente cuando llega la siguiente (la anterior queda perdida, como en
  /// un despertador). Devuelve true si cambió.
  static bool rollOver(Reminder r, DateTime now) {
    if (r.done || !r.recurrence.repeats) {
      return false;
    }
    bool changed = false;
    for (int guard = 0; guard < 2000; guard++) {
      final DateTime? next = Recurrences.next(r.recurrence, r.dueAt, r.dueAt);
      if (next == null || next.isAfter(now)) {
        break;
      }
      r.dueAt = next;
      changed = true;
    }
    if (changed && r.snoozedUntil != null && r.snoozedUntil!.isBefore(r.dueAt)) {
      r.snoozedUntil = null;
    }
    return changed;
  }

  static void snooze(Reminder r, DateTime now, int minutes) {
    r.snoozedUntil = now.add(Duration(minutes: minutes));
  }

  /// Vuelve a abrir un recordatorio hecho (deshacer).
  static void reopen(Reminder r) {
    r.doneAt = null;
    if (r.completions.isNotEmpty) {
      r.completions.removeLast();
    }
  }

  static bool isOverdue(Reminder r, DateTime now) => !r.done && !r.alertAt.isAfter(now);
}
