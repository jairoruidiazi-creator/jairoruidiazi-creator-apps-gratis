import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';

import 'support/fakes.dart';

void main() {
  final DateTime t0 = DateTime.utc(2026, 3, 9, 19, 5);

  RawPosition at(double lat, double lon, {DateTime? time, double? accuracy = 5, double? altitude, double? speed}) =>
      RawPosition(latitude: lat, longitude: lon, time: time ?? t0, accuracy: accuracy, altitude: altitude, speed: speed);

  Future<LocationService> started(FakeLocationBackend backend, {bool msl = false, double undulation = 20}) async {
    backend.permission = LocationPermission.whileInUse;
    final LocationService loc = LocationService(backend: backend, systemAltitudeIsMsl: msl, undulation: (double lat, double lon) => undulation);
    await loc.start();
    return loc;
  }

  Future<void> settle() => pumpEventQueue();

  group('Altitud (G2, G15)', () {
    test('Android: la altura del GPS es elipsoidal y el geoide se resta una sola vez', () async {
      final FakeLocationBackend backend = FakeLocationBackend();
      final LocationService loc = await started(backend);
      // geolocator puede entregar ya la altura sobre el nivel del mar (Android 14 QPR3+):
      // ese valor no se usa; se toma la elipsoidal del canal propio.
      backend.altitudesCtrl.add(GpsAltitude(ellipsoid: 2620, time: t0, accuracy: 4));
      await settle();
      backend.positionsCtrl.add(at(4.711, -74.0721, altitude: 2600));
      await settle();
      expect(loc.fix!.altitudeEllipsoid, 2620);
      expect(loc.fix!.altitudeMsl, 2600);
      expect(loc.fix!.altitudeAccuracy, 4);
      // Con otra altura "del sistema" el resultado no cambia: no se mezcla.
      backend.positionsCtrl.add(at(4.711, -74.0721, altitude: 9999));
      await settle();
      expect(loc.fix!.altitudeMsl, 2600);
      await loc.stop();
      loc.dispose();
    });

    test('Android: sin lectura del GPS cercana en el tiempo la altitud queda desconocida', () async {
      final FakeLocationBackend backend = FakeLocationBackend();
      final LocationService loc = await started(backend);
      backend.altitudesCtrl.add(GpsAltitude(ellipsoid: 2620, time: t0.subtract(const Duration(seconds: 30))));
      await settle();
      backend.positionsCtrl.add(at(4.711, -74.0721, altitude: 2600));
      await settle();
      expect(loc.fix!.hasAltitude, isFalse);
      expect(loc.fix!.altitudeFor('msl'), isNull);
      // Si la lectura llega justo después, la posición la toma.
      backend.altitudesCtrl.add(GpsAltitude(ellipsoid: 2621, time: t0.add(const Duration(seconds: 1))));
      await settle();
      expect(loc.fix!.altitudeMsl, 2601);
      await loc.stop();
      loc.dispose();
    });

    test('iPhone: la altitud del sistema ya es sobre el nivel del mar', () async {
      final FakeLocationBackend backend = FakeLocationBackend();
      final LocationService loc = await started(backend, msl: true);
      backend.positionsCtrl.add(at(4.711, -74.0721, altitude: 2600));
      await settle();
      expect(loc.fix!.altitudeMsl, 2600);
      expect(loc.fix!.altitudeEllipsoid, 2620);
      // Lectura sin altitud (geolocator: hasAltitude falso): no se inventa un 0.
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(loc.fix!.hasAltitude, isFalse);
      await loc.stop();
      loc.dispose();
    });
  });

  group('Dirección (G3)', () {
    List<Placemark> bogota(double lat, double lon) => <Placemark>[const Placemark(thoroughfare: 'Carrera 7', subThoroughfare: '72-41', locality: 'Bogotá', country: 'Colombia')];

    test('Solo se usa cerca de donde se buscó y se borra al apagarla', () async {
      final FakeLocationBackend backend = FakeLocationBackend()..onPlacemarks = bogota;
      final LocationService loc = await started(backend);
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(loc.address?.full, 'Carrera 7 72-41, Bogotá, Colombia');
      // 150 m al norte sin red: la dirección anterior no se escribe aquí.
      backend.placemarkError = Exception('sin red');
      backend.positionsCtrl.add(at(4.71235, -74.0721));
      await settle();
      expect(loc.address, isNull);
      expect(loc.addressFor(loc.fix), isNull);
      // De vuelta en el punto original vuelve a valer...
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(loc.address, isNotNull);
      // ...salvo que se apague la opción.
      loc.geocodingEnabled = false;
      expect(loc.address, isNull);
      await loc.stop();
      loc.dispose();
    });

    test('Sin conexión no se reintenta en cada lectura', () async {
      final FakeLocationBackend backend = FakeLocationBackend()..placemarkError = Exception('sin red');
      final LocationService loc = await started(backend);
      for (int i = 0; i < 10; i++) {
        backend.positionsCtrl.add(at(4.711 + i * 0.00001, -74.0721));
        await settle();
      }
      expect(backend.placemarkCalls, 1);
      // Si el teléfono se mueve más de 200 m, sí se vuelve a intentar.
      backend.positionsCtrl.add(at(4.715, -74.0721));
      await settle();
      expect(backend.placemarkCalls, 2);
      await loc.stop();
      loc.dispose();
    });
  });

  group('Promedio (G4)', () {
    test('El promedio queda fijado y su precisión no se divide por √N', () async {
      final FakeLocationBackend backend = FakeLocationBackend();
      final LocationService loc = await started(backend);
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      loc.startAveraging(seconds: 20);
      for (int i = 0; i < 20; i++) {
        // Lecturas de ±5 m que oscilan ±2 m alrededor del punto.
        backend.positionsCtrl.add(at(4.711 + (i.isEven ? 0.000018 : -0.000018), -74.0721, time: t0.add(Duration(seconds: i))));
        await settle();
      }
      expect(loc.averaging, isTrue);
      expect(loc.averagingSamples, 20);
      loc.finishAveraging();
      final Fix f = loc.fix!;
      expect(loc.locked, isTrue);
      expect(f.source, PositionSource.averaged);
      expect(f.averagedSamples, 20);
      expect(f.latitude, closeTo(4.711, 1e-7));
      // 20 lecturas de ±5 m no dan ±1,1 m: siguen siendo ±5 m.
      expect(f.accuracy, closeTo(5, 0.01));
      // La siguiente lectura en vivo no reemplaza el promedio.
      backend.positionsCtrl.add(at(4.72, -74.08));
      await settle();
      expect(loc.fix!.source, PositionSource.averaged);
      expect(loc.fix!.latitude, closeTo(4.711, 1e-7));
      loc.unlock();
      expect(loc.fix!.latitude, 4.72);
      await loc.stop();
      loc.dispose();
    });

    test('La dispersión manda cuando las lecturas se alejan entre sí', () {
      final List<Fix> samples = <Fix>[
        Fix(latitude: 4.711, longitude: -74.0721, time: t0, accuracy: 3),
        Fix(latitude: 4.7111, longitude: -74.0721, time: t0, accuracy: 3),
        Fix(latitude: 4.7109, longitude: -74.0721, time: t0, accuracy: 3),
      ];
      final Fix avg = LocationService.averageOf(samples);
      // Las lecturas se separan ±11 m: la precisión no puede ser ±3 m.
      expect(avg.accuracy!, greaterThan(8));
      expect(avg.source, PositionSource.averaged);
    });
  });

  group('Lecturas viejas y permisos (M13, G13)', () {
    test('Una lectura de hace más de 10 s se marca como vieja', () async {
      final FakeLocationBackend backend = FakeLocationBackend();
      final LocationService loc = await started(backend);
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(withClock(Clock.fixed(t0.add(const Duration(seconds: 5))), () => loc.stale), isFalse);
      expect(withClock(Clock.fixed(t0.add(const Duration(seconds: 40))), () => loc.stale), isTrue);
      expect(withClock(Clock.fixed(t0.add(const Duration(seconds: 40))), () => loc.liveAge), const Duration(seconds: 40));
      // Fijada a propósito no es "vieja".
      loc.lock();
      expect(withClock(Clock.fixed(t0.add(const Duration(minutes: 5))), () => loc.stale), isFalse);
      await loc.stop();
      loc.dispose();
    });

    test('Una petición de permiso sin respuesta no deja el GPS colgado: reintentar lo arranca', () async {
      final FakeLocationBackend backend = FakeLocationBackend();
      final LocationService loc = LocationService(backend: backend, systemAltitudeIsMsl: false, undulation: (double a, double b) => 20);
      backend.pendingRequest = Completer<LocationPermission>();
      unawaited(loc.start());
      await settle();
      expect(backend.requestCount, 1);
      expect(loc.status, 'off');
      // El usuario dio el permiso en los ajustes y vuelve a la app.
      backend.pendingRequest = null;
      backend.permission = LocationPermission.whileInUse;
      await loc.retry();
      expect(loc.status, 'searching');
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(loc.status, 'ok');
      await loc.stop();
      loc.dispose();
    });

    test('Permiso negado para siempre: se ofrece abrir los ajustes', () async {
      final FakeLocationBackend backend = FakeLocationBackend()..requestResult = LocationPermission.deniedForever;
      final LocationService loc = LocationService(backend: backend, systemAltitudeIsMsl: false);
      await loc.start();
      expect(loc.status, 'deniedForever');
      expect(loc.needsSettings, isTrue);
      loc.dispose();
    });
  });

  group('Solo mientras se ve (M5, M6)', () {
    test('Se lee mientras una pantalla la usa y la app está a la vista; si no, se detiene', () async {
      final FakeLocationBackend backend = FakeLocationBackend()..permission = LocationPermission.whileInUse;
      final LocationService loc = LocationService(backend: backend, systemAltitudeIsMsl: false, undulation: (double a, double b) => 20);
      final Object camera = Object();
      final Object map = Object();
      expect(loc.wanted, isFalse);
      loc.acquire(camera);
      await settle();
      expect(backend.positionsCtrl.hasListener, isTrue);
      expect(backend.altitudesCtrl.hasListener, isTrue);
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(loc.status, 'ok');
      // El mapa también la usa: al salir de la cámara sigue.
      loc.acquire(map);
      loc.release(camera);
      await settle();
      expect(backend.positionsCtrl.hasListener, isTrue);
      // Nadie la usa: se detiene, pero se conserva la última posición.
      loc.release(map);
      await settle();
      expect(backend.positionsCtrl.hasListener, isFalse);
      expect(backend.altitudesCtrl.hasListener, isFalse);
      expect(loc.status, 'off');
      expect(loc.fix, isNotNull);
      // En segundo plano tampoco se lee, aunque la cámara esté abierta.
      loc.acquire(camera);
      await settle();
      expect(backend.positionsCtrl.hasListener, isTrue);
      loc.foreground = false;
      await settle();
      expect(backend.positionsCtrl.hasListener, isFalse);
      expect(loc.status, 'off');
      loc.foreground = true;
      await settle();
      expect(backend.positionsCtrl.hasListener, isTrue);
      expect(loc.status, 'searching');
      await loc.stop();
      loc.dispose();
    });

    test('Android: reintentar con las lecturas en marcha vuelve a abrir el canal de altitud', () async {
      final FakeLocationBackend backend = FakeLocationBackend();
      final LocationService loc = await started(backend);
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(loc.status, 'ok');
      expect(backend.altitudeOpens, 1);
      // El usuario pasó de ubicación aproximada a precisa en los ajustes.
      await loc.retry();
      expect(backend.altitudeOpens, 2);
      expect(backend.altitudesCtrl.hasListener, isTrue);
      backend.altitudesCtrl.add(GpsAltitude(ellipsoid: 2620, time: t0, accuracy: 4));
      await settle();
      backend.positionsCtrl.add(at(4.711, -74.0721));
      await settle();
      expect(loc.fix!.altitudeEllipsoid, 2620);
      await loc.stop();
      loc.dispose();
    });
  });

  group('Ubicación aproximada (G1 de la ronda 6)', () {
    test('Se detecta al arrancar, marca las lecturas, no da dirección y se puede pedir la precisa', () async {
      final FakeLocationBackend backend = FakeLocationBackend()
        ..permission = LocationPermission.whileInUse
        ..accuracy = LocationAccuracyStatus.reduced;
      final LocationService loc = LocationService(backend: backend, systemAltitudeIsMsl: true, undulation: (double a, double b) => 20);
      await loc.start();
      expect(loc.approximate, isTrue);
      backend.positionsCtrl.add(at(4.7113, -74.0727, accuracy: 2000));
      await settle();
      expect(loc.fix!.approximate, isTrue);
      // Fijar o promediar lecturas aproximadas no las vuelve precisas.
      loc.lock();
      expect(loc.fix!.approximate, isTrue);
      loc.unlock();
      // Ninguna dirección postal para una posición que puede estar a kilómetros:
      // ni se consulta.
      expect(loc.addressFor(loc.fix), isNull);
      expect(backend.placemarkCalls, 0);
      // El usuario la pide y la concede.
      backend.accuracyOnRequest = LocationAccuracyStatus.precise;
      expect(await loc.requestPreciseLocation(), isTrue);
      expect(backend.fullAccuracyRequests, 1);
      expect(loc.approximate, isFalse);
      backend.positionsCtrl.add(at(4.7113, -74.0727, accuracy: 4));
      await settle();
      expect(loc.fix!.approximate, isFalse);
      await loc.stop();
      loc.dispose();
    });

    test('Al volver a la app se vuelve a consultar (el usuario la cambió en los ajustes)', () async {
      final FakeLocationBackend backend = FakeLocationBackend()..permission = LocationPermission.whileInUse;
      final LocationService loc = LocationService(backend: backend, systemAltitudeIsMsl: true, undulation: (double a, double b) => 20);
      await loc.start();
      backend.positionsCtrl.add(at(4.7113, -74.0727));
      await settle();
      expect(loc.approximate, isFalse);
      // Apagó «Ubicación precisa» en los ajustes y volvió.
      backend.accuracy = LocationAccuracyStatus.reduced;
      await loc.retry();
      expect(loc.approximate, isTrue);
      // Si al pedirla sigue aproximada, se dice que no (la hoja ofrece los ajustes).
      expect(await loc.requestPreciseLocation(), isFalse);
      expect(loc.approximate, isTrue);
      // La activó en los ajustes.
      backend.accuracy = LocationAccuracyStatus.precise;
      await loc.retry();
      expect(loc.approximate, isFalse);
      await loc.stop();
      loc.dispose();
    });

    test('Sin dato de precisión (Android 11 o anterior, iOS 13) se toma como precisa', () async {
      final FakeLocationBackend backend = FakeLocationBackend()
        ..permission = LocationPermission.whileInUse
        ..accuracy = LocationAccuracyStatus.unknown;
      final LocationService loc = LocationService(backend: backend, systemAltitudeIsMsl: true);
      await loc.start();
      expect(loc.approximate, isFalse);
      await loc.stop();
      loc.dispose();
    });
  });
}
