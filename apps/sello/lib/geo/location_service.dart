import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'geoid.dart';

/// Posición resumida para el sello.
class Fix {
  const Fix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.altitudeAccuracy,
    required this.speed,
    required this.time,
    this.averagedSamples = 0,
    this.locked = false,
    this.altitudeMsl,
    this.altitudeEllipsoid,
  });

  final double latitude;
  final double longitude;

  /// Radio de error horizontal en metros.
  final double accuracy;

  /// Altitud elipsoidal o sobre el nivel del mar según el sistema (metros).
  final double altitude;
  final double altitudeAccuracy;

  /// Metros por segundo.
  final double speed;
  final DateTime time;
  final int averagedSamples;
  final bool locked;

  /// Altura sobre el nivel del mar (geoide EGM96), si se pudo calcular.
  final double? altitudeMsl;

  /// Altura sobre el elipsoide WGS84, si se pudo calcular.
  final double? altitudeEllipsoid;

  Fix copyWith({bool? locked, int? averagedSamples}) => Fix(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        altitude: altitude,
        altitudeAccuracy: altitudeAccuracy,
        speed: speed,
        time: time,
        averagedSamples: averagedSamples ?? this.averagedSamples,
        locked: locked ?? this.locked,
        altitudeMsl: altitudeMsl,
        altitudeEllipsoid: altitudeEllipsoid,
      );

  /// Altura según la referencia pedida ('msl' o 'ellipsoid'); si no hay dato
  /// convertido, la cruda del sistema.
  double altitudeFor(String reference) => (reference == 'ellipsoid' ? altitudeEllipsoid : altitudeMsl) ?? altitude;
}

/// Dirección postal resumida.
class Address {
  const Address({required this.line1, required this.line2, required this.full});

  final String line1;
  final String line2;
  final String full;
}

