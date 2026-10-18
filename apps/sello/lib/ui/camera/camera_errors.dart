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
