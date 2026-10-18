@Tags(<String>['screenshots'])
library;

// Capturas de tienda de Clave: pantallas reales con los datos de ejemplo de
// test/store/clave_demo.dart, en teléfono y tableta de Android y en iPhone y
// iPad, en español e inglés. Se ejecutan con `flutter test --tags screenshots`.

import 'dart:math' as math;

import 'package:clave/app.dart';
import 'package:clave/audio/click_synth.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/core/settings.dart';
import 'package:clave/music/notes.dart';
import 'package:clave/ui/metronome/metronome_screen.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store/clave_demo.dart';
import 'store/store_shots.dart';
import 'support/fakes.dart';

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

Future<void> _goTab(WidgetTester tester, String label) async {
  Finder f = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  if (f.evaluate().isEmpty) {
    f = find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
  }
  await tester.tap(f.first);
  await _settle(tester);
}

void main() {
  for (final StoreDevice device in StoreDevice.all) {
    for (final String lang in storeLanguages) {
      testWidgets('Capturas de Clave en ${device.id} ($lang)', (WidgetTester tester) async {
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
        // Sábado por la tarde, hora de práctica: el reloj de la app avanza con
        // el tiempo simulado de la prueba a partir de esa hora.
        final Clock outer = clock;
        final DateTime fakeStart = outer.now();
        final DateTime demoNow = DateTime(2026, 10, 17, 18, 32);
        await withClock(Clock(() => demoNow.add(outer.now().difference(fakeStart))), () async {
          final AppSettings settings = AppSettings()
            ..language = lang
            ..themeMode = 'light'
            ..instrumentId = 'guitarra'
            ..notation = es ? Notation.solfeo : Notation.english;
          // El micrófono de prueba tiene permiso: el afinador se muestra
          // escuchando y las muestras llegan con Tuner.feed.
          final TestServices t = TestServices(settings: settings);
          final DateTime now = clock.now();
          await tester.runAsync(() async {
            await t.services.state.load();
            await seedClaveDemo(t.services.state, t.services.practice, spanish: es, now: now);
          });

          await tester.pumpWidget(storeShotRoot(ClaveApp(services: t.services)));
          await _settle(tester);

          // 1. Afinador: la cuerda La de la guitarra sube hasta quedar afinada
          // (de -14 a -1 cents) y se sostiene un momento.
          const double a2 = 110.0;
          final SustainedString string = SustainedString();
          t.services.tuner.feed(string.next(a2 * math.pow(2, -14 / 1200).toDouble(), 8192));
          for (int i = 0; i < 40; i++) {
            final double cents = i < 28 ? -14 + 13 * (i / 27) : -1;
            t.services.tuner.feed(string.next(a2 * math.pow(2, cents / 1200).toDouble(), 2048));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
            await tester.pump();
          }
          await takeStoreShot(tester, device, lang, '01-afinador');

          // 2. Metrónomo en marcha: 4/4 a 96 con corcheas.
          t.services.metronome.setConfig(const RhythmConfig(bpm: 96, subdivision: 2, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.accent, BeatMode.normal], sound: ClickSound.madera));
          await _goTab(tester, tr('Metrónomo', 'Metronome'));
          await tester.tap(find.text(tr('Iniciar', 'Start')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1310));
          await takeStoreShot(tester, device, lang, '02-metronomo', settle: false);
          await tester.tap(find.text(tr('Parar', 'Stop')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // 3. Preajustes y setlists.
          final Finder presets = find.text(tr('Preajustes', 'Presets'));
          // Las pestañas ocultas siguen en el árbol: se desplaza la lista del metrónomo.
          final Finder metronomeList = find.descendant(of: find.byType(MetronomeScreen), matching: find.byType(Scrollable)).first;
          await tester.scrollUntilVisible(presets, 200, scrollable: metronomeList);
          await tester.tap(presets);
          await _settle(tester);
          await tester.tap(find.textContaining(tr('Ensayo del sábado', 'Saturday rehearsal')));
          await _settle(tester);
          await takeStoreShot(tester, device, lang, '03-preajustes');
          await tester.tap(find.byType(BackButton));
          await _settle(tester);

          // 4. Bordón en Re con su quinta pura.
          await _goTab(tester, tr('Tono', 'Drone'));
          await tester.tap(find.widgetWithText(ChoiceChip, es ? 'Re' : 'D').first);
          await tester.pump();
          await tester.tap(find.byType(Switch).first);
          await tester.pump();
          await tester.tap(find.text(tr('Sonar', 'Play')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await takeStoreShot(tester, device, lang, '04-bordon', settle: false);
          await tester.tap(find.text(tr('Parar', 'Stop')));
          await tester.pump(const Duration(milliseconds: 300));

          // 5. Grabadora con tomas en carpetas.
          await _goTab(tester, tr('Grabar', 'Record'));
          await takeStoreShot(tester, device, lang, '05-grabadora');

          // 6. Registro de práctica.
          await _goTab(tester, tr('Práctica', 'Practice'));
          await takeStoreShot(tester, device, lang, '06-practica');

          await t.shutdown(tester);
          await tester.runAsync(() => t.services.store.flush());
        });
        expect(errors, isEmpty, reason: errors.join('\n----\n'));
      }, variant: TargetPlatformVariant.only(device.platform), timeout: const Timeout(Duration(minutes: 4)));
    }
  }
}
