import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../music/instruments.dart';
import '../music/notes.dart';
import 'mic_capture.dart';
import 'pitch_detector.dart';
import 'spectrum.dart';

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

/// Por qué el afinador no muestra lectura aunque oye un tono claro.
enum TunerNotice {
  none,

  /// Suena más grave que el rango del perfil elegido.
  belowRange,

  /// La lectura cae en un subarmónico de un tono de la propia app (bordón,
  /// quinta, teclas o acorde): es la mezcla con ese tono, no la nota.
  ownTone,
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
  Instrument _instrument = Instruments.all.first;

  Instrument get instrument => _instrument;

  /// Al cambiar de instrumento, un aviso del anterior ya no vale.
  set instrument(Instrument value) {
    if (identical(value, _instrument)) {
      return;
    }
    _instrument = value;
    _residueSince = null;
    _belowSince = null;
    _cleanSince = null;
    if (_notice != TunerNotice.none) {
      _notice = TunerNotice.none;
      _noticeAt = null;
      notifyListeners();
    }
  }

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

  /// Tonos sostenidos que suena la propia app ahora (bordón, quinta, teclas
  /// y acordes, sin los clics del metrónomo): una lectura en f/k de uno de
  /// ellos (k de 2 a 8) es la mezcla con ese tono y no se muestra.
  List<double> Function()? ownTones;

  /// Cuánto se mantiene el aviso del bordón sin que se repita.
  static const Duration noticeHold = Duration(milliseconds: 600);

  /// El aviso de nota bajo el rango (con su botón «Usar Cromático») se
  /// mantiene más: quien toca tiene que soltar el instrumento para tocar el
  /// botón, y con el lector de pantalla llegar a él lleva tiempo.
  static const Duration rangeNoticeHold = Duration(seconds: 5);

  /// Tiempo seguido de residuo para pasar al aviso del bordón, y de notas
  /// para dejarlo (sin parpadeo entre la lectura y el aviso).
  static const Duration noticeDelay = Duration(milliseconds: 300);

  /// Prominencia mínima (dB) sobre el piso entre armónicos para contar un
  /// armónico de la lectura como sonido propio de lo que se toca (ver
  /// [isResidue]): de [residueProminenceLowDb] con la claridad de
  /// [residueClarityLow] o menos (mucho ruido) a [residueProminenceHighDb]
  /// con [residueClarityHigh] o más.
  static const double residueProminenceLowDb = 10;
  static const double residueProminenceHighDb = 14;
  static const double residueClarityLow = 0.85;
  static const double residueClarityHigh = 0.98;

  /// Umbral de [isResidue] para una lectura de claridad [clarity]. Con ruido,
  /// los armónicos de una nota real asoman menos sobre el piso y el umbral
  /// baja; sin ruido, un pico suelto de la mezcla (vibrato, batido) puede
  /// asomar más y el umbral sube.
  static double residueThresholdDb(double clarity) {
    final double t = ((clarity - residueClarityLow) / (residueClarityHigh - residueClarityLow)).clamp(0.0, 1.0).toDouble();
    return residueProminenceLowDb + (residueProminenceHighDb - residueProminenceLowDb) * t;
  }

  /// Prominencia mínima (dB) de un tono de la app en el búfer para contar
  /// que el micrófono lo oye.
  static const double ownTonePresentDb = 15;

  /// Distancia (cents) hasta un parcial de un tono de la app por debajo de la
  /// cual un armónico de la lectura se atribuye a la app y no cuenta como
  /// sonido propio.
  static const double ownPartialCents = 90;

  /// Armónicos de la lectura que se miran, y hasta qué frecuencia.
  static const int residueHarmonics = 12;
  static const double residueMaxHz = 5000;

  /// Bajo esta frecuencia, con 8192 muestras cada hueco entre armónicos
  /// tiene 5 bins o menos y no hay resolución para decidir con seguridad.
  /// Ahí una lectura que no queda bajo la cuerda (o nota) más grave del
  /// instrumento se muestra siempre (La1, Mi1 y Si0 del bajo, aunque el
  /// micrófono les quite la fundamental). Una más grave que esa nota (una
  /// cuerda bajada, como el Re1 de Drop D, o la mezcla de la voz a 55 Hz) se
  /// decide por los armónicos como más arriba, con el piso medido a más de
  /// [lowGuardBins] bins de cada múltiplo; si no queda ningún armónico que
  /// se pueda medir, se muestra.
  static const double residueMinHz = 58;

