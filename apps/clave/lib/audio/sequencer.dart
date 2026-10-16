import 'dart:typed_data';

import 'click_synth.dart';

/// Qué hace cada pulso del compás.
enum BeatMode { accent, normal, silent, subOnly }

/// Configuración rítmica del metrónomo (lo que se guarda en un preajuste).
class RhythmConfig {
  const RhythmConfig({
    this.bpm = 100,
    this.beatsPerBar = 4,
    this.denominator = 4,
    this.subdivision = 1,
    this.swing = 0,
    this.beats = const <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal, BeatMode.normal],
    this.subdivisionAudible = true,
    this.sound = ClickSound.madera,
    this.trainer,
    this.muteBars,
  });

  final double bpm;
  final int beatsPerBar;

  /// Figura que lleva el pulso: 2, 4, 8 o 16.
  final int denominator;

  /// Subdivisiones por pulso: 1 (ninguna), 2 (corcheas), 3 (tresillos), 4 (semicorcheas).
  final int subdivision;

  /// Swing de 0 (recto) a 1 (tresillo) para subdivisiones de 2.
  final double swing;
  final List<BeatMode> beats;
  final bool subdivisionAudible;
  final ClickSound sound;
  final TrainerConfig? trainer;
  final MuteConfig? muteBars;

  RhythmConfig copyWith({
    double? bpm,
    int? beatsPerBar,
    int? denominator,
    int? subdivision,
    double? swing,
    List<BeatMode>? beats,
    bool? subdivisionAudible,
    ClickSound? sound,
    TrainerConfig? trainer,
    bool clearTrainer = false,
    MuteConfig? muteBars,
    bool clearMute = false,
  }) {
    final int n = beatsPerBar ?? this.beatsPerBar;
    List<BeatMode> b = beats ?? this.beats;
    if (b.length != n) {
      b = List<BeatMode>.generate(n, (int i) => i == 0 ? BeatMode.accent : (i < b.length ? b[i] : BeatMode.normal));
    }
    return RhythmConfig(
      bpm: bpm ?? this.bpm,
      beatsPerBar: n,
      denominator: denominator ?? this.denominator,
      subdivision: subdivision ?? this.subdivision,
      swing: swing ?? this.swing,
      beats: b,
      subdivisionAudible: subdivisionAudible ?? this.subdivisionAudible,
      sound: sound ?? this.sound,
      trainer: clearTrainer ? null : (trainer ?? this.trainer),
      muteBars: clearMute ? null : (muteBars ?? this.muteBars),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'bpm': bpm,
        'beatsPerBar': beatsPerBar,
        'denominator': denominator,
        'subdivision': subdivision,
        'swing': swing,
        'beats': beats.map((BeatMode b) => b.name).toList(),
        'subdivisionAudible': subdivisionAudible,
        'sound': sound.name,
        if (trainer != null) 'trainer': trainer!.toJson(),
        if (muteBars != null) 'muteBars': muteBars!.toJson(),
      };

  static RhythmConfig fromJson(Map<String, dynamic> j) {
    final List<dynamic> beatNames = (j['beats'] as List<dynamic>?) ?? <dynamic>[];
    final List<BeatMode> beats = <BeatMode>[
      for (final dynamic n in beatNames) BeatMode.values.firstWhere((BeatMode m) => m.name == n, orElse: () => BeatMode.normal),
    ];
    final int bpb = (j['beatsPerBar'] as num?)?.toInt() ?? 4;
    return RhythmConfig(
      bpm: (j['bpm'] as num?)?.toDouble() ?? 100,
      beatsPerBar: bpb,
      denominator: (j['denominator'] as num?)?.toInt() ?? 4,
      subdivision: (j['subdivision'] as num?)?.toInt() ?? 1,
      swing: (j['swing'] as num?)?.toDouble() ?? 0,
      beats: beats.length == bpb ? beats : List<BeatMode>.generate(bpb, (int i) => i == 0 ? BeatMode.accent : BeatMode.normal),
      subdivisionAudible: j['subdivisionAudible'] as bool? ?? true,
      sound: ClickSound.values.firstWhere((ClickSound s) => s.name == j['sound'], orElse: () => ClickSound.madera),
      trainer: j['trainer'] is Map<String, dynamic> ? TrainerConfig.fromJson(j['trainer'] as Map<String, dynamic>) : null,
      muteBars: j['muteBars'] is Map<String, dynamic> ? MuteConfig.fromJson(j['muteBars'] as Map<String, dynamic>) : null,
    );
  }

  /// Duración de un pulso en segundos (una negra a 60 BPM = 1 s; el
  /// denominador 8 hace que el pulso sea una corchea).
  double get beatSeconds => 60.0 / bpm;

  /// Compás escrito, por ejemplo "3/4".
  String get timeSignature => '$beatsPerBar/$denominator';
}

