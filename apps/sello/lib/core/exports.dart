import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import '../geo/coords.dart';
import '../geo/projection.dart';
import '../model/models.dart';

/// Una entrada de un ZIP o KMZ: un archivo del disco (se lee al escribir)
/// o bytes ya armados (CSV, KML).
class ArchiveEntry {
  const ArchiveEntry.file(this.name, String this.path) : bytes = null;

  const ArchiveEntry.bytes(this.name, List<int> this.bytes) : path = null;

  /// Ruta dentro del archivo comprimido.
  final String name;
  final String? path;
  final List<int>? bytes;
}

/// Una celda del CSV. Las numéricas las genera la app; las de texto pueden
/// venir del usuario y se protegen contra fórmulas.
class _Cell {
  const _Cell(this.text, {this.numeric = false});

  final String text;
  final bool numeric;
}

/// Generación local de KML, KMZ, CSV y ZIP con las fotos.
class Exports {
  Exports._();

  static String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  /// Escape para valores de atributos XML (entre comillas dobles): además de
  /// & < >, las comillas. Un rótulo como «Tubería 1/2"» no debe romper el KML.
  static String _attr(String s) => const HtmlEscape(HtmlEscapeMode.attribute).convert(s);

  static final RegExp _plainNumber = RegExp(r'^[-+]?\d+([.,]\d+)?$');

  /// Texto seguro para una hoja de cálculo: una celda que empiece por
  /// = + - @ (o tabulador o retorno) se abriría como fórmula en Excel, Google
  /// Sheets o LibreOffice; se le antepone un apóstrofo. Los números simples
  /// ("-2", "+5,5") se dejan como están.
  static String neutralizeFormula(String s) {
    if (s.isEmpty) {
      return s;
    }
    const String risky = '=+-@\t\r';
    if (risky.contains(s[0]) && !_plainNumber.hasMatch(s.trim())) {
      return "'$s";
    }
    return s;
  }

