import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sello/core/app_state.dart';
import 'package:sello/core/exports.dart';
import 'package:sello/core/report.dart';
import 'package:sello/core/storage.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/composer.dart';
import 'package:sello/stamp/stamp_data.dart';
import 'package:sello/stamp/stamp_painter.dart';

import 'support/fakes.dart';

/// Capa de sello sintética: PNG opaco rojo de [w] × [h].
Uint8List redOverlay(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return img.encodePng(im);
}

/// Estructura del EXIF leída byte a byte.
class RawExifLayout {
  const RawExifLayout(this.nextIfd, this.exifSegments);

  /// Desplazamiento del IFD que sigue a IFD0: 0 si no hay IFD1 (miniatura).
  final int nextIfd;

  /// Segmentos APP1 de EXIF en el archivo.
  final int exifSegments;
}

/// Lee a mano, sin el paquete `image`, el EXIF de un JPEG.
RawExifLayout rawExifLayout(Uint8List jpeg) {
  int? nextIfd;
  int segments = 0;
  int i = 2; // Tras SOI.
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final int marker = jpeg[i + 1];
    if (marker == 0xDA) {
      break; // Empieza la imagen.
    }
    final int length = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (marker == 0xE1 && String.fromCharCodes(jpeg.sublist(i + 4, i + 10)) == 'Exif\u0000\u0000') {
      segments++;
      final int t = i + 10; // Cabecera TIFF.
      final bool little = jpeg[t] == 0x49;
      int u16(int o) => little ? jpeg[t + o] | (jpeg[t + o + 1] << 8) : (jpeg[t + o] << 8) | jpeg[t + o + 1];
      int u32(int o) => little ? u16(o) | (u16(o + 2) << 16) : (u16(o) << 16) | u16(o + 2);
      final int ifd0 = u32(4);
      nextIfd ??= u32(ifd0 + 2 + u16(ifd0) * 12);
    }
    i += 2 + length;
  }
  if (nextIfd == null) {
    throw StateError('El JPEG no tiene EXIF');
  }
  return RawExifLayout(nextIfd, segments);
}