/// Entrenador de tempo: sube (o baja) el BPM cada cierto número de compases.
class TrainerConfig {
  const TrainerConfig({required this.targetBpm, this.stepBpm = 4, this.everyBars = 4});

  final double targetBpm;
  final double stepBpm;
  final int everyBars;

  Map<String, dynamic> toJson() => <String, dynamic>{'targetBpm': targetBpm, 'stepBpm': stepBpm, 'everyBars': everyBars};

  static TrainerConfig fromJson(Map<String, dynamic> j) => TrainerConfig(
        targetBpm: (j['targetBpm'] as num?)?.toDouble() ?? 120,
        stepBpm: (j['stepBpm'] as num?)?.toDouble() ?? 4,
        everyBars: (j['everyBars'] as num?)?.toInt() ?? 4,
      );
}

/// Compases que suenan y compases mudos, en ciclo.
class MuteConfig {
  const MuteConfig({this.soundBars = 2, this.muteBarsCount = 1});

  final int soundBars;
  final int muteBarsCount;

  Map<String, dynamic> toJson() => <String, dynamic>{'soundBars': soundBars, 'muteBars': muteBarsCount};

  static MuteConfig fromJson(Map<String, dynamic> j) => MuteConfig(
        soundBars: (j['soundBars'] as num?)?.toInt() ?? 2,
        muteBarsCount: (j['muteBars'] as num?)?.toInt() ?? 1,
      );
}

/// Un golpe programado.
class ClickEvent {
  const ClickEvent({required this.sample, required this.bar, required this.beat, required this.sub, required this.kind, required this.audible, required this.bpm});

  /// Posición en muestras desde el inicio del flujo.
  final int sample;
  final int bar;
  final int beat;

  /// Subdivisión dentro del pulso (0 = el pulso mismo).
  final int sub;
  final BeatKind kind;

  /// Falso en los compases mudos o pulsos silenciosos (el evento sigue
  /// existiendo para la animación).
  final bool audible;

  /// Tempo vigente en ese golpe.
  final double bpm;

  double seconds(int sampleRate) => sample / sampleRate;
}

/// Genera los golpes en orden a partir de la configuración, que puede
/// cambiar mientras suena: el cambio se aplica desde la siguiente subdivisión.
class ClickScheduler {
  ClickScheduler(this.config, {this.sampleRate = 44100, int startSample = 0}) : _nextSample = startSample.toDouble(), _currentBpm = config.bpm;

  RhythmConfig config;
  final int sampleRate;
  double _nextSample;
  int _bar = 0;
  int _beat = 0;
  int _sub = 0;
  double _currentBpm;
  int _barsAtCurrentBpm = 0;

  double get currentBpm => _currentBpm;

  int get bar => _bar;

  /// Cambia la configuración en caliente. Si cambia el tempo base, el
  /// entrenador vuelve a empezar desde ahí.
  void update(RhythmConfig c) {
    final bool tempoChanged = c.bpm != config.bpm;
    config = c;
    if (tempoChanged || c.trainer == null) {
      _currentBpm = c.bpm;
      _barsAtCurrentBpm = 0;
    }
    if (_beat >= c.beatsPerBar) {
      _beat = 0;
    }
    if (_sub >= c.subdivision) {
      _sub = 0;
    }
  }

  /// Golpes cuya posición es menor que [untilSample].
  List<ClickEvent> eventsUntil(int untilSample) {
    final List<ClickEvent> out = <ClickEvent>[];
    while (_nextSample < untilSample) {
      out.add(_emit());
    }
    return out;
  }

