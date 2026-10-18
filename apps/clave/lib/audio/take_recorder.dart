import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../core/storage.dart';
import 'audio_session.dart';
import 'mic_capture.dart';

/// Una toma terminada, con los datos que se fijaron al empezarla.
class TakeResult {
  const TakeResult({
    required this.file,
    required this.format,
    required this.durationMs,
    required this.startedAt,
    this.folder = '',
    this.instrumentId = '',
    this.bpm,
  });

  /// Ruta relativa dentro del almacén.
  final String file;
  final String format;

  /// Tiempo grabado, sin las pausas.
  final int durationMs;
  final DateTime startedAt;
  final String folder;
  final String instrumentId;

  /// Tempo del metrónomo si sonaba al empezar la toma.
  final double? bpm;
}

/// Por qué terminó una toma sin que la persona la detuviera.
enum TakeStopReason { user, interruption, background }

/// Captura de audio a archivo para la grabadora.
abstract class AudioFileCapture {
  /// Con [request] en false solo se consulta, sin mostrar el diálogo.
  Future<bool> hasPermission({bool request = true});

  Future<void> start(String path, {required String format});

  /// Devuelve la ruta del archivo o null.
  Future<String?> stop();

  /// Estado de la captura (grabando, en pausa, detenida).
  Stream<RecordState> get state;

  /// Nivel en dBFS (−160 a 0) cada [interval].
  Stream<double> level(Duration interval);

  Future<void> dispose();
}

/// Captura con el paquete `record`.
class RecordFileCapture implements AudioFileCapture {
  RecordFileCapture({this.guard});

  /// Coordina el micrófono con el afinador y repone la sesión de audio al
  /// soltarlo.
  final MicSessionGuard? guard;
  bool _holding = false;

  AudioRecorder? _recorder;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission({bool request = true}) => _rec.hasPermission(request: request);

  @override
  Future<void> start(String path, {required String format}) async {
    final AudioEncoder enc = format == 'wav' ? AudioEncoder.wav : (format == 'flac' ? AudioEncoder.flac : AudioEncoder.aacLc);
    if (!_holding) {
      _holding = true;
      guard?.acquire();
    }
    try {
      await _rec.start(
        RecordConfig(
          encoder: enc,
          sampleRate: 44100,
          numChannels: 1,
          bitRate: 160000,
          androidConfig: kTakeAndroidConfig,
          iosConfig: kMicIosConfig,
          // iOS pausa la toma con una llamada o Siri (la app la cierra y la
          // guarda); en Android no se pide foco de audio.
          audioInterruption: defaultTargetPlatform == TargetPlatform.iOS ? AudioInterruptionMode.pause : AudioInterruptionMode.none,
        ),
        path: path,
      );
    } catch (e) {
      _holding = false;
      await guard?.release();
      rethrow;
    }
  }

  @override
  Future<String?> stop() async {
    try {
      return await _rec.stop();
    } finally {
      if (_holding) {
        _holding = false;
        await guard?.release();
      }
    }
  }

  @override
  Stream<RecordState> get state => _rec.onStateChanged();

  @override
  Stream<double> level(Duration interval) => _rec.onAmplitudeChanged(interval).map((Amplitude a) => a.current);

  @override
  Future<void> dispose() async {
    final AudioRecorder? r = _recorder;
    _recorder = null;
    if (r != null) {
      await r.dispose();
    }
  }
}

/// La grabadora de tomas: graba a un archivo en recordings/, mide la
/// duración real (sin las pausas por interrupciones) y deja un marcador
/// mientras graba para rescatar la toma si la app se cierra de golpe.
class TakeRecorder extends ChangeNotifier {
  TakeRecorder({required this.store, AudioFileCapture? capture}) : _capture = capture;

  final JsonStore store;
  AudioFileCapture? _capture;

  AudioFileCapture get _cap => _capture ??= RecordFileCapture();

  /// Marcador de la toma en curso.
  static const String pendingFile = 'recordings/pending.json';

  bool _recording = false;
  bool _paused = false;
  String? _file;
  String _format = 'aac';
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _folder = '';
  String _instrumentId = '';
  double? _bpm;
  DateTime? _segmentStart;
  Duration _accumulated = Duration.zero;
  double _level = 0;
  StreamSubscription<RecordState>? _stateSub;
  StreamSubscription<double>? _levelSub;

  /// Se llama cuando una toma termina sola (interrupción o segundo plano).
  void Function(TakeResult? result, TakeStopReason reason)? onAutoStop;

