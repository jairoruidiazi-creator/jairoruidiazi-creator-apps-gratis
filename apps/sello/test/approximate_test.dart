import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sello/core/app_state.dart';
import 'package:sello/core/exports.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/geo/coords.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';
import 'package:sello/stamp/composer.dart';
import 'package:sello/stamp/stamp_data.dart';
import 'package:sello/ui/gallery/gallery_screen.dart';
import 'package:sello/ui/map/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// G1 de la ronda 6: con el permiso de ubicación aproximada las coordenadas
/// pueden estar a kilómetros. La foto lo dice y nada muestra decimales que
/// aparenten una precisión que no hay.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late AppState state;
  late AppSettings settings;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_aprox');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await testSettings();
    state = await testState(tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('Formatos sin detalle de más: ~1 km en todos', () {
    const double lat = 4.71137;
    const double lon = -74.07263;
    expect(Coords.format(CoordFormat.dd, lat, lon, coarse: true), '4.71, -74.07');
    expect(Coords.format(CoordFormat.dms, lat, lon, coarse: true), "4°43'N 74°04'W");
    expect(Coords.format(CoordFormat.ddm, lat, lon, coarse: true), "4°43'N 74°04'W");
    final String utm = Coords.format(CoordFormat.utm, lat, lon, coarse: true);
    expect(utm, matches(RegExp(r'^18N \d+000 E \d+000 N$')));
    expect(Coords.format(CoordFormat.mgrs, lat, lon, coarse: true), matches(RegExp(r'^18N[A-Z]{2}\d{4}$')));
    expect(Coords.format(CoordFormat.plusCode, lat, lon, coarse: true), matches(RegExp(r'^[2-9CFGHJMPQRVWX]{6}00\+$')));
    expect(Coords.format(CoordFormat.ctm12, lat, lon, coarse: true), matches(RegExp(r'^E \d+000 N \d+000$')));
    expect(Coords.format(CoordFormat.magna, lat, lon, coarse: true), matches(RegExp(r'^Bogotá E \d+000 N \d+000$')));
    // Lo preciso no cambia.
    expect(Coords.format(CoordFormat.dd, lat, lon), '4.711370, -74.072630');
  });

  test('La foto guarda la posición redondeada y marcada; el sello lo dice', () async {
    final CapturePipeline pipeline = CapturePipeline(store: state.store, state: state, settings: settings);
    final Project project = state.projectById('general');
    final Fix approx = Fix(latitude: 4.71137, longitude: -74.07263, time: DateTime.utc(2026, 3, 9, 19), accuracy: 2000, approximate: true);
    final PhotoRecord r = pipeline.buildRecord(id: 'a', project: project, originalFile: 'photos/general/a-orig.jpg', stampedFile: 'photos/general/a.jpg', time: DateTime.utc(2026, 3, 9, 19), fix: approx);
    expect(r.approximateLocation, isTrue);
    expect(r.latitude, 4.71);
    expect(r.longitude, -74.07);
    // Se guarda y se lee.
    expect(PhotoRecord.fromJson(r.toJson()).approximateLocation, isTrue);
    final StampTemplate t = StampTemplate.defaultTemplate()
      ..items = <StampItem>{StampItem.coords, StampItem.coords2, StampItem.accuracy}
      ..coordFormat = CoordFormat.dd
      ..coordFormat2 = CoordFormat.ctm12;
    final List<String> es = StampData.fromRecord(r, project: project, spanish: true).lines(t).map((StampLine l) => l.text).toList();
    expect(es.join('\n'), contains('4.71, -74.07 (ubicación aproximada)'));
    expect(es.firstWhere((String l) => RegExp(r'E \d').hasMatch(l)), matches(RegExp(r'E \d+000 N \d+000$')));
    expect(es.join('\n'), contains('± 2000 m'));
    final List<String> en = StampData.fromRecord(r, project: project, spanish: false).lines(t).map((StampLine l) => l.text).toList();
    expect(en.join('\n'), contains('(approximate location)'));
    // Una precisa no lleva la marca ni se redondea.
    final PhotoRecord precise = pipeline.buildRecord(id: 'b', project: project, originalFile: '', stampedFile: '', time: DateTime.utc(2026, 3, 9, 19), fix: Fix(latitude: 4.71137, longitude: -74.07263, time: DateTime.utc(2026, 3, 9, 19), accuracy: 4));
    expect(precise.approximateLocation, isFalse);
    expect(precise.latitude, 4.71137);
    expect(StampData.fromRecord(precise, project: project, spanish: true).lines(t).map((StampLine l) => l.text).join('\n'), isNot(contains('aproximada')));
    // El nombre de archivo con {lat}/{lon} tampoco aparenta precisión.
    expect(buildFileName('{lat}_{lon}', project: 'x', time: DateTime(2026), lat: 4.71, lon: -74.07, n: 1, approximate: true), '4p71_-74p07');
  });

  test('CSV y KML: marcada en el origen de la posición y sin decimales de más', () {
    final Project obra = Project(id: 'p1', name: 'Obra');
    final PhotoRecord p = PhotoRecord(id: 'a', projectId: 'p1', originalFile: '', stampedFile: '', takenAt: DateTime.utc(2026, 3, 9, 19), latitude: 4.71, longitude: -74.07, accuracy: 2000, approximateLocation: true);
    final String csv = Exports.csv(<PhotoRecord>[p], <String, Project>{'p1': obra});
    final List<String> header = csv.split('\n').first.split(';');
    final List<String> row = csv.split('\n')[1].split(';');
    String col(String name) => row[header.indexOf(name)];
    expect(col('latitud'), '4,71');
    expect(col('longitud'), '-74,07');
    expect(col('origen_posicion'), 'GPS (ubicación aproximada)');
    expect(col('ctm12_este'), endsWith('000'));
    expect(col('ctm12_norte'), endsWith('000'));
    expect(col('magna_este'), endsWith('000'));
    expect(col('plus_code'), endsWith('00+'));
    final String kml = Exports.kml(<PhotoRecord>[p], <String, Project>{'p1': obra}, title: 'T');
    expect(kml, contains('<coordinates>-74.07,4.71,'));
    expect(kml, contains('GPS (ubicación aproximada)'));
  });

  group('Séptima ronda', () {
    test('El EXIF dice la precisión y que la posición es aproximada, y el reindexado lo recupera (M4)', () async {
      // Una foto aproximada sellada, cuya ficha se perdió.
      await state.store.writeBytes('photos/general/Obra_x_ap1-orig.jpg', syntheticJpeg(64, 48));
      final String out = await state.store.absolutePath('photos/general/Obra_x_ap1.jpg');
      composeStampedSync(ComposeJob(
        originalPath: await state.store.absolutePath('photos/general/Obra_x_ap1-orig.jpg'),
        outputPath: out,
        quality: 85,
        latitude: 4.71,
        longitude: -74.07,
        accuracy: 2000,
        positionMethod: kExifApproximate,
        takenAt: DateTime.utc(2026, 3, 9, 19),
        utcOffsetMinutes: -300,
      ));
      final StampExif e = readStampExif(File(out).readAsBytesSync());
      expect(e.approximate, isTrue);
      expect(e.accuracy, 2000);
      expect(await state.reindexPhotos(), 1);
      final PhotoRecord r = state.photoById('ap1')!;
      expect(r.approximateLocation, isTrue);
      expect(r.accuracy, 2000);
      // Y se muestra sin precisión falsa.
      expect(Coords.format(CoordFormat.ctm12, r.latitude!, r.longitude!, coarse: r.approximateLocation), matches(RegExp(r'^E \d+000 N \d+000$')));
      expect(Exports.csv(<PhotoRecord>[r], state.projectMap), contains('GPS (ubicación aproximada)'));
      // Una precisa lleva su GPSHPositioningError y ninguna marca; una manual, la suya.
      for (final String method in <String>['', kExifManual]) {
        final String path = '${tmp.path}/m$method.jpg';
        composeStampedSync(ComposeJob(originalPath: await state.store.absolutePath('photos/general/Obra_x_ap1-orig.jpg'), outputPath: path, quality: 85, latitude: 4.711, longitude: -74.0721, accuracy: method.isEmpty ? 3.2 : null, positionMethod: method));
        final StampExif x = readStampExif(File(path).readAsBytesSync());
        expect(x.approximate, isFalse);
        expect(x.manual, method == kExifManual);
        expect(x.accuracy, method.isEmpty ? closeTo(3.2, 0.01) : isNull);
      }
    });

    test('El sello dice a la vez que es aproximada y que la lectura es vieja (M1)', () {
      final PhotoRecord r = PhotoRecord(id: 'a', projectId: 'general', originalFile: 'a-orig.jpg', stampedFile: 'a.jpg', takenAt: DateTime.utc(2026, 3, 9, 19), latitude: 4.71, longitude: -74.07, accuracy: 2000, approximateLocation: true, fixAgeSeconds: 120);
      final StampTemplate t = StampTemplate.defaultTemplate()
        ..items = <StampItem>{StampItem.coords}
        ..coordFormat = CoordFormat.dd;
      final String line = StampData.fromRecord(r, spanish: true).lines(t).single.text;
      expect(line, contains('(ubicación aproximada, lectura de hace 2 min)'));
    });

    test('Con la aproximada: una sola fila de grados y minutos, y distancias en km enteros (M2)', () {
      final List<CoordFormat> coarse = Coords.formatsFor(4.71, -74.07, coarse: true);
      expect(coarse, isNot(contains(CoordFormat.dms)));
      expect(coarse, contains(CoordFormat.ddm));
      expect(Coords.formatName(CoordFormat.ddm, spanish: true, coarse: true), 'Grados y minutos');
      expect(Coords.formatsFor(4.71, -74.07), contains(CoordFormat.dms));
      expect(MapScreen.distanceText(1234), '1.23 km');
      expect(MapScreen.distanceText(1234, approximate: true), '≈ 1 km');
      expect(MapScreen.distanceText(240, approximate: true), '≈ 1 km');
      expect(MapScreen.distanceText(5600, approximate: true), '≈ 6 km');
    });
  });

  group('Comprobación final', () {
    test('Los segundos del EXIF nunca llegan a 60: se acarrean a minutos y grados (O3)', () {
      expect(exifDms(4.6), <int>[4, 36, 0]);
      expect(exifDms(-4.6), <int>[4, 36, 0]);
      expect(exifDms(-74.6), <int>[74, 36, 0]);
      expect(exifDms(1.15), <int>[1, 9, 0]);
      // 59,9999° = 59°59'59,64"; y un pelo menos de 60° redondea a 60°0'0".
      expect(exifDms(59.9999), <int>[59, 59, 596400]);
      expect(exifDms(59.99999999), <int>[60, 0, 0]);
      expect(exifDms(-179.99999999), <int>[180, 0, 0]);
      // Todos los valores de 0,00° a 179,99° (los de una ubicación aproximada
      // y cualquier otro): minutos y segundos en rango y el mismo ángulo.
      for (int i = 0; i < 18000; i++) {
        final double v = i / 100;
        final List<int> p = exifDms(v);
        expect(p[1], inInclusiveRange(0, 59), reason: '$v');
        expect(p[2], inInclusiveRange(0, 599999), reason: '$v');
        expect(p[0] + p[1] / 60 + p[2] / 36000000, closeTo(v, 1e-7), reason: '$v');
      }
      // El texto (sello, hoja, detalle y PDF usan Coords.format) también acarrea.
      expect(Coords.dms(4.6, -74.6), '4°36\'00.0"N 74°36\'00.0"W');
      expect(Coords.dms(59.99999, -59.99999), '60°00\'00.0"N 60°00\'00.0"W');
      expect(Coords.ddm(4.6, -74.6), '4°36.000\'N 74°36.000\'W');
      expect(Coords.format(CoordFormat.dms, 59.9999, -4.6, coarse: true), '60°00\'N 4°36\'W');
      for (final CoordFormat f in <CoordFormat>[CoordFormat.dms, CoordFormat.ddm]) {
        for (final bool coarse in <bool>[false, true]) {
          expect(Coords.format(f, 4.6, -1.15, coarse: coarse), isNot(contains('60')));
        }
      }
    });

    test('El EXIF escrito tiene las etiquetas en orden ascendente y los segundos acarreados (O2, O3)', () async {
      await state.store.writeBytes('photos/general/o-orig.jpg', syntheticJpeg(64, 48));
      final String out = '${tmp.path}/o.jpg';
      composeStampedSync(ComposeJob(
        originalPath: await state.store.absolutePath('photos/general/o-orig.jpg'),
        outputPath: out,
        quality: 85,
        latitude: -4.6,
        longitude: -74.6,
        altitudeMsl: 2600,
        accuracy: 2000,
        positionMethod: kExifApproximate,
        heading: 337,
        headingTrue: true,
        description: 'Obra · Bogotá',
        takenAt: DateTime.utc(2026, 3, 9, 19),
        utcOffsetMinutes: -300,
      ));
      final img.ExifData exif = img.decodeJpgExif(File(out).readAsBytesSync())!;
      void ascending(String name, Iterable<int> keys) {
        final List<int> k = keys.toList();
        expect(k.length, greaterThan(3), reason: name);
        expect(k, List<int>.of(k)..sort(), reason: name);
      }

      ascending('IFD0', exif.imageIfd.keys);
      expect(exif.imageIfd.keys, containsAll(<int>[0x8769, 0x8825]));
      ascending('EXIF', exif.exifIfd.keys);
      ascending('GPS', exif.gpsIfd.keys);
      expect(exif.gpsIfd.keys, containsAll(<int>[0x0007, 0x001B, 0x001D, 0x001F]));
      for (final int tag in <int>[0x0002, 0x0004]) {
        final img.IfdValue v = exif.gpsIfd[tag]!;
        expect(<int>[v.toRational(0).numerator, v.toRational(1).numerator, v.toRational(2).numerator], <int>[tag == 2 ? 4 : 74, 36, 0]);
      }
      final StampExif e = readStampExif(File(out).readAsBytesSync());
      expect(e.latitude, closeTo(-4.6, 1e-9));
      expect(e.longitude, closeTo(-74.6, 1e-9));
      expect(e.approximate, isTrue);
    });

    test('Por distancia, una foto aproximada va en su propio grupo y no «a menos de 100 m» (N2)', () {
      PhotoRecord photo(String id, double lat, {bool approximate = false}) => PhotoRecord(id: id, projectId: 'general', originalFile: '$id-orig.jpg', stampedFile: '$id.jpg', takenAt: DateTime.utc(2026, 3, 9, 19), latitude: lat, longitude: -74.07, accuracy: approximate ? 2000 : 4, approximateLocation: approximate);
      final Fix here = Fix(latitude: 4.71, longitude: -74.07, time: DateTime.utc(2026, 3, 9, 19), accuracy: 4);
      final PhotoRecord near = photo('cerca', 4.7101);
      final PhotoRecord approx = photo('aprox', 4.71, approximate: true);
      final PhotoRecord far = photo('lejos', 4.9);
      final PhotoRecord none = PhotoRecord(id: 'sin', projectId: 'general', originalFile: 's-orig.jpg', stampedFile: 's.jpg', takenAt: DateTime.utc(2026, 3, 9, 19));
      expect(distanceGroup(near, here, spanish: true), 'A menos de 100 m');
      expect(distanceGroup(approx, here, spanish: true), 'Ubicación aproximada (distancia incierta)');
      expect(distanceGroup(approx, here, spanish: false), 'Approximate location (uncertain distance)');
      expect(distanceGroup(far, here, spanish: true), 'A más de 10 km');
      expect(distanceGroup(none, here, spanish: true), 'Sin distancia');
      // Las aproximadas van después de las de distancia fiable (aunque estén
      // «a 0 m») y antes de las que no tienen distancia: un solo grupo.
      final List<PhotoRecord> list = <PhotoRecord>[none, approx, far, near];
      sortByDistance(list, here);
      expect(list.map((PhotoRecord p) => p.id), <String>['cerca', 'lejos', 'aprox', 'sin']);
      // Si la aproximada es la posición propia, ninguna distancia es fiable.
      final Fix coarseHere = Fix(latitude: 4.71, longitude: -74.07, time: DateTime.utc(2026, 3, 9, 19), accuracy: 2000, approximate: true);
      expect(distanceGroup(near, coarseHere, spanish: true), 'Ubicación aproximada (distancia incierta)');
    });

    test('El círculo de una foto aproximada en el mapa es su precisión, de 1 a 10 km (O1)', () {
      expect(MapScreen.approximateRadius(null), 1000);
      expect(MapScreen.approximateRadius(300), 1000);
      expect(MapScreen.approximateRadius(3000), 3000);
      expect(MapScreen.approximateRadius(50000), 10000);
    });
  });
}
