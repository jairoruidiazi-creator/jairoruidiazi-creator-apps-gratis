import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../geo/coords.dart';
import '../model/models.dart';
import '../stamp/composer.dart';
import 'exports.dart';

/// Informe PDF de un conjunto de fotos: resumen, tabla y una ficha por foto
/// con su imagen sellada y todos los datos. Generado en el teléfono con el
/// paquete `pdf` (sin servidor) y en un isolate aparte, para no congelar la
/// interfaz.
class PdfReport {
  PdfReport._();

  /// Ancho de las imágenes del informe: la ficha mide 215 × 162 puntos, así
  /// que 640 px dan unos 210 ppp al imprimir y pesan unas cinco veces menos
  /// que la foto a 900 px.
  static const int reportImageWidth = 640;

  /// Arma el informe en un isolate aparte y lo escribe en [outPath]. Ese
  /// isolate lee cada foto de [imagePaths] (por id) y la reduce de a una:
  /// ni las fotos ni el PDF pasan por la memoria de la interfaz, y nada se
  /// copia entre isolates. [onProgress] recibe cuántas fotos van listas.
  static Future<void> writeFile({
    required String outPath,
    required List<PhotoRecord> photos,
    required Map<String, Project> projects,
    required String title,
    required Map<String, String> imagePaths,
    bool spanish = true,
    String author = '',
    DateTime? now,
    void Function(int done, int total)? onProgress,
    ExportCancel? cancel,
  }) async {
    final ReceivePort port = ReceivePort();
    final Completer<void> done = Completer<void>();
    Isolate? isolate;
    final StreamSubscription<dynamic> sub = port.listen((dynamic msg) {
      if (msg is int) {
        onProgress?.call(msg, photos.length);
      } else if (msg == 'done') {
        if (!done.isCompleted) {
          done.complete();
        }
      } else if (msg is String && msg.startsWith('error:')) {
        if (!done.isCompleted) {
          done.completeError(StateError(msg.substring(6)));
        }
      } else if (msg == null && !done.isCompleted) {
        done.completeError(StateError('El informe se interrumpió'));
      }
    });
    cancel?.whenCancelled(() {
      isolate?.kill(priority: Isolate.immediate);
      if (!done.isCompleted) {
        done.completeError(const ExportCancelled());
      }
    });
    try {
      final _PdfRequest request = _PdfRequest(port.sendPort, outPath, photos, projects, title, imagePaths, spanish, author, now ?? clock.now());
      final Isolate spawned = await Isolate.spawn<_PdfRequest>(_pdfMain, request, onExit: port.sendPort, errorsAreFatal: true);
      isolate = spawned;
      if (cancel != null && cancel.cancelled) {
        spawned.kill(priority: Isolate.immediate);
        throw const ExportCancelled();
      }
      await done.future;
    } catch (_) {
      for (final String path in <String>[outPath, '$outPath.tmp-pdf']) {
        try {
          final File f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
      rethrow;
    } finally {
      cancel?.whenCancelled(null);
      await sub.cancel();
      port.close();
    }
  }

  /// Reduce un JPEG a [maxWidth] px para incrustarlo en el PDF. Decodifica
  /// directamente a tamaño reducido (1/2, 1/4 u 1/8) cuando se puede.
  static Future<Uint8List> thumbnail(Uint8List bytes, {int maxWidth = 900, int quality = 78}) {
    return Isolate.run(() => thumbnailSync(bytes, maxWidth: maxWidth, quality: quality));
  }

  static Uint8List thumbnailSync(Uint8List bytes, {int maxWidth = 900, int quality = 78}) {
    final JpegDims? dims = jpegSize(bytes);
    int scale = 1;
    if (dims != null) {
      final int longest = dims.width > dims.height ? dims.width : dims.height;
      while (scale < 8 && longest / (scale * 2) >= maxWidth) {
        scale *= 2;
      }
    }
    final img.Image? im = img.decodeJpg(bytes, scale: scale);
    if (im == null) {
      return bytes;
    }
    final img.Image baked = (im.exif.imageIfd.orientation ?? 1) == 1 ? im : img.bakeOrientation(im);
    final img.Image small = baked.width > maxWidth ? img.copyResize(baked, width: maxWidth, interpolation: img.Interpolation.average) : baked;
    return img.encodeJpg(small, quality: quality, chroma: img.JpegChroma.yuv420);
  }

  /// Construye el PDF en el isolate actual (lo usan [writeFile] y las
  /// pruebas). [images] tiene las miniaturas por id de foto (las que falten
  /// se muestran como "Sin imagen"); [fileNames], el archivo de cada imagen,
  /// y sin él la ficha no nombra ningún archivo: nunca uno que no exista.
  static Future<Uint8List> buildInCurrentIsolate({
    required List<PhotoRecord> photos,
    required Map<String, Project> projects,
    required String title,
    required Map<String, Uint8List> images,
    Map<String, String> fileNames = const <String, String>{},
    bool spanish = true,
    String author = '',
    required DateTime now,
  }) {
    // En orden cronológico, como se recorre una obra.
    final List<PhotoRecord> list = List<PhotoRecord>.of(photos)..sort((PhotoRecord a, PhotoRecord b) => a.takenAt.compareTo(b.takenAt));
    final List<pw.Widget> blocks = <pw.Widget>[];
    String s(String es, String en) => _clean(spanish ? es : en);
    const pw.TextStyle small = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800);
    const pw.TextStyle label = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600);
    const pw.TextStyle h1 = pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1B4332));
    const pw.TextStyle h2 = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);

    final List<PhotoRecord> located = list.where((PhotoRecord p) => p.hasLocation).toList();
    final DateTime? first = list.isEmpty ? null : list.first.wallTime;
    final DateTime? last = list.isEmpty ? null : list.last.wallTime;
    final Set<String> projectNames = <String>{for (final PhotoRecord p in list) projects[p.projectId]?.name ?? ''}..remove('');

    // Portada / resumen
    blocks.add(pw.Text(_clean(title), style: h1));
    blocks.add(pw.SizedBox(height: 4));
    blocks.add(pw.Text(
      '${s('Informe fotográfico', 'Photo report')} · ${list.length} ${s('fotos', 'photos')}'
      '${first != null && last != null ? ' · ${formatDate(first, 'dd/MM/yyyy')}${_sameDay(first, last) ? '' : ' - ${formatDate(last, 'dd/MM/yyyy')}'}' : ''}'
      '${projectNames.isNotEmpty ? ' · ${s('Proyecto', 'Project')}: ${_clean(projectNames.join(', '))}' : ''}',
      style: small,
    ));
    blocks.add(pw.Text('${s('Generado', 'Generated')} ${formatDate(now, 'dd/MM/yyyy HH:mm')}${author.isNotEmpty ? ' · ${_clean(author)}' : ''} · Sello', style: label));
    blocks.add(pw.SizedBox(height: 10));

    // Tabla índice
    if (list.isNotEmpty) {
      blocks.add(pw.TableHelper.fromTextArray(
        headerStyle: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF40916C)),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        columnWidths: <int, pw.TableColumnWidth>{0: const pw.FixedColumnWidth(22), 1: const pw.FixedColumnWidth(78), 2: const pw.FixedColumnWidth(110), 3: const pw.FlexColumnWidth(2), 4: const pw.FlexColumnWidth(3)},
        headers: <String>['#', s('Fecha y hora', 'Date and time'), s('Coordenadas', 'Coordinates'), s('Proyecto', 'Project'), s('Notas', 'Notes')],
        data: <List<String>>[
          for (int i = 0; i < list.length; i++)
            <String>[
              '${i + 1}',
              formatDate(list[i].wallTime, 'dd/MM/yyyy HH:mm'),
              list[i].hasLocation ? '${Coords.dd(list[i].latitude!, list[i].longitude!, decimals: list[i].approximateLocation ? 2 : 5)}${list[i].approximateLocation ? s(' (aprox.)', ' (approx.)') : ''}' : s('Sin GPS', 'No GPS'),
              _clean(projects[list[i].projectId]?.name ?? ''),
              _clean(_truncate(list[i].notes.isNotEmpty ? list[i].notes : list[i].description, 70)),
            ],
        ],
      ));
      blocks.add(pw.SizedBox(height: 14));
    }

    // Fichas (varias por página: imagen a la izquierda y datos a la derecha)
    for (int i = 0; i < list.length; i++) {
      final PhotoRecord p = list[i];
      final Uint8List? bytes = images[p.id];
      final Project? project = projects[p.projectId];
      final List<List<String>> rows = <List<String>>[
        <String>[s('Fecha y hora', 'Date and time'), '${formatDate(p.wallTime, 'dd/MM/yyyy HH:mm:ss')} ${p.offsetLabel}'],
        if (p.hasLocation) ...<List<String>>[
          <String>[s('Grados decimales', 'Decimal degrees'), Coords.format(CoordFormat.dd, p.latitude!, p.longitude!, coarse: p.approximateLocation)],
          <String>[s('GMS', 'DMS'), Coords.format(CoordFormat.dms, p.latitude!, p.longitude!, coarse: p.approximateLocation)],
          <String>['UTM', Coords.format(CoordFormat.utm, p.latitude!, p.longitude!, coarse: p.approximateLocation)],
          <String>['MGRS', Coords.format(CoordFormat.mgrs, p.latitude!, p.longitude!, coarse: p.approximateLocation)],
          <String>['Plus Code', p.approximateLocation ? Coords.plusCode(p.latitude!, p.longitude!, length: 6) : Coords.plusCode(p.latitude!, p.longitude!, length: 11)],
          if (Coords.inColombia(p.latitude!, p.longitude!)) ...<List<String>>[
            <String>[s('Origen Nacional (CTM12)', 'National origin (CTM12)'), Coords.format(CoordFormat.ctm12, p.latitude!, p.longitude!, coarse: p.approximateLocation)],
            <String>['MAGNA-SIRGAS', Coords.format(CoordFormat.magna, p.latitude!, p.longitude!, coarse: p.approximateLocation)],
          ],
          if (p.positionSource == PositionSource.manual) <String>[s('Posición', 'Position'), s('escrita a mano', 'entered by hand')],
          if (p.approximateLocation) <String>[s('Posición', 'Position'), s('ubicación aproximada (el teléfono no dio la precisa; puede estar a kilómetros)', 'approximate location (the phone did not give the precise one; it may be kilometres off)')],
          if (p.accuracy != null) <String>[s('Precisión', 'Accuracy'), '± ${p.accuracy!.toStringAsFixed(1)} m${p.averagedSamples > 1 ? ' (${s('promedio de', 'average of')} ${p.averagedSamples})' : ''}'],
          if (p.altitude != null) <String>[s('Altitud', 'Altitude'), '${p.altitude!.toStringAsFixed(1)} m ${p.altitudeReference == 'ellipsoid' ? s('(elipsoide)', '(ellipsoid)') : s('s. n. m.', 'MSL')}'],
        ] else
          <String>[s('Ubicación', 'Location'), s('Sin señal GPS', 'No GPS fix')],
        if (p.heading != null)
          <String>[
            s('Rumbo', 'Heading'),
            '${p.heading!.toStringAsFixed(0)}° ${Coords.cardinal(p.heading!, spanish: spanish)}${p.headingTrue ? '' : s(' (magnético)', ' (magnetic)')} · ${s('fachada', 'facade')} ${Coords.facade(p.heading!, spanish: spanish)}${p.pitch != null ? ' · ${s('incl.', 'tilt')} ${p.pitch!.toStringAsFixed(0)}°' : ''}',
          ],
        if (p.address.isNotEmpty) <String>[s('Dirección', 'Address'), p.address],
        if (project != null) <String>[s('Proyecto', 'Project'), project.name],
        for (final MapEntry<String, String> e in p.labeledFields(project)) <String>[e.key, e.value],
        if (p.notes.isNotEmpty) <String>[s('Notas', 'Notes'), p.notes],
        if (p.tags.isNotEmpty) <String>[s('Etiquetas', 'Tags'), p.tags.map((String x) => '#$x').join(' ')],
        if (fileNames[p.id] != null) <String>[s('Archivo', 'File'), fileNames[p.id]!],
      ];
      blocks.add(pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.5))),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Container(
              width: 215,
              height: 162,
              alignment: pw.Alignment.topLeft,
              child: bytes == null
                  ? pw.Container(color: PdfColors.grey200, alignment: pw.Alignment.center, child: pw.Text(s('Sin imagen', 'No image'), style: label))
                  : pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text('${i + 1}. ${_clean(p.notes.isNotEmpty ? _truncate(p.notes, 60) : formatDate(p.wallTime, 'dd/MM/yyyy HH:mm'))}', style: h2),
                  pw.SizedBox(height: 3),
                  for (final List<String> r in rows)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 1.5),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: <pw.Widget>[
                          pw.SizedBox(width: 92, child: pw.Text(_clean(r[0]), style: label)),
                          pw.Expanded(child: pw.Text(_clean(r[1]), style: small)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ));
    }

    final pw.Document doc = pw.Document(title: _clean(title), author: author.isEmpty ? 'Sello' : _clean(author), creator: 'Sello', subject: s('Informe fotográfico con sello GPS', 'GPS-stamped photo report'));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      maxPages: 2000,
      footer: (pw.Context ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text('${_clean(title)} · ${located.length}/${list.length} ${s('con GPS', 'with GPS')}', style: label),
          pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: label),
        ],
      ),
      build: (pw.Context ctx) => blocks,
    ));
    return doc.save();
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static Future<void> _pdfMain(_PdfRequest r) async {
    try {
      final Map<String, Uint8List> images = <String, Uint8List>{};
      final Map<String, String> names = <String, String>{};
      int i = 0;
      for (final PhotoRecord p in r.photos) {
        final String? path = r.imagePaths[p.id];
        if (path != null) {
          try {
            images[p.id] = thumbnailSync(File(path).readAsBytesSync(), maxWidth: reportImageWidth, quality: 72);
            names[p.id] = path.split(Platform.pathSeparator).last.split('/').last;
          } catch (_) {
            // Sin imagen: la ficha lo dice y no nombra el archivo.
          }
        }
        i++;
        r.port.send(i);
      }
      final Uint8List pdf = await buildInCurrentIsolate(photos: r.photos, projects: r.projects, title: r.title, images: images, fileNames: names, spanish: r.spanish, author: r.author, now: r.now);
      final File tmp = File('${r.outPath}.tmp-pdf');
      tmp.writeAsBytesSync(pdf, flush: true);
      tmp.renameSync(r.outPath);
      r.port.send('done');
    } catch (err) {
      r.port.send('error:$err');
    }
  }

  static String _truncate(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

  /// Las fuentes incorporadas del PDF (Helvetica) solo cubren Latin-1: se
  /// sustituyen los signos frecuentes fuera de ese rango y se quitan emojis.
  static String _clean(String text) {
    const Map<int, String> map = <int, String>{0x2014: '-', 0x2013: '-', 0x2018: '\'', 0x2019: '\'', 0x201C: '"', 0x201D: '"', 0x2026: '...', 0x2022: '-', 0x2212: '-'};
    final StringBuffer b = StringBuffer();
    for (final int r in text.runes) {
      if (r <= 0xFF) {
        b.writeCharCode(r);
      } else if (map.containsKey(r)) {
        b.write(map[r]);
      }
    }
    return b.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }
}

class _PdfRequest {
  const _PdfRequest(this.port, this.outPath, this.photos, this.projects, this.title, this.imagePaths, this.spanish, this.author, this.now);

  final SendPort port;
  final String outPath;
  final List<PhotoRecord> photos;
  final Map<String, Project> projects;
  final String title;
  final Map<String, String> imagePaths;
  final bool spanish;
  final String author;
  final DateTime now;
}
