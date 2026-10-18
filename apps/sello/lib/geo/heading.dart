import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'device_orientation.dart';

/// Lectura de orientación del teléfono.
class Orientation3 {
  const Orientation3({required this.cameraHeading, required this.deviceHeading, required this.pitch, required this.roll, required this.flat, this.trueNorth = true, this.accuracy});

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

  /// Verdadero si los rumbos son respecto al norte verdadero; falso si son
  /// magnéticos (todavía no se conoce la declinación).
  final bool trueNorth;

  /// Precisión del rumbo en grados, si el sistema la da (iPhone).
  final double? accuracy;

  /// Lo mismo visto desde la cámara frontal: mira al lado contrario de la
  /// trasera, así que su rumbo es 180° distinto y su inclinación, la opuesta.
  /// Con el teléfono plano el rumbo es el del borde superior y no cambia.
  Orientation3 forFrontCamera() => flat
      ? this
      : Orientation3(
          cameraHeading: (cameraHeading + 180) % 360,
          deviceHeading: deviceHeading,
          pitch: -pitch,
          roll: roll,
          flat: flat,
          trueNorth: trueNorth,
          accuracy: accuracy,
        );
}

/// Rumbo que entrega el sistema en iPhone (canal propio
/// co.appsgratis.sello/heading; ver native/ios/AppDelegate.swift).
///
/// - Los rumbos magnéticos de la cámara y del borde superior salen de la
///   orientación que calcula iOS (CMDeviceMotion con el norte magnético como
///   referencia): fusiona el giroscopio con el magnetómetro ya calibrado.
/// - La precisión y el norte verdadero salen de CLLocationManager:
///   [declination] es `trueHeading − magneticHeading` de su CLHeading y
///   [accuracy], su `headingAccuracy`.
class SystemHeading {
  const SystemHeading({required this.cameraMagnetic, required this.topMagnetic, this.declination, this.accuracy, this.calibration});

  /// Rumbo magnético del eje de la cámara trasera (grados).
  final double cameraMagnetic;

  /// Rumbo magnético del borde superior del teléfono (grados).
  final double topMagnetic;

  /// Declinación que usa el sistema (grados, este positivo), o null si
  /// todavía no tiene posición para calcular el norte verdadero.
  final double? declination;

  /// Desviación máxima del rumbo en grados, o null si el sistema no la sabe.
  final double? accuracy;

  /// Calibración del magnetómetro: -1 sin calibrar, 0 baja, 1 media, 2 alta.
  final int? calibration;

  static SystemHeading? fromMap(Object? event) {
    if (event is! Map) {
      return null;
    }
    final Object? camera = event['camera'];
    final Object? top = event['top'];
    if (camera is! num || top is! num || !camera.isFinite || !top.isFinite) {
      return null;
    }
    final Object? declination = event['declination'];
    final Object? accuracy = event['accuracy'];
    final Object? calibration = event['calibration'];
    return SystemHeading(
      cameraMagnetic: camera.toDouble(),
      topMagnetic: top.toDouble(),
      declination: declination is num && declination.isFinite && declination.abs() <= 180 ? declination.toDouble() : null,
      accuracy: accuracy is num && accuracy >= 0 ? accuracy.toDouble() : null,
      calibration: calibration is num ? calibration.toInt() : null,
    );
  }
}

typedef VectorStreamFactory = Stream<List<double>> Function();
typedef SystemHeadingStreamFactory = Stream<SystemHeading> Function();

/// Orientación y rumbo del teléfono.
///
/// - Android: fusión de acelerómetro y magnetómetro con la misma matriz de
///   rotación que usa Android (`getRotationMatrix`): da el rumbo del eje de
///   la cámara, la inclinación y el giro.
/// - iPhone: el rumbo lo da el sistema (CLLocationManager, con su
///   calibración del magnetómetro y su precisión); el acelerómetro da la
///   inclinación y el giro. El magnetómetro crudo de iOS trae el sesgo del
///   propio teléfono, por eso no se usa.
///
/// También calcula la orientación física (vertical, girado a la izquierda o
/// a la derecha) que sigue la captura de cada foto.
class HeadingService extends ChangeNotifier {
  HeadingService({this.alpha = 0.2, VectorStreamFactory? accelerometer, VectorStreamFactory? magnetometer, SystemHeadingStreamFactory? systemHeading, bool? useSystemHeading})
      : _accelerometer = accelerometer ?? _defaultAccelerometer,
        _magnetometer = magnetometer ?? _defaultMagnetometer,
        _systemHeading = systemHeading ?? _defaultSystemHeading,
        useSystemHeading = useSystemHeading ?? (defaultTargetPlatform == TargetPlatform.iOS);