  ClickEvent _emit() {
    final RhythmConfig c = config;
    final BeatMode mode = _beat < c.beats.length ? c.beats[_beat] : BeatMode.normal;
    final bool barMuted = _isBarMuted(_bar);
    BeatKind kind;
    bool audible;
    if (_sub == 0) {
      kind = mode == BeatMode.accent ? BeatKind.accent : BeatKind.normal;
      audible = !barMuted && (mode == BeatMode.accent || mode == BeatMode.normal);
    } else {
      kind = BeatKind.sub;
      audible = !barMuted && c.subdivisionAudible && mode != BeatMode.silent;
    }
    if (mode == BeatMode.subOnly && _sub == 0) {
      audible = false;
    }
    final ClickEvent e = ClickEvent(sample: _nextSample.round(), bar: _bar, beat: _beat, sub: _sub, kind: kind, audible: audible, bpm: _currentBpm);
    _advance();
    return e;
  }

  bool _isBarMuted(int bar) {
    final MuteConfig? m = config.muteBars;
    if (m == null || m.soundBars <= 0) {
      return false;
    }
    final int cycle = m.soundBars + m.muteBarsCount;
    return bar % cycle >= m.soundBars;
  }

  void _advance() {
    final RhythmConfig c = config;
    final double beatSamples = 60.0 / _currentBpm * sampleRate;
    double subSamples = beatSamples / c.subdivision;
    if (c.subdivision == 2 && c.swing > 0) {
      // Con swing la primera corchea se alarga y la segunda se acorta.
      final double ratio = 0.5 + c.swing / 6; // 0,5 recto … 0,667 tresillo
      subSamples = _sub == 0 ? beatSamples * ratio : beatSamples * (1 - ratio);
    }
    _nextSample += subSamples;
    _sub += 1;
    if (_sub >= c.subdivision) {
      _sub = 0;
      _beat += 1;
      if (_beat >= c.beatsPerBar) {
        _beat = 0;
        _bar += 1;
        _barsAtCurrentBpm += 1;
        _applyTrainer();
      }
    }
  }

  void _applyTrainer() {
    final TrainerConfig? t = config.trainer;
    if (t == null || t.everyBars <= 0) {
      return;
    }
    if (_barsAtCurrentBpm >= t.everyBars) {
      _barsAtCurrentBpm = 0;
      if (_currentBpm < t.targetBpm) {
        _currentBpm = (_currentBpm + t.stepBpm.abs()).clamp(20.0, t.targetBpm).toDouble();
      } else if (_currentBpm > t.targetBpm) {
        _currentBpm = (_currentBpm - t.stepBpm.abs()).clamp(t.targetBpm, 400.0).toDouble();
      }
    }
  }
}

/// Mezcla los golpes en un flujo PCM continuo, por bloques.
class ClickRenderer {
  ClickRenderer(this.scheduler, this.synth, {this.volume = 1.0});

  final ClickScheduler scheduler;
  final ClickSynth synth;
  double volume;
  final List<_Voice> _voices = <_Voice>[];
  final List<ClickEvent> _recent = <ClickEvent>[];
  int _rendered = 0;

  /// Muestras ya producidas.
  int get renderedSamples => _rendered;

  /// Golpes recientes (para la animación), ordenados por posición.
  List<ClickEvent> get recent => List<ClickEvent>.unmodifiable(_recent);

  /// Produce [frames] muestras más y devuelve los nuevos golpes.
  Float32List render(int frames) {
    final int start = _rendered;
    final int end = start + frames;
    final List<ClickEvent> events = scheduler.eventsUntil(end);
    for (final ClickEvent e in events) {
      _recent.add(e);
      if (e.audible) {
        _voices.add(_Voice(e.sample, synth.sample(scheduler.config.sound, e.kind)));
      }
    }
    while (_recent.length > 256) {
      _recent.removeAt(0);
    }
    final Float32List out = Float32List(frames);
    for (final _Voice v in _voices) {
      final int from = v.start > start ? v.start : start;
      final int to = (v.start + v.data.length) < end ? (v.start + v.data.length) : end;
      for (int s = from; s < to; s++) {
        out[s - start] += v.data[s - v.start] * volume;
      }
    }
    _voices.removeWhere((_Voice v) => v.start + v.data.length <= end);
    for (int i = 0; i < frames; i++) {
      final double x = out[i];
      out[i] = x > 1 ? 1 : (x < -1 ? -1 : x);
    }
    _rendered = end;
    return out;
  }

  /// Golpe vigente en [sample] (el último cuyo inicio ya pasó).
  ClickEvent? eventAt(int sample) {
    ClickEvent? last;
    for (final ClickEvent e in _recent) {
      if (e.sample <= sample) {
        last = e;
      } else {
        break;
      }
    }
    return last;
  }
}

class _Voice {
  _Voice(this.start, this.data);

  final int start;
  final Float32List data;
}