  static String _csvCell(_Cell c, String separator) {
    final String s = c.numeric ? c.text : neutralizeFormula(c.text);
    if (s.contains(separator) || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Rótulos de los campos de [photos], sin repetir, en el orden en que
  /// aparecen (las exportaciones usan el rótulo, nunca la clave interna).
  static List<String> fieldColumns(List<PhotoRecord> photos, Map<String, Project> projects) {
    final List<String> out = <String>[];
    for (final PhotoRecord p in photos) {
      for (final MapEntry<String, String> e in p.labeledFields(projects[p.projectId])) {
        if (!out.contains(e.key)) {
          out.add(e.key);
        }
      }
    }
    return out;
  }

  /// Valores de los campos de una foto por rótulo (si dos campos comparten
  /// rótulo se juntan con " / ").
  static Map<String, String> fieldsByLabel(PhotoRecord p, Project? project) {
    final Map<String, String> out = <String, String>{};
    for (final MapEntry<String, String> e in p.labeledFields(project)) {
      out[e.key] = out.containsKey(e.key) ? '${out[e.key]} / ${e.value}' : e.value;
    }
    return out;
  }

  /// CSV con una fila por foto. En español usa punto y coma y coma decimal
  /// (lo que espera Excel con la configuración de Colombia); en inglés,
  /// coma y punto decimal. [exists] dice qué archivos (rutas relativas) hay
  /// en el teléfono: el CSV nunca nombra uno que no exista (una foto sin
  /// sellar no tiene copia sellada; sin "Conservar el original", la original
  /// se borra al sellar).
  static String csv(List<PhotoRecord> photos, Map<String, Project> projects, {bool spanish = true, bool Function(String relativePath)? exists}) {
    bool has(String rel) => rel.isNotEmpty && (exists?.call(rel) ?? true);
    final String sep = spanish ? ';' : ',';
    String n(double? v, int decimals) {
      if (v == null || !v.isFinite) {
        return '';
      }
      final String s = v.toStringAsFixed(decimals);
      return spanish ? s.replaceAll('.', ',') : s;
    }

    final List<String> header = spanish
        ? <String>['id', 'proyecto', 'fecha_hora', 'zona_horaria', 'utc', 'latitud', 'longitud', 'precision_m', 'altitud_m', 'altitud_ref', 'rumbo', 'rumbo_ref', 'inclinacion', 'velocidad_ms', 'origen_posicion', 'utm', 'mgrs', 'plus_code', 'ctm12_este', 'ctm12_norte', 'magna_zona', 'magna_este', 'magna_norte', 'direccion', 'notas', 'etiquetas', 'archivo_original', 'archivo_sellado']
        : <String>['id', 'project', 'datetime', 'utc_offset', 'utc', 'latitude', 'longitude', 'accuracy_m', 'altitude_m', 'altitude_ref', 'heading', 'heading_ref', 'tilt', 'speed_ms', 'position_source', 'utm', 'mgrs', 'plus_code', 'ctm12_east', 'ctm12_north', 'magna_zone', 'magna_east', 'magna_north', 'address', 'notes', 'tags', 'original_file', 'stamped_file'];
    final List<String> labels = fieldColumns(photos, projects);
    final StringBuffer b = StringBuffer();
    b.writeln(<_Cell>[for (final String h in <String>[...header, ...labels]) _Cell(h)].map((_Cell c) => _csvCell(c, sep)).join(sep));
    for (final PhotoRecord p in photos) {
      final bool loc = p.hasLocation;
      final bool col = loc && Coords.inColombia(p.latitude!, p.longitude!);
      final ProjectedPointPair? co = col ? ProjectedPointPair.of(p.latitude!, p.longitude!) : null;
      final Map<String, String> fields = fieldsByLabel(p, projects[p.projectId]);
      // Ubicación aproximada: sin decimales que aparenten precisión (grados a
      // 0,01°, proyecciones a 1 km; ver Coords.format) y marcada en origen.
      final bool approx = p.approximateLocation;
      String grid(double v) => approx ? n((v / Coords.coarseGridMeters).round() * Coords.coarseGridMeters, 0) : n(v, 2);
      final List<_Cell> row = <_Cell>[
        _Cell(p.id),
        _Cell(projects[p.projectId]?.name ?? ''),
        _Cell(formatDate(p.wallTime, 'yyyy-MM-dd HH:mm:ss'), numeric: true),
        // "UTC-05:00" y no "-05:00": la hoja de cálculo convertía el desfase
        // en una duración (y "+05:30" en una hora, sin el signo).
        _Cell('UTC${exifUtcOffset(p.utcOffsetMinutes)}', numeric: true),
        _Cell('${formatDate(p.takenAt, 'yyyy-MM-ddTHH:mm:ss')}Z', numeric: true),
        _Cell(loc ? n(p.latitude, approx ? 2 : 7) : '', numeric: true),
        _Cell(loc ? n(p.longitude, approx ? 2 : 7) : '', numeric: true),
        _Cell(n(p.accuracy, 1), numeric: true),
        _Cell(n(p.altitude, 1), numeric: true),
        _Cell(p.altitude == null ? '' : (p.altitudeReference == 'ellipsoid' ? (spanish ? 'elipsoide' : 'ellipsoid') : (spanish ? 'nivel del mar' : 'sea level'))),
        _Cell(n(p.heading, 1), numeric: true),
        _Cell(p.heading == null ? '' : (p.headingTrue ? (spanish ? 'verdadero' : 'true') : (spanish ? 'magnético' : 'magnetic'))),
        _Cell(n(p.pitch, 1), numeric: true),
        _Cell(n(p.speed, 2), numeric: true),
        _Cell(loc ? positionText(p, spanish: spanish) : ''),
        _Cell(loc ? Coords.format(CoordFormat.utm, p.latitude!, p.longitude!, coarse: approx) : ''),
        _Cell(loc ? Coords.format(CoordFormat.mgrs, p.latitude!, p.longitude!, coarse: approx) : ''),
        _Cell(loc ? (approx ? Coords.plusCode(p.latitude!, p.longitude!, length: 6) : Coords.plusCode(p.latitude!, p.longitude!, length: 11)) : ''),
        _Cell(co == null ? '' : grid(co.ctm12Easting), numeric: true),
        _Cell(co == null ? '' : grid(co.ctm12Northing), numeric: true),
        _Cell(co?.magnaZone ?? ''),
        _Cell(co == null ? '' : grid(co.magnaEasting), numeric: true),
        _Cell(co == null ? '' : grid(co.magnaNorthing), numeric: true),
        _Cell(p.address),
        _Cell(p.notes),
        _Cell(p.tags.join(' ')),
        _Cell(has(p.originalFile) ? p.originalFile.split('/').last : ''),
        _Cell(p.status == PhotoStatus.ok && has(p.stampedFile) ? p.stampedFile.split('/').last : ''),
        for (final String l in labels) _Cell(fields[l] ?? ''),
      ];
      b.writeln(row.map((_Cell c) => _csvCell(c, sep)).join(sep));
    }
    return b.toString();
  }

  /// El CSV en UTF-8 con BOM (para que Excel lea bien las tildes), igual
  /// para compartirlo suelto o dentro del ZIP.
  static Uint8List csvBytes(List<PhotoRecord> photos, Map<String, Project> projects, {bool spanish = true, bool Function(String relativePath)? exists}) =>
      Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csv(photos, projects, spanish: spanish, exists: exists))]);

  /// Origen de la posición de una foto, con la marca de ubicación aproximada.
  static String positionText(PhotoRecord p, {required bool spanish}) {
    final String source = positionSourceName(p.positionSource, spanish: spanish);
    if (!p.approximateLocation) {
      return source;
    }
    return spanish ? '$source (ubicación aproximada)' : '$source (approximate location)';
  }

  /// Nombre del origen de la posición, para exportaciones e informes.
  static String positionSourceName(PositionSource s, {required bool spanish}) {
    switch (s) {
      case PositionSource.gps:
        return 'GPS';
      case PositionSource.locked:
        return spanish ? 'fijada' : 'locked';
      case PositionSource.averaged:
        return spanish ? 'promediada' : 'averaged';
      case PositionSource.manual:
        return spanish ? 'manual' : 'manual';
    }
  }

  /// Nombre de un marcador: la nota (primera línea, corta) o la fecha.
  static String placemarkName(PhotoRecord p) {
    final String note = p.notes.trim().split('\n').first.trim();
    if (note.isNotEmpty) {
      return note.length <= 60 ? note : '${note.substring(0, 59)}…';
    }
    return formatDate(p.wallTime, 'dd/MM/yyyy HH:mm');
  }

  /// KML con un marcador por foto; [photoHref] da la ruta relativa de la
  /// imagen dentro del KMZ o del ZIP (o null para no incrustar).
  static String kml(List<PhotoRecord> photos, Map<String, Project> projects, {required String title, String Function(PhotoRecord p)? photoHref, bool spanish = true}) {
    String k(String es, String en) => spanish ? es : en;
    final StringBuffer b = StringBuffer();
    b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    b.writeln('<kml xmlns="http://www.opengis.net/kml/2.2"><Document>');
    b.writeln('<name>${_esc(title)}</name>');
    b.writeln('<Style id="foto"><IconStyle><scale>1.1</scale><Icon><href>http://maps.google.com/mapfiles/kml/shapes/camera.png</href></Icon></IconStyle></Style>');
    final Map<String, List<PhotoRecord>> byProject = <String, List<PhotoRecord>>{};
    for (final PhotoRecord p in photos) {
      byProject.putIfAbsent(p.projectId, () => <PhotoRecord>[]).add(p);
    }
    byProject.forEach((String pid, List<PhotoRecord> list) {
      final Project? project = projects[pid];
      final String pname = project?.name ?? k('Sin proyecto', 'No project');
      b.writeln('<Folder><name>${_esc(pname)}</name>');
      for (final PhotoRecord p in list) {
        if (!p.hasLocation) {
          continue;
        }
        final String href = photoHref?.call(p) ?? '';
        final String when = '${formatDate(p.takenAt, 'yyyy-MM-ddTHH:mm:ss')}Z';
        final List<MapEntry<String, String>> fields = p.labeledFields(project);
        final StringBuffer desc = StringBuffer();
        if (href.isNotEmpty) {
          desc.write('<img src="${_attr(href)}" width="400"/><br/>');
        }
        desc.write('${_esc(formatDate(p.wallTime, 'dd/MM/yyyy HH:mm:ss'))} ${_esc(p.offsetLabel)}<br/>');
        if (p.address.isNotEmpty) {
          desc.write('${_esc(p.address)}<br/>');
        }
        if (p.notes.isNotEmpty) {
          desc.write('${_esc(p.notes)}<br/>');
        }
        for (final MapEntry<String, String> e in fields) {
          desc.write('${_esc(e.key)}: ${_esc(e.value)}<br/>');
        }
        b.writeln('<Placemark><name>${_esc(placemarkName(p))}</name>');
        b.writeln('<styleUrl>#foto</styleUrl>');
        b.writeln('<TimeStamp><when>$when</when></TimeStamp>');
        b.writeln('<description><![CDATA[${desc.toString().replaceAll(']]>', ']]]]><![CDATA[>')}]]></description>');
        b.writeln('<ExtendedData>');
        void data(String key, String v) {
          if (v.isNotEmpty) {
            b.writeln('<Data name="${_attr(key)}"><value>${_esc(v)}</value></Data>');
          }
        }

        data(k('proyecto', 'project'), pname);
        data(k('fecha_hora', 'datetime'), '${formatDate(p.wallTime, 'yyyy-MM-dd HH:mm:ss')} ${p.offsetLabel}');
        final bool approx = p.approximateLocation;
        data('utm', Coords.format(CoordFormat.utm, p.latitude!, p.longitude!, coarse: approx));
        data('mgrs', Coords.format(CoordFormat.mgrs, p.latitude!, p.longitude!, coarse: approx));
        if (Coords.inColombia(p.latitude!, p.longitude!)) {
          data(k('origen_nacional_ctm12', 'ctm12_national_origin'), Coords.format(CoordFormat.ctm12, p.latitude!, p.longitude!, coarse: approx));
          data(k('magna_sirgas_zona', 'magna_sirgas_zone'), Coords.format(CoordFormat.magna, p.latitude!, p.longitude!, coarse: approx));
        }
        data(k('precision_m', 'accuracy_m'), p.accuracy?.toStringAsFixed(1) ?? '');
        data(k('altitud_m', 'altitude_m'), p.altitude?.toStringAsFixed(1) ?? '');
        if (p.altitude != null) {
          data(k('altitud_ref', 'altitude_ref'), p.altitudeReference == 'ellipsoid' ? k('elipsoide', 'ellipsoid') : k('nivel del mar', 'sea level'));
        }
        data(k('rumbo', 'heading'), p.heading == null ? '' : '${p.heading!.toStringAsFixed(1)}${p.headingTrue ? '' : k(' (magnético)', ' (magnetic)')}');
        data(k('origen_posicion', 'position_source'), positionText(p, spanish: spanish));
        data(k('direccion', 'address'), p.address);
        data(k('notas', 'notes'), p.notes);
        data(k('etiquetas', 'tags'), p.tags.join(' '));
        for (final MapEntry<String, String> e in fields) {
          data(e.key, e.value);
        }
        b.writeln('</ExtendedData>');
        final double alt = p.altitudeMsl ?? (p.altitudeReference == 'ellipsoid' ? 0 : (p.altitude ?? 0));
        final int dec = approx ? 2 : 7;
        b.writeln('<Point><coordinates>${p.longitude!.toStringAsFixed(dec)},${p.latitude!.toStringAsFixed(dec)},${alt.toStringAsFixed(1)}</coordinates></Point>');
        b.writeln('</Placemark>');
      }
      b.writeln('</Folder>');
    });
    b.writeln('</Document></kml>');
    return b.toString();
  }

  /// Nombre de una foto dentro de un ZIP o KMZ (sin repetir).
  static String uniqueName(String folder, String fileName, Set<String> used) {
    String name = '$folder/$fileName';
    int i = 2;
    while (used.contains(name)) {
      final int dot = fileName.lastIndexOf('.');
      final String stem = dot > 0 ? fileName.substring(0, dot) : fileName;
      final String ext = dot > 0 ? fileName.substring(dot) : '';
      name = '$folder/${stem}_$i$ext';
      i++;
    }
    used.add(name);
    return name;
  }

  /// Entradas del KMZ: doc.kml y las fotos en files/ (las rutas del KML
  /// coinciden con los nombres dentro del archivo).
  static List<ArchiveEntry> kmzEntries(List<PhotoRecord> photos, Map<String, Project> projects, {required String title, required Map<String, String> files, bool spanish = true}) {
    final Set<String> used = <String>{};
    final Map<String, String> hrefs = <String, String>{};
    final List<ArchiveEntry> entries = <ArchiveEntry>[];
    for (final PhotoRecord p in photos) {
      final String? path = files[p.id];
      if (path == null) {
        continue;
      }
      final String name = uniqueName('files', path.split(Platform.pathSeparator).last.split('/').last, used);
      hrefs[p.id] = name;
      entries.add(ArchiveEntry.file(name, path));
    }
    final String doc = kml(photos, projects, title: title, spanish: spanish, photoHref: (PhotoRecord p) => hrefs[p.id] ?? '');
    return <ArchiveEntry>[ArchiveEntry.bytes('doc.kml', utf8.encode(doc)), ...entries];
  }

  /// Entradas del ZIP: las fotos dadas en [files] (selladas u originales),
  /// el CSV (con BOM) y el KML, que enlaza los mismos nombres que el ZIP.
  static List<ArchiveEntry> zipEntries(List<PhotoRecord> photos, Map<String, Project> projects, {required String title, required Map<String, String> files, bool spanish = true, bool Function(String relativePath)? exists}) {
    final String folder = spanish ? 'fotos' : 'photos';
    final Set<String> used = <String>{};
    final Map<String, String> hrefs = <String, String>{};
    final List<ArchiveEntry> entries = <ArchiveEntry>[];
    for (final PhotoRecord p in photos) {
      final String? path = files[p.id];
      if (path == null) {
        continue;
      }
      final String name = uniqueName(folder, path.split(Platform.pathSeparator).last.split('/').last, used);
      hrefs[p.id] = name;
      entries.add(ArchiveEntry.file(name, path));
    }
    entries.add(ArchiveEntry.bytes(spanish ? 'datos.csv' : 'data.csv', csvBytes(photos, projects, spanish: spanish, exists: exists)));
    entries.add(ArchiveEntry.bytes(spanish ? 'mapa.kml' : 'map.kml', utf8.encode(kml(photos, projects, title: title, spanish: spanish, photoHref: (PhotoRecord p) => hrefs[p.id] ?? ''))));
    return entries;
  }
}

