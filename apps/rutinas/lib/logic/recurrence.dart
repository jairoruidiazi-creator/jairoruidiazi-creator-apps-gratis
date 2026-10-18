import 'dart:math' as math;

import '../core/dates.dart';
import '../model/reminder.dart';

/// Arma una fecha y hora locales a partir de sus partes. En la app es la hora
/// del teléfono; las pruebas pasan una zona con cambio de horario (paquete
/// timezone) para comprobar que las horas no se corren.
typedef LocalTime = DateTime Function(int year, int month, int day, int hour, int minute);

/// La hora local del teléfono. Si la hora no existe ese día (el reloj salta de
/// 2:00 a 3:00), Dart da la hora corrida (2:30 pasa a 3:30).
DateTime phoneTime(int year, int month, int day, int hour, int minute) => DateTime(year, month, day, hour, minute);

/// Cálculo de las ocurrencias de los recordatorios.
class Recurrences {
  Recurrences._();

  /// Primera ocurrencia estrictamente posterior a [after]. La hora del día sale
  /// de la regla (o de [anchor] si la regla es vieja y no la trae). En "cada N
  /// días" la serie arranca en el día de [anchor]; en las demás, el día sale de
  /// la regla (día de la semana, del mes o del año).
  static DateTime? next(Recurrence rule, DateTime anchor, DateTime after, {LocalTime local = phoneTime}) {
    final Recurrence r = rule.normalized();
    final int hh = r.hour ?? anchor.hour;
    final int mm = r.hour == null ? anchor.minute : (r.minute ?? 0);
    DateTime at(int y, int m, int d) => local(y, m, d, hh, mm);
    switch (r.type) {
      case RecurrenceType.once:
        return null;
      case RecurrenceType.everyNDays:
        // Saltos de N días de calendario desde el día del ancla, a la hora de la regla.
        int k = daysBetween(anchor, after) ~/ r.n;
        if (k < 0) {
          k = 0;
        }
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
  static DateTime align(Recurrence rule, DateTime first, {LocalTime local = phoneTime}) {
    final Recurrence r = rule.normalized();
    if (r.type == RecurrenceType.once || r.type == RecurrenceType.everyNDays) {
      return first;
    }
    return next(r, first, first.subtract(const Duration(minutes: 1)), local: local) ?? first;
  }

  /// Las próximas [count] ocurrencias después de [after] (sin incluir la del ancla
  /// si ya pasó).
  static List<DateTime> upcoming(Recurrence rule, DateTime anchor, DateTime after, int count, {LocalTime local = phoneTime}) {
    final List<DateTime> out = <DateTime>[];
    DateTime cursor = after;
    for (int i = 0; i < count; i++) {
      final DateTime? n = next(rule, anchor, cursor, local: local);
      if (n == null) {
        break;
      }
      out.add(n);
      cursor = n;
    }
    return out;
  }
}

/// Con cuánta anticipación se puede posponer un recordatorio que todavía no
/// suena: posponer es para lo que ya sonó o está por sonar.
const Duration kSnoozeWindow = Duration(hours: 1);

/// Operaciones sobre un recordatorio que dependen de la hora.
class ReminderLogic {
  ReminderLogic._();

  /// Marca hecho: los que no se repiten quedan hechos; los que se repiten
  /// pasan a la siguiente ocurrencia después de ahora.
  static void complete(Reminder r, DateTime now, {LocalTime local = phoneTime}) {
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
    final DateTime? next = Recurrences.next(r.recurrence, r.dueAt, after, local: local);
    if (next == null) {
      r.doneAt = now;
    } else {
      r.dueAt = next;
    }
  }

  /// Un recordatorio que se repite y no se marcó a tiempo pasa a la ocurrencia
  /// más reciente cuando llega la siguiente (la anterior queda perdida, como en
  /// un despertador). Devuelve true si cambió.
  static bool rollOver(Reminder r, DateTime now, {LocalTime local = phoneTime}) {
    if (r.done || !r.recurrence.repeats) {
      return false;
    }
    bool changed = false;
    for (int guard = 0; guard < 2000; guard++) {
      final DateTime? next = Recurrences.next(r.recurrence, r.dueAt, r.dueAt, local: local);
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

  /// ¿Se puede posponer ahora? Solo lo que ya sonó o suena dentro de
  /// [kSnoozeWindow]: posponer uno de dentro de días lo haría sonar antes.
  static bool canSnooze(Reminder r, DateTime now) => !r.done && !r.alertAt.isAfter(now.add(kSnoozeWindow));

  /// Pospone [minutes] desde que suena: desde ahora si ya sonó, o desde su hora
  /// si todavía no llega. Nunca queda antes de la hora del recordatorio.
  static void snooze(Reminder r, DateTime now, int minutes) {
    final DateTime base = r.alertAt.isAfter(now) ? r.alertAt : now;
    snoozeUntil(r, base.add(Duration(minutes: minutes)));
  }

  /// Pospone hasta [target] (por ejemplo, mañana a las 9:00), nunca antes de
  /// la hora del recordatorio.
  static void snoozeUntil(Reminder r, DateTime target) {
    r.snoozedUntil = target.isBefore(r.dueAt) ? r.dueAt : target;
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
