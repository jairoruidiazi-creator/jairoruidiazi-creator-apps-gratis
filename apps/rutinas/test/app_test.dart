import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/app.dart';
import 'package:rutinas/core/app_scope.dart';
import 'package:rutinas/core/backup.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/logic/notice_plan.dart';
import 'package:rutinas/logic/recurrence.dart';
import 'package:rutinas/logic/templates.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/reminder.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/ui/catalog.dart';
import 'package:rutinas/ui/reminders/reminder_texts.dart';
import 'package:rutinas/ui/timer/countdown_view.dart';
import 'package:rutinas/ui/timer/run_bar.dart';
import 'package:rutinas/ui/timer/runner_screen.dart';
import 'package:rutinas/ui/timer/stopwatch_view.dart';
import 'package:rutinas/ui/timer/workout_editor.dart';
import 'package:rutinas/ui/widgets/common.dart';

import 'support/app_harness.dart';
import 'support/test_clock.dart';

/// Miércoles 14 de octubre de 2026, 9:30 de la mañana.
final DateTime demoNow = DateTime(2026, 10, 14, 9, 30);

/// Datos de partida para las pruebas de pantallas: hábitos de cada tipo con
/// tres semanas de historia, recordatorios, entrenamientos y su historial.
void seed(Services s, {required bool es}) {
  String tr(String a, String b) => es ? a : b;
  final DateTime today = dateOnly(demoNow);
  final DateTime start = addDays(today, -20);
  final List<Habit> habits = <Habit>[
    Habit(id: 'agua', name: tr('Beber agua', 'Drink water'), kind: HabitKind.count, goal: 8, unit: tr('vasos', 'glasses'), icon: 'water_drop', color: 0xFF1565C0, startDate: start, createdAt: start, reminders: <int>[10 * 60, 16 * 60], nagMinutes: 30),
    Habit(id: 'leer', name: tr('Leer 20 páginas', 'Read 20 pages'), icon: 'menu_book', color: 0xFF00796B, startDate: start, createdAt: start, reminders: <int>[21 * 60]),
    Habit(id: 'meditar', name: tr('Meditar', 'Meditate'), kind: HabitKind.timed, goal: 600, icon: 'self_improvement', color: 0xFF6A1B9A, startDate: start, createdAt: start),
    Habit(id: 'gym', name: tr('Ir al gimnasio', 'Go to the gym'), frequency: const Frequency(type: FrequencyType.perWeek, n: 3), icon: 'fitness_center', color: 0xFFC62828, startDate: start, createdAt: start),
    Habit(id: 'fumar', name: tr('Dejar de fumar', 'Quit smoking'), kind: HabitKind.negative, icon: 'smoke_free', color: 0xFF455A64, startDate: start, createdAt: start),
  ];
  for (final Habit h in habits) {
    s.habits.add(h);
  }
  for (int back = 20; back >= 1; back--) {
    final DateTime d = addDays(today, -back);
    s.habits.setValue('agua', d, back % 6 == 0 ? 5 : 8);
    if (back % 7 != 3) {
      s.habits.setValue('leer', d, 1);
    }
    s.habits.setValue('meditar', d, back % 5 == 0 ? 300 : 600);
    if (d.weekday == DateTime.monday || d.weekday == DateTime.wednesday || d.weekday == DateTime.friday) {
      s.habits.setValue('gym', d, 1);
    }
  }
  s.habits.setSkipped('leer', addDays(today, -3), true);
  s.habits.setNote('leer', addDays(today, -2), tr('Terminé el capítulo 4', 'Finished chapter 4'));
  s.habits.setValue('fumar', addDays(today, -12), 1);
  s.habits.setValue('agua', today, 3);
  s.reminders.add(Reminder(id: 'pastilla', title: tr('Tomar la vitamina', 'Take the vitamin'), dueAt: DateTime(2026, 10, 14, 8), recurrence: const Recurrence(type: RecurrenceType.everyNDays), nagMinutes: 10, createdAt: start));
  s.reminders.add(Reminder(id: 'arriendo', title: tr('Pagar el arriendo', 'Pay the rent'), dueAt: DateTime(2026, 10, 31, 9), recurrence: const Recurrence(type: RecurrenceType.monthlyDay, day: 31), createdAt: start));
  s.reminders.add(Reminder(id: 'mama', title: tr('Llamar a mamá', 'Call mom'), dueAt: DateTime(2026, 10, 14, 19), notes: tr('Preguntar por el viaje', 'Ask about the trip'), createdAt: start));
  final Workout tabata = WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: es, now: start);
  s.timers.addWorkout(tabata);
  s.timers.addWorkout(WorkoutTemplates.create(WorkoutTemplate.hiit, spanish: es, now: start));
  for (final int back in <int>[1, 3, 6, 8]) {
    final DateTime at = addDays(today, -back).add(const Duration(hours: 7));
    s.timers.addSession(WorkoutSession(id: 's$back', workoutId: tabata.id, name: tabata.name, startedAt: at, endedAt: at.add(const Duration(seconds: 1110)), activeSeconds: 1110, completed: true));
  }
  s.flushAll();
}

