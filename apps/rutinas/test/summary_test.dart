import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/logic/summary.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/workout.dart';

/// Hoy: miércoles 14 de octubre de 2026. La semana va del lunes 12 al domingo 18.
final DateTime today = DateTime(2026, 10, 14);
final DateTime start = DateTime(2026, 10, 1);

Habit habit(String id, {HabitKind kind = HabitKind.check, int goal = 1, Frequency frequency = const Frequency(), DateTime? from}) =>
    Habit(id: id, name: id, kind: kind, goal: goal, frequency: frequency, startDate: from ?? start, createdAt: from ?? start);

Map<String, HabitEntry> days(Map<int, int> valueByDay, {int month = 10, Set<int> skipped = const <int>{}}) {
  final Map<String, HabitEntry> out = <String, HabitEntry>{};
  valueByDay.forEach((int d, int v) => out[dayKey(DateTime(2026, month, d))] = HabitEntry(value: v));
  for (final int d in skipped) {
    out[dayKey(DateTime(2026, month, d))] = HabitEntry(skipped: true);
  }
  return out;
}

final List<Habit> habits = <Habit>[
  habit('leer'),
  habit('agua', kind: HabitKind.count, goal: 8),
  habit('meditar', kind: HabitKind.timed, goal: 600),
  habit('fumar', kind: HabitKind.negative),
];

final Map<String, Map<String, HabitEntry>> entries = <String, Map<String, HabitEntry>>{
  'leer': days(<int, int>{12: 1, 13: 1}),
  'agua': days(<int, int>{12: 8, 13: 5, 14: 8}),
  'meditar': days(<int, int>{12: 600, 13: 300}),
  'fumar': days(<int, int>{13: 1}),
};

final List<WorkoutSession> sessions = <WorkoutSession>[
  WorkoutSession(id: 's1', name: 'Tabata', startedAt: DateTime(2026, 10, 5, 7), endedAt: DateTime(2026, 10, 5, 7, 10), activeSeconds: 600, completed: true),
  WorkoutSession(id: 's2', name: 'HIIT', startedAt: DateTime(2026, 10, 13, 7), endedAt: DateTime(2026, 10, 13, 7, 15), activeSeconds: 900, completed: true),
  WorkoutSession(id: 's3', name: 'HIIT', startedAt: DateTime(2026, 10, 14, 7), endedAt: DateTime(2026, 10, 14, 7, 5), activeSeconds: 300, completed: false),
];

PeriodSummary build(SummaryRange range, {DateTime? anchor, List<Habit>? list, Map<String, Map<String, HabitEntry>>? data}) => Summaries.build(
      range: range,
      anchor: anchor ?? today,
      today: today,
      weekStart: DateTime.monday,
      habits: list ?? habits,
      entries: data ?? entries,
      sessions: sessions,
    );

HabitPeriodStats statsOf(PeriodSummary s, String id) => s.habits.firstWhere((HabitPeriodStats h) => h.habit.id == id);

