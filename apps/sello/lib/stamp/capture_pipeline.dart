import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../core/photo_library.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../geo/heading.dart';
import '../geo/location_service.dart';
import '../model/models.dart';
import 'composer.dart';
import 'stamp_data.dart';
import 'stamp_painter.dart';

/// Resultado de sellar una foto.
class StampOutcome {
  const StampOutcome({required this.record, this.galleryError, this.galleryDenied = false});

  final PhotoRecord record;

  /// Por qué no se pudo copiar a la fototeca (null si se copió o no se pidió).
  final String? galleryError;

  /// La copia falló porque el usuario no dio permiso para la fototeca.
  final bool galleryDenied;
}

/// Convierte la foto que entrega la cámara en: original guardado con su
/// ficha (en el acto, para no perderla nunca) y, después, en la cola, la
/// copia sellada con el EXIF, el registro actualizado y, si se pide, la
/// copia en la fototeca del sistema.
class CapturePipeline {
  CapturePipeline({required this.store, required this.state, required this.settings});

  final JsonStore store;
  final AppState state;
  final AppSettings settings;

  /// Ficha de una foto con el estado de los sensores al disparar.
  PhotoRecord buildRecord({
    required String id,
    required Project project,
    required String originalFile,
    required String stampedFile,
    required DateTime time,
    Fix? fix,
    Orientation3? orientation,
    Address? address,
    Map<String, String> fields = const <String, String>{},
    String notes = '',
    List<String> tags = const <String>[],
    bool frontCamera = false,
    PhotoStatus status = PhotoStatus.pending,
  }) {
    final Map<String, String> labels = <String, String>{
      for (final FieldDef f in project.fields)
        if (fields.containsKey(f.key)) f.key: f.label,
    };
    int age = 0;
    if (fix != null && !fix.locked) {
      age = time.difference(fix.time).inSeconds;
      if (age < 0) {
        age = 0;
      }
    }
    return PhotoRecord(
      id: id,
      projectId: project.id,
      originalFile: originalFile,
      stampedFile: stampedFile,
      takenAt: time,
      latitude: fix?.latitude,
      longitude: fix?.longitude,
      accuracy: fix?.accuracy,
      altitude: fix?.altitudeFor(settings.altitudeReference),
      altitudeReference: settings.altitudeReference,
      altitudeMsl: fix?.altitudeMsl,
      heading: orientation?.cameraHeading,
      headingTrue: orientation?.trueNorth ?? true,
      pitch: orientation?.pitch,
      speed: fix?.speed,
      positionSource: fix?.source ?? PositionSource.gps,
      averagedSamples: fix?.averagedSamples ?? 0,
      fixAgeSeconds: age,
      address: address?.full ?? '',
      fields: Map<String, String>.from(fields),
      fieldLabels: labels,
      notes: notes,
      tags: List<String>.from(tags),
      templateId: project.templateId,
      frontCamera: frontCamera,
      status: status,
    );
  }

  /// Paso rápido al disparar: guarda el original y la ficha "pendiente" (ya
  /// en el índice en disco) antes de componer nada. Si el teléfono se queda
  /// sin memoria o la app se cierra mientras se sella, la foto y sus datos
  /// siguen ahí y el sellado se reanuda al abrir la app.
  Future<PhotoRecord> saveCapture({
    required String jpegPath,
    required Project project,
    Fix? fix,
    Orientation3? orientation,
    Address? address,
    Map<String, String> fields = const <String, String>{},
    String notes = '',
    List<String> tags = const <String>[],
    bool frontCamera = false,
    DateTime? now,
  }) async {
    final DateTime time = now ?? clock.now();
    final Uint8List bytes = await File(jpegPath).readAsBytes();
    final int n = state.nextNumber(project.id);
    final String base = buildFileName(project.fileNamePattern, project: project.name, time: time, lat: fix?.latitude, lon: fix?.longitude, n: n);
    final String id = newId();
    final String originalRel = 'photos/${project.id}/${base}_$id-orig.jpg';
    final String stampedRel = 'photos/${project.id}/${base}_$id.jpg';
    await store.writeBytes(originalRel, bytes);
    final PhotoRecord record = buildRecord(
      id: id,
      project: project,
      originalFile: originalRel,
      stampedFile: stampedRel,
      time: time,
      fix: fix,
      orientation: orientation,
      address: address,
      fields: fields,
      notes: notes,
      tags: tags,
      frontCamera: frontCamera,
    );
    // Texto del sello desde ya, para que la búsqueda la encuentre.
    record.description = StampData.fromRecord(record, project: project, spanish: settings.spanish).summary(state.templateById(project.templateId));
    await state.addPhoto(record);
    try {
      await File(jpegPath).delete();
    } catch (_) {}
    return record;
  }

