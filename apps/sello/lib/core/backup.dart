import 'dart:async';
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
  ///
  /// Se descomprime en un isolate que avisa el avance a [onProgress]
  /// (archivos revisados de los que trae la copia). Si [cancel] se activa,
  /// el isolate se detiene entre un archivo y otro, borra los que alcanzó a
  /// copiar y no se agrega nada al índice: lanza [ExportCancelled].
  static Future<RestoreSummary> restore(String zipPath, AppState state, {void Function(int done, int total)? onProgress, ExportCancel? cancel}) async {
    final String root = (await state.store.root()).path;
    final _Extracted ex = await _extractInIsolate(zipPath, root, onProgress: onProgress, cancel: cancel);
    if (ex.cancelled) {
      throw const ExportCancelled();
    }
    if (!ex.valid) {
      throw const NotABackup();
    }
    // Si algo falla al agregar las fichas (por ejemplo, el disco se llena al
    // guardar el índice), se deshace todo: fichas nuevas y archivos copiados.
    final Set<String> projectsBefore = <String>{for (final Project p in state.projects) p.id};
    final Set<String> templatesBefore = <String>{for (final StampTemplate t in state.templates) t.id};
    final Set<String> photosBefore = <String>{for (final PhotoRecord p in state.photos) p.id};
    try {
      return await _merge(ex, state);
    } catch (_) {
      state.projects.removeWhere((Project p) => !projectsBefore.contains(p.id));
      state.templates.removeWhere((StampTemplate t) => !templatesBefore.contains(t.id));
      state.photos.removeWhere((PhotoRecord p) => !photosBefore.contains(p.id));
      for (final String path in ex.created) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      try {
        await state.saveProjects();
        await state.savePhotos();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<RestoreSummary> _merge(_Extracted ex, AppState state) async {
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
  const _Extracted({required this.valid, this.projectsJson, this.photosJson, this.files = 0, this.cancelled = false, this.created = const <String>[]});

  /// Archivos que se copiaron (para deshacerlo si falla lo que sigue).
  final List<String> created;

  final bool valid;
  final bool cancelled;
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

/// Marca de cancelación: el isolate la busca entre un archivo y otro (no
/// comparte memoria con la app).
String _cancelMark(String root) => '$root${Platform.pathSeparator}exports${Platform.pathSeparator}.cancelar-restaurar';

class _ExtractRequest {
  const _ExtractRequest(this.port, this.zipPath, this.root);

  final SendPort port;
  final String zipPath;
  final String root;
}

Future<_Extracted> _extractInIsolate(String zipPath, String root, {void Function(int done, int total)? onProgress, ExportCancel? cancel}) async {
  final File mark = File(_cancelMark(root));
  if (mark.existsSync()) {
    mark.deleteSync();
  }
  void markCancelled() {
    try {
      mark.parent.createSync(recursive: true);
      mark.writeAsStringSync('1');
    } catch (_) {}
  }

  cancel?.whenCancelled(markCancelled);
  if (cancel?.cancelled ?? false) {
    markCancelled();
  }
  final ReceivePort port = ReceivePort();
  final Completer<_Extracted> done = Completer<_Extracted>();
  final StreamSubscription<dynamic> sub = port.listen((dynamic msg) {
    if (msg is _Extracted) {
      if (!done.isCompleted) {
        done.complete(msg);
      }
    } else if (msg is List && msg.length == 3 && msg[0] == 'progress') {
      onProgress?.call(msg[1] as int, msg[2] as int);
    } else if (msg is List) {
      // Error sin atrapar del isolate: [error, pila].
      if (!done.isCompleted) {
        done.completeError(FileSystemException('${msg.isNotEmpty ? msg.first : msg}'));
      }
    } else if (msg == null) {
      // El isolate terminó sin responder.
      if (!done.isCompleted) {
        done.completeError(const FileSystemException('La restauración se detuvo'));
      }
    }
  });
  try {
    await Isolate.spawn<_ExtractRequest>(_extractMain, _ExtractRequest(port.sendPort, zipPath, root), onError: port.sendPort, onExit: port.sendPort);
    return await done.future;
  } finally {
    cancel?.whenCancelled(null);
    await sub.cancel();
    port.close();
    try {
      if (mark.existsSync()) {
        mark.deleteSync();
      }
    } catch (_) {}
  }
}

void _extractMain(_ExtractRequest r) {
  r.port.send(_extract(r.zipPath, r.root, progress: (int d, int t) => r.port.send(<Object>['progress', d, t]), cancelled: () => File(_cancelMark(r.root)).existsSync()));
}

_Extracted _extract(String zipPath, String root, {void Function(int done, int total)? progress, bool Function()? cancelled}) {
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
    final List<ArchiveFile> entries = archive.files.where((ArchiveFile f) => f.isFile).toList();
    final List<String> created = <String>[];
    // Lo que se alcanzó a copiar se borra si se cancela o algo falla a mitad
    // (disco lleno, una entrada dañada): sin sus fichas, el reindexado lo
    // "recuperaría" como fotos sueltas.
    void undo() {
      for (final String path in created) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }

    int seen = 0;
    for (final ArchiveFile f in entries) {
      progress?.call(seen, entries.length);
      seen++;
      if (cancelled != null && cancelled()) {
        undo();
        return const _Extracted(valid: true, cancelled: true);
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
      final String tmp = '${dest.path}.tmp-restore';
      try {
        dest.parent.createSync(recursive: true);
        final OutputFileStream out = OutputFileStream(tmp);
        try {
          f.writeContent(out);
        } finally {
          out.closeSync();
        }
        File(tmp).renameSync(dest.path);
      } catch (e) {
        try {
          final File t = File(tmp);
          if (t.existsSync()) {
            t.deleteSync();
          }
        } catch (_) {}
        undo();
        rethrow;
      }
      created.add(dest.path);
      files++;
    }
    progress?.call(entries.length, entries.length);
    return _Extracted(valid: true, projectsJson: projects, photosJson: photos, files: files, created: created);
  } finally {
    input.closeSync();
  }
}
