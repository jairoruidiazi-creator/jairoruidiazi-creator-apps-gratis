import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/core/notifications.dart';
import 'package:rutinas/core/settings.dart';
import 'package:rutinas/core/storage.dart';
import 'package:rutinas/logic/notice_plan.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/reminder.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/state/habit_store.dart';
import 'package:rutinas/state/notice_service.dart';
import 'package:rutinas/state/reminder_store.dart';
import 'package:rutinas/state/timer_store.dart';

/// "Ahora" en estas pruebas: miércoles 14 de octubre de 2026, 9:00.
final DateTime now = DateTime(2026, 10, 14, 9);

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

List<PlannedNotice> plan({List<Reminder> reminders = const <Reminder>[], List<Habit> habits = const <Habit>[], Map<String, Map<String, HabitEntry>> entries = const <String, Map<String, HabitEntry>>{}, TimerRun? run, int budget = 500, bool spanish = true}) {
  return NoticePlanner.build(now: now, reminders: reminders, habits: habits, entries: entries, weekStart: DateTime.monday, spanish: spanish, backgroundRun: run, budget: budget);
}

Reminder reminder(String id, DateTime due, {Recurrence rec = const Recurrence(), int nag = 0, int countdown = 0}) => Reminder(id: id, title: 'Recordatorio $id', dueAt: due, recurrence: rec, nagMinutes: nag, countdownSeconds: countdown, createdAt: now);