  /// Plantilla con la que se sella una foto: la que tenía al tomarla o, si
  /// ya no existe, la del proyecto.
  StampTemplate templateFor(PhotoRecord p) {
    final String? id = p.templateId;
    if (id != null && state.templates.any((StampTemplate t) => t.id == id)) {
      return state.templateById(id);
    }
    return state.templateForProject(state.projectById(p.projectId));
  }

  /// Sella (o vuelve a sellar) una foto desde su original. Lanza una
  /// excepción si no se puede; la ficha no cambia en ese caso.
  Future<StampOutcome> stamp(PhotoRecord p, {ui.Image? logo, bool copyToGallery = false}) async {
    final File original = await state.fileOf(p.originalFile);
    if (!await original.exists()) {
      throw const StampException(StampException.missingOriginal);
    }
    final Uint8List bytes = await original.readAsBytes();
    final StampedPlan? plan = planStamped(bytes);
    if (plan == null) {
      throw const StampException(StampException.unreadable);
    }
    final Project project = state.projectById(p.projectId);
    final StampTemplate template = templateFor(p);
    final StampData data = StampData.fromRecord(p, project: project, spanish: settings.spanish);
    final StampOverlay? overlay = await renderStampOverlay(template, data, width: plan.width, height: plan.height, logo: logo);
    final String stampedRel = p.stampedFile.isNotEmpty ? p.stampedFile : p.originalFile.replaceAll('-orig.jpg', '.jpg');
    final String stampedPath = await store.absolutePath(stampedRel);
    final String description = data.summary(template);
    final ComposeResult result = await composeStamped(ComposeJob(
      originalPath: original.path,
      outputPath: stampedPath,
      quality: settings.jpegQuality,
      scale: plan.scale,
      expectedWidth: plan.width,
      expectedHeight: plan.height,
      overlayPng: overlay?.png,
      overlayLeft: overlay?.left ?? 0,
      overlayTop: overlay?.top ?? 0,
      latitude: p.latitude,
      longitude: p.longitude,
      altitudeMsl: p.altitudeMsl,
      heading: p.heading,
      headingTrue: p.headingTrue,
      takenAt: p.takenAt,
      utcOffsetMinutes: p.utcOffsetMinutes,
      description: description,
    ));
    final bool firstTime = p.status != PhotoStatus.ok;
    p
      ..stampedFile = stampedRel
      ..description = description
      ..width = result.width
      ..height = result.height
      ..status = PhotoStatus.ok
      ..error = ''
      ..templateId = template.id
      ..version = p.version + 1;
    await state.savePhotos();
    if (firstTime && !settings.keepOriginal) {
      await store.delete(p.originalFile);
    }
    String? galleryError;
    bool galleryDenied = false;
    if (copyToGallery && firstTime && settings.saveToGallery) {
      try {
        await PhotoLibrary.put(stampedPath);
      } on PhotoLibraryDenied catch (e) {
        galleryError = e.toString();
        galleryDenied = true;
      } catch (e) {
        galleryError = e.toString();
      }
    }
    return StampOutcome(record: p, galleryError: galleryError, galleryDenied: galleryDenied);
  }
}

/// Por qué no se pudo sellar una foto.
class StampException implements Exception {
  const StampException(this.code);

  /// El original ya no está (se borró o no se conservó).
  static const String missingOriginal = 'missing-original';

  /// El archivo no es un JPEG legible.
  static const String unreadable = 'unreadable';

  final String code;

  @override
  String toString() => 'StampException: $code';
}
