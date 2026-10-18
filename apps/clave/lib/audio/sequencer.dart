import 'dart:typed_data';

import '../model/models.dart';
import 'click_synth.dart';

/// Qué hace cada pulso del compás.
enum BeatMode { accent, normal, silent, subOnly }

/// Configuración rítmica del metrónomo (lo que se guarda en un preajuste).
/// [sanitized] la deja siempre dentro de los rangos que el planificador
/// admite, venga de donde venga (código, ajustes o un JSON importado).
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

  static const double minBpm = 20;
  static const double maxBpm = 400;
  static const int maxBeats = 16;
  static const List<int> denominators = <int>[2, 4, 8, 16];
  static const List<int> subdivisions = <int>[1, 2, 3, 4, 6];

  final double bpm;
  final int beatsPerBar;

  /// Figura que lleva el pulso: 2, 4, 8 o 16.
  final int denominator;

  /// Subdivisiones por pulso: 1 (ninguna), 2 (corcheas), 3 (tresillos),
  /// 4 (semicorcheas) o 6 (seisillos).
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

  /// La misma configuración con cada valor dentro de su rango.
  RhythmConfig sanitized() {
    final double b = bpm.isFinite ? bpm.clamp(minBpm, maxBpm).toDouble() : 100;
    final int n = beatsPerBar.clamp(1, maxBeats);
    final List<BeatMode> modes = List<BeatMode>.generate(n, (int i) => i < beats.length ? beats[i] : (i == 0 ? BeatMode.accent : BeatMode.normal));
    return RhythmConfig(
      bpm: b,
      beatsPerBar: n,
      denominator: denominators.contains(denominator) ? denominator : 4,
      subdivision: subdivisions.contains(subdivision) ? subdivision : 1,
      swing: swing.isFinite ? swing.clamp(0.0, 1.0).toDouble() : 0,
      beats: List<BeatMode>.unmodifiable(modes),
      subdivisionAudible: subdivisionAudible,
      sound: sound,
      trainer: trainer?.sanitized(),
      muteBars: muteBars?.sanitized(),
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

  /// Lee un ritmo de un JSON propio o importado: cualquier valor ausente, de
  /// otro tipo o fuera de rango toma un valor válido.
  static RhythmConfig fromJson(Map<String, dynamic> j) {
    final int bpb = jsonInt(j, 'beatsPerBar', fallback: 4, min: 1, max: maxBeats);
    final Object? rawBeats = j['beats'];
    final List<BeatMode> beats = <BeatMode>[];
    if (rawBeats is List<dynamic>) {
      for (final Object? n in rawBeats) {
        if (beats.length >= bpb) {
          break;
        }
        beats.add(BeatMode.values.firstWhere((BeatMode m) => m.name == n, orElse: () => BeatMode.normal));
      }
    }
    final Object? sound = j['sound'];
    final Object? trainer = j['trainer'];
    final Object? mute = j['muteBars'];
    return RhythmConfig(
      bpm: jsonDouble(j, 'bpm', fallback: 100, min: minBpm, max: maxBpm),
      beatsPerBar: bpb,
      denominator: jsonInt(j, 'denominator', fallback: 4, min: 1, max: 16),
      subdivision: jsonInt(j, 'subdivision', fallback: 1, min: 1, max: 6),
      swing: jsonDouble(j, 'swing', fallback: 0, min: 0, max: 1),
      beats: beats.length == bpb ? beats : List<BeatMode>.generate(bpb, (int i) => i < beats.length ? beats[i] : (i == 0 ? BeatMode.accent : BeatMode.normal)),
      subdivisionAudible: jsonBool(j, 'subdivisionAudible', fallback: true),
      sound: ClickSound.values.firstWhere((ClickSound s) => s.name == sound, orElse: () => ClickSound.madera),
      trainer: trainer is Map<String, dynamic> ? TrainerConfig.fromJson(trainer) : null,
      muteBars: mute is Map<String, dynamic> ? MuteConfig.fromJson(mute) : null,
    ).sanitized();
  }

  /// Duración de un pulso en segundos (60 BPM = 1 s por pulso, sea cual sea
  /// la figura que lo lleva).
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

  TrainerConfig sanitized() => TrainerConfig(
        targetBpm: targetBpm.isFinite ? targetBpm.clamp(RhythmConfig.minBpm, RhythmConfig.maxBpm).toDouble() : 120,
        stepBpm: stepBpm.isFinite ? stepBpm.abs().clamp(1.0, 20.0).toDouble() : 4,
        everyBars: everyBars.clamp(1, 16),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{'targetBpm': targetBpm, 'stepBpm': stepBpm, 'everyBars': everyBars};

  static TrainerConfig fromJson(Map<String, dynamic> j) => TrainerConfig(
        targetBpm: jsonDouble(j, 'targetBpm', fallback: 120, min: RhythmConfig.minBpm, max: RhythmConfig.maxBpm),
        stepBpm: jsonDouble(j, 'stepBpm', fallback: 4, min: 1, max: 20),
        everyBars: jsonInt(j, 'everyBars', fallback: 4, min: 1, max: 16),
      );
}

/// Compases que suenan y compases mudos, en ciclo.
class MuteConfig {
  const MuteConfig({this.soundBars = 2, this.muteBarsCount = 1});

  final int soundBars;
  final int muteBarsCount;

  MuteConfig sanitized() => MuteConfig(soundBars: soundBars.clamp(1, 8), muteBarsCount: muteBarsCount.clamp(1, 8));

  Map<String, dynamic> toJson() => <String, dynamic>{'soundBars': soundBars, 'muteBars': muteBarsCount};

  static MuteConfig fromJson(Map<String, dynamic> j) => MuteConfig(
        soundBars: jsonInt(j, 'soundBars', fallback: 2, min: 1, max: 8),
        muteBarsCount: jsonInt(j, 'muteBars', fallback: 1, min: 1, max: 8),
      );
}

/// Un golpe programado.
class ClickEvent {
  const ClickEvent({
    required this.sample,
    required this.bar,
    required this.beat,
    required this.sub,
    required this.kind,
    required this.audible,
    required this.bpm,
    required this.beatStart,
    required this.beatLength,
    required this.beatCount,
  });

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

  /// Muestra en que empieza el pulso de este golpe y su duración en
  /// muestras: con ellas la fase del péndulo es exacta, con swing o sin él.
  final double beatStart;
  final double beatLength;

  /// Pulsos contados desde el inicio (el péndulo alterna con este número).
  final int beatCount;

  double seconds(int sampleRate) => sample / sampleRate;
}

/// Genera los golpes en orden a partir de la configuración. Un cambio de
/// configuración con el metrónomo en marcha (tempo, compás, subdivisión,
/// swing, pulsos) se aplica desde el pulso siguiente: el pulso en curso
/// termina con su rejilla y el siguiente empieza justo donde le toca.
class ClickScheduler {
  ClickScheduler(RhythmConfig config, {this.sampleRate = 44100, int startSample = 0})
      : _config = config.sanitized(),
        _beatStart = startSample.toDouble(),
        _currentBpm = config.sanitized().bpm {
    _beatLength = _lengthFor(_currentBpm);
  }

  final int sampleRate;
  RhythmConfig _config;
  RhythmConfig? _pending;
  double _beatStart;
  double _beatLength = 0;
  int _bar = 0;
  int _beat = 0;
  int _sub = 0;
  int _beatCount = 0;
  double _currentBpm;
  int _barsAtCurrentBpm = 0;

  /// Tope de golpes por llamada: nunca un bucle sin fin.
  static const int maxEventsPerCall = 4096;

  /// Configuración del pulso que está sonando.
  RhythmConfig get config => _config;

  double get currentBpm => _currentBpm;

  int get bar => _bar;

  /// Cambia la configuración en caliente: rige desde el pulso siguiente.
  void update(RhythmConfig c) {
    _pending = c.sanitized();
  }

  double _lengthFor(double bpm) => 60.0 / bpm * sampleRate;

  /// Desplazamiento de la subdivisión [sub] dentro del pulso.
  double _offset(int sub) {
    if (sub == 0) {
      return 0;
    }
    final RhythmConfig c = _config;
    if (c.subdivision == 2 && c.swing > 0) {
      // Con swing la primera corchea se alarga: 0,5 recto … 0,667 tresillo.
      return _beatLength * (0.5 + c.swing / 6);
    }
    return _beatLength * sub / c.subdivision;
  }

  /// Golpes cuya posición es menor que [untilSample].
  List<ClickEvent> eventsUntil(int untilSample) {
    final List<ClickEvent> out = <ClickEvent>[];
    while (out.length < maxEventsPerCall) {
      if (_sub == 0 && _pending != null) {
        // El pulso que sigue aún no ha sonado: ya rige con la configuración nueva.
        _applyPending();
      }
      final double next = _beatStart + _offset(_sub);
      if (next >= untilSample) {
        break;
      }
      out.add(_emit(next));
      _advance();
    }
    return out;
  }

  ClickEvent _emit(double position) {
    final RhythmConfig c = _config;
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
    return ClickEvent(
      sample: position.round(),
      bar: _bar,
      beat: _beat,
      sub: _sub,
      kind: kind,
      audible: audible,
      bpm: _currentBpm,
      beatStart: _beatStart,
      beatLength: _beatLength,
      beatCount: _beatCount,
    );
  }

  bool _isBarMuted(int bar) {
    final MuteConfig? m = _config.muteBars;
    if (m == null) {
      return false;
    }
    final int cycle = m.soundBars + m.muteBarsCount;
    return bar % cycle >= m.soundBars;
  }

  void _applyPending() {
    final RhythmConfig? p = _pending;
    if (p == null) {
      return;
    }
    _pending = null;
    final bool tempoChanged = p.bpm != _config.bpm;
    _config = p;
    if (tempoChanged || p.trainer == null) {
      _currentBpm = p.bpm;
      _barsAtCurrentBpm = 0;
    }
    if (_beat >= _config.beatsPerBar) {
      // El compás nuevo es más corto: este pulso abre el compás siguiente.
      _beat = 0;
      _bar += 1;
    }
    _beatLength = _lengthFor(_currentBpm);
  }

  void _advance() {
    _sub += 1;
    if (_sub < _config.subdivision) {
      return;
    }
    // Termina el pulso: el siguiente empieza exactamente donde acaba este.
    _sub = 0;
    _beatStart += _beatLength;
    _beat += 1;
    _beatCount += 1;
    if (_beat >= _config.beatsPerBar) {
      _beat = 0;
      _bar += 1;
      _barsAtCurrentBpm += 1;
      _applyTrainer();
    }
    _beatLength = _lengthFor(_currentBpm);
  }

  void _applyTrainer() {
    final TrainerConfig? t = _config.trainer;
    if (t == null) {
      return;
    }
    if (_barsAtCurrentBpm >= t.everyBars) {
      _barsAtCurrentBpm = 0;
      if (_currentBpm < t.targetBpm) {
        _currentBpm = (_currentBpm + t.stepBpm).clamp(RhythmConfig.minBpm, t.targetBpm).toDouble();
      } else if (_currentBpm > t.targetBpm) {
        _currentBpm = (_currentBpm - t.stepBpm).clamp(t.targetBpm, RhythmConfig.maxBpm).toDouble();
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
    while (_recent.length > 512) {
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
