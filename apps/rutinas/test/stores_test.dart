import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/backup.dart';
import 'package:rutinas/core/settings.dart';
import 'package:rutinas/core/storage.dart';
import 'package:rutinas/logic/templates.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/reminder.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/state/habit_store.dart';
import 'package:rutinas/state/reminder_store.dart';
import 'package:rutinas/state/timer_store.dart';

final DateTime now = DateTime(2026, 10, 14, 9);
final DateTime today = DateTime(2026, 10, 14);

/// Los tres almacenes sobre una carpeta temporal.
class Stores {
  Stores(this.dir) : store = JsonStore(root: dir) {
    habits = HabitStore(store)..load();
    reminders = ReminderStore(store)..load();
    timers = TimerStore(store)..load();
  }

  final Directory dir;
  final JsonStore store;
  late final HabitStore habits;
  late final ReminderStore reminders;
  late final TimerStore timers;

  void flush() {
    habits.flush();
    reminders.flush();
    timers.flush();
  }

  void dispose() {
    habits.dispose();
    reminders.dispose();
    timers.dispose();
  }

  File file(String name) => File('${dir.path}${Platform.pathSeparator}rutinas${Platform.pathSeparator}$name');
}

Habit water() => Habit(id: 'agua', name: 'Agua', kind: HabitKind.count, goal: 8, unit: 'vasos', startDate: DateTime(2026, 10, 1), createdAt: DateTime(2026, 10, 1), reminders: <int>[9 * 60, 15 * 60]);

