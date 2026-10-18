import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/logic/habit_logic.dart';
import 'package:rutinas/model/habit.dart';

/// Hoy en estas pruebas: miércoles 14 de octubre de 2026.
final DateTime today = DateTime(2026, 10, 14);

DateTime d(int month, int day) => DateTime(2026, month, day);

Habit habit({HabitKind kind = HabitKind.check, Frequency frequency = const Frequency(), int goal = 1, required DateTime start}) =>
    Habit(id: 'h', name: 'Prueba', kind: kind, frequency: frequency, goal: goal, startDate: start, createdAt: start);

/// Registros a partir de valores por día; [skipped] marca días saltados.
Map<String, HabitEntry> log(Map<DateTime, int> values, {List<DateTime> skipped = const <DateTime>[]}) {
  final Map<String, HabitEntry> out = <String, HabitEntry>{};
  values.forEach((DateTime day, int v) => out[dayKey(day)] = HabitEntry(value: v));
  for (final DateTime s in skipped) {
    out.putIfAbsent(dayKey(s), () => HabitEntry()).skipped = true;
  }
  return out;
}

Map<DateTime, int> done(List<DateTime> days, [int value = 1]) => <DateTime, int>{for (final DateTime x in days) x: value};

List<DateTime> range(DateTime a, DateTime b) => <DateTime>[for (DateTime x = a; !x.isAfter(b); x = addDays(x, 1)) x];

