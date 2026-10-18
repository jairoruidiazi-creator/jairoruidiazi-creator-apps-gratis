// Todas las pantallas principales en teléfonos pequeños y con letra grande
// (G5), y las guías de accesibilidad en los dos temas (G7).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clave/app.dart';
import 'package:clave/ui/drone/drone_screen.dart';
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

Future<void> goTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
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
        await tester.scrollUntilVisible(find.text('Preajustes'), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Preajustes'));
        await tester.pumpAndSettle();
        expect(errors, isEmpty, reason: 'preajustes: ${report(errors)}');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Ajustes'));
        await tester.pumpAndSettle();
        expect(errors, isEmpty, reason: 'ajustes: ${report(errors)}');
        await tester.scrollUntilVisible(find.text('Calibrar con toques'), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Calibrar con toques'));
        await tester.pumpAndSettle();
        expect(errors, isEmpty, reason: 'calibración: ${report(errors)}');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(find.byType(DroneKeyboard), 200, scrollable: find.byType(Scrollable).first);
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

  for (final bool dark in <bool>[false, true]) {
    testWidgets('Guías de accesibilidad de Android e iOS en cada pantalla, tema ${dark ? 'oscuro' : 'claro'} (G7)', (WidgetTester tester) async {
      useScreen(tester, const Size(360, 640));
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
      await tester.pageBack();
      await tester.pumpAndSettle();
      handle.dispose();
      await t.shutdown(tester);
    });
  }
}