/// Corre [body] con el reloj de la demo, sobre una carpeta temporal y con la
/// app montada; al final la desmonta y deja todo limpio.
Future<void> withApp(WidgetTester tester, Future<void> Function(Services s) body, {String language = 'es', bool seeded = false, Size screen = const Size(360, 740), bool ios = false}) async {
  useScreen(tester, screen);
  final Directory dir = Directory.systemTemp.createTempSync('rutinas_app');
  await withTestClock(demoNow, () async {
    final Services s = testServices(dir, language: language, ios: ios);
    if (seeded) {
      seed(s, es: language == 'es');
    }
    await tester.pumpWidget(RutinasApp(services: s, startup: false));
    await settle(tester);
    expectNoErrors(tester, 'al abrir');
    await body(s);
    s.timer.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    s.dispose();
  });
  dir.deleteSync(recursive: true);
}

void main() {
  testWidgets('recorrido completo en un teléfono de 360 × 740', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      // Pantalla vacía y las cinco pestañas al alcance del dedo.
      expect(find.text('Crea tu primer hábito'), findsOneWidget);
      for (final String label in <String>['Hábitos', 'Avisos', 'Tiempo', 'Resumen', 'Ajustes']) {
        expectHittable(tester, navDestination(label), 'pestaña $label');
      }

      // Un hábito desde una sugerencia: beber agua, 8 vasos.
      expectHittable(tester, find.byTooltip('Nuevo hábito'), 'botón de hábito nuevo');
      await tester.tap(find.byTooltip('Nuevo hábito'));
      await settle(tester);
      expect(find.text('Nuevo hábito'), findsOneWidget);
      await tester.tap(find.text('Beber agua'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(find.text('Beber agua'), findsOneWidget);
      expect(find.text('0 de 8 vasos'), findsOneWidget);
      expectHittable(tester, find.byTooltip('Sumar 1 (vasos)'), 'sumar un vaso');
      await tester.tap(find.byTooltip('Sumar 1 (vasos)'));
      await settle(tester);
      expect(find.text('1 de 8 vasos'), findsOneWidget);

      // Un hábito escrito a mano, con aviso a las 8:00 que insiste.
      await tester.tap(find.byTooltip('Nuevo hábito'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Leer 20 páginas');
      await scrollAndTap(tester, find.text('Agregar hora'));
      final MaterialLocalizations ml = MaterialLocalizations.of(tester.element(find.byType(Dialog)));
      await tester.tap(find.text(ml.okButtonLabel));
      await settle(tester);
      expect(find.byType(InputChip), findsOneWidget);
      await scrollAndTap(tester, find.text('Insistir hasta marcarlo'));
      expect(find.textContaining('Repite el aviso cada 15 min mientras no esté hecho'), findsOneWidget);
      expect(find.textContaining('El teléfono guarda hasta 30 repeticiones'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Habit leer = s.habits.habits.last;
      expect(leer.reminders, <int>[8 * 60]);
      expect(leer.nagMinutes, 15);
      expect(s.fakeGateway.notificationsAllowed, isTrue);
      expectHittable(tester, find.byTooltip('Marcar como hecho'), 'marcar hecho');
      await tester.tap(find.byTooltip('Marcar como hecho'));
      await settle(tester);
      expect(find.text('Hechos (1)'), findsOneWidget);
      // Hecho hoy: su aviso de hoy ya no se programa, el de mañana sí.
      await tester.pump(const Duration(seconds: 1));
      final List<PlannedNotice> plan = s.notices.lastPlan.notices.where((PlannedNotice n) => n.route.startsWith('habit:${leer.id}:')).toList();
      expect(plan.where((PlannedNotice n) => n.route.endsWith(dayKey(demoNow))), isEmpty);
      expect(plan.first.when, DateTime(2026, 10, 15, 8));

      // Detalle: rachas, calendario y una nota en el día de hoy.
      await tester.tap(find.text('Leer 20 páginas'));
      await settle(tester);
      expect(find.text('Racha actual'), findsOneWidget);
      expect(find.text('Mejor racha'), findsOneWidget);
      await scrollAndTap(tester, find.text('14'));
      await tester.enterText(find.widgetWithText(TextField, 'Nota del día'), 'Capítulo 3');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(s.habits.entry(leer.id, demoNow)!.note, 'Capítulo 3');
      expect(find.text('Capítulo 3'), findsWidgets);
      await goBack(tester);
      expectNoErrors(tester, 'hábitos');

      // Recordatorios: "avísame en 10 min" y uno mensual hecho a mano.
      await goTab(tester, 'Avisos');
      expectHittable(tester, find.text('10 min'), 'avísame en 10 min');
      await tester.tap(find.text('10 min'));
      await settle(tester);
      expect(find.text('Cuenta regresiva de 10 min'), findsOneWidget);
      expect(find.textContaining('Suena en '), findsOneWidget);
      await tester.tap(find.text('Recordatorio'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '¿Qué te recuerdo?'), 'Pagar el arriendo');
      await tester.tap(find.text('Cada mes'));
      await tester.pump();
      expect(find.textContaining('El 14 de cada mes'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(find.text('Pagar el arriendo'), findsOneWidget);
      // La regla guarda su hora (G8).
      expect(s.reminders.reminders.last.recurrence, const Recurrence(type: RecurrenceType.monthlyDay, day: 14, hour: 10, minute: 0));
      // Apagar la cuenta regresiva desde la lista.
      expectHittable(tester, find.byTooltip('Apagar'), 'apagar la cuenta regresiva');
      await tester.tap(find.byTooltip('Apagar'));
      await settle(tester);
      expect(s.reminders.completed, hasLength(1));
      expectNoErrors(tester, 'recordatorios');

      // Temporizador: Tabata desde la plantilla, a pantalla completa.
      await goTab(tester, 'Tiempo');
      await tester.tap(find.text('Tabata'));
      await settle(tester);
      expect(find.text('18:30 · 64 intervalos'), findsOneWidget);
      await scrollAndTap(tester, find.text('Guardar e iniciar'), running: true);
      expect(find.byType(RunnerScreen), findsOneWidget);
      expect(find.text('Prepárate'), findsOneWidget);
      expect(find.textContaining('Sigue: Trabajo'), findsOneWidget);
      expect(find.textContaining('Total restante'), findsOneWidget);
      final Finder lock = find.byKey(const ValueKey<String>('runner-lock'));
      expectHittable(tester, lock, 'candado');
      expectHittable(tester, find.byTooltip('Pausar'), 'pausar');
      expectHittable(tester, find.byTooltip('Intervalo siguiente'), 'siguiente');
      await tester.tap(lock);
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(s.timer.locked, isTrue);
      // Bloqueado: el botón de pausa no hace nada.
      await tester.tap(find.byTooltip('Pausar'), warnIfMissed: false);
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(s.timer.run!.paused, isFalse);
      await tester.longPress(lock);
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(s.timer.locked, isFalse);
      await tester.tap(find.byTooltip('Intervalo siguiente'));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('Trabajo'), findsOneWidget);
      expect(find.text('Ronda 1 de 8 · Serie 1 de 4'), findsOneWidget);
      expect(s.silentCues.log, containsAllInOrder(<String>['speak:Prepárate', 'speak:Trabajo']));
      await tester.tap(find.byTooltip('Pausar'));
      await settle(tester);
      expect(find.text('En pausa'), findsOneWidget);
      await tester.tap(find.byTooltip('Minimizar'));
      await settle(tester);
      // La barra del temporizador queda a mano desde cualquier pestaña.
      expect(find.textContaining('En pausa ·'), findsOneWidget);
      await goTab(tester, 'Resumen');
      expectHittable(tester, find.textContaining('En pausa ·'), 'barra del temporizador');
      await tester.tap(find.textContaining('En pausa ·'));
      await settle(tester);
      await tester.tap(find.byTooltip('Terminar'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Terminar')));
      await settle(tester);
      expect(s.timer.run, isNull);
      expect(find.byType(RunnerScreen), findsNothing);
      await goTab(tester, 'Tiempo');
      expectNoErrors(tester, 'temporizador');

      // Cronómetro con dos vueltas: la más rápida y la más lenta resaltadas.
      await tapTab(tester, 'Cronómetro');
      Finder inStopwatch(String text) => find.descendant(of: find.byType(StopwatchView), matching: find.text(text));
      await tester.tap(inStopwatch('Iniciar'));
      await pumpFor(tester, const Duration(milliseconds: 1500));
      await tester.tap(inStopwatch('Vuelta'));
      await pumpFor(tester, const Duration(milliseconds: 700));
      await tester.tap(inStopwatch('Vuelta'));
      await pumpFor(tester, const Duration(milliseconds: 200));
      await tester.tap(inStopwatch('Pausar'));
      await settle(tester);
      expect(s.timers.stopwatch.laps, hasLength(2));
      expect(find.textContaining('Mejor'), findsOneWidget);
      expect(find.textContaining('Peor'), findsOneWidget);

      // Cuenta regresiva guardada.
      await tapTab(tester, 'Cuenta regresiva');
      Finder inCountdown(String text) => find.descendant(of: find.byType(CountdownView), matching: find.text(text));
      await tester.tap(inCountdown('5 min'));
      await tester.pump();
      await tester.tap(inCountdown('Guardar'));
      await settle(tester);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Té verde');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Guardar')));
      await settle(tester);
      await reveal(tester, find.text('Té verde'));
      expect(find.text('Té verde'), findsOneWidget);
      expect(s.timers.presets.single.seconds, 300);
      expectNoErrors(tester, 'cronómetro y cuenta regresiva');

      // Resumen de la semana, el mes y el año.
      await goTab(tester, 'Resumen');
      expect(find.text('Cumplimiento'), findsOneWidget);
      await reveal(tester, find.text('Hábitos hechos por día'));
      expect(find.text('Hábitos hechos por día'), findsOneWidget);
      await scrollAndTap(tester, find.text('Año'));
      expect(find.text('2026'), findsOneWidget);
      await reveal(tester, find.text('Hábitos hechos por mes'));
      expect(find.text('Hábitos hechos por mes'), findsOneWidget);
      expectNoErrors(tester, 'resumen');

      // Ajustes: idioma, copia de seguridad y política de privacidad.
      await goTab(tester, 'Ajustes');
      await tester.tap(find.text('English'));
      await settle(tester);
      for (final String label in <String>['Habits', 'Reminders', 'Timer', 'Summary', 'Settings']) {
        expectHittable(tester, navDestination(label), 'tab $label');
      }
      await tester.tap(find.text('Español'));
      await settle(tester);
      final Finder export = find.text('Exportar copia');
      await tester.scrollUntilVisible(export, 200, scrollable: verticalList());
      await tester.tap(export);
      await waitFor(tester, () => s.fakeIO.shared.isNotEmpty);
      await settle(tester);
      final BackupContents c = Backups.decode(File(s.fakeIO.shared.single).readAsStringSync());
      expect(<int>[c.habits, c.reminders, c.workouts], <int>[2, 2, 1]);
      expect(s.settings.lastExportAt, isNotNull);
      await scrollAndTap(tester, find.text('Política de privacidad'));
      await waitFor(tester, () => find.text('Política de privacidad de Rutinas').evaluate().isNotEmpty);
      await goBack(tester);
      expectNoErrors(tester, 'ajustes');
    });
  });

  testWidgets('los botones de las notificaciones marcan, suman y posponen', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      await s.notices.init();
      final String today8 = 'reminder:pastilla|${DateTime(2026, 10, 14, 8).millisecondsSinceEpoch}|0|0';
      s.fakeGateway.respond(today8, 'snooze');
      await settle(tester);
      final DateTime snoozed = s.reminders.byId('pastilla')!.snoozedUntil!;
      expect(snoozed.difference(demoNow.add(const Duration(minutes: 10))).inSeconds.abs(), lessThan(10));
      // Lleva a la pestaña de avisos.
      expect(find.text('Recordatorios'), findsOneWidget);
      s.fakeGateway.respond(today8, 'done');
      await settle(tester);
      expect(s.reminders.byId('pastilla')!.dueAt, DateTime(2026, 10, 15, 8));
      expect(s.reminders.byId('pastilla')!.snoozedUntil, isNull);
      // Un aviso viejo (el de hoy, ya hecho) no toca la ocurrencia de mañana:
      // solo se quita del panel (G3).
      s.fakeGateway.respond(today8, 'done', 77);
      await settle(tester);
      expect(s.reminders.byId('pastilla')!.dueAt, DateTime(2026, 10, 15, 8));
      expect(s.fakeGateway.cancelled, contains(77));
      expect(find.text('Ese aviso era de una vez anterior: el recordatorio de ahora sigue pendiente.'), findsOneWidget);
      s.fakeGateway.respond(today8, 'snooze', 78);
      await settle(tester);
      expect(s.reminders.byId('pastilla')!.snoozedUntil, isNull);
      s.fakeGateway.respond('habit:agua:${dayKey(demoNow)}|1|2', 'plus');
      await settle(tester);
      expect(s.habits.entry('agua', demoNow)!.value, 4);
      expect(find.text('4 de 8 vasos'), findsOneWidget);
      s.fakeGateway.respond('habit:leer:${dayKey(demoNow)}|1|2', 'done');
      await settle(tester);
      expect(s.habits.entry('leer', demoNow)!.value, 1);
      // El aviso de un hábito con tiempo abre el hábito, con su botón para empezar (M4).
      s.fakeGateway.respond('habit:meditar:${dayKey(demoNow)}|1|2');
      await settle(tester);
      expect(find.text('Racha actual'), findsOneWidget);
      expect(find.textContaining('Iniciar 10 min'), findsOneWidget);
      // «Empezar» abre el temporizador con lo que falta de hoy.
      s.fakeGateway.respond('habit:meditar:${dayKey(demoNow)}|1|2', 'start');
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(RunnerScreen), findsOneWidget);
      expect(s.timer.run!.name, 'Meditar');
      s.timer.stop();
      await settle(tester);
      // Un toque en el aviso del temporizador abre la pantalla en marcha.
      s.timer.startWorkout(s.timers.sortedWorkouts.first);
      s.fakeGateway.respond('timer|1|2');
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(RunnerScreen), findsOneWidget);
    }, seeded: true);
  });

  for (final bool landscape in <bool>[false, true]) {
    for (final double scale in <double>[1.0, 2.0]) {
      final String where = '${landscape ? 'apaisado' : 'vertical'}, texto ×$scale';
      testWidgets('todas las pantallas sin desbordes ($where)', (WidgetTester tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await withApp(tester, (Services s) async {
          await screensTour(tester, s, where);
        }, seeded: true, screen: landscape ? const Size(740, 360) : const Size(360, 740));
      });
    }
  }

  testWidgets('tema oscuro y otro color de acento', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      s.settings
        ..themeMode = 'dark'
        ..accent = 4;
      await s.settings.save();
      await settle(tester);
      expect(Theme.of(tester.element(find.text('Beber agua'))).brightness, Brightness.dark);
      expect(Theme.of(tester.element(find.text('Beber agua'))).colorScheme.brightness, Brightness.dark);
      for (final String tab in <String>['Avisos', 'Tiempo', 'Resumen', 'Ajustes', 'Hábitos']) {
        await goTab(tester, tab);
        expectNoErrors(tester, 'oscuro: $tab');
      }
    }, seeded: true);
  });

  testWidgets('tableta: riel lateral y contenido a un ancho legible', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await screensTour(tester, s, 'tableta');
    }, seeded: true, screen: const Size(800, 1280));
  });

  testWidgets('tableta: la barra del temporizador queda sobre la barra del sistema (M6)', (WidgetTester tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 60);
    tester.view.viewPadding = const FakeViewPadding(bottom: 60);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await withApp(tester, (Services s) async {
      s.timer.startWorkout(s.timers.sortedWorkouts.first);
      await pumpFor(tester, const Duration(milliseconds: 600));
      final Finder pause = find.descendant(of: find.byType(RunBar), matching: find.byType(IconButton));
      expect(pause, findsOneWidget);
      // 60 píxeles físicos con densidad 3: 20 dp de barra del sistema abajo.
      expect(tester.getRect(pause).bottom, lessThanOrEqualTo(1280 - 20));
      expectHittable(tester, pause, 'pausar desde la barra');
    }, seeded: true, screen: const Size(800, 1280));
  });

  testWidgets('en inglés si el teléfono está en inglés', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      expect(find.text('Habits'), findsWidgets);
      expect(find.text('Drink water'), findsOneWidget);
      expect(find.text('3 of 8 glasses'), findsOneWidget);
      await goTab(tester, 'Reminders');
      expect(find.text('Remind me in…'), findsOneWidget);
      expect(find.textContaining('Repeats every 10 min'), findsOneWidget);
      // La misma hora en la lista y en el editor (M15).
      expect(find.textContaining('Today, 7:00 PM'), findsOneWidget);
      await scrollAndTap(tester, find.text('Call mom'));
      expect(find.text('7:00 PM'), findsOneWidget);
      expect(find.text('What should I remind you about?'), findsOneWidget);
      await goBack(tester);
      await goTab(tester, 'Summary');
      expect(find.text('Success rate'), findsOneWidget);
      expectNoErrors(tester, 'inglés');
    }, language: 'en', seeded: true);
  });

  testWidgets('objetivos táctiles de 48 dp y con nombre en las pantallas principales', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await withApp(tester, (Services s) async {
      Future<void> check(String where) async {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: where);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: where);
      }

      await check('hábitos');
      await tester.tap(find.text('Leer 20 páginas'));
      await settle(tester);
      await check('detalle del hábito');
      await goBack(tester);
      // Los editores, con los días de la semana a la vista (M18).
      await tester.tap(find.byTooltip('Nuevo hábito'));
      await settle(tester);
      await scrollAndTap(tester, find.text('Varias veces'));
      await scrollAndTap(tester, find.text('Algunos días'));
      await check('editor de hábitos');
      await goBack(tester);
      final Finder meditar = find.text('Meditar');
      await reveal(tester, meditar);
      await tester.longPress(meditar);
      await settle(tester);
      await check('hoja del día');
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      await goTab(tester, 'Avisos');
      await tester.tap(find.text('Recordatorio'));
      await settle(tester);
      await scrollAndTap(tester, find.text('Días de la semana'));
      await check('editor de recordatorios');
      await scrollAndTap(tester, find.text('Cada N días'));
      await check('editor de recordatorios, cada N días');
      await goBack(tester);
      for (final String tab in <String>['Avisos', 'Tiempo', 'Resumen', 'Ajustes']) {
        await goTab(tester, tab);
        await check(tab);
      }
      await goTab(tester, 'Tiempo');
      await tester.tap(find.text('Tabata de 4 series').first);
      await settle(tester);
      await check('editor de entrenamientos');
      await goBack(tester);
      s.timer.startWorkout(s.timers.sortedWorkouts.first);
      unawaited(RunnerScreen.open(tester.element(find.byType(NavigationBar))));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await check('temporizador en marcha');
    }, seeded: true);
    handle.dispose();
  });

  testWidgets('los días de la semana se marcan con la acción de toque de los lectores de pantalla (G9)', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await withApp(tester, (Services s) async {
      await tester.tap(find.byTooltip('Nuevo hábito'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Correr');
      await scrollAndTap(tester, find.text('Algunos días'));
      // Lo que hacen TalkBack, VoiceOver, Switch Access y Voice Access: la acción de toque del nodo.
      tester.semantics.tap(find.semantics.byLabel('lunes'));
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel('miércoles'));
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel('viernes'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      // Hoy es miércoles (ya marcado): queda lunes y viernes.
      expect(s.habits.habits.single.frequency.weekdays, <int>[1, 5]);
    });
    handle.dispose();
  });

  testWidgets('posponer solo aparece en lo que ya sonó o está por sonar (G1)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      await goTab(tester, 'Avisos');
      // La vitamina está vencida; mamá (19:00) y el arriendo (día 31) todavía no.
      expect(find.byTooltip('Posponer'), findsOneWidget);
      await tester.tap(find.byTooltip('Posponer'));
      await settle(tester);
      await tester.tap(find.text('Mañana a las 9:00'));
      await settle(tester);
      expect(s.reminders.byId('pastilla')!.alertAt, DateTime(2026, 10, 15, 9));
      expect(s.reminders.byId('pastilla')!.dueAt, DateTime(2026, 10, 14, 8));
    }, seeded: true);
  });

  testWidgets('abrir y guardar un recordatorio no cambia su regla ni su ocurrencia (G2)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      s.reminders.add(Reminder(id: 'fin', title: 'Fin de mes', dueAt: DateTime(2026, 11, 30, 9), recurrence: const Recurrence(type: RecurrenceType.monthlyDay, day: 31), createdAt: demoNow));
      s.reminders.add(Reminder(id: 'ana', title: 'Cumpleaños de Ana', dueAt: DateTime(2027, 2, 28, 8), recurrence: const Recurrence(type: RecurrenceType.yearly, month: 2, day: 29), createdAt: demoNow));
      s.reminders.snooze('pastilla', 30);
      final DateTime snoozed = s.reminders.byId('pastilla')!.snoozedUntil!;
      await goTab(tester, 'Avisos');

      await scrollAndTap(tester, find.text('Fin de mes'));
      expect(find.textContaining('El 31 de cada mes'), findsOneWidget);
      expect(find.textContaining('En los meses que no tienen día 31'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '¿Qué te recuerdo?'), 'Pagar la tarjeta');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Reminder fin = s.reminders.byId('fin')!;
      expect(fin.title, 'Pagar la tarjeta');
      expect(fin.recurrence.day, 31);
      expect(fin.dueAt, DateTime(2026, 11, 30, 9));
      ReminderLogic.complete(fin, DateTime(2026, 11, 30, 9, 5));
      expect(fin.dueAt, DateTime(2026, 12, 31, 9));

      await scrollAndTap(tester, find.text('Cumpleaños de Ana'));
      expect(find.textContaining('En los años no bisiestos suena el 28 de febrero'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Reminder ana = s.reminders.byId('ana')!;
      expect(<int>[ana.recurrence.month, ana.recurrence.day], <int>[2, 29]);
      expect(ana.dueAt, DateTime(2027, 2, 28, 8));
      ReminderLogic.complete(ana, DateTime(2027, 2, 28, 8, 5));
      expect(ana.dueAt, DateTime(2028, 2, 29, 8));

      // Vencido y pospuesto: guardar sin cambios no lo mueve ni quita lo pospuesto.
      await scrollAndTap(tester, find.text('Tomar la vitamina'));
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(s.reminders.byId('pastilla')!.dueAt, DateTime(2026, 10, 14, 8));
      expect(s.reminders.byId('pastilla')!.snoozedUntil, snoozed);
    }, seeded: true);
  });

  testWidgets('el tipo de un hábito con días anotados no cambia y la meta nueva rige desde hoy (G5)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      await tester.tap(find.text('Beber agua'));
      await settle(tester);
      await tester.tap(find.byTooltip('Editar'));
      await settle(tester);
      expect(find.text('Dejar de…'), findsNothing);
      expect(find.text('Con tiempo'), findsNothing);
      await reveal(tester, find.text('Crear un hábito nuevo'));
      expect(find.textContaining('El tipo no se puede cambiar'), findsOneWidget);
      final Finder plus = find.descendant(of: find.byType(NumberStepper), matching: find.byIcon(Icons.add)).first;
      await reveal(tester, plus);
      await tester.tap(plus);
      await tester.pump();
      expect(find.textContaining('El cambio rige desde hoy'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Habit agua = s.habits.byId('agua')!;
      expect(agua.kind, HabitKind.count);
      expect(agua.goal, 9);
      expect(agua.targetOn(DateTime(2026, 10, 13)), 8);
      // Los días de antes, con 8 vasos, siguen hechos.
      expect(s.habits.entry('agua', DateTime(2026, 10, 13))!.value, 8);
      await goBack(tester);
      // Otra forma de medirlo: un hábito nuevo con el mismo nombre.
      await tester.tap(find.text('Beber agua'));
      await settle(tester);
      await tester.tap(find.byTooltip('Editar'));
      await settle(tester);
      await scrollAndTap(tester, find.text('Crear un hábito nuevo'));
      expect(find.text('Nuevo hábito'), findsOneWidget);
      await scrollAndTap(tester, find.text('Con tiempo'));
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(s.habits.habits.where((Habit h) => h.name == 'Beber agua').map((Habit h) => h.kind), containsAll(<HabitKind>[HabitKind.count, HabitKind.timed]));
    }, seeded: true);
  });

  testWidgets('un hábito saltado hoy deja de estar por hacer (M11)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      // Agua, leer, meditar y el gimnasio (1 de 3 esta semana).
      expect(find.text('Por hacer (4)'), findsOneWidget);
      s.habits.setSkipped('leer', demoNow, true);
      await settle(tester);
      expect(find.text('Por hacer (3)'), findsOneWidget);
      expect(find.text('Saltados (1)'), findsOneWidget);
    }, seeded: true);
  });

  testWidgets('tocar una notificación no cierra un editor con cambios sin guardar (M12)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      await s.notices.init();
      await goTab(tester, 'Tiempo');
      await tester.tap(find.text('Tabata'));
      await settle(tester);
      expect(find.byType(WorkoutEditorScreen), findsOneWidget);
      s.fakeGateway.respond('timer|1|2');
      await settle(tester);
      expect(find.byType(WorkoutEditorScreen), findsOneWidget);
    });
  });

  testWidgets('los números se pueden escribir (M14)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      await goTab(tester, 'Avisos');
      await tester.tap(find.text('Otro'));
      await settle(tester);
      await tester.tap(find.text('20 min'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '120');
      await tester.tap(find.text('Aceptar'));
      await settle(tester);
      expect(find.text('2 h'), findsOneWidget);
      await tester.tap(find.text('Empezar'));
      await settle(tester);
      expect(s.reminders.reminders.single.countdownSeconds, 7200);
      // Fuera de rango: lo dice y no cierra.
      await tester.tap(find.text('Otro'));
      await settle(tester);
      await tester.tap(find.text('20 min'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '5000');
      await tester.tap(find.text('Aceptar'));
      await settle(tester);
      expect(find.text('Escribe un número de 1 a 1440.'), findsOneWidget);
    });
  });

  testWidgets('primer entrenamiento sin alarmas exactas: lo explica y lo advierte en la pantalla (G6)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      s.fakeGateway.exactAllowed = false;
      await s.notices.refreshPermissions();
      await goTab(tester, 'Tiempo');
      await reveal(tester, find.text('Iniciar'));
      await tester.tap(find.text('Iniciar').first);
      await settle(tester);
      expect(find.text('Avisos a tiempo con la pantalla apagada'), findsOneWidget);
      expect(find.textContaining('hasta una hora tarde'), findsOneWidget);
      await tester.tap(find.text('Ahora no'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(RunnerScreen), findsOneWidget);
      expect(s.settings.askedExactForTimer, isTrue);
      expect(find.textContaining('pueden llegar hasta una hora tarde'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(RunnerScreen), matching: find.text('Permitir')));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(s.fakeGateway.exactAllowed, isTrue);
      expect(find.textContaining('pueden llegar hasta una hora tarde'), findsNothing);
      s.timer.stop();
      await settle(tester);
      // La segunda vez ya no pregunta.
      s.fakeGateway.exactAllowed = false;
      await s.notices.refreshPermissions();
      await reveal(tester, find.text('Iniciar'));
      await tester.tap(find.text('Iniciar').first);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('Avisos a tiempo con la pantalla apagada'), findsNothing);
      expect(find.byType(RunnerScreen), findsOneWidget);
    }, seeded: true);
  });

  testWidgets('iPhone: si los cambios del Tabata no caben, se dice antes de bloquear (G6)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      final Workout tabata = s.timers.sortedWorkouts.firstWhere((Workout w) => w.template == WorkoutTemplate.tabata);
      final int total = TimerEngine.flatten(tabata.nodes).length;
      s.timer.startWorkout(tabata);
      unawaited(RunnerScreen.open(tester.element(find.byType(NavigationBar))));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.textContaining('Si bloqueas la pantalla, los avisos llegan hasta el intervalo 60 de $total'), findsOneWidget);
      expect(find.textContaining('Alarmas y recordatorios'), findsNothing);
    }, seeded: true, ios: true);
  });

  testWidgets('si los avisos no caben, la app dice hasta cuándo llegan (B1)', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      for (int i = 0; i < 10; i++) {
        s.habits.add(Habit(id: 'h$i', name: 'Hábito $i', startDate: DateTime(2026, 9, 1), createdAt: DateTime(2026, 9, 1), reminders: <int>[7 * 60 + i, 13 * 60 + i, 20 * 60 + i], nagMinutes: 15));
        s.reminders.add(Reminder(id: 'r$i', title: 'Recordatorio $i', dueAt: DateTime(2026, 10, 14, 10 + i), recurrence: const Recurrence(type: RecurrenceType.everyNDays), nagMinutes: 5, createdAt: demoNow));
      }
      await s.notices.sync();
      expect(s.notices.coveredUntil, isNotNull);
      await goTab(tester, 'Avisos');
      expect(find.textContaining('Tienes más avisos de los que el teléfono puede guardar'), findsOneWidget);
      await goTab(tester, 'Ajustes');
      await reveal(tester, find.text('Avisos programados'));
      expect(find.textContaining('El teléfono guarda 60 avisos a la vez'), findsOneWidget);
    }, ios: true);
  });

  test('textos de las cuentas regresivas que suenan (M5)', () {
    final DateTime alert = DateTime(2026, 10, 14, 9, 30);
    expect(ReminderTexts.ringingSince(alert, DateTime(2026, 10, 14, 9, 30, 20), true), 'Sonando desde las 9:30');
    expect(ReminderTexts.ringingSince(alert, DateTime(2026, 10, 15, 7), true), 'Sonando desde ayer a las 9:30');
    expect(ReminderTexts.ringingSince(alert, DateTime(2026, 10, 14, 9, 31), false), 'Ringing since 9:30 AM');
  });

  test('los colores de hábitos, intervalos y acentos dejan leer texto blanco (AA)', () {
    const Color white = Color(0xFFFFFFFF);
    for (final NamedColor c in kColors) {
      expect(contrastRatio(c.color, white), greaterThanOrEqualTo(4.5), reason: c.en);
      expect(onColor(c.color), white, reason: c.en);
    }
    for (final NamedColor c in kAccents) {
      expect(contrastRatio(c.color, white), greaterThanOrEqualTo(4.5), reason: c.en);
    }
    for (final StepKind k in StepKind.values) {
      expect(contrastRatio(Color(defaultStepColor(k)), white), greaterThanOrEqualTo(4.5), reason: k.name);
    }
    // Los colores fijos de la cuenta regresiva y del tiempo de los hábitos.
    for (final int c in <int>[0xFF283593, 0xFF00695C]) {
      expect(contrastRatio(Color(c), white), greaterThanOrEqualTo(4.5));
    }
  });
}

