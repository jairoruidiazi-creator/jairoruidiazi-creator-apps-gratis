import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../music/instruments.dart';
import '../music/notes.dart';
import 'pitch_detector.dart';

/// Una lectura del afinador lista para pintar.
class TunerReading {
  const TunerReading({required this.note, required this.clarity, required this.rms, required this.stringIndex, required this.inTune});

  final NoteReading note;
  final double clarity;
  final double rms;

  /// Cuerda detectada del instrumento (o -1).
  final int stringIndex;
  final bool inTune;
}

/// Punto del historial de estabilidad: tiempo relativo y cents.
class CentsPoint {
  const CentsPoint(this.t, this.cents, this.midi);

  final double t;
  final double cents;
  final int midi;
}

/// Afinador: captura el micrófono, detecta el tono y lo interpreta según
/// los ajustes (referencia, temperamento, transposición, instrumento).
class Tuner extends ChangeNotifier {
  Tuner({AudioRecorder? recorder, PitchDetector? detector, this.sampleRate = 44100, this.microphoneEnabled = true})
      : _recorder = recorder,
        _detector = detector ?? PitchDetector(sampleRate: sampleRate);

  AudioRecorder? _recorder;
  final PitchDetector _detector;
  final int sampleRate;

  /// Falso en pruebas y en equipos sin micrófono: [start] no hace nada.
  final bool microphoneEnabled;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  PitchSettings settings = const PitchSettings();
  Instrument instrument = Instruments.all.first;

  /// Cents dentro de los cuales la nota se da por afinada.
  double toleranceCents = 5;

  /// Amortiguación de la aguja: 0 (sin suavizar) a 0,95.
  double damping = 0.6;

  /// Cuerda fijada manualmente (-1 = detección automática).
  int lockedString = -1;

  /// Segundos que se conserva una lectura cuando se apaga el sonido.
  double holdSeconds = 1.2;

  static const int bufferFrames = 8192;
  final Float32List _ring = Float32List(bufferFrames);
  int _ringPos = 0;
  int _filled = 0;
  StreamSubscription<Uint8List>? _sub;
  Timer? _timer;
  bool _listening = false;
  bool _permissionDenied = false;
  TunerReading? _reading;
  double _smoothCents = 0;
  int _smoothMidi = -1;
  DateTime? _lastVoiced;
  final List<CentsPoint> _history = <CentsPoint>[];
  final Stopwatch _clock = Stopwatch()..start();
  double _lastHz = 0;

  bool get listening => _listening;

  bool get permissionDenied => _permissionDenied;

  TunerReading? get reading => _reading;

  double get lastHz => _lastHz;

  /// Últimos segundos de desviación en cents (para la gráfica).
  List<CentsPoint> get history => List<CentsPoint>.unmodifiable(_history);

  double get now => _clock.elapsedMicroseconds / 1e6;

  Future<void> start() async {
    if (_listening || !microphoneEnabled) {
      return;
    }
    try {
      final bool ok = await _rec.hasPermission();
      if (!ok) {
        _permissionDenied = true;
        notifyListeners();
        return;
      }
      _permissionDenied = false;
      final Stream<Uint8List> stream = await _rec.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      _sub = stream.listen(_onChunk, onError: (Object e) => debugPrint('Micrófono: $e'));
      _listening = true;
      _timer = Timer.periodic(const Duration(milliseconds: 60), (_) => _analyze());
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudo iniciar el micrófono: $e');
      _listening = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    if (_listening) {
      try {
        await _rec.stop();
      } catch (_) {}
    }
    _listening = false;
    _reading = null;
    notifyListeners();
  }

  void _onChunk(Uint8List bytes) {
    final Float32List f = pcm16ToFloat(bytes);
    for (int i = 0; i < f.length; i++) {
      _ring[_ringPos] = f[i];
      _ringPos = (_ringPos + 1) % bufferFrames;
    }
    _filled += f.length;
  }

  /// Entrega directa de muestras (para pruebas sin micrófono).
  @visibleForTesting
  void feed(Float32List samples) {
    for (int i = 0; i < samples.length; i++) {
      _ring[_ringPos] = samples[i];
      _ringPos = (_ringPos + 1) % bufferFrames;
    }
    _filled += samples.length;
    _analyze();
  }

  void _analyze() {
    if (_filled < bufferFrames) {
      return;
    }
    // Copia ordenada del anillo (del más antiguo al más reciente).
    final Float32List buf = Float32List(bufferFrames);
    for (int i = 0; i < bufferFrames; i++) {
      buf[i] = _ring[(_ringPos + i) % bufferFrames];
    }
    final PitchResult r = _detector.detect(buf);
    final double t = now;
    if (!r.hasPitch || r.clarity < 0.6) {
      // Mantiene la última lectura un momento para que la aguja no parpadee.
      if (_lastVoiced != null && DateTime.now().difference(_lastVoiced!).inMilliseconds > holdSeconds * 1000) {
        if (_reading != null) {
          _reading = null;
          _smoothMidi = -1;
          notifyListeners();
        }
      }
      _trimHistory(t);
      return;
    }
    _lastVoiced = DateTime.now();
    _lastHz = r.frequency;
    final NoteReading note = settings.read(r.frequency);
    double cents = note.cents;
    if (_smoothMidi == note.midi) {
      cents = _smoothCents * damping + note.cents * (1 - damping);
    }
    _smoothMidi = note.midi;
    _smoothCents = cents;
    final NoteReading smoothed = NoteReading(midi: note.midi, cents: cents, targetHz: note.targetHz, hz: note.hz);
    int stringIndex = -1;
    if (instrument.hasStrings) {
      stringIndex = lockedString >= 0 ? lockedString : instrument.nearestString(Notes.hzToMidi(r.frequency, a4: settings.a4));
    }
    final NoteReading shown = lockedString >= 0 && instrument.hasStrings ? _relativeToString(r.frequency, instrument.strings[lockedString]) : smoothed;
    _reading = TunerReading(note: shown, clarity: r.clarity, rms: r.rms, stringIndex: stringIndex, inTune: shown.cents.abs() <= toleranceCents);
    _history.add(CentsPoint(t, shown.cents, shown.midi));
    _trimHistory(t);
    notifyListeners();
  }

  /// Con una cuerda fijada, los cents se miden contra esa cuerda aunque la
  /// nota esté lejos (hasta ±200 cents), para guiar el giro de la clavija.
  NoteReading _relativeToString(double hz, int stringMidi) {
    final double target = Notes.frequency(stringMidi, a4: settings.a4, temperament: settings.temperament, root: settings.temperamentRoot, custom: settings.custom);
    final double cents = (1200 * (log2(hz / target))).clamp(-200.0, 200.0).toDouble();
    return NoteReading(midi: stringMidi, cents: cents, targetHz: target, hz: hz);
  }

  void _trimHistory(double t) {
    while (_history.isNotEmpty && t - _history.first.t > 6) {
      _history.removeAt(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    final AudioRecorder? r = _recorder;
    if (r != null) {
      unawaited(r.dispose());
    }
    super.dispose();
  }
}

double log2(double x) => x <= 0 ? 0 : math.log(x) / math.ln2;
