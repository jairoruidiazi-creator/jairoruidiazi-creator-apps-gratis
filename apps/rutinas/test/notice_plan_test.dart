import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/app_scope.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/core/notifications.dart';
import 'package:rutinas/core/settings.dart';
import 'package:rutinas/core/storage.dart';
import 'package:rutinas/logic/notice_plan.dart';
import 'package:rutinas/logic/templates.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/reminder.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/state/habit_store.dart';
import 'package:rutinas/state/notice_service.dart';
import 'package:rutinas/state/reminder_store.dart';
import 'package:rutinas/state/timer_store.dart';

import 'store/rutinas_demo.dart';
import 'support/app_harness.dart';

/// "Ahora" en estas pruebas: miércoles 14 de octubre de 2026, 9:00.
final DateTime now = DateTime(2026, 10, 14, 9);

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

/// Sin tope en la práctica: para comparar con lo que entra en el cupo real.
NoticeLimits roomy(int nagCap) => NoticeLimits(budget: 1000000, nagCap: nagCap, guaranteed: const Duration(days: 7));

NoticePlan build({
  DateTime? when,
  List<Reminder> reminders = const <Reminder>[],
  List<Habit> habits = const <Habit>[],
  Map<String, Map<String, HabitEntry>> entries = const <String, Map<String, HabitEntry>>{},
  TimerRun? run,
  NoticeLimits limits = kAndroidLimits,
  bool spanish = true,
  bool sounds = true,
  bool vibration = true,
}) {
  return NoticePlanner.build(now: when ?? now, reminders: reminders, habits: habits, entries: entries, weekStart: DateTime.monday, spanish: spanish, backgroundRun: run, limits: limits, sounds: sounds, vibration: vibration);
}

List<PlannedNotice> plan({List<Reminder> reminders = const <Reminder>[], List<Habit> habits = const <Habit>[], Map<String, Map<String, HabitEntry>> entries = const <String, Map<String, HabitEntry>>{}, TimerRun? run, NoticeLimits limits = kAndroidLimits}) {
  return build(reminders: reminders, habits: habits, entries: entries, run: run, limits: limits).notices;
}

Reminder reminder(String id, DateTime due, {Recurrence rec = const Recurrence(), int nag = 0, int countdown = 0}) => Reminder(id: id, title: 'Recordatorio $id', dueAt: due, recurrence: rec, nagMinutes: nag, countdownSeconds: countdown, createdAt: now);

/// Cada cadena de avisos de un mismo elemento se borra del panel al llegar el
/// siguiente; el último que de verdad se programa se queda (B1).
void expectTimeoutsChain(List<PlannedNotice> notices) {
  final Map<String, List<PlannedNotice>> chains = <String, List<PlannedNotice>>{};
  for (final PlannedNotice n in notices) {
    if (n.kind == NoticeKind.first || n.kind == NoticeKind.nag) {
      chains.putIfAbsent(n.element, () => <PlannedNotice>[]).add(n);
    }
  }
  for (final List<PlannedNotice> chain in chains.values) {
    chain.sort((PlannedNotice a, PlannedNotice b) => a.when.compareTo(b.when));
    for (int i = 0; i < chain.length; i++) {
      if (i + 1 == chain.length) {
        expect(chain[i].timeoutMs, isNull, reason: 'el último aviso de ${chain[i].element} no se borra solo');
      } else {
        expect(chain[i].timeoutMs, chain[i + 1].when.difference(chain[i].when).inMilliseconds);
      }
    }
  }
}

/// Usuario intenso: diez hábitos con tres avisos e insistencia y diez
/// recordatorios diarios que insisten cada 5 minutos.
final DateTime intenseNow = DateTime(2026, 10, 19, 6);
List<Habit> intenseHabits() => <Habit>[
      for (int i = 0; i < 10; i++) Habit(id: 'h$i', name: 'Hábito $i', startDate: DateTime(2026, 9, 1), createdAt: DateTime(2026, 9, 1), reminders: <int>[7 * 60 + i, 13 * 60 + i, 20 * 60 + i], nagMinutes: 15),
    ];