/// Pasa por cada pestaña y por las pantallas que se abren desde ellas, y
/// comprueba que no haya desbordes y que los botones principales reciban toques.
Future<void> screensTour(WidgetTester tester, Services s, String where) async {
  final bool es = s.settings.spanish;
  String tr(String a, String b) => es ? a : b;
  await reveal(tester, find.text(tr('Beber agua', 'Drink water')));
  expect(find.text(tr('Beber agua', 'Drink water')), findsOneWidget);
  await expectReachable(tester, find.byTooltip(tr('Sumar 1 (vasos)', 'Add 1 (glasses)')), '$where: sumar');
  expectNoErrors(tester, '$where: hábitos');

  // Editor de hábitos con sus secciones abiertas.
  await tester.tap(find.byTooltip(tr('Nuevo hábito', 'New habit')));
  await settle(tester);
  await scrollAndTap(tester, find.text(tr('Varias veces', 'Several times')));
  await scrollAndTap(tester, find.text(tr('Algunos días', 'Some days')));
  await toBottom(tester);
  await expectReachable(tester, find.text(tr('Guardar hábito', 'Save habit')), '$where: guardar hábito');
  expectNoErrors(tester, '$where: editor de hábitos');
  await goBack(tester);

  // Detalle de un hábito con su calendario, y la hoja del día.
  await scrollAndTap(tester, find.text(tr('Ir al gimnasio', 'Go to the gym')));
  expectNoErrors(tester, '$where: detalle');
  await toBottom(tester);
  expectNoErrors(tester, '$where: calendario');
  await goBack(tester);
  final Finder meditar = find.text(tr('Meditar', 'Meditate'));
  await reveal(tester, meditar);
  await tester.longPress(meditar);
  await settle(tester);
  await expectReachable(tester, find.text(tr('Guardar', 'Save')), '$where: guardar el día');
  expectNoErrors(tester, '$where: hoja del día');
  await tester.tap(find.text(tr('Cancelar', 'Cancel')));
  await settle(tester);

  // Recordatorios y su editor.
  await goTab(tester, tr('Avisos', 'Reminders'));
  await reveal(tester, find.text(tr('Tomar la vitamina', 'Take the vitamin')));
  expectHittable(tester, find.text(tr('Recordatorio', 'Reminder')), '$where: recordatorio nuevo');
  expectNoErrors(tester, '$where: recordatorios');
  await scrollAndTap(tester, find.text(tr('Pagar el arriendo', 'Pay the rent')));
  await toBottom(tester);
  await expectReachable(tester, find.text(tr('Guardar recordatorio', 'Save reminder')), '$where: guardar recordatorio');
  expectNoErrors(tester, '$where: editor de recordatorios');
  await goBack(tester);

  // Temporizador: lista, editor con bloques anidados, cronómetro y cuenta regresiva.
  await goTab(tester, tr('Tiempo', 'Timer'));
  await expectReachable(tester, find.text(tr('Iniciar', 'Start')), '$where: iniciar entrenamiento');
  expectNoErrors(tester, '$where: entrenamientos');
  await scrollAndTap(tester, find.text(tr('Tabata de 4 series', 'Tabata, 4 sets')).first);
  await toBottom(tester);
  expectNoErrors(tester, '$where: editor de entrenamientos');
  await goBack(tester);
  for (final String tab in <String>[tr('Cronómetro', 'Stopwatch'), tr('Cuenta regresiva', 'Countdown')]) {
    await tapTab(tester, tab);
    expectNoErrors(tester, '$where: $tab');
  }
  await tapTab(tester, tr('Intervalos', 'Intervals'));

  // En marcha, a pantalla completa.
  await reveal(tester, find.text(tr('Iniciar', 'Start')));
  await tester.tap(find.text(tr('Iniciar', 'Start')).first);
  await pumpFor(tester, const Duration(seconds: 2));
  expect(find.byType(RunnerScreen), findsOneWidget);
  expectHittable(tester, find.byKey(const ValueKey<String>('runner-lock')), '$where: candado');
  await expectReachable(tester, find.byTooltip(tr('Pausar', 'Pause')), '$where: pausar');
  await expectReachable(tester, find.byTooltip(tr('Terminar', 'Stop')), '$where: terminar');
  expectNoErrors(tester, '$where: en marcha');
  await tester.tap(find.byTooltip(tr('Intervalo siguiente', 'Next interval')));
  await pumpFor(tester, const Duration(milliseconds: 400));
  expectNoErrors(tester, '$where: en marcha, trabajo');
  // Terminado: la pantalla de felicitación.
  for (int i = 0; i < 80 && s.timer.run != null; i++) {
    s.timer.next();
  }
  await settle(tester);
  expect(find.text(tr('¡Terminaste!', 'Done!')), findsOneWidget);
  await expectReachable(tester, find.text(tr('Cerrar', 'Close')), '$where: cerrar');
  expectNoErrors(tester, '$where: terminado');
  await tester.tap(find.text(tr('Cerrar', 'Close')));
  await settle(tester);
  expect(find.byType(RunnerScreen), findsNothing);

  // Resumen en sus tres periodos.
  await goTab(tester, tr('Resumen', 'Summary'));
  for (final String r in <String>[tr('Mes', 'Month'), tr('Año', 'Year'), tr('Semana', 'Week')]) {
    await tester.tap(find.text(r));
    await settle(tester);
    expectNoErrors(tester, '$where: resumen $r');
  }
  await toBottom(tester);
  expectNoErrors(tester, '$where: resumen por hábito');

  // Ajustes de arriba abajo.
  await goTab(tester, tr('Ajustes', 'Settings'));
  await toBottom(tester);
  await expectReachable(tester, find.text(tr('Política de privacidad', 'Privacy policy')), '$where: privacidad');
  expectNoErrors(tester, '$where: ajustes');
}
