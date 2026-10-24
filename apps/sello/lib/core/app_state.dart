import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../stamp/composer.dart';
import 'storage.dart';

/// Qué tuvo que arreglar la última carga, para avisarlo una vez.
enum LoadNoticeKind {
  /// El índice de fotos estaba dañado y se usó la copia anterior.
  photosFromBackup,

  /// No se pudo leer el índice de fotos ni su copia.
  photosLost,

  /// Los proyectos y plantillas venían de la copia anterior.
  projectsFromBackup,

  /// No se pudieron leer los proyectos ni su copia.
  projectsLost,

  /// Fotos de la carpeta que no estaban en el índice y se recuperaron.
  photosRecovered,
}

class LoadNotice {
  const LoadNotice(this.kind, [this.count = 0]);

  final LoadNoticeKind kind;
  final int count;
}

/// Proyectos, plantillas y fotos, guardados en JSON local.
class AppState extends ChangeNotifier {
  AppState(this.store);

  final JsonStore store;
  final List<Project> projects = <Project>[];
  final List<StampTemplate> templates = <StampTemplate>[];
  final List<PhotoRecord> photos = <PhotoRecord>[];
  bool loaded = false;

  /// Avisos de la última carga (recuperación del índice o de fotos sueltas).
  final List<LoadNotice> notices = <LoadNotice>[];

  /// Fotos que se están borrando ahora mismo (ver [isGone]).
  final Set<String> _deleting = <String>{};
  final StreamController<Set<String>> _removed = StreamController<Set<String>>.broadcast();

  /// Ids de las fotos que se empiezan a borrar. La cola de sellado los saca
  /// de su fila: el borrado gana siempre.
  Stream<Set<String>> get removedPhotos => _removed.stream;

  /// La ficha [p] ya no es la de la galería: se borró, se está borrando o la
  /// reemplazó otra. Lo que se estuviera haciendo con ella se descarta.
  bool isGone(PhotoRecord p) => _deleting.contains(p.id) || !identical(photoById(p.id), p);

  /// Lista de un JSON leído del disco, aunque traiga otra cosa (un índice
  /// tocado a mano desde la app Archivos no debe impedir abrir la app).
  static List<Map<String, dynamic>> _maps(Object? list) => list is List ? list.whereType<Map<String, dynamic>>().toList() : const <Map<String, dynamic>>[];

  /// Convierte cada elemento y deja fuera los que no se pueden leer y los
  /// que repiten un id ya leído (dos fichas con el mismo id confundirían la
  /// galería y los menús).
  static List<T> _parseAll<T>(Object? list, T Function(Map<String, dynamic> j) parse, String Function(T item) idOf) {
    final List<T> out = <T>[];
    final Set<String> seen = <String>{};
    for (final Map<String, dynamic> j in _maps(list)) {
      try {
        final T item = parse(j);
        if (seen.add(idOf(item))) {
          out.add(item);
        }
      } catch (e) {
        debugPrint('Ficha ilegible: $e');
      }
    }
    return out;
  }

  Future<void> load() async {
    notices.clear();
    final JsonRead p = await store.readJsonChecked('projects.json');
    if (p.outcome == ReadOutcome.fromBackup) {
      notices.add(const LoadNotice(LoadNoticeKind.projectsFromBackup));
    } else if (p.outcome == ReadOutcome.lost) {
      notices.add(const LoadNotice(LoadNoticeKind.projectsLost));
    }
    projects
      ..clear()
      ..addAll(_parseAll<Project>(p.data?['projects'], Project.fromJson, (Project x) => x.id));
    templates
      ..clear()
      ..addAll(_parseAll<StampTemplate>(p.data?['templates'], StampTemplate.fromJson, (StampTemplate x) => x.id));
    if (templates.every((StampTemplate t) => t.id != 'default')) {
      templates.insert(0, StampTemplate.defaultTemplate());
    }
    if (projects.isEmpty) {
      projects.add(Project(id: 'general', name: 'General'));
    }
    final JsonRead ph = await store.readJsonChecked('photos.json');
    if (ph.outcome == ReadOutcome.fromBackup) {
      notices.add(const LoadNotice(LoadNoticeKind.photosFromBackup));
    } else if (ph.outcome == ReadOutcome.lost) {
      notices.add(const LoadNotice(LoadNoticeKind.photosLost));
    }
    // Una ficha con tipos inesperados se deja fuera; si su foto sigue en la
    // carpeta, el reindexado de abajo la recupera con los datos de su EXIF.
    photos
      ..clear()
      ..addAll(_parseAll<PhotoRecord>(ph.data?['photos'], PhotoRecord.fromJson, (PhotoRecord x) => x.id));
    await store.cleanTemporaries('photos');
    final int recovered = await reindexPhotos();
    if (recovered > 0) {
      notices.add(LoadNotice(LoadNoticeKind.photosRecovered, recovered));
    }
    photos.sort((PhotoRecord a, PhotoRecord b) => b.takenAt.compareTo(a.takenAt));
    if (recovered > 0) {
      await savePhotos();
    }
    loaded = true;
    notifyListeners();
  }

