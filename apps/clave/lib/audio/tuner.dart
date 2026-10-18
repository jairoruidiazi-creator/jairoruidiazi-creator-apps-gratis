import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../music/instruments.dart';
import '../music/notes.dart';
import 'mic_capture.dart';
import 'pitch_detector.dart';

/// Una lectura del afinador lista para pintar.
class TunerReading {
  const TunerReading({required this.note, required this.clarity, required this.rms, required this.stringIndex, required this.inTune});

  final NoteReading note;
  final double clarity;
  final double rms;

  /// Orden de cuerdas detectado o fijado (o -1).
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

/// Estado del micrófono del afinador.
enum MicStatus {
  /// Apagado: por la persona, porque la pestaña no se ve o la app no está al frente.
  off,

  /// Falta pedir el permiso: se muestra la explicación antes del diálogo.
  needsPermission,

  /// El permiso se negó: solo se puede dar en los ajustes del sistema.
  denied,

  /// Escuchando.
  listening,

  /// El sistema pausó la captura (llamada, Siri) o dejaron de llegar muestras.
  interrupted,

  /// La grabadora está usando el micrófono.
  busy,

  /// No se pudo abrir el micrófono.
  error,
}

/// Decide cuándo lo que se oye es un tono estable de instrumento (y no ruido,
/// habla suelta, golpes ni los propios sonidos de la app). Solo entonces el
/// afinador cuenta como práctica.
class ToneStability {
  ToneStability({this.minClarity = 0.85, this.minDuration = const Duration(milliseconds: 400), this.maxGap = const Duration(milliseconds: 150)});

  final double minClarity;
  final Duration minDuration;
  final Duration maxGap;

  DateTime? _since;
  DateTime? _last;
  int _midi = -1000;
  bool _stable = false;

  bool get stable => _stable;

  void reset() {
    _since = null;
    _last = null;
    _midi = -1000;
    _stable = false;
  }

  /// Registra un análisis. Devuelve true si este análisis cuenta: tono claro,
  /// sostenido (sin envolvente de golpe), que no es un sonido de la app y que
  /// lleva al menos [minDuration] en la misma nota (± 1 semitono por paso,
  /// para seguir el giro de la clavija).
  bool update(DateTime now, {required bool voiced, required double midi, required double clarity, required bool impulsive, required bool ownSound}) {
    final bool candidate = voiced && clarity >= minClarity && !impulsive && !ownSound;
    final DateTime? last = _last;
    final bool gap = last == null || now.difference(last) > maxGap;
    if (!candidate) {
      if (gap) {
        reset();
      }
      return false;
    }
    final int m = midi.round();
    if (_since == null || gap || (m - _midi).abs() > 1) {
      _since = now;
    }
    _midi = m;
    _last = now;
    _stable = now.difference(_since!) >= minDuration;
    return _stable;
  }
}

/// Afinador: captura el micrófono, detecta el tono y lo interpreta según
/// los ajustes (referencia, temperamento, transposición, instrumento y capo).
///
/// Solo escucha cuando la persona lo quiere ([userEnabled]), su pestaña se ve
/// y la app está al frente ([setActive]) y la grabadora no tiene el micrófono
/// ([setMicBusy]). Al dejar de cumplirse cualquiera de las tres, suelta el
/// micrófono; al volver a cumplirse, lo abre otra vez.
class Tuner extends ChangeNotifier {
  Tuner({MicCapture? mic, PitchDetector? detector, this.sampleRate = 44100, this.microphoneEnabled = true})
      : _mic = mic,
        _detector = detector ?? PitchDetector(sampleRate: sampleRate);

  MicCapture? _mic;
  final PitchDetector _detector;
  final int sampleRate;

  /// Falso en pruebas y en equipos sin micrófono: nunca abre la captura.
  final bool microphoneEnabled;

  MicCapture get _capture => _mic ??= RecordMicCapture();

  PitchSettings settings = const PitchSettings();
  Instrument instrument = Instruments.all.first;

  /// Cents dentro de los cuales la nota se da por afinada.
  double toleranceCents = 5;

  /// Amortiguación de la aguja: 0 (sin suavizar) a 0,95.
  double damping = 0.6;

  /// Orden fijado manualmente (-1 = detección automática).
  int lockedString = -1;

