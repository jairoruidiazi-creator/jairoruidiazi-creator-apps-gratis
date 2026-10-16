import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_engine.dart';
import 'click_synth.dart';
import 'sequencer.dart';

/// Estado visible del pulso actual.
class BeatState {
  const BeatState({required this.bar, required this.beat, required this.sub, required this.kind, required this.phase, required this.bpm, required this.running});

  final int bar;
  final int beat;
  final int sub;
  final BeatKind kind;

  /// Fracción transcurrida del pulso actual (0 a 1), para el péndulo.
  final double phase;
  final double bpm;
  final bool running;

  static const BeatState idle = BeatState(bar: 0, beat: 0, sub: 0, kind: BeatKind.accent, phase: 0, bpm: 0, running: false);
}

/// Metrónomo: genera el audio por bloques adelantándose al reloj del motor,
/// y expone el pulso actual leyendo cuánto audio se ha consumido. Así las
/// luces, el péndulo y la vibración van atados al sonido y no a un Timer.
class Metronome extends ChangeNotifier {
  Metronome(this.engine, {this.sampleRate = 44100});

  final AudioEngine engine;
  final int sampleRate;
  final ClickSynth _synth = ClickSynth();

  RhythmConfig _config = const RhythmConfig();
  RhythmConfig get config => _config;

  bool hapticsEnabled = false;
  bool flashEnabled = true;

  /// Desfase visual en milisegundos (positivo = adelantar la animación),
  /// para compensar la latencia de salida o los audífonos Bluetooth.
  int visualOffsetMs = 0;
  double volume = 1.0;

  PcmStream? _stream;
  ClickScheduler? _scheduler;
  ClickRenderer? _renderer;
  Timer? _feeder;
  Timer? _ticker;
  BeatState _state = BeatState.idle;
  int _lastHapticSample = -1;
  int _tapCount = 0;
  DateTime? _lastTap;
  final List<int> _tapIntervals = <int>[];

  /// Tiempo de audio que se mantiene generado por delante del consumo.
  static const double lookaheadSeconds = 0.18;
  static const int chunkFrames = 2048;

  BeatState get state => _state;

  bool get running => _stream != null;

  /// Tempo vigente (con el entrenador puede diferir del configurado).
  double get currentBpm => _scheduler?.currentBpm ?? _config.bpm;

  void setConfig(RhythmConfig c) {
    _config = c;
    _scheduler?.update(c);
    notifyListeners();
  }

  void setBpm(double bpm) => setConfig(_config.copyWith(bpm: bpm.clamp(20.0, 400.0).toDouble()));

  Future<void> start() async {
    if (running) {
      return;
    }
    final PcmStream? s = await engine.openPcmStream(sampleRate: sampleRate, bufferingSeconds: 0.03);
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
    _state = BeatState.idle;
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

  void _tick() {
    final PcmStream? s = _stream;
    final ClickRenderer? r = _renderer;
    if (s == null || r == null) {
      return;
    }
    final double consumed = engine.consumedSeconds(s) + visualOffsetMs / 1000.0;
    final int sample = (consumed * sampleRate).round();
    final ClickEvent? e = r.eventAt(sample);
    if (e == null) {
      return;
    }
    final double subSeconds = 60.0 / e.bpm / _config.subdivision;
    final double beatSeconds = 60.0 / e.bpm;
    // Fase del pulso: posición dentro del pulso, contando las subdivisiones.
    final double sinceEvent = (sample - e.sample) / sampleRate;
    final double phase = ((e.sub * subSeconds + sinceEvent) / beatSeconds).clamp(0.0, 1.0).toDouble();
    final BeatState next = BeatState(bar: e.bar, beat: e.beat, sub: e.sub, kind: e.kind, phase: phase, bpm: e.bpm, running: true);
    final bool newEvent = e.sample != _lastHapticSample;
    if (newEvent) {
      _lastHapticSample = e.sample;
      if (hapticsEnabled && e.sub == 0 && e.audible) {
        if (e.kind == BeatKind.accent) {
          unawaited(HapticFeedback.heavyImpact());
        } else {
          unawaited(HapticFeedback.lightImpact());
        }
      }
    }
    _state = next;
    notifyListeners();
  }

  /// Tap tempo: promedia los últimos intervalos entre toques.
  double? tap() {
    final DateTime now = DateTime.now();
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
    final double bpm = (60000 / avg).clamp(20.0, 400.0).toDouble();
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
    super.dispose();
  }
}