/// Coordenadas colombianas de un punto (Origen Nacional y zona MAGNA).
class ProjectedPointPair {
  const ProjectedPointPair({required this.ctm12Easting, required this.ctm12Northing, required this.magnaZone, required this.magnaEasting, required this.magnaNorthing});

  factory ProjectedPointPair.of(double lat, double lon) {
    final ProjectedPoint ctm = Coords.ctm12(lat, lon);
    final MagnaPoint m = Coords.magna(lat, lon);
    return ProjectedPointPair(ctm12Easting: ctm.easting, ctm12Northing: ctm.northing, magnaZone: m.zoneName, magnaEasting: m.easting, magnaNorthing: m.northing);
  }

  final double ctm12Easting;
  final double ctm12Northing;
  final String magnaZone;
  final double magnaEasting;
  final double magnaNorthing;
}

/// Se puede cancelar una exportación en curso.
class ExportCancel {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get cancelled => _cancelled;

  /// Qué hacer al cancelar (detener el isolate que está trabajando); null
  /// lo quita.
  void whenCancelled(void Function()? f) => _onCancel = f;

  void cancel() {
    _cancelled = true;
    _onCancel?.call();
  }
}

/// La exportación se canceló.
class ExportCancelled implements Exception {
  const ExportCancelled();
}

