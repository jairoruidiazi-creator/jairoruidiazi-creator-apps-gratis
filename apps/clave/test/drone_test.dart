// Bordón, teclado y acordes (M4): quinta pura, ganancia repartida, ondas sin
// aliasing y notas que siguen la referencia.

import 'package:clave/audio/audio_engine.dart';
import 'package:clave/audio/drone.dart';
import 'package:clave/music/notes.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

double totalVolume(SilentEngine e) => e.volumes.values.fold<double>(0, (double a, double b) => a + b);

void main() {
  test('La quinta del bordón es pura (3:2), también con temperamento', () {
    fakeAsync((FakeAsync async) {
      final SilentEngine e = SilentEngine();
      final DroneController d = DroneController(e)
        ..setPitch(const PitchSettings(a4: 442, temperament: Temperament.meantone))
        ..setDroneMidi(50);
      d.setFifth(true);
      d.startDrone();
      async.flushMicrotasks();
      final List<double> f = e.frequencies.values.toList()..sort();
      expect(f, hasLength(2));
      expect(f[1] / f[0], closeTo(1.5, 1e-12));
      expect(f[0], closeTo(d.frequencyOf(50), 1e-9));
      expect(d.soundingFrequencies, hasLength(2));
      d.stopAll();
      async.flushMicrotasks();
      expect(e.frequencies, isEmpty);
    });
  });

  test('La ganancia se reparte: bordón, quinta, teclas y acorde nunca suman más que el bordón solo', () {
    fakeAsync((FakeAsync async) {
      final SilentEngine e = SilentEngine();
      final DroneController d = DroneController(e)..setVolume(1);
      d.startDrone();
      async.flushMicrotasks();
      final double alone = totalVolume(e);
      expect(alone, closeTo(1.5 * shapeGain(WaveShape.sine), 1e-9));
      d.setFifth(true);
      for (final int k in <int>[60, 64, 67, 72, 76]) {
        d.keyDown(k);
      }
      d.playChord(48, 'M7');
      async.flushMicrotasks();
      expect(e.volumes.length, 2 + 5 + 4);
      expect(totalVolume(e), lessThanOrEqualTo(alone + 1e-9));
      // La quinta pesa menos que el bordón.
      final List<double> v = e.volumes.values.toList()..sort();
      expect(v.first, greaterThan(0));
      d.stopAll();
      async.flushMicrotasks();
    });
  });

  test('Las ondas con armónicos pasan a seno donde se doblarían (sin aliasing)', () {
    expect(bandLimitedShape(WaveShape.saw, 440), WaveShape.saw);
    expect(bandLimitedShape(WaveShape.saw, 2000), WaveShape.sine);
    expect(bandLimitedShape(WaveShape.square, 1500), WaveShape.sine);
    expect(bandLimitedShape(WaveShape.triangle, 2500), WaveShape.triangle);
    expect(bandLimitedShape(WaveShape.triangle, 3500), WaveShape.sine);
    fakeAsync((FakeAsync async) {
      final SilentEngine e = SilentEngine();
      final DroneController d = DroneController(e)..setShape(WaveShape.saw);
      d.keyDown(100); // Mi7, 2637 Hz
      d.keyDown(57);
      async.flushMicrotasks();
      final Map<double, WaveShape> byFreq = <double, WaveShape>{for (final Tone t in e.frequencies.keys) e.frequencies[t]!: t.actual};
      expect(byFreq[d.frequencyOf(100)], WaveShape.sine);
      expect(byFreq[d.frequencyOf(57)], WaveShape.saw);
      d.stopAll();
      async.flushMicrotasks();
    });
  });

  test('Teclas y acordes siguen la referencia La4 y se reafinan al cambiarla', () {
    fakeAsync((FakeAsync async) {
      final SilentEngine e = SilentEngine();
      final DroneController d = DroneController(e);
      d.keyDown(69);
      d.playChord(57, 'M');
      async.flushMicrotasks();
      expect(e.frequencies.values, contains(closeTo(440, 1e-9)));
      d.setPitch(const PitchSettings(a4: 432));
      expect(e.frequencies.values, contains(closeTo(432, 1e-9)));
      expect(e.frequencies.values, contains(closeTo(216, 1e-9)));
      expect(e.frequencies.values.any((double f) => (f - 440).abs() < 1e-6), isFalse);
      d.stopAll();
      async.flushMicrotasks();
    });
  });

  test('Con "sostener" las teclas siguen sonando hasta soltar el pedal', () {
    fakeAsync((FakeAsync async) {
      final SilentEngine e = SilentEngine();
      final DroneController d = DroneController(e)..setSustain(true);
      d.keyDown(60);
      async.flushMicrotasks();
      d.keyUp(60);
      async.flushMicrotasks();
      expect(d.pressedKeys, <int>{60});
      d.setSustain(false);
      async.flushMicrotasks();
      expect(d.pressedKeys, isEmpty);
      expect(e.frequencies, isEmpty);
      // Un toque del lector de pantalla suena un momento y se suelta solo.
      d.tapKey(64);
      async.flushMicrotasks();
      expect(d.pressedKeys, <int>{64});
      async.elapse(const Duration(seconds: 1));
      expect(d.pressedKeys, isEmpty);
    });
  });
}
