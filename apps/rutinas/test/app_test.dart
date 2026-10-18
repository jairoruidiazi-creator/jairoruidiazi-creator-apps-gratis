import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/app.dart';
import 'package:rutinas/core/app_scope.dart';
import 'package:rutinas/core/backup.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/logic/notice_plan.dart';
import 'package:rutinas/logic/templates.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/reminder.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/ui/catalog.dart';
import 'package:rutinas/ui/timer/countdown_view.dart';
import 'package:rutinas/ui/timer/runner_screen.dart';
import 'package:rutinas/ui/timer/stopwatch_view.dart';

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
Future<void> withApp(WidgetTester tester, Future<void> Function(Services s) body, {String language = 'es', bool seeded = false, Size screen = const Size(360, 740)}) async {
  useScreen(tester, screen);
  final Directory dir = Directory.systemTemp.createTempSync('rutinas_app');
  await withTestClock(demoNow, () async {
    final Services s = testServices(dir, language: language);
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
      expectHittable(tester, find.text('Hábito'), 'botón de hábito nuevo');
      await tester.tap(find.text('Hábito'));
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
      await tester.tap(find.text('Hábito'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Leer 20 páginas');
      await scrollAndTap(tester, find.text('Agregar hora'));
      final MaterialLocalizations ml = MaterialLocalizations.of(tester.element(find.byType(Dialog)));
      await tester.tap(find.text(ml.okButtonLabel));
      await settle(tester);
      expect(find.byType(InputChip), findsOneWidget);
      await scrollAndTap(tester, find.text('Insistir hasta marcarlo'));
      expect(find.text('Repite el aviso cada 15 min mientras no esté hecho.'), findsOneWidget);
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
      final List<PlannedNotice> plan = s.notices.lastPlan.where((PlannedNotice n) => n.route.startsWith('habit:${leer.id}:')).toList();
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
      expect(s.reminders.reminders.last.recurrence, const Recurrence(type: RecurrenceType.monthlyDay, day: 14));
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
      await tester.tap(find.text('Cronómetro'));
      await settle(tester);
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

      // Cuenta atrás guardada.
      await tester.tap(find.text('Cuenta atrás'));
      await settle(tester);
      Finder inCountdown(String text) => find.descendant(of: find.byType(CountdownView), matching: find.text(text));
      await tester.tap(inCountdown('5 min'));
      await tester.pump();
      await tester.tap(inCountdown('Guardar'));
      await settle(tester);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Té verde');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Guardar')));
      await settle(tester);
      expect(find.text('Té verde'), findsOneWidget);
      expect(s.timers.presets.single.seconds, 300);
      expectNoErrors(tester, 'cronómetro y cuenta atrás');

      // Resumen de la semana, el mes y el año.
      await goTab(tester, 'Resumen');
      expect(find.text('Cumplimiento'), findsOneWidget);
      expect(find.text('Hábitos hechos por día'), findsOneWidget);
      await tester.tap(find.text('Año'));
      await settle(tester);
      expect(find.text('Hábitos hechos por mes'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
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
      s.fakeGateway.respond('reminder:pastilla|1|2', 'snooze');
      await settle(tester);
      final DateTime snoozed = s.reminders.byId('pastilla')!.snoozedUntil!;
      expect(snoozed.difference(demoNow.add(const Duration(minutes: 10))).inSeconds.abs(), lessThan(10));
      // Lleva a la pestaña de avisos.
      expect(find.text('Recordatorios'), findsOneWidget);
      s.fakeGateway.respond('reminder:pastilla|1|2', 'done');
      await settle(tester);
      expect(s.reminders.byId('pastilla')!.dueAt, DateTime(2026, 10, 15, 8));
      expect(s.reminders.byId('pastilla')!.snoozedUntil, isNull);
      s.fakeGateway.respond('habit:agua:${dayKey(demoNow)}|1|2', 'plus');
      await settle(tester);
      expect(s.habits.entry('agua', demoNow)!.value, 4);
      expect(find.text('4 de 8 vasos'), findsOneWidget);
      s.fakeGateway.respond('habit:leer:${dayKey(demoNow)}|1|2', 'done');
      await settle(tester);
      expect(s.habits.entry('leer', demoNow)!.value, 1);
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

  testWidgets('tableta: riel lateral y contenido a un ancho legible', (WidgetTester tester) async {
    await withApp(tester, (Services s) async {
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await screensTour(tester, s, 'tableta');
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
    // Los colores fijos de la cuenta atrás y del tiempo de los hábitos.
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
  expect(find.text(tr('Beber agua', 'Drink water')), findsOneWidget);
  await expectReachable(tester, find.byTooltip(tr('Sumar 1 (vasos)', 'Add 1 (glasses)')), '$where: sumar');
  expectNoErrors(tester, '$where: hábitos');

  // Editor de hábitos con sus secciones abiertas.
  await tester.tap(find.text(tr('Hábito', 'Habit')));
  await settle(tester);
  await scrollAndTap(tester, find.text(tr('Varias veces', 'Several times')));
  await scrollAndTap(tester, find.text(tr('Algunos días', 'Some days')));
  await tester.drag(verticalList(), const Offset(0, -3000));
  await settle(tester);
  await expectReachable(tester, find.text(tr('Guardar hábito', 'Save habit')), '$where: guardar hábito');
  expectNoErrors(tester, '$where: editor de hábitos');
  await goBack(tester);

  // Detalle de un hábito con su calendario, y la hoja del día.
  await scrollAndTap(tester, find.text(tr('Ir al gimnasio', 'Go to the gym')));
  expectNoErrors(tester, '$where: detalle');
  await tester.drag(verticalList(), const Offset(0, -3000));
  await settle(tester);
  expectNoErrors(tester, '$where: calendario');
  await goBack(tester);
  final Finder meditar = find.text(tr('Meditar', 'Meditate'));
  await tester.scrollUntilVisible(meditar, 200, scrollable: verticalList());
  await tester.longPress(meditar);
  await settle(tester);
  await expectReachable(tester, find.text(tr('Guardar', 'Save')), '$where: guardar el día');
  expectNoErrors(tester, '$where: hoja del día');
  await tester.tap(find.text(tr('Cancelar', 'Cancel')));
  await settle(tester);

  // Recordatorios y su editor.
  await goTab(tester, tr('Avisos', 'Reminders'));
  expect(find.text(tr('Tomar la vitamina', 'Take the vitamin')), findsOneWidget);
  expectHittable(tester, find.text(tr('Recordatorio', 'Reminder')), '$where: recordatorio nuevo');
  expectNoErrors(tester, '$where: recordatorios');
  await scrollAndTap(tester, find.text(tr('Pagar el arriendo', 'Pay the rent')));
  await tester.drag(verticalList(), const Offset(0, -3000));
  await settle(tester);
  await expectReachable(tester, find.text(tr('Guardar recordatorio', 'Save reminder')), '$where: guardar recordatorio');
  expectNoErrors(tester, '$where: editor de recordatorios');
  await goBack(tester);

  // Temporizador: lista, editor con bloques anidados, cronómetro y cuenta atrás.
  await goTab(tester, tr('Tiempo', 'Timer'));
  await expectReachable(tester, find.text(tr('Iniciar', 'Start')), '$where: iniciar entrenamiento');
  expectNoErrors(tester, '$where: entrenamientos');
  await scrollAndTap(tester, find.text(tr('Tabata de 4 series', 'Tabata, 4 sets')).first);
  await tester.drag(verticalList(), const Offset(0, -1500));
  await settle(tester);
  expectNoErrors(tester, '$where: editor de entrenamientos');
  await goBack(tester);
  for (final String tab in <String>[tr('Cronómetro', 'Stopwatch'), tr('Cuenta atrás', 'Countdown')]) {
    await tester.tap(find.text(tab));
    await settle(tester);
    expectNoErrors(tester, '$where: $tab');
  }
  await tester.tap(find.text(tr('Entrenamientos', 'Workouts')));
  await settle(tester);

  // En marcha, a pantalla completa.
  await tester.ensureVisible(find.text(tr('Iniciar', 'Start')).first);
  await tester.pump();
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
  await tester.drag(verticalList(), const Offset(0, -3000));
  await settle(tester);
  expectNoErrors(tester, '$where: resumen por hábito');

  // Ajustes de arriba abajo.
  await goTab(tester, tr('Ajustes', 'Settings'));
  await tester.drag(verticalList(), const Offset(0, -6000));
  await settle(tester);
  await expectReachable(tester, find.text(tr('Política de privacidad', 'Privacy policy')), '$where: privacidad');
  expectNoErrors(tester, '$where: ajustes');
}