  /// Por debajo de esto ni siquiera con [lowGuardBins] quedan bins entre
  /// armónicos: la lectura se muestra siempre (el La0 de un bajo de 5
  /// cuerdas bajado).
  static const double residueMinResolvedHz = 30;

  /// Margen (semitonos) bajo la nota más grave del instrumento para contar
  /// una lectura como "más grave que el instrumento" bajo [residueMinHz]:
  /// una cuerda al aire unos cents baja sigue siendo esa cuerda.
  static const double belowLowestSemitones = 0.5;

  /// Separación mínima (bins) del piso a cada múltiplo de la lectura bajo
  /// [residueMinHz] (más arriba, 2,5). El lóbulo de Hann mide ±2 bins.
  static const double lowGuardBins = 2;

  /// Armónicos que deciden solos: si los que cuentan hasta este h ya tienen
  /// máximo común divisor 1, es una nota. Los de más arriba solo cuentan si
  /// el resultado no depende de uno solo de ellos (N4: un pico suelto en un
  /// armónico alto, sin fuente clara, no basta para mostrar una mezcla).
  static const int robustHarmonic = 7;

  /// Claridad mínima para avisar que una nota queda bajo el rango.
  static const double noticeClarity = 0.85;

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
  TunerNotice _notice = TunerNotice.none;
  DateTime? _noticeAt;
  DateTime? _residueSince;
  DateTime? _belowSince;
  DateTime? _cleanSince;

  MicStatus get status => _status;

  bool get listening => _status == MicStatus.listening;

  bool get permissionDenied => _status == MicStatus.denied;

  /// Lo que la persona eligió con el botón del micrófono.
  bool get userEnabled => _userEnabled;

  bool get active => _active;

  /// true si el último análisis contó como tono estable de instrumento.
  bool get stableTone => _stableNow;

  TunerReading? get reading => _reading;

