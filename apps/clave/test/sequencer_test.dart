import 'dart:typed_data';

import 'package:clave/audio/click_synth.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Posiciones de los pulsos (subdivisión 0).
List<int> beats(List<ClickEvent> ev) => <int>[for (final ClickEvent e in ev) if (e.sub == 0) e.sample];

void main() {
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
    expect(ev[5].beatCount, 5);
    expect(ev[5].beatStart, 5 * 22050);
    expect(ev[5].beatLength, 22050);
  });

  test('Las subdivisiones y el swing reparten el pulso', () {
    final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 60, subdivision: 2, swing: 1), startSample: 0);
    final List<ClickEvent> ev = s.eventsUntil(44100 * 2);
    expect(ev[0].sub, 0);
    expect(ev[1].sub, 1);
    // Con swing 1 la primera corchea dura 2/3 del pulso.
    expect(ev[1].sample - ev[0].sample, closeTo(44100 * 2 / 3, 2));
    expect(ev[2].sample - ev[0].sample, 44100);
    expect(ev[1].kind, BeatKind.sub);
  });

  group('Cambios en marcha (G1)', () {
    test('Cambiar la subdivisión no corre la rejilla de pulsos', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 120), startSample: 0);
      final List<ClickEvent> all = <ClickEvent>[...s.eventsUntil(30000)];
      s.update(const RhythmConfig(bpm: 120, subdivision: 2));
      all.addAll(s.eventsUntil(44100 * 3));
      expect(beats(all), <int>[for (int k = 0; k < 6; k++) k * 22050]);
      // Las corcheas empiezan en el pulso siguiente al cambio, a mitad de pulso.
      final List<int> subs = <int>[for (final ClickEvent e in all) if (e.sub == 1) e.sample];
      expect(subs.first, 44100 + 11025);
      expect(subs, <int>[for (int k = 2; k < 6; k++) k * 22050 + 11025]);
    });

    test('Cambiar el swing a mitad de pulso: el pulso en curso termina con su rejilla', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 60, subdivision: 2), startSample: 0);
      final List<ClickEvent> all = <ClickEvent>[...s.eventsUntil(10000)]; // solo el pulso 0
      s.update(const RhythmConfig(bpm: 60, subdivision: 2, swing: 1));
      all.addAll(s.eventsUntil(44100 * 3));
      expect(beats(all), <int>[0, 44100, 88200]);
      final List<int> subs = <int>[for (final ClickEvent e in all) if (e.sub == 1) e.sample];
      expect(subs[0], 22050); // recta: ya estaba en curso
      expect(subs[1], 44100 + 29400); // con swing desde el pulso siguiente
      expect(subs[2], 88200 + 29400);
    });

    test('Cambiar el tempo rige desde el pulso siguiente, donde le toca', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 60), startSample: 0);
      s.eventsUntil(50000); // pulsos en 0 y 44100
      s.update(const RhythmConfig(bpm: 120));
      final List<ClickEvent> ev = s.eventsUntil(44100 * 4);
      expect(ev.first.sample, 88200);
      expect(ev.first.bpm, 120);
      expect(ev[1].sample - ev[0].sample, 22050);
    });

    test('Un compás más corto en marcha empieza un compás nuevo en el pulso siguiente', () {
      final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: 120), startSample: 0);
      s.eventsUntil(22050 * 2 + 1); // pulsos 0, 1 y 2 del primer compás de 4
      s.update(const RhythmConfig(bpm: 120, beatsPerBar: 2, beats: <BeatMode>[BeatMode.accent, BeatMode.normal]));
      final List<ClickEvent> ev = s.eventsUntil(22050 * 8);
      expect(ev.first.sample, 22050 * 3);
      expect(ev.first.beat, 0);
      expect(ev.first.bar, 1);
      expect(ev.first.kind, BeatKind.accent);
      expect(ev[1].beat, 1);
      expect(ev[2].beat, 0);
    });
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
    const RhythmConfig c = RhythmConfig(
      bpm: 93.5,
      beatsPerBar: 7,
      denominator: 8,
      subdivision: 3,
      swing: 0.2,
      beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.silent, BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.subOnly],
      sound: ClickSound.cencerro,
      trainer: TrainerConfig(targetBpm: 120, stepBpm: 2, everyBars: 2),
      muteBars: MuteConfig(soundBars: 3, muteBarsCount: 1),
    );
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

  test('Un JSON hostil se acota y el planificador nunca se cuelga (G11)', () {
    final RhythmConfig c = RhythmConfig.fromJson(<String, dynamic>{
      'bpm': 1e12,
      'beatsPerBar': 100000,
      'denominator': 3,
      'subdivision': 5,
      'swing': -7,
      'beats': 'no es una lista',
      'sound': 'trompeta',
      'subdivisionAudible': 'sí',
      'trainer': <String, dynamic>{'targetBpm': double.nan, 'stepBpm': -50, 'everyBars': 0},
      'muteBars': <String, dynamic>{'soundBars': -1, 'muteBars': 1e9},
    });
    expect(c.bpm, RhythmConfig.maxBpm);
    expect(c.beatsPerBar, RhythmConfig.maxBeats);
    expect(c.beats.length, c.beatsPerBar);
    expect(c.beats.first, BeatMode.accent);
    expect(c.denominator, 4);
    expect(c.subdivision, 1);
    expect(c.swing, 0);
    expect(c.sound, ClickSound.madera);
    expect(c.subdivisionAudible, isTrue);
    expect(c.trainer!.targetBpm, 120);
    expect(c.trainer!.stepBpm, inInclusiveRange(1, 20));
    expect(c.trainer!.everyBars, 1);
    expect(c.muteBars!.soundBars, 1);
    expect(c.muteBars!.muteBarsCount, 8);
    final RhythmConfig empty = RhythmConfig.fromJson(<String, dynamic>{'bpm': 'rápido', 'beatsPerBar': -3});
    expect(empty.bpm, 100);
    expect(empty.beatsPerBar, 1);
    // BPM 0 o negativo, compás vacío, sumas 0 en los compases mudos y un
    // entrenador que bajaría el tempo a cero: el planificador sigue en pie.
    for (final Map<String, dynamic> j in <Map<String, dynamic>>[
      <String, dynamic>{'bpm': 0, 'beatsPerBar': 0, 'beats': <Object>[], 'muteBars': <String, dynamic>{'soundBars': 0, 'muteBars': 0}},
      <String, dynamic>{'bpm': -120, 'trainer': <String, dynamic>{'targetBpm': -5, 'stepBpm': 0, 'everyBars': 0}},
      <String, dynamic>{'bpm': double.nan, 'subdivision': 0, 'swing': double.infinity},
    ]) {
      final RhythmConfig h = RhythmConfig.fromJson(j);
      expect(h.bpm, inInclusiveRange(RhythmConfig.minBpm, RhythmConfig.maxBpm), reason: '$j');
      expect(h.beatsPerBar, greaterThanOrEqualTo(1));
      final ClickScheduler sched = ClickScheduler(h, startSample: 0);
      final List<ClickEvent> ev = sched.eventsUntil(44100 * 60);
      expect(ev, isNotEmpty, reason: '$j');
      for (int i = 1; i < ev.length; i++) {
        expect(ev[i].sample, greaterThanOrEqualTo(ev[i - 1].sample), reason: '$j');
      }
      expect(sched.currentBpm, inInclusiveRange(RhythmConfig.minBpm, RhythmConfig.maxBpm));
    }
    // Valores imposibles creados en código también se acotan.
    final ClickScheduler s = ClickScheduler(const RhythmConfig(bpm: double.infinity, beatsPerBar: 0, subdivision: 0), startSample: 0);
    final List<ClickEvent> ev = s.eventsUntil(44100 * 3600);
    expect(ev.length, ClickScheduler.maxEventsPerCall);
    expect(ev.every((ClickEvent e) => e.sample >= 0), isTrue);
    expect(s.config.bpm, 100);
    expect(s.config.beatsPerBar, 1);
    expect(s.config.subdivision, 1);
  });
}