void main() {
  group('Diarios', () {
    test('la racha cuenta los días seguidos y hoy sin terminar no la rompe', () {
      final Habit h = habit(start: d(10, 1));
      final Map<String, HabitEntry> e = log(done(<DateTime>[...range(d(10, 1), d(10, 5)), ...range(d(10, 7), d(10, 13))]));
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 7);
      expect(s.best, 7);
      expect(s.met, 12);
      expect(s.missed, 1); // el 6 de octubre
      expect(s.completions, 12);
      expect(s.unit, StreakUnit.days);
      expect(s.rate, closeTo(12 / 13, 1e-9));
      // Al marcar hoy, la racha suma.
      e[dayKey(today)] = HabitEntry(value: 1);
      expect(HabitLogic.streak(h, e, today, weekStart: DateTime.monday).current, 8);
    });

    test('un día saltado a propósito no rompe la racha ni la suma', () {
      final Habit h = habit(start: d(10, 10));
      final Map<String, HabitEntry> e = log(done(<DateTime>[d(10, 10), d(10, 11), d(10, 13)]), skipped: <DateTime>[d(10, 12)]);
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 3);
      expect(s.best, 3);
      expect(s.missed, 0);
      expect(HabitLogic.dayStatus(h, e, d(10, 12), today, weekStart: DateTime.monday), DayStatus.skipped);
    });

    test('un día fallado la deja en cero hasta el siguiente hecho', () {
      final Habit h = habit(start: d(10, 10));
      final Map<String, HabitEntry> e = log(done(<DateTime>[d(10, 10), d(10, 11), d(10, 12)]));
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 0); // el 13 no se hizo
      expect(s.best, 3);
      expect(HabitLogic.dayStatus(h, e, d(10, 13), today, weekStart: DateTime.monday), DayStatus.missed);
      expect(HabitLogic.dayStatus(h, e, today, today, weekStart: DateTime.monday), DayStatus.pending);
      expect(HabitLogic.dayStatus(h, e, d(10, 15), today, weekStart: DateTime.monday), DayStatus.future);
      expect(HabitLogic.dayStatus(h, e, d(10, 9), today, weekStart: DateTime.monday), DayStatus.beforeStart);
    });

    test('anotar un día anterior al inicio adelanta el inicio', () {
      final Habit h = habit(start: d(10, 12));
      final Map<String, HabitEntry> e = log(done(<DateTime>[d(10, 10), d(10, 11), d(10, 12), d(10, 13)]));
      expect(HabitLogic.effectiveStart(h, e), d(10, 10));
      expect(HabitLogic.streak(h, e, today, weekStart: DateTime.monday).current, 4);
    });

    test('un hábito que empieza en el futuro no tiene periodos ni toca hoy', () {
      final Habit h = habit(start: d(10, 20));
      expect(HabitLogic.slots(h, const <String, HabitEntry>{}, today, weekStart: DateTime.monday), isEmpty);
      expect(HabitLogic.isDueOn(h, const <String, HabitEntry>{}, today, today, weekStart: DateTime.monday), isFalse);
      expect(HabitLogic.streak(h, const <String, HabitEntry>{}, today, weekStart: DateTime.monday).current, 0);
    });
  });

  group('Días de la semana', () {
    test('los días que no tocan no rompen la racha', () {
      final Habit h = habit(start: d(9, 28), frequency: const Frequency(type: FrequencyType.weekdays, weekdays: <int>[1, 3, 5]));
      // Lunes 28, miércoles 30, viernes 2, lunes 5, miércoles 7, (viernes 9 no), lunes 12; hoy miércoles 14 sin hacer.
      final Map<String, HabitEntry> e = log(done(<DateTime>[d(9, 28), d(9, 30), d(10, 2), d(10, 5), d(10, 7), d(10, 12)]));
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 1);
      expect(s.best, 5);
      expect(s.missed, 1);
      expect(HabitLogic.dayStatus(h, e, d(10, 13), today, weekStart: DateTime.monday), DayStatus.notDue);
      expect(HabitLogic.dayStatus(h, e, d(10, 9), today, weekStart: DateTime.monday), DayStatus.missed);
      expect(HabitLogic.isDueOn(h, e, today, today, weekStart: DateTime.monday), isTrue);
      expect(HabitLogic.isDueOn(h, e, d(10, 13), today, weekStart: DateTime.monday), isFalse);
    });

    test('hacerlo un día que no toca cuenta como hecho pero no como periodo', () {
      final Habit h = habit(start: d(10, 12), frequency: const Frequency(type: FrequencyType.weekdays, weekdays: <int>[1, 3]));
      final Map<String, HabitEntry> e = log(done(<DateTime>[d(10, 12), d(10, 13)]));
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 1);
      expect(s.completions, 2);
    });
  });

  group('Cada N días', () {
    test('basta una vez en cada bloque de N días', () {
      final Habit h = habit(start: d(10, 1), frequency: const Frequency(type: FrequencyType.everyN, n: 3));
      // Bloques: 1-3 (hecho el 2), 4-6 (hecho el 6), 7-9 (nada), 10-12 (hecho el 10), 13-15 (en curso).
      final Map<String, HabitEntry> e = log(done(<DateTime>[d(10, 2), d(10, 6), d(10, 10)]));
      final List<HabitSlot> slots = HabitLogic.slots(h, e, today, weekStart: DateTime.monday);
      expect(slots.map((HabitSlot s) => s.state).toList(), <SlotState>[SlotState.met, SlotState.met, SlotState.missed, SlotState.met, SlotState.open]);
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 1);
      expect(s.best, 2);
      expect(s.unit, StreakUnit.times);
      expect(HabitLogic.isDueOn(h, e, today, today, weekStart: DateTime.monday), isTrue);
      // Hecho el 13: el bloque queda cumplido y el 14 ya no toca.
      e[dayKey(d(10, 13))] = HabitEntry(value: 1);
      expect(HabitLogic.isDueOn(h, e, today, today, weekStart: DateTime.monday), isFalse);
      expect(HabitLogic.streak(h, e, today, weekStart: DateTime.monday).current, 2);
    });
  });

  group('Veces por semana', () {
    test('cuenta semanas cumplidas; la semana de hoy no rompe y la primera a medias se excusa', () {
      final Habit h = habit(start: d(9, 30), frequency: const Frequency(type: FrequencyType.perWeek, n: 3));
      final Map<String, HabitEntry> e = log(done(<DateTime>[d(10, 1), d(10, 3), d(10, 5), d(10, 7), d(10, 9), d(10, 12)]));
      final List<HabitSlot> slots = HabitLogic.slots(h, e, today, weekStart: DateTime.monday);
      expect(slots.length, 3);
      expect(slots[0].start, d(9, 28));
      expect(slots[0].partial, isTrue);
      expect(slots.map((HabitSlot s) => s.state).toList(), <SlotState>[SlotState.excused, SlotState.met, SlotState.open]);
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 1);
      expect(s.unit, StreakUnit.weeks);
      expect(HabitLogic.currentSlot(h, e, today, weekStart: DateTime.monday)!.done, 1);
    });

    test('los días saltados cubren lo que faltó en la semana', () {
      final Habit h = habit(start: d(9, 14), frequency: const Frequency(type: FrequencyType.perWeek, n: 3));
      final Map<String, HabitEntry> e = log(
        done(<DateTime>[d(9, 14), d(9, 16), d(9, 18), d(9, 22), d(9, 28), d(9, 30), d(10, 5), d(10, 7), d(10, 9), d(10, 12), d(10, 13), d(10, 14)]),
        skipped: <DateTime>[d(10, 2)],
      );
      final List<SlotState> states = HabitLogic.slots(h, e, today, weekStart: DateTime.monday).map((HabitSlot s) => s.state).toList();
      // 14-20 sep cumplida, 21-27 fallada (1), 28 sep-4 oct excusada (2 + 1 saltado), 5-11 cumplida, 12-18 cumplida (hoy).
      expect(states, <SlotState>[SlotState.met, SlotState.missed, SlotState.excused, SlotState.met, SlotState.met]);
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 2);
      expect(s.best, 2);
      expect(s.met, 3);
      expect(s.missed, 1);
    });

    test('la semana empieza el día elegido', () {
      final Habit h = habit(start: d(10, 11), frequency: const Frequency(type: FrequencyType.perWeek, n: 1));
      final List<HabitSlot> monday = HabitLogic.slots(h, const <String, HabitEntry>{}, today, weekStart: DateTime.monday);
      final List<HabitSlot> sunday = HabitLogic.slots(h, const <String, HabitEntry>{}, today, weekStart: DateTime.sunday);
      expect(monday.first.start, d(10, 5));
      expect(sunday.first.start, d(10, 11));
      expect(sunday.first.partial, isFalse);
    });
  });

  group('Veces al mes', () {
    test('cuenta meses cumplidos', () {
      final Habit h = habit(start: d(8, 1), frequency: const Frequency(type: FrequencyType.perMonth, n: 10));
      final Map<String, HabitEntry> e = log(done(<DateTime>[...range(d(8, 1), d(8, 10)), ...range(d(9, 1), d(9, 5)), ...range(d(10, 1), d(10, 3))]));
      final List<SlotState> states = HabitLogic.slots(h, e, today, weekStart: DateTime.monday).map((HabitSlot s) => s.state).toList();
      expect(states, <SlotState>[SlotState.met, SlotState.missed, SlotState.open]);
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 0);
      expect(s.best, 1);
      expect(s.unit, StreakUnit.months);
    });

    test('la meta nunca pasa de los días del mes', () {
      final Habit h = habit(start: DateTime(2026, 2, 1), frequency: const Frequency(type: FrequencyType.perMonth, n: 31));
      final Map<String, HabitEntry> e = log(done(range(DateTime(2026, 2, 1), DateTime(2026, 2, 28))));
      final List<HabitSlot> slots = HabitLogic.slots(h, e, DateTime(2026, 3, 2), weekStart: DateTime.monday);
      expect(slots.first.target, 28);
      expect(slots.first.state, SlotState.met);
    });
  });

  group('Con meta y con tiempo', () {
    test('varias veces al día: solo cuenta al llegar a la meta', () {
      final Habit h = habit(kind: HabitKind.count, goal: 8, start: d(10, 12));
      final Map<String, HabitEntry> e = log(<DateTime, int>{d(10, 12): 8, d(10, 13): 5, today: 3});
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 0);
      expect(s.best, 1);
      expect(HabitLogic.dayStatus(h, e, d(10, 13), today, weekStart: DateTime.monday), DayStatus.partial);
      expect(HabitLogic.dayStatus(h, e, today, today, weekStart: DateTime.monday), DayStatus.partial);
      expect(HabitLogic.isDone(h, e[dayKey(d(10, 12))]), isTrue);
      expect(HabitLogic.isDone(h, e[dayKey(d(10, 13))]), isFalse);
    });

    test('con tiempo: los segundos tienen que llegar a la meta', () {
      final Habit h = habit(kind: HabitKind.timed, goal: 600, start: d(10, 12));
      final Map<String, HabitEntry> e = log(<DateTime, int>{d(10, 12): 599, d(10, 13): 600});
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 1);
      expect(s.missed, 1);
    });
  });

  group('Dejar de…', () {
    test('cuenta días completos sin recaer', () {
      final Habit h = habit(kind: HabitKind.negative, start: d(10, 1));
      final Map<String, HabitEntry> e = log(<DateTime, int>{d(10, 5): 1, d(10, 10): 2});
      final StreakInfo s = HabitLogic.streak(h, e, today, weekStart: DateTime.monday);
      expect(s.current, 3); // 11, 12 y 13; hoy aún no termina
      expect(s.best, 4); // del 1 al 4 y del 6 al 9
      expect(s.missed, 2);
      expect(s.met, 11);
      expect(s.rate, closeTo(11 / 13, 1e-9));
      expect(HabitLogic.dayStatus(h, e, d(10, 5), today, weekStart: DateTime.monday), DayStatus.relapse);
      expect(HabitLogic.dayStatus(h, e, d(10, 6), today, weekStart: DateTime.monday), DayStatus.clean);
      expect(HabitLogic.dayStatus(h, e, today, today, weekStart: DateTime.monday), DayStatus.pending);
    });

    test('recaer hoy deja la racha en cero; empezar hoy también', () {
      final Habit h = habit(kind: HabitKind.negative, start: d(10, 1));
      expect(HabitLogic.streak(h, log(<DateTime, int>{today: 1}), today, weekStart: DateTime.monday).current, 0);
      final Habit fresh = habit(kind: HabitKind.negative, start: today);
      expect(HabitLogic.streak(fresh, const <String, HabitEntry>{}, today, weekStart: DateTime.monday).current, 0);
      expect(HabitLogic.streak(fresh, const <String, HabitEntry>{}, addDays(today, 1), weekStart: DateTime.monday).current, 1);
    });

    test('los hábitos negativos siempre tocan', () {
      final Habit h = habit(kind: HabitKind.negative, start: d(10, 1));
      expect(HabitLogic.isDueOn(h, const <String, HabitEntry>{}, today, today, weekStart: DateTime.monday), isTrue);
      expect(HabitLogic.slots(h, const <String, HabitEntry>{}, today, weekStart: DateTime.monday), isEmpty);
    });
  });

  group('Modelo', () {
    test('la frecuencia se normaliza y viaja en JSON', () {
      expect(const Frequency(type: FrequencyType.weekdays, weekdays: <int>[]).normalized().type, FrequencyType.daily);
      expect(const Frequency(type: FrequencyType.weekdays, weekdays: <int>[1, 2, 3, 4, 5, 6, 7]).normalized().type, FrequencyType.daily);
      expect(const Frequency(type: FrequencyType.perWeek, n: 12).normalized().n, 7);
      expect(const Frequency(type: FrequencyType.everyN, n: 1).normalized().n, 2);
      const Frequency f = Frequency(type: FrequencyType.weekdays, weekdays: <int>[5, 1, 3]);
      expect(Frequency.fromJson(f.toJson()).weekdays, <int>[1, 3, 5]);
      final Habit h = habit(kind: HabitKind.count, goal: 8, start: d(10, 1), frequency: f)
        ..unit = 'vasos'
        ..reminders = <int>[480, 1200]
        ..nagMinutes = 15;
      final Habit back = Habit.fromJson(h.toJson());
      expect(back.kind, HabitKind.count);
      expect(back.goal, 8);
      expect(back.unit, 'vasos');
      expect(back.frequency, Frequency.fromJson(f.toJson()));
      expect(back.reminders, <int>[480, 1200]);
      expect(back.nagMinutes, 15);
      expect(back.startDate, d(10, 1));
    });

    test('las claves de día se leen y se rechazan las inválidas', () {
      expect(parseDayKey('2026-02-28'), DateTime(2026, 2, 28));
      expect(parseDayKey('2026-02-29'), isNull);
      expect(parseDayKey('2028-02-29'), DateTime(2028, 2, 29));
      expect(parseDayKey('2026-13-01'), isNull);
      expect(parseDayKey('2026-1-01'), isNull);
      expect(parseDayKey('abcd-ef-gh'), isNull);
      expect(dayKey(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
      expect(daysBetween(DateTime(2026, 3, 1), DateTime(2026, 4, 1)), 31);
      expect(startOfWeek(today, DateTime.monday), d(10, 12));
      expect(startOfWeek(today, DateTime.sunday), d(10, 11));
    });
  });
}