List<Reminder> intenseReminders() => <Reminder>[
      for (int i = 0; i < 10; i++) Reminder(id: 'r$i', title: 'Recordatorio $i', dueAt: DateTime(2026, 10, 19, 9 + i), recurrence: const Recurrence(type: RecurrenceType.everyNDays), nagMinutes: 5, createdAt: DateTime(2026, 9, 1)),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(p.single.occurrence, at(14, 10));
      expect(p.single.urgent, isTrue);
    });

    test('la insistencia de la ocurrencia más próxima tiene un tope por elemento', () {
      final List<PlannedNotice> android = plan(reminders: <Reminder>[reminder('a', at(14, 10), nag: 5)]);
      expect(android.length, 1 + kAndroidLimits.nagCap);
      expect(android[1].when, at(14, 10, 5));
      expect(android.last.when, at(14, 10).add(Duration(minutes: 5 * kAndroidLimits.nagCap)));
      expect(android.first.timeoutMs, 5 * 60 * 1000);
      expect(android.last.timeoutMs, isNull);
      expect(android[1].body, contains('Sigue pendiente desde las 10:00'));
      expect(android[1].kind, NoticeKind.nag);
      final List<PlannedNotice> ios = plan(reminders: <Reminder>[reminder('a', at(14, 10), nag: 5)], limits: kIosLimits);
      expect(ios.length, 1 + kIosLimits.nagCap);
      expect(ios.last.timeoutMs, isNull);
    });

    test('vencido: una sola solicitud que se repite hasta marcarlo hecho', () {
      final List<PlannedNotice> p = plan(reminders: <Reminder>[reminder('a', at(14, 8, 30), nag: 10)]);
      expect(p, hasLength(1));
      final PlannedNotice n = p.single;
      expect(n.kind, NoticeKind.repeating);
      expect(n.repeatEvery, const Duration(minutes: 10));
      expect(n.when, at(14, 9, 10));
      expect(n.timeoutMs, isNull);
      expect(n.occurrence, at(14, 8, 30));
      expect(n.body, 'Sigue pendiente desde el mié 14 oct a las 8:30. Toca Hecho si ya lo hiciste.');
      // La carga útil no depende de cuándo se programó.
      expect(n.payload(exact: true), contains('|cada600|'));
    });

    test('los que se repiten programan sus próximas ocurrencias y la insistencia para antes de la siguiente', () {
      final List<PlannedNotice> p = plan(reminders: <Reminder>[reminder('a', at(14, 20), rec: const Recurrence(type: RecurrenceType.everyNDays), nag: 60)]);
      final List<PlannedNotice> mains = p.where((PlannedNotice n) => n.key.startsWith('r:')).toList();
      // Hoy y los días siguientes hasta el horizonte de 14 días.
      expect(mains.first.when, at(14, 20));
      expect(mains.length, 14);
      // Insiste cada hora hasta las 19:00 del día siguiente, sin cruzarse con la siguiente ocurrencia.
      final List<PlannedNotice> nags = p.where((PlannedNotice n) => n.key.startsWith('n:')).toList();
      expect(nags.length, 23);
      expect(nags.last.when, at(15, 19));
      // Solo insiste la ocurrencia más próxima.
      expect(nags.every((PlannedNotice n) => n.occurrence == at(14, 20)), isTrue);
    });

    test('«la 1:30», no «las 1:30»', () {
      final List<PlannedNotice> p = plan(reminders: <Reminder>[reminder('a', at(15, 1, 30), nag: 5), reminder('b', at(15, 13, 30))]);
      expect(p.first.body, 'Para la 1:30');
      expect(p[1].body, 'Sigue pendiente desde la 1:30. Toca Hecho si ya lo hiciste.');
      expect(p.last.body, 'Para las 13:30');
      final List<PlannedNotice> overdue = build(when: at(15, 1, 45), reminders: <Reminder>[reminder('c', at(15, 1, 30), nag: 5)]).notices;
      expect(overdue.single.body, 'Sigue pendiente desde el jue 15 oct a la 1:30. Toca Hecho si ya lo hiciste.');
    });

    test('pospuesto: suena a la nueva hora', () {
      final Reminder r = reminder('a', at(14, 8))..snoozedUntil = at(14, 9, 30);
      final List<PlannedNotice> p = plan(reminders: <Reminder>[r]);
      expect(p.single.when, at(14, 9, 30));
      expect(p.single.occurrence, at(14, 8));
    });

    test('cuenta regresiva: insiste cada minuto en su propio canal', () {
      final Reminder r = reminder('c', at(14, 9, 10), nag: 1, countdown: 600);
      final List<PlannedNotice> p = plan(reminders: <Reminder>[r]);
      expect(p.first.channel, NoticeChannel.countdowns);
      expect(p.first.body, 'Se cumplió la cuenta regresiva de 10 min.');
      expect(p[1].when, at(14, 9, 11));
      expect(p[1].body, 'Sonando desde las 9:10. Toca Hecho para apagarla.');
      expect(p.length, 1 + kAndroidLimits.nagCap);
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
      expect(p.first.urgent, isFalse);
    });

    test('hecho o saltado hoy: el aviso de hoy no se programa', () {
      final List<PlannedNotice> p = plan(habits: <Habit>[water()], entries: <String, Map<String, HabitEntry>>{
        'w': <String, HabitEntry>{dayKey(now): HabitEntry(value: 8)},
      });
      expect(p.first.when, at(15, 20));
      final List<PlannedNotice> q = plan(habits: <Habit>[water()], entries: <String, Map<String, HabitEntry>>{
        'w': <String, HabitEntry>{dayKey(now): HabitEntry(skipped: true)},
      });
      expect(q.first.when, at(15, 20));
    });

    test('insiste hasta medianoche solo en la ocurrencia más próxima; los días que no tocan no avisan', () {
      final Habit h = Habit(id: 'g', name: 'Gimnasio', startDate: DateTime(2026, 10, 1), createdAt: DateTime(2026, 10, 1), reminders: <int>[22 * 60], nagMinutes: 30, frequency: const Frequency(type: FrequencyType.weekdays, weekdays: <int>[3]));
      final List<PlannedNotice> p = plan(habits: <Habit>[h]);
      // Hoy es miércoles: 22:00, 22:30, 23:00 y 23:30; el próximo miércoles solo el primer aviso.
      expect(p.map((PlannedNotice n) => n.when).toList(), <DateTime>[at(14, 22), at(14, 22, 30), at(14, 23), at(14, 23, 30), at(21, 22)]);
      expect(p.first.actions, NoticeActions.habitCheck);
      expect(p[1].kind, NoticeKind.nag);
      expect(p[1].occurrence, at(14, 22));
    });

    test('archivados y sin horas de aviso no programan nada', () {
      final Habit a = water()..archive(now);
      final Habit b = water()..reminders = <int>[];
      expect(plan(habits: <Habit>[a, b]), isEmpty);
    });
  });

  group('Cupo con los topes reales (B1)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rutinas_cupo');
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('demo de la tienda: en iOS cubre casi una semana y no pierde ningún primer aviso antes de ese momento', () {
      final DateTime demoNow = DateTime(2026, 10, 14, 18, 40);
      final Services s = testServices(tmp);
      seedRutinasDemo(s, spanish: true, now: demoNow);
      NoticePlan of(NoticeLimits limits) => build(when: demoNow, reminders: s.reminders.reminders, habits: s.habits.habits, entries: s.habits.entries, limits: limits);

      final NoticePlan ios = of(kIosLimits);
      final NoticePlan all = of(roomy(kIosLimits.nagCap));
      expect(ios.notices.length, lessThanOrEqualTo(kIosLimits.budget));
      final DateTime until = ios.coveredUntil!;
      // Casi seis días (hasta el martes siguiente a las 18:00).
      expect(until.isAfter(demoNow.add(const Duration(days: 5, hours: 12))), isTrue, reason: 'cubre hasta $until');
      final Set<String> keys = ios.notices.map((PlannedNotice n) => n.key).toSet();
      final List<PlannedNotice> firsts = all.notices.where((PlannedNotice n) => n.kind == NoticeKind.first && n.when.isBefore(until)).toList();
      // Antes se perdían 56 de 59 primeros avisos (lo último programado era de las 19:38 del mismo día).
      expect(firsts.length, greaterThanOrEqualTo(40));
      for (final PlannedNotice n in firsts) {
        expect(keys, contains(n.key), reason: '${n.title} ${n.when}');
      }
      // «Leer 20 páginas» hoy a las 21:00 y «Meditar» mañana a las 7:00.
      expect(keys, contains('h:leer:${DateTime(2026, 10, 14, 21).millisecondsSinceEpoch}'));
      expect(keys, contains('h:meditar:${DateTime(2026, 10, 15, 7).millisecondsSinceEpoch}'));
      // El aviso honesto suena a la hora del primero que no cupo, y nada va después.
      final PlannedNotice cov = ios.notices.singleWhere((PlannedNotice n) => n.kind == NoticeKind.coverage);
      expect(cov.when, until);
      expect(cov.body, 'Abre Rutinas para que este y tus próximos avisos sigan llegando.');
      expect(ios.notices.every((PlannedNotice n) => !n.when.isAfter(until)), isTrue);
      // La insistencia de lo más próximo sigue ahí.
      expect(ios.notices.any((PlannedNotice n) => n.kind == NoticeKind.nag || n.kind == NoticeKind.repeating), isTrue);
      expectTimeoutsChain(ios.notices);

      // Android: todo el horizonte cabe.
      final NoticePlan android = of(kAndroidLimits);
      expect(android.coveredUntil, isNull);
      expect(android.notices.length, of(roomy(kAndroidLimits.nagCap)).notices.length);
      expect(android.notices.length, lessThanOrEqualTo(kAndroidLimits.budget));
      expectTimeoutsChain(android.notices);
      s.dispose();
    });

    test('usuario típico: un hábito que insiste no deja sin avisos los días siguientes', () {
      // Lunes 19 a las 22:00, con todo hecho hoy.
      final DateTime monday = DateTime(2026, 10, 19, 22);
      final List<Habit> habits = <Habit>[
        Habit(id: 'med', name: 'Meditar', kind: HabitKind.timed, goal: 600, startDate: DateTime(2026, 9, 1), createdAt: DateTime(2026, 9, 1), reminders: <int>[7 * 60], nagMinutes: 15),
        Habit(id: 'leer', name: 'Leer', startDate: DateTime(2026, 9, 1), createdAt: DateTime(2026, 9, 1), reminders: <int>[21 * 60]),
      ];
      final Map<String, Map<String, HabitEntry>> entries = <String, Map<String, HabitEntry>>{
        'med': <String, HabitEntry>{dayKey(monday): HabitEntry(value: 600)},
        'leer': <String, HabitEntry>{dayKey(monday): HabitEntry(value: 1)},
      };
      final List<Reminder> reminders = <Reminder>[Reminder(id: 'vit', title: 'Vitamina', dueAt: DateTime(2026, 10, 20, 8), recurrence: const Recurrence(type: RecurrenceType.everyNDays), createdAt: DateTime(2026, 9, 1))];
      for (final NoticeLimits limits in <NoticeLimits>[kIosLimits, kAndroidLimits]) {
        final NoticePlan p = build(when: monday, reminders: reminders, habits: habits, entries: entries, limits: limits);
        expect(p.coveredUntil, isNull);
        // Meditar y Leer todos los días de la semana que viene, no solo mañana.
        for (int d = 20; d <= 26; d++) {
          expect(p.notices.where((PlannedNotice n) => n.kind == NoticeKind.first && n.route.startsWith('habit:') && n.when.day == d).length, 2, reason: 'día $d');
        }
        expect(p.notices.where((PlannedNotice n) => n.route == 'reminder:vit' && n.kind == NoticeKind.first).length, 14);
        expect(p.notices.where((PlannedNotice n) => n.kind == NoticeKind.nag).length, limits.nagCap);
      }
    });

    test('uso intenso: lo que cabe va sin huecos y termina con el aviso honesto', () {
      for (final NoticeLimits limits in <NoticeLimits>[kIosLimits, kAndroidLimits]) {
        final NoticePlan p = build(when: intenseNow, reminders: intenseReminders(), habits: intenseHabits(), limits: limits);
        final NoticePlan all = build(when: intenseNow, reminders: intenseReminders(), habits: intenseHabits(), limits: roomy(limits.nagCap));
        expect(p.notices.length, lessThanOrEqualTo(limits.budget));
        final DateTime until = p.coveredUntil!;
        expect(until.isAfter(intenseNow.add(Duration(days: limits == kIosLimits ? 1 : 5))), isTrue, reason: 'cubre hasta $until');
        final Set<String> keys = p.notices.map((PlannedNotice n) => n.key).toSet();
        for (final PlannedNotice n in all.notices.where((PlannedNotice n) => n.kind == NoticeKind.first && n.when.isBefore(until))) {
          expect(keys, contains(n.key));
        }
        expect(p.notices.last.kind, NoticeKind.coverage);
        expectTimeoutsChain(p.notices);
      }
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
      expect(p.first.urgent, isTrue);
      expect(p[1].channel, NoticeChannel.timerBeep);
      expect(p.last.key, 'te');
      expect(p.last.title, '¡Terminaste!');
      expect(p.last.channel, NoticeChannel.timerGong);
      expect(p.last.when, now.add(const Duration(seconds: 75)));
      expect(p.last.timeoutMs, isNull);
    });

    test('sonidos o vibración apagados en Ajustes también con la pantalla apagada (M2)', () {
      final List<PlannedNotice> mute = build(run: run(), sounds: false).notices;
      expect(mute.every((PlannedNotice n) => n.channel == NoticeChannel.timerVibrate), isTrue);
      final List<PlannedNotice> still = build(run: run(), vibration: false).notices;
      expect(still.first.channel, NoticeChannel.timerBellNoVibration);
      expect(still[1].channel, NoticeChannel.timerBeepNoVibration);
      final List<PlannedNotice> none = build(run: run(), sounds: false, vibration: false).notices;
      expect(none.every((PlannedNotice n) => n.channel == NoticeChannel.timerSilent), isTrue);
      expect(timerChannelFor(CueSound.none), NoticeChannel.timerVibrate);
    });

    test('en pausa no se programa nada', () {
      final TimerRun r = run()..pause(now);
      expect(plan(run: r), isEmpty);
    });

    test('si no caben todos, el último que cabe avisa que hay que abrir la app', () {
      final NoticePlan p = build(run: run(), limits: const NoticeLimits(budget: 3, nagCap: 6, guaranteed: Duration(days: 3)));
      expect(p.notices.length, 2);
      expect(p.notices.last.body, contains('Abre Rutinas'));
      expect(p.notices.first.body, isNot(contains('Abre Rutinas')));
      expect(p.timerLastCovered, 2);
      // El último no se borra solo.
      expect(p.notices.last.timeoutMs, isNull);
    });

    test('el Tabata no cabe en iOS: se sabe hasta qué intervalo llegan los avisos (G6)', () {
      final Workout tabata = WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: true, now: now);
      final List<TimerSegment> segments = TimerEngine.flatten(tabata.nodes);
      expect(segments.length, greaterThan(kIosLimits.timerCapacity));
      final TimerRun r = TimerRun(kind: RunKind.workout, name: tabata.name, segments: segments, startedAt: now);
      final NoticePlan ios = build(run: r, limits: kIosLimits, reminders: <Reminder>[reminder('a', at(14, 10))]);
      expect(ios.timerLastCovered, kIosLimits.timerCapacity);
      expect(ios.notices.where((PlannedNotice n) => n.isTimer).length, kIosLimits.timerCapacity);
      expect(ios.notices.lastWhere((PlannedNotice n) => n.isTimer).body, contains('Abre Rutinas'));
      expect(ios.notices.length, lessThanOrEqualTo(kIosLimits.budget));
      // En Android cabe entero.
      final NoticePlan android = build(run: r, limits: kAndroidLimits);
      expect(android.timerLastCovered, isNull);
      expect(android.notices.length, segments.length);
    });

    test('los cambios del temporizador van primero en el cupo', () {
      // Cambios a los 15, 25, 45, 55 y 75 s; el recordatorio, a los 50 s.
      final List<PlannedNotice> p = plan(run: run(), reminders: <Reminder>[reminder('a', now.add(const Duration(seconds: 50)))], limits: const NoticeLimits(budget: 4, nagCap: 6, guaranteed: Duration(days: 3)));
      expect(p.map((PlannedNotice n) => n.key).toList(), <String>['t:1', 't:2', 't:3', 'r:a:${now.add(const Duration(seconds: 50)).millisecondsSinceEpoch}']);
      expect(p[2].body, contains('Abre Rutinas'));
    });
  });

  group('Claves y cargas útiles', () {
    test('la misma clave da siempre el mismo número', () {
      expect(noticeIdFor('r:a:1'), noticeIdFor('r:a:1'));
      expect(noticeIdFor('r:a:1'), isNot(noticeIdFor('r:a:2')));
      expect(noticeIdFor('x') > 0, isTrue);
      expect(stableHash('Rutinas'), stableHash('Rutinas'));
      expect(routeOfPayload('reminder:abc|123|456'), 'reminder:abc');
      expect(routeOfPayload(null), '');
    });

    test('la carga útil lleva la ocurrencia y si es una alarma exacta (G3, G7)', () {
      final PlannedNotice n = plan(reminders: <Reminder>[reminder('a', at(14, 10))]).single;
      final String exact = n.payload(exact: true);
      expect(NoticePayload.parse(exact).route, 'reminder:a');
      expect(NoticePayload.parse(exact).occurrence, at(14, 10));
      expect(NoticeResponse(exact, 'done').occurrence, at(14, 10));
      expect(exact, isNot(n.payload(exact: false)));
      expect(exact, n.payload(exact: true));
      expect(NoticePayload.parse('timer').occurrence, isNull);
    });
  });

  group('Servicio de avisos', () {
    late Directory tmp;
    late JsonStore store;
    late AppSettings settings;
    late HabitStore habits;
    late ReminderStore reminders;
    late TimerStore timers;
    late FakeNotificationGateway gateway;
    late NoticeService service;

    NoticeService make(FakeNotificationGateway g) => NoticeService(gateway: g, settings: settings, habits: habits, reminders: reminders, timers: timers, store: store);

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rutinas_avisos');
      store = JsonStore(root: tmp);
      settings = AppSettings();
      habits = HabitStore(store)..load();
      reminders = ReminderStore(store)..load();
      timers = TimerStore(store)..load();
      gateway = FakeNotificationGateway();
      service = make(gateway);
    });

    tearDown(() async {
      service.dispose();
      await tmp.delete(recursive: true);
    });

    test('iOS: solo programa y cancela lo que cambió', () async {
      await withClock(Clock.fixed(now), () async {
        final FakeNotificationGateway ios = FakeNotificationGateway(ios: true);
        final NoticeService s = make(ios);
        reminders.reminders.add(reminder('a', at(14, 10), nag: 30));
        await s.sync();
        final int first = ios.scheduleCalls;
        expect(first, ios.scheduled.length);
        expect(first, 1 + kIosLimits.nagCap);
        expect(ios.scheduled.values.every((PlannedNotice n) => n.route == 'reminder:a'), isTrue);
        // Sin cambios: no se vuelve a programar nada.
        await s.sync();
        expect(ios.scheduleCalls, first);
        expect(ios.cancelAllCalls, 0);
        // Hecho: se cancelan todos sus avisos pendientes.
        reminders.reminders.single.doneAt = now;
        await s.sync();
        expect(ios.scheduled, isEmpty);
        expect(ios.cancelled.length, first);
        s.dispose();
      });
    });

    test('Android: tras forzar la detención, al abrir la app se vuelve a programar todo (B2)', () async {
      await withClock(Clock.fixed(now), () async {
        reminders.reminders.add(reminder('a', at(14, 10), nag: 30));
        reminders.reminders.add(reminder('b', at(16, 18)));
        await service.sync();
        final int n = gateway.scheduled.length;
        expect(n, greaterThan(2));
        // En el mismo proceso y sin cambios no se toca nada.
        final int calls = gateway.scheduleCalls;
        await service.sync();
        expect(gateway.scheduleCalls, calls);
        // El sistema borra las alarmas; la lista del plugin sigue igual.
        gateway.forceStop();
        expect(gateway.scheduled, isEmpty);
        expect(gateway.cache, hasLength(n));
        // La app se vuelve a abrir (proceso nuevo): no le cree a esa lista.
        final NoticeService again = make(gateway);
        expect(again.pendingFullResync, isTrue);
        await again.sync();
        expect(gateway.scheduled, hasLength(n));
        expect(again.pendingFullResync, isFalse);
        again.dispose();
      });
    });

    test('reprogramar todo: primero se programa y después se cancela lo que sobra (M1)', () async {
      await withClock(Clock.fixed(now), () async {
        reminders.reminders.add(reminder('a', at(14, 10), nag: 30));
        reminders.reminders.add(reminder('b', at(16, 18)));
        await service.sync();
        // b se borra mientras la app está cerrada; el proceso nuevo no le cree a la caché.
        reminders.reminders.removeWhere((Reminder r) => r.id == 'b');
        gateway.ops.clear();
        final NoticeService again = make(gateway);
        await again.sync();
        final int lastSchedule = gateway.ops.lastIndexWhere((String o) => o.startsWith('programar:'));
        final int firstCancel = gateway.ops.indexWhere((String o) => o.startsWith('cancelar:'));
        expect(firstCancel, greaterThan(lastSchedule));
        expect(gateway.cancelAllCalls, 0);
        expect(gateway.scheduled.values.every((PlannedNotice n) => n.route == 'reminder:a'), isTrue);
        expect(gateway.cache.length, gateway.scheduled.length);
        again.dispose();
      });
    });

    test('iOS: al aplicar diferencias se cancela antes de programar y nunca se pasa del cupo (M1)', () async {
      DateTime t = intenseNow;
      await withClock(Clock(() => t), () async {
        final FakeNotificationGateway ios = FakeNotificationGateway(ios: true);
        final NoticeService s = make(ios);
        reminders.reminders.addAll(intenseReminders());
        habits.habits.addAll(intenseHabits());
        // Un Tabata en marcha con la pantalla bloqueada: sus cambios llenan el cupo.
        final Workout tabata = WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: true, now: t);
        timers.run = TimerRun(kind: RunKind.workout, name: tabata.name, segments: TimerEngine.flatten(tabata.nodes), startedAt: t);
        s.background = true;
        await s.sync();
        expect(ios.scheduled.values.where((PlannedNotice n) => n.isTimer).length, kIosLimits.timerCapacity);
        // De vuelta en la app: salen los del temporizador y entran los recordatorios.
        t = t.add(const Duration(seconds: 30));
        timers.run = null;
        s.background = false;
        ios.ops.clear();
        await s.sync();
        final int lastCancel = ios.ops.lastIndexWhere((String o) => o.startsWith('cancelar:'));
        final int firstSchedule = ios.ops.indexWhere((String o) => o.startsWith('programar:'));
        expect(lastCancel, lessThan(firstSchedule));
        expect(ios.peak, lessThanOrEqualTo(kIosLimits.budget));
        expect(ios.scheduled.values.where((PlannedNotice n) => n.isTimer), isEmpty);
        s.dispose();
      });
    });

    test('iOS: restaurar una copia no pasa nunca del cupo de pendientes (N1)', () async {
      await withClock(Clock.fixed(intenseNow), () async {
        final FakeNotificationGateway ios = FakeNotificationGateway(ios: true);
        final NoticeService s = make(ios);
        reminders.reminders.addAll(intenseReminders());
        habits.habits.addAll(intenseHabits());
        await s.sync();
        expect(ios.scheduled.length, kIosLimits.budget);
        // La copia trae otros datos: el plan nuevo no comparte números con el viejo.
        reminders.reminders
          ..clear()
          ..addAll(<Reminder>[
            for (int i = 0; i < 10; i++) Reminder(id: 'copia$i', title: 'De la copia $i', dueAt: DateTime(2026, 10, 19, 9 + i), recurrence: const Recurrence(type: RecurrenceType.everyNDays), nagMinutes: 5, createdAt: DateTime(2026, 9, 1)),
          ]);
        habits.habits.clear();
        ios.peak = 0;
        ios.ops.clear();
        await s.afterRestore();
        expect(ios.peak, lessThanOrEqualTo(kIosLimits.budget));
        expect(ios.scheduled.length, lessThanOrEqualTo(kIosLimits.budget));
        expect(ios.scheduled.values.every((PlannedNotice n) => n.route.startsWith('reminder:copia') || n.kind == NoticeKind.coverage), isTrue);
        final int lastCancel = ios.ops.lastIndexWhere((String o) => o.startsWith('cancelar:'));
        final int firstSchedule = ios.ops.indexWhere((String o) => o.startsWith('programar:'));
        expect(lastCancel, lessThan(firstSchedule));
        s.dispose();
      });
    });

    test('Android: una copia restaurada en otro teléfono trae la lista del plugin pero no las alarmas (B2)', () async {
      await withClock(Clock.fixed(now), () async {
        reminders.reminders.add(reminder('a', at(14, 10), nag: 30));
        await service.sync();
        final Map<int, String> restored = Map<int, String>.of(gateway.cache);
        // Teléfono nuevo: la lista del plugin llegó con la copia de Google; las alarmas, no.
        final FakeNotificationGateway fresh = FakeNotificationGateway();
        fresh.cache.addAll(restored);
        final NoticeService other = make(fresh);
        await other.sync();
        expect(fresh.scheduled.keys.toSet(), restored.keys.toSet());
        other.dispose();
        // Restaurar una copia desde Ajustes también lo vuelve a programar todo.
        gateway.forceStop();
        await service.afterRestore();
        expect(gateway.scheduled.keys.toSet(), restored.keys.toSet());
      });
    });

    test('al conceder las alarmas exactas, lo ya programado pasa a ser exacto (G7)', () async {
      await withClock(Clock.fixed(now), () async {
        reminders.reminders.add(reminder('a', at(14, 10), nag: 30));
        reminders.reminders.add(reminder('b', at(16, 18)));
        gateway.exactAllowed = false;
        await service.sync();
        expect(gateway.scheduled, isNotEmpty);
        expect(gateway.scheduled.keys.every((int id) => gateway.exactById[id] == false), isTrue);
        // Se concede en Configuración y se vuelve a la app (sin tocar ningún recordatorio).
        gateway.exactAllowed = true;
        await service.resumed();
        expect(gateway.scheduled.keys.every((int id) => gateway.exactById[id] == true), isTrue);
        // Y si se quita, vuelven a ser inexactas.
        gateway.exactAllowed = false;
        await service.resumed();
        expect(gateway.scheduled.keys.every((int id) => gateway.exactById[id] == false), isTrue);
      });
    });

    test('al cambiar el idioma, canales, botones y textos pasan al nuevo (M3)', () async {
      await withClock(Clock.fixed(now), () async {
        reminders.reminders.add(reminder('a', at(14, 10)));
        await service.init();
        await service.sync();
        expect(gateway.scheduled.values.single.body, 'Para las 10:00');
        settings.language = 'en';
        await service.languageChanged();
        expect(gateway.languages.last, isFalse);
        expect(gateway.scheduled.values.single.body, 'Due at 10:00 AM');
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

    test('con la app abierta, al sonar el primer aviso la insistencia pasa a una sola solicitud que se repite (B1)', () async {
      DateTime t = now;
      await withClock(Clock(() => t), () async {
        reminders.reminders.add(reminder('a', at(14, 9, 5), nag: 5));
        await service.sync();
        expect(gateway.scheduled.values.where((PlannedNotice n) => n.kind == NoticeKind.nag).length, kAndroidLimits.nagCap);
        t = at(14, 9, 6);
        gateway.deliver(t);
        await service.sync();
        final List<PlannedNotice> left = gateway.scheduled.values.where((PlannedNotice n) => n.route == 'reminder:a').toList();
        expect(left, hasLength(1));
        expect(left.single.kind, NoticeKind.repeating);
        expect(left.single.repeatEvery, const Duration(minutes: 5));
        // Al marcarlo hecho se cancela y sale del panel.
        reminders.complete('a');
        await service.dismissReminder(reminders.byId('a')!);
        await service.sync();
        expect(gateway.scheduled.values.where((PlannedNotice n) => n.route == 'reminder:a'), isEmpty);
        expect(gateway.shown, isEmpty);
      });
    });

    test('al marcarlo hecho se quitan del panel también los avisos de días anteriores (G3)', () async {
      DateTime t = DateTime(2026, 10, 12, 7);
      // En iOS los avisos no se borran solos (en Android, cada uno se va al
      // llegar el siguiente con `timeoutAfter`).
      final FakeNotificationGateway gateway = FakeNotificationGateway(ios: true);
      final NoticeService service = make(gateway);
      addTearDown(service.dispose);
      await withClock(Clock(() => t), () async {
        reminders.reminders.add(Reminder(id: 'p', title: 'Pastilla', dueAt: DateTime(2026, 10, 12, 8), recurrence: const Recurrence(type: RecurrenceType.everyNDays), createdAt: t));
        await service.sync();
        // Lunes: suena y no se le hace caso.
        t = DateTime(2026, 10, 12, 9);
        gateway.deliver(t);
        // Martes: vuelve a sonar; la app no se abrió en medio.
        t = DateTime(2026, 10, 13, 9);
        gateway.deliver(t);
        expect(gateway.shown, hasLength(2));
        reminders.rollOverAll();
        await service.sync();
        // Se marca hecho desde la app: fuera los dos avisos.
        reminders.complete('p');
        await service.dismissReminder(reminders.byId('p')!);
        expect(gateway.shown, isEmpty);
      });
    });

    test('si no cabe todo, el sistema guarda el aviso honesto y la app sabe hasta cuándo (B1)', () async {
      await withClock(Clock.fixed(intenseNow), () async {
        final FakeNotificationGateway ios = FakeNotificationGateway(ios: true);
        final NoticeService s = make(ios);
        reminders.reminders.addAll(intenseReminders());
        habits.habits.addAll(intenseHabits());
        await s.sync();
        expect(ios.scheduled.length, lessThanOrEqualTo(kIosLimits.budget));
        expect(s.coveredUntil, isNotNull);
        expect(ios.scheduled.values.where((PlannedNotice n) => n.kind == NoticeKind.coverage), hasLength(1));
        s.dispose();
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
