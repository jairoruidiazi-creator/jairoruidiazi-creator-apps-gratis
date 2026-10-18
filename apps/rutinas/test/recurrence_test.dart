import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/logic/recurrence.dart';
import 'package:rutinas/model/reminder.dart';

DateTime at(int y, int m, int d, [int h = 8, int min = 0]) => DateTime(y, m, d, h, min);

List<DateTime> series(Recurrence r, DateTime anchor, int n) => Recurrences.upcoming(r, anchor, anchor, n);

void main() {
  group('Ocurrencias', () {
    test('una vez no se repite', () {
      expect(Recurrences.next(const Recurrence(), at(2026, 10, 14), at(2026, 10, 14)), isNull);
    });

    test('cada día y cada N días con la hora del ancla', () {
      const Recurrence daily = Recurrence(type: RecurrenceType.everyNDays);
      expect(Recurrences.next(daily, at(2026, 10, 14, 8, 30), at(2026, 10, 14, 9)), at(2026, 10, 15, 8, 30));
      expect(Recurrences.next(daily, at(2026, 10, 14, 8, 30), at(2026, 10, 14, 7)), at(2026, 10, 14, 8, 30));
      const Recurrence every3 = Recurrence(type: RecurrenceType.everyNDays, n: 3);
      expect(series(every3, at(2026, 10, 30), 3), <DateTime>[at(2026, 11, 2), at(2026, 11, 5), at(2026, 11, 8)]);
      // Muy atrasado: salta directo a la próxima de la serie.
      // 1 de enero + 3k días: 13 de octubre, 16 de octubre…
      expect(Recurrences.next(every3, at(2026, 1, 1), at(2026, 10, 14, 12)), at(2026, 10, 16));
    });

    test('días de la semana', () {
      const Recurrence r = Recurrence(type: RecurrenceType.weekdays, weekdays: <int>[1, 5]);
      // Miércoles 14 de octubre de 2026 → viernes 16, lunes 19, viernes 23.
      expect(series(r, at(2026, 10, 14), 3), <DateTime>[at(2026, 10, 16), at(2026, 10, 19), at(2026, 10, 23)]);
      // Un lunes antes de la hora: toca ese mismo día.
      expect(Recurrences.next(r, at(2026, 10, 12, 18), at(2026, 10, 19, 9)), at(2026, 10, 19, 18));
    });

    test('mensual el 31 cae en el último día de los meses cortos y vuelve al 31', () {
      const Recurrence r = Recurrence(type: RecurrenceType.monthlyDay, day: 31);
      expect(series(r, at(2026, 1, 31), 6), <DateTime>[at(2026, 2, 28), at(2026, 3, 31), at(2026, 4, 30), at(2026, 5, 31), at(2026, 6, 30), at(2026, 7, 31)]);
      expect(Recurrences.next(r, at(2028, 1, 31), at(2028, 1, 31)), at(2028, 2, 29));
    });

    test('mensual el 30 en febrero', () {
      const Recurrence r = Recurrence(type: RecurrenceType.monthlyDay, day: 30);
      expect(Recurrences.next(r, at(2026, 1, 30), at(2026, 1, 30)), at(2026, 2, 28));
      expect(Recurrences.next(r, at(2028, 1, 30), at(2028, 1, 30)), at(2028, 2, 29));
      expect(Recurrences.next(r, at(2026, 2, 28), at(2026, 2, 28)), at(2026, 3, 30));
    });

    test('último día del mes', () {
      const Recurrence r = Recurrence(type: RecurrenceType.monthlyLast);
      expect(series(r, at(2027, 12, 31, 20), 4), <DateTime>[at(2028, 1, 31, 20), at(2028, 2, 29, 20), at(2028, 3, 31, 20), at(2028, 4, 30, 20)]);
    });

    test('anual: el 29 de febrero cae el 28 en los años no bisiestos', () {
      const Recurrence r = Recurrence(type: RecurrenceType.yearly, month: 2, day: 29);
      expect(series(r, at(2028, 2, 29), 4), <DateTime>[at(2029, 2, 28), at(2030, 2, 28), at(2031, 2, 28), at(2032, 2, 29)]);
      const Recurrence birthday = Recurrence(type: RecurrenceType.yearly, month: 10, day: 18);
      expect(Recurrences.next(birthday, at(2026, 10, 18, 7), at(2026, 10, 18, 7)), at(2027, 10, 18, 7));
    });

    test('la primera fecha se ajusta a la regla', () {
      const Recurrence r = Recurrence(type: RecurrenceType.weekdays, weekdays: <int>[1]);
      expect(Recurrences.align(r, at(2026, 10, 14, 9)), at(2026, 10, 19, 9));
      expect(Recurrences.align(r, at(2026, 10, 19, 9)), at(2026, 10, 19, 9));
      expect(Recurrences.align(const Recurrence(type: RecurrenceType.monthlyLast), at(2026, 10, 14, 9)), at(2026, 10, 31, 9));
    });

    test('la regla se normaliza y viaja en JSON', () {
      expect(const Recurrence(type: RecurrenceType.weekdays).normalized().type, RecurrenceType.everyNDays);
      expect(const Recurrence(type: RecurrenceType.monthlyDay, day: 40).normalized().day, 31);
      expect(const Recurrence(type: RecurrenceType.yearly, month: 2, day: 30).normalized().day, 29);
      const Recurrence r = Recurrence(type: RecurrenceType.weekdays, weekdays: <int>[3, 1]);
      expect(Recurrence.fromJson(r.toJson()).weekdays, <int>[1, 3]);
    });
  });

  group('Recordatorios', () {
    Reminder make(DateTime due, {Recurrence rec = const Recurrence(), int nag = 0}) => Reminder(id: 'r', title: 'Pastilla', dueAt: due, recurrence: rec, nagMinutes: nag, createdAt: due);

    test('marcar hecho uno de una vez lo cierra', () {
      final Reminder r = make(at(2026, 10, 14, 8));
      ReminderLogic.complete(r, at(2026, 10, 14, 8, 5));
      expect(r.done, isTrue);
      expect(r.completions, hasLength(1));
      ReminderLogic.reopen(r);
      expect(r.done, isFalse);
      expect(r.completions, isEmpty);
    });

    test('marcar hecho uno que se repite pasa a la siguiente ocurrencia', () {
      final Reminder r = make(at(2026, 10, 14, 8), rec: const Recurrence(type: RecurrenceType.everyNDays));
      // Hecho antes de la hora: la siguiente es mañana, no hoy otra vez.
      ReminderLogic.complete(r, at(2026, 10, 14, 7, 50));
      expect(r.dueAt, at(2026, 10, 15, 8));
      expect(r.done, isFalse);
      // Hecho con días de atraso: salta a la próxima después de ahora.
      ReminderLogic.complete(r, at(2026, 10, 18, 9));
      expect(r.dueAt, at(2026, 10, 19, 8));
    });

    test('mensual del 31 mantiene el día al marcarlo hecho', () {
      final Reminder r = make(at(2026, 1, 31, 9), rec: const Recurrence(type: RecurrenceType.monthlyDay, day: 31));
      ReminderLogic.complete(r, at(2026, 1, 31, 9, 1));
      expect(r.dueAt, at(2026, 2, 28, 9));
      ReminderLogic.complete(r, at(2026, 2, 28, 9, 1));
      expect(r.dueAt, at(2026, 3, 31, 9));
    });

    test('sin marcar, pasa a la ocurrencia más reciente cuando llega la siguiente', () {
      final Reminder r = make(at(2026, 10, 10, 8), rec: const Recurrence(type: RecurrenceType.everyNDays));
      r.snoozedUntil = at(2026, 10, 10, 8, 30);
      expect(ReminderLogic.rollOver(r, at(2026, 10, 14, 7)), isTrue);
      expect(r.dueAt, at(2026, 10, 13, 8));
      expect(r.snoozedUntil, isNull);
      expect(ReminderLogic.isOverdue(r, at(2026, 10, 14, 7)), isTrue);
      expect(ReminderLogic.rollOver(r, at(2026, 10, 14, 7, 30)), isFalse);
      // Los de una vez nunca se mueven solos.
      final Reminder once = make(at(2026, 10, 10, 8));
      expect(ReminderLogic.rollOver(once, at(2026, 10, 14)), isFalse);
      expect(once.dueAt, at(2026, 10, 10, 8));
    });

    test('posponer cambia la hora del aviso, no la del recordatorio', () {
      final Reminder r = make(at(2026, 10, 14, 8), nag: 5);
      ReminderLogic.snooze(r, at(2026, 10, 14, 8, 2), 10);
      expect(r.alertAt, at(2026, 10, 14, 8, 12));
      expect(r.dueAt, at(2026, 10, 14, 8));
    });

    test('viaja en JSON', () {
      final Reminder r = make(at(2026, 10, 14, 8), rec: const Recurrence(type: RecurrenceType.yearly, month: 10, day: 14), nag: 15)
        ..notes = 'Con agua'
        ..countdownSeconds = 600
        ..snoozedUntil = at(2026, 10, 14, 8, 10);
      final Reminder back = Reminder.fromJson(r.toJson());
      expect(back.title, 'Pastilla');
      expect(back.notes, 'Con agua');
      expect(back.recurrence, r.recurrence);
      expect(back.nagMinutes, 15);
      expect(back.isCountdown, isTrue);
      expect(back.alertAt, at(2026, 10, 14, 8, 10));
    });
  });
}
