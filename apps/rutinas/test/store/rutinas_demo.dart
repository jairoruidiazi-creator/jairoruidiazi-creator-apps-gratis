// Datos de ejemplo para las capturas de tienda de Rutinas: seis hábitos con
// dos meses de historia, recordatorios de todo tipo, entrenamientos con
// bloques anidados y su historial. Todo es ficticio y relativo a [now].

import 'package:rutinas/core/app_scope.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/logic/templates.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/reminder.dart';
import 'package:rutinas/model/workout.dart';

/// El entrenamiento propio de la demo (se abre en el editor de bloques).
const String kDemoCustomWorkout = 'w_piernas';

/// El Tabata de la demo (corre en la captura del temporizador).
const String kDemoTabata = 'w_tabata';

/// Llena los almacenes de [s] en el idioma pedido.
void seedRutinasDemo(Services s, {required bool spanish, required DateTime now}) {
  String tr(String es, String en) => spanish ? es : en;
  final DateTime today = dateOnly(now);
  DateTime ago(int days) => addDays(today, -days);

  // ------------------------------------------------------------------ hábitos
  final Habit agua = Habit(id: 'agua', name: tr('Beber agua', 'Drink water'), kind: HabitKind.count, goal: 8, unit: tr('vasos', 'glasses'), icon: 'water_drop', color: 0xFF1565C0, startDate: ago(60), createdAt: ago(60), reminders: <int>[10 * 60, 15 * 60, 19 * 60], nagMinutes: 30);
  final Habit meditar = Habit(id: 'meditar', name: tr('Meditar', 'Meditate'), kind: HabitKind.timed, goal: 600, icon: 'self_improvement', color: 0xFF6A1B9A, startDate: ago(75), createdAt: ago(75), reminders: <int>[7 * 60], notes: tr('Diez minutos antes del desayuno', 'Ten minutes before breakfast'));
  final Habit leer = Habit(id: 'leer', name: tr('Leer 20 páginas', 'Read 20 pages'), icon: 'menu_book', color: 0xFF00796B, startDate: ago(50), createdAt: ago(50), reminders: <int>[21 * 60]);
  final Habit gym = Habit(id: 'gym', name: tr('Ir al gimnasio', 'Go to the gym'), frequency: const Frequency(type: FrequencyType.perWeek, n: 3), icon: 'fitness_center', color: 0xFFC62828, startDate: startOfWeek(ago(56), DateTime.monday), createdAt: ago(56));
  final Habit ingles = Habit(id: 'ingles', name: tr('Practicar inglés', 'Practice Spanish'), frequency: const Frequency(type: FrequencyType.weekdays, weekdays: <int>[1, 2, 3, 4, 5]), icon: 'translate', color: 0xFF3949AB, startDate: ago(40), createdAt: ago(40));
  final Habit fumar = Habit(id: 'fumar', name: tr('Dejar de fumar', 'Quit smoking'), kind: HabitKind.negative, icon: 'smoke_free', color: 0xFF455A64, startDate: ago(60), createdAt: ago(60));
  for (final Habit h in <Habit>[agua, meditar, leer, gym, ingles, fumar]) {
    s.habits.add(h);
  }

  for (int back = 60; back >= 1; back--) {
    s.habits.setValue('agua', ago(back), <int>{24, 37, 52}.contains(back) ? 6 : 8);
  }
  s.habits.setValue('agua', today, 5);

  for (int back = 75; back >= 1; back--) {
    if (back == 9 || back == 10) {
      s.habits.setSkipped('meditar', ago(back), true);
    } else {
      s.habits.setValue('meditar', ago(back), back == 42 ? 300 : (back % 9 == 0 ? 900 : 600));
    }
  }
  s.habits.setNote('meditar', ago(10), tr('De viaje: lo retomo a la vuelta', 'Travelling: back to it when I return'));
  s.habits.setNote('meditar', ago(4), tr('Con lluvia afuera, la más tranquila del mes', 'Rain outside, the calmest one this month'));
  s.habits.setNote('meditar', ago(1), tr('Me costó concentrarme, pero la hice', 'Hard to focus, but I did it'));
  s.habits.setValue('meditar', today, 600);

  for (int back = 50; back >= 1; back--) {
    if (!<int>{13, 27, 28, 40}.contains(back)) {
      s.habits.setValue('leer', ago(back), 1);
    }
  }
  s.habits.setNote('leer', ago(2), tr('Terminé «Cien años de soledad»', 'Finished "One Hundred Years of Solitude"'));

  // Tres días por semana (lunes, miércoles y viernes); un miércoles saltado
  // por enfermedad, que no rompe la racha. Esta semana va en 2 de 3.
  for (int back = 56; back >= 1; back--) {
    final DateTime d = ago(back);
    if (d.weekday == DateTime.monday || d.weekday == DateTime.wednesday || d.weekday == DateTime.friday) {
      if (back == 28) {
        s.habits.setSkipped('gym', d, true);
        s.habits.setNote('gym', d, tr('Con gripa', 'Down with the flu'));
      } else {
        s.habits.setValue('gym', d, 1);
      }
    }
  }
  s.habits.setValue('gym', ago(1), 1);

  for (int back = 40; back >= 1; back--) {
    final DateTime d = ago(back);
    if (d.weekday <= DateTime.friday && back != 16) {
      s.habits.setValue('ingles', d, 1);
    }
  }
  s.habits.setValue('ingles', today, 1);

  s.habits.setValue('fumar', ago(55), 1);
  s.habits.setValue('fumar', ago(48), 2);

  // ------------------------------------------------------------ recordatorios
  s.reminders.add(Reminder(id: 'vitamina', title: tr('Tomar la vitamina D', 'Take vitamin D'), dueAt: DateTime(today.year, today.month, today.day, 18), recurrence: const Recurrence(type: RecurrenceType.everyNDays), nagMinutes: 10, createdAt: ago(30)));
  s.reminders.add(Reminder(id: 'ropa', title: tr('Sacar la ropa de la lavadora', 'Take the laundry out'), dueAt: now.add(const Duration(minutes: 7, seconds: 12)), nagMinutes: 1, countdownSeconds: 15 * 60, createdAt: now.subtract(const Duration(minutes: 7, seconds: 48))));
  s.reminders.add(Reminder(id: 'mama', title: tr('Llamar a mamá', 'Call Mom'), notes: tr('Preguntarle por el viaje a Cartagena', 'Ask about her trip to Cartagena'), dueAt: DateTime(today.year, today.month, today.day, 19, 30), createdAt: ago(2)));
  s.reminders.add(Reminder(id: 'plantas', title: tr('Regar las plantas', 'Water the plants'), dueAt: DateTime(today.year, today.month, today.day + 2, 7, 30), recurrence: const Recurrence(type: RecurrenceType.everyNDays, n: 3), createdAt: ago(21)));
  s.reminders.add(Reminder(id: 'odonto', title: tr('Cita con el odontólogo', 'Dentist appointment'), dueAt: DateTime(today.year, today.month, today.day + 6, 15), nagMinutes: 15, createdAt: ago(5)));
  s.reminders.add(Reminder(id: 'arriendo', title: tr('Pagar el arriendo', 'Pay the rent'), dueAt: DateTime(today.year, today.month + 1, 0, 9), recurrence: const Recurrence(type: RecurrenceType.monthlyLast), nagMinutes: 60, createdAt: ago(40)));
  s.reminders.add(Reminder(id: 'ana', title: tr('Cumpleaños de Ana', "Ana's birthday"), dueAt: DateTime(2027, 2, 28, 8), recurrence: const Recurrence(type: RecurrenceType.yearly, month: 2, day: 29), createdAt: ago(60)));
  final Reminder hecho = Reminder(id: 'basura', title: tr('Sacar la basura', 'Take out the trash'), dueAt: DateTime(today.year, today.month, today.day, 8), createdAt: ago(1))..doneAt = DateTime(today.year, today.month, today.day, 8, 4);
  s.reminders.add(hecho);

  // ----------------------------------------------------------- entrenamientos
  final Workout tabata = Workout.fromJson(WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: spanish, now: ago(30)).toJson()..['id'] = kDemoTabata);
  final Workout hiit = WorkoutTemplates.create(WorkoutTemplate.hiit, spanish: spanish, now: ago(30));
  IntervalStep step(String es, String en, int seconds, StepKind kind, {int? color}) => IntervalStep(name: tr(es, en), seconds: seconds, kind: kind, color: color);
  final Workout piernas = Workout(
    id: kDemoCustomWorkout,
    name: tr('Piernas y core', 'Legs and core'),
    createdAt: ago(20),
    finishSound: CueSound.gong,
    nodes: <TimerNode>[
      step('Prepárate', 'Get ready', 10, StepKind.prepare),
      step('Calentamiento', 'Warm-up', 240, StepKind.warmup),
      RepeatBlock(name: tr('Ronda', 'Round'), repeats: 3, children: <TimerNode>[
        step('Sentadillas', 'Squats', 45, StepKind.work),
        step('Descanso', 'Rest', 15, StepKind.rest),
        step('Zancadas', 'Lunges', 45, StepKind.work),
        step('Descanso', 'Rest', 15, StepKind.rest),
        RepeatBlock(name: tr('Serie', 'Set'), repeats: 2, children: <TimerNode>[
          step('Plancha', 'Plank', 30, StepKind.work, color: 0xFF6A1B9A),
          step('Descanso', 'Rest', 10, StepKind.rest),
        ]),
        step('Descanso entre rondas', 'Rest between rounds', 60, StepKind.rest),
      ]),
      step('Estiramientos', 'Stretching', 180, StepKind.cooldown),
    ],
  );
  s.timers.addWorkout(tabata);
  s.timers.addWorkout(piernas);
  s.timers.addWorkout(hiit);
  for (final int back in <int>[1, 2, 4, 6, 8, 9, 11, 13, 15, 16, 18]) {
    final Workout w = back % 3 == 0 ? hiit : (back % 2 == 0 ? piernas : tabata);
    final DateTime start = ago(back).add(Duration(hours: back.isEven ? 18 : 6, minutes: 30));
    final int seconds = TimerEngine.totalSeconds(TimerEngine.flatten(w.nodes));
    s.timers.addSession(WorkoutSession(id: 'sesion$back', workoutId: w.id, name: w.name, startedAt: start, endedAt: start.add(Duration(seconds: seconds)), activeSeconds: seconds, completed: true));
  }
  s.timers.addPreset(CountdownPreset(id: 'te', name: tr('Té verde', 'Green tea'), seconds: 180));
  s.timers.addPreset(CountdownPreset(id: 'pasta', name: 'Pasta', seconds: 540));
  s.timers.addPreset(CountdownPreset(id: 'siesta', name: tr('Siesta', 'Nap'), seconds: 1200));
  s.flushAll();
}