  /// Factor del filtro pasabajos (0 = muy suave, 1 = sin filtro).
  final double alpha;

  /// El rumbo viene del sistema (iPhone) en vez del magnetómetro.
  final bool useSystemHeading;

  final VectorStreamFactory _accelerometer;
  final VectorStreamFactory _magnetometer;
  final SystemHeadingStreamFactory _systemHeading;

  static const EventChannel _headingChannel = EventChannel('co.appsgratis.sello/heading');

  static Stream<List<double>> _defaultAccelerometer() => accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 50)).map((AccelerometerEvent e) => <double>[e.x, e.y, e.z]);

  static Stream<List<double>> _defaultMagnetometer() => magnetometerEventStream(samplingPeriod: const Duration(milliseconds: 50)).map((MagnetometerEvent e) => <double>[e.x, e.y, e.z]);

  static Stream<SystemHeading> _defaultSystemHeading() => _headingChannel.receiveBroadcastStream().map(SystemHeading.fromMap).where((SystemHeading? h) => h != null).cast<SystemHeading>();

  double _declination = 0;
  bool _declinationKnown = false;
  bool _systemTrueNorth = true;

  /// Declinación magnética en grados (este positivo) que se suma al rumbo
  /// magnético, y si se conoce. Sin declinación conocida el rumbo queda
  /// magnético y así se marca.
  void setDeclination(double degrees, {required bool known}) {
    if (_declination == degrees && _declinationKnown == known) {
      return;
    }
    _declination = degrees;
    _declinationKnown = known;
    _update();
  }

  double get declination => _declination;

  bool get declinationKnown => _declinationKnown;

  /// En iPhone, en modo automático y con posición: el rumbo usa la
  /// declinación que calcula el sistema.
  bool get usingSystemDeclination => useSystemHeading && _systemTrueNorth && _system?.declination != null;

  /// Declinación del sistema (iPhone), si la hay.
  double? get systemDeclination => _system?.declination;

  /// En iPhone, usar el norte verdadero que calcula el sistema (modo
  /// automático). En modo manual se usa el rumbo magnético más la
  /// declinación elegida.
  set systemTrueNorth(bool v) {
    if (_systemTrueNorth != v) {
      _systemTrueNorth = v;
      _update();
    }
  }

  StreamSubscription<List<double>>? _accSub;
  StreamSubscription<List<double>>? _magSub;
  StreamSubscription<SystemHeading>? _sysSub;
  List<double>? _acc;
  List<double>? _mag;
  SystemHeading? _system;
  Orientation3? _last;
  bool _running = false;
  bool available = true;
  DeviceOrientation _physical = DeviceOrientation.portraitUp;

  Orientation3? get orientation => _last;

  bool get running => _running;

  /// Orientación física del teléfono (de la gravedad), con histéresis.
  DeviceOrientation get physicalOrientation => _physical;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    available = true;
    try {
      _accSub = _accelerometer().listen((List<double> v) {
        _acc = _smooth(_acc, v);
        final DeviceOrientation o = orientationFromGravity(_acc![0], _acc![1], _acc![2], _physical);
        if (o != _physical) {
          _physical = o;
        }
        _update();
      }, onError: (Object e) {
        available = false;
        notifyListeners();
      });
      if (useSystemHeading) {
        _sysSub = _systemHeading().listen((SystemHeading h) {
          _system = h;
          _update();
        }, onError: (Object e) {
          available = false;
          notifyListeners();
        });
      } else {
        _magSub = _magnetometer().listen((List<double> v) {
          _mag = _smooth(_mag, v);
          _update();
        }, onError: (Object e) {
          available = false;
          notifyListeners();
        });
      }
    } catch (e) {
      available = false;
      _running = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _running = false;
    _lastKey = null;
    await _accSub?.cancel();
    await _magSub?.cancel();
    await _sysSub?.cancel();
    _accSub = null;
    _magSub = null;
    _sysSub = null;
  }

  List<double> _smooth(List<double>? prev, List<double> v) {
    if (prev == null) {
      return v;
    }
    return <double>[for (int i = 0; i < 3; i++) prev[i] + alpha * (v[i] - prev[i])];
  }

  void _update() {
    final List<double>? a = _acc;
    if (a == null) {
      return;
    }
    Orientation3? o;
    if (useSystemHeading) {
      final SystemHeading? h = _system;
      if (h != null) {
        o = fromSystemHeading(a, h, declination: _declination, declinationKnown: _declinationKnown, useSystemTrueNorth: _systemTrueNorth);
      }
    } else {
      final List<double>? m = _mag;
      if (m != null) {
        o = compute(a, m, declination: _declinationKnown ? _declination : 0, trueNorth: _declinationKnown);
      }
    }
    if (o != null) {
      _last = o;
    }
    // Se avisa solo cuando cambia algo que se ve (al grado) o la orientación
    // física: con el teléfono quieto la cámara no se redibuja con cada uno
    // de los ~40 eventos por segundo de los sensores. La foto siempre toma
    // el último valor ([orientation]).
    final String key = o == null
        ? '-|${_physical.index}'
        : '${o.cameraHeading.round()}|${o.deviceHeading.round()}|${o.pitch.round()}|${o.roll.round()}|${o.flat}|${o.trueNorth}|${o.accuracy?.round()}|${_physical.index}';
    if (key != _lastKey) {
      _lastKey = key;
      notifyListeners();
    }
  }

  String? _lastKey;

  /// Rumbo del iPhone. Con el teléfono plano cuenta el borde superior; si
  /// no, el eje de la cámara. Al rumbo magnético se le suma la declinación
  /// del sistema (modo automático, si ya la tiene), la conocida (WMM o la
  /// manual) o ninguna, y entonces queda marcado como magnético.
  static Orientation3? fromSystemHeading(List<double> gravity, SystemHeading h, {double declination = 0, bool declinationKnown = false, bool useSystemTrueNorth = true}) {
    final _Tilt? tilt = _tiltOf(gravity);
    if (tilt == null) {
      return null;
    }
    final double offset;
    final bool trueNorth;
    if (useSystemTrueNorth && h.declination != null) {
      offset = h.declination!;
      trueNorth = true;
    } else if (declinationKnown) {
      offset = declination;
      trueNorth = true;
    } else {
      offset = 0;
      trueNorth = false;
    }
    final double device = _norm(h.topMagnetic + offset);
    final double camera = tilt.flat ? device : _norm(h.cameraMagnetic + offset);
    return Orientation3(cameraHeading: camera, deviceHeading: device, pitch: tilt.pitch, roll: tilt.roll, flat: tilt.flat, trueNorth: trueNorth, accuracy: h.accuracy);
  }

  static double _norm(double degrees) => (degrees % 360 + 360) % 360;

  /// Cálculo puro (probado en `geo_test.dart`). [gravity] y [magnetic] en el
  /// sistema de ejes del dispositivo: x a la derecha, y hacia arriba de la
  /// pantalla, z saliendo de la pantalla.
  static Orientation3? compute(List<double> gravity, List<double> magnetic, {double declination = 0, bool trueNorth = true}) {
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
    // (La componente x de M no hace falta para los rumbos.)
    final double my = gz * hx - gx * hz;
    final double mz = gx * hy - gy * hx;
    // Rumbo del borde superior (eje y del dispositivo) y del eje de la cámara (-z).
    final double deviceHeading = _deg(math.atan2(hy, my));
    final double cameraHeading = _deg(math.atan2(-hz, -mz));
    final _Tilt tilt = _tiltOf(gravity)!;
    final double heading = tilt.flat ? deviceHeading : cameraHeading;
    return Orientation3(
      cameraHeading: (heading + declination + 360) % 360,
      deviceHeading: (deviceHeading + declination + 360) % 360,
      pitch: tilt.pitch,
      roll: tilt.roll,
      flat: tilt.flat,
      trueNorth: trueNorth,
    );
  }

  static _Tilt? _tiltOf(List<double> gravity) {
    final double ax = gravity[0];
    final double ay = gravity[1];
    final double az = gravity[2];
    final double normA = math.sqrt(ax * ax + ay * ay + az * az);
    if (normA < 1e-6) {
      return null;
    }
    final double gx = ax / normA;
    final double gy = ay / normA;
    final double gz = az / normA;
    // Inclinación de la cámara: componente vertical del eje -z en el mundo.
    final double pitch = math.asin((-gz).clamp(-1.0, 1.0)) * 180 / math.pi; // 0 horizontal, +90 cámara hacia abajo
    final double roll = math.atan2(gx, gy) * 180 / math.pi;
    return _Tilt(-pitch, roll, gz.abs() > 0.85);
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

class _Tilt {
  const _Tilt(this.pitch, this.roll, this.flat);

  final double pitch;
  final double roll;
  final bool flat;
}
