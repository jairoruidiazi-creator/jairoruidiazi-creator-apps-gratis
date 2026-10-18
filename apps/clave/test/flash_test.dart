// Destello de pantalla del metrónomo dentro de WCAG 2.3.1 (segunda ronda,
// N-G1): apagado de entrada, como mucho 3 destellos por segundo, contraste
// suave y nada con "quitar animaciones".

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clave/app.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/core/settings.dart';
import 'package:clave/core/theme.dart';
import 'package:clave/ui/metronome/screen_flash.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const Key flashKey = ValueKey<String>('destello');

/// Un destello: cuándo empieza y su color.
class Onset {
  Onset(this.at, this.color);

  final Duration at;
  final Color color;
}

/// Arranca el metrónomo con [config] y anota, durante [seconds] de tiempo
/// simulado en pasos de 5 ms, cuándo se enciende el destello y su color.
Future<List<Onset>> recordFlashes(WidgetTester tester, RhythmConfig config, {bool dark = false, bool reduceMotion = false, int seconds = 4}) async {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final TestServices t = TestServices(settings: AppSettings()..themeMode = dark ? 'dark' : 'light');
  t.services.settings.flash = true;
  await t.services.settings.save();
  t.services.metronome.setConfig(config);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(ClaveApp(services: t.services, initialIndex: 1));
  await tester.pump();
  await tester.tap(find.text('Iniciar'));
  await tester.pump();
  final List<Onset> onsets = <Onset>[];
  bool wasOn = false;
  Duration now = Duration.zero;
  const Duration step = Duration(milliseconds: 5);
  while (now < Duration(seconds: seconds)) {
    await tester.pump(step);
    now += step;
    final Finder f = find.byKey(flashKey);
    final bool on = f.evaluate().isNotEmpty;
    if (on && !wasOn) {
      onsets.add(Onset(now, tester.widget<ColoredBox>(f).color));
    }
    wasOn = on;
  }
  await tester.tap(find.text('Parar'));
  await tester.pump();
  await t.shutdown(tester);
  return onsets;
}

/// La pantalla en píxeles RGBA (1 píxel por punto lógico).
Future<Uint8List> capture(WidgetTester tester, GlobalKey key) async {
  final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final Uint8List? bytes = await tester.runAsync<Uint8List?>(() async {
    final ui.Image img = await b.toImage();
    final ByteData? d = await img.toByteData();
    img.dispose();
    return d?.buffer.asUint8List();
  });
  return bytes!;
}

