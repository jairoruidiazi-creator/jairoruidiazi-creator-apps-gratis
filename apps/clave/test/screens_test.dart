// Todas las pantallas principales en teléfonos pequeños y con letra grande
// (G5), y las guías de accesibilidad en los dos temas (G7).

import 'dart:math' as math;

import 'package:clave/app.dart';
import 'package:clave/ui/drone/drone_screen.dart';
import 'package:clave/ui/metronome/metronome_screen.dart';
import 'package:clave/ui/tuner/tuner_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const List<String> tabsEs = <String>['Afinador', 'Metrónomo', 'Tono', 'Grabar', 'Práctica'];

Float32List aString(double hz) {
  final Float32List out = Float32List(8192);
  for (int i = 0; i < out.length; i++) {
    final double t = i / 44100;
    out[i] = 0.3 * (math.sin(2 * math.pi * hz * t) + 0.5 * math.sin(4 * math.pi * hz * t)) / 1.5;
  }
  return out;
}

/// La lista desplazable principal de una pantalla (las pestañas ocultas
/// siguen en el árbol: `find.byType(Scrollable).first` sería la del afinador).
Finder mainScrollable(Type screen) => find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first;

/// Vuelve atrás con la flecha de la barra (pageBack busca el texto "Back"
/// y la app está en español).
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await tester.pumpAndSettle();
}