  /// Busca en photos/ las imágenes que no figuran en el índice (por ejemplo,
  /// si el índice se perdió) y les crea su ficha con los datos que Sello
  /// escribió en el EXIF. Devuelve cuántas recuperó.
  Future<int> reindexPhotos() async {
    final Set<String> known = <String>{
      for (final PhotoRecord p in photos) ...<String>[p.originalFile, p.stampedFile],
    };
    final Map<String, String> stamped = <String, String>{};
    final Map<String, String> originals = <String, String>{};
    for (final String rel in await store.list('photos', extension: '.jpg', recursive: true)) {
      if (known.contains(rel) || rel.contains('.tmp-')) {
        continue;
      }
      if (rel.endsWith('-orig.jpg')) {
        originals[rel.substring(0, rel.length - '-orig.jpg'.length)] = rel;
      } else {
        stamped[rel.substring(0, rel.length - '.jpg'.length)] = rel;
      }
    }
    final Set<String> bases = <String>{...stamped.keys, ...originals.keys};
    final Set<String> ids = <String>{for (final PhotoRecord p in photos) p.id};
    int n = 0;
    for (final String base in bases.toList()..sort()) {
      final PhotoRecord? r = await _recordFromFiles(base, stamped[base], originals[base], ids);
      if (r != null) {
        photos.add(r);
        ids.add(r.id);
        n++;
      }
    }
    return n;
  }

  Future<PhotoRecord?> _recordFromFiles(String base, String? stampedRel, String? originalRel, Set<String> usedIds) async {
    final String source = stampedRel ?? originalRel!;
    Uint8List bytes;
    try {
      bytes = await File(await store.absolutePath(source)).readAsBytes();
    } catch (_) {
      return null;
    }
    final StampExif info = readStampExif(bytes);
    // photos/<proyecto>/<base>_<id>.jpg
    final List<String> parts = base.split('/');
    final String folder = parts.length >= 3 ? parts[1] : '';
    final String projectId = projects.any((Project p) => p.id == folder) ? folder : projects.first.id;
    final String name = parts.last;
    final int underscore = name.lastIndexOf('_');
    final String candidate = underscore >= 0 && underscore < name.length - 1 ? name.substring(underscore + 1) : '';
    final String id = candidate.isNotEmpty && !usedIds.contains(candidate) ? candidate : newId();
    DateTime when = info.takenAt ?? DateTime.now();
    if (info.takenAt == null) {
      try {
        when = await File(await store.absolutePath(source)).lastModified();
      } catch (_) {}
    }
    final JpegDims? dims = jpegSize(bytes);
    return PhotoRecord(
      id: id,
      projectId: projectId,
      originalFile: originalRel ?? '$base-orig.jpg',
      stampedFile: stampedRel ?? '$base.jpg',
      takenAt: when,
      utcOffsetMinutes: info.utcOffsetMinutes,
      latitude: info.latitude,
      longitude: info.longitude,
      altitude: info.altitudeMsl,
      altitudeMsl: info.altitudeMsl,
      heading: info.heading,
      headingTrue: info.headingTrue,
      // Sin la ficha, el EXIF de Sello dice la precisión y si la posición era
      // aproximada o escrita a mano: no se recupera como un punto exacto.
      accuracy: info.manual ? null : info.accuracy,
      approximateLocation: info.approximate,
      positionSource: info.manual ? PositionSource.manual : PositionSource.gps,
      description: info.description,
      width: dims?.width ?? 0,
      height: dims?.height ?? 0,
      status: stampedRel != null ? PhotoStatus.ok : PhotoStatus.failed,
      error: stampedRel != null ? '' : kErrorRecoveredOriginal,
    );
  }

  /// Motivo de fallo de una foto recuperada de la carpeta sin su copia sellada.
  static const String kErrorRecoveredOriginal = 'recovered';

  Future<void> saveProjects() async {
    await store.writeJson('projects.json', <String, dynamic>{
      'projects': projects.map((Project p) => p.toJson()).toList(),
      'templates': templates.map((StampTemplate t) => t.toJson()).toList(),
    });
    notifyListeners();
  }

  /// Guarda el índice de fotos. Las llamadas se encolan en el almacén: cada
  /// una escribe una foto completa del índice en el momento de llamarla.
  Future<void> savePhotos() async {
    await store.writeJson('photos.json', <String, dynamic>{'photos': photos.map((PhotoRecord p) => p.toJson()).toList()});
    notifyListeners();
  }

  Project projectById(String id) {
    for (final Project p in projects) {
      if (p.id == id) {
        return p;
      }
    }
    return projects.first;
  }

  Map<String, Project> get projectMap => <String, Project>{for (final Project p in projects) p.id: p};

  StampTemplate templateById(String id) {
    for (final StampTemplate t in templates) {
      if (t.id == id) {
        return t;
      }
    }
    return templates.first;
  }

  StampTemplate templateForProject(Project p) => templateById(p.templateId);

