import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Vibración del pulso del metrónomo.
abstract class Haptics {
  /// Un pulso: más largo y fuerte en el acento.
  void pulse({required bool accent});
}

/// Sin vibración (pruebas y equipos sin motor de vibración).
class NoHaptics implements Haptics {
  const NoHaptics();

  @override
  void pulse({required bool accent}) {}
}

/// Vibración real del teléfono.
///
/// - Android: `Vibrator` con `VibrationEffect.createOneShot` (paquete
///   `vibration`, que declara el permiso VIBRATE), con amplitud si el motor la
///   admite. No depende de la "respuesta táctil" del sistema, que da pulsos
///   casi imperceptibles.
/// - iOS: el generador de impacto del sistema (HapticFeedback). Funciona
///   también con el afinador escuchando, porque la sesión de grabación se
///   abre con `allowHapticsAndSystemSoundsDuringRecording`.
class DeviceHaptics implements Haptics {
  DeviceHaptics();

  bool? _hasVibrator;
  bool _amplitude = false;
  Future<void>? _probe;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  Future<void> _check() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
      _amplitude = await Vibration.hasAmplitudeControl();
    } catch (e) {
      debugPrint('Vibración no disponible: $e');
      _hasVibrator = false;
    }
  }

  @override
  void pulse({required bool accent}) {
    if (_android) {
      unawaited(_vibrateAndroid(accent));
    } else {
      unawaited((accent ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact()).catchError((Object e) {
        debugPrint('Vibración: $e');
      }));
    }
  }

  Future<void> _vibrateAndroid(bool accent) async {
    if (_hasVibrator == null) {
      await (_probe ??= _check());
    }
    if (_hasVibrator != true) {
      return;
    }
    try {
      await Vibration.vibrate(duration: accent ? 45 : 25, amplitude: _amplitude ? (accent ? 255 : 140) : -1);
    } catch (e) {
      debugPrint('Vibración: $e');
    }
  }
}
