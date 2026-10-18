import '../../core/dates.dart';
import '../../model/reminder.dart';

/// Textos de los recordatorios en español e inglés.
class ReminderTexts {
  ReminderTexts._();

  /// "Hoy, 18:30" / "Mañana, 8:00" / "mar 14 oct, 8:00".
  static String when(DateTime d, DateTime now, bool es) {
    final int days = daysBetween(now, d);
    final String time = formatTime(d, spanish: es);
    if (days == 0) {
      return es ? 'Hoy, $time' : 'Today, $time';
    }
    if (days == 1) {
      return es ? 'Mañana, $time' : 'Tomorrow, $time';
    }
    if (days == -1) {
      return es ? 'Ayer, $time' : 'Yesterday, $time';
    }
    final String date = formatShortDate(d, spanish: es);
    return d.year == now.year ? '$date, $time' : '$date ${d.year}, $time';
  }

  static String recurrence(Recurrence r, bool es, int weekStart) {
    final Recurrence n = r.normalized();
    switch (n.type) {
      case RecurrenceType.once:
        return es ? 'No se repite' : 'Does not repeat';
      case RecurrenceType.everyNDays:
        if (n.n == 1) {
          return es ? 'Todos los días' : 'Every day';
        }
        return es ? 'Cada ${n.n} días' : 'Every ${n.n} days';
      case RecurrenceType.weekdays:
        final List<String> names = orderedWeekdays(weekStart).where(n.weekdays.contains).map((int d) => weekdayShort(d, spanish: es)).toList();
        return es ? 'Los ${names.join(', ')}' : 'On ${names.join(', ')}';
      case RecurrenceType.monthlyDay:
        return es ? 'El ${n.day} de cada mes' : 'Day ${n.day} of every month';
      case RecurrenceType.monthlyLast:
        return es ? 'El último día de cada mes' : 'Last day of every month';
      case RecurrenceType.yearly:
        return es ? 'Cada ${n.day} de ${monthName(n.month, spanish: true)}' : 'Every ${monthName(n.month, spanish: false)} ${n.day}';
    }
  }

  static String typeLabel(RecurrenceType t, bool es) {
    switch (t) {
      case RecurrenceType.once:
        return es ? 'Una vez' : 'Once';
      case RecurrenceType.everyNDays:
        return es ? 'Cada N días' : 'Every N days';
      case RecurrenceType.weekdays:
        return es ? 'Días de la semana' : 'Days of the week';
      case RecurrenceType.monthlyDay:
        return es ? 'Cada mes' : 'Monthly';
      case RecurrenceType.monthlyLast:
        return es ? 'Último día del mes' : 'Last day of the month';
      case RecurrenceType.yearly:
        return es ? 'Cada año' : 'Yearly';
    }
  }

  /// "Insiste cada 5 min".
  static String nag(int minutes, bool es) => es ? 'Insiste cada $minutes min' : 'Repeats every $minutes min';
}