  /// Por qué no hay lectura aunque suena un tono claro (se mantiene un
  /// momento para que el aviso no parpadee).
  TunerNotice get notice => _notice;

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
    // Las cancelaciones no se esperan: su futuro vive en la zona raíz y, con
    // el tiempo simulado de las pruebas, no terminaría nunca (el micrófono
    // se cierra igual con stop).
    final StreamSubscription<bool>? paused = _pausedSub;
    _pausedSub = null;
    unawaited(paused?.cancel());
    final StreamSubscription<Uint8List>? sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
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
    _notice = TunerNotice.none;
    _noticeAt = null;
    _residueSince = null;
    _belowSince = null;
    _cleanSince = null;
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
      if (_reading != null || _stableNow || _notice != TunerNotice.none) {
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
    // Muy por debajo del rango del perfil elegido no es la nota (ruido grave o
    // un subarmónico) y no se muestra; con un tono claro, se avisa (puede ser
    // otro instrumento: Cromático lo lee). En Cromático no limita.
    // Con un tono de la app sonando que el micrófono de verdad oye, una
    // lectura en f/k de ese tono puede ser la mezcla con él (un residuo): solo
    // se oculta si lo que ese tono no explica no tiene el periodo de la
    // lectura (ver isResidue).
    final bool voiced = r.hasPitch && r.clarity >= 0.6;
    bool hide = false;
    bool belowRange = false;
    bool residue = false;
    if (voiced) {
      final List<double>? own = ownTones?.call();
      final double heardMidi = Notes.hzToMidi(r.frequency, a4: settings.a4);
      final double lowest = instrument.lowestReading(capo: settings.capo);
      // Un residuo bajo el rango también es un residuo: el aviso es el del
      // bordón (usar Cromático no ayudaría) y no alterna con el de rango.
      residue = own != null &&
          own.isNotEmpty &&
          matchesOwnTone(r.frequency, own) &&
          isResidue(Spectrum(buf, sampleRate: sampleRate), r.frequency, own, clarity: r.clarity, belowLowest: heardMidi < lowest + Instrument.rangeMargin - belowLowestSemitones);
      if (residue) {
        hide = true;
      } else if (heardMidi < lowest) {
        hide = true;
        // El propio bordón grave (con Voz o Violín) no es "una nota más grave
        // que el rango": no se avisa (O2).
        belowRange = r.clarity >= noticeClarity && !_isOwnSound(r.frequency, octaves: 0);
      }
    }
    // Histéresis: cada aviso pide 300 ms seguidos de su causa para aparecer,
    // y el del bordón, 300 ms seguidos de notas para irse. Cualquier cuadro
    // de otra clase (también silencio) reinicia la cuenta.
    final bool clean = voiced && !hide;
    _residueSince = residue ? (_residueSince ?? wall) : null;
    _belowSince = belowRange ? (_belowSince ?? wall) : null;
    _cleanSince = clean ? (_cleanSince ?? wall) : null;
    if (_notice == TunerNotice.ownTone && clean && wall.difference(_cleanSince!) < noticeDelay) {
      hide = true;
    }
    TunerNotice why = TunerNotice.none;
    if (belowRange && (_notice == TunerNotice.belowRange || wall.difference(_belowSince!) >= noticeDelay)) {
      why = TunerNotice.belowRange;
    } else if (residue && (_notice == TunerNotice.ownTone || wall.difference(_residueSince!) >= noticeDelay)) {
      why = TunerNotice.ownTone;
    }
    if (why != TunerNotice.none) {
      final bool changed = _notice != why || _reading != null;
      _notice = why;
      _noticeAt = wall;
      if (_reading != null) {
        _reading = null;
        _smoothMidi = -1;
      }
      if (changed) {
        notifyListeners();
      }
    } else if (_notice != TunerNotice.none) {
      final DateTime? at = _noticeAt;
      final Duration keep = _notice == TunerNotice.belowRange ? rangeNoticeHold : noticeHold;
      final bool expired = at != null && wall.difference(at) > keep;
      // Un tono de la propia app (el bordón que suena) no cuenta como lectura
      // que borre el aviso.
      if (expired || (voiced && !hide && !_isOwnSound(r.frequency))) {
        _notice = TunerNotice.none;
        _noticeAt = null;
        notifyListeners();
      }
    }
    if (!voiced || hide) {
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

  /// true si [hz] cae (±60 cents) en f/k (k de 2 a 8) de alguno de [own].
  static bool matchesOwnTone(double hz, List<double> own) => _matching(hz, own).isNotEmpty;

  static List<double> _matching(double hz, List<double> own) => <double>[
        for (final double f in own)
          if (f > 0 && <int>[2, 3, 4, 5, 6, 7, 8].any((int k) => (1200 * log2(hz * k / f)).abs() <= 60)) f,
      ];

  /// Si una lectura [hz] que cae en f/k de un tono de la app es un residuo
  /// de la mezcla, no una nota. Lo es solo si:
  /// - alguno de esos tonos asoma en el búfer (prominencia de al menos
  ///   [ownTonePresentDb]). Con el volumen muy bajo no hay mezcla y no se
  ///   oculta nada; con audífonos puede asomar igual, porque lo que suena en
  ///   la frecuencia del tono puede ser un armónico de la propia nota, y
  ///   entonces decide el criterio de los armónicos;
  /// - [hz] es de al menos [residueMinHz], o queda bajo la nota más grave
  ///   del instrumento ([belowLowest]);
  /// - y lo que no explican los tonos de la app no tiene el periodo de [hz].
  ///   Se miran los armónicos h·[hz] (h de 1 a [residueHarmonics], hasta
  ///   [residueMaxHz]) que no caen a menos de [ownPartialCents] de un
  ///   parcial de un tono de la app, y cuentan los que superan
  ///   [residueThresholdDb] sobre el piso entre armónicos (el piso se mide
  ///   en cada zona del espectro y el umbral baja con el ruido, [clarity]).
  ///   Si el máximo común divisor de los que cuentan es 1, ese sonido tiene
  ///   de verdad el periodo de [hz]: es una nota (ver [robustHarmonic] para
  ///   los armónicos altos). Si no cuenta ninguno, o todos son múltiplos de
  ///   un j > 1, lo tocado es j·[hz] y [hz] sale de la mezcla. Si no se pudo
  ///   medir ninguno, no se decide: se muestra.
  static bool isResidue(Spectrum spectrum, double hz, List<double> own, {double clarity = 1, bool belowLowest = false}) {
    final bool low = hz < residueMinHz;
    if (low && (!belowLowest || hz < residueMinResolvedHz)) {
      return false;
    }
    if (!_matching(hz, own).any((double g) => spectrum.prominenceDb(g) >= ownTonePresentDb)) {
      return false;
    }
    final double guard = low ? lowGuardBins : 2.5;
    final double threshold = residueThresholdDb(clarity);
    final List<int> counted = <int>[];
    int measured = 0;
    for (int h = 1; h <= residueHarmonics && h * hz <= residueMaxHz; h++) {
      if (_nearOwnPartial(h * hz, own)) {
        continue;
      }
      final double p = h == 1 ? _fundamentalDb(spectrum, hz, guard) : spectrum.harmonicProminenceDb(hz, h, guard: guard);
      if (p.isNaN) {
        continue;
      }
      measured++;
      if (p >= threshold) {
        counted.add(h);
      }
    }
    if (measured == 0) {
      return false;
    }
    if (_gcdOf(counted) != 1) {
      return true;
    }
    if (_gcdOf(<int>[for (final int h in counted) if (h <= robustHarmonic) h]) == 1) {
      return false;
    }
    // El 1 sale gracias a armónicos altos: tiene que seguir saliendo sin
    // cualquiera de ellos.
    for (final int c in counted) {
      if (c > robustHarmonic && _gcdOf(<int>[for (final int h in counted) if (h != c) h]) != 1) {
        return true;
      }
    }
    return false;
  }

  static int _gcdOf(List<int> values) {
    int g = 0;
    for (final int v in values) {
      g = _gcd(g, v);
    }
    return g;
  }

  /// La fundamental se mide contra el piso agrupado y contra su entorno
  /// cercano (0,55·f a 1,45·f, con el piso del lado más alto), y vale la
  /// mayor: con el paso alto de un teléfono y ruido, el piso sube mucho
  /// hacia 2·f y el agrupado la subestima. El entorno cercano toma el lado
  /// más alto para que el ruido en f no asome solo sobre el lado grave, más
  /// atenuado por el paso alto (N4).
  static double _fundamentalDb(Spectrum spectrum, double hz, double guard) {
    final double pooled = spectrum.harmonicProminenceDb(hz, 1, guard: guard);
    final double near = spectrum.prominenceBothSidesDb(hz);
    if (pooled.isNaN) {
      return near;
    }
    if (near.isNaN) {
      return pooled;
    }
    return math.max(pooled, near);
  }

  static bool _nearOwnPartial(double hz, List<double> own) {
    for (final double g in own) {
      if (g <= 0) {
        continue;
      }
      final int m = math.max(1, (hz / g).round());
      if ((1200 * log2(hz / (m * g))).abs() <= ownPartialCents) {
        return true;
      }
    }
    return false;
  }

  static int _gcd(int a, int b) {
    int x = a;
    int y = b;
    while (y != 0) {
      final int t = x % y;
      x = y;
      y = t;
    }
    return x;
  }

  /// true si [hz] cae (±60 cents) en un sonido de la propia app o, con
  /// [octaves] > 0, en una de sus octavas (el detector puede quedarse con
  /// una de ellas).
  bool _isOwnSound(double hz, {int octaves = 2}) {
    final List<double>? own = ownFrequencies?.call();
    if (own == null || own.isEmpty) {
      return false;
    }
    for (final double f in own) {
      if (f <= 0) {
        continue;
      }
      final double c = 1200 * log2(hz / f);
      final double nearest = (c / 1200).roundToDouble();
      if (nearest.abs() <= octaves && (c - nearest * 1200).abs() <= 60) {
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
