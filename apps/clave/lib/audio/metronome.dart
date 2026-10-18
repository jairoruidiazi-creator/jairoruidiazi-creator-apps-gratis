import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'audio_engine.dart';
import 'click_synth.dart';
import 'haptics.dart';
import 'sequencer.dart';

/// Estado visible del pulso actual.
class BeatState {
  const BeatState({required this.bar, required this.beat, required this.sub, required this.kind, required this.phase, required this.bpm, required this.running, this.beatCount = 0, this.audible = true});

  final int bar;
  final int beat;
  final int sub;
  final BeatKind kind;

  /// Fracción transcurrida del pulso actual (0 a 1), para el péndulo.
  final double phase;
  final double bpm;
  final bool running;

  /// Pulsos desde que arrancó: el péndulo va y viene alternando con él,
  /// también en compases de 3, 5 o 7 pulsos.
  final int beatCount;

  /// false en pulsos de silencio y compases mudos (no destellan).
  final bool audible;

  static const BeatState idle = BeatState(bar: 0, beat: 0, sub: 0, kind: BeatKind.accent, phase: 0, bpm: 0, running: false);
}

/// Metrónomo: genera el audio por bloques adelantándose al reloj del motor,
/// y expone el pulso actual leyendo cuánto audio se ha consumido. Así las
/// luces, el péndulo y la vibración van atados al sonido y no a un Timer.
///
/// [ChangeNotifier] avisa de los cambios de configuración y de marcha; el
/// pulso de la animación (60 veces por segundo) va aparte en [beat].
class Metronome extends ChangeNotifier {
  Metronome(this.engine, {this.sampleRate = 44100, Haptics? haptics}) : haptics = haptics ?? const NoHaptics();

  final AudioEngine engine;
  final int sampleRate;
  final Haptics haptics;
  final ClickSynth _synth = ClickSynth();

  RhythmConfig _config = const RhythmConfig();
  RhythmConfig get config => _config;

  bool hapticsEnabled = false;
  bool flashEnabled = false;

  /// Retraso del audio en milisegundos (0 a 400): el sonido que el
  /// mezclador ya consumió tarda este tiempo en oírse (salida del teléfono y
  /// audífonos Bluetooth), así que la animación y la vibración se retrasan lo
  /// mismo. Positivo = el audio llega tarde.
  int audioDelayMs = 0;
  double volume = 1.0;

  /// Pulso actual para la animación.
  final ValueNotifier<BeatState> beat = ValueNotifier<BeatState>(BeatState.idle);

  PcmStream? _stream;
  ClickScheduler? _scheduler;
  ClickRenderer? _renderer;
  Timer? _feeder;
  Timer? _ticker;
  int _lastHapticSample = -1;
  int _tapCount = 0;
  DateTime? _lastTap;
  final List<int> _tapIntervals = <int>[];
  bool _starting = false;

  /// Tiempo de audio que se mantiene generado por delante del consumo.
  static const double lookaheadSeconds = 0.18;
  static const int chunkFrames = 2048;

  BeatState get state => beat.value;

  bool get running => _stream != null;

  /// Tempo vigente (con el entrenador puede diferir del configurado).
  double get currentBpm => _scheduler?.currentBpm ?? _config.bpm;

  /// Sonido del clic que suena (el afinador no cuenta sus frecuencias).
  ClickSound get sound => _config.sound;

  void setConfig(RhythmConfig c) {
    _config = c.sanitized();
    _scheduler?.update(_config);
    notifyListeners();
  }

  void setBpm(double bpm) => setConfig(_config.copyWith(bpm: bpm.clamp(RhythmConfig.minBpm, RhythmConfig.maxBpm).toDouble()));

  Future<void> start() async {
    if (running || _starting) {
      return;
    }
    _starting = true;
    PcmStream? s;
    try {
      s = await engine.openPcmStream(sampleRate: sampleRate, bufferingSeconds: 0.03);
    } finally {
      _starting = false;
    }
    if (s == null) {
      return;
    }
    _stream = s;
    _scheduler = ClickScheduler(_config, sampleRate: sampleRate, startSample: (sampleRate * 0.05).round());
    _renderer = ClickRenderer(_scheduler!, _synth, volume: volume);
    _lastHapticSample = -1;
    _feed();
    _feeder = Timer.periodic(const Duration(milliseconds: 25), (_) => _feed());
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    notifyListeners();
  }

  Future<void> stop() async {
    final PcmStream? s = _stream;
    _feeder?.cancel();
    _ticker?.cancel();
    _feeder = null;
    _ticker = null;
    _stream = null;
    _scheduler = null;
    _renderer = null;
    beat.value = BeatState.idle;
    notifyListeners();
    if (s != null) {
      await engine.closePcmStream(s);
    }
  }

  Future<void> toggle() => running ? stop() : start();

  void _feed() {
    final PcmStream? s = _stream;
    final ClickRenderer? r = _renderer;
    if (s == null || r == null) {
      return;
    }
    r.volume = volume;
    final double consumed = engine.consumedSeconds(s);
    final int target = ((consumed + lookaheadSeconds) * sampleRate).ceil();
    int guard = 0;
    while (r.renderedSamples < target && guard < 40) {
      guard += 1;
      engine.pushPcm(s, floatToPcm16(r.render(chunkFrames)));
    }
  }

  /// Muestra que se está oyendo ahora: lo consumido menos el retraso.
  int _heardSample(PcmStream s) {
    final double heard = engine.consumedSeconds(s) - audioDelayMs / 1000.0;
    return (heard * sampleRate).round();
  }

  void _tick() {
    final PcmStream? s = _stream;
    final ClickRenderer? r = _renderer;
    if (s == null || r == null) {
      return;
    }
    final int sample = _heardSample(s);
    final ClickEvent? e = r.eventAt(sample);
    if (e == null) {
      return;
    }
    final double phase = e.beatLength <= 0 ? 0 : ((sample - e.beatStart) / e.beatLength).clamp(0.0, 1.0).toDouble();
    final BeatState next = BeatState(bar: e.bar, beat: e.beat, sub: e.sub, kind: e.kind, phase: phase, bpm: e.bpm, running: true, beatCount: e.beatCount, audible: e.audible);
    if (e.sample != _lastHapticSample) {
      _lastHapticSample = e.sample;
      if (hapticsEnabled && e.sub == 0 && e.audible) {
        haptics.pulse(accent: e.kind == BeatKind.accent);
      }
    }
    beat.value = next;
  }

  /// Tap tempo: promedia los últimos intervalos entre toques.
  double? tap() {
    final DateTime now = clock.now();
    final DateTime? last = _lastTap;
    _lastTap = now;
    if (last == null || now.difference(last).inMilliseconds > 2500) {
      _tapIntervals.clear();
      _tapCount = 1;
      return null;
    }
    _tapIntervals.add(now.difference(last).inMilliseconds);
    while (_tapIntervals.length > 6) {
      _tapIntervals.removeAt(0);
    }
    _tapCount += 1;
    final double avg = _tapIntervals.reduce((int a, int b) => a + b) / _tapIntervals.length;
    if (avg <= 0) {
      return null;
    }
    final double bpm = (60000 / avg).clamp(RhythmConfig.minBpm, RhythmConfig.maxBpm).toDouble();
    setBpm(bpm.roundToDouble());
    return bpm;
  }

  int get tapCount => _tapCount;

  @override
  void dispose() {
    _feeder?.cancel();
    _ticker?.cancel();
    final PcmStream? s = _stream;
    _stream = null;
    if (s != null) {
      unawaited(engine.closePcmStream(s));
    }
    beat.dispose();
    super.dispose();
  }
}
