// Afinador sin interfaz: cuándo abre el micrófono (B2, M6), búfer viejo
// (M1), cuerda fijada y amortiguación (M2), capo (G9) y cuándo un sonido
// cuenta como práctica (B3).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clave/audio/click_synth.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/audio/tuner.dart';
import 'package:clave/music/instruments.dart';
import 'package:clave/music/notes.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Tono sostenido con armónicos y fase continua entre bloques.
class Sustained {
  final List<double> _phase = List<double>.filled(4, 0);
  static const List<double> _amps = <double>[1.0, 0.5, 0.3, 0.15];

  Float32List next(double hz, int n, {double amp = 0.3}) {
    final Float32List out = Float32List(n);
    for (int i = 0; i < n; i++) {
      double v = 0;
      for (int h = 0; h < _amps.length; h++) {
        _phase[h] += 2 * math.pi * hz * (h + 1) / 44100;
        if (_phase[h] > 2 * math.pi) {
          _phase[h] -= 2 * math.pi;
        }
        v += _amps[h] * math.sin(_phase[h]);
      }
      out[i] = amp * v / 1.95;
    }
    return out;
  }
}

double hzAt(int midi, double cents) => 440 * math.pow(2, (midi - 69 + cents / 100) / 12).toDouble();

void main() {
  group('Micrófono (B2)', () {
    test('Solo escucha con la pestaña activa, sin la grabadora y si la persona quiere', () {
      fakeAsync((FakeAsync async) {
        final FakeMic mic = FakeMic();
        final Tuner tuner = Tuner(mic: mic);
        expect(mic.open, isFalse);
        expect(tuner.status, MicStatus.off);
        tuner.setActive(true);
        async.flushMicrotasks();
        expect(mic.open, isTrue);
        expect(tuner.status, MicStatus.listening);
        tuner.setActive(false);
        async.flushMicrotasks();
        expect(mic.open, isFalse);
        expect(tuner.status, MicStatus.off);
        tuner.setActive(true);
        async.flushMicrotasks();
        expect(mic.open, isTrue);
        // La grabadora toma el micrófono.
        tuner.setMicBusy(true);
        async.flushMicrotasks();
        expect(mic.open, isFalse);
        expect(tuner.status, MicStatus.busy);
        tuner.setMicBusy(false);
        async.flushMicrotasks();
        expect(mic.open, isTrue);
        // El botón del micrófono.
        tuner.setUserEnabled(false);
        async.flushMicrotasks();
        expect(mic.open, isFalse);
        expect(tuner.status, MicStatus.off);
        tuner.setUserEnabled(true);
        async.flushMicrotasks();
        expect(mic.open, isTrue);
        expect(mic.starts, 4);
        expect(mic.stops, 3);
        // Cambios muy seguidos terminan en el último estado pedido.
        tuner
          ..setActive(false)
          ..setActive(true)
          ..setActive(false);
        async.flushMicrotasks();
        expect(mic.open, isFalse);
        tuner.dispose();
      });
    });

    test('Sin permiso explica primero y pide el permiso solo al tocar el botón (M6)', () {
      fakeAsync((FakeAsync async) {
        final FakeMic mic = FakeMic(granted: false);
        final Tuner tuner = Tuner(mic: mic);
        int asked = 0;
        tuner.onPermissionAsked = () => asked++;
        tuner.setActive(true);
        async.flushMicrotasks();
        expect(tuner.status, MicStatus.needsPermission);
        expect(mic.requests, 0, reason: 'no se muestra el diálogo del sistema sin explicarlo');
        tuner.requestPermission();
        async.flushMicrotasks();
        expect(mic.requests, 1);
        expect(asked, 1);
        expect(tuner.status, MicStatus.listening);
        tuner.dispose();
      });
    });

    test('Con el permiso negado queda en "denegado" (para ofrecer los ajustes)', () {
      fakeAsync((FakeAsync async) {
        final FakeMic mic = FakeMic(granted: false, grantOnRequest: false);
        final Tuner tuner = Tuner(mic: mic)..permissionAsked = true;
        tuner.setActive(true);
        async.flushMicrotasks();
        expect(tuner.status, MicStatus.denied);
        // Vuelve de los ajustes con el permiso dado.
        mic.granted = true;
        tuner.recheck();
        async.flushMicrotasks();
        expect(tuner.status, MicStatus.listening);
        tuner.dispose();
      });
    });
  });

  group('Lecturas', () {
    test('Una interrupción o un corte de muestras no deja una nota vieja (M1)', () {
      fakeAsync((FakeAsync async) {
        final FakeMic mic = FakeMic();
        final Tuner tuner = Tuner(mic: mic)..instrument = Instruments.byId('cromatico');
        final Sustained s = Sustained();
        tuner.setActive(true);
        async.flushMicrotasks();
        mic.push(s.next(hzAt(69, 0), 8192));
        async.elapse(const Duration(milliseconds: 70));
        expect(tuner.reading?.note.midi, 69);
        // Dejan de llegar muestras sin aviso: la lectura se borra.
        async.elapse(const Duration(milliseconds: 700));
        expect(tuner.reading, isNull);
        // Llega un poco de sonido nuevo de otra nota: no se mezcla con el viejo.
        mic.push(s.next(hzAt(64, 0), 2048));
        async.elapse(const Duration(milliseconds: 70));
        expect(tuner.reading, isNull);
        mic.push(s.next(hzAt(64, 0), 8192));
        async.elapse(const Duration(milliseconds: 70));
        expect(tuner.reading?.note.midi, 64);
        // Una llamada pausa la captura.
        mic.systemPause(true);
        async.flushMicrotasks();
        expect(tuner.status, MicStatus.interrupted);
        expect(tuner.reading, isNull);
        mic.systemPause(false);
        async.flushMicrotasks();
        expect(tuner.status, MicStatus.listening);
        mic.push(s.next(hzAt(67, 0), 4096));
        async.elapse(const Duration(milliseconds: 70));
        expect(tuner.reading, isNull, reason: 'medio búfer nuevo no basta');
        tuner.setActive(false);
        async.flushMicrotasks();
        tuner.dispose();
      });
    });

    test('Con una cuerda fijada se mide contra ella y la aguja se amortigua (M2)', () {
      final Tuner tuner = Tuner(microphoneEnabled: false)
        ..instrument = Instruments.byId('guitarra')
        ..lockedString = 1 // La2
        ..damping = 0;
      final Sustained s = Sustained();
      // 150 cents por encima de La2 (casi un Si♭): sigue midiendo contra La2.
      tuner.feed(s.next(hzAt(45, 150), 8192));
      expect(tuner.reading!.note.midi, 45);
      expect(tuner.reading!.note.cents, closeTo(150, 2));
      expect(tuner.reading!.stringIndex, 1);
      // Con amortiguación, un salto de -30 a +30 cents no llega de golpe.
      tuner.damping = 0.6;
      for (int i = 0; i < 12; i++) {
        tuner.feed(s.next(hzAt(45, -30), 8192));
      }
      final double before = tuner.reading!.note.cents;
      tuner.feed(s.next(hzAt(45, 30), 8192));
      final double after = tuner.reading!.note.cents;
      expect(before, lessThan(-20));
      expect(after, closeTo(before * 0.6 + 30 * 0.4, 2));
      // Cuerda libre: lee la nota más cercana.
      tuner
        ..lockedString = -1
        ..damping = 0;
      tuner.feed(s.next(hzAt(46, 0), 8192));
      expect(tuner.reading!.note.midi, 46);
    });

    test('Con capo, la cuerda que suena se reconoce y su meta sube (G9)', () {
      final Tuner tuner = Tuner(microphoneEnabled: false)
        ..instrument = Instruments.byId('guitarra')
        ..settings = const PitchSettings(capo: 2)
        ..damping = 0;
      final Sustained s = Sustained();
      tuner.feed(s.next(hzAt(47, -8), 8192)); // La2 con capo 2 = Si2
      expect(tuner.reading!.stringIndex, 1);
      expect(tuner.reading!.note.midi, 47);
      expect(tuner.reading!.note.cents, closeTo(-8, 1));
      tuner.lockedString = 1;
      tuner.feed(s.next(hzAt(46, 0), 8192)); // un semitono por debajo de la meta
      expect(tuner.reading!.note.midi, 47);
      expect(tuner.reading!.note.cents, closeTo(-100, 2));
    });

    test('Con un perfil elegido no se muestra lo que queda muy por debajo de su rango; en Cromático sí (3.ª ronda)', () {
      Tuner fresh(String id, {int capo = 0}) => Tuner(microphoneEnabled: false)
        ..instrument = Instruments.byId(id)
        ..settings = PitchSettings(capo: capo)
        ..damping = 0;
      final Sustained s = Sustained();
      // Flauta (desde Do4): un La2 es ruido grave o un subarmónico.
      final Tuner flute = fresh('flauta')..feed(s.next(hzAt(45, 0), 8192));
      expect(flute.reading, isNull);
      expect(flute.stableTone, isFalse);
      expect(flute.notice, TunerNotice.belowRange, reason: 'tono claro bajo el rango: se avisa');
      flute.feed(s.next(hzAt(54, 0), 8192)); // Fa♯3, dentro del margen de 7 semitonos
      expect(flute.reading?.note.midi, 54);
      expect(flute.notice, TunerNotice.none);
      // Guitarra (Mi2 = 40): Do2 y el Si1 de Drop B (aunque esté bajo) se
      // muestran; Sol1 no. Con capo 5, el límite sube.
      expect((fresh('guitarra')..feed(s.next(hzAt(36, 0), 8192))).reading?.note.midi, 36);
      final Tuner dropB = fresh('guitarra')..feed(s.next(hzAt(35, -20), 8192));
      expect(dropB.reading?.note.midi, 35);
      expect(dropB.reading!.note.cents, closeTo(-20, 2));
      expect((fresh('guitarra')..feed(s.next(hzAt(31, 0), 8192))).reading, isNull);
      expect((fresh('guitarra', capo: 5)..feed(s.next(hzAt(36, 0), 8192))).reading, isNull);
      // Ukelele con Sol grave (Sol3 = 55, cinco semitonos bajo su Do4), unos
      // cents bajo: se muestra para poder subirlo.
      final Tuner uke = fresh('ukelele')..feed(s.next(hzAt(55, -15), 8192));
      expect(uke.reading?.note.midi, 55);
      // Trompa en Fa: el Si1 sonante (Fa♯2 escrito) está en su rango.
      expect((fresh('trompa')..feed(s.next(hzAt(35, -10), 8192))).reading?.note.midi, 35);
      // Cromático: cualquier nota del rango del detector.
      expect((fresh('cromatico')..feed(s.next(hzAt(24, 0), 8192))).reading?.note.midi, 24);
      expect(Instruments.byId('cromatico').lowestReading(), lessThan(12.1));
    });

    test('El aviso de nota bajo el rango dura un momento y se va con el silencio (4.ª ronda, M3)', () {
      fakeAsync((FakeAsync async) {
        final Tuner tuner = Tuner(microphoneEnabled: false)
          ..instrument = Instruments.byId('violin')
          ..damping = 0;
        final Sustained s = Sustained();
        tuner.feed(s.next(hzAt(36, 0), 8192)); // el Do2 de un violonchelo
        expect(tuner.reading, isNull);
        expect(tuner.notice, TunerNotice.belowRange);
        async.elapse(const Duration(milliseconds: 300));
        tuner.feed(Float32List(8192));
        expect(tuner.notice, TunerNotice.belowRange, reason: 'no parpadea');
        async.elapse(const Duration(milliseconds: 400));
        tuner.feed(Float32List(8192));
        expect(tuner.notice, TunerNotice.none);
        tuner.dispose();
      });
    });

    test('Con el bordón sonando, una lectura en f/k de sus tonos no se muestra y se avisa (4.ª ronda, M1)', () {
      final double root = hzAt(50, 0); // Re3 del bordón
      Tuner fresh({bool drone = true}) {
        final Tuner t = Tuner(microphoneEnabled: false)
          ..instrument = Instruments.byId('voz')
          ..damping = 0;
        if (drone) {
          t.ownTones = () => <double>[root, root * 1.5]; // con la quinta pura
        }
        return t;
      }

      final Sustained s = Sustained();
      // La mezcla de una voz al unísono con bordón y quinta tiene periodo de
      // Re2 (la mitad del bordón): esa lectura no es la nota.
      final Tuner a = fresh()..feed(s.next(root / 2, 8192));
      expect(a.reading, isNull);
      expect(a.notice, TunerNotice.ownTone);
      // La residual de la quinta (un tercio de La3 = Re2) también.
      final Tuner b = fresh()..feed(s.next(root * 1.5 / 3, 8192));
      expect(b.notice, TunerNotice.ownTone);
      // La nota del bordón, su quinta y una nota cantada encima se muestran.
      expect((fresh()..feed(s.next(root, 8192))).reading?.note.midi, 50);
      expect((fresh()..feed(s.next(root * 1.5, 8192))).reading?.note.midi, 57);
      expect((fresh()..feed(s.next(hzAt(54, 0), 8192))).reading?.note.midi, 54);
      // Sin el bordón, el mismo Re2 es una nota más.
      expect((fresh(drone: false)..feed(s.next(root / 2, 8192))).reading?.note.midi, 38);
    });

    test('Un tono sostenido cuenta como práctica a partir de 0,4 s; los clics no (B3)', () {
      fakeAsync((FakeAsync async) {
        final Tuner tuner = Tuner(microphoneEnabled: false);
        int stable = 0;
        tuner.onStableTone = () => stable++;
        final Sustained s = Sustained();
        tuner.feed(s.next(hzAt(57, 0), 8192));
        int firstAt = -1;
        for (int i = 0; i < 40; i++) {
          async.elapse(const Duration(milliseconds: 46));
          tuner.feed(s.next(hzAt(57, 0), 2048));
          if (stable > 0 && firstAt < 0) {
            firstAt = i;
          }
        }
        expect(firstAt, inInclusiveRange(7, 10), reason: 'unos 400 ms');
        expect(stable, greaterThan(25));
        // El metrónomo de la app sonando cerca del micrófono: con subdivisiones
        // las alturas se alternan y nunca es un tono estable.
        stable = 0;
        final ClickRenderer subs = ClickRenderer(ClickScheduler(const RhythmConfig(bpm: 120, sound: ClickSound.beep, subdivision: 2)), ClickSynth());
        for (int i = 0; i < 100; i++) {
          async.elapse(const Duration(milliseconds: 46));
          tuner.feed(subs.render(2048));
        }
        expect(stable, 0);
        // Sin subdivisiones y rápido, los clics se parecen a una nota tenida:
        // como en ServiceLinks, las alturas del clic que suena no cuentan.
        tuner.ownFrequencies = () => ClickSynth.pitchedFrequencies(ClickSound.beep);
        for (final double bpm in <double>[120, 300]) {
          final ClickRenderer clicks = ClickRenderer(ClickScheduler(RhythmConfig(bpm: bpm, sound: ClickSound.beep)), ClickSynth());
          for (int i = 0; i < 100; i++) {
            async.elapse(const Duration(milliseconds: 46));
            tuner.feed(clicks.render(2048));
          }
        }
        expect(stable, 0);
        // Un tono que suena desde la propia app (el bordón) tampoco cuenta.
        tuner.ownFrequencies = () => <double>[hzAt(57, 0)];
        for (int i = 0; i < 40; i++) {
          async.elapse(const Duration(milliseconds: 46));
          tuner.feed(s.next(hzAt(57, 0), 2048));
        }
        expect(stable, 0);
        // Su octava, tampoco (el detector puede quedarse con ella).
        for (int i = 0; i < 40; i++) {
          async.elapse(const Duration(milliseconds: 46));
          tuner.feed(s.next(hzAt(45, 0), 2048));
        }
        expect(stable, 0);
        tuner.dispose();
      });
    });

    test('Los golpes se reconocen por su envolvente', () {
      final Float32List hit = Float32List(8192);
      for (int i = 0; i < 600; i++) {
        hit[i] = 0.8 * math.exp(-i / 120) * math.sin(i * 0.3);
      }
      expect(Tuner.isImpulsive(hit), isTrue);
      expect(Tuner.isImpulsive(Sustained().next(220, 8192)), isFalse);
    });
  });
}