void main() {
  late Directory tmp;
  final List<Stores> opened = <Stores>[];

  Stores open([String sub = 'a']) {
    final Stores s = Stores(Directory('${tmp.path}${Platform.pathSeparator}$sub'));
    opened.add(s);
    return s;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rutinas_stores');
  });

  tearDown(() async {
    for (final Stores s in opened) {
      s.dispose();
    }
    opened.clear();
    await tmp.delete(recursive: true);
  });

  group('Hábitos', () {
    test('registros por día: se suman, se saltan, llevan nota y se limpian solos', () {
      withClock(Clock.fixed(now), () {
        final Stores s = open();
        s.habits.add(water());
        s.habits.addValue('agua', today, 3);
        s.habits.addValue('agua', today, 2);
        expect(s.habits.entry('agua', today)!.value, 5);
        s.habits.setNote('agua', today, '  Con limón  ');
        expect(s.habits.entry('agua', today)!.note, 'Con limón');
        // Saltar un día no borra lo que tenga; anotar algo quita el salto.
        final DateTime yesterday = DateTime(2026, 10, 13);
        s.habits.setSkipped('agua', yesterday, true);
        expect(s.habits.entry('agua', yesterday)!.skipped, isTrue);
        s.habits.addValue('agua', yesterday, 1);
        expect(s.habits.entry('agua', yesterday)!.skipped, isFalse);
        // Un registro que queda vacío desaparece.
        s.habits.setValue('agua', yesterday, 0);
        expect(s.habits.entry('agua', yesterday), isNull);
        s.habits.setDay('agua', today, value: 8, skipped: false, note: '');
        expect(s.habits.entry('agua', today)!.value, 8);
        expect(s.habits.entry('agua', today)!.note, '');
        // Nunca por debajo de cero.
        s.habits.addValue('agua', today, -20);
        expect(s.habits.entry('agua', today), isNull);
      });
    });

    test('marcar y desmarcar un hábito de sí o no', () {
      withClock(Clock.fixed(now), () {
        final Stores s = open();
        s.habits.add(Habit(id: 'leer', name: 'Leer', startDate: today, createdAt: now));
        s.habits.toggleDone('leer', today);
        expect(s.habits.entry('leer', today)!.value, 1);
        s.habits.toggleDone('leer', today);
        expect(s.habits.entry('leer', today), isNull);
      });
    });

    test('orden, archivo y borrado', () {
      withClock(Clock.fixed(now), () {
        final Stores s = open();
        for (final String id in <String>['a', 'b', 'c']) {
          s.habits.add(Habit(id: id, name: id.toUpperCase(), startDate: today, createdAt: now));
        }
        expect(s.habits.active.map((Habit h) => h.id), <String>['a', 'b', 'c']);
        s.habits.move('c', -1);
        expect(s.habits.active.map((Habit h) => h.id), <String>['a', 'c', 'b']);
        s.habits.move('a', -1); // ya es el primero
        expect(s.habits.active.first.id, 'a');
        s.habits.setArchived('a', true);
        expect(s.habits.active.map((Habit h) => h.id), <String>['c', 'b']);
        expect(s.habits.archived.single.id, 'a');
        // Al recuperarlo vuelve al final.
        s.habits.setArchived('a', false);
        expect(s.habits.active.last.id, 'a');
        s.habits.toggleDone('b', today);
        s.habits.remove('b');
        expect(s.habits.byId('b'), isNull);
        expect(s.habits.entries.containsKey('b'), isFalse);
      });
    });

    test('se guardan en disco y se vuelven a leer igual', () {
      withClock(Clock.fixed(now), () {
        final Stores s = open();
        final Habit h = water()
          ..frequency = const Frequency(type: FrequencyType.weekdays, weekdays: <int>[1, 3, 5])
          ..nagMinutes = 15
          ..notes = 'Antes de las comidas';
        s.habits.add(h);
        s.habits.setValue('agua', today, 6);
        s.habits.setNote('agua', today, 'Hacía calor');
        expect(s.habits.dirty, isTrue);
        s.habits.flush();
        expect(s.habits.dirty, isFalse);
        final Stores again = open();
        final Habit back = again.habits.byId('agua')!;
        expect(back.frequency, h.frequency);
        expect(back.reminders, <int>[9 * 60, 15 * 60]);
        expect(back.nagMinutes, 15);
        expect(back.notes, 'Antes de las comidas');
        expect(again.habits.entry('agua', today)!.value, 6);
        expect(again.habits.entry('agua', today)!.note, 'Hacía calor');
      });
    });

    test('un archivo dañado se aparta y no se sobrescribe', () {
      withClock(Clock.fixed(now), () {
        final Stores first = open();
        first.habits.add(water());
        first.flush();
        first.file('habits.json').writeAsStringSync('{"habits": [ {"id": "agua", "name": "Ag');
        final Stores s = open();
        expect(s.habits.habits, isEmpty);
        expect(s.habits.damagedCopy, isNotNull);
        expect(File(s.habits.damagedCopy!).readAsStringSync(), startsWith('{"habits"'));
        expect(s.file('habits.json').existsSync(), isFalse);
        // Lo nuevo se guarda aparte; la copia dañada sigue ahí.
        s.habits.add(water());
        s.habits.flush();
        expect(File(s.habits.damagedCopy!).existsSync(), isTrue);
        expect(s.file('habits.json').existsSync(), isTrue);
      });
    });
  });

  group('Recordatorios', () {
    test('cuenta regresiva rápida: hecho, repetir y limpiar', () {
      withClock(Clock.fixed(now), () {
        final Stores s = open();
        final Reminder r = s.reminders.addCountdown(seconds: 600, title: 'Horno', nagMinutes: 1);
        expect(r.dueAt, now.add(const Duration(minutes: 10)));
        expect(r.isCountdown, isTrue);
        final Map<String, dynamic>? before = s.reminders.complete(r.id);
        expect(r.done, isTrue);
        expect(s.reminders.completed.single.id, r.id);
        // Deshacer deja todo como estaba.
        s.reminders.restore(before!);
        expect(s.reminders.byId(r.id)!.done, isFalse);
        s.reminders.complete(r.id);
        s.reminders.restartCountdown(r.id);
        expect(s.reminders.byId(r.id)!.done, isFalse);
        expect(s.reminders.byId(r.id)!.dueAt, now.add(const Duration(minutes: 10)));
        s.reminders.complete(r.id);
        expect(s.reminders.clearCompleted(), 1);
        expect(s.reminders.reminders, isEmpty);
      });
    });

    test('posponer, volver a abrir y pasar a la ocurrencia que toca', () {
      withClock(Clock.fixed(now), () {
        final Stores s = open();
        s.reminders.add(Reminder(id: 'a', title: 'Pastilla', dueAt: DateTime(2026, 10, 14, 8), createdAt: now));
        s.reminders.add(Reminder(id: 'b', title: 'Regar', dueAt: DateTime(2026, 10, 10, 18), recurrence: const Recurrence(type: RecurrenceType.everyNDays, n: 2), createdAt: now));
        s.reminders.snooze('a', 15);
        expect(s.reminders.byId('a')!.alertAt, now.add(const Duration(minutes: 15)));
        expect(s.reminders.pending.first.id, 'b');
        s.reminders.complete('a');
        s.reminders.reopen('a');
        expect(s.reminders.byId('a')!.done, isFalse);
        // 10, 12, 14 (hoy a las 18 todavía no llega): queda en la del 12.
        expect(s.reminders.rollOverAll(), isTrue);
        expect(s.reminders.byId('b')!.dueAt, DateTime(2026, 10, 12, 18));
        expect(s.reminders.rollOverAll(), isFalse);
        s.flush();
        final Stores again = open();
        expect(again.reminders.byId('b')!.recurrence.n, 2);
        expect(again.reminders.byId('b')!.dueAt, DateTime(2026, 10, 12, 18));
      });
    });
  });

  group('Temporizador', () {
    test('entrenamientos, cuentas atrás guardadas e historial', () {
      withClock(Clock.fixed(now), () {
        final Stores s = open();
        final Workout tabata = WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: true, now: now);
        final Workout hiit = WorkoutTemplates.create(WorkoutTemplate.hiit, spanish: true, now: now);
        s.timers.addWorkout(tabata);
        s.timers.addWorkout(hiit);
        expect(s.timers.sortedWorkouts.map((Workout w) => w.id), <String>[tabata.id, hiit.id]);
        s.timers.addPreset(CountdownPreset(id: 'p1', name: 'Siesta', seconds: 1200));
        s.timers.addPreset(CountdownPreset(id: 'p2', name: 'Té', seconds: 240));
        expect(s.timers.presets.map((CountdownPreset p) => p.name), <String>['Té', 'Siesta']);
        s.timers.addSession(WorkoutSession(id: 'x', workoutId: tabata.id, name: tabata.name, startedAt: now, endedAt: now.add(const Duration(minutes: 18)), activeSeconds: 1110, completed: true));
        s.timers.run = TimerRun(kind: RunKind.workout, refId: hiit.id, name: hiit.name, segments: TimerEngine.flatten(hiit.nodes), startedAt: now, pausedMs: 2000);
        s.timers.stopwatch.start(now);
        s.timers.changed();
        s.flush();
        final Stores again = open();
        expect(again.timers.workouts, hasLength(2));
        expect(TimerEngine.totalSeconds(TimerEngine.flatten(again.timers.workoutById(tabata.id)!.nodes)), 1110);
        expect(again.timers.presets.first.seconds, 240);
        expect(again.timers.sessions.single.activeSeconds, 1110);
        expect(again.timers.run!.pausedMs, 2000);
        expect(again.timers.run!.segments.length, 22);
        expect(again.timers.stopwatch.running, isTrue);
        // La copia de seguridad no lleva lo que está en marcha.
        expect(again.timers.toBackupJson().containsKey('run'), isFalse);
        expect(again.timers.toBackupJson().containsKey('stopwatch'), isFalse);
      });
    });
  });

  group('Copia de seguridad', () {
    test('exportar y restaurar en otro teléfono', () async {
      await withClock(Clock.fixed(now), () async {
        final Stores a = open('a');
        a.habits.add(water());
        a.habits.setValue('agua', today, 8);
        a.habits.setValue('agua', DateTime(2026, 10, 13), 5);
        a.reminders.add(Reminder(id: 'r', title: 'Llamar a mamá', dueAt: DateTime(2026, 10, 18, 11), recurrence: const Recurrence(type: RecurrenceType.weekdays, weekdays: <int>[7]), createdAt: now));
        a.timers.addWorkout(WorkoutTemplates.create(WorkoutTemplate.circuit, spanish: true, now: now));
        a.timers.addSession(WorkoutSession(id: 'x', name: 'Circuito', startedAt: now, endedAt: now, activeSeconds: 805, completed: true));
        final AppSettings settingsA = AppSettings()
          ..language = 'en'
          ..weekStart = DateTime.sunday
          ..accent = 3
          ..voice = false;
        final String text = Backups.encode(Backups.build(habits: a.habits, reminders: a.reminders, timers: a.timers, settings: settingsA, now: now));
        expect(Backups.fileName(now), 'rutinas-2026-10-14.json');

        final BackupContents c = Backups.decode(text);
        expect(<int>[c.habits, c.days, c.reminders, c.workouts, c.sessions], <int>[1, 2, 1, 1, 1]);
        expect(c.exportedAt, now);

        // El otro teléfono tenía datos propios y un cronómetro corriendo.
        final Stores b = open('b');
        b.habits.add(Habit(id: 'otro', name: 'Otro', startDate: today, createdAt: now));
        b.timers.stopwatch.start(now);
        final AppSettings settingsB = AppSettings();
        await Backups.restore(c, habits: b.habits, reminders: b.reminders, timers: b.timers, settings: settingsB);
        expect(b.habits.habits.map((Habit h) => h.id), <String>['agua']);
        expect(b.habits.entry('agua', today)!.value, 8);
        expect(b.reminders.byId('r')!.recurrence.weekdays, <int>[7]);
        expect(b.timers.workouts.single.template, WorkoutTemplate.circuit);
        expect(b.timers.sessions.single.activeSeconds, 805);
        expect(b.timers.stopwatch.running, isTrue);
        expect(settingsB.language, 'en');
        expect(settingsB.weekStart, DateTime.sunday);
        expect(settingsB.accent, 3);
        expect(settingsB.voice, isFalse);
        // Quedó guardado en disco.
        final Stores b2 = open('b');
        expect(b2.habits.byId('agua'), isNotNull);
        expect(b2.reminders.reminders, hasLength(1));
      });
    });

    test('archivos que no son una copia válida', () {
      Object? error(String text) {
        try {
          Backups.decode(text);
          return null;
        } on FormatException catch (e) {
          return e.message;
        }
      }

      expect(error('hola'), 'not-json');
      expect(error('[1, 2]'), 'not-rutinas');
      expect(error('{"format": "otra-app", "version": 1}'), 'not-rutinas');
      expect(error('{"format": "rutinas-backup", "version": 2}'), 'newer-version');
      expect(error('{"format": "rutinas-backup", "version": 1, "habits": {"habits": [{"name": "sin id"}]}}'), 'damaged');
      expect(error('{"format": "rutinas-backup", "version": 1}'), isNull);
    });
  });
}
