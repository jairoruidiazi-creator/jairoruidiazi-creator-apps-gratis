import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:clock/clock.dart';

import '../model/models.dart';
import 'app_state.dart';
import 'exports.dart';

/// Resultado de restaurar una copia.
class RestoreSummary {
  const RestoreSummary({required this.photos, required this.projects, required this.templates, required this.files});

  /// Fichas de fotos agregadas.
  final int photos;
  final int projects;
  final int templates;

  /// Archivos (fotos y logos) copiados a la carpeta de la app.
  final int files;
}

/// El archivo no es una copia de Sello.
class NotABackup implements Exception {
  const NotABackup();

  @override
  String toString() => 'NotABackup';
}

/// Copia de seguridad completa: un ZIP con los proyectos, las plantillas,
/// los logos, el índice de fotos y todas las fotos (selladas y originales).
/// Sirve para pasar todo a otro teléfono o guardarlo donde el usuario
/// quiera (la copia automática de Android tiene un tope de 25 MB y no lleva
/// las fotos). Restaurar solo agrega lo que falta: no borra ni reemplaza.
class Backup {
  Backup._();

  static const String manifestName = 'sello-backup.json';
  static const int format = 1;

  /// Entradas del ZIP de la copia.
  static Future<List<ArchiveEntry>> entries(AppState state, {DateTime? now}) async {
    final List<ArchiveEntry> out = <ArchiveEntry>[
      ArchiveEntry.bytes(manifestName, utf8.encode(jsonEncode(<String, dynamic>{'app': 'Sello', 'format': format, 'created': (now ?? clock.now()).toUtc().toIso8601String(), 'photos': state.photos.length}))),
      ArchiveEntry.bytes('projects.json', utf8.encode(jsonEncode(<String, dynamic>{
        'projects': state.projects.map((Project p) => p.toJson()).toList(),
        'templates': state.templates.map((StampTemplate t) => t.toJson()).toList(),
      }))),
      ArchiveEntry.bytes('photos.json', utf8.encode(jsonEncode(<String, dynamic>{'photos': state.photos.map((PhotoRecord p) => p.toJson()).toList()}))),
    ];
    for (final String rel in await state.store.list('logos', recursive: true)) {
      if (!rel.contains('.tmp-')) {
        out.add(ArchiveEntry.file(rel, await state.store.absolutePath(rel)));
      }
    }
    final Set<String> added = <String>{};
    for (final PhotoRecord p in state.photos) {
      for (final String rel in <String>[p.originalFile, p.stampedFile]) {
        if (rel.isEmpty || added.contains(rel)) {
          continue;
        }
        final File f = File(await state.store.absolutePath(rel));
        if (await f.exists()) {
          added.add(rel);
          out.add(ArchiveEntry.file(rel, f.path));
        }
      }
    }
    return out;
  }

  /// Restaura la copia de [zipPath]: copia las fotos y logos que no estén y
  /// agrega los proyectos, plantillas y fichas que falten (por id).
  static Future<RestoreSummary> restore(String zipPath, AppState state) async {
    final String root = (await state.store.root()).path;
    final _Extracted ex = await Isolate.run(() => _extract(zipPath, root));
    if (!ex.valid) {
      throw const NotABackup();
    }
    int projects = 0;
    int templates = 0;
    int photos = 0;
    // Lectura tolerante: una ficha ilegible de la copia se deja fuera (sus
    // fotos igual se copiaron y el reindexado las recupera) en vez de
    // impedir restaurar las demás.
    Iterable<Map<String, dynamic>> maps(Object? list) => list is List ? list.whereType<Map<String, dynamic>>() : const <Map<String, dynamic>>[];
    T? parse<T>(Map<String, dynamic> j, T Function(Map<String, dynamic>) f) {
      try {
        return f(j);
      } catch (_) {
        return null;
      }
    }

    if (ex.projectsJson != null) {
      final Object? decoded = _decode(ex.projectsJson!);
      if (decoded is Map<String, dynamic>) {
        for (final Map<String, dynamic> j in maps(decoded['projects'])) {
          final Project? p = parse(j, Project.fromJson);
          if (p != null && !state.projects.any((Project x) => x.id == p.id)) {
            state.projects.add(p);
            projects++;
          }
        }
        for (final Map<String, dynamic> j in maps(decoded['templates'])) {
          final StampTemplate? tpl = parse(j, StampTemplate.fromJson);
          if (tpl != null && !state.templates.any((StampTemplate x) => x.id == tpl.id)) {
            state.templates.add(tpl);
            templates++;
          }
        }
      }
    }
    if (ex.photosJson != null) {
      final Object? decoded = _decode(ex.photosJson!);
      if (decoded is Map<String, dynamic>) {
        for (final Map<String, dynamic> j in maps(decoded['photos'])) {
          final PhotoRecord? p = parse(j, PhotoRecord.fromJson);
          if (p != null && state.photoById(p.id) == null) {
            if (!state.projects.any((Project x) => x.id == p.projectId)) {
              p.projectId = state.projects.first.id;
            }
            state.photos.add(p);
            photos++;
          }
        }
      }
    }
    photos += await state.reindexPhotos();
    state.photos.sort((PhotoRecord a, PhotoRecord b) => b.takenAt.compareTo(a.takenAt));
    await state.saveProjects();
    await state.savePhotos();
    return RestoreSummary(photos: photos, projects: projects, templates: templates, files: ex.files);
  }
}

Object? _decode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

class _Extracted {
  const _Extracted({required this.valid, this.projectsJson, this.photosJson, this.files = 0});

  final bool valid;
  final String? projectsJson;
  final String? photosJson;
  final int files;
}

/// Solo se aceptan rutas relativas dentro de photos/ y logos/.
bool _safeName(String name) {
  if (name.startsWith('/') || name.contains('..') || name.contains(':')) {
    return false;
  }
  return name.startsWith('photos/') || name.startsWith('logos/');
}

_Extracted _extract(String zipPath, String root) {
  final InputFileStream input = InputFileStream(zipPath);
  try {
    final Archive archive = ZipDecoder().decodeStream(input);
    final ArchiveFile? manifest = archive.findFile(Backup.manifestName);
    if (manifest == null) {
      return const _Extracted(valid: false);
    }
    final Object? m = jsonDecode(utf8.decode(manifest.content, allowMalformed: true));
    if (m is! Map || m['app'] != 'Sello') {
      return const _Extracted(valid: false);
    }
    String? projects;
    String? photos;
    int files = 0;
    for (final ArchiveFile f in archive.files) {
      if (!f.isFile) {
        continue;
      }
      final String name = f.name.replaceAll('\\', '/');
      if (name == 'projects.json') {
        projects = utf8.decode(f.content, allowMalformed: true);
        continue;
      }
      if (name == 'photos.json') {
        photos = utf8.decode(f.content, allowMalformed: true);
        continue;
      }
      if (!_safeName(name)) {
        continue;
      }
      final File dest = File('$root${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}');
      if (dest.existsSync()) {
        continue;
      }
      dest.parent.createSync(recursive: true);
      final String tmp = '${dest.path}.tmp-restore';
      final OutputFileStream out = OutputFileStream(tmp);
      f.writeContent(out);
      out.closeSync();
      File(tmp).renameSync(dest.path);
      files++;
    }
    return _Extracted(valid: true, projectsJson: projects, photosJson: photos, files: files);
  } finally {
    input.closeSync();
  }
}
