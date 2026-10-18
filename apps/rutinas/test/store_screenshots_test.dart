@Tags(<String>['screenshots'])
library;

// Capturas de tienda de Rutinas: pantallas reales con los datos de ejemplo de
// test/store/rutinas_demo.dart, en teléfono y tableta de Android y en iPhone y
// iPad, en español e inglés. Se ejecutan con `flutter test --tags screenshots`.

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/app.dart';
import 'package:rutinas/core/app_scope.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/ui/timer/runner_screen.dart';

import 'store/rutinas_demo.dart';
import 'store/store_shots.dart';
import 'support/app_harness.dart';

void main() {
  for (final StoreDevice device in StoreDevice.all) {
    for (final String lang in storeLanguages) {
      testWidgets('Capturas de Rutinas en ${device.id} ($lang)', (WidgetTester tester) async {
        final bool es = lang == 'es';
        String tr(String a, String b) => es ? a : b;
        final List<String> errors = <String>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails d) {
          errors.add(d.toString());
          previous?.call(d);
        };
        addTearDown(() => FlutterError.onError = previous);

        device.apply(tester);
        await loadStoreFonts(tester);
        // Miércoles a las 6:40 de la tarde. El reloj de la app queda quieto a
        // esa hora: el temporizador en marcha se dibuja siempre en el mismo
        // segundo y las pantallas quedan quietas para la captura.
        final DateTime demoNow = DateTime(2026, 10, 14, 18, 40);
        await withClock(Clock.fixed(demoNow), () async {
          final Directory dir = Directory.systemTemp.createTempSync('rutinas_shots');
          final Services s = testServices(dir, language: lang);
          seedRutinasDemo(s, spanish: es, now: demoNow);
          await tester.pumpWidget(storeShotRoot(RutinasApp(services: s, startup: false)));
          await settle(tester);

          // 1. Los hábitos de hoy, con lo pendiente, lo hecho y lo que se deja.
          expect(find.text(tr('Beber agua', 'Drink water')), findsOneWidget);
          await takeStoreShot(tester, device, lang, '01-habitos');

          // 2. Meditar: racha, cumplimiento y el calendario del mes, con los
          // dos días saltados de un viaje que no rompen la racha.
          await tester.tap(find.text(tr('Meditar', 'Meditate')));
          await settle(tester);
          expect(find.text(tr('Racha actual', 'Current streak')), findsOneWidget);
          await takeStoreShot(tester, device, lang, '02-racha');
          await goBack(tester);

          // 3. Recordatorios: uno vencido que insiste, una cuenta regresiva y
          // los próximos con sus repeticiones.
          await goTab(tester, tr('Avisos', 'Reminders'));
          expect(find.text(tr('Tomar la vitamina D', 'Take vitamin D')), findsOneWidget);
          await takeStoreShot(tester, device, lang, '03-avisos');

          // 5. Un entrenamiento propio con un bloque dentro de otro.
          await goTab(tester, tr('Tiempo', 'Timer'));
          await tester.tap(find.text(tr('Piernas y core', 'Legs and core')).first);
          await settle(tester);
          expect(find.text(tr('Serie · repetir 2 veces', 'Set · repeat 2 times')), findsOneWidget);
          await takeStoreShot(tester, device, lang, '05-bloques');
          await goBack(tester);

          // 6. El resumen de la semana.
          await goTab(tester, tr('Resumen', 'Summary'));
          expect(find.text(tr('Cumplimiento', 'Success rate')), findsOneWidget);
          await takeStoreShot(tester, device, lang, '06-resumen');

          // 4. Un Tabata en marcha: serie 2, ronda 3, a 14 s del descanso.
          final Workout tabata = s.timers.workoutById(kDemoTabata)!;
          s.timers.run = TimerRun(kind: RunKind.workout, refId: tabata.id, name: tabata.name, segments: TimerEngine.flatten(tabata.nodes), startedAt: demoNow.subtract(const Duration(seconds: 366)), finishSound: tabata.finishSound);
          s.timer.restore();
          await tester.pump();
          await tester.tap(find.textContaining(tr('Trabajo · 0:14', 'Work · 0:14')));
          await settle(tester);
          expect(find.byType(RunnerScreen), findsOneWidget);
          expect(find.text(tr('Ronda 3 de 8 · Serie 2 de 4', 'Round 3 of 8 · Set 2 of 4')), findsOneWidget);
          await takeStoreShot(tester, device, lang, '04-intervalos');

          s.timer.stop();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          s.dispose();
          dir.deleteSync(recursive: true);
        });
        expect(errors, isEmpty, reason: errors.join('\n----\n'));
      }, variant: TargetPlatformVariant.only(device.platform), timeout: const Timeout(Duration(minutes: 4)));
    }
  }
}
