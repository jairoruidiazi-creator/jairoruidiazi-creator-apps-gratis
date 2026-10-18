import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../model/models.dart';
import 'coords.dart';
import 'geoid.dart';

/// Posición resumida para el sello.
class Fix {
  const Fix({
    required this.latitude,
    required this.longitude,
    required this.time,
    this.accuracy,
    this.altitudeMsl,
    this.altitudeEllipsoid,
    this.altitudeAccuracy,
    this.speed = 0,
    this.averagedSamples = 0,
    this.source = PositionSource.gps,
  });

  final double latitude;
  final double longitude;

  /// Radio de error horizontal en metros; null si no se conoce (posición
  /// escrita a mano).
  final double? accuracy;

  /// Altura sobre el nivel del mar (geoide EGM96), si se conoce.
  final double? altitudeMsl;

  /// Altura sobre el elipsoide WGS84, si se conoce.
  final double? altitudeEllipsoid;

  /// Precisión vertical en metros, si se conoce.
  final double? altitudeAccuracy;

  /// Metros por segundo.
  final double speed;
  final DateTime time;
  final int averagedSamples;
  final PositionSource source;

  /// Posición que no es la lectura en vivo (fijada, promediada o manual).
  bool get locked => source != PositionSource.gps;

  bool get manual => source == PositionSource.manual;

  bool get hasAltitude => altitudeMsl != null || altitudeEllipsoid != null;

  /// Altura según la referencia pedida ('msl' o 'ellipsoid'), o null si no
  /// se conoce. Nunca se usa una en lugar de la otra.
  double? altitudeFor(String reference) => reference == 'ellipsoid' ? altitudeEllipsoid : altitudeMsl;

  Fix copyWith({PositionSource? source, int? averagedSamples, double? altitudeMsl, double? altitudeEllipsoid, double? altitudeAccuracy, bool clearAltitude = false}) => Fix(
        latitude: latitude,
        longitude: longitude,
        time: time,
        accuracy: accuracy,
        altitudeMsl: clearAltitude ? null : (altitudeMsl ?? this.altitudeMsl),
        altitudeEllipsoid: clearAltitude ? null : (altitudeEllipsoid ?? this.altitudeEllipsoid),
        altitudeAccuracy: clearAltitude ? null : (altitudeAccuracy ?? this.altitudeAccuracy),
        speed: speed,
        averagedSamples: averagedSamples ?? this.averagedSamples,
        source: source ?? this.source,
      );
}

/// Dirección postal resumida y el punto para el que se buscó.
class Address {
  const Address({required this.line1, required this.line2, required this.full, required this.latitude, required this.longitude});

  final String line1;
  final String line2;
  final String full;
  final double latitude;
  final double longitude;
}

/// Lectura de posición tal como la entrega el sistema.
class RawPosition {
  const RawPosition({required this.latitude, required this.longitude, required this.time, this.accuracy, this.altitude, this.altitudeAccuracy, this.speed});

  final double latitude;
  final double longitude;
  final DateTime time;
  final double? accuracy;

  /// Altitud tal como la da el sistema: en iPhone es sobre el nivel del mar.
  /// En Android no se usa (ver [GpsAltitude]).
  final double? altitude;
  final double? altitudeAccuracy;
  final double? speed;
}

/// Altura sobre el elipsoide WGS84 leída directamente del GPS de Android
/// (`Location.getAltitude()`, que por contrato es siempre elipsoidal).
class GpsAltitude {
  const GpsAltitude({required this.ellipsoid, required this.time, this.accuracy});

  final double ellipsoid;
  final DateTime time;
  final double? accuracy;

  static GpsAltitude? fromMap(Object? event) {
    if (event is! Map) {
      return null;
    }
    final Object? e = event['ellipsoid'];
    final Object? t = event['time'];
    if (e is! num || t is! num) {
      return null;
    }
    final Object? acc = event['accuracy'];
    return GpsAltitude(ellipsoid: e.toDouble(), time: DateTime.fromMillisecondsSinceEpoch(t.toInt(), isUtc: true), accuracy: acc is num ? acc.toDouble() : null);
  }
}

