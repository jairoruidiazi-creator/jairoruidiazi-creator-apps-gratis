import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

import '../core/app_state.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../geo/heading.dart';
import '../geo/location_service.dart';
import '../model/models.dart';
import 'composer.dart';
import 'stamp_data.dart';
import 'stamp_painter.dart';

/// Resultado de una captura procesada.
class CaptureOutcome {
  const CaptureOutcome({required this.record, this.galleryError});

  final PhotoRecord record;
  final String? galleryError;
}

/// Convierte la foto que entrega la cámara en: original guardado, copia
/// sellada, EXIF con los datos, registro en la galería propia y, si se pide,
/// copia en la fototeca del sistema.
class CapturePipeline {
  CapturePipeline({required this.store, required this.state, required this.settings});

  final JsonStore store;
  final AppState state;
  final AppSettings settings;

  /// Construye los datos del sello con el estado actual de los sensores.
  StampData buildData({required Project project, Fix? fix, Orientation3? orientation, Address? address, Map<String, String> fields = const <String, String>{}, String notes = '', DateTime? now}) {
    return StampData(
      time: now ?? DateTime.now(),
      latitude: fix?.latitude,
      longitude: fix?.longitude,
      accuracy: fix?.accuracy,
      altitude: fix?.altitudeFor(settings.altitudeReference),
      altitudeIsMsl: settings.altitudeReference != 'ellipsoid',
      heading: orientation?.cameraHeading,
      pitch: orientation?.pitch,
      speed: fix?.speed,
      address: address?.full ?? '',
      projectName: project.name,
      fields: fields,
      fieldLabels: <String, String>{for (final FieldDef f in project.fields) f.key: f.label},
      notes: notes,
      spanish: settings.spanish,
      locked: fix?.locked ?? false,
      averaged: fix?.averagedSamples ?? 0,
    );
  }

  /// Procesa una captura. [jpegPath] es el archivo temporal que entrega la cámara.
  Future<CaptureOutcome> process({
    required String jpegPath,
    required Project project,
    required StampTemplate template,
    required StampData data,
    ui.Image? logo,
    Map<String, String> fields = const <String, String>{},
    String notes = '',
    List<String> tags = const <String>[],
  }) async {
    final Uint8List bytes = await File(jpegPath).readAsBytes();
    final int n = state.nextNumber(project.id);
    final String base = buildFileName(project.fileNamePattern, project: project.name, time: data.time, lat: data.latitude, lon: data.longitude, n: n);
    final String id = newId();
    final String originalRel = 'photos/${project.id}/${base}_$id-orig.jpg';
    final String stampedRel = 'photos/${project.id}/${base}_$id.jpg';
    await store.writeBytes(originalRel, bytes);

    // Tamaño de la foto (ya orientada) para dibujar el sello a escala.
    final JpegDims? dims = jpegSize(bytes);
    int w = dims?.width ?? 2000;
    int h = dims?.height ?? 1500;
    final int orientation = exifOrientation(bytes);
    if (orientation >= 5) {
      final int tmp = w;
      w = h;
      h = tmp;
    }
    // La capa se dibuja a 2000 px de ancho (misma proporción) y se escala en el isolate.
    const int layerW = 2000;
    final int layerH = (layerW * h / w).round().clamp(200, 6000);
    final Uint8List overlay = await renderStampPng(template, data, width: layerW, height: layerH, logo: logo);
    final String originalPath = await store.absolutePath(originalRel);
    final String stampedPath = await store.absolutePath(stampedRel);
    ComposeResult result;
    try {
      result = await composeStamped(ComposeJob(
        originalPath: originalPath,
        outputPath: stampedPath,
        overlayPng: overlay,
        overlayWidth: layerW,
        overlayHeight: layerH,
        quality: settings.jpegQuality,
        latitude: data.latitude,
        longitude: data.longitude,
        altitude: data.altitude,
        heading: data.heading,
        takenAt: data.time,
        description: data.summary(template),
      ));
    } catch (e) {
      debugPrint('No se pudo componer el sello: $e');
      // Si falla la composición, la copia sellada es el original.
      await File(originalPath).copy(stampedPath);
      result = ComposeResult(width: w, height: h, bytes: bytes.length);
    }
    final PhotoRecord record = PhotoRecord(
      id: id,
      projectId: project.id,
      originalFile: originalRel,
      stampedFile: stampedRel,
      takenAt: data.time,
      latitude: data.latitude,
      longitude: data.longitude,
      accuracy: data.accuracy,
      altitude: data.altitude,
      altitudeReference: settings.altitudeReference,
      heading: data.heading,
      pitch: data.pitch,
      speed: data.speed,
      address: data.address,
      fields: Map<String, String>.from(fields),
      notes: notes,
      tags: List<String>.from(tags),
      description: data.summary(template),
      width: result.width,
      height: result.height,
    );
    await state.addPhoto(record);
    if (!settings.keepOriginal) {
      await store.delete(originalRel);
    }
    String? galleryError;
    if (settings.saveToGallery) {
      try {
        await Gal.putImage(stampedPath, album: 'Sello');
      } catch (e) {
        galleryError = e.toString();
      }
    }
    try {
      await File(jpegPath).delete();
    } catch (_) {}
    return CaptureOutcome(record: record, galleryError: galleryError);
  }

  /// Lee la etiqueta de orientación EXIF (1 si no hay).
  static int exifOrientation(Uint8List bytes) {
    try {
      final ByteData d = ByteData.sublistView(bytes);
      int i = 2;
      while (i + 4 < bytes.length) {
        if (bytes[i] != 0xFF) {
          return 1;
        }
        final int marker = bytes[i + 1];
        final int len = d.getUint16(i + 2);
        if (marker == 0xE1 && i + 10 < bytes.length && bytes[i + 4] == 0x45 && bytes[i + 5] == 0x78) {
          final int tiff = i + 10;
          final bool little = bytes[tiff] == 0x49;
          final Endian e = little ? Endian.little : Endian.big;
          final int ifd = tiff + d.getUint32(tiff + 4, e);
          final int count = d.getUint16(ifd, e);
          for (int k = 0; k < count; k++) {
            final int entry = ifd + 2 + k * 12;
            if (d.getUint16(entry, e) == 0x0112) {
              return d.getUint16(entry + 8, e);
            }
          }
          return 1;
        }
        if (marker == 0xDA) {
          return 1;
        }
        i += 2 + len;
      }
    } catch (_) {}
    return 1;
  }
}
