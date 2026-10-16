import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clave/audio/click_synth.dart';
import 'package:clave/audio/pitch_detector.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/music/instruments.dart';
import 'package:clave/music/notes.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List sine(double hz, {int n = 8192, int rate = 44100, double amp = 0.5, List<double> harmonics = const <double>[]}) {
  final Float32List out = Float32List(n);
  for (int i = 0; i < n; i++) {
    final double tt = i / rate;
    double v = math.sin(2 * math.pi * hz * tt);
    for (int h = 0; h < harmonics.length; h++) {
      v += harmonics[h] * math.sin(2 * math.pi * hz * (h + 2) * tt);
    }
    out[i] = amp * v / (1 + harmonics.fold<double>(0, (double a, double b) => a + b));
  }
  return out;
}

void main() {
  group('Notas', () {
    test('La4 = 440 Hz y Do4 = 261,63 Hz en temperamento igual', () {
      expect(Notes.midiToHz(69), 440);
      expect(Notes.midiToHz(60), closeTo(261.63, 0.01));
      expect(Notes.hzToMidi(880), closeTo(81, 1e-9));
      expect(Notes.octaveOf(60), 4);
      expect(Notes.octaveOf(21), 0);
      expect(Notes.pitchClassOf(61), 1);
    });

    test('Los nombres cambian con la notación y los bemoles', () {
      expect(Notes.name(0, Notation.solfeo), 'Do');
      expect(Notes.name(1, Notation.solfeo), 'Do♯');
      expect(Notes.name(1, Notation.solfeo, flats: true), 'Re♭');
      expect(Notes.name(11, Notation.german), 'H');
      expect(Notes.name(10, Notation.german, flats: true), 'B');
      expect(Notes.name(9, Notation.english), 'A');
      expect(Notes.name(7, Notation.indian), 'Pa');
    });

    test('Los temperamentos históricos desvían como manda la teoría', () {
      final List<double> just = Notes.temperamentOffsets(Temperament.just);
      expect(just[7], closeTo(1.955, 0.01)); // quinta justa 3/2 = 701,955 cents
      expect(just[4], closeTo(-13.69, 0.01)); // tercera mayor 5/4 = 386,31 cents
      final List<double> pyth = Notes.temperamentOffsets(Temperament.pythagorean);
      expect(pyth[4], closeTo(7.82, 0.01)); // 81/64 = 407,82 cents
      final List<double> mean = Notes.temperamentOffsets(Temperament.meantone);
      expect(mean[4], closeTo(-13.69, 0.1)); // tercera pura en mesotónico de 1/4 de coma
      expect(mean[7], closeTo(-3.42, 0.1));
      expect(Notes.temperamentOffsets(Temperament.equal).every((double d) => d == 0), isTrue);
    });

    test('La referencia La4 se mantiene exacta en cualquier temperamento', () {
      for (final Temperament tmp in Temperament.values) {
        expect(Notes.frequency(69, temperament: tmp, a4: 442), closeTo(442, 1e-9), reason: tmp.name);
      }
      // En justo con tónica Do, la quinta Mi4-La4... el Mi4 queda 13,69 + 15,64 cents respecto a igual.
      final double mi = Notes.frequency(64, temperament: Temperament.just);
      expect(1200 * math.log(mi / Notes.midiToHz(64)) / math.ln2, closeTo(-13.69 + 15.64, 0.05));
    });

    test('PitchSettings interpreta frecuencias con transposición y capo', () {
      const PitchSettings ps = PitchSettings();
      final NoteReading r = ps.read(445);
      expect(r.midi, 69);
      expect(r.cents, closeTo(19.56, 0.05));
      expect(ps.read(430).midi, 69);
      expect(ps.read(430).cents, lessThan(0));
      const PitchSettings sib = PitchSettings(transposition: 2);
      expect(sib.displayName(70), 'Do'); // Si♭ sonante se muestra como Do
      const PitchSettings capo = PitchSettings(capo: 2, notation: Notation.english);
      expect(capo.displayName(66), 'E'); // Fa♯ con capo en 2 es un Mi
      expect(PitchSettings(a4: 432).read(432).midi, 69);
    });

    test('Formato de hercios con coma', () {
      expect(formatHz(440.04), '440,0');
      expect(formatHz(261.626, comma: false), '261.6');
    });
  });

  group('Instrumentos', () {
    test('Cuerdas de la guitarra y detección de la más cercana', () {
      final Instrument g = Instruments.byId('guitarra');
      expect(g.strings, <int>[40, 45, 50, 55, 59, 64]);
      expect(g.nearestString(Notes.hzToMidi(110)), 1); // La2
      expect(g.nearestString(Notes.hzToMidi(330)), 5); // Mi4
      expect(Instruments.byId('tiple').courses, 3);
      expect(Instruments.byId('clarinete').transposition, 2);
      expect(Instruments.byId('no-existe').id, 'cromatico');
      final Set<String> ids = Instruments.all.map((Instrument i) => i.id).toSet();
      expect(ids.length, Instruments.all.length);
    });

    test('Indicaciones de tempo', () {
      expect(TempoMark.forBpm(50), 'Largo');
      expect(TempoMark.forBpm(100), 'Andante');
      expect(TempoMark.forBpm(140), 'Allegro');
      expect(TempoMark.forBpm(300), 'Prestissimo');
    });
  });

  group('Detector de tono', () {
    final PitchDetector det = PitchDetector();

    test('Detecta senos puros de Do1 a La6 con menos de 1 cent de error', () {
      for (final double hz in <double>[32.7, 55, 82.41, 110, 146.83, 196, 246.94, 329.63, 440, 659.26, 1046.5, 1760]) {
        final PitchResult r = det.detect(sine(hz));
        expect(r.hasPitch, isTrue, reason: '$hz Hz');
        final double cents = 1200 * math.log(r.frequency / hz) / math.ln2;
        expect(cents.abs(), lessThan(hz < 60 ? 3 : 1), reason: '$hz Hz → ${r.frequency}');
        expect(r.clarity, greaterThan(0.9), reason: '$hz Hz');
      }
    });

    test('Con armónicos fuertes sigue encontrando la fundamental', () {
      for (final double hz in <double>[98, 220, 392]) {
        final PitchResult r = det.detect(sine(hz, harmonics: <double>[0.8, 0.6, 0.4]));
        final double cents = 1200 * math.log(r.frequency / hz) / math.ln2;
        expect(cents.abs(), lessThan(2), reason: '$hz Hz → ${r.frequency}');
      }
    });

    test('El silencio y el ruido no producen nota', () {
      expect(det.detect(Float32List(8192)).hasPitch, isFalse);
      final math.Random rnd = math.Random(1);
      final Float32List noise = Float32List(8192);
      for (int i = 0; i < noise.length; i++) {
        noise[i] = (rnd.nextDouble() * 2 - 1) * 0.3;
      }
      final PitchResult r = det.detect(noise);
      expect(!r.hasPitch || r.clarity < 0.6, isTrue);
    });

    test('pcm16ToFloat convierte extremos', () {
      final ByteData b = ByteData(4)
        ..setInt16(0, 32767, Endian.little)
        ..setInt16(2, -32768, Endian.little);
      final Float32List f = pcm16ToFloat(b.buffer.asUint8List());
      expect(f[0], closeTo(1, 1e-3));
      expect(f[1], -1);
    });
  });

  group('Secuenciador', () {
    test('A 120 BPM en 4/4 los pulsos caen cada 22.050 muestras', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 120), startSample: 0);
      final List<ClickEvent> ev = s.eventsUntil(44100 * 4);
      expect(ev.length, 8);
      expect(ev[1].sample - ev[0].sample, 22050);
      expect(ev[0].kind, BeatKind.accent);
      expect(ev[1].kind, BeatKind.normal);
      expect(ev[4].bar, 1);
      expect(ev[4].beat, 0);
      expect(ev[4].kind, BeatKind.accent);
    });

    test('Las subdivisiones y el swing reparten el pulso', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 60, subdivision: 2, swing: 1), startSample: 0);
      final List<ClickEvent> ev = s.eventsUntil(44100 * 2);
      expect(ev[0].sub, 0);
      expect(ev[1].sub, 1);
      // Con swing 1 la primera corchea dura 2/3 del pulso.
      expect(ev[1].sample - ev[0].sample, closeTo(44100 * 2 / 3, 2));
      expect(ev[2].sample - ev[0].sample, closeTo(44100, 2));
      expect(ev[1].kind, BeatKind.sub);
    });

    test('Los pulsos silenciosos y los compases mudos no suenan pero existen', () {
      final ClickScheduler s = ClickScheduler(
        const RhythmConfig(bpm: 120, beatsPerBar: 2, beats: <BeatMode>[BeatMode.accent, BeatMode.silent], muteBars: MuteConfig(soundBars: 1, muteBarsCount: 1)),
        startSample: 0,
      );
      final List<ClickEvent> ev = s.eventsUntil(44100 * 4);
      expect(ev.length, 8);
      expect(ev[0].audible, isTrue);
      expect(ev[1].audible, isFalse); // pulso silencioso
      expect(ev[2].audible, isFalse); // compás mudo
      expect(ev[3].audible, isFalse);
      expect(ev[4].audible, isTrue);
    });

    test('El entrenador sube el tempo por pasos hasta la meta', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 100, beatsPerBar: 4, trainer: TrainerConfig(targetBpm: 110, stepBpm: 4, everyBars: 1)), startSample: 0);
      final List<ClickEvent> ev = s.eventsUntil(44100 * 20);
      final List<double> bpms = ev.where((ClickEvent e) => e.beat == 0).map((ClickEvent e) => e.bpm).toList();
      expect(bpms.take(5).toList(), <double>[100, 104, 108, 110, 110]);
    });

    test('Cambiar la configuración en caliente aplica desde el siguiente golpe', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 60), startSample: 0);
      s.eventsUntil(44100 + 1);
      s.update(const RhythmConfig(bpm: 120));
      final List<ClickEvent> ev = s.eventsUntil(44100 * 3);
      expect(ev.first.bpm, 120);
      expect(ev[1].sample - ev[0].sample, 22050);
    });

    test('El renderizador produce audio audible y alineado', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 120, sound: ClickSound.beep), startSample: 0);
      final ClickRenderer r = ClickRenderer(s, ClickSynth());
      final Float32List a = r.render(2048);
      expect(a.any((double v) => v.abs() > 0.1), isTrue);
      expect(a.every((double v) => v.abs() <= 1), isTrue);
      final Float32List b = r.render(2048);
      expect(r.renderedSamples, 4096);
      expect(b.length, 2048);
      for (int i = 0; i < 14; i++) {
        r.render(2048);
      }
      expect(r.renderedSamples, 2048 * 16);
      expect(r.eventAt(100)?.beat, 0);
      expect(r.eventAt(22060)?.beat, 1);
      expect(r.eventAt(22040)?.beat, 0);
    });

    test('Todos los sonidos se sintetizan sin NaN y con duración razonable', () {
      final ClickSynth synth = ClickSynth();
      for (final ClickSound s in ClickSound.values) {
        for (final BeatKind k in BeatKind.values) {
          final Float32List x = synth.sample(s, k);
          expect(x.length, greaterThan(400), reason: '${s.name} ${k.name}');
          expect(x.length, lessThanOrEqualTo(44100), reason: '${s.name} ${k.name}');
          expect(x.every((double v) => v.isFinite && v.abs() <= 1), isTrue, reason: '${s.name} ${k.name}');
          expect(x.any((double v) => v.abs() > 0.05), isTrue, reason: '${s.name} ${k.name}');
        }
      }
      final Uint8List pcm = floatToPcm16(Float32List.fromList(<double>[0, 1, -1]));
      expect(pcm.length, 6);
    });

    test('RhythmConfig sobrevive al JSON', () {
      const RhythmConfig c = RhythmConfig(bpm: 93.5, beatsPerBar: 7, denominator: 8, subdivision: 3, swing: 0.2, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.silent, BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.subOnly], sound: ClickSound.cencerro, trainer: TrainerConfig(targetBpm: 120, stepBpm: 2, everyBars: 2), muteBars: MuteConfig(soundBars: 3, muteBarsCount: 1));
      final RhythmConfig back = RhythmConfig.fromJson(c.toJson());
      expect(back.bpm, 93.5);
      expect(back.beatsPerBar, 7);
      expect(back.beats[6], BeatMode.subOnly);
      expect(back.sound, ClickSound.cencerro);
      expect(back.trainer!.targetBpm, 120);
      expect(back.muteBars!.soundBars, 3);
      expect(back.timeSignature, '7/8');
      expect(c.copyWith(beatsPerBar: 3).beats.length, 3);
    });
  });
}