/// Ubicación con promedio de lecturas (para afinar en interiores), bloqueo
/// manual y geocodificación inversa del sistema (sin servidor propio).
class LocationService extends ChangeNotifier {
  LocationService({bool? systemAltitudeIsMsl, this.undulation = Geoid.undulation}) : systemAltitudeIsMsl = systemAltitudeIsMsl ?? (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  /// iOS entrega la altitud sobre el nivel del mar; Android, sobre el elipsoide.
  final bool systemAltitudeIsMsl;

  /// Ondulación del geoide (metros) o null si no está disponible.
  final double? Function(double lat, double lon) undulation;

  StreamSubscription<Position>? _sub;
  Fix? _fix;
  Fix? _locked;
  final List<Position> _window = <Position>[];
  bool _averaging = false;
  Timer? _averagingTimer;
  String status = 'off'; // off | denied | disabled | searching | ok
  Address? _address;
  double? _addressLat;
  double? _addressLon;
  bool _geocoding = false;
  bool geocodingEnabled = true;
  String localeIdentifier = 'es_CO';

  Fix? get fix => _locked ?? _fix;

  Fix? get live => _fix;

  bool get locked => _locked != null;

  bool get averaging => _averaging;

  Address? get address => _address;

  Future<void> start() async {
    if (_sub != null) {
      return;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        status = 'disabled';
        notifyListeners();
      }
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        status = 'denied';
        notifyListeners();
        return;
      }
      status = 'searching';
      notifyListeners();
      _sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0)).listen(_onPosition, onError: (Object e) {
        debugPrint('Ubicación: $e');
        status = 'disabled';
        notifyListeners();
      });
    } catch (e) {
      debugPrint('No se pudo iniciar la ubicación: $e');
      status = 'disabled';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _averagingTimer?.cancel();
    _averaging = false;
    status = 'off';
    notifyListeners();
  }

  void _onPosition(Position p) {
    status = 'ok';
    if (_averaging) {
      _window.add(p);
      _fix = _withAltitudes(_averageFix(_window));
    } else {
      _fix = _withAltitudes(Fix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        altitude: p.altitude,
        altitudeAccuracy: p.altitudeAccuracy,
        speed: p.speed < 0 ? 0 : p.speed,
        time: p.timestamp,
      ));
    }
    notifyListeners();
    unawaited(_maybeGeocode());
  }

  /// Promedio ponderado por la precisión (1/σ²) de las lecturas de la ventana;
  /// la precisión resultante es sqrt(1/Σw), que mejora con más muestras.
  static Fix _averageFix(List<Position> ps) {
    double wsum = 0;
    double lat = 0;
    double lon = 0;
    double alt = 0;
    for (final Position p in ps) {
      final double sigma = p.accuracy <= 0 ? 10 : p.accuracy;
      final double w = 1 / (sigma * sigma);
      wsum += w;
      lat += p.latitude * w;
      lon += p.longitude * w;
      alt += p.altitude * w;
    }
    final Position last = ps.last;
    if (wsum <= 0) {
      return Fix(latitude: last.latitude, longitude: last.longitude, accuracy: last.accuracy, altitude: last.altitude, altitudeAccuracy: last.altitudeAccuracy, speed: 0, time: last.timestamp, averagedSamples: ps.length);
    }
    return Fix(
      latitude: lat / wsum,
      longitude: lon / wsum,
      accuracy: math.sqrt(1 / wsum),
      altitude: alt / wsum,
      altitudeAccuracy: last.altitudeAccuracy,
      speed: 0,
      time: last.timestamp,
      averagedSamples: ps.length,
    );
  }

  /// Completa las alturas sobre el nivel del mar y sobre el elipsoide.
  Fix _withAltitudes(Fix f) {
    final double? n = undulation(f.latitude, f.longitude);
    final double? msl = systemAltitudeIsMsl ? f.altitude : (n == null ? null : f.altitude - n);
    final double? ell = systemAltitudeIsMsl ? (n == null ? null : f.altitude + n) : f.altitude;
    return Fix(
      latitude: f.latitude,
      longitude: f.longitude,
      accuracy: f.accuracy,
      altitude: f.altitude,
      altitudeAccuracy: f.altitudeAccuracy,
      speed: f.speed,
      time: f.time,
      averagedSamples: f.averagedSamples,
      locked: f.locked,
      altitudeMsl: msl,
      altitudeEllipsoid: ell,
    );
  }

  /// Promedia lecturas durante [seconds] segundos.
  void startAveraging({int seconds = 15}) {
    _window.clear();
    _averaging = true;
    _averagingTimer?.cancel();
    _averagingTimer = Timer(Duration(seconds: seconds), () {
      _averaging = false;
      notifyListeners();
    });
    notifyListeners();
  }

  void stopAveraging() {
    _averagingTimer?.cancel();
    _averaging = false;
    notifyListeners();
  }

  /// Fija la posición actual hasta que se libere (interiores, bajo techo).
  void lock() {
    final Fix? f = _fix;
    if (f != null) {
      _locked = f.copyWith(locked: true);
      notifyListeners();
    }
  }

  void unlock() {
    _locked = null;
    notifyListeners();
  }

  /// Fija una posición escrita a mano.
  void lockManual(double lat, double lon) {
    _locked = _withAltitudes(Fix(latitude: lat, longitude: lon, accuracy: 0, altitude: _fix?.altitude ?? 0, altitudeAccuracy: 0, speed: 0, time: clock.now(), locked: true));
    notifyListeners();
    unawaited(_maybeGeocode());
  }

  Future<void> _maybeGeocode() async {
    final Fix? f = fix;
    if (f == null || !geocodingEnabled || _geocoding) {
      return;
    }
    // Solo se vuelve a consultar si nos movimos más de ~40 m.
    if (_addressLat != null && _addressLon != null) {
      final double dLat = (f.latitude - _addressLat!).abs();
      final double dLon = (f.longitude - _addressLon!).abs();
      if (dLat < 0.00036 && dLon < 0.00036) {
        return;
      }
    }
    _geocoding = true;
    try {
      try {
        await setLocaleIdentifier(localeIdentifier);
      } catch (_) {}
      final List<Placemark> marks = await placemarkFromCoordinates(f.latitude, f.longitude);
      if (marks.isNotEmpty) {
        final Placemark m = marks.first;
        final String street = <String>[if ((m.thoroughfare ?? '').isNotEmpty) m.thoroughfare!, if ((m.subThoroughfare ?? '').isNotEmpty) m.subThoroughfare!].join(' ');
        final String line1 = street.isNotEmpty ? street : (m.name ?? '');
        final String line2 = <String>[if ((m.subLocality ?? '').isNotEmpty) m.subLocality!, if ((m.locality ?? '').isNotEmpty) m.locality!, if ((m.administrativeArea ?? '').isNotEmpty) m.administrativeArea!, if ((m.country ?? '').isNotEmpty) m.country!].join(', ');
        _address = Address(line1: line1, line2: line2, full: <String>[if (line1.isNotEmpty) line1, if (line2.isNotEmpty) line2].join(', '));
        _addressLat = f.latitude;
        _addressLon = f.longitude;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Geocodificación: $e');
    } finally {
      _geocoding = false;
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _averagingTimer?.cancel();
    super.dispose();
  }
}
