import '../model/models.dart';

/// Un lapso [start, end).
class Period {
  const Period(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  int get days => daysBetween(start, end);

  /// Último día incluido.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  @override
  bool operator ==(Object other) => other is Period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Period(${dayKey(start)} → ${dayKey(end)})';
}

enum PeriodMode { month, quincena }

/// Cómo se parte el tiempo para el inicio ("mes") de la app: un mes que
/// empieza el día de pago, o quincenas (1–15 y 16–fin).
class PeriodSpec {
  const PeriodSpec({this.mode = PeriodMode.month, this.startDay = 1});

  final PeriodMode mode;

  /// Día del mes en que empieza el periodo (1–28), modo mes.
  final int startDay;

  Period containing(DateTime date) {
    final DateTime d = dateOnly(date);
    switch (mode) {
      case PeriodMode.quincena:
        if (d.day <= 15) {
          return Period(DateTime(d.year, d.month), DateTime(d.year, d.month, 16));
        }
        return Period(DateTime(d.year, d.month, 16), DateTime(d.year, d.month + 1));
      case PeriodMode.month:
        final int s = startDay.clamp(1, 28);
        final DateTime start = d.day >= s ? DateTime(d.year, d.month, s) : DateTime(d.year, d.month - 1, s);
        return Period(start, DateTime(start.year, start.month + 1, s));
    }
  }

  Period shift(Period p, int n) {
    if (n == 0) {
      return p;
    }
    DateTime cursor = p.start;
    if (n > 0) {
      for (int i = 0; i < n; i++) {
        cursor = containing(cursor).end;
      }
    } else {
      for (int i = 0; i < -n; i++) {
        cursor = addDays(containing(cursor).start, -1);
      }
    }
    return containing(cursor);
  }

  /// Los últimos [n] periodos terminando en el que contiene [now] (orden cronológico).
  List<Period> lastN(DateTime now, int n) {
    final Period current = containing(now);
    final List<Period> out = <Period>[current];
    for (int i = 1; i < n; i++) {
      out.insert(0, shift(out.first, -1));
    }
    return out;
  }

  /// Etiqueta corta: "oct 2026", "1–15 oct" o "16–31 oct".
  String label(Period p, {bool spanish = true}) {
    switch (mode) {
      case PeriodMode.quincena:
        return '${p.start.day}–${p.lastDay.day} ${formatDate(p.start, 'MMM', spanish: spanish)}';
      case PeriodMode.month:
        if (startDay == 1) {
          return formatDate(p.start, 'MMM yyyy', spanish: spanish);
        }
        return '${formatDate(p.start, 'dd MMM', spanish: spanish)} – ${formatDate(p.lastDay, 'dd MMM', spanish: spanish)}';
    }
  }
}

/// Periodos de un presupuesto a partir de su fecha de inicio. Todo se cuenta
/// en días de calendario, para que el horario de verano no corra los cortes.
class BudgetPeriods {
  BudgetPeriods._();

  static Period containing(Budget b, DateTime date) {
    final DateTime d = dateOnly(date);
    final DateTime s = dateOnly(b.startDate);
    switch (b.period) {
      case BudgetPeriod.week:
        return _fixed(s, d, 7);
      case BudgetPeriod.custom:
        return _fixed(s, d, b.customDays < 1 ? 1 : b.customDays);
      case BudgetPeriod.quincena:
        return const PeriodSpec(mode: PeriodMode.quincena).containing(d);
      case BudgetPeriod.month:
        return PeriodSpec(startDay: s.day.clamp(1, 28)).containing(d);
      case BudgetPeriod.year:
        final DateTime start = d.isBefore(DateTime(d.year, s.month, s.day.clamp(1, 28))) ? DateTime(d.year - 1, s.month, s.day.clamp(1, 28)) : DateTime(d.year, s.month, s.day.clamp(1, 28));
        return Period(start, DateTime(start.year + 1, start.month, start.day));
    }
  }

  /// Bloques de [len] días contados desde [s].
  static Period _fixed(DateTime s, DateTime d, int len) {
    final int offset = daysBetween(s, d);
    final int k = offset >= 0 ? offset ~/ len : -((-offset + len - 1) ~/ len);
    final DateTime start = DateTime(s.year, s.month, s.day + len * k);
    return Period(start, DateTime(start.year, start.month, start.day + len));
  }

  static Period previous(Budget b, Period p) => containing(b, addDays(p.start, -1));

  static Period next(Budget b, Period p) => containing(b, p.end);
}

/// Ciclo de una tarjeta de crédito: (corte anterior, corte] y fecha de pago.
class CardCycle {
  const CardCycle({required this.start, required this.cut, required this.payDate});

  /// Primer día incluido en el estado de cuenta.
  final DateTime start;

  /// Día de corte (incluido).
  final DateTime cut;
  final DateTime payDate;

  Period get period => Period(start, DateTime(cut.year, cut.month, cut.day + 1));

  /// Ciclo cuyo corte es el primero en o después de [date] (el ciclo "actual").
  static CardCycle current(Account card, DateTime date) {
    final int cutDay = (card.cutDay ?? 1).clamp(1, 31);
    final int payDay = (card.payDay ?? cutDay).clamp(1, 31);
    final DateTime d = dateOnly(date);
    DateTime cut = _clamp(d.year, d.month, cutDay);
    if (cut.isBefore(d)) {
      cut = _clamp(d.year, d.month + 1, cutDay);
    }
    final DateTime prevCut = _clamp(cut.year, cut.month - 1, cutDay);
    return CardCycle(start: DateTime(prevCut.year, prevCut.month, prevCut.day + 1), cut: cut, payDate: payDateFor(cut, cutDay, payDay));
  }

  /// Fecha límite de pago del estado que corta en [cut]. Si el día de pago va
  /// después del de corte, se paga ese mismo mes; si no, el mes siguiente. En
  /// un mes corto el día de pago puede quedar recortado sobre el corte (corte
  /// 30 y pago 31 en febrero): entonces se conserva la distancia entre los dos
  /// días, para que cada estado de cuenta tenga su propia fecha de pago.
  static DateTime payDateFor(DateTime cut, int cutDay, int payDay) {
    if (payDay > cutDay) {
      final DateTime same = _clamp(cut.year, cut.month, payDay);
      if (same.isAfter(cut)) {
        return same;
      }
      return DateTime(cut.year, cut.month, cut.day + (payDay - cutDay));
    }
    return _clamp(cut.year, cut.month + 1, payDay);
  }

  /// Corte que cae [months] meses después de [cut] (o antes, si es negativo).
  static DateTime cutAfter(Account card, DateTime cut, int months) => _clamp(cut.year, cut.month + months, (card.cutDay ?? 1).clamp(1, 31));

  /// Meses de corte entre dos cortes (0 si son el mismo ciclo).
  static int cyclesBetween(DateTime cutA, DateTime cutB) => (cutB.year - cutA.year) * 12 + (cutB.month - cutA.month);

  /// Ciclo anterior (el último estado de cuenta ya cerrado).
  CardCycle previous(Account card) => current(card, DateTime(start.year, start.month, start.day - 1));

  static DateTime _clamp(int y, int m, int day) {
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    final int last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, day > last ? last : day);
  }
}
