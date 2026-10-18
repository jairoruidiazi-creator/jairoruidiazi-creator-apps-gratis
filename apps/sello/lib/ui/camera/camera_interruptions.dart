import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'camera_errors.dart';

/// Interrupciones de la cámara que avisa iOS (en Android no hay canal: allí
/// los errores de estado de CameraX llegan por onCameraError).
Stream<CameraInterruption> systemCameraInterruptions() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return const Stream<CameraInterruption>.empty();
  }
  return const EventChannel('co.appsgratis.sello/camera_interruption').receiveBroadcastStream().where((Object? e) => e is Map).map((Object? e) {
    final Map<Object?, Object?> m = e! as Map<Object?, Object?>;
    final Object? reason = m['reason'];
    return CameraInterruption(interrupted: m['interrupted'] == true, reason: reason is int ? reason : 0);
  }).handleError((Object e) => debugPrint('Interrupciones de la cámara: $e'));
}
