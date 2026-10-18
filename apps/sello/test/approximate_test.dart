import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/exports.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/geo/coords.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';
import 'package:sello/stamp/stamp_data.dart';
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
    final PhotoRecord r = pipeline.buildRecord(id: 'a', project: project, originalFile: '', stampedFile: '', time: DateTime.utc(2026, 3, 9, 19), fix: approx);
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
    expect(buildFileName('{lat}_{lon}', project: 'x', time: DateTime(2026), lat: 4.71, lon: -74.07, n: 1, approximate: true), '4_71_-74_07');
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
}
