import '../../core/dates.dart';
import '../../logic/habit_logic.dart';
import '../../model/habit.dart';

/// Textos de los hábitos en español e inglés.
class HabitTexts {
  HabitTexts._();

  static String kind(HabitKind k, bool es) {
    switch (k) {
      case HabitKind.check:
        return es ? 'Sí o no' : 'Yes or no';
      case HabitKind.count:
        return es ? 'Varias veces' : 'Several times';
      case HabitKind.timed:
        return es ? 'Con tiempo' : 'Timed';
      case HabitKind.negative:
        return es ? 'Dejar de…' : 'Quit…';
    }
  }

  static String kindHelp(HabitKind k, bool es) {
    switch (k) {
      case HabitKind.check:
        return es ? 'Se marca hecho una vez al día (leer, tender la cama).' : 'Checked off once a day (read, make the bed).';
      case HabitKind.count:
        return es ? 'Varias veces al día hasta una meta (8 vasos de agua).' : 'Several times a day up to a goal (8 glasses of water).';
      case HabitKind.timed:
        return es ? 'Minutos al día con el temporizador (meditar 10 min).' : 'Minutes a day with the timer (meditate 10 min).';
      case HabitKind.negative:
        return es ? 'Algo que quieres dejar: se cuentan los días sin recaer.' : 'Something to quit: counts the days without a slip.';
    }
  }

  static String _list(List<String> items, bool es) {
    if (items.isEmpty) {
      return '';
    }
    if (items.length == 1) {
      return items.first;
    }
    return '${items.sublist(0, items.length - 1).join(', ')} ${es ? 'y' : 'and'} ${items.last}';
  }

  static String frequency(Frequency f, bool es, int weekStart) {
    final Frequency n = f.normalized();
    switch (n.type) {
      case FrequencyType.daily:
        return es ? 'Todos los días' : 'Every day';
      case FrequencyType.weekdays:
        final List<int> order = orderedWeekdays(weekStart).where(n.weekdays.contains).toList();
        final String days = _list(order.map((int d) => weekdayShort(d, spanish: es)).toList(), es);
        return es ? 'Los $days' : 'On $days';
      case FrequencyType.everyN:
        return es ? 'Cada ${n.n} días' : 'Every ${n.n} days';
      case FrequencyType.perWeek:
        return es ? '${n.n} ${n.n == 1 ? 'vez' : 'veces'} por semana' : '${n.n} ${n.n == 1 ? 'time' : 'times'} a week';
      case FrequencyType.perMonth:
        return es ? '${n.n} ${n.n == 1 ? 'vez' : 'veces'} al mes' : '${n.n} ${n.n == 1 ? 'time' : 'times'} a month';
    }
  }

  static String streakUnit(StreakUnit u, int n, bool es) {
    switch (u) {
      case StreakUnit.days:
        return es ? (n == 1 ? 'día' : 'días') : (n == 1 ? 'day' : 'days');
      case StreakUnit.times:
        return es ? (n == 1 ? 'vez' : 'veces') : (n == 1 ? 'time' : 'times');
      case StreakUnit.weeks:
        return es ? (n == 1 ? 'semana' : 'semanas') : (n == 1 ? 'week' : 'weeks');
      case StreakUnit.months:
        return es ? (n == 1 ? 'mes' : 'meses') : (n == 1 ? 'month' : 'months');
    }
  }

  /// "Racha: 12 días".
  static String streak(StreakInfo s, bool es) => '${s.current} ${streakUnit(s.unit, s.current, es)}';

  static String unit(Habit h, int n, bool es) {
    final String u = h.unit.trim();
    if (u.isNotEmpty) {
      return u;
    }
    return es ? (n == 1 ? 'vez' : 'veces') : (n == 1 ? 'time' : 'times');
  }

  /// Valor de un día: "5 de 8 vasos", "4 de 10 min", "Hecho". La meta es la
  /// que regía ese [day] (la de hoy si es null).
  static String progress(Habit h, HabitEntry? e, bool es, {DateTime? day}) {
    final int v = e?.value ?? 0;
    final int target = h.targetOn(day);
    switch (h.kind) {
      case HabitKind.check:
        if (e != null && e.skipped && v < 1) {
          return es ? 'Saltado' : 'Skipped';
        }
        return v >= 1 ? (es ? 'Hecho' : 'Done') : (es ? 'Pendiente' : 'To do');
      case HabitKind.count:
        final String base = es ? '$v de $target ${unit(h, target, es)}' : '$v of $target ${unit(h, target, es)}';
        return e != null && e.skipped && v < target ? '$base · ${es ? 'saltado' : 'skipped'}' : base;
      case HabitKind.timed:
        final String base = es ? '${minutesOf(v, es)} de ${minutesOf(target, es)} min' : '${minutesOf(v, es)} of ${minutesOf(target, es)} min';
        return e != null && e.skipped && v < target ? '$base · ${es ? 'saltado' : 'skipped'}' : base;
      case HabitKind.negative:
        return v == 0 ? (es ? 'Sin recaídas' : 'No slips') : (es ? '$v ${v == 1 ? 'recaída' : 'recaídas'}' : '$v ${v == 1 ? 'slip' : 'slips'}');
    }
  }

  /// Minutos con un decimal si hace falta ("2,5" / "2.5").
  static String _minutes(int seconds) {
    if (seconds % 60 == 0) {
      return '${seconds ~/ 60}';
    }
    return (seconds / 60).toStringAsFixed(1);
  }

  static String minutesOf(int seconds, bool es) {
    final String m = _minutes(seconds);
    return es ? m.replaceAll('.', ',') : m;
  }

  /// Fracción del día cumplida (0 a 1), para el anillo.
  static double fraction(Habit h, HabitEntry? e, {DateTime? day}) {
    final int v = e?.value ?? 0;
    if (h.isNegative) {
      return v == 0 ? 1 : 0;
    }
    return (v / h.targetOn(day)).clamp(0.0, 1.0).toDouble();
  }

  /// "2 de 3 esta semana" ([current]) o "2 de 3 esa semana" (un periodo pasado),
  /// con la regla de ese periodo.
  static String? period(Habit h, HabitSlot? s, bool es, {bool current = true}) {
    if (s == null) {
      return null;
    }
    switch (s.frequency.type) {
      case FrequencyType.daily:
      case FrequencyType.weekdays:
        return null;
      case FrequencyType.everyN:
        final int n = s.frequency.n;
        final String block = es ? (current ? 'este bloque de $n días' : 'ese bloque de $n días') : (current ? 'this $n-day block' : 'that $n-day block');
        return s.done >= s.target ? (es ? 'Hecho en $block' : 'Done for $block') : (es ? 'Falta en $block' : 'Due in $block');
      case FrequencyType.perWeek:
        return es ? '${s.done} de ${s.target} ${current ? 'esta semana' : 'esa semana'}' : '${s.done} of ${s.target} ${current ? 'this week' : 'that week'}';
      case FrequencyType.perMonth:
        return es ? '${s.done} de ${s.target} ${current ? 'este mes' : 'ese mes'}' : '${s.done} of ${s.target} ${current ? 'this month' : 'that month'}';
    }
  }
}