class _ZipRequest {
  const _ZipRequest(this.port, this.outPath, this.entries);

  final SendPort port;
  final String outPath;
  final List<ArchiveEntry> entries;
}

/// Escribe un ZIP (o KMZ) en [outPath] desde un isolate aparte: los
/// archivos se leen del disco de a uno y se escriben directo al archivo de
/// salida, las fotos sin comprimir (un JPEG ya está comprimido). Ni la
/// interfaz se congela ni el archivo completo pasa por la memoria.
/// [onProgress] recibe cuántas entradas van escritas.
Future<void> writeZipFile(String outPath, List<ArchiveEntry> entries, {void Function(int done, int total)? onProgress, ExportCancel? cancel}) async {
  final ReceivePort port = ReceivePort();
  final Completer<void> done = Completer<void>();
  Isolate? isolate;
  final StreamSubscription<dynamic> sub = port.listen((dynamic msg) {
    if (msg is int) {
      onProgress?.call(msg, entries.length);
    } else if (msg == 'done') {
      if (!done.isCompleted) {
        done.complete();
      }
    } else if (msg is String && msg.startsWith('error:')) {
      if (!done.isCompleted) {
        done.completeError(StateError(msg.substring(6)));
      }
    } else if (msg == null && !done.isCompleted) {
      // El isolate terminó sin avisar que había acabado.
      done.completeError(StateError('La exportación se interrumpió'));
    }
  });
  if (cancel != null) {
    cancel._onCancel = () {
      isolate?.kill(priority: Isolate.immediate);
      if (!done.isCompleted) {
        done.completeError(const ExportCancelled());
      }
    };
  }
  try {
    final Isolate spawned = await Isolate.spawn<_ZipRequest>(_zipMain, _ZipRequest(port.sendPort, outPath, entries), onExit: port.sendPort, errorsAreFatal: true);
    isolate = spawned;
    if (cancel != null && cancel.cancelled) {
      spawned.kill(priority: Isolate.immediate);
      throw const ExportCancelled();
    }
    await done.future;
  } catch (e) {
    try {
      final File f = File(outPath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
    rethrow;
  } finally {
    if (cancel != null) {
      cancel._onCancel = null;
    }
    await sub.cancel();
    port.close();
  }
}

Future<void> _zipMain(_ZipRequest r) async {
  final ZipFileEncoder enc = ZipFileEncoder();
  try {
    enc.create(r.outPath);
    for (int i = 0; i < r.entries.length; i++) {
      final ArchiveEntry e = r.entries[i];
      final String? path = e.path;
      if (path != null) {
        // Sin comprimir (un JPEG ya lo está): se marca la entrada, que es lo
        // que todas las versiones del paquete respetan.
        final InputFileStream input = InputFileStream(path);
        try {
          enc.addArchiveFile(ArchiveFile.stream(e.name, input)..compression = CompressionType.none);
        } finally {
          input.closeSync();
        }
      } else {
        enc.addArchiveFile(ArchiveFile.bytes(e.name, e.bytes!));
      }
      r.port.send(i + 1);
    }
    await enc.close();
    r.port.send('done');
  } catch (err) {
    try {
      await enc.close();
    } catch (_) {}
    r.port.send('error:$err');
  }
}