Future<void> goTab(WidgetTester tester, String label) async {
  // En el teléfono, la barra inferior; en tableta, el riel lateral.
  final Finder bar = find.widgetWithText(NavigationDestination, label);
  await tester.tap(bar.evaluate().isNotEmpty ? bar : find.descendant(of: find.byType(NavigationRail), matching: find.text(label)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

List<FlutterErrorDetails> watchErrors() {
  final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    errors.add(d);
    previous?.call(d);
  };
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

String report(List<FlutterErrorDetails> errors) => errors.map((FlutterErrorDetails d) => d.toString()).join('\n----\n');

void useScreen(WidgetTester tester, Size size, {double textScale = 1}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// La app con datos, el tiple en el afinador y una lectura en pantalla.
Future<TestServices> openApp(WidgetTester tester, {bool dark = false, bool micGranted = true}) async {
  final TestServices t = TestServices(micGranted: micGranted);
  seedSample(t);
  t.services.settings
    ..instrumentId = 'tiple'
    ..themeMode = dark ? 'dark' : 'light';
  await t.services.settings.save();
  await tester.pumpWidget(ClaveApp(services: t.services));
  await tester.pump();
  if (micGranted) {
    t.services.tuner.feed(aString(146.83)); // Re3, la cuerda entorchada del 4.º orden
    await tester.pump();
  }
  return t;
}

void main() {
  for (final Size size in <Size>[const Size(360, 640), const Size(375, 667)]) {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('Sin desbordes en ${size.width.toInt()} × ${size.height.toInt()} con letra × $scale (G5)', (WidgetTester tester) async {
        useScreen(tester, size, textScale: scale);
        final List<FlutterErrorDetails> errors = watchErrors();
        final TestServices t = await openApp(tester);
        expect(t.services.tuner.reading, isNotNull);
        expect(errors, isEmpty, reason: 'afinador: ${report(errors)}');
        await tester.tap(find.text('Ajustar'));
        await tester.pumpAndSettle();
        expect(errors, isEmpty, reason: 'ajustes del afinador: ${report(errors)}');
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        for (final String tab in tabsEs.skip(1)) {
          await goTab(tester, tab);
          expect(errors, isEmpty, reason: '$tab: ${report(errors)}');
        }
        // Metrónomo en marcha, con péndulo y con número grande.
        await goTab(tester, 'Metrónomo');
        await tester.tap(find.text('Iniciar'));
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tap(find.byTooltip('Ver el número grande'));
        await tester.pump(const Duration(milliseconds: 700));
        expect(errors, isEmpty, reason: 'metrónomo en marcha: ${report(errors)}');
        await tester.tap(find.text('Parar'));
        await tester.pump();
        // Preajustes, ajustes y calibración.
        await tester.scrollUntilVisible(find.text('Preajustes'), 200, scrollable: mainScrollable(MetronomeScreen));
        // ensureVisible salta sin dibujar: hace falta un cuadro antes de tocar.
        await tester.pumpAndSettle();
        await tester.tap(find.text('Preajustes'));
        await tester.pumpAndSettle();
        expect(errors, isEmpty, reason: 'preajustes: ${report(errors)}');
        await goBack(tester);
        await tester.tap(find.byTooltip('Ajustes'));
        await tester.pumpAndSettle();
        expect(errors, isEmpty, reason: 'ajustes: ${report(errors)}');
        await tester.scrollUntilVisible(find.text('Calibrar con toques'), 200, scrollable: find.byType(Scrollable).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Calibrar con toques'));
        await tester.pumpAndSettle();
        expect(errors, isEmpty, reason: 'calibración: ${report(errors)}');
        await goBack(tester);
        await goBack(tester);
        expect(errors, isEmpty, reason: report(errors));
        await t.shutdown(tester);
      });
    }
  }

  testWidgets('Sin permiso de micrófono, la tarjeta del afinador cabe en 360 × 640 con letra × 1,3 (G5)', (WidgetTester tester) async {
    useScreen(tester, const Size(360, 640), textScale: 1.3);
    final List<FlutterErrorDetails> errors = watchErrors();
    final TestServices t = await openApp(tester, micGranted: false);
    expect(find.text('Permitir micrófono'), findsOneWidget);
    expect(errors, isEmpty, reason: report(errors));
    await t.shutdown(tester);
  });

  testWidgets('Teclado: en 360 dp cabe una octava entera de teclas de 48 dp y cada tecla tiene nombre (G7)', (WidgetTester tester) async {
    useScreen(tester, const Size(360, 640));
    final SemanticsHandle handle = tester.ensureSemantics();
    final TestServices t = await openApp(tester);
    await goTab(tester, 'Tono');
    await tester.scrollUntilVisible(find.byType(DroneKeyboard), 200, scrollable: mainScrollable(DroneScreen));
    await tester.pumpAndSettle();
    for (final String name in <String>['Do 4', 'Do sostenido 4', 'Re 4', 'Mi 4', 'Fa 4', 'Sol 4', 'La 4', 'La sostenido 4', 'Si 4']) {
      final Finder key = find.bySemanticsLabel(name);
      expect(key, findsOneWidget, reason: name);
      final Rect r = tester.getSemantics(key).rect;
      expect(r.width, greaterThanOrEqualTo(48), reason: name);
      expect(r.height, greaterThanOrEqualTo(48), reason: name);
    }
    // Las flechas mueven la ventana una octava.
    await tester.tap(find.byTooltip('Notas más agudas'));
    await tester.pump();
    expect(find.bySemanticsLabel('Do 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Do 4'), findsNothing);
    // Con el lector, tocar la tecla la hace sonar.
    tester.semantics.tap(find.semantics.byLabel('La 5'));
    await tester.pump();
    expect(t.services.drone.pressedKeys, <int>{81});
    await tester.pump(const Duration(seconds: 1));
    expect(t.services.drone.pressedKeys, isEmpty);
    handle.dispose();
    await t.shutdown(tester);
  });

  testWidgets('Con clarinete en Si♭, el bordón y el teclado usan la nota escrita y suenan un tono abajo (M5)', (WidgetTester tester) async {
    useScreen(tester, const Size(375, 667));
    final SemanticsHandle handle = tester.ensureSemantics();
    final TestServices t = await openApp(tester);
    t.services.settings
      ..instrumentId = 'clarinete'
      ..transposition = 2;
    await t.services.settings.save();
    await goTab(tester, 'Tono');
    Finder inDrone(Finder f) => find.descendant(of: find.byType(DroneScreen), matching: f);
    // El bordón suena La3: para el clarinete es un Si3 escrito.
    expect(t.services.drone.droneMidi, 57);
    expect(inDrone(find.text('Si3')), findsOneWidget);
    // El chip "Re" pide un Re escrito, que suena Do.
    await tester.tap(inDrone(find.widgetWithText(ChoiceChip, 'Re')).first);
    await tester.pump();
    expect(t.services.drone.droneMidi, 48);
    expect(inDrone(find.text('Re3')), findsOneWidget);
    // Las teclas se nombran por la nota escrita y suenan la real.
    await tester.scrollUntilVisible(find.byType(DroneKeyboard), 200, scrollable: mainScrollable(DroneScreen));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('Do 4'));
    await tester.pump();
    expect(t.services.drone.pressedKeys, <int>{58});
    await tester.pump(const Duration(seconds: 1));
    handle.dispose();
    await t.shutdown(tester);
  });

  testWidgets('Una nota bajo el rango del perfil se explica, también al lector, y se ofrece Cromático (4.ª ronda, M3)', (WidgetTester tester) async {
    useScreen(tester, const Size(375, 667));
    final SemanticsHandle handle = tester.ensureSemantics();
    final TestServices t = TestServices(micEnabled: false);
    t.services.settings.instrumentId = 'violin';
    await t.services.settings.save();
    await tester.pumpWidget(ClaveApp(services: t.services));
    await tester.pump();
    for (int i = 0; i < 7; i++) {
      t.services.tuner.feed(aString(65.41)); // Do2: un violonchelo, no un violín
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Suena más grave que el rango de Violín · usar Cromático'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('más grave que el rango de Violín')), findsWidgets);
    await tester.tap(find.text('Usar Cromático'));
    await tester.pump();
    expect(t.services.settings.instrumentId, 'cromatico');
    expect(t.services.tuner.instrument.id, 'cromatico');
    t.services.tuner.feed(aString(65.41));
    await tester.pump();
    expect(t.services.tuner.reading?.note.midi, 36);
    expect(find.textContaining('más grave que el rango'), findsNothing);
    handle.dispose();
    await t.shutdown(tester);
  });

  for (final Size size in <Size>[const Size(360, 640), const Size(640, 360)]) {
    testWidgets('Con letra × 2 en ${size.width.toInt()} × ${size.height.toInt()}, los avisos del afinador se ven enteros o se llega a ellos desplazando (final, m4)', (WidgetTester tester) async {
      useScreen(tester, size, textScale: 2.0);
      final List<FlutterErrorDetails> errors = watchErrors();
      final TestServices t = TestServices(micEnabled: false);
      t.services.settings.instrumentId = 'violin';
      await t.services.settings.save();
      await tester.pumpWidget(ClaveApp(services: t.services));
      await tester.pump();
      final Rect screen = Offset.zero & size;
      // El aviso está dentro de una zona desplazable que cabe en la pantalla,
      // y desplazando se llega a su primera y a su última línea (con la
      // tipografía de prueba, de glifos cuadrados, puede ser más alto que la
      // pantalla).
      Future<void> reachable(String text) async {
        final Finder f = find.text(text);
        expect(f, findsOneWidget);
        final Finder scroll = find.ancestor(of: f, matching: find.byType(Scrollable)).first;
        final Rect viewport = tester.getRect(scroll);
        expect(viewport.top >= screen.top && viewport.bottom <= screen.bottom + 0.5 && viewport.left >= screen.left && viewport.right <= screen.right + 0.5, isTrue, reason: 'zona desplazable en $viewport');
        for (final double alignment in <double>[0, 1]) {
          await Scrollable.ensureVisible(tester.element(f), alignment: alignment);
          await tester.pump();
          final Rect r = tester.getRect(f);
          expect(r.left >= viewport.left - 0.5 && r.right <= viewport.right + 0.5, isTrue, reason: '$text en $r, zona $viewport');
          if (alignment == 0) {
            expect(r.top >= viewport.top - 0.5 && r.top < viewport.bottom, isTrue, reason: 'primera línea de «$text»: $r, zona $viewport');
          } else {
            expect(r.bottom <= viewport.bottom + 0.5 && r.bottom > viewport.top, isTrue, reason: 'última línea de «$text»: $r, zona $viewport');
          }
        }
      }

      // Nota bajo el rango, sostenida.
      for (int i = 0; i < 7; i++) {
        t.services.tuner.feed(aString(65.41));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await reachable('Suena más grave que el rango de Violín · usar Cromático');
      await reachable('Usar Cromático');
      // Residuo con el bordón (La3 con quinta, que se oye en la señal: lo que
      // suena tiene periodo de La2 y en La2 no hay energía).
      t.services.settings.instrumentId = 'voz';
      await t.services.settings.save();
      t.services.tuner.ownTones = () => <double>[220, 330];
      final Float32List mixture = Float32List.fromList(<double>[for (int i = 0; i < 8192; i++) 0.15 * math.sin(2 * math.pi * 220 * i / 44100) + 0.1 * math.sin(2 * math.pi * 330 * i / 44100 + 1)]);
      for (int i = 0; i < 8; i++) {
        t.services.tuner.feed(mixture);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await reachable('Lo que se oye puede ser la mezcla con el bordón, las teclas o el acorde de la app. Apágalos para afinar esta nota.');
      expect(errors, isEmpty, reason: report(errors));
      await t.shutdown(tester);
    });
  }

  testWidgets('El afinador anuncia la nota al lector sin saturarlo: como mucho un aviso cada 1,1 s (G7)', (WidgetTester tester) async {
    useScreen(tester, const Size(360, 640));
    final SemanticsHandle handle = tester.ensureSemantics();
    final TestServices t = TestServices();
    await tester.pumpWidget(ClaveApp(services: t.services));
    await tester.pump();
    final Finder live = find.descendant(of: find.byType(TunerScreen), matching: find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.liveRegion == true));
    String label() => tester.getSemantics(live).label;
    expect(label(), 'Toca una nota');
    final List<int> changes = <int>[];
    String last = label();
    // Una nota distinta cada 100 ms durante 2 s.
    for (int i = 0; i < 20; i++) {
      t.services.tuner.feed(aString(220.0 * math.pow(2, i / 12).toDouble()));
      await tester.pump(const Duration(milliseconds: 100));
      final String now = label();
      if (now != last) {
        changes.add(i * 100);
        last = now;
      }
    }
    expect(changes, isNotEmpty);
    for (int i = 1; i < changes.length; i++) {
      expect(changes[i] - changes[i - 1], greaterThanOrEqualTo(1000), reason: 'avisos en $changes ms');
    }
    expect(changes.length, lessThanOrEqualTo(2));
    // Al quedarse en una nota, el aviso llega con ella.
    for (int i = 0; i < 12; i++) {
      t.services.tuner.feed(aString(220.0 * math.pow(2, 19 / 12).toDouble()));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(label(), startsWith('Mi 5'));
    handle.dispose();
    await t.shutdown(tester);
  });

  testWidgets('El lector no repite el mismo aviso antes de 6 s aunque alterne con lecturas, y la etiqueta sigue a la pantalla (N2, O1)', (WidgetTester tester) async {
    useScreen(tester, const Size(360, 640));
    final SemanticsHandle handle = tester.ensureSemantics();
    final TestServices t = TestServices();
    t.services.settings.instrumentId = 'violin';
    await t.services.settings.save();
    await tester.pumpWidget(ClaveApp(services: t.services));
    await tester.pump();
    final Finder region = find.byKey(const ValueKey<String>('tuner-live'));
    String label() => tester.getSemantics(region).label;
    bool live() => tester.widget<Semantics>(region).properties.liveRegion ?? false;
    const String notice = 'Suena más grave que el rango de Violín · usar Cromático';
    Future<void> play(double hz, int frames) async {
      for (int i = 0; i < frames; i++) {
        t.services.tuner.feed(aString(hz));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await play(65.41, 15); // Do2 con Violín: el aviso
    expect(label(), notice);
    expect(live(), isTrue);
    await play(440, 15); // La4: la nota
    expect(label(), startsWith('La 4'));
    expect(live(), isTrue);
    await play(65.41, 15); // el aviso otra vez, a menos de 6 s del primero
    expect(find.text(notice), findsOneWidget);
    // La etiqueta sigue a la pantalla, pero la región deja de estar en vivo:
    // el lector no lo vuelve a decir.
    expect(label(), notice);
    expect(live(), isFalse, reason: 'el mismo aviso no se vuelve a anunciar antes de 6 s');
    await play(440, 15); // otra nota: se anuncia y la región vuelve a estar en vivo
    expect(label(), startsWith('La 4'));
    expect(live(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await play(65.41, 20); // ya pasaron más de 6 s desde el primer aviso
    expect(label(), notice);
    expect(live(), isTrue);
    handle.dispose();
    await t.shutdown(tester);
  });

  for (final Size size in <Size>[const Size(360, 640), const Size(800, 1280), const Size(1280, 800)]) {
    for (final bool dark in <bool>[false, true]) {
      testWidgets('Guías de accesibilidad de Android e iOS en cada pantalla, ${size.width.toInt()} × ${size.height.toInt()}, tema ${dark ? 'oscuro' : 'claro'} (G7, O4)', (WidgetTester tester) async {
        useScreen(tester, size);
        final SemanticsHandle handle = tester.ensureSemantics();
        final TestServices t = await openApp(tester, dark: dark);
        Future<void> check(String where) async {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: where);
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline), reason: where);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: where);
          await expectLater(tester, meetsGuideline(textContrastGuideline), reason: where);
        }

        for (final String tab in tabsEs) {
          await goTab(tester, tab);
          await check(tab);
        }
        await tester.tap(find.byTooltip('Ajustes'));
        await tester.pumpAndSettle();
        await check('Ajustes');
        await goBack(tester);
        handle.dispose();
        await t.shutdown(tester);
      });
    }
  }
}