/// Acceso al sistema de ubicación. Las pruebas usan uno simulado.
abstract class LocationBackend {
  Future<bool> isServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Stream<RawPosition> positions();

  /// Alturas elipsoidales del GPS (Android); vacío donde no hace falta.
  Stream<GpsAltitude> gpsAltitudes();
  Future<List<Placemark>> placemarks(double latitude, double longitude, String localeIdentifier);
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

/// Ubicación del sistema con geolocator y geocoding, y en Android la altura
/// elipsoidal por el canal propio co.appsgratis.sello/altitude (ver
/// native/android/MainActivity.kt y docs/DECISIONES.md, "Altitud").
class SystemLocationBackend implements LocationBackend {
  static const EventChannel _altitudeChannel = EventChannel('co.appsgratis.sello/altitude');

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();

  @override
  Stream<RawPosition> positions() => Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0)).map(
        (Position p) => RawPosition(
          latitude: p.latitude,
          longitude: p.longitude,
          time: p.timestamp,
          accuracy: p.hasAccuracy || p.accuracy > 0 ? p.accuracy : null,
          altitude: p.hasAltitude ? p.altitude : null,
          altitudeAccuracy: p.hasAltitudeAccuracy ? p.altitudeAccuracy : null,
          speed: p.hasSpeed || p.speed > 0 ? p.speed : null,
        ),
      );

  @override
  Stream<GpsAltitude> gpsAltitudes() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Stream<GpsAltitude>.empty();
    }
    return _altitudeChannel.receiveBroadcastStream().map(GpsAltitude.fromMap).where((GpsAltitude? a) => a != null).cast<GpsAltitude>();
  }

  @override
  Future<List<Placemark>> placemarks(double latitude, double longitude, String localeIdentifier) async {
    try {
      await setLocaleIdentifier(localeIdentifier);
    } catch (_) {}
    return placemarkFromCoordinates(latitude, longitude);
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// Ubicación con promedio de lecturas (para afinar en interiores), bloqueo
/// manual y geocodificación inversa del sistema (sin servidor propio).
///
/// Altitud: en iPhone el sistema la da sobre el nivel del mar. En Android se
/// toma la elipsoidal del GPS por un canal propio, porque la que entrega
/// geolocator puede venir ya sobre el nivel del mar (Android 14 QPR3 o
/// superior la agrega y el complemento la sustituye sin avisar) o no; sin
/// esa lectura la altitud queda desconocida en vez de adivinarse.
class LocationService extends ChangeNotifier {
  LocationService({LocationBackend? backend, bool? systemAltitudeIsMsl, this.undulation = Geoid.undulation, this.altitudeMaxAge = const Duration(seconds: 5), this.addressRadiusMeters = 75})
      : backend = backend ?? SystemLocationBackend(),
        systemAltitudeIsMsl = systemAltitudeIsMsl ?? (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  final LocationBackend backend;

  /// iPhone entrega la altitud sobre el nivel del mar; Android, por el canal
  /// propio, sobre el elipsoide.
  final bool systemAltitudeIsMsl;

  /// Ondulación del geoide (metros) o null si no está disponible.
  final double? Function(double lat, double lon) undulation;

  /// Máxima diferencia de tiempo entre la posición y la lectura de altitud
  /// del GPS para usarla.
  final Duration altitudeMaxAge;

  /// La dirección solo se escribe si se buscó a menos de esta distancia.
  final double addressRadiusMeters;

  StreamSubscription<RawPosition>? _sub;
  StreamSubscription<GpsAltitude>? _altSub;
  Fix? _live;
  Fix? _locked;
  GpsAltitude? _gpsAltitude;
  final List<Fix> _window = <Fix>[];
  bool _averaging = false;
  Timer? _averagingTimer;
  bool _starting = false;
  int _generation = 0;

  /// off | denied | deniedForever | disabled | searching | ok
  String status = 'off';
  Address? _address;
  bool _geocoding = false;
  bool _geocodingEnabled = true;
  int _geocodeFailures = 0;
  DateTime? _nextGeocodeAt;
  double? _failedLat;
  double? _failedLon;
  String localeIdentifier = 'es_CO';

  /// Posición para el sello: la fijada (a mano, promediada o bloqueada) o la
  /// de la lectura en vivo; durante un promedio, el promedio parcial.
  Fix? get fix {
    if (_locked != null) {
      return _locked;
    }
    if (_averaging && _window.length >= 2) {
      return averageOf(_window);
    }
    return _live;
  }

  Fix? get live => _live;

  bool get locked => _locked != null;

  bool get averaging => _averaging;

  int get averagingSamples => _window.length;

  /// Hace cuánto llegó la última lectura en vivo (null si no hay).
  Duration? get liveAge => _live == null ? null : clock.now().difference(_live!.time);

  /// La lectura en vivo es vieja (bajo techo, sin señal): la posición ya no
  /// corresponde necesariamente al lugar donde está el teléfono.
  bool get stale {
    final Duration? age = liveAge;
    return _locked == null && age != null && age > const Duration(seconds: 10);
  }

  bool get geocodingEnabled => _geocodingEnabled;

  /// Apagar la dirección borra la que hubiera, para que no se escriba en
  /// fotos posteriores.
  set geocodingEnabled(bool v) {
    if (_geocodingEnabled == v) {
      return;
    }
    _geocodingEnabled = v;
    if (!v) {
      _address = null;
      notifyListeners();
    } else {
      unawaited(_maybeGeocode());
    }
  }

  /// Dirección de la posición actual, solo si se buscó cerca de ella.
  Address? get address => addressFor(fix);

  /// Dirección para [f]: la última encontrada, si está a menos de
  /// [addressRadiusMeters]. Así una dirección vieja nunca acaba en una foto
  /// tomada en otro lugar.
  Address? addressFor(Fix? f) {
    final Address? a = _address;
    if (f == null || a == null || !_geocodingEnabled) {
      return null;
    }
    return Coords.distanceMeters(f.latitude, f.longitude, a.latitude, a.longitude) <= addressRadiusMeters ? a : null;
  }

  /// El usuario puede resolver el problema desde los ajustes del teléfono.
  bool get needsSettings => status == 'denied' || status == 'deniedForever' || status == 'disabled';

  /// Pantallas que necesitan la ubicación ahora (la cámara o el mapa, a la
  /// vista).
  final Set<Object> _users = <Object>{};
  bool _foreground = true;

  /// La app está en primer plano. En segundo plano las lecturas se detienen
  /// (Sello no usa la ubicación en segundo plano) y al volver se retoman si
  /// alguna pantalla las necesita.
  bool get foreground => _foreground;

  set foreground(bool v) {
    if (_foreground != v) {
      _foreground = v;
      _syncRunning();
    }
  }

  /// Hay que leer la ubicación: la app está a la vista y una pantalla la usa.
  bool get wanted => _foreground && _users.isNotEmpty;

  /// [user] necesita la ubicación mientras se ve (la cámara después de abrir
  /// su permiso; el mapa mientras su pestaña está a la vista).
  void acquire(Object user) {
    if (_users.add(user)) {
      _syncRunning();
    }
  }

  /// [user] dejó de verse: si nadie más la usa, se detienen las lecturas
  /// (se conservan la última posición y la que se haya fijado).
  void release(Object user) {
    if (_users.remove(user)) {
      _syncRunning();
    }
  }

  void _syncRunning() {
    if (wanted) {
      if (_sub == null && !_starting) {
        unawaited(start());
      }
    } else if (_sub != null || _starting) {
      unawaited(_pause());
    }
  }

  /// Detiene las lecturas sin olvidar la posición fijada ni la última en
  /// vivo (un promedio en curso se cierra con lo que haya juntado).
  Future<void> _pause() async {
    final int generation = ++_generation;
    _starting = false;
    await _cancelStreams();
    // Si mientras tanto alguien volvió a pedirla, ya se está arrancando.
    if (generation == _generation) {
      status = 'off';
      notifyListeners();
    }
  }

  Future<void> start() async {
    if (_sub != null || _starting) {
      return;
    }
    _starting = true;
    final int generation = ++_generation;
    try {
      final bool enabled = await backend.isServiceEnabled();
      if (generation != _generation) {
        return;
      }
      LocationPermission p = await backend.checkPermission();
      if (p == LocationPermission.denied) {
        p = await backend.requestPermission();
      }
      if (generation != _generation) {
        // Otra llamada (por ejemplo, al volver a la app) tomó el relevo.
        return;
      }
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever || p == LocationPermission.unableToDetermine) {
        status = p == LocationPermission.deniedForever ? 'deniedForever' : 'denied';
        notifyListeners();
        return;
      }
      _listen();
      if (!enabled) {
        status = 'disabled';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('No se pudo iniciar la ubicación: $e');
      if (generation == _generation) {
        status = 'disabled';
        notifyListeners();
      }
    } finally {
      if (generation == _generation) {
        _starting = false;
      }
    }
  }

  /// Vuelve a intentar (al volver a la app o desde la hoja del GPS): si no
  /// hay lecturas en curso consulta otra vez el permiso y el servicio. Deja
  /// atrás una petición de permiso que el sistema no contestó.
  Future<void> retry() async {
    if (_sub != null && status == 'ok') {
      // Las lecturas siguen, pero el canal de altitud de Android pudo
      // haberse abierto sin el permiso de ubicación precisa (que el usuario
      // acaba de dar en los ajustes): se vuelve a abrir.
      _resubscribeAltitude();
      return;
    }
    _generation++;
    _starting = false;
    await _cancelStreams();
    await start();
  }

  void _resubscribeAltitude() {
    if (systemAltitudeIsMsl || _sub == null) {
      return;
    }
    final StreamSubscription<GpsAltitude>? old = _altSub;
    _altSub = null;
    unawaited(old?.cancel());
    _altSub = backend.gpsAltitudes().listen(_onGpsAltitude, onError: (Object e) {
      debugPrint('Altitud del GPS: $e');
    });
  }

  void _listen() {
    status = 'searching';
    notifyListeners();
    _sub = backend.positions().listen(_onPosition, onError: (Object e) {
      debugPrint('Ubicación: $e');
      status = 'disabled';
      unawaited(_cancelStreams());
      notifyListeners();
    });
    if (!systemAltitudeIsMsl) {
      _altSub = backend.gpsAltitudes().listen(_onGpsAltitude, onError: (Object e) {
        // Sin lectura de altitud del GPS la altitud queda desconocida.
        debugPrint('Altitud del GPS: $e');
      });
    }
  }

  Future<void> _cancelStreams() async {
    final StreamSubscription<RawPosition>? s = _sub;
    final StreamSubscription<GpsAltitude>? a = _altSub;
    _sub = null;
    _altSub = null;
    await s?.cancel();
    await a?.cancel();
  }

  Future<void> stop() async {
    _generation++;
    _starting = false;
    await _cancelStreams();
    _averagingTimer?.cancel();
    _averaging = false;
    _window.clear();
    status = 'off';
    notifyListeners();
  }

  /// Para pruebas y para el canal: entrega una lectura como si viniera del
  /// sistema.
  @visibleForTesting
  void debugAddPosition(RawPosition p) => _onPosition(p);

  void _onPosition(RawPosition p) {
    status = 'ok';
    final Fix f = _fixFrom(p);
    _live = f;
    if (_averaging) {
      _window.add(f);
    }
    notifyListeners();
    unawaited(_maybeGeocode());
  }

  void _onGpsAltitude(GpsAltitude a) {
    _gpsAltitude = a;
    final Fix? live = _live;
    if (live != null && !live.hasAltitude && (live.time.difference(a.time)).abs() <= altitudeMaxAge) {
      _live = _withAltitudes(live, null);
      notifyListeners();
    }
  }

  Fix _fixFrom(RawPosition p) {
    final double? speed = p.speed;
    final Fix f = Fix(
      latitude: p.latitude,
      longitude: p.longitude,
      time: p.time,
      accuracy: p.accuracy != null && p.accuracy! > 0 ? p.accuracy : null,
      speed: speed == null || speed < 0 ? 0 : speed,
    );
    return _withAltitudes(f, p);
  }

  /// Completa las dos alturas (nivel del mar y elipsoide) con una sola
  /// conversión por el geoide.
  Fix _withAltitudes(Fix f, RawPosition? raw) {
    final double? n = undulation(f.latitude, f.longitude);
    double? msl;
    double? ell;
    double? acc;
    if (systemAltitudeIsMsl) {
      msl = raw?.altitude;
      acc = raw?.altitudeAccuracy;
      ell = (msl == null || n == null) ? null : msl + n;
    } else {
      final GpsAltitude? g = _gpsAltitude;
      if (g != null && (f.time.difference(g.time)).abs() <= altitudeMaxAge) {
        ell = g.ellipsoid;
        acc = g.accuracy;
        msl = n == null ? null : ell - n;
      }
    }
    return Fix(
      latitude: f.latitude,
      longitude: f.longitude,
      time: f.time,
      accuracy: f.accuracy,
      altitudeMsl: msl,
      altitudeEllipsoid: ell,
      altitudeAccuracy: acc,
      speed: f.speed,
      averagedSamples: f.averagedSamples,
      source: f.source,
    );
  }

  /// Promedio de varias lecturas, ponderado por su precisión (1/σ²).
  ///
  /// La precisión del promedio no se divide por √N: las lecturas seguidas
  /// del GPS están correlacionadas (comparten el mismo error de satélites y
  /// rebotes), así que no se vuelven independientes por ser muchas. Se toma
  /// la mayor entre la dispersión de las lecturas alrededor del promedio y
  /// la precisión típica que declaró el GPS.
  static Fix averageOf(List<Fix> samples) {
    assert(samples.isNotEmpty);
    double wsum = 0;
    double lat = 0;
    double lon = 0;
    double sigmaSum = 0;
    double mslSum = 0;
    double mslW = 0;
    double ellSum = 0;
    double ellW = 0;
    for (final Fix s in samples) {
      final double sigma = math.max(1.0, s.accuracy ?? 10);
      final double w = 1 / (sigma * sigma);
      wsum += w;
      lat += s.latitude * w;
      lon += s.longitude * w;
      sigmaSum += sigma * w;
      if (s.altitudeMsl != null) {
        mslSum += s.altitudeMsl! * w;
        mslW += w;
      }
      if (s.altitudeEllipsoid != null) {
        ellSum += s.altitudeEllipsoid! * w;
        ellW += w;
      }
    }
    final double mLat = lat / wsum;
    final double mLon = lon / wsum;
    double spread = 0;
    for (final Fix s in samples) {
      final double sigma = math.max(1.0, s.accuracy ?? 10);
      final double w = 1 / (sigma * sigma);
      final double d = Coords.distanceMeters(mLat, mLon, s.latitude, s.longitude);
      spread += w * d * d;
    }
    final double rms = math.sqrt(spread / wsum);
    final double typical = sigmaSum / wsum;
    final Fix last = samples.last;
    return Fix(
      latitude: mLat,
      longitude: mLon,
      time: last.time,
      accuracy: math.max(rms, typical),
      altitudeMsl: mslW > 0 ? mslSum / mslW : null,
      altitudeEllipsoid: ellW > 0 ? ellSum / ellW : null,
      altitudeAccuracy: last.altitudeAccuracy,
      averagedSamples: samples.length,
      source: PositionSource.averaged,
    );
  }

  /// Promedia lecturas durante [seconds] segundos. Al terminar, el promedio
  /// queda fijado (hasta que se libere) en vez de perderse con la siguiente
  /// lectura.
  void startAveraging({int seconds = 20}) {
    _window.clear();
    _locked = null;
    _averaging = true;
    _averagingTimer?.cancel();
    _averagingTimer = Timer(Duration(seconds: seconds), finishAveraging);
    notifyListeners();
  }

  /// Termina el promedio: con dos lecturas o más lo fija; con una, fija esa.
  void finishAveraging() {
    _averagingTimer?.cancel();
    if (!_averaging) {
      return;
    }
    _averaging = false;
    if (_window.length >= 2) {
      _locked = averageOf(_window);
    } else if (_window.length == 1) {
      _locked = _window.single.copyWith(source: PositionSource.locked);
    }
    _window.clear();
    notifyListeners();
    unawaited(_maybeGeocode());
  }

  /// Cancela el promedio sin fijar nada.
  void cancelAveraging() {
    _averagingTimer?.cancel();
    _averaging = false;
    _window.clear();
    notifyListeners();
  }

  /// Fija la posición actual hasta que se libere (interiores, bajo techo).
  void lock() {
    final Fix? f = _live;
    if (f != null) {
      _locked = f.copyWith(source: PositionSource.locked);
      notifyListeners();
    }
  }

  void unlock() {
    _locked = null;
    notifyListeners();
  }

  /// Fija una posición escrita a mano: sin precisión ni altitud, porque no
  /// se midieron.
  void lockManual(double lat, double lon) {
    _locked = Fix(latitude: lat, longitude: lon, time: clock.now(), source: PositionSource.manual);
    notifyListeners();
    unawaited(_maybeGeocode());
  }

  Future<void> _maybeGeocode() async {
    final Fix? f = fix;
    if (f == null || !_geocodingEnabled || _geocoding) {
      return;
    }
    // Ya hay dirección cerca: no se vuelve a consultar.
    final Address? a = _address;
    if (a != null && Coords.distanceMeters(f.latitude, f.longitude, a.latitude, a.longitude) < 40) {
      return;
    }
    // Sin conexión no se insiste en cada lectura: se espera cada vez más
    // (30 s, 1, 2, 4… hasta 5 min), salvo que la posición cambie mucho.
    final DateTime now = clock.now();
    final DateTime? next = _nextGeocodeAt;
    if (next != null && now.isBefore(next) && _failedLat != null && Coords.distanceMeters(f.latitude, f.longitude, _failedLat!, _failedLon!) < 200) {
      return;
    }
    _geocoding = true;
    try {
      final List<Placemark> marks = await backend.placemarks(f.latitude, f.longitude, localeIdentifier);
      if (marks.isNotEmpty && _geocodingEnabled) {
        final Placemark m = marks.first;
        final String street = <String>[if ((m.thoroughfare ?? '').isNotEmpty) m.thoroughfare!, if ((m.subThoroughfare ?? '').isNotEmpty) m.subThoroughfare!].join(' ');
        final String line1 = street.isNotEmpty ? street : (m.name ?? '');
        final String line2 = <String>[if ((m.subLocality ?? '').isNotEmpty) m.subLocality!, if ((m.locality ?? '').isNotEmpty) m.locality!, if ((m.administrativeArea ?? '').isNotEmpty) m.administrativeArea!, if ((m.country ?? '').isNotEmpty) m.country!].join(', ');
        _address = Address(line1: line1, line2: line2, full: <String>[if (line1.isNotEmpty) line1, if (line2.isNotEmpty) line2].join(', '), latitude: f.latitude, longitude: f.longitude);
        _geocodeFailures = 0;
        _nextGeocodeAt = null;
        notifyListeners();
      } else if (marks.isEmpty) {
        _registerGeocodeFailure(f, now);
      }
    } catch (e) {
      debugPrint('Geocodificación: $e');
      _registerGeocodeFailure(f, now);
    } finally {
      _geocoding = false;
    }
  }

  void _registerGeocodeFailure(Fix f, DateTime now) {
    _geocodeFailures += 1;
    final int seconds = math.min(300, 30 * (1 << math.min(_geocodeFailures - 1, 4)));
    _nextGeocodeAt = now.add(Duration(seconds: seconds));
    _failedLat = f.latitude;
    _failedLon = f.longitude;
  }

  @override
  void dispose() {
    _generation++;
    _users.clear();
    unawaited(_cancelStreams());
    _averagingTimer?.cancel();
    super.dispose();
  }
}
