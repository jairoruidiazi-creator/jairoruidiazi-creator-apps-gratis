import 'package:wakelock_plus/wakelock_plus.dart';

/// Pantalla encendida: solo mientras la cámara está a la vista (ver
/// CameraScreen). Las pruebas usan una versión que solo anota.
class KeepAwake {
  const KeepAwake();

  Future<void> set(bool on) => WakelockPlus.toggle(enable: on);
}