void main() {
  group('Límites de los periodos', () {
    test('semana que empieza el lunes o el domingo, mes y año', () {
      expect(Summaries.bounds(SummaryRange.week, today, DateTime.monday), <DateTime>[DateTime(2026, 10, 12), DateTime(2026, 10, 18)]);
      expect(Summaries.bounds(SummaryRange.week, today, DateTime.sunday), <DateTime>[DateTime(2026, 10, 11), DateTime(2026, 10, 17)]);
      expect(Summaries.bounds(SummaryRange.month, DateTime(2028, 2, 10), DateTime.monday), <DateTime>[DateTime(2028, 2, 1), DateTime(2028, 2, 29)]);
      expect(Summaries.bounds(SummaryRange.year, today, DateTime.monday), <DateTime>[DateTime(2026), DateTime(2026, 12, 31)]);
    });

    test('ir al periodo anterior y al siguiente', () {
      expect(Summaries.shift(SummaryRange.week, today, -1), DateTime(2026, 10, 7));
      expect(Summaries.shift(SummaryRange.month, DateTime(2026, 1, 31), 1), DateTime(2026, 2));
      expect(Summaries.shift(SummaryRange.month, DateTime(2026, 1, 15), -1), DateTime(2025, 12));
      expect(Summaries.shift(SummaryRange.year, today, 1), DateTime(2027));
    });
  });

  group('Resumen semanal', () {
    test('cumplimiento de cada hábito: hoy sin terminar no cuenta como fallado', () {
      final PeriodSummary s = build(SummaryRange.week);
      final HabitPeriodStats leer = statsOf(s, 'leer');
      expect(<int>[leer.met, leer.missed, leer.open, leer.doneDays], <int>[2, 0, 1, 2]);
      expect(leer.rate, 1.0);
      final HabitPeriodStats agua = statsOf(s, 'agua');
      expect(<int>[agua.met, agua.missed, agua.open, agua.doneDays, agua.totalValue], <int>[2, 1, 0, 2, 21]);
      final HabitPeriodStats meditar = statsOf(s, 'meditar');
      expect(<int>[meditar.met, meditar.missed, meditar.open, meditar.totalValue], <int>[1, 1, 1, 900]);
      final HabitPeriodStats fumar = statsOf(s, 'fumar');
      expect(<int>[fumar.cleanDays, fumar.relapseDays], <int>[1, 1]);
      expect(fumar.rate, 0.5);
    });

    test('totales, mejor día, minutos con tiempo y entrenamientos', () {
      final PeriodSummary s = build(SummaryRange.week);
      expect(s.start, DateTime(2026, 10, 12));
      expect(s.end, DateTime(2026, 10, 18));
      expect(s.completions, 5);
      expect(s.bestDay, DateTime(2026, 10, 12));
      expect(s.bestDayCount, 3);
      expect(s.bestWeekday, isNull);
      expect(s.timedSeconds, 900);
      expect(s.bars, <int>[3, 1, 1, 0, 0, 0, 0]);
      expect(s.met, 6);
      expect(s.missed, 3);
      expect(s.rate, closeTo(6 / 9, 1e-9));
      // Uno terminado en la semana; el interrumpido suma su tiempo.
      expect(s.workouts, 1);
      expect(s.workoutSeconds, 1200);
    });

    test('un hábito que empezó después del periodo no aparece', () {
      final PeriodSummary s = build(SummaryRange.week, anchor: DateTime(2026, 10, 7), list: <Habit>[...habits, habit('nuevo', from: DateTime(2026, 10, 12))]);
      expect(s.habits.map((HabitPeriodStats h) => h.habit.id), isNot(contains('nuevo')));
      expect(statsOf(s, 'leer').missed, 7);
      expect(s.completions, 0);
      expect(s.bestDay, isNull);
    });

    test('una semana futura queda en blanco', () {
      final PeriodSummary s = build(SummaryRange.week, anchor: DateTime(2026, 10, 21));
      expect(s.completions, 0);
      expect(s.met + s.missed, 0);
      expect(s.rate, isNull);
      expect(s.bars, everyElement(0));
      expect(s.workouts, 0);
    });
  });

  group('Resumen mensual y anual', () {
    test('el mes: días cerrados sin cumplir y el día de la semana más constante', () {
      final PeriodSummary s = build(SummaryRange.month);
      expect(s.bars, hasLength(31));
      expect(s.bars.sublist(11, 14), <int>[3, 1, 1]);
      final HabitPeriodStats leer = statsOf(s, 'leer');
      expect(<int>[leer.met, leer.missed, leer.open], <int>[2, 11, 1]);
      final HabitPeriodStats fumar = statsOf(s, 'fumar');
      expect(<int>[fumar.cleanDays, fumar.relapseDays], <int>[12, 1]);
      // Los lunes (5 y 12): 3 hábitos en dos lunes.
      expect(s.bestWeekday, DateTime.monday);
      expect(s.bestWeekdayAverage, 1.5);
      expect(s.workouts, 2);
      expect(s.workoutSeconds, 1800);
    });

    test('veces por semana: cuentan las semanas que terminan en el mes; la saltada no falla', () {
      // 3 veces por semana desde el lunes 28 de septiembre.
      final Habit gym = habit('gym', frequency: const Frequency(type: FrequencyType.perWeek, n: 3), from: DateTime(2026, 9, 28));
      final Map<String, HabitEntry> e = <String, HabitEntry>{
        ...days(<int, int>{28: 1, 30: 1}, month: 9),
        ...days(<int, int>{2: 1, 6: 1, 8: 1, 13: 1}, skipped: <int>{10}),
      };
      final PeriodSummary oct = build(SummaryRange.month, list: <Habit>[gym], data: <String, Map<String, HabitEntry>>{'gym': e});
      final HabitPeriodStats g = statsOf(oct, 'gym');
      // Semana del 28 sep al 4 oct: cumplida. Del 5 al 11: dos y un día saltado (no falla).
      // La semana actual va en curso.
      expect(<int>[g.met, g.missed, g.open], <int>[1, 0, 1]);
      expect(g.doneDays, 4);
      expect(g.skippedDays, 1);
      expect(g.rate, 1.0);
      // En septiembre ninguna semana termina dentro del mes: sin cumplimiento.
      final PeriodSummary sep = build(SummaryRange.month, anchor: DateTime(2026, 9, 15), list: <Habit>[gym], data: <String, Map<String, HabitEntry>>{'gym': e});
      expect(statsOf(sep, 'gym').rate, isNull);
      expect(statsOf(sep, 'gym').doneDays, 2);
    });

    test('el año: barras por mes', () {
      final PeriodSummary s = build(SummaryRange.year);
      expect(s.bars, hasLength(12));
      expect(s.bars[9], 5);
      expect(s.bars.fold<int>(0, (int a, int b) => a + b), 5);
      expect(s.bestDay, DateTime(2026, 10, 12));
      expect(s.workouts, 2);
    });
  });

  group('Archivados (G4)', () {
    // Uno archivado el 1 de agosto y otro hecho todos los días desde junio.
    final DateTime june = DateTime(2026, 6, 1);
    Habit archivedHabit() => habit('viejo', from: june)..archive(DateTime(2026, 8, 1));
    final Habit daily = habit('diario', from: june);
    Map<String, HabitEntry> every(DateTime a, DateTime b) => <String, HabitEntry>{
          for (DateTime x = a; !x.isAfter(b); x = addDays(x, 1)) dayKey(x): HabitEntry(value: 1),
        };
    Map<String, Map<String, HabitEntry>> data() => <String, Map<String, HabitEntry>>{
          'viejo': every(june, DateTime(2026, 7, 31)),
          'diario': every(june, DateTime(2026, 10, 13)),
        };

    test('no cuentan como fallados después de archivarlos', () {
      final PeriodSummary week = build(SummaryRange.week, list: <Habit>[archivedHabit(), daily], data: data());
      expect(week.habits.map((HabitPeriodStats h) => h.habit.id), <String>['diario']);
      expect(week.missed, 0);
      expect(week.rate, 1.0);
      final PeriodSummary year = build(SummaryRange.year, list: <Habit>[archivedHabit(), daily], data: data());
      expect(year.missed, 0);
      expect(year.rate, 1.0);
      final HabitPeriodStats old = statsOf(year, 'viejo');
      expect(old.met, 61); // junio y julio
      expect(old.missed, 0);
      // El mes en que se archivó solo cuenta hasta ese día.
      final PeriodSummary august = build(SummaryRange.month, anchor: DateTime(2026, 8, 15), list: <Habit>[archivedHabit(), daily], data: data());
      expect(august.habits.map((HabitPeriodStats h) => h.habit.id), isNot(contains('viejo')));
      expect(august.missed, 0);
    });

    test('al recuperarlo, el tiempo archivado no falla pero lo de después sí', () {
      final Habit h = archivedHabit()..unarchive(DateTime(2026, 10, 12));
      final PeriodSummary week = build(SummaryRange.week, list: <Habit>[h], data: data());
      final HabitPeriodStats st = statsOf(week, 'viejo');
      // Lunes 12 y martes 13 sin hacer; hoy en curso.
      expect(<int>[st.met, st.missed, st.open], <int>[0, 2, 1]);
      final PeriodSummary september = build(SummaryRange.month, anchor: DateTime(2026, 9, 10), list: <Habit>[h], data: data());
      expect(september.habits, isEmpty);
    });
  });
}