void main() {
  group('Recordatorios', () {
    test('un aviso a su hora; los hechos y los ya pasados sin insistencia no se programan', () {
      final Reminder done = reminder('b', at(14, 10))..doneAt = now;
      final List<PlannedNotice> p = plan(reminders: <Reminder>[reminder('a', at(14, 10)), done, reminder('c', at(14, 8))]);
      expect(p, hasLength(1));
      expect(p.single.when, at(14, 10));
      expect(p.single.title, 'Recordatorio a');
      expect(p.single.body, 'Para las 10:00');
      expect(p.single.route, 'reminder:a');
      expect(p.single.actions, NoticeActions.reminder);
      expect(p.single.channel, NoticeChannel.reminders);
    });

    test('la insistencia repite el aviso hasta 60 veces y cada uno reemplaza al anterior', () {
      final List<PlannedNotice> p = plan(reminders: <Reminder>[reminder('a', at(14, 10), nag: 5)]);
      expect(p.length, 61);
      expect(p[1].when, at(14, 10, 5));
      expect(p.last.when, at(14, 15));
      expect(p.first.timeoutMs, 5 * 60 * 1000);
      expect(p.last.timeoutMs, isNull);
      expect(p[1].body, contains('Sigue pendiente desde las 10:00'));
    });

    test('un recordatorio vencido sigue insistiendo desde ahora', () {
      final List<PlannedNotice> p = plan(reminders: <Reminder>[reminder('a', at(14, 8, 30), nag: 10)]);
      expect(p.first.when, at(14, 9, 10));
      expect(p.every((PlannedNotice n) => n.when.isAfter(now)), isTrue);
      expect(p.any((PlannedNotice n) => n.key.startsWith('r:')), isFalse);
    });

    test('los que se repiten programan sus próximas ocurrencias y la insistencia para antes de la siguiente', () {
      final List<PlannedNotice> p = plan(reminders: <Reminder>[reminder('a', at(14, 20), rec: const Recurrence(type: RecurrenceType.everyNDays), nag: 60)]);
      final List<PlannedNotice> mains = p.where((PlannedNotice n) => n.key.startsWith('r:')).toList();
      // Hoy y los 14 días siguientes (el horizonte).
      expect(mains.first.when, at(14, 20));
      expect(mains.length, 14);
      // Insiste cada hora hasta las 19:00 del día siguiente, no se cruza con la siguiente ocurrencia.
      final List<PlannedNotice> nagsToday = p.where((PlannedNotice n) => n.key.startsWith('n:') && n.when.isBefore(at(15, 20))).toList();
      expect(nagsToday.length, 23);
      expect(nagsToday.last.when, at(15, 19));
    });

    test('pospuesto: suena a la nueva hora', () {
      final Reminder r = reminder('a', at(14, 8))..snoozedUntil = at(14, 9, 30);
      final List<PlannedNotice> p = plan(reminders: <Reminder>[r]);
      expect(p.single.when, at(14, 9, 30));
    });

    test('cuenta regresiva: insiste cada minuto en su propio canal', () {
      final Reminder r = reminder('c', at(14, 9, 10), nag: 1, countdown: 600);
      final List<PlannedNotice> p = plan(reminders: <Reminder>[r]);
      expect(p.first.channel, NoticeChannel.countdowns);
      expect(p.first.body, 'Se cumplió la cuenta regresiva de 10 min.');
      expect(p[1].when, at(14, 9, 11));
      expect(p.length, 61);
    });
  });

  group('Hábitos', () {
    Habit water() => Habit(id: 'w', name: 'Agua', kind: HabitKind.count, goal: 8, unit: 'vasos', startDate: DateTime(2026, 10, 1), createdAt: DateTime(2026, 10, 1), reminders: <int>[20 * 60]);

    test('aviso diario mientras no esté hecho, con el avance en el texto', () {
      final List<PlannedNotice> p = plan(habits: <Habit>[water()], entries: <String, Map<String, HabitEntry>>{
        'w': <String, HabitEntry>{dayKey(now): HabitEntry(value: 3)},
      });
      expect(p.length, 8); // hoy y los 7 días siguientes
      expect(p.first.when, at(14, 20));
      expect(p.first.body, 'Llevas 3 de 8 vasos.');
      expect(p[1].body, 'Meta de hoy: 8 vasos.');
      expect(p.first.actions, NoticeActions.habitCount);
      expect(p.first.route, 'habit:w:2026-10-14');
    });

    test('hecho hoy: el aviso de hoy no se programa', () {
      final List<PlannedNotice> p = plan(habits: <Habit>[water()], entries: <String, Map<String, HabitEntry>>{
        'w': <String, HabitEntry>{dayKey(now): HabitEntry(value: 8)},
      });
      expect(p.first.when, at(15, 20));
    });

    test('insiste hasta medianoche; los días que no tocan no avisan', () {
      final Habit h = Habit(id: 'g', name: 'Gimnasio', startDate: DateTime(2026, 10, 1), createdAt: DateTime(2026, 10, 1), reminders: <int>[22 * 60], nagMinutes: 30, frequency: const Frequency(type: FrequencyType.weekdays, weekdays: <int>[3]));
      final List<PlannedNotice> p = plan(habits: <Habit>[h]);
      // Hoy es miércoles: 22:00, 22:30, 23:00 y 23:30; el próximo miércoles igual.
      expect(p.map((PlannedNotice n) => n.when).toList(), <DateTime>[at(14, 22), at(14, 22, 30), at(14, 23), at(14, 23, 30), at(21, 22), at(21, 22, 30), at(21, 23), at(21, 23, 30)]);
      expect(p.first.actions, NoticeActions.habitCheck);
    });

    test('archivados y sin horas de aviso no programan nada', () {
      final Habit a = water()..archived = true;
      final Habit b = water()..reminders = <int>[];
      expect(plan(habits: <Habit>[a, b]), isEmpty);
    });
  });

  group('Temporizador en segundo plano', () {
    TimerRun run() => TimerRun(
          kind: RunKind.workout,
          name: 'Tabata',
          segments: TimerEngine.flatten(<TimerNode>[
            RepeatBlock(repeats: 3, children: <TimerNode>[
              IntervalStep(name: 'Trabajo', seconds: 20),
              IntervalStep(name: 'Descanso', seconds: 10, kind: StepKind.rest),
            ]),
          ]),
          startedAt: now.subtract(const Duration(seconds: 5)),
        );

    test('un aviso con sonido por cada cambio de intervalo que falta y uno al final', () {
      final List<PlannedNotice> p = plan(run: run());
      expect(p.length, 5); // 4 cambios + final
      expect(p.first.when, now.add(const Duration(seconds: 15)));
      expect(p.first.title, 'Descanso');
      expect(p.first.body, '0:10 · ronda 1 de 3 · sigue: Trabajo');
      expect(p.first.channel, NoticeChannel.timerBell);
      expect(p.first.timeoutMs, 10000);
      expect(p[1].channel, NoticeChannel.timerBeep);
      expect(p.last.key, 'te');
      expect(p.last.title, '¡Terminaste!');
      expect(p.last.channel, NoticeChannel.timerGong);
      expect(p.last.when, now.add(const Duration(seconds: 75)));
    });

    test('en pausa no se programa nada', () {
      final TimerRun r = run()..pause(now);
      expect(plan(run: r), isEmpty);
    });

    test('si no caben todos, el último que cabe avisa que hay que abrir la app', () {
      final List<PlannedNotice> p = plan(run: run(), budget: 3);
      expect(p.length, 3);
      expect(p.last.body, contains('Abre Rutinas'));
      expect(p.first.body, isNot(contains('Abre Rutinas')));
    });

    test('se ordena por hora y el presupuesto deja lo más cercano', () {
      // Cambios a los 15, 25, 45, 55 y 75 s; el recordatorio, a los 50 s.
      final List<PlannedNotice> p = plan(run: run(), reminders: <Reminder>[reminder('a', now.add(const Duration(seconds: 50)))], budget: 4);
      expect(p.map((PlannedNotice n) => n.key).toList(), <String>['t:1', 't:2', 't:3', 'r:a:${now.add(const Duration(seconds: 50)).millisecondsSinceEpoch}']);
      expect(p[2].body, contains('Abre Rutinas'));
    });
  });

  group('Claves y números', () {
    test('la misma clave da siempre el mismo número', () {
      expect(noticeIdFor('r:a:1'), noticeIdFor('r:a:1'));
      expect(noticeIdFor('r:a:1'), isNot(noticeIdFor('r:a:2')));
      expect(noticeIdFor('x') > 0, isTrue);
      expect(stableHash('Rutinas'), stableHash('Rutinas'));
      expect(routeOfPayload('reminder:abc|123|456'), 'reminder:abc');
      expect(routeOfPayload(null), '');
    });
  });

  group('Servicio de avisos', () {
    late Directory tmp;
    late HabitStore habits;
    late ReminderStore reminders;
    late TimerStore timers;
    late FakeNotificationGateway gateway;
    late NoticeService service;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rutinas_avisos');
      final JsonStore store = JsonStore(root: tmp);
      habits = HabitStore(store)..load();
      reminders = ReminderStore(store)..load();
      timers = TimerStore(store)..load();
      gateway = FakeNotificationGateway();
      service = NoticeService(gateway: gateway, settings: AppSettings(), habits: habits, reminders: reminders, timers: timers);
    });

    tearDown(() async {
      service.dispose();
      await tmp.delete(recursive: true);
    });

    test('solo programa y cancela lo que cambió', () async {
      await withClock(Clock.fixed(now), () async {
        reminders.reminders.add(reminder('a', at(14, 10), nag: 30));
        await service.sync();
        final int first = gateway.scheduleCalls;
        expect(first, gateway.scheduled.length);
        expect(gateway.scheduled.values.every((PlannedNotice n) => n.route == 'reminder:a'), isTrue);
        // Sin cambios: no se vuelve a programar nada.
        await service.sync();
        expect(gateway.scheduleCalls, first);
        // Hecho: se cancelan todos sus avisos pendientes.
        reminders.reminders.single.doneAt = now;
        await service.sync();
        expect(gateway.scheduled, isEmpty);
        expect(gateway.cancelled.length, first);
      });
    });

    test('alarmas exactas solo si el permiso está concedido', () async {
      await withClock(Clock.fixed(now), () async {
        reminders.reminders.add(reminder('a', at(14, 10)));
        gateway.exactAllowed = false;
        await service.sync();
        expect(gateway.exactById.values.single, isFalse);
        gateway.exactAllowed = true;
        reminders.reminders.single.dueAt = at(14, 11);
        await service.sync();
        expect(gateway.exactById[gateway.scheduled.keys.single], isTrue);
      });
    });

    test('al volver a la app se quitan los avisos del temporizador', () async {
      await withClock(Clock.fixed(now), () async {
        timers.run = TimerRun(kind: RunKind.countdown, name: 'Té', segments: const <TimerSegment>[TimerSegment(name: 'Té', seconds: 300, kind: StepKind.work, color: 0xFF283593, sound: CueSound.none)], startedAt: now);
        service.background = true;
        await service.sync();
        expect(gateway.scheduled.values.single.key, 'te');
        final int id = gateway.scheduled.keys.single;
        service.background = false;
        await service.sync();
        expect(gateway.scheduled, isEmpty);
        expect(gateway.cancelled, contains(id));
      });
    });

    test('los toques en las notificaciones llegan al que los atiende, aunque llegue después', () async {
      final List<String> got = <String>[];
      await service.init();
      gateway.respond('reminder:a|1|2', 'done');
      expect(got, isEmpty);
      service.handler = (NoticeResponse r) => got.add('${r.route}/${r.actionId}');
      expect(got, <String>['reminder:a/done']);
      gateway.respond('timer|1|2');
      expect(got.last, 'timer/null');
    });
  });
}
