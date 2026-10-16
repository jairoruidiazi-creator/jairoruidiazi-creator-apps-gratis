import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../geo/coords.dart';
import '../model/models.dart';

/// Generación local de KML, KMZ, CSV y ZIP con las fotos.
class Exports {
  Exports._();

  static String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  static String _csvCell(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// CSV con una fila por foto.
  static String csv(List<PhotoRecord> photos, Map<String, Project> projects, {bool spanish = true}) {
    final Set<String> fieldKeys = <String>{};
    for (final PhotoRecord p in photos) {
      fieldKeys.addAll(p.fields.keys);
    }
    final List<String> header = spanish
        ? <String>['id', 'proyecto', 'fecha_hora', 'utc', 'latitud', 'longitud', 'precision_m', 'altitud_m', 'altitud_ref', 'rumbo', 'inclinacion', 'velocidad_ms', 'utm', 'mgrs', 'plus_code', 'ctm12_este', 'ctm12_norte', 'magna_zona', 'magna_este', 'magna_norte', 'direccion', 'notas', 'etiquetas', 'archivo_original', 'archivo_sellado']
        : <String>['id', 'project', 'datetime', 'utc', 'latitude', 'longitude', 'accuracy_m', 'altitude_m', 'altitude_ref', 'heading', 'tilt', 'speed_ms', 'utm', 'mgrs', 'plus_code', 'ctm12_east', 'ctm12_north', 'magna_zone', 'magna_east', 'magna_north', 'address', 'notes', 'tags', 'original_file', 'stamped_file'];
    final List<String> keys = fieldKeys.toList()..sort();
    final StringBuffer b = StringBuffer();
    b.writeln(<String>[...header, ...keys].map(_csvCell).join(','));
    for (final PhotoRecord p in photos) {
      final bool loc = p.hasLocation;
      final bool col = loc && Coords.inColombia(p.latitude!, p.longitude!);
      final List<String> row = <String>[
        p.id,
        projects[p.projectId]?.name ?? '',
        p.takenAt.toIso8601String(),
        p.takenAt.toUtc().toIso8601String(),
        loc ? p.latitude!.toStringAsFixed(7) : '',
        loc ? p.longitude!.toStringAsFixed(7) : '',
        p.accuracy?.toStringAsFixed(1) ?? '',
        p.altitude?.toStringAsFixed(1) ?? '',
        p.altitude == null ? '' : (p.altitudeReference == 'ellipsoid' ? 'elipsoide' : 'nivel del mar'),
        p.heading?.toStringAsFixed(1) ?? '',
        p.pitch?.toStringAsFixed(1) ?? '',
        p.speed?.toStringAsFixed(2) ?? '',
        loc ? Coords.utm(p.latitude!, p.longitude!) : '',
        loc ? Coords.mgrs(p.latitude!, p.longitude!) : '',
        loc ? Coords.plusCode(p.latitude!, p.longitude!, length: 11) : '',
        loc && col ? Coords.ctm12(p.latitude!, p.longitude!).easting.toStringAsFixed(2) : '',
        loc && col ? Coords.ctm12(p.latitude!, p.longitude!).northing.toStringAsFixed(2) : '',
        loc && col ? Coords.magna(p.latitude!, p.longitude!).zoneName : '',
        loc && col ? Coords.magna(p.latitude!, p.longitude!).easting.toStringAsFixed(2) : '',
        loc && col ? Coords.magna(p.latitude!, p.longitude!).northing.toStringAsFixed(2) : '',
        p.address,
        p.notes,
        p.tags.join(' '),
        p.originalFile.split('/').last,
        p.stampedFile.split('/').last,
        for (final String k in keys) p.fields[k] ?? '',
      ];
      b.writeln(row.map(_csvCell).join(','));
    }
    return b.toString();
  }

  /// KML con un marcador por foto; [photoHref] da la ruta relativa de la
  /// imagen dentro del KMZ (o null para no incrustar).
  static String kml(List<PhotoRecord> photos, Map<String, Project> projects, {required String title, String Function(PhotoRecord p)? photoHref, bool spanish = true}) {
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
      final String pname = projects[pid]?.name ?? (spanish ? 'Sin proyecto' : 'No project');
      b.writeln('<Folder><name>${_esc(pname)}</name>');
      for (final PhotoRecord p in list) {
        if (!p.hasLocation) {
          continue;
        }
        final String href = photoHref?.call(p) ?? '';
        final String when = p.takenAt.toUtc().toIso8601String();
        final StringBuffer desc = StringBuffer();
        if (href.isNotEmpty) {
          desc.write('<img src="$href" width="400"/><br/>');
        }
        desc.write('${_esc(formatDate(p.takenAt, 'dd/MM/yyyy HH:mm:ss'))} ${_esc(utcOffsetLabel(p.takenAt))}<br/>');
        if (p.address.isNotEmpty) {
          desc.write('${_esc(p.address)}<br/>');
        }
        if (p.notes.isNotEmpty) {
          desc.write('${_esc(p.notes)}<br/>');
        }
        b.writeln('<Placemark><name>${_esc(p.description.isNotEmpty ? p.description : (p.notes.isNotEmpty ? p.notes : formatDate(p.takenAt, 'dd/MM HH:mm')))}</name>');
        b.writeln('<styleUrl>#foto</styleUrl>');
        b.writeln('<TimeStamp><when>$when</when></TimeStamp>');
        b.writeln('<description><![CDATA[$desc]]></description>');
        b.writeln('<ExtendedData>');
        void data(String k, String v) {
          if (v.isNotEmpty) {
            b.writeln('<Data name="${_esc(k)}"><value>${_esc(v)}</value></Data>');
          }
        }

        data('proyecto', pname);
        data('utm', Coords.utm(p.latitude!, p.longitude!));
        data('mgrs', Coords.mgrs(p.latitude!, p.longitude!));
        if (Coords.inColombia(p.latitude!, p.longitude!)) {
          data('origen_nacional_ctm12', Coords.ctm12Text(p.latitude!, p.longitude!));
          data('magna_sirgas_zona', Coords.magnaText(p.latitude!, p.longitude!));
        }
        data('precision_m', p.accuracy?.toStringAsFixed(1) ?? '');
        data('altitud_m', p.altitude?.toStringAsFixed(1) ?? '');
        data('rumbo', p.heading?.toStringAsFixed(1) ?? '');
        data('direccion', p.address);
        data('notas', p.notes);
        data('etiquetas', p.tags.join(' '));
        p.fields.forEach(data);
        b.writeln('</ExtendedData>');
        b.writeln('<Point><coordinates>${p.longitude!.toStringAsFixed(7)},${p.latitude!.toStringAsFixed(7)},${(p.altitude ?? 0).toStringAsFixed(1)}</coordinates></Point>');
        b.writeln('</Placemark>');
      }
      b.writeln('</Folder>');
    });
    b.writeln('</Document></kml>');
    return b.toString();
  }

  /// KMZ: doc.kml más las fotos selladas en la carpeta files/.
  static Future<Uint8List> kmz(List<PhotoRecord> photos, Map<String, Project> projects, {required String title, required Future<File?> Function(PhotoRecord p) stampedFile, bool spanish = true}) async {
    final Archive archive = Archive();
    final Map<String, String> hrefs = <String, String>{};
    for (final PhotoRecord p in photos) {
      final File? f = await stampedFile(p);
      if (f != null && await f.exists()) {
        final String name = 'files/${f.uri.pathSegments.last}';
        hrefs[p.id] = name;
        final Uint8List bytes = await f.readAsBytes();
        archive.addFile(ArchiveFile.bytes(name, bytes));
      }
    }
    final String doc = kml(photos, projects, title: title, spanish: spanish, photoHref: (PhotoRecord p) => hrefs[p.id] ?? '');
    final List<int> docBytes = utf8.encode(doc);
    archive.addFile(ArchiveFile.bytes('doc.kml', docBytes));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// ZIP con fotos (selladas u originales), el CSV y el KML.
  static Future<Uint8List> zip(List<PhotoRecord> photos, Map<String, Project> projects, {required String title, required Future<File?> Function(PhotoRecord p) file, bool spanish = true}) async {
    final Archive archive = Archive();
    for (final PhotoRecord p in photos) {
      final File? f = await file(p);
      if (f != null && await f.exists()) {
        final Uint8List bytes = await f.readAsBytes();
        archive.addFile(ArchiveFile.bytes('fotos/${f.uri.pathSegments.last}', bytes));
      }
    }
    final List<int> csvBytes = utf8.encode(csv(photos, projects, spanish: spanish));
    archive.addFile(ArchiveFile.bytes('datos.csv', csvBytes));
    final List<int> kmlBytes = utf8.encode(kml(photos, projects, title: title, spanish: spanish, photoHref: (PhotoRecord p) => 'fotos/${p.stampedFile.split('/').last}'));
    archive.addFile(ArchiveFile.bytes('mapa.kml', kmlBytes));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
