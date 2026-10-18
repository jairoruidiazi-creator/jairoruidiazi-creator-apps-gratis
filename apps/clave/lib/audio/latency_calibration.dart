import 'dart:async';

import 'audio_engine.dart';
import 'click_synth.dart';
import 'sequencer.dart';

/// Calibración del retraso del audio con toques: suena un clic a 90 BPM y
/// la persona toca al ritmo de lo que oye. Cada toque se compara con el clic
/// más cercano en la línea de tiempo del audio consumido; la diferencia es lo
/// que tarda en oírse el sonido (más el pequeño adelanto o atraso de la mano).
class LatencyCalibration {
  LatencyCalibration(this.engine, {this.sampleRate = 44100});

  final AudioEngine engine;
  final int sampleRate;

  static const double bpm = 90;
  static const int minTaps = 8;

  /// Diferencias de cada toque con su clic, en segundos.
  final List<double> residuals = <double>[];

  PcmStream? _stream;
  ClickRenderer? _renderer;
  Timer? _feeder;
  final int _startSample = 2205;

  bool get running => _stream != null;

  int get taps => residuals.length;

  double get _period => 60 / bpm;

  Future<bool> start() async {
    if (running) {
      return true;
    }
    residuals.clear();
    final PcmStream? s = await engine.openPcmStream(sampleRate: sampleRate, bufferingSeconds: 0.03);
    if (s == null) {
      return false;
    }
    _stream = s;
    final ClickScheduler scheduler = ClickScheduler(
      const RhythmConfig(bpm: bpm, beatsPerBar: 1, beats: <BeatMode>[BeatMode.accent], sound: ClickSound.clave),
      sampleRate: sampleRate,
      startSample: _startSample,
    );
    _renderer = ClickRenderer(scheduler, ClickSynth(sampleRate: sampleRate));
    _feed();
    _feeder = Timer.periodic(const Duration(milliseconds: 25), (_) => _feed());
    return true;
  }

  void _feed() {
    final PcmStream? s = _stream;
    final ClickRenderer? r = _renderer;
    if (s == null || r == null) {
      return;
    }
    final double consumed = engine.consumedSeconds(s);
    final int target = ((consumed + 0.18) * sampleRate).ceil();
    int guard = 0;
    while (r.renderedSamples < target && guard < 40) {
      guard++;
      engine.pushPcm(s, floatToPcm16(r.render(2048)));
    }
  }

  /// Registra un toque. Devuelve la diferencia con su clic (segundos) o null
  /// si todavía no ha sonado ninguno.
  double? tap() {
    final PcmStream? s = _stream;
    if (s == null) {
      return null;
    }
    final double r = residualFor(engine.consumedSeconds(s), firstClick: _startSample / sampleRate, period: _period);
    if (r.isNaN) {
      return null;
    }
    residuals.add(r);
    return r;
  }

  /// Diferencia entre lo consumido al tocar y el clic que corresponde: el que
  /// deja la diferencia entre -0,15 s y un periodo menos 0,15 s.
  static double residualFor(double consumed, {required double firstClick, required double period}) {
    final double x = consumed - firstClick + 0.15;
    if (x < 0) {
      return double.nan;
    }
    final int k = (x / period).floor();
    return consumed - (firstClick + k * period);
  }

  /// Resultado en milisegundos si ya hay suficientes toques coherentes.
  int? get resultMs => estimateDelayMs(residuals);

  /// Mediana de los toques tras descartar los que se alejan más de 60 ms de
  /// la mediana; null con menos de [minTaps] toques o si menos de 6 (y del
  /// 60 %) quedan cerca. Acotado a 0..400 ms.
  static int? estimateDelayMs(List<double> residuals) {
    if (residuals.length < minTaps) {
      return null;
    }
    final List<double> sorted = List<double>.from(residuals)..sort();
    final double median = _median(sorted);
    final List<double> kept = sorted.where((double r) => (r - median).abs() <= 0.06).toList();
    if (kept.length < 6 || kept.length < (residuals.length * 0.6).ceil()) {
      return null;
    }
    return (_median(kept) * 1000).round().clamp(0, 400);
  }

  static double _median(List<double> sorted) {
    final int n = sorted.length;
    return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  Future<void> stop() async {
    _feeder?.cancel();
    _feeder = null;
    final PcmStream? s = _stream;
    _stream = null;
    _renderer = null;
    if (s != null) {
      await engine.closePcmStream(s);
    }
  }
}
