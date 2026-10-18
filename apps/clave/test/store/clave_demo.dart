// Datos de ejemplo para las capturas de tienda de Clave: preajustes de ritmos
// colombianos y de práctica, una setlist, grabaciones y un mes de práctica.
// Todo es ficticio y relativo a la fecha en que corren las pruebas.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clave/audio/click_synth.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/core/app_state.dart';
import 'package:clave/model/models.dart';

const List<BeatMode> _3 = <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal];
const List<BeatMode> _2 = <BeatMode>[BeatMode.accent, BeatMode.normal];
const List<BeatMode> _4 = <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.normal];

/// Llena [st] con los datos de ejemplo en el idioma pedido.
Future<void> seedClaveDemo(AppState st, {required bool spanish, required DateTime now}) async {
  String tr(String es, String en) => spanish ? es : en;
  final DateTime day = DateTime(now.year, now.month, now.day);

  final List<Preset> presets = <Preset>[
    Preset(id: 'p_bambuco', name: 'Bambuco', rhythm: const RhythmConfig(bpm: 96, beatsPerBar: 3, subdivision: 2, beats: _3, sound: ClickSound.madera), notes: tr('Tiple rasgueado, acento en el tercer tiempo', 'Strummed tiple, accent on beat three')),
    Preset(id: 'p_pasillo', name: 'Pasillo', rhythm: const RhythmConfig(bpm: 126, beatsPerBar: 3, beats: _3, sound: ClickSound.clave)),
    Preset(id: 'p_cumbia', name: 'Cumbia', rhythm: const RhythmConfig(bpm: 92, beatsPerBar: 2, denominator: 2, subdivision: 2, beats: _2, sound: ClickSound.clave), notes: tr('Tambor alegre en contratiempo', 'Off-beat tambor alegre')),
    Preset(id: 'p_porro', name: 'Porro', rhythm: const RhythmConfig(bpm: 104, beatsPerBar: 2, denominator: 2, beats: _2, sound: ClickSound.madera)),
    Preset(id: 'p_joropo', name: 'Joropo', rhythm: const RhythmConfig(bpm: 184, beatsPerBar: 3, beats: _3, sound: ClickSound.beep), notes: tr('Arpa y cuatro, subir de 160 a 184', 'Harp and cuatro, build from 160 to 184'), createdAt: day.subtract(const Duration(days: 3))),
    Preset(id: 'p_escalas', name: tr('Escalas a corcheas', 'Scales in eighths'), rhythm: const RhythmConfig(bpm: 80, subdivision: 2, beats: _4, sound: ClickSound.beep)),
    Preset(id: 'p_balada', name: tr('Balada en 6/8', 'Ballad in 6/8'), rhythm: const RhythmConfig(bpm: 66, beatsPerBar: 6, denominator: 8, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.accent, BeatMode.normal, BeatMode.normal], sound: ClickSound.campana)),
  ];
  for (final Preset p in presets) {
    await st.addPreset(p);
  }
  final Setlist ensayo = await st.addSetlist(tr('Ensayo del sábado', 'Saturday rehearsal'));
  ensayo.presetIds.addAll(<String>['p_bambuco', 'p_pasillo', 'p_joropo', 'p_cumbia']);
  await st.savePresets();

  Recording rec(String id, String es, String en, int minutesAgo, int seconds, String folder, String instrument, double? bpm, {String notesEs = '', String notesEn = '', String format = 'aac'}) => Recording(
        id: id,
        name: tr(es, en),
        file: 'recordings/$id.${format == 'aac' ? 'm4a' : format}',
        format: format,
        durationMs: seconds * 1000,
        createdAt: now.subtract(Duration(minutes: minutesAgo)),
        folder: folder,
        instrumentId: instrument,
        bpm: bpm,
        notes: tr(notesEs, notesEn),
      );
  final String repertorio = tr('Repertorio', 'Repertoire');
  final String tecnica = tr('Técnica', 'Technique');
  final String ideas = tr('Ideas', 'Ideas');
  for (final Recording r in <Recording>[
    rec('r1', 'Bambuco · primera parte, toma 3', 'Bambuco · first section, take 3', 25, 94, repertorio, 'tiple', 96, notesEs: 'Cuidar el rasgueo en el compás 12', notesEn: 'Watch the strum in bar 12'),
    rec('r2', 'Escala de Sol mayor a dos octavas', 'G major scale, two octaves', 70, 48, tecnica, 'guitarra', 80),
    rec('r3', 'Pasillo · segunda voz', 'Pasillo · second voice', 60 * 26, 132, repertorio, 'bandola', 126, format: 'flac'),
    rec('r4', 'Arpegios con metrónomo', 'Arpeggios with metronome', 60 * 27, 61, tecnica, 'guitarra', 72),
    rec('r5', 'Improvisación sobre bordón en Re', 'Improvisation over a D drone', 60 * 50, 187, ideas, 'violin', null, format: 'wav'),
    rec('r6', 'Joropo · pasaje rápido a 160', 'Joropo · fast passage at 160', 60 * 74, 39, repertorio, 'cuatro', 160),
  ]) {
    st.recordings.add(r);
  }
  st.recordings.sort((Recording a, Recording b) => b.createdAt.compareTo(a.createdAt));
  await st.saveRecordings();

  // Un mes de práctica con días de descanso; hoy va cerca de la meta diaria.
  final math.Random rnd = math.Random(7);
  const List<String> tools = <String>['metronomo', 'afinador', 'tono', 'grabadora'];
  const List<String> instruments = <String>['guitarra', 'guitarra', 'tiple', 'tiple', 'bandola', 'violin'];
  int n = 0;
  for (int back = 29; back >= 0; back--) {
    final DateTime d = day.subtract(Duration(days: back));
    if (back > 6 && (back % 5 == 0 || back % 7 == 3)) {
      continue; // descanso
    }
    final int blocks = back == 0 ? 2 : 1 + rnd.nextInt(3);
    DateTime start = DateTime(d.year, d.month, d.day, 18 + rnd.nextInt(2), rnd.nextInt(40));
    for (int b = 0; b < blocks; b++) {
      final String tool = back == 0 ? (b == 0 ? 'afinador' : 'metronomo') : tools[rnd.nextInt(tools.length)];
      final int minutes = back == 0 ? (b == 0 ? 3 : 15) : (tool == 'afinador' ? 2 + rnd.nextInt(4) : 8 + rnd.nextInt(22));
      final DateTime end = start.add(Duration(minutes: minutes));
      if (back == 0 && end.isAfter(now)) {
        break;
      }
      st.sessions.add(PracticeSession(id: 's${n++}', start: start, end: end, tool: tool, instrumentId: instruments[rnd.nextInt(instruments.length)]));
      start = end.add(Duration(minutes: 2 + rnd.nextInt(6)));
    }
  }
  await st.savePractice();
}

/// Señal de prueba para el afinador: una cuerda pulsada (fundamental y
/// armónicos con caída suave) en [hz], a 44,1 kHz.
Float32List pluckedString(double hz, {int samples = 8192, int sampleRate = 44100, int offset = 0}) {
  final Float32List out = Float32List(samples);
  const List<double> harmonics = <double>[0.55, 0.3, 0.16, 0.08, 0.04];
  for (int i = 0; i < samples; i++) {
    final double t = (i + offset) / sampleRate;
    double v = 0;
    for (int h = 0; h < harmonics.length; h++) {
      v += harmonics[h] * math.sin(2 * math.pi * hz * (h + 1) * t);
    }
    out[i] = (v * 0.6 * math.exp(-t * 0.35)).toDouble();
  }
  return out;
}