/// Texto de un PDF: el archivo tal cual más sus flujos descomprimidos.
String pdfText(Uint8List pdf) {
  final String raw = latin1.decode(pdf);
  final StringBuffer out = StringBuffer(raw);
  int i = 0;
  while (true) {
    final int s = raw.indexOf('stream', i);
    if (s < 0) {
      break;
    }
    int start = s + 6;
    if (start < raw.length && raw[start] == '\r') {
      start++;
    }
    if (start < raw.length && raw[start] == '\n') {
      start++;
    }
    final int e = raw.indexOf('endstream', start);
    if (e < 0) {
      break;
    }
    int end = e;
    while (end > start && (raw[end - 1] == '\n' || raw[end - 1] == '\r')) {
      end--;
    }
    final List<int> bytes = pdf.sublist(start, end);
    try {
      out.write(latin1.decode(zlib.decode(bytes), allowInvalid: true));
    } catch (_) {
      out.write(latin1.decode(bytes, allowInvalid: true));
    }
    i = e + 9;
  }
  return out.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('Composición del sello', () {
    test('Superpone la capa en su lugar y escribe un EXIF nuevo con los datos de Sello', () async {
      final File orig = File('${tmp.path}/orig.jpg')..writeAsBytesSync(syntheticJpeg(640, 480, thumbnail: true, make: 'Acme', cameraLatitude: 51.5));
      // La foto de la cámara traía miniatura (IFD1) y su propio GPS.
      expect(img.decodeJpgExif(orig.readAsBytesSync())!.thumbnailData, isNotNull);
      expect(rawExifLayout(orig.readAsBytesSync()).nextIfd, isNot(0));
      final String out = '${tmp.path}/out.jpg';
      final ComposeResult r = composeStampedSync(ComposeJob(
        originalPath: orig.path,
        outputPath: out,
        quality: 90,
        overlayPng: redOverlay(640, 96),
        overlayLeft: 0,
        overlayTop: 384,
        latitude: 4.711,
        longitude: -74.0721,
        altitudeMsl: 2600.2,
        heading: 135.25,
        takenAt: DateTime.utc(2026, 3, 9, 19, 5, 7),
        utcOffsetMinutes: -300,
        description: 'Prueba ñandú | GPS: 4.711000, -74.072100 · 135°',
      ));
      expect(r.width, 640);
      expect(r.height, 480);
      final Uint8List bytes = File(out).readAsBytesSync();
      expect(bytes.length, r.bytes);
      final img.Image decoded = img.decodeJpg(bytes)!;
      // Abajo (la capa roja) el píxel es rojo; arriba sigue la foto.
      final img.Pixel low = decoded.getPixel(320, 470);
      expect(low.r, greaterThan(200));
      expect(low.g, lessThan(60));
      expect(decoded.getPixel(320, 100).r, lessThan(200));
      final img.ExifData exif = decoded.exif;
      expect(exif.imageIfd['Software'].toString(), 'Sello');
      expect(utf8.decode(exif.imageIfd['ImageDescription']!.toData()).replaceAll('\u0000', ''), 'Prueba ñandú | GPS: 4.711000, -74.072100 · 135°');
      // Hora local con su desfase (M9).
      expect(exif.exifIfd['DateTimeOriginal'].toString(), '2026:03:09 14:05:07');
      expect(exif.exifIfd[0x9011].toString(), '-05:00');
      final img.IfdDirectory gps = exif.gpsIfd;
      expect(gps['GPSLatitudeRef'].toString(), 'N');
      expect(gps['GPSLongitudeRef'].toString(), 'W');
      expect(gps['GPSLatitude']!.toDouble(0), 4);
      expect(gps['GPSLatitude']!.toDouble(1), 42);
      expect(gps['GPSLatitude']!.toDouble(2), closeTo(39.6, 0.01));
      expect(gps['GPSLongitude']!.toDouble(2), closeTo(19.56, 0.01));
      // Altitud sobre el nivel del mar con referencia 0 (encima) (M2).
      expect(gps['GPSAltitude']!.toDouble(), closeTo(2600.2, 0.01));
      expect(gps['GPSAltitudeRef']!.toInt(), 0);
      expect(gps['GPSImgDirection']!.toDouble(), closeTo(135.25, 0.01));
      expect(gps['GPSImgDirectionRef'].toString(), 'T');
      // De la cámara solo quedan los datos de equipo y exposición, sin miniatura ni su GPS (M22).
      expect(exif.imageIfd['Make'].toString(), 'Acme');
      expect(exif.exifIfd['FNumber']!.toDouble(), closeTo(1.8, 0.001));
      final img.ExifData raw = img.decodeJpgExif(bytes)!;
      expect(raw.thumbnailData, isNull);
      expect(raw.directories.containsKey('ifd1'), isFalse);
      // Lo mismo leído byte a byte, sin el paquete que lo escribió: un solo
      // EXIF y IFD0 sin IFD siguiente.
      final RawExifLayout layout = rawExifLayout(bytes);
      expect(layout.nextIfd, 0);
      expect(layout.exifSegments, 1);
      expect(readStampExif(bytes).latitude, closeTo(4.711, 1e-6));
      // Y lo escrito se vuelve a leer para recuperar la ficha.
      final StampExif back = readStampExif(bytes);
      expect(back.takenAt, DateTime.utc(2026, 3, 9, 19, 5, 7));
      expect(back.utcOffsetMinutes, -300);
      expect(back.altitudeMsl, closeTo(2600.2, 0.01));
      expect(back.description, startsWith('Prueba ñandú'));
    });

    test('Rumbo magnético y altitud bajo el nivel del mar llevan su referencia (M1, M2)', () {
      final File orig = File('${tmp.path}/o.jpg')..writeAsBytesSync(syntheticJpeg(64, 48));
      final String out = '${tmp.path}/m.jpg';
      composeStampedSync(ComposeJob(originalPath: orig.path, outputPath: out, quality: 80, latitude: 31.5, longitude: 35.5, altitudeMsl: -415, heading: 10, headingTrue: false));
      final img.IfdDirectory gps = img.decodeJpgExif(File(out).readAsBytesSync())!.gpsIfd;
      expect(gps['GPSImgDirectionRef'].toString(), 'M');
      expect(gps['GPSAltitudeRef']!.toInt(), 1);
      expect(gps['GPSAltitude']!.toDouble(), closeTo(415, 0.01));
      // Sin altitud conocida no se escribe ninguna (nada de 0 m inventados).
      composeStampedSync(ComposeJob(originalPath: orig.path, outputPath: out, quality: 80, latitude: 4.7, longitude: -74.1));
      expect(img.decodeJpgExif(File(out).readAsBytesSync())!.gpsIfd['GPSAltitude'], isNull);
    });

    test('Aplica la orientación EXIF antes de sellar', () {
      // Foto guardada "acostada" (640×480) con orientación 6: al verla es 480×640.
      final File orig = File('${tmp.path}/rot.jpg')..writeAsBytesSync(syntheticJpeg(640, 480, orientation: 6));
      expect(exifOrientation(orig.readAsBytesSync()), 6);
      final StampedPlan plan = planStamped(orig.readAsBytesSync())!;
      expect(plan.width, 480);
      expect(plan.height, 640);
      final String out = '${tmp.path}/rot-out.jpg';
      final ComposeResult r = composeStampedSync(ComposeJob(originalPath: orig.path, outputPath: out, quality: 85, overlayPng: redOverlay(480, 40), overlayTop: 600, expectedWidth: 480, expectedHeight: 640));
      expect(r.width, 480);
      expect(r.height, 640);
      final img.Image decoded = img.decodeJpg(File(out).readAsBytesSync())!;
      expect(decoded.width, 480);
      expect(decoded.exif.imageIfd.orientation ?? 1, 1);
      expect(decoded.getPixel(240, 630).r, greaterThan(200));
    });

    test('Sin orientación EXIF devuelve 1', () {
      expect(exifOrientation(syntheticJpeg(64, 48)), 1);
      expect(exifOrientation(Uint8List.fromList(<int>[1, 2, 3])), 1);
    });

    test('Las fotos muy grandes se sellan reducidas desde el JPEG (G1)', () {
      final Uint8List jpeg = syntheticJpeg(400, 300);
      expect(planStamped(jpeg)!.scale, 1);
      final StampedPlan small = planStamped(jpeg, maxPixels: 40000)!;
      expect(small.scale, 2);
      expect(small.width, 200);
      expect(small.height, 150);
      expect(planStamped(jpeg, maxPixels: 10000)!.scale, 4);
      final File orig = File('${tmp.path}/big.jpg')..writeAsBytesSync(jpeg);
      final ComposeResult r = composeStampedSync(ComposeJob(originalPath: orig.path, outputPath: '${tmp.path}/big-out.jpg', quality: 80, scale: small.scale, expectedWidth: small.width, expectedHeight: small.height));
      expect(r.width, 200);
      expect(r.height, 150);
    });

    test('Compartir sin EXIF quita los datos pero conserva la orientación (M4)', () {
      final Uint8List original = syntheticJpeg(64, 48, orientation: 6, make: 'Acme', cameraLatitude: 4.7);
      final Uint8List clean = stripMetadata(original);
      expect(exifOrientation(clean), 6);
      final img.ExifData exif = img.decodeJpgExif(clean)!;
      expect(exif.imageIfd.orientation, 6);
      expect(exif.imageIfd['Make'], isNull);
      expect(exif.gpsIfd['GPSLatitude'], isNull);
      // Se decodifica (de pie: 48 × 64).
      final img.Image im = img.decodeJpg(clean)!;
      expect(<int>[im.width, im.height]..sort(), <int>[48, 64]);
      // Una foto ya derecha queda sin ningún EXIF.
      final Uint8List upright = stripMetadata(syntheticJpeg(64, 48, make: 'Acme'));
      expect(img.decodeJpgExif(upright)?.imageIfd['Make'], isNull);
      expect(exifOrientation(upright), 1);
      expect(stripMetadata(Uint8List.fromList(<int>[1, 2, 3])).length, 3);
    });
  });

  group('Capa del sello', () {
    test('Se dibuja a tamaño real y solo donde hay algo (M19)', () async {
      final StampTemplate t = StampTemplate.defaultTemplate();
      final StampData d = StampData(time: DateTime(2026, 3, 9, 14, 5), latitude: 4.711, longitude: -74.0721, accuracy: 4, altitude: 2600, heading: 135, projectName: 'Obra', notes: 'Columna C-3');
      final StampOverlay o = (await renderStampOverlay(t, d, width: 4000, height: 3000))!;
      final StampLayout l = StampPainter.layout(const Size(4000, 3000), t, d);
      // El texto mide en píxeles de la foto (1 % del ancho = 40 px): nada se amplía después.
      expect(l.unit, 40);
      expect(o.width, lessThan(4000));
      expect(o.height, lessThan(3000));
      expect(o.left + o.width, lessThanOrEqualTo(4000));
      expect(o.top + o.height, lessThanOrEqualTo(3000));
      final img.Image png = img.decodePng(o.png)!;
      expect(png.width, o.width);
      expect(png.height, o.height);
    });

    test('El logo queda dentro de la foto y fuera del texto, también con el sello arriba (M10)', () async {
      final StampTemplate t = StampTemplate(id: 'x', name: 'x', position: StampPosition.topRight, logoPosition: StampPosition.topRight, items: <StampItem>{StampItem.dateTime, StampItem.coords, StampItem.notes});
      final StampData d = StampData(time: DateTime(2026, 3, 9), latitude: 4.711, longitude: -74.0721, notes: 'Nota');
      final ui.PictureRecorder rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 400, 400), ui.Paint());
      final ui.Image logo = await rec.endRecording().toImage(400, 400);
      for (final StampPosition pos in <StampPosition>[StampPosition.topRight, StampPosition.topLeft, StampPosition.bottomRight, StampPosition.bottomLeft]) {
        t
          ..position = pos
          ..logoPosition = pos;
        final StampLayout l = StampPainter.layout(const Size(1600, 1200), t, d, logo: logo);
        final Rect r = l.logo!;
        expect(r.left, greaterThanOrEqualTo(0), reason: '$pos');
        expect(r.top, greaterThanOrEqualTo(0), reason: '$pos');
        expect(r.right, lessThanOrEqualTo(1600), reason: '$pos');
        expect(r.bottom, lessThanOrEqualTo(1200), reason: '$pos');
        expect(r.overlaps(l.block!), isFalse, reason: '$pos');
      }
    });
  });

  group('Exportaciones', () {
    // Claves internas aleatorias, como las que crea la app.
    final Project obra = Project(id: 'p1', name: 'Obra, Calle 80', fields: <FieldDef>[const FieldDef('mgx3k0001a', 'Lote'), const FieldDef('mgx3k0002b', 'Inspector')]);
    final Map<String, Project> projects = <String, Project>{'p1': obra};
    List<PhotoRecord> photos() => <PhotoRecord>[
          PhotoRecord(
            id: 'a',
            projectId: 'p1',
            originalFile: 'photos/p1/a-orig.jpg',
            stampedFile: 'photos/p1/a.jpg',
            takenAt: DateTime.utc(2026, 3, 9, 19, 5, 7),
            utcOffsetMinutes: -300,
            latitude: 4.711,
            longitude: -74.0721,
            accuracy: 4.2,
            altitude: 2601.5,
            altitudeMsl: 2601.5,
            heading: 135,
            address: 'Cra 7 "La Séptima"; Bogotá',
            notes: 'Columna\nC-3',
            tags: <String>['muro', 'fisura'],
            fields: <String, String>{'mgx3k0001a': '12', 'mgx3k0002b': '=HYPERLINK("http://x")'},
            fieldLabels: <String, String>{'mgx3k0001a': 'Lote', 'mgx3k0002b': 'Inspector'},
            description: 'desc',
          ),
          PhotoRecord(id: 'b', projectId: 'p1', originalFile: 'photos/p1/b-orig.jpg', stampedFile: 'photos/p1/b.jpg', takenAt: DateTime.utc(2026, 3, 9, 20), utcOffsetMinutes: -300, notes: '@ojo sin gps'),
        ];

    test('CSV en español: punto y coma, coma decimal, rótulos y fórmulas neutralizadas (G8, G10)', () {
      final String csv = Exports.csv(photos(), projects);
      final List<String> lines = const LineSplitter().convert(csv);
      expect(lines.first, startsWith('id;proyecto;fecha_hora;zona_horaria;utc;latitud;longitud'));
      // Las columnas de los campos llevan el rótulo, nunca la clave interna.
      expect(lines.first, endsWith(';Lote;Inspector'));
      expect(csv, isNot(contains('mgx3k')));
      final String rowA = csv.split('\nb;').first.split('\na;').last;
      expect(rowA, contains('2026-03-09 14:05:07;-05:00;2026-03-09T19:05:07Z;4,7110000;-74,0721000;4,2;2601,5'));
      expect(rowA, contains('"Cra 7 ""La Séptima""; Bogotá"'));
      expect(rowA, contains('"Columna\nC-3"'));
      expect(rowA, contains('18NXL0291020787'));
      expect(rowA, contains('67P7PW6H+C52'));
      expect(rowA, contains('4881143,15'));
      expect(rowA, contains(';12;'));
      // Una celda que empieza por = no se abre como fórmula.
      expect(rowA, contains('"\'=HYPERLINK(""http://x"")"'));
      expect(lines.last, contains("'@ojo sin gps"));
    });

    test('CSV en inglés: coma y punto decimal; con BOM al compartir', () {
      final String csv = Exports.csv(photos(), projects, spanish: false);
      expect(csv, startsWith('id,project,datetime,utc_offset,utc,latitude,longitude'));
      expect(csv, contains('4.7110000,-74.0721000,4.2,2601.5'));
      final Uint8List bytes = Exports.csvBytes(photos(), projects, spanish: false);
      expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      expect(Exports.neutralizeFormula('-74.07'), '-74.07');
      expect(Exports.neutralizeFormula('+57 300'), "'+57 300");
      expect(Exports.neutralizeFormula('Muro'), 'Muro');
    });

    test('KML con rótulos, nombre corto del marcador y nombres en el idioma (G8, M6)', () {
      final String kml = Exports.kml(photos(), projects, title: 'Prueba <x>');
      expect(kml, contains('<name>Prueba &lt;x&gt;</name>'));
      expect(kml, contains('<coordinates>-74.0721000,4.7110000,2601.5</coordinates>'));
      expect('<Placemark>'.allMatches(kml).length, 1);
      expect(kml, contains('<Data name="Lote"><value>12</value></Data>'));
      expect(kml, isNot(contains('mgx3k')));
      expect(kml, contains('<when>2026-03-09T19:05:07Z</when>'));
      // El marcador se llama como la nota (su primera línea), no como el sello entero.
      expect(kml, contains('<Placemark><name>Columna</name>'));
      expect(kml, contains('<Data name="fecha_hora">'));
      final String en = Exports.kml(photos(), projects, title: 'T', spanish: false);
      expect(en, contains('<Data name="datetime">'));
      expect(en, contains('<Data name="address">'));
      expect(en, isNot(contains('<Data name="direccion">')));
    });

    test('ZIP y KMZ: enlaces que coinciden con los archivos, CSV con BOM y nombres en el idioma (G9, G10, M5, M6)', () async {
      final JsonStore store = JsonStore(root: tmp);
      final List<PhotoRecord> list = photos();
      final Map<String, String> stamped = <String, String>{};
      final Map<String, String> originals = <String, String>{};
      for (final PhotoRecord p in list) {
        await store.writeBytes(p.stampedFile, syntheticJpeg(64, 48));
        await store.writeBytes(p.originalFile, syntheticJpeg(64, 48));
        stamped[p.id] = await store.absolutePath(p.stampedFile);
        originals[p.id] = await store.absolutePath(p.originalFile);
      }
      final List<int> progress = <int>[];
      final String zipPath = '${tmp.path}/o.zip';
      await writeZipFile(zipPath, Exports.zipEntries(list, projects, title: 'T', files: originals), onProgress: (int d, int t) => progress.add(d));
      final Archive z = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
      expect(z.files.map((ArchiveFile f) => f.name), containsAll(<String>['fotos/a-orig.jpg', 'fotos/b-orig.jpg', 'datos.csv', 'mapa.kml']));
      expect(progress.last, 4);
      // El KML del ZIP con originales enlaza los originales que van en el ZIP.
      final String kml = utf8.decode(z.findFile('mapa.kml')!.content);
      expect(kml, contains('<img src="fotos/a-orig.jpg"'));
      // El CSV de adentro también lleva BOM.
      expect(z.findFile('datos.csv')!.content.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      // Las fotos van sin volver a comprimir (un JPEG ya está comprimido).
      expect(z.findFile('fotos/a-orig.jpg')!.compression, CompressionType.none);
      final String enPath = '${tmp.path}/en.zip';
      await writeZipFile(enPath, Exports.zipEntries(list, projects, title: 'T', files: stamped, spanish: false));
      final Archive en = ZipDecoder().decodeBytes(File(enPath).readAsBytesSync());
      expect(en.files.map((ArchiveFile f) => f.name), containsAll(<String>['photos/a.jpg', 'data.csv', 'map.kml']));
      final String kmzPath = '${tmp.path}/t.kmz';
      await writeZipFile(kmzPath, Exports.kmzEntries(list, projects, title: 'T', files: stamped));
      final Archive k = ZipDecoder().decodeBytes(File(kmzPath).readAsBytesSync());
      expect(k.files.map((ArchiveFile f) => f.name), containsAll(<String>['doc.kml', 'files/a.jpg', 'files/b.jpg']));
      expect(utf8.decode(k.findFile('doc.kml')!.content), contains('<img src="files/a.jpg"'));
    });

    test('Cancelar una exportación borra el archivo a medias (G9)', () async {
      final List<ArchiveEntry> entries = <ArchiveEntry>[
        for (int i = 0; i < 200; i++) ArchiveEntry.bytes('x$i.bin', Uint8List(200000)),
      ];
      final ExportCancel cancel = ExportCancel();
      final String path = '${tmp.path}/c.zip';
      final Future<void> f = writeZipFile(path, entries, cancel: cancel, onProgress: (int d, int t) {
        if (d == 3) {
          cancel.cancel();
        }
      });
      await expectLater(f, throwsA(isA<ExportCancelled>()));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('Informe PDF', () {
    test('Orden cronológico, imagen incrustada y rótulos en inglés (M6, M21)', () async {
      final Project obra = Project(id: 'p1', name: 'Obra Calle 80 🏗️', fields: <FieldDef>[const FieldDef('k1', 'Lote')]);
      final List<PhotoRecord> list = <PhotoRecord>[
        PhotoRecord(id: 'b', projectId: 'p1', originalFile: 'b-orig.jpg', stampedFile: 'b.jpg', takenAt: DateTime.utc(2026, 3, 10, 15), notes: 'Segunda'),
        PhotoRecord(id: 'a', projectId: 'p1', originalFile: 'a-orig.jpg', stampedFile: 'a.jpg', takenAt: DateTime.utc(2026, 3, 9, 19, 5, 7), latitude: 4.711, longitude: -74.0721, accuracy: 4.2, altitude: 2601, heading: 135, address: 'Cra 7 — Bogotá', notes: 'Primera', fields: <String, String>{'k1': '12'}, fieldLabels: <String, String>{'k1': 'Lote'}),
      ];
      final Uint8List small = PdfReport.thumbnailSync(syntheticJpeg(1600, 1200), maxWidth: 400);
      expect(img.decodeJpg(small)!.width, 400);
      final Uint8List pdf = await PdfReport.buildInCurrentIsolate(photos: list, projects: <String, Project>{'p1': obra}, title: 'Report', images: <String, Uint8List>{'a': small}, spanish: false, now: DateTime(2026, 3, 11, 9));
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      final String text = pdfText(pdf);
      expect(text, contains('/Subtype/Image'));
      expect(text.indexOf('(Primera'), lessThan(text.indexOf('(Segunda')));
      expect(text, contains('(DMS)'));
      expect(text, isNot(contains('(GMS)')));
      expect(text, contains('(Lote)'));
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
      await store.writeBytes('photos/x/a.jpg', syntheticJpeg(16, 16));
      await st.addPhoto(PhotoRecord(id: 'a', projectId: p.id, originalFile: 'photos/x/a-orig.jpg', stampedFile: 'photos/x/a.jpg', takenAt: DateTime.utc(2026), tags: <String>['t1']));
      expect(st.nextNumber(p.id), 2);
      expect(st.allTags, <String>{'t1'});
      final AppState again = AppState(store);
      await again.load();
      expect(again.projects.length, 2);
      expect(again.projectById(p.id).fields.single.label, 'Lote');
      expect(again.templateForProject(again.projectById(p.id)).position, StampPosition.bottomBar);
      expect(again.photos.single.tags, <String>['t1']);
      await again.deleteTemplate(t.id);
      expect(again.projectById(p.id).templateId, 'default');
      await again.deleteProject(p.id);
      expect(again.photos.single.projectId, 'general');
      await again.deletePhotos(again.photos.toList());
      expect(again.photos, isEmpty);
      expect(await File(await store.absolutePath('photos/x/a.jpg')).exists(), isFalse);
      await again.deleteTemplate('default');
      await again.deleteProject('general');
      expect(again.templates.length, 1);
      expect(again.projects.length, 1);
    });
  });
}
