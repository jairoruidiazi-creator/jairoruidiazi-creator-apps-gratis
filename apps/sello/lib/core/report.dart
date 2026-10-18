import 'dart:isolate';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../geo/coords.dart';
import '../model/models.dart';
import '../stamp/composer.dart';

/// Informe PDF de un conjunto de fotos: resumen, tabla y una ficha por foto
/// con su imagen sellada y todos los datos. Generado en el teléfono con el
/// paquete `pdf` (sin servidor) y en un isolate aparte, para no congelar la
/// interfaz.
class PdfReport {
  PdfReport._();

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

  /// Construye el PDF en un isolate. [images] tiene las miniaturas por id de
  /// foto (las que falten se muestran como "Sin imagen").
  static Future<Uint8List> build({
    required List<PhotoRecord> photos,
    required Map<String, Project> projects,
    required String title,
    required Map<String, Uint8List> images,
    bool spanish = true,
    String author = '',
    DateTime? now,
  }) {
    final DateTime when = now ?? clock.now();
    return Isolate.run(() => buildInCurrentIsolate(photos: photos, projects: projects, title: title, images: images, spanish: spanish, author: author, now: when));
  }

  /// Construye el PDF en el isolate actual (lo usan [build] y las pruebas).
  static Future<Uint8List> buildInCurrentIsolate({
    required List<PhotoRecord> photos,
    required Map<String, Project> projects,
    required String title,
    required Map<String, Uint8List> images,
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
              list[i].hasLocation ? Coords.dd(list[i].latitude!, list[i].longitude!, decimals: 5) : s('Sin GPS', 'No GPS'),
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
          <String>[s('Grados decimales', 'Decimal degrees'), Coords.dd(p.latitude!, p.longitude!)],
          <String>[s('GMS', 'DMS'), Coords.dms(p.latitude!, p.longitude!)],
          <String>['UTM', Coords.utm(p.latitude!, p.longitude!)],
          <String>['MGRS', Coords.mgrs(p.latitude!, p.longitude!)],
          <String>['Plus Code', Coords.plusCode(p.latitude!, p.longitude!, length: 11)],
          if (Coords.inColombia(p.latitude!, p.longitude!)) ...<List<String>>[
            <String>[s('Origen Nacional (CTM12)', 'National origin (CTM12)'), Coords.ctm12Text(p.latitude!, p.longitude!)],
            <String>['MAGNA-SIRGAS', Coords.magnaText(p.latitude!, p.longitude!)],
          ],
          if (p.positionSource == PositionSource.manual) <String>[s('Posición', 'Position'), s('escrita a mano', 'entered by hand')],
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
        <String>[s('Archivo', 'File'), p.stampedFile.split('/').last],
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