double _linear(int c) {
  final double v = c / 255;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// Luminancia relativa del píxel [i] (WCAG).
double luminanceAt(Uint8List rgba, int i) => 0.2126 * _linear(rgba[i * 4]) + 0.7152 * _linear(rgba[i * 4 + 1]) + 0.0722 * _linear(rgba[i * 4 + 2]);

/// El mayor número de destellos que empiezan dentro de un mismo segundo.
int maxPerSecond(List<Onset> onsets) {
  int best = 0;
  for (int i = 0; i < onsets.length; i++) {
    int n = 0;
    for (int j = i; j < onsets.length && onsets[j].at - onsets[i].at < const Duration(seconds: 1); j++) {
      n++;
    }
    if (n > best) {
      best = n;
    }
  }
  return best;
}

void main() {
  test('El destello viene apagado', () {
    expect(AppSettings().flash, isFalse);
  });

  test('Qué pulsos destellan según el tempo', () {
    const List<BeatMode> oneAccent = <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.normal];
    expect(ScreenFlash.beatsFor(const RhythmConfig(bpm: 120, beats: oneAccent), 120), FlashBeats.all);
    expect(ScreenFlash.beatsFor(const RhythmConfig(bpm: 170, beats: oneAccent), 170), FlashBeats.all);
    // 180 BPM son 3 pulsos por segundo justos: ya solo el acento.
    expect(ScreenFlash.beatsFor(const RhythmConfig(bpm: 180, beats: oneAccent), 180), FlashBeats.accents);
    expect(ScreenFlash.beatsFor(const RhythmConfig(bpm: 240, beats: oneAccent), 240), FlashBeats.accents);
    // Acentos en 1 y 3 a 400 BPM: 0,3 s entre acentos, no destella.
    expect(ScreenFlash.beatsFor(const RhythmConfig(bpm: 400, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.accent, BeatMode.normal]), 400), FlashBeats.none);
    // Compás de un pulso a 400 BPM: cada pulso es acento, tampoco.
    expect(ScreenFlash.beatsFor(const RhythmConfig(bpm: 400, beatsPerBar: 1, beats: <BeatMode>[BeatMode.accent]), 400), FlashBeats.none);
    // Pulsos en silencio no cuentan: 2 de 4 suenan a 240 BPM (0,5 s).
    expect(ScreenFlash.beatsFor(const RhythmConfig(bpm: 240, beats: <BeatMode>[BeatMode.accent, BeatMode.silent, BeatMode.normal, BeatMode.silent]), 240), FlashBeats.all);
  });

  test('El cambio de luminancia del destello es menor que el de un destello general, en los dos temas', () {
    for (final ThemeData theme in <ThemeData>[ClaveTheme.light(), ClaveTheme.dark()]) {
      final ColorScheme cs = theme.colorScheme;
      final ClavePalette pal = theme.extension<ClavePalette>()!;
      for (final Color tint in <Color>[Color.alphaBlend(pal.accent.withValues(alpha: 0.45), cs.surface), cs.primaryContainer]) {
        final Color c = ScreenFlash.overlay(tint, cs.surface);
        final double change = (Color.alphaBlend(c, cs.surface).computeLuminance() - cs.surface.computeLuminance()).abs();
        expect(change, lessThanOrEqualTo(ScreenFlash.maxLuminanceChange + 1e-6));
        expect(change, lessThan(0.1));
        expect(c.a, greaterThan(0), reason: 'se ve algo');
      }
    }
  });

  testWidgets('A 240 BPM: como mucho 3 destellos por segundo, solo en el acento y con contraste suave', (WidgetTester tester) async {
    final List<Onset> onsets = await recordFlashes(tester, const RhythmConfig(bpm: 240, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.normal]));
    // Un acento por segundo en 4/4 a 240.
    expect(onsets.length, inInclusiveRange(3, 5));
    expect(maxPerSecond(onsets), lessThanOrEqualTo(3));
    for (int i = 1; i < onsets.length; i++) {
      expect(onsets[i].at - onsets[i - 1].at, greaterThanOrEqualTo(const Duration(milliseconds: 950)));
    }
    final Color surface = ClaveTheme.light().colorScheme.surface;
    for (final Onset o in onsets) {
      final double change = (Color.alphaBlend(o.color, surface).computeLuminance() - surface.computeLuminance()).abs();
      expect(change, lessThan(0.1));
    }
  });

  for (final bool dark in <bool>[false, true]) {
    testWidgets('El tinte va detrás del contenido: en los píxeles reales nada cambia más de 0,06 de luminancia (tema ${dark ? 'oscuro' : 'claro'})', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final TestServices t = TestServices(settings: AppSettings()..themeMode = dark ? 'dark' : 'light');
      t.services.settings.flash = true;
      await t.services.settings.save();
      t.services.metronome.setConfig(const RhythmConfig(bpm: 60));
      final GlobalKey root = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: root, child: ClaveApp(services: t.services, initialIndex: 1)));
      await tester.pump();
      await tester.tap(find.text('Iniciar'));
      await tester.pump();
      for (int i = 0; i < 400 && find.byKey(flashKey).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(find.byKey(flashKey), findsOneWidget);
      final Uint8List on = await capture(tester, root);
      final Rect stop = tester.getRect(find.text('Parar'));
      // El mismo cuadro, sin destello (el tiempo no avanza).
      t.services.metronome.flashEnabled = false;
      tester.element(find.ancestor(of: find.byKey(flashKey), matching: find.byWidgetPredicate((Widget w) => w.runtimeType.toString() == '_BeatBuilder'))).markNeedsBuild();
      await tester.pump();
      expect(find.byKey(flashKey), findsNothing);
      final Uint8List off = await capture(tester, root);
      expect(on.length, off.length);
      final int width = 432;
      double maxChange = 0;
      double stopChange = 0;
      int changed = 0;
      for (int i = 0; i < on.length ~/ 4; i++) {
        final double d = (luminanceAt(on, i) - luminanceAt(off, i)).abs();
        if (d > maxChange) {
          maxChange = d;
        }
        if (d > 0.002) {
          changed++;
        }
        final double x = (i % width) + 0.5;
        final double y = (i ~/ width) + 0.5;
        if (stop.contains(Offset(x, y)) && d > stopChange) {
          stopChange = d;
        }
      }
      expect(maxChange, lessThanOrEqualTo(ScreenFlash.maxLuminanceChange + 0.01), reason: 'ningún píxel, tampoco botones ni números');
      expect(stopChange, lessThan(0.002), reason: 'el botón Parar no cambia');
      expect(changed, greaterThan(2000), reason: 'el destello se ve en el fondo');
      await tester.tap(find.text('Parar'));
      await tester.pump();
      await t.shutdown(tester);
    });
  }

  testWidgets('A 120 BPM destella en cada pulso: 2 por segundo', (WidgetTester tester) async {
    final List<Onset> onsets = await recordFlashes(tester, const RhythmConfig(bpm: 120), seconds: 3);
    expect(onsets.length, inInclusiveRange(5, 7));
    expect(maxPerSecond(onsets), lessThanOrEqualTo(3));
  });

  testWidgets('A 400 BPM con acentos en 1 y 3 no destella', (WidgetTester tester) async {
    final List<Onset> onsets = await recordFlashes(tester, const RhythmConfig(bpm: 400, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.accent, BeatMode.normal]), seconds: 2);
    expect(onsets, isEmpty);
  });

  testWidgets('Con "quitar animaciones" no destella', (WidgetTester tester) async {
    final List<Onset> onsets = await recordFlashes(tester, const RhythmConfig(bpm: 60), reduceMotion: true, seconds: 3);
    expect(onsets, isEmpty);
  });
}
