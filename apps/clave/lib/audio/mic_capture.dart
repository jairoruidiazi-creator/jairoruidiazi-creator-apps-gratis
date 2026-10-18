import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'audio_session.dart';

/// Captura del micrófono en PCM de 16 bits mono para el afinador. Separada
/// del afinador para poder probar su ciclo de vida sin micrófono.
abstract class MicCapture {
  /// Si hay permiso. Con [request] en falso solo consulta, sin mostrar el
  /// diálogo del sistema.
  Future<bool> hasPermission({bool request = true});

  /// Abre el micrófono y entrega bloques PCM s16le.
  Future<Stream<Uint8List>> start(int sampleRate);

  Future<void> stop();

  /// true mientras el sistema tiene la captura en pausa (llamada, Siri).
  Stream<bool> get paused;

  Future<void> dispose();
}

/// Opciones de la sesión de audio de iOS mientras el micrófono está abierto
/// (afinador o grabadora). Sin `allowBluetooth`: con audífonos Bluetooth el
/// sonido sigue saliendo por A2DP en calidad completa y se escucha el
/// micrófono del teléfono, no el de los audífonos. `mixWithOthers` deja
/// sonando la música de otra app. Con la vibración permitida durante la
/// captura, el pulso del metrónomo se siente aunque el afinador escuche.
const IosRecordConfig kMicIosConfig = IosRecordConfig(
  categoryOptions: <IosAudioCategoryOption>[
    IosAudioCategoryOption.defaultToSpeaker,
    IosAudioCategoryOption.allowBluetoothA2DP,
    IosAudioCategoryOption.mixWithOthers,
  ],
  allowHapticsAndSystemSoundsDuringRecording: true,
);

/// En Android no se pide el foco de audio (no se detiene la música de otra
/// app) ni se abre el enlace SCO de los audífonos Bluetooth, que bajaría el
/// sonido a calidad de llamada. El afinador usa la fuente de reconocimiento
/// de voz, que en Android no lleva control de ganancia ni reducción de ruido.
const AndroidRecordConfig kTunerAndroidConfig = AndroidRecordConfig(manageBluetooth: false, audioSource: AndroidAudioSource.voiceRecognition);

const AndroidRecordConfig kTakeAndroidConfig = AndroidRecordConfig(manageBluetooth: false);

/// En iOS la captura se pausa y se reanuda sola con las interrupciones del
/// sistema; en Android no se pide foco de audio (modo none).
AudioInterruptionMode tunerInterruptionMode() => defaultTargetPlatform == TargetPlatform.iOS ? AudioInterruptionMode.pauseResume : AudioInterruptionMode.none;

/// Captura con el paquete `record`.
class RecordMicCapture implements MicCapture {
  RecordMicCapture({this.guard});

  /// Coordina el micrófono con la grabadora y repone la sesión de audio al
  /// soltarlo.
  final MicSessionGuard? guard;

  AudioRecorder? _recorder;
  StreamSubscription<RecordState>? _stateSub;
  final StreamController<bool> _paused = StreamController<bool>.broadcast();
  bool _running = false;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  @override
  Stream<bool> get paused => _paused.stream;

  @override
  Future<bool> hasPermission({bool request = true}) => _rec.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> start(int sampleRate) async {
    _stateSub ??= _rec.onStateChanged().listen((RecordState s) {
      if (_running) {
        _paused.add(s == RecordState.pause);
      }
    });
    guard?.acquire();
    final Stream<Uint8List> stream;
    try {
      stream = await _rec.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: kTunerAndroidConfig,
        iosConfig: kMicIosConfig,
        audioInterruption: tunerInterruptionMode(),
      ));
    } catch (e) {
      await guard?.release();
      rethrow;
    }
    _running = true;
    return stream;
  }

  @override
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    try {
      await _rec.stop();
    } catch (e) {
      debugPrint('No se pudo cerrar el micrófono: $e');
    }
    await guard?.release();
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _stateSub?.cancel();
    _stateSub = null;
    await _paused.close();
    final AudioRecorder? r = _recorder;
    _recorder = null;
    if (r != null) {
      await r.dispose();
    }
  }
}