  /// Segundos que se conserva una lectura cuando se apaga el sonido.
  double holdSeconds = 1.2;

  /// Si ya se pidió el permiso alguna vez (la app lo guarda en los ajustes).
  bool permissionAsked = false;

  /// Se llama la primera vez que se pide el permiso.
  VoidCallback? onPermissionAsked;

  /// Se llama en cada análisis con un tono estable de instrumento.
  VoidCallback? onStableTone;

  /// Frecuencias que está sonando la propia app (clics del metrónomo, bordón,
  /// teclado): no cuentan como práctica del afinador.
  List<double> Function()? ownFrequencies;

  static const int bufferFrames = 8192;
  static const Duration analysisPeriod = Duration(milliseconds: 60);

  /// Sin muestras nuevas durante este tiempo, la captura se da por detenida.
  static const Duration stallTimeout = Duration(milliseconds: 500);

  final Float32List _ring = Float32List(bufferFrames);
  int _ringPos = 0;
  int _filled = 0;
  int _analyzedAt = 0;
  DateTime? _lastChunkAt;
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<bool>? _pausedSub;
  Timer? _timer;
  MicStatus _status = MicStatus.off;
  bool _userEnabled = true;
  bool _active = false;
  bool _busy = false;
  bool _capturing = false;
  Future<void> _ops = Future<void>.value();
  TunerReading? _reading;
  double _smoothCents = 0;
  int _smoothMidi = -1;
  DateTime? _lastVoiced;
  final List<CentsPoint> _history = <CentsPoint>[];
  final DateTime _epoch = clock.now();
  double _lastHz = 0;
  final ToneStability stability = ToneStability();
  bool _stableNow = false;

  MicStatus get status => _status;

  bool get listening => _status == MicStatus.listening;

  bool get permissionDenied => _status == MicStatus.denied;

  /// Lo que la persona eligió con el botón del micrófono.
  bool get userEnabled => _userEnabled;

  bool get active => _active;

  /// true si el último análisis contó como tono estable de instrumento.
  bool get stableTone => _stableNow;

  TunerReading? get reading => _reading;

  double get lastHz => _lastHz;

  /// Últimos segundos de desviación en cents (para la gráfica).
  List<CentsPoint> get history => List<CentsPoint>.unmodifiable(_history);

  double get now => clock.now().difference(_epoch).inMicroseconds / 1e6;

  /// Pestaña visible y app al frente.
  void setActive(bool value) {
    if (_active == value) {
      return;
    }
    _active = value;
    _reconcile();
  }

  /// La grabadora toma o suelta el micrófono.
  void setMicBusy(bool value) {
    if (_busy == value) {
      return;
    }
    _busy = value;
    _reconcile();
  }

  /// El botón del micrófono.
  void setUserEnabled(bool value) {
    if (_userEnabled == value) {
      return;
    }
    _userEnabled = value;
    _reconcile();
  }

  Future<void> toggle() async {
    setUserEnabled(!_userEnabled);
    await _ops;
  }

  /// Para compatibilidad con la grabadora y las pruebas: espera a que se
  /// aplique el estado pedido.
  Future<void> settle() => _ops;

  /// La persona aceptó la explicación: se muestra el diálogo del sistema.
  Future<void> requestPermission() {
    _ops = _ops.then((_) async {
      permissionAsked = true;
      onPermissionAsked?.call();
      bool ok = false;
      try {
        ok = await _capture.hasPermission(request: true);
      } catch (e) {
        debugPrint('Permiso de micrófono: $e');
      }
      if (!ok) {
        _setStatus(MicStatus.denied);
        return;
      }
      await _apply();
    });
    return _ops;
  }

  /// Vuelve a mirar el permiso (al volver de los ajustes del sistema).
  void recheck() => _reconcile();

  void _reconcile() {
    _ops = _ops.then((_) => _apply());
  }

  bool get _shouldListen => microphoneEnabled && _userEnabled && _active && !_busy;

