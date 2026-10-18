/// Qué errores de la cámara en marcha la dejan inservible.
///
/// El complemento entrega por el mismo canal (`onCameraError`) dos cosas muy
/// distintas:
///
/// - Errores de estado de la cámara: en Android, los de `CameraState` de
///   CameraX (cámara en uso por otra app, deshabilitada, error fatal,
///   configuración fallida, No molestar); en iPhone, el error de la sesión
///   de captura (`AVCaptureSessionRuntimeError`, con el dominio
///   AVFoundationErrorDomain). Con ellos la vista se congela: hay que cerrar
///   la cámara y ofrecer reintentar.
/// - Avisos de operaciones que no se hicieron: un cambio de exposición o un
///   enfoque cancelado porque llegó otro más nuevo, la linterna en una cámara
///   sin flash, un zoom fuera de rango. La cámara sigue funcionando y se
///   ignoran.
///
/// Los textos son los de camera_android_camerax 0.6.30
/// (`_createCameraClosingObserver`) y camera_avfoundation 0.9.23
/// (`captureSessionRuntimeError`).
bool isFatalCameraError(String description) {
  for (final String known in kFatalCameraErrors) {
    if (description == known) {
      return true;
    }
  }
  return description.contains('AVFoundationErrorDomain');
}

/// Errores de estado de CameraX que cierran la cámara. Quedan fuera
/// «otherRecoverableError» (CameraX se recupera solo) y el desconocido.
const List<String> kFatalCameraErrors = <String>[
  'The camera was already in use, possibly by a higher-priority camera client.',
  'The limit number of open cameras has been reached, and more cameras cannot be opened until other instances are closed.',
  'Configuring the camera has failed.',
  'The camera device could not be opened due to a device policy. Thia may be caused by a client from a background process attempting to open the camera.',
  'The camera was closed due to a fatal error. This may require the Android device be shut down and restarted to restore camera function or may indicate a persistent camera hardware problem.',
  'The camera could not be opened because "Do Not Disturb" mode is enabled. Please disable this mode, and try opening the camera again.',
];

/// Avisos de CameraX que no son fallos (para las pruebas y la referencia).
const List<String> kHarmlessCameraXNotices = <String>[
  'Setting exposure compensation index was canceled due to the camera being closed or a new request being submitted.',
  'Starting focus and metering was canceled due to the camera being closed or a new request being submitted.',
  'The camera was unable to change torch modes.',
  'Zoom ratio was unable to be set. If ratio was not out of range, newer value may have been set; otherwise, the camera may be closed.',
  'The camera device has encountered a recoverable error. CameraX will attempt to recover from the error.',
];

/// Qué le pasó a la cámara, en palabras de la app.
enum CameraFailure {
  /// Otra app la tomó o hay demasiadas cámaras abiertas.
  inUse,

  /// Deshabilitada por una política del equipo.
  disabled,

  /// «No molestar» impide abrirla.
  doNotDisturb,

  /// Error del sistema de cámara (configuración, error fatal, sesión de iOS).
  system,
}

/// Clasifica un error fatal ([isFatalCameraError]).
CameraFailure cameraFailureOf(String description) {
  final int i = kFatalCameraErrors.indexOf(description);
  switch (i) {
    case 0:
    case 1:
      return CameraFailure.inUse;
    case 3:
      return CameraFailure.disabled;
    case 5:
      return CameraFailure.doNotDisturb;
  }
  return CameraFailure.system;
}

/// Mensaje propio para un error de la cámara en marcha. El texto del
/// complemento (en inglés, o un `Error Domain=…` de iOS) nunca se muestra:
/// queda en el registro de depuración.
String cameraFailureMessage(CameraFailure f, {required bool spanish}) {
  String k(String es, String en) => spanish ? es : en;
  switch (f) {
    case CameraFailure.inUse:
      return k('Otra app está usando la cámara. Ciérrala y toca Reintentar.', 'Another app is using the camera. Close it and tap Retry.');
    case CameraFailure.disabled:
      return k('La cámara está deshabilitada por una política del equipo.', 'The camera is disabled by a device policy.');
    case CameraFailure.doNotDisturb:
      return k('Con «No molestar» activado no se puede abrir la cámara. Desactívalo y toca Reintentar.', 'The camera cannot open while Do Not Disturb is on. Turn it off and tap Retry.');
    case CameraFailure.system:
      return k('El sistema de la cámara tuvo un error. Toca Reintentar; si sigue, reinicia el teléfono.', 'The camera system had an error. Tap Retry; if it persists, restart the phone.');
  }
}

/// Una interrupción de la sesión de cámara de iOS (iPad con otra app en
/// pantalla, otra app con la cámara, el equipo muy caliente…), del canal
/// co.appsgratis.sello/camera_interruption (native/ios/AppDelegate.swift).
class CameraInterruption {
  const CameraInterruption({required this.interrupted, this.reason = 0});

  final bool interrupted;

  /// `AVCaptureSession.InterruptionReason`: 1 en segundo plano, 3 otra app
  /// usa la cámara, 4 varias apps en pantalla, 5 presión del sistema.
  final int reason;

  static const int inBackground = 1;
  static const int inUseByAnotherClient = 3;
  static const int multipleForegroundApps = 4;
  static const int systemPressure = 5;
}

/// Mensaje propio para una interrupción.
String cameraInterruptionMessage(int reason, {required bool spanish}) {
  String k(String es, String en) => spanish ? es : en;
  switch (reason) {
    case CameraInterruption.multipleForegroundApps:
      return k('La cámara no está disponible con otra app en pantalla. Pon Sello en pantalla completa; si no vuelve sola, toca Reintentar.', 'The camera is not available with another app on screen. Make Sello full screen; if it does not come back, tap Retry.');
    case CameraInterruption.inUseByAnotherClient:
      return k('Otra app está usando la cámara. Ciérrala; si no vuelve sola, toca Reintentar.', 'Another app is using the camera. Close it; if it does not come back, tap Retry.');
    case CameraInterruption.systemPressure:
      return k('La cámara se pausó porque el equipo está muy caliente. Espera un momento y toca Reintentar.', 'The camera paused because the device is too hot. Wait a moment and tap Retry.');
  }
  return k('La cámara está en pausa. Toca Reintentar.', 'The camera is paused. Tap Retry.');
}
