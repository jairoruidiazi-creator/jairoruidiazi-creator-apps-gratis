import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Lectura de orientación del teléfono.
class Orientation3 {
  const Orientation3({required this.cameraHeading, required this.deviceHeading, required this.pitch, required this.roll, required this.flat});

  /// Rumbo (grados desde el norte, en sentido horario) hacia donde apunta la
  /// cámara trasera. Si el teléfono está plano se usa el rumbo del borde
  /// superior.
  final double cameraHeading;

  /// Rumbo del borde superior del teléfono (brújula clásica).
  final double deviceHeading;

  /// Inclinación de la cámara respecto al horizonte (0 = horizontal, 90 = hacia abajo).
  final double pitch;

  /// Giro lateral (0 = nivelado).
  final double roll;

  /// Verdadero cuando el teléfono está casi horizontal.
  final bool flat;
}

/// Fusión de acelerómetro y magnetómetro con la misma matriz de rotación que
/// usa Android (`getRotationMatrix`): da el rumbo del eje de la cámara,
/// la inclinación y el giro. Declinación magnética manual para norte verdadero.
class HeadingService extends ChangeNotifier {
  HeadingService({this.alpha = 0.2});

  /// Factor del filtro pasabajos (0 = muy suave, 1 = sin filtro).
  final double alpha;

  /// Declinación magnética en grados (este positivo). Se suma al rumbo.
  double declination = 0;

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  List<double>? _acc;
  List<double>? _mag;
  Orientation3? _last;
  bool _running = false;
  bool available = true;

  Orientation3? get orientation => _last;

  bool get running => _running;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    try {
      _accSub = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 50)).listen((AccelerometerEvent e) {
        _acc = _smooth(_acc, <double>[e.x, e.y, e.z]);
        _update();
      }, onError: (Object e) {
        available = false;
        notifyListeners();
      });
      _magSub = magnetometerEventStream(samplingPeriod: const Duration(milliseconds: 50)).listen((MagnetometerEvent e) {
        _mag = _smooth(_mag, <double>[e.x, e.y, e.z]);
        _update();
      }, onError: (Object e) {
        available = false;
        notifyListeners();
      });
    } catch (e) {
      available = false;
      _running = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _running = false;
    await _accSub?.cancel();
    await _magSub?.cancel();
    _accSub = null;
    _magSub = null;
  }

  List<double> _smooth(List<double>? prev, List<double> v) {
    if (prev == null) {
      return v;
    }
    return <double>[for (int i = 0; i < 3; i++) prev[i] + alpha * (v[i] - prev[i])];
  }

  void _update() {
    final List<double>? a = _acc;
    final List<double>? m = _mag;
    if (a == null || m == null) {
      return;
    }
    final Orientation3? o = compute(a, m, declination: declination);
    if (o != null) {
      _last = o;
      notifyListeners();
    }
  }

  /// Cálculo puro (probado en `geo_test.dart`). [gravity] y [magnetic] en el
  /// sistema de ejes del dispositivo: x a la derecha, y hacia arriba de la
  /// pantalla, z saliendo de la pantalla.
  static Orientation3? compute(List<double> gravity, List<double> magnetic, {double declination = 0}) {
    final double ax = gravity[0];
    final double ay = gravity[1];
    final double az = gravity[2];
    final double ex = magnetic[0];
    final double ey = magnetic[1];
    final double ez = magnetic[2];
    final double normA = math.sqrt(ax * ax + ay * ay + az * az);
    if (normA < 1e-6) {
      return null;
    }
    // H = E × A (este), normalizado.
    double hx = ey * az - ez * ay;
    double hy = ez * ax - ex * az;
    double hz = ex * ay - ey * ax;
    final double normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 1e-6) {
      return null;
    }
    hx /= normH;
    hy /= normH;
    hz /= normH;
    final double gx = ax / normA;
    final double gy = ay / normA;
    final double gz = az / normA;
    // M = A × H (norte).
    final double mx = gy * hz - gz * hy;
    final double my = gz * hx - gx * hz;
    final double mz = gx * hy - gy * hx;
    // Rumbo del borde superior (eje y del dispositivo) y del eje de la cámara (-z).
    final double deviceHeading = _deg(math.atan2(hy, my));
    final double cameraHeading = _deg(math.atan2(-hz, -mz));
    // Inclinación de la cámara: componente vertical del eje -z en el mundo.
    final double pitch = math.asin((-gz).clamp(-1.0, 1.0)) * 180 / math.pi; // 0 horizontal, +90 cámara hacia abajo
    final double roll = math.atan2(gx, gy) * 180 / math.pi;
    final bool flat = gz.abs() > 0.85;
    final double heading = flat ? deviceHeading : cameraHeading;
    return Orientation3(
      cameraHeading: (heading + declination + 360) % 360,
      deviceHeading: (deviceHeading + declination + 360) % 360,
      pitch: -pitch,
      roll: roll,
      flat: flat,
    );
  }

  static double _deg(double rad) {
    final double d = rad * 180 / math.pi;
    return (d + 360) % 360;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