  Future<void> _apply() async {
    if (!_shouldListen) {
      await _closeCapture();
      _setStatus(_busy && _userEnabled && _active ? MicStatus.busy : MicStatus.off);
      return;
    }
    if (_capturing) {
      return;
    }
    bool granted = false;
    try {
      granted = await _capture.hasPermission(request: false);
    } catch (e) {
      debugPrint('Permiso de micrófono: $e');
    }
    if (!_shouldListen) {
      _setStatus(MicStatus.off);
      return;
    }
    if (!granted) {
      _setStatus(permissionAsked ? MicStatus.denied : MicStatus.needsPermission);
      return;
    }
    try {
      final Stream<Uint8List> stream = await _capture.start(sampleRate);
      _capturing = true;
      _filled = 0;
      _analyzedAt = 0;
      _lastChunkAt = clock.now();
      _sub = stream.listen(_onChunk, onError: (Object e) => debugPrint('Micrófono: $e'));
      _pausedSub = _capture.paused.listen((bool p) {
        if (p) {
          // Lo que quedó en el búfer es de antes de la interrupción: al
          // volver se espera un búfer entero de sonido nuevo.
          _discardBuffer();
          _clearReading();
          _setStatus(MicStatus.interrupted);
        } else if (_capturing) {
          _lastChunkAt = clock.now();
          _setStatus(MicStatus.listening);
        }
      });
      _timer = Timer.periodic(analysisPeriod, (_) => _analyze());
      _setStatus(MicStatus.listening);
      // Pudo cambiar el estado mientras se abría el micrófono.
      if (!_shouldListen) {
        await _closeCapture();
        _setStatus(MicStatus.off);
      }
    } catch (e) {
      debugPrint('No se pudo iniciar el micrófono: $e');
      await _closeCapture();
      _setStatus(MicStatus.error);
    }
  }

  Future<void> _closeCapture() async {
    _timer?.cancel();
    _timer = null;
    await _pausedSub?.cancel();
    _pausedSub = null;
    await _sub?.cancel();
    _sub = null;
    if (_capturing) {
      _capturing = false;
      try {
        await _capture.stop();
      } catch (e) {
        debugPrint('No se pudo cerrar el micrófono: $e');
      }
    }
    _clearReading();
  }

  void _setStatus(MicStatus s) {
    if (_status == s) {
      return;
    }
    _status = s;
    notifyListeners();
  }

  void _discardBuffer() {
    _filled = 0;
    _analyzedAt = 0;
  }

  void _clearReading() {
    _reading = null;
    _smoothMidi = -1;
    _stableNow = false;
    stability.reset();
  }

  /// Compatibilidad: detiene la escucha hasta que se vuelva a pedir.
  Future<void> stop() async {
    setUserEnabled(false);
    await _ops;
  }

  /// Compatibilidad: pide escuchar (si la pestaña está activa).
  Future<void> start() async {
    setUserEnabled(true);
    await _ops;
  }

  void _onChunk(Uint8List bytes) {
    _push(pcm16ToFloat(bytes));
  }

  void _push(Float32List f) {
    for (int i = 0; i < f.length; i++) {
      _ring[_ringPos] = f[i];
      _ringPos = (_ringPos + 1) % bufferFrames;
    }
    _filled += f.length;
    _lastChunkAt = clock.now();
  }

  /// Entrega directa de muestras (pruebas y capturas de tienda).
  @visibleForTesting
  void feed(Float32List samples) {
    _push(samples);
    _analyze();
  }