  bool get recording => _recording;

  /// El sistema pausó la toma (llamada, Siri).
  bool get paused => _paused;

  /// Nivel de entrada de 0 a 1.
  double get level => _level;

  String get format => _format;

  /// Tiempo grabado, sin las pausas.
  Duration get elapsed {
    final DateTime? s = _segmentStart;
    return s == null ? _accumulated : _accumulated + clock.now().difference(s);
  }

  Future<bool> hasPermission({bool request = true}) async {
    try {
      return await _cap.hasPermission(request: request);
    } catch (e) {
      debugPrint('Permiso de micrófono: $e');
      return false;
    }
  }

  /// Empieza una toma. Lanza una excepción si el sistema no deja grabar.
  ///
  /// [folder], [instrumentId] y [bpm] viajan con la toma hasta la lista, la
  /// detenga la persona o el sistema.
  Future<void> start({required String format, String folder = '', String instrumentId = '', double? bpm}) async {
    if (_recording) {
      return;
    }
    _format = format == 'wav' || format == 'flac' ? format : 'aac';
    final String ext = _format == 'aac' ? 'm4a' : _format;
    final DateTime now = clock.now();
    final String rel = 'recordings/${now.millisecondsSinceEpoch}.$ext';
    final String path = await store.absolutePath(rel);
    await File(path).parent.create(recursive: true);
    await store.writeJson(pendingFile, <String, dynamic>{
      'file': rel,
      'format': _format,
      'startedAt': now.toIso8601String(),
      'folder': folder,
      'instrumentId': instrumentId,
    });
    _stateSub ??= _cap.state.listen(_onState);
    try {
      await _cap.start(path, format: _format);
    } catch (e) {
      await store.delete(pendingFile);
      rethrow;
    }
    _file = rel;
    _startedAt = now;
    _folder = folder;
    _instrumentId = instrumentId;
    _bpm = bpm;
    _recording = true;
    _paused = false;
    _accumulated = Duration.zero;
    _segmentStart = clock.now();
    _levelSub = _cap.level(const Duration(milliseconds: 120)).listen((double db) {
      // dBFS de -60 a 0 → 0 a 1
      _level = ((db + 60) / 60).clamp(0.0, 1.0).toDouble();
      notifyListeners();
    });
    notifyListeners();
  }

  void _onState(RecordState s) {
    if (!_recording) {
      return;
    }
    if (s == RecordState.pause && !_paused) {
      _paused = true;
      final DateTime? start = _segmentStart;
      if (start != null) {
        _accumulated += clock.now().difference(start);
      }
      _segmentStart = null;
      notifyListeners();
      // Una llamada o Siri pausaron la toma: se cierra y se guarda lo grabado.
      unawaited(_autoStop(TakeStopReason.interruption));
    } else if (s == RecordState.record && _paused) {
      _paused = false;
      _segmentStart = clock.now();
      notifyListeners();
    }
  }

  Future<void> _autoStop(TakeStopReason reason) async {
    final TakeResult? r = await stop();
    onAutoStop?.call(r, reason);
  }

  /// Detiene la toma por salir la app al fondo en Android (no deja grabar).
  Future<void> stopForBackground() async {
    if (_recording) {
      await _autoStop(TakeStopReason.background);
    }
  }

  /// Termina la toma y devuelve su archivo y duración (o null si no hubo).
  Future<TakeResult?> stop() async {
    if (!_recording) {
      return null;
    }
    final Duration total = elapsed;
    _recording = false;
    _paused = false;
    _segmentStart = null;
    _level = 0;
    final StreamSubscription<double>? levels = _levelSub;
    _levelSub = null;
    unawaited(levels?.cancel());
    String? path;
    try {
      path = await _cap.stop();
    } catch (e) {
      debugPrint('No se pudo cerrar la grabación: $e');
    }
    final String? rel = _file;
    _file = null;
    await store.delete(pendingFile);
    notifyListeners();
    if (rel == null) {
      return null;
    }
    if (path == null && !await store.exists(rel)) {
      return null;
    }
    return TakeResult(
      file: rel,
      format: _format,
      durationMs: total.inMilliseconds,
      startedAt: _startedAt,
      folder: _folder,
      instrumentId: _instrumentId,
      bpm: _bpm,
    );
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_levelSub?.cancel());
    final AudioFileCapture? c = _capture;
    if (c != null) {
      unawaited(c.dispose());
    }
    super.dispose();
  }
}
