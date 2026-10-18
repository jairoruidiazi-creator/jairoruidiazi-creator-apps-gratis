import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Sesión de audio de la app (detalle y razones en docs/DECISIONES.md,
/// "Sesión de audio"):
///
/// - iOS: categoría `playback` con `mixWithOthers`. El metrónomo, el bordón,
///   el teclado, el conteo y las tomas suenan con el interruptor de silencio
///   puesto, siguen con la pantalla bloqueada y no detienen la música de otra
///   app (se puede tocar encima de una pista). Mientras el micrófono está
///   abierto, `record` pasa a `playAndRecord` con A2DP, altavoz y
///   `mixWithOthers` (ver mic_capture.dart); al soltarlo se vuelve aquí.
/// - Android: las tomas se reproducen sin pedir el foco de audio, igual que
///   el metrónomo y el bordón (SoLoud no lo pide): nada de Clave pausa la
///   música de otra app.
///
/// audioplayers aplica este contexto a toda la sesión de iOS (categoría y
/// opciones) y a sus reproductores de Android.
AudioContext playbackAudioContext() => AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const <AVAudioSessionOptions>{AVAudioSessionOptions.mixWithOthers},
      ),
      android: const AudioContextAndroid(
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.none,
      ),
    );

Future<void> configureAudioSession() async {
  try {
    await AudioPlayer.global.setAudioContext(playbackAudioContext());
  } catch (e) {
    debugPrint('No se pudo configurar la sesión de audio: $e');
  }
}

/// Al soltar el micrófono en iOS, la sesión vuelve a `playback` (en
/// `playAndRecord` el altavoz suena más bajo en varios iPhone).
Future<void> restorePlaybackSession() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  await configureAudioSession();
}
