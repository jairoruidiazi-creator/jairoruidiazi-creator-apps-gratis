import '../model/models.dart';

/// Un lapso [start, end).
class Period {
  const Period(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  int get days => end.difference(start).inDays;

  /// Último día incluido.
  DateTime get lastDay => end.subtract(const Duration(days: 1));

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
        cursor = containing(cursor).start.subtract(const Duration(days: 1));
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

/// Periodos de un presupuesto a partir de su fecha de inicio.
class BudgetPeriods {
  BudgetPeriods._();

  static Period containing(Budget b, DateTime date) {
    final DateTime d = dateOnly(date);
    final DateTime s = dateOnly(b.startDate);
    switch (b.period) {
      case BudgetPeriod.week:
        final int offset = d.difference(s).inDays;
        final int k = offset >= 0 ? offset ~/ 7 : -((-offset + 6) ~/ 7);
        final DateTime start = s.add(Duration(days: 7 * k));
        return Period(start, start.add(const Duration(days: 7)));
      case BudgetPeriod.custom:
        final int len = b.customDays < 1 ? 1 : b.customDays;
        final int offset = d.difference(s).inDays;
        final int k = offset >= 0 ? offset ~/ len : -((-offset + len - 1) ~/ len);
        final DateTime start = s.add(Duration(days: len * k));
        return Period(start, start.add(Duration(days: len)));
      case BudgetPeriod.quincena:
        return const PeriodSpec(mode: PeriodMode.quincena).containing(d);
      case BudgetPeriod.month:
        return PeriodSpec(startDay: s.day.clamp(1, 28)).containing(d);
      case BudgetPeriod.year:
        final DateTime start = d.isBefore(DateTime(d.year, s.month, s.day.clamp(1, 28))) ? DateTime(d.year - 1, s.month, s.day.clamp(1, 28)) : DateTime(d.year, s.month, s.day.clamp(1, 28));
        return Period(start, DateTime(start.year + 1, start.month, start.day));
    }
  }

  static Period previous(Budget b, Period p) => containing(b, p.start.subtract(const Duration(days: 1)));

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

  Period get period => Period(start, cut.add(const Duration(days: 1)));

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
    DateTime pay = _clamp(cut.year, cut.month, payDay);
    if (!pay.isAfter(cut)) {
      pay = _clamp(cut.year, cut.month + 1, payDay);
    }
    return CardCycle(start: prevCut.add(const Duration(days: 1)), cut: cut, payDate: pay);
  }

  /// Ciclo anterior (el último estado de cuenta ya cerrado).
  CardCycle previous(Account card) => current(card, start.subtract(const Duration(days: 1)));

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
