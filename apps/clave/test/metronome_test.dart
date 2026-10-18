// Metrónomo con el motor mudo y tiempo simulado: retraso del audio (G2),
// vibración (G3), péndulo (M3), avisos (M10), golpeteo y calibración.

import 'package:clave/audio/audio_engine.dart';
import 'package:clave/audio/latency_calibration.dart';
import 'package:clave/audio/metronome.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('Metrónomo', () {
    test('Arranca, sigue el tempo y para', () {
      fakeAsync((FakeAsync async) {
        final Metronome m = Metronome(SilentEngine());
        expect(m.running, isFalse);
        m.start();
        async.flushMicrotasks();
        expect(m.running, isTrue);
        m.setBpm(140);
        expect(m.config.bpm, 140);
        m.stop();
        async.flushMicrotasks();
        expect(m.running, isFalse);
        expect(m.state.running, isFalse);
        m.dispose();
      });
    });

    test('La animación y la vibración van con lo que se oye: el retraso las corre (G2, G3)', () {
      for (final int delay in <int>[0, 200]) {
        fakeAsync((FakeAsync async) {
          final FakeHaptics h = FakeHaptics();
          final Metronome m = Metronome(SilentEngine(), haptics: h)
            ..hapticsEnabled = true
            ..audioDelayMs = delay
            ..setConfig(const RhythmConfig(bpm: 120));
          m.start();
          async.flushMicrotasks();
          // Los pulsos suenan a los 0,05 s, 0,55 s, 1,05 s... del audio consumido.
          async.elapse(const Duration(milliseconds: 650));
          if (delay == 0) {
            expect(m.beat.value.beat, 1);
            expect(h.pulses, <bool>[true, false]);
          } else {
            // Con 200 ms de retraso todavía se oye el primer pulso.
            expect(m.beat.value.beat, 0);
            expect(h.pulses, <bool>[true]);
          }
          async.elapse(const Duration(milliseconds: 1500));
          // 2,15 s: cinco pulsos (cuatro con el retraso); el quinto abre el
          // segundo compás con acento.
          expect(h.pulses.length, delay == 0 ? 5 : 4);
          expect(h.pulses.first, isTrue);
          if (delay == 0) {
            expect(h.pulses, <bool>[true, false, false, false, true]);
          }
          m.stop();
          async.flushMicrotasks();
          m.dispose();
        });
      }
    });

    test('Sin la vibración activada no vibra', () {
      fakeAsync((FakeAsync async) {
        final FakeHaptics h = FakeHaptics();
        final Metronome m = Metronome(SilentEngine(), haptics: h)..setConfig(const RhythmConfig(bpm: 240));
        m.start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(h.pulses, isEmpty);
        m.stop();
        async.flushMicrotasks();
        m.dispose();
      });
    });

    test('El péndulo alterna en compases impares y su fase es la del pulso, con swing (M3)', () {
      fakeAsync((FakeAsync async) {
        final Metronome m = Metronome(SilentEngine())
          ..setConfig(const RhythmConfig(bpm: 60, beatsPerBar: 3, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal], subdivision: 2, swing: 1));
        m.start();
        async.flushMicrotasks();
        final List<int> counts = <int>[];
        double maxPhaseJump = 0;
        double last = 0;
        int lastCount = -1;
        for (int i = 0; i < 400; i++) {
          async.elapse(const Duration(milliseconds: 16));
          final BeatState b = m.beat.value;
          if (!b.running) {
            continue;
          }
          if (b.beatCount != lastCount) {
            counts.add(b.beatCount);
            lastCount = b.beatCount;
          } else {
            // Dentro del pulso la fase avanza sin saltos, aunque pase la corchea con swing.
            maxPhaseJump = (b.phase - last).abs() > maxPhaseJump ? (b.phase - last).abs() : maxPhaseJump;
          }
          last = b.phase;
        }
        // Pulsos seguidos 0, 1, 2, 3, 4, 5...: el compás de 3 no reinicia la cuenta.
        expect(counts.take(6).toList(), <int>[0, 1, 2, 3, 4, 5]);
        expect(maxPhaseJump, lessThan(0.05));
        m.stop();
        async.flushMicrotasks();
        m.dispose();
      });
    });

    test('El pulso de la animación no avisa a los oyentes del metrónomo (M10)', () {
      fakeAsync((FakeAsync async) {
        final Metronome m = Metronome(SilentEngine());
        int notifications = 0;
        int beats = 0;
        m.addListener(() => notifications++);
        m.beat.addListener(() => beats++);
        m.start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(beats, greaterThan(60));
        expect(notifications, 1);
        m.stop();
        async.flushMicrotasks();
        m.dispose();
      });
    });

    test('Golpear el tempo promedia los toques', () {
      fakeAsync((FakeAsync async) {
        final Metronome m = Metronome(SilentEngine());
        expect(m.tap(), isNull);
        for (int i = 0; i < 4; i++) {
          async.elapse(const Duration(milliseconds: 500));
          m.tap();
        }
        expect(m.config.bpm, 120);
        // Una pausa larga empieza otra cuenta.
        async.elapse(const Duration(seconds: 3));
        expect(m.tap(), isNull);
        m.dispose();
      });
    });
  });

  group('Calibración por toques (G2)', () {
    test('La diferencia de cada toque se mide contra su clic', () {
      const double period = 60 / 90;
      expect(LatencyCalibration.residualFor(0.05 + 3 * period + 0.18, firstClick: 0.05, period: period), closeTo(0.18, 1e-9));
      // Un toque un poco adelantado cuenta contra el mismo clic.
      expect(LatencyCalibration.residualFor(0.05 + 3 * period - 0.04, firstClick: 0.05, period: period), closeTo(-0.04, 1e-9));
      expect(LatencyCalibration.residualFor(0.0, firstClick: 0.5, period: period).isNaN, isTrue);
    });

    test('Mediana sin los toques sueltos; hacen falta ocho parejos', () {
      final List<double> taps = <double>[0.18, 0.19, 0.17, 0.185, 0.175, 0.18, 0.2, 0.16];
      expect(LatencyCalibration.estimateDelayMs(taps.sublist(0, 7)), isNull);
      expect(LatencyCalibration.estimateDelayMs(taps), 180);
      expect(LatencyCalibration.estimateDelayMs(<double>[...taps, 0.45, -0.1]), 180);
      expect(LatencyCalibration.estimateDelayMs(<double>[0.0, 0.1, 0.2, 0.3, 0.4, 0.05, 0.15, 0.25]), isNull);
      // Toques adelantados: el retraso no baja de 0.
      expect(LatencyCalibration.estimateDelayMs(List<double>.filled(8, -0.03)), 0);
    });

    test('Con el motor mudo, tocar 150 ms después de cada clic da 150 ms', () {
      fakeAsync((FakeAsync async) {
        final LatencyCalibration cal = LatencyCalibration(SilentEngine());
        cal.start();
        async.flushMicrotasks();
        expect(cal.running, isTrue);
        const double period = 60 / LatencyCalibration.bpm;
        // El primer clic suena a los 0,05 s.
        async.elapse(const Duration(milliseconds: 200));
        for (int k = 0; k < 9; k++) {
          cal.tap();
          async.elapse(Duration(microseconds: (period * 1e6).round()));
        }
        expect(cal.taps, 9);
        expect(cal.resultMs, closeTo(150, 2));
        cal.stop();
        async.flushMicrotasks();
        expect(cal.running, isFalse);
      });
    });
  });
}
