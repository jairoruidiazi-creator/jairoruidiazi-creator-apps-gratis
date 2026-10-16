import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sello/core/app_state.dart';
import 'package:sello/core/exports.dart';
import 'package:sello/core/report.dart';
import 'package:sello/core/storage.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';
import 'package:sello/stamp/composer.dart';

/// JPEG sintético: degradado con un recuadro, opcionalmente con orientación EXIF.
Uint8List syntheticJpeg(int w, int h, {int orientation = 1}) {
  final img.Image im = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgb(x, y, (255 * x / w).round(), (255 * y / h).round(), 90);
    }
  }
  img.fillRect(im, x1: 10, y1: 10, x2: 60, y2: 40, color: img.ColorRgb8(255, 255, 255));
  if (orientation != 1) {
    im.exif.imageIfd.orientation = orientation;
  }
  return img.encodeJpg(im, quality: 90);
}

/// Capa de sello sintética: PNG transparente con una franja roja opaca abajo.
Uint8List syntheticOverlay(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(im, x1: 0, y1: (h * 0.8).round(), x2: w - 1, y2: h - 1, color: img.ColorRgba8(255, 0, 0, 255));
  return img.encodePng(im);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('Composición del sello', () {
    test('Superpone la capa, conserva el tamaño y escribe EXIF con GPS', () async {
      final File orig = File('${tmp.path}/orig.jpg')..writeAsBytesSync(syntheticJpeg(640, 480));
      final String out = '${tmp.path}/out.jpg';
      final ComposeResult r = composeStampedSync(ComposeJob(
        originalPath: orig.path,
        outputPath: out,
        overlayPng: syntheticOverlay(2000, 1500),
        overlayWidth: 2000,
        overlayHeight: 1500,
        quality: 90,
        latitude: 4.711,
        longitude: -74.0721,
        altitude: 2601.4,
        heading: 135.25,
        takenAt: DateTime(2026, 3, 9, 14, 5, 7),
        description: 'Prueba ñandú | GPS: 4.711000, -74.072100 · 135°',
      ));
      expect(r.width, 640);
      expect(r.height, 480);
      final Uint8List bytes = File(out).readAsBytesSync();
      expect(bytes.length, r.bytes);
      final img.Image decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, 640);
      // Abajo (franja roja del sello) el píxel es rojo; arriba sigue el degradado.
      final img.Pixel low = decoded.getPixel(320, 470);
      expect(low.r, greaterThan(200));
      expect(low.g, lessThan(60));
      final img.Pixel high = decoded.getPixel(320, 100);
      expect(high.r, lessThan(200));
      // EXIF
      expect(decoded.exif.imageIfd['Software'].toString(), 'Sello');
      // La descripción va en UTF-8 dentro de la etiqueta ASCII.
      expect(utf8.decode(decoded.exif.imageIfd['ImageDescription']!.toData()), 'Prueba ñandú | GPS: 4.711000, -74.072100 · 135°');
      expect(decoded.exif.exifIfd['DateTimeOriginal'].toString(), '2026:03:09 14:05:07');
      final img.IfdDirectory gps = decoded.exif.gpsIfd;
      expect(gps['GPSLatitudeRef'].toString(), 'N');
      expect(gps['GPSLongitudeRef'].toString(), 'W');
      final img.IfdValue lat = gps['GPSLatitude']!;
      expect(lat.toDouble(0), 4);
      expect(lat.toDouble(1), 42);
      expect(lat.toDouble(2), closeTo(39.6, 0.01));
      final img.IfdValue lon = gps['GPSLongitude']!;
      expect(lon.toDouble(0), 74);
      expect(lon.toDouble(1), 4);
      expect(lon.toDouble(2), closeTo(19.56, 0.01));
      expect(gps['GPSAltitude']!.toDouble(), closeTo(2601.4, 0.01));
      expect(gps['GPSImgDirection']!.toDouble(), closeTo(135.25, 0.01));
      expect(gps['GPSImgDirectionRef'].toString(), 'T');
      expect(jpegSize(bytes)!.width, 640);
      expect(jpegSize(bytes)!.height, 480);
      // Texto con tildes en UTF-8 y XPComment en UTF-16.
      expect(decoded.exif.imageIfd['XPComment'], isNotNull);
      // Copia sin metadatos: misma imagen, sin EXIF.
      final Uint8List clean = stripMetadata(bytes);
      expect(clean.length, lessThan(bytes.length));
      final img.Image cleanImg = img.decodeJpg(clean)!;
      expect(cleanImg.width, 640);
      expect(cleanImg.exif.imageIfd['Software'], isNull);
      expect(cleanImg.exif.gpsIfd['GPSLatitude'], isNull);
      expect(cleanImg.getPixel(320, 470).r, greaterThan(200));
      expect(stripMetadata(Uint8List.fromList(<int>[1, 2, 3])).length, 3);
    });

    test('Aplica la orientación EXIF antes de sellar', () async {
      // Foto guardada "acostada" (640×480) con orientación 6: al verla es 480×640.
      final File orig = File('${tmp.path}/rot.jpg')..writeAsBytesSync(syntheticJpeg(640, 480, orientation: 6));
      expect(CapturePipeline.exifOrientation(orig.readAsBytesSync()), 6);
      final String out = '${tmp.path}/rot-out.jpg';
      final ComposeResult r = composeStampedSync(ComposeJob(
        originalPath: orig.path,
        outputPath: out,
        overlayPng: syntheticOverlay(1500, 2000),
        overlayWidth: 1500,
        overlayHeight: 2000,
        quality: 85,
      ));
      expect(r.width, 480);
      expect(r.height, 640);
      final img.Image decoded = img.decodeJpg(File(out).readAsBytesSync())!;
      expect(decoded.width, 480);
      expect(decoded.exif.imageIfd.orientation ?? 1, 1);
      final img.Pixel low = decoded.getPixel(240, 630);
      expect(low.r, greaterThan(200));
      expect(low.g, lessThan(60));
    });

    test('Sin orientación EXIF devuelve 1', () {
      expect(CapturePipeline.exifOrientation(syntheticJpeg(64, 48)), 1);
      expect(CapturePipeline.exifOrientation(Uint8List.fromList(<int>[1, 2, 3])), 1);
    });
  });

  group('Exportaciones', () {
    final Project obra = Project(id: 'p1', name: 'Obra, Calle 80', fields: <FieldDef>[const FieldDef('lote', 'Lote')]);
    final Map<String, Project> projects = <String, Project>{'p1': obra};
    final List<PhotoRecord> photos = <PhotoRecord>[
      PhotoRecord(id: 'a', projectId: 'p1', originalFile: 'photos/p1/a-orig.jpg', stampedFile: 'photos/p1/a.jpg', takenAt: DateTime(2026, 3, 9, 14, 5, 7), latitude: 4.711, longitude: -74.0721, accuracy: 4.2, altitude: 2601, heading: 135, address: 'Cra 7 "La Séptima", Bogotá', notes: 'Columna\nC-3', tags: <String>['muro', 'fisura'], fields: <String, String>{'lote': '12'}, description: 'desc'),
      PhotoRecord(id: 'b', projectId: 'p1', originalFile: 'photos/p1/b-orig.jpg', stampedFile: 'photos/p1/b.jpg', takenAt: DateTime(2026, 3, 9, 15), notes: 'sin gps'),
    ];

    test('CSV con comillas, campos y formatos de coordenadas', () {
      final String csv = Exports.csv(photos, projects);
      final List<String> lines = const LineSplitter().convert(csv);
      expect(lines.length, 3);
      expect(lines.first, startsWith('id,proyecto,fecha_hora,utc,latitud,longitud'));
      expect(lines.first, endsWith(',lote'));
      expect(lines[1], contains('"Obra, Calle 80"'));
      expect(lines[1], contains('"Cra 7 ""La Séptima"", Bogotá"'));
      expect(lines[1], contains('18NXL0291020787'));
      expect(lines[1], contains('67P7PW6H+C52'));
      expect(lines[1], contains('muro fisura'));
      expect(lines[1], endsWith(',12'));
      expect(lines[2], contains('sin gps'));
      expect(Exports.csv(photos, projects, spanish: false), startsWith('id,project,datetime'));
    });

    test('KML solo con las fotos ubicadas', () {
      final String kml = Exports.kml(photos, projects, title: 'Prueba <x>');
      expect(kml, contains('<name>Prueba &lt;x&gt;</name>'));
      expect(kml, contains('<coordinates>-74.0721000,4.7110000,2601.0</coordinates>'));
      expect('<Placemark>'.allMatches(kml).length, 1);
      expect(kml, contains('<Data name="lote"><value>12</value></Data>'));
      expect(kml, contains('<when>2026-03-09T14:05:07.000Z</when>'));
    });

    test('KMZ y ZIP contienen las fotos y los datos', () async {
      final JsonStore store = JsonStore(root: tmp);
      for (final PhotoRecord p in photos) {
        await store.writeBytes(p.stampedFile, syntheticJpeg(64, 48));
      }
      Future<File?> file(PhotoRecord p) async => File(await store.absolutePath(p.stampedFile));
      final Uint8List kmz = await Exports.kmz(photos, projects, title: 'T', stampedFile: file);
      final Archive a = ZipDecoder().decodeBytes(kmz);
      expect(a.files.map((ArchiveFile f) => f.name), containsAll(<String>['doc.kml', 'files/a.jpg', 'files/b.jpg']));
      final String doc = utf8.decode(a.findFile('doc.kml')!.content as List<int>);
      expect(doc, contains('<img src="files/a.jpg"'));
      final Uint8List zip = await Exports.zip(photos, projects, title: 'T', file: file);
      final Archive z = ZipDecoder().decodeBytes(zip);
      expect(z.files.map((ArchiveFile f) => f.name), containsAll(<String>['fotos/a.jpg', 'fotos/b.jpg', 'datos.csv', 'mapa.kml']));
    });
  });

  group('Informe PDF', () {
    test('Se genera con imagen, tabla y fichas', () async {
      final Project obra = Project(id: 'p1', name: 'Obra Calle 80 🏗️', fields: <FieldDef>[const FieldDef('lote', 'Lote')]);
      final List<PhotoRecord> photos = <PhotoRecord>[
        PhotoRecord(id: 'a', projectId: 'p1', originalFile: 'a-orig.jpg', stampedFile: 'a.jpg', takenAt: DateTime(2026, 3, 9, 14, 5, 7), latitude: 4.711, longitude: -74.0721, accuracy: 4.2, altitude: 2601, heading: 135, address: 'Cra 7 — Bogotá', notes: 'Columna “C-3”', tags: <String>['muro'], fields: <String, String>{'lote': '12'}),
        PhotoRecord(id: 'b', projectId: 'p1', originalFile: 'b-orig.jpg', stampedFile: 'b.jpg', takenAt: DateTime(2026, 3, 10), notes: 'sin gps'),
      ];
      final Uint8List photo = syntheticJpeg(1600, 1200);
      final Uint8List small = await PdfReport.thumbnail(photo, maxWidth: 400);
      expect(img.decodeJpg(small)!.width, 400);
      final Uint8List pdf = await PdfReport.build(
        photos: photos,
        projects: <String, Project>{'p1': obra},
        title: 'Informe de prueba',
        imageOf: (PhotoRecord p) async => p.id == 'a' ? small : null,
        now: DateTime(2026, 3, 11, 9),
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(5000));
      final String text = String.fromCharCodes(pdf);
      expect(text, contains('/Type/Page'));
      // Una imagen incrustada.
      expect(text, contains('/Subtype/Image'));
    });
  });

  group('Estado', () {
    test('Proyectos, plantillas y fotos se guardan y recargan', () async {
      final JsonStore store = JsonStore(root: tmp);
      final AppState st = AppState(store);
      await st.load();
      expect(st.projects.single.id, 'general');
      expect(st.templates.single.id, 'default');
      final Project p = await st.addProject('Obra');
      p.fields.add(const FieldDef('lote', 'Lote'));
      final StampTemplate t = await st.addTemplate('Mía', copyOf: st.templateById('default'));
      t.position = StampPosition.bottomBar;
      p.templateId = t.id;
      await st.saveProjects();
      await store.writeBytes('photos/x/a.jpg', Uint8List.fromList(<int>[1, 2, 3]));
      await st.addPhoto(PhotoRecord(id: 'a', projectId: p.id, originalFile: 'photos/x/a-orig.jpg', stampedFile: 'photos/x/a.jpg', takenAt: DateTime(2026, 1, 1), tags: <String>['t1']));
      expect(st.nextNumber(p.id), 2);
      expect(st.allTags, <String>{'t1'});
      final AppState again = AppState(store);
      await again.load();
      expect(again.projects.length, 2);
      expect(again.projectById(p.id).fields.single.label, 'Lote');
      expect(again.templateForProject(again.projectById(p.id)).position, StampPosition.bottomBar);
      expect(again.photos.single.tags, <String>['t1']);
      // Borrar la plantilla devuelve el proyecto a la estándar; borrar el proyecto mueve las fotos.
      await again.deleteTemplate(t.id);
      expect(again.projectById(p.id).templateId, 'default');
      await again.deleteProject(p.id);
      expect(again.photos.single.projectId, 'general');
      await again.deletePhotos(again.photos.toList());
      expect(again.photos, isEmpty);
      expect(await File(await store.absolutePath('photos/x/a.jpg')).exists(), isFalse);
      // La plantilla estándar y el último proyecto no se borran.
      await again.deleteTemplate('default');
      await again.deleteProject('general');
      expect(again.templates.length, 1);
      expect(again.projects.length, 1);
    });
  });
}