  PhotoRecord? photoById(String id) {
    for (final PhotoRecord p in photos) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  Future<Project> addProject(String name) async {
    final Project p = Project(id: newId(), name: name);
    projects.add(p);
    await saveProjects();
    return p;
  }

  Future<void> deleteProject(String id) async {
    if (projects.length <= 1) {
      return;
    }
    projects.removeWhere((Project p) => p.id == id);
    for (final PhotoRecord ph in photos) {
      if (ph.projectId == id) {
        ph.projectId = projects.first.id;
      }
    }
    await saveProjects();
    await savePhotos();
  }

  Future<StampTemplate> addTemplate(String name, {StampTemplate? copyOf}) async {
    final StampTemplate t = copyOf == null ? StampTemplate(id: newId(), name: name) : StampTemplate.fromJson(copyOf.toJson()..['id'] = newId()..['name'] = name);
    templates.add(t);
    await saveProjects();
    return t;
  }

  Future<void> deleteTemplate(String id) async {
    if (id == 'default') {
      return;
    }
    final String? logo = templateById(id).id == id ? templateById(id).logoPath : null;
    templates.removeWhere((StampTemplate t) => t.id == id);
    for (final Project p in projects) {
      if (p.templateId == id) {
        p.templateId = 'default';
      }
    }
    await saveProjects();
    await deleteLogoIfUnused(logo);
  }

  /// Borra el archivo de un logo si ya ninguna plantilla lo usa (las
  /// plantillas duplicadas comparten el archivo).
  Future<void> deleteLogoIfUnused(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('/')) {
      return;
    }
    if (templates.any((StampTemplate t) => t.logoPath == path)) {
      return;
    }
    await store.delete(path);
  }

  Future<void> addPhoto(PhotoRecord p) async {
    photos.insert(0, p);
    await savePhotos();
  }

  /// Borra fotos: primero los archivos (así el reindexado nunca las
  /// "resucita") y después sus fichas. El borrado gana siempre: se anuncia
  /// antes de empezar, y si una de estas fotos se está sellando, el sellado
  /// descarta lo que produzca (ver CapturePipeline.stamp).
  Future<void> deletePhotos(Iterable<PhotoRecord> list) async {
    final List<PhotoRecord> items = list.toList();
    final Set<String> ids = items.map((PhotoRecord p) => p.id).toSet();
    _deleting.addAll(ids);
    _removed.add(ids);
    try {
      for (final PhotoRecord p in items) {
        await store.delete(p.originalFile);
        if (p.stampedFile.isNotEmpty) {
          await store.delete(p.stampedFile);
        }
      }
      photos.removeWhere((PhotoRecord p) => ids.contains(p.id));
      await savePhotos();
    } finally {
      _deleting.removeAll(ids);
    }
  }

  /// Número que tendrá la próxima foto de un proyecto (variable {n} del
  /// nombre de archivo). Sale de un contador guardado en el proyecto que
  /// nunca baja: borrar o mover fotos no hace que un número se repita.
  int nextNumber(String projectId) {
    final int inProject = photos.where((PhotoRecord p) => p.projectId == projectId).length;
    final Project? project = projects.where((Project p) => p.id == projectId).firstOrNull;
    return math.max(project?.photoCounter ?? 0, inProject) + 1;
  }

  /// Toma el número de la próxima foto y lo deja guardado.
  Future<int> takeNumber(String projectId) async {
    final int n = nextNumber(projectId);
    final Project? project = projects.where((Project p) => p.id == projectId).firstOrNull;
    if (project != null) {
      project.photoCounter = n;
      await saveProjects();
    }
    return n;
  }

  Future<File> fileOf(String relative) async => File(await store.absolutePath(relative));

  /// Archivo que se muestra de una foto: la copia sellada si ya existe; si
  /// no (pendiente o fallida), el original.
  Future<File?> displayFile(PhotoRecord p) async {
    if (p.stampedFile.isNotEmpty && p.status == PhotoStatus.ok) {
      final File s = await fileOf(p.stampedFile);
      if (await s.exists()) {
        return s;
      }
    }
    final File o = await fileOf(p.originalFile);
    if (await o.exists()) {
      return o;
    }
    if (p.stampedFile.isNotEmpty) {
      final File s = await fileOf(p.stampedFile);
      if (await s.exists()) {
        return s;
      }
    }
    return null;
  }

  /// Archivo del logo de una plantilla (ruta relativa a la carpeta de la app
  /// o absoluta), o null si no tiene o no existe.
  Future<File?> logoFile(StampTemplate t) async {
    final String? p = t.logoPath;
    if (p == null || p.isEmpty) {
      return null;
    }
    final File f = p.startsWith('/') ? File(p) : await fileOf(p);
    return await f.exists() ? f : null;
  }

  Set<String> get allTags {
    final Set<String> s = <String>{};
    for (final PhotoRecord p in photos) {
      s.addAll(p.tags);
    }
    return s;
  }

  @override
  void dispose() {
    unawaited(_removed.close());
    super.dispose();
  }
}
