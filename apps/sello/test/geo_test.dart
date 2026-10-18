import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/geo/coords.dart';
import 'package:sello/geo/device_orientation.dart';
import 'package:sello/geo/geoid.dart';
import 'package:sello/geo/heading.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/geo/projection.dart';
import 'package:sello/geo/wmm.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/stamp_data.dart';

void main() {
  group('Coordenadas (valores de referencia de pyproj, mgrs y Open Location Code)', () {
    void checkUtm(double lat, double lon, int zone, String band, double e, double n) {
      final UtmPoint p = Coords.toUtm(lat, lon);
      expect(p.zone, zone);
      expect(p.band, band);
      expect(p.easting, closeTo(e, 0.01));
      expect(p.northing, closeTo(n, 0.01));
    }

    test('UTM coincide con PROJ al centímetro', () {
      checkUtm(4.7110, -74.0721, 18, 'N', 602910.007, 520787.259);
      checkUtm(-33.4489, -70.6693, 19, 'H', 344846.720, 6297700.156);
      checkUtm(51.5074, -0.1278, 30, 'U', 699316.234, 5710163.758);
      checkUtm(-33.8688, 151.2093, 56, 'H', 334368.634, 6250948.345);
      checkUtm(-0.1807, -78.4678, 17, 'M', 781861.457, 9980007.567);
      checkUtm(-4.2153, -69.9406, 19, 'M', 395611.344, 9534011.278);
      checkUtm(12.4583, -71.6667, 19, 'P', 210109.521, 1378688.504);
    });

    test('MGRS a 1 m', () {
      expect(Coords.mgrs(4.7110, -74.0721), '18NXL0291020787');
      expect(Coords.mgrs(-33.4489, -70.6693), '19HCC4484697700');
      expect(Coords.mgrs(51.5074, -0.1278), '30UXC9931610163');
      expect(Coords.mgrs(-33.8688, 151.2093), '56HLH3436850948');
      expect(Coords.mgrs(-0.1807, -78.4678), '17MQV8186180007');
      expect(Coords.mgrs(-4.2153, -69.9406), '19MCR9561134011');
      expect(Coords.mgrs(12.4583, -71.6667), '19PBP1010978688');
    });

    test('Plus Codes de 10 y 11 caracteres', () {
      expect(Coords.plusCode(4.7110, -74.0721), '67P7PW6H+C5');
      expect(Coords.plusCode(4.7110, -74.0721, length: 11), '67P7PW6H+C52');
      expect(Coords.plusCode(-33.4489, -70.6693), '47RFH82J+C7');
      expect(Coords.plusCode(-33.4489, -70.6693, length: 11), '47RFH82J+C7W');
      expect(Coords.plusCode(51.5074, -0.1278), '9C3XGV4C+XV');
      expect(Coords.plusCode(-33.8688, 151.2093, length: 11), '4RRH46J5+FPM');
      expect(Coords.plusCode(12.4583, -71.6667, length: 11), '774CF85M+88F');
    });

    test('Plus Codes en los bordes de celda: se trunca como la referencia (M7)', () {
      // Puntos donde redondear al entero (lo que hacía la app) daba otro
      // código que la implementación de referencia de Open Location Code.
      expect(Coords.plusCode(4.180243, -70.6772813, length: 11), '67PF58JF+33W');
      expect(Coords.plusCode(-4.0765277, -76.6201563, length: 11), '6775W9FH+9WP');
      expect(Coords.plusCode(6.7552592, -77.7527813, length: 11), '67R4Q64W+4V4');
      expect(Coords.plusCode(7.8392377, -79.6445313, length: 11), '67V2R9Q4+M5W');
    });

    test('Origen Nacional (CTM12) y zonas MAGNA-SIRGAS coinciden con PROJ al milímetro', () {
      void ctm(double lat, double lon, double e, double n) {
        final ProjectedPoint p = Coords.ctm12(lat, lon);
        expect(p.easting, closeTo(e, 0.002));
        expect(p.northing, closeTo(n, 0.002));
      }

      ctm(4.7110, -74.0721, 4881143.149, 2078651.312); // Bogotá
      ctm(-4.2153, -69.9406, 5339544.706, 1091643.422); // Leticia
      ctm(12.58, -81.70, 4052053.353, 2963947.971); // San Andrés
      ctm(6.19, -67.49, 5610255.821, 2245154.768); // Puerto Carreño
      ctm(6.2442, -75.5812, 4714489.067, 2248672.284); // Medellín
      ctm(1.6, -79.03, 4328292.656, 1735817.013); // Cabo Manglares
      expect(Coords.format(CoordFormat.ctm12, 4.7110, -74.0721), 'E 4881143.15 N 2078651.31');

      void magna(double lat, double lon, String zone, double e, double n) {
        final MagnaPoint p = Coords.magna(lat, lon);
        expect(p.zoneName, zone);
        expect(p.easting, closeTo(e, 0.002));
        expect(p.northing, closeTo(n, 0.002));
      }

      magna(4.7110, -74.0721, 'Bogotá', 1000599.986, 1012694.722);
      magna(6.2442, -75.5812, 'Oeste', 1165605.106, 1182478.052);
      magna(3.4516, -76.5320, 'Oeste', 1060617.159, 873447.711);
      magna(10.9685, -74.7813, 'Bogotá', 923074.321, 1704839.092);
      magna(7.89, -72.50, 'Este Central', 843122.438, 1364521.108);
      magna(-4.2153, -69.9406, 'Este Central', 1126228.183, 25563.291);
      magna(6.19, -67.49, 'Este', 1065023.432, 1176284.928);
      magna(12.58, -81.70, 'Oeste Oeste', 823671.586, 1883558.156);
      magna(1.80, -78.76, 'Oeste Oeste', 1146605.406, 690854.841);
      expect(Coords.format(CoordFormat.magna, 4.7110, -74.0721), 'Bogotá E 1000599.99 N 1012694.72');

      expect(Coords.inColombia(4.7110, -74.0721), isTrue);
      expect(Coords.inColombia(12.58, -81.70), isTrue);
      expect(Coords.inColombia(-33.4489, -70.6693), isFalse);
      expect(Coords.formatsFor(4.7110, -74.0721).length, CoordFormat.values.length);
      expect(Coords.formatsFor(51.5074, -0.1278), isNot(contains(CoordFormat.ctm12)));
      expect(Coords.format(CoordFormat.ctm12, 51.5074, -0.1278), Coords.dd(51.5074, -0.1278));
    });

    test('Formatos de grados', () {
      expect(Coords.dd(4.7110, -74.0721), '4.711000, -74.072100');
      expect(Coords.dms(4.7110, -74.0721), '4°42\'39.6"N 74°04\'19.6"W');
      expect(Coords.ddm(4.7110, -74.0721), '4°42.660\'N 74°04.326\'W');
      expect(Coords.dms(-33.4489, -70.6693), '33°26\'56.0"S 70°40\'09.5"W');
      // Redondeo que llegaría a 60": sube el minuto.
      expect(Coords.dms(0.99999999, 0), '1°00\'00.0"N 0°00\'00.0"E');
      expect(Coords.ddm(10.9999999, 0), '11°00.000\'N 0°00.000\'E');
      for (final CoordFormat f in CoordFormat.values) {
        expect(Coords.format(f, 4.711, -74.0721), isNotEmpty);
        expect(Coords.formatName(f, spanish: true), isNotEmpty);
        expect(Coords.formatName(f, spanish: false), isNotEmpty);
      }
    });

    test('Distancia, puntos cardinales y fachada', () {
      expect(Coords.distanceMeters(4.7110, -74.0721, 4.7110, -74.0621), closeTo(1109, 5));
      expect(Coords.cardinal(0), 'N');
      expect(Coords.cardinal(359), 'N');
      expect(Coords.cardinal(90), 'E');
      expect(Coords.cardinal(270), 'O');
      expect(Coords.cardinal(270, spanish: false), 'W');
      expect(Coords.cardinal(202.5), 'SSO');
      expect(Coords.facade(0), 'sur');
      expect(Coords.facade(90), 'oeste');
      expect(Coords.facade(315), 'sureste');
      expect(Coords.facade(180, spanish: false), 'north');
    });
  });

  group('Geoide EGM96', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await Geoid.load();
    });

    test('Ondulación en Colombia (rejilla de 5\') y en el mundo (30\')', () {
      expect(Geoid.loaded, isTrue);
      expect(Geoid.undulation(4.711, -74.0721), closeTo(21.82, 0.02)); // Bogotá
      expect(Geoid.undulation(-4.2153, -69.9406), closeTo(18.40, 0.02)); // Leticia
      expect(Geoid.undulation(10.39, -75.51), closeTo(-6.06, 0.02)); // Cartagena
      expect(Geoid.undulation(48.14, 11.58), closeTo(45.5, 0.3)); // Múnich
      expect(Geoid.undulation(-33.8688, 151.2093), closeTo(22.4, 0.3)); // Sídney
      expect(Geoid.undulation(-33.4489, -70.6693), closeTo(27.1, 0.3)); // Santiago
      expect(Geoid.undulation(4.711, 285.9279), closeTo(21.82, 0.02)); // longitud envuelta
      expect(Geoid.toMsl(2622.0, 4.711, -74.0721), closeTo(2600.18, 0.02));
      expect(Geoid.toEllipsoid(2600.18, 4.711, -74.0721), closeTo(2622.0, 0.02));
    });

    test('La posición manual no inventa altitud ni precisión (G2)', () {
      for (final bool msl in <bool>[false, true]) {
        final LocationService loc = LocationService(systemAltitudeIsMsl: msl);
        loc.lockManual(4.711, -74.0721);
        final Fix f = loc.fix!;
        expect(f.manual, isTrue);
        expect(f.accuracy, isNull);
        expect(f.altitudeMsl, isNull);
        expect(f.altitudeEllipsoid, isNull);
        expect(f.hasAltitude, isFalse);
        expect(f.altitudeFor('msl'), isNull);
        expect(f.altitudeFor('ellipsoid'), isNull);
        loc.dispose();
      }
    });
  });

  group('Modelo magnético WMM2025', () {
    test('Declinación coincide con el cálculo de referencia (NOAA)', () {
      expect(Wmm.decimalYear(DateTime.utc(2026)), 2026.0);
      expect(Wmm.decimalYear(DateTime.utc(2027, 7, 2, 12)), closeTo(2027.5, 1e-9));
      final MagneticField bogota = Wmm.compute(4.711, -74.072, altitudeMeters: 2600, at: DateTime.utc(2026));
      expect(bogota.declination, closeTo(-8.6643, 0.001));
      expect(bogota.inclination, closeTo(26.5948, 0.001));
      expect(bogota.intensity, closeTo(29976.5, 0.5));
      expect(bogota.horizontal, closeTo(26804.8, 0.5));
      expect(bogota.extrapolated, isFalse);
      expect(bogota.weakField, isFalse);
      expect(Wmm.declination(47.6205, -122.3493, at: DateTime.utc(2026)), closeTo(14.9729, 0.001));
      expect(Wmm.declination(0, 0, at: DateTime.utc(2026)), closeTo(-3.8929, 0.001));
      expect(Wmm.declination(-4.21, -69.94, altitudeMeters: 100, at: DateTime.utc(2026)), closeTo(-10.6094, 0.001));
      expect(Wmm.declination(-33.45, -70.67, altitudeMeters: 500, at: DateTime.utc(2027, 7, 2, 12)), closeTo(-0.0179, 0.001));
      expect(Wmm.declination(11.54, -72.91, at: DateTime.utc(2026, 10, 16)), closeTo(-10.1483, 0.001));
      final MagneticField polar = Wmm.compute(80, 120, at: DateTime.utc(2027, 7, 2, 12));
      expect(polar.declination, closeTo(-13.2180, 0.001));
      expect(polar.weakField, isTrue);
      expect(Wmm.compute(4.7, -74, at: DateTime.utc(2031)).extrapolated, isTrue);
    });
  });

  group('Brújula', () {
    test('Teléfono vertical con la cámara al norte', () {
      // Ejes del dispositivo: x derecha, y arriba, z saliendo de la pantalla.
      // Vertical: la gravedad va por -y (el acelerómetro mide +9.81 en y).
      // Campo magnético (hemisferio norte): 20 μT al norte y 30 μT hacia abajo.
      final Orientation3 o = HeadingService.compute(<double>[0, 9.81, 0], <double>[0, -30, -20])!;
      expect(o.cameraHeading, closeTo(0, 0.01));
      expect(o.pitch, closeTo(0, 0.01));
      expect(o.flat, isFalse);
    });

    test('Teléfono vertical con la cámara al este', () {
      final Orientation3 o = HeadingService.compute(<double>[0, 9.81, 0], <double>[-20, -30, 0])!;
      expect(o.cameraHeading, closeTo(90, 0.01));
    });

    test('Inclinar la cámara hacia el suelo no cambia el rumbo', () {
      // Cámara al norte, inclinada 30° hacia abajo: la gravedad gana componente -z... (rotación alrededor de x).
      const double c = 0.8660254;
      const double s = 0.5;
      // Vector gravedad (mundo) = abajo; abajo en ejes del dispositivo tras inclinar 30°.
      final List<double> g = <double>[0, 9.81 * c, 9.81 * s];
      // Norte (mundo) en ejes del dispositivo.
      final List<double> north = <double>[0, s, -c];
      final List<double> down = <double>[0, -c, -s];
      final List<double> m = <double>[for (int i = 0; i < 3; i++) 20 * north[i] + 30 * down[i]];
      final Orientation3 o = HeadingService.compute(g, m)!;
      expect(o.cameraHeading, closeTo(0, 0.01));
      expect(o.pitch, closeTo(30, 0.01));
    });

    test('Teléfono plano sobre la mesa usa el borde superior', () {
      final Orientation3 o = HeadingService.compute(<double>[0, 0, 9.81], <double>[0, 20, -30])!;
      expect(o.flat, isTrue);
      expect(o.deviceHeading, closeTo(0, 0.01));
      expect(o.cameraHeading, closeTo(0, 0.01));
      expect(o.pitch, closeTo(90, 0.01));
      // Borde superior al este: el norte queda hacia -x.
      final Orientation3 e = HeadingService.compute(<double>[0, 0, 9.81], <double>[-20, 0, -30])!;
      expect(e.deviceHeading, closeTo(90, 0.01));
    });

    test('La declinación se suma al rumbo', () {
      final Orientation3 o = HeadingService.compute(<double>[0, 9.81, 0], <double>[0, -30, -20], declination: -8.5)!;
      expect(o.cameraHeading, closeTo(351.5, 0.01));
    });

    test('Sin campo o sin gravedad no hay lectura', () {
      expect(HeadingService.compute(<double>[0, 0, 0], <double>[0, -30, -20]), isNull);
      expect(HeadingService.compute(<double>[0, 9.81, 0], <double>[0, 0, 0]), isNull);
    });

    test('Sin declinación conocida el rumbo queda marcado como magnético (M1)', () {
      final Orientation3 o = HeadingService.compute(<double>[0, 9.81, 0], <double>[0, -30, -20], trueNorth: false)!;
      expect(o.trueNorth, isFalse);
      final HeadingService h = HeadingService(useSystemHeading: false);
      expect(h.declinationKnown, isFalse);
      h.setDeclination(-8.6, known: true);
      expect(h.declinationKnown, isTrue);
      expect(h.declination, -8.6);
      h.dispose();
    });

    test('Cámara frontal: rumbo opuesto e inclinación invertida (M3)', () {
      final Orientation3 back = HeadingService.compute(<double>[0, 9.81, 0], <double>[-20, -30, 0])!;
      final Orientation3 front = back.forFrontCamera();
      expect(back.cameraHeading, closeTo(90, 0.01));
      expect(front.cameraHeading, closeTo(270, 0.01));
      expect(front.pitch, closeTo(-back.pitch, 1e-9));
      // Plano sobre la mesa manda el borde superior: no cambia.
      final Orientation3 flat = HeadingService.compute(<double>[0, 0, 9.81], <double>[0, 20, -30])!;
      expect(flat.forFrontCamera().cameraHeading, flat.cameraHeading);
    });
  });

  group('Rumbo del sistema en iPhone (G5)', () {
    test('Lee el evento del canal propio', () {
      final SystemHeading h = SystemHeading.fromMap(<String, Object>{'camera': 91.5, 'top': 12.0, 'declination': -8.4, 'accuracy': 7.0, 'calibration': 2})!;
      expect(h.cameraMagnetic, 91.5);
      expect(h.topMagnetic, 12.0);
      expect(h.declination, -8.4);
      expect(h.accuracy, 7.0);
      expect(h.calibration, 2);
      // Sin norte verdadero ni precisión (el sistema aún no los tiene).
      final SystemHeading bare = SystemHeading.fromMap(<String, Object>{'camera': 10, 'top': 20, 'accuracy': -1})!;
      expect(bare.declination, isNull);
      expect(bare.accuracy, isNull);
      expect(SystemHeading.fromMap(<String, Object>{'top': 20}), isNull);
      expect(SystemHeading.fromMap('x'), isNull);
    });

    test('Vertical usa el eje de la cámara; plano, el borde superior', () {
      const SystemHeading h = SystemHeading(cameraMagnetic: 100, topMagnetic: 40, declination: -8, accuracy: 5);
      final Orientation3 upright = HeadingService.fromSystemHeading(<double>[0, 9.81, 0], h)!;
      expect(upright.flat, isFalse);
      expect(upright.cameraHeading, closeTo(92, 1e-9));
      expect(upright.deviceHeading, closeTo(32, 1e-9));
      expect(upright.trueNorth, isTrue);
      expect(upright.accuracy, 5);
      final Orientation3 flat = HeadingService.fromSystemHeading(<double>[0, 0, 9.81], h)!;
      expect(flat.flat, isTrue);
      expect(flat.cameraHeading, closeTo(32, 1e-9));
    });

    test('Declinación: la del sistema, la conocida o ninguna (magnético)', () {
      const SystemHeading noTrue = SystemHeading(cameraMagnetic: 5, topMagnetic: 5);
      final Orientation3 magnetic = HeadingService.fromSystemHeading(<double>[0, 9.81, 0], noTrue)!;
      expect(magnetic.trueNorth, isFalse);
      expect(magnetic.cameraHeading, closeTo(5, 1e-9));
      final Orientation3 wmm = HeadingService.fromSystemHeading(<double>[0, 9.81, 0], noTrue, declination: -8.6, declinationKnown: true)!;
      expect(wmm.trueNorth, isTrue);
      expect(wmm.cameraHeading, closeTo(356.4, 1e-9));
      // En modo manual se usa la declinación elegida aunque el sistema tenga la suya.
      const SystemHeading withTrue = SystemHeading(cameraMagnetic: 5, topMagnetic: 5, declination: -8);
      final Orientation3 manual = HeadingService.fromSystemHeading(<double>[0, 9.81, 0], withTrue, declination: -2, declinationKnown: true, useSystemTrueNorth: false)!;
      expect(manual.cameraHeading, closeTo(3, 1e-9));
    });

    test('El servicio usa el canal del sistema y no el magnetómetro', () async {
      final List<List<double>> acc = <List<double>>[<double>[0, 9.81, 0]];
      final HeadingService h = HeadingService(
        useSystemHeading: true,
        accelerometer: () => Stream<List<double>>.fromIterable(acc),
        magnetometer: () => throw StateError('no debe usarse'),
        systemHeading: () => Stream<SystemHeading>.value(const SystemHeading(cameraMagnetic: 200, topMagnetic: 10, declination: -9)),
      );
      h.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(h.orientation, isNotNull);
      expect(h.orientation!.cameraHeading, closeTo(191, 1e-9));
      expect(h.usingSystemDeclination, isTrue);
      await h.stop();
      h.dispose();
    });
  });

  group('Orientación física del teléfono (B2)', () {
    test('Sale de la gravedad, con histéresis y sin cambiar cuando está plano', () {
      const DeviceOrientation up = DeviceOrientation.portraitUp;
      expect(orientationFromGravity(0, 9.81, 0, up), DeviceOrientation.portraitUp);
      // Borde superior a la izquierda: la gravedad (medida hacia arriba) va por +x.
      expect(orientationFromGravity(9.81, 0, 0, up), DeviceOrientation.landscapeLeft);
      expect(orientationFromGravity(-9.81, 0, 0, up), DeviceOrientation.landscapeRight);
      expect(orientationFromGravity(0, -9.81, 0, up), DeviceOrientation.portraitDown);
      // 50° de giro: todavía no cambia (45° + 10° de histéresis).
      expect(orientationFromGravity(9.81 * 0.766, 9.81 * 0.643, 0, up), DeviceOrientation.portraitUp);
      expect(orientationFromGravity(9.81 * 0.866, 9.81 * 0.5, 0, up), DeviceOrientation.landscapeLeft);
      // Volviendo desde horizontal, a 50° sigue horizontal.
      expect(orientationFromGravity(9.81 * 0.643, 9.81 * 0.766, 0, DeviceOrientation.landscapeLeft), DeviceOrientation.landscapeLeft);
      // Plano: se conserva la anterior.
      expect(orientationFromGravity(0.5, 0.2, 9.8, DeviceOrientation.landscapeRight), DeviceOrientation.landscapeRight);
    });

    test('Giro del sello respecto a la interfaz', () {
      expect(quarterTurnsBetween(DeviceOrientation.portraitUp, DeviceOrientation.portraitUp), 0);
      expect(quarterTurnsBetween(DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft), 1);
      expect(quarterTurnsBetween(DeviceOrientation.portraitUp, DeviceOrientation.landscapeRight), 3);
      expect(quarterTurnsBetween(DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeLeft), 0);
      expect(isLandscapeOrientation(DeviceOrientation.landscapeRight), isTrue);
      expect(isLandscapeOrientation(DeviceOrientation.portraitDown), isFalse);
    });
  });

  group('Datos del sello', () {
    final StampTemplate tpl = StampTemplate.defaultTemplate();
    final StampData data = StampData(
      time: DateTime(2026, 3, 9, 14, 5, 7),
      latitude: 4.711,
      longitude: -74.0721,
      accuracy: 4.2,
      altitude: 2601,
      heading: 135,
      pitch: 3,
      speed: 0,
      address: 'Cra 7 # 72-41, Bogotá',
      projectName: 'Obra',
      fields: <String, String>{'lote': '12', 'vacio': ''},
      fieldLabels: <String, String>{'lote': 'Lote'},
      notes: 'Columna C-3',
    );

    test('Las líneas siguen la plantilla y el orden de StampItem', () {
      final List<String> lines = data.lines(tpl).map((StampLine l) => l.text).toList();
      expect(lines.first, startsWith('09/03/2026 14:05:07 UTC'));
      expect(lines, contains('GPS: 4.711000, -74.072100'));
      expect(lines, contains('Alt.: 2601 m s. n. m.'));
      expect(lines, contains('Precisión: ± 4.2 m'));
      expect(lines, contains('Rumbo: 135° SE · incl.: 3°'));
      expect(lines, contains('Cra 7 # 72-41, Bogotá'));
      expect(lines, contains('Proyecto: Obra'));
      expect(lines, contains('Columna C-3'));
      // Los campos no están en la plantilla estándar.
      expect(lines.any((String l) => l.startsWith('Lote')), isFalse);
      tpl.items.add(StampItem.fields);
      tpl.items.add(StampItem.utc);
      tpl.items.add(StampItem.facade);
      tpl.items.add(StampItem.coords2);
      final List<String> more = data.lines(tpl).map((StampLine l) => l.text).toList();
      expect(more, contains('Lote: 12'));
      expect(more.any((String l) => l.startsWith('vacio')), isFalse);
      expect(more, contains('Fachada: noroeste'));
      expect(more, contains('UTM: 18N 602910 E 520787 N'));
      expect(more.any((String l) => l.startsWith('UTC: ')), isTrue);
      expect(data.summary(tpl), contains(' | '));
    });

    test('Posición manual, fijada, vieja y rumbo magnético se dicen en el sello (G2, M1, M13)', () {
      final StampTemplate t = StampTemplate.defaultTemplate()..items.addAll(<StampItem>{StampItem.facade, StampItem.speed});
      final StampData manual = StampData(time: DateTime(2026, 3, 9), latitude: 4.711, longitude: -74.0721, altitude: 2600, accuracy: 3, manual: true, heading: 10, headingTrue: false, speed: 3);
      final List<String> m = manual.lines(t).map((StampLine l) => l.text).toList();
      expect(m, contains('GPS: 4.711000, -74.072100 (posición manual)'));
      expect(m.any((String l) => l.startsWith('Alt.')), isFalse);
      expect(m.any((String l) => l.startsWith('Precisión')), isFalse);
      expect(m.any((String l) => l.startsWith('Velocidad')), isFalse);
      expect(m, contains('Rumbo: 10° N (magnético)'));
      expect(m, contains('Fachada: sur (magnética)'));
      final StampData stale = StampData(time: DateTime(2026, 3, 9), latitude: 4.711, longitude: -74.0721, fixAgeSeconds: 125);
      expect(stale.lines(t).map((StampLine l) => l.text), contains('GPS: 4.711000, -74.072100 (lectura de hace 2 min)'));
      final StampData locked = StampData(time: DateTime(2026, 3, 9), latitude: 4.711, longitude: -74.0721, locked: true, fixAgeSeconds: 600);
      expect(locked.lines(t).map((StampLine l) => l.text), contains('GPS: 4.711000, -74.072100 (fija)'));
    });

    test('CTM12 y MAGNA fuera de Colombia salen como grados con rótulo GPS (M14)', () {
      final StampTemplate t = StampTemplate(id: 'x', name: 'x', coordFormat: CoordFormat.ctm12, coordFormat2: CoordFormat.magna, items: <StampItem>{StampItem.coords, StampItem.coords2});
      final StampData lima = StampData(time: DateTime(2026, 3, 9), latitude: -12.0464, longitude: -77.0428);
      final List<String> lines = lima.lines(t).map((StampLine l) => l.text).toList();
      expect(lines.first, 'GPS: -12.046400, -77.042800');
      expect(lines.any((String l) => l.contains('CTM12') || l.contains('MAGNA')), isFalse);
      final StampData bogota = StampData(time: DateTime(2026, 3, 9), latitude: 4.711, longitude: -74.0721);
      expect(bogota.lines(t).first.text, startsWith('CTM12: '));
    });

    test('Los campos sin rótulo conocido no se escriben con la clave interna (G8)', () {
      final StampTemplate t = StampTemplate.defaultTemplate()..items.add(StampItem.fields);
      final StampData d = StampData(time: DateTime(2026, 3, 9), fields: <String, String>{'mgx3k0001a': '12', 'k2': 'J. Díaz'}, fieldLabels: <String, String>{'k2': 'Inspector'});
      final List<String> lines = d.lines(t).map((StampLine l) => l.text).toList();
      expect(lines, contains('Inspector: J. Díaz'));
      expect(lines.any((String l) => l.contains('mgx3k0001a')), isFalse);
    });

    test('Sin GPS se avisa y en inglés cambian los rótulos', () {
      final StampData sinGps = StampData(time: DateTime(2026, 3, 9), spanish: false, projectName: 'Site');
      final List<String> lines = sinGps.lines(StampTemplate.defaultTemplate()).map((StampLine l) => l.text).toList();
      expect(lines, contains('No GPS fix'));
      expect(lines, contains('Project: Site'));
      final StampTemplate sinRotulos = StampTemplate(id: 'x', name: 'x', showLabels: false);
      expect(data.lines(sinRotulos).map((StampLine l) => l.text), contains('4.711000, -74.072100'));
    });

    test('Nombres de archivo seguros', () {
      final DateTime t = DateTime(2026, 3, 9, 14, 5, 7);
      expect(buildFileName('{proyecto}_{fecha}_{hora}', project: 'Obra Calle 80', time: t, n: 3), 'Obra_Calle_80_20260309_140507');
      expect(buildFileName('{n}-{lat}_{lon}', project: 'x', time: t, lat: 4.711, lon: -74.0721, n: 3), '0003-4p71100_-74p07210');
      expect(buildFileName('', project: '', time: t, n: 9), 'foto_9');
      final String raro = buildFileName('{proyecto}/..\\{fecha}', project: 'a/b', time: t, n: 1);
      expect(raro, isNot(contains('/')));
      expect(raro, isNot(contains('\\')));
      expect(raro, isNot(contains('..')));
      expect(raro, endsWith('20260309'));
    });

    test('Plantillas y proyectos sobreviven al JSON', () {
      final StampTemplate t = StampTemplate(id: 't1', name: 'Mía', position: StampPosition.bottomBar, coordFormat: CoordFormat.mgrs, textScale: 1.4, logoPath: 'logos/x.png', items: <StampItem>{StampItem.coords, StampItem.compass});
      final StampTemplate back = StampTemplate.fromJson(t.toJson());
      expect(back.position, StampPosition.bottomBar);
      expect(back.coordFormat, CoordFormat.mgrs);
      expect(back.textScale, 1.4);
      expect(back.logoPath, 'logos/x.png');
      expect(back.items, <StampItem>{StampItem.coords, StampItem.compass});
      final Project p = Project(id: 'p1', name: 'Obra', fields: <FieldDef>[const FieldDef('lote', 'Lote', defaultValue: '1')], templateId: 't1', emoji: '🏗️');
      final Project pb = Project.fromJson(p.toJson());
      expect(pb.fields.single.label, 'Lote');
      expect(pb.fields.single.defaultValue, '1');
      expect(pb.templateId, 't1');
      expect(pb.emoji, '🏗️');
      final PhotoRecord r = PhotoRecord(
        id: 'r',
        projectId: 'p1',
        originalFile: 'a-orig.jpg',
        stampedFile: 'a.jpg',
        takenAt: DateTime.utc(2026, 1, 2, 8, 4, 5),
        utcOffsetMinutes: -300,
        latitude: 4.7,
        longitude: -74.1,
        tags: <String>['muro'],
        fields: <String, String>{'lote': '12'},
        fieldLabels: <String, String>{'lote': 'Lote'},
        altitudeMsl: 2600,
        headingTrue: false,
        positionSource: PositionSource.averaged,
        averagedSamples: 18,
        status: PhotoStatus.pending,
        templateId: 't1',
        frontCamera: true,
      );
      final PhotoRecord rb = PhotoRecord.fromJson(r.toJson());
      expect(rb.takenAt, DateTime.utc(2026, 1, 2, 8, 4, 5));
      expect(rb.takenAt.isUtc, isTrue);
      expect(rb.utcOffsetMinutes, -300);
      expect(formatDate(rb.wallTime, 'dd/MM/yyyy HH:mm'), '02/01/2026 03:04');
      expect(rb.offsetLabel, 'UTC−05:00');
      expect(rb.latitude, 4.7);
      expect(rb.tags, <String>['muro']);
      expect(rb.fields['lote'], '12');
      expect(rb.labelFor('lote'), 'Lote');
      expect(rb.altitudeMsl, 2600);
      expect(rb.headingTrue, isFalse);
      expect(rb.positionSource, PositionSource.averaged);
      expect(rb.averagedSamples, 18);
      expect(rb.status, PhotoStatus.pending);
      expect(rb.templateId, 't1');
      expect(rb.frontCamera, isTrue);
      expect(rb.hasLocation, isTrue);
    });

    test('La hora de la foto no cambia si el teléfono cambia de zona horaria (M9)', () {
      // Tomada en Bogotá (UTC−5) a las 14:05; se lee igual desde cualquier zona.
      final PhotoRecord r = PhotoRecord(id: 'z', projectId: 'p', originalFile: 'o', stampedFile: 's', takenAt: DateTime.utc(2026, 3, 9, 19, 5), utcOffsetMinutes: -300);
      final PhotoRecord back = PhotoRecord.fromJson(r.toJson());
      expect(formatDate(back.wallTime, 'HH:mm'), '14:05');
      expect(exifUtcOffset(back.utcOffsetMinutes), '-05:00');
      expect(formatUtcOffset(330), 'UTC+05:30');
      // Fichas viejas (sin desfase guardado) se leen con el desfase local.
      final Map<String, dynamic> legacy = r.toJson()..remove('utcOffset');
      expect(PhotoRecord.fromJson(legacy).takenAt, r.takenAt);
    });

    test('Formato de fecha y desfase horario', () {
      final DateTime d = DateTime(2026, 3, 9, 14, 5, 7);
      expect(formatDate(d, 'dd/MM/yyyy HH:mm:ss'), '09/03/2026 14:05:07');
      expect(formatDate(d, 'EEE dd/MM', spanish: true), 'lun 09/03');
      expect(formatDate(d, 'EEE dd/MM', spanish: false), 'Mon 09/03');
      expect(utcOffsetLabel(DateTime.utc(2026)), 'UTC+00:00');
    });
  });
}