  void _analyze() {
    final DateTime wall = clock.now();
    final DateTime? lastChunk = _lastChunkAt;
    if (_capturing && lastChunk != null && wall.difference(lastChunk) > stallTimeout) {
      // La captura se detuvo sin avisar: no se analiza un búfer viejo, ni
      // ahora ni cuando vuelvan a llegar muestras.
      _discardBuffer();
      if (_reading != null || _stableNow) {
        _clearReading();
        notifyListeners();
      }
      return;
    }
    if (_filled < bufferFrames || _filled == _analyzedAt) {
      return;
    }
    _analyzedAt = _filled;
    final Float32List buf = Float32List(bufferFrames);
    for (int i = 0; i < bufferFrames; i++) {
      buf[i] = _ring[(_ringPos + i) % bufferFrames];
    }
    final PitchResult r = _detector.detect(buf);
    final double t = now;
    if (!r.hasPitch || r.clarity < 0.6) {
      _stableNow = stability.update(wall, voiced: false, midi: 0, clarity: 0, impulsive: false, ownSound: false);
      // Mantiene la última lectura un momento para que la aguja no parpadee.
      final DateTime? lv = _lastVoiced;
      if (_reading != null && lv != null && wall.difference(lv).inMilliseconds > holdSeconds * 1000) {
        _reading = null;
        _smoothMidi = -1;
        notifyListeners();
      }
      _trimHistory(t);
      return;
    }
    _lastVoiced = wall;
    _lastHz = r.frequency;
    final double midiF = Notes.hzToMidi(r.frequency, a4: settings.a4);
    int stringIndex = -1;
    NoteReading target;
    if (instrument.hasStrings && lockedString >= 0 && lockedString < instrument.courses.length) {
      // Cuerda fijada: los cents se miden contra esa cuerda (o su octava), con
      // el capo puesto, hasta ±200 cents para guiar el giro de la clavija.
      stringIndex = lockedString;
      final int targetMidi = instrument.targetInCourse(lockedString, midiF, capo: settings.capo);
      final double targetHz = settings.frequencyOf(targetMidi);
      final double cents = (1200 * log2(r.frequency / targetHz)).clamp(-200.0, 200.0).toDouble();
      target = NoteReading(midi: targetMidi, cents: cents, targetHz: targetHz, hz: r.frequency);
    } else {
      target = settings.read(r.frequency);
      if (instrument.hasStrings) {
        stringIndex = instrument.nearestCourse(midiF, capo: settings.capo).course;
      }
    }
    double cents = target.cents;
    if (_smoothMidi == target.midi) {
      cents = _smoothCents * damping + target.cents * (1 - damping);
    }
    _smoothMidi = target.midi;
    _smoothCents = cents;
    final NoteReading shown = NoteReading(midi: target.midi, cents: cents, targetHz: target.targetHz, hz: target.hz);
    _reading = TunerReading(note: shown, clarity: r.clarity, rms: r.rms, stringIndex: stringIndex, inTune: shown.cents.abs() <= toleranceCents);
    _history.add(CentsPoint(t, shown.cents, shown.midi));
    _trimHistory(t);
    _stableNow = stability.update(wall, voiced: true, midi: midiF, clarity: r.clarity, impulsive: isImpulsive(buf), ownSound: _isOwnSound(r.frequency));
    if (_stableNow) {
      onStableTone?.call();
    }
    notifyListeners();
  }

  bool _isOwnSound(double hz) {
    final List<double>? own = ownFrequencies?.call();
    if (own == null || own.isEmpty) {
      return false;
    }
    for (final double f in own) {
      if (f <= 0) {
        continue;
      }
      // También sus octavas: el detector puede quedarse con una de ellas.
      final double c = 1200 * log2(hz / f);
      final double octaves = c / 1200;
      final double nearest = octaves.roundToDouble();
      if (nearest.abs() <= 2 && (c - nearest * 1200).abs() <= 60) {
        return true;
      }
    }
    return false;
  }

  /// Envolvente de golpe: la energía se concentra en un trozo corto del
  /// búfer (más de 9 dB entre el bloque más fuerte y la mediana).
  @visibleForTesting
  static bool isImpulsive(Float32List buf) {
    const int blocks = 8;
    final int size = buf.length ~/ blocks;
    final List<double> e = <double>[];
    for (int b = 0; b < blocks; b++) {
      double acc = 0;
      for (int i = b * size; i < (b + 1) * size; i++) {
        acc += buf[i] * buf[i];
      }
      e.add(acc / size);
    }
    final List<double> sorted = List<double>.from(e)..sort();
    final double median = (sorted[blocks ~/ 2 - 1] + sorted[blocks ~/ 2]) / 2;
    final double maxE = sorted.last;
    if (median <= 0) {
      return maxE > 0;
    }
    return 10 * math.log(maxE / median) / math.ln10 > 9;
  }

  void _trimHistory(double t) {
    while (_history.isNotEmpty && t - _history.first.t > 6) {
      _history.removeAt(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_sub?.cancel());
    unawaited(_pausedSub?.cancel());
    final MicCapture? m = _mic;
    if (m != null) {
      unawaited(m.dispose());
    }
    super.dispose();
  }
}

double log2(double x) => x <= 0 ? 0 : math.log(x) / math.ln2;
