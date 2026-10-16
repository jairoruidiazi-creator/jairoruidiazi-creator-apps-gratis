import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import 'storage.dart';

/// Proyectos, plantillas y fotos, guardados en JSON local.
class AppState extends ChangeNotifier {
  AppState(this.store);

  final JsonStore store;
  final List<Project> projects = <Project>[];
  final List<StampTemplate> templates = <StampTemplate>[];
  final List<PhotoRecord> photos = <PhotoRecord>[];
  bool loaded = false;

  Future<void> load() async {
    final Map<String, dynamic>? p = await store.readJson('projects.json');
    projects
      ..clear()
      ..addAll(((p?['projects'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Project.fromJson));
    templates
      ..clear()
      ..addAll(((p?['templates'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(StampTemplate.fromJson));
    if (templates.every((StampTemplate t) => t.id != 'default')) {
      templates.insert(0, StampTemplate.defaultTemplate());
    }
    if (projects.isEmpty) {
      projects.add(Project(id: 'general', name: 'General'));
    }
    final Map<String, dynamic>? ph = await store.readJson('photos.json');
    photos
      ..clear()
      ..addAll(((ph?['photos'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(PhotoRecord.fromJson));
    photos.sort((PhotoRecord a, PhotoRecord b) => b.takenAt.compareTo(a.takenAt));
    loaded = true;
    notifyListeners();
  }

  Future<void> saveProjects() async {
    await store.writeJson('projects.json', <String, dynamic>{
      'projects': projects.map((Project p) => p.toJson()).toList(),
      'templates': templates.map((StampTemplate t) => t.toJson()).toList(),
    });
    notifyListeners();
  }

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
    templates.removeWhere((StampTemplate t) => t.id == id);
    for (final Project p in projects) {
      if (p.templateId == id) {
        p.templateId = 'default';
      }
    }
    await saveProjects();
  }

  Future<void> addPhoto(PhotoRecord p) async {
    photos.insert(0, p);
    await savePhotos();
  }

  Future<void> deletePhotos(Iterable<PhotoRecord> list) async {
    final Set<String> ids = list.map((PhotoRecord p) => p.id).toSet();
    for (final PhotoRecord p in list) {
      await store.delete(p.originalFile);
      if (p.stampedFile.isNotEmpty) {
        await store.delete(p.stampedFile);
      }
    }
    photos.removeWhere((PhotoRecord p) => ids.contains(p.id));
    await savePhotos();
  }

  /// Número consecutivo dentro de un proyecto (para nombres de archivo).
  int nextNumber(String projectId) => photos.where((PhotoRecord p) => p.projectId == projectId).length + 1;

  Future<File> fileOf(String relative) async => File(await store.absolutePath(relative));

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
}
