import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:sello/core/app_state.dart';
import 'package:sello/core/device_files.dart';
import 'package:sello/core/exports.dart';
import 'package:sello/core/keep_awake.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/core/storage.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';

/// JPEG sintético: degradado con un recuadro blanco arriba a la izquierda.
/// Opcionalmente con orientación EXIF, miniatura (IFD1) y datos de cámara.
Uint8List syntheticJpeg(int w, int h, {int orientation = 1, bool thumbnail = false, String? make, double? cameraLatitude}) {
  final img.Image im = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgb(x, y, (255 * x / w).round(), (255 * y / h).round(), 90);
    }
  }
  img.fillRect(im, x1: 2, y1: 2, x2: (w * 0.3).round(), y2: (h * 0.3).round(), color: img.ColorRgb8(255, 255, 255));
  if (orientation != 1) {
    im.exif.imageIfd.orientation = orientation;
  }
  if (make != null) {
    im.exif.imageIfd['Make'] = img.IfdValueAscii(make);
    im.exif.imageIfd['Model'] = img.IfdValueAscii('$make Uno');
    im.exif.exifIfd['ExposureTime'] = img.IfdValueRational(1, 120);
    im.exif.exifIfd['FNumber'] = img.IfdValueRational(18, 10);
  }
  if (cameraLatitude != null) {
    im.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    im.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational((cameraLatitude * 100).round(), 100);
  }
  if (thumbnail) {
    // Miniatura de otra imagen (negra): si sobrevive, mostraría algo distinto a la foto sellada.
    im.exif.thumbnailIfd['ImageWidth'] = img.IfdValueShort(8);
    im.exif.thumbnailData = img.encodeJpg(img.Image(width: 8, height: 6));
  }
  return img.encodeJpg(im, quality: 90);
}

/// Ubicación simulada: el test entrega las lecturas y decide los permisos.
class FakeLocationBackend implements LocationBackend {
  FakeLocationBackend({this.log});

  /// Registro compartido (por ejemplo con la cámara) del orden de las llamadas.
  final List<String>? log;
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission requestResult = LocationPermission.whileInUse;

  /// Si no es null, la petición de permiso queda esperando esta respuesta.
  Completer<LocationPermission>? pendingRequest;
  int requestCount = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;
  final StreamController<RawPosition> positionsCtrl = StreamController<RawPosition>.broadcast();
  final StreamController<GpsAltitude> altitudesCtrl = StreamController<GpsAltitude>.broadcast();
  List<Placemark> Function(double lat, double lon)? onPlacemarks;
  Object? placemarkError;
  int placemarkCalls = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() {
    requestCount++;
    log?.add('location:request');
    final Completer<LocationPermission>? p = pendingRequest;
    if (p != null) {
      return p.future;
    }
    permission = requestResult;
    return Future<LocationPermission>.value(requestResult);
  }

  @override
  Stream<RawPosition> positions() => positionsCtrl.stream;

  /// Veces que se abrió el canal de altitud del GPS (M6).
  int altitudeOpens = 0;

  /// Precisión concedida («aproximada» si el usuario la eligió).
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;

  /// Lo que concede el usuario al pedirle la precisa (null: no cambia).
  LocationAccuracyStatus? accuracyOnRequest;
  int fullAccuracyRequests = 0;

  @override
  Future<LocationAccuracyStatus> accuracyStatus() async => accuracy;

  @override
  Future<LocationAccuracyStatus> requestFullAccuracy() async {
    fullAccuracyRequests++;
    accuracy = accuracyOnRequest ?? accuracy;
    return accuracy;
  }

  @override
  Stream<GpsAltitude> gpsAltitudes() {
    altitudeOpens++;
    return altitudesCtrl.stream;
  }

  @override
  Future<List<Placemark>> placemarks(double latitude, double longitude, String localeIdentifier) async {
    placemarkCalls++;
    final Object? error = placemarkError;
    if (error != null) {
      throw error;
    }
    return onPlacemarks?.call(latitude, longitude) ?? <Placemark>[];
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }
}

/// Cámara simulada: anota cada llamada (crear, orientación, disparo…) y
/// entrega el JPEG que el test indique.
class FakeCameraPlatform extends CameraPlatform {
  FakeCameraPlatform({required this.directory, required this.picture, this.log});

  final Directory directory;

  /// JPEG que devuelve cada disparo (puede depender de la orientación fijada).
  final Uint8List Function(DeviceOrientation? locked) picture;
  final List<String>? log;
  final List<String> calls = <String>[];
  final List<ResolutionPreset?> presets = <ResolutionPreset?>[];
  int created = 0;
  int disposed = 0;
  int _nextId = 1;
  final Set<int> _disposedIds = <int>{};
  DeviceOrientation? _locked;

  /// Si no es null, initializeCamera espera hasta que se complete (como
  /// cuando el sistema muestra el diálogo de permiso).
  Completer<void>? initGate;
  final StreamController<DeviceOrientationChangedEvent> orientationCtrl = StreamController<DeviceOrientationChangedEvent>.broadcast();

  static const List<CameraDescription> cameras = <CameraDescription>[
    CameraDescription(name: 'trasera', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
    CameraDescription(name: 'frontal', lensDirection: CameraLensDirection.front, sensorOrientation: 270),
  ];

  void _log(String s) {
    calls.add(s);
    log?.add('camera:$s');
  }

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  /// Cámara abierta ahora (para saber si es la frontal, sin flash).
  CameraDescription? current;

  /// Si no es null, cada disparo espera hasta que se complete (un disparo
  /// largo, como con la resolución máxima).
  Completer<void>? takeGate;

  /// Exposición: valores pedidos, cuántos a la vez y cuánto tarda cada uno.
  final List<double> exposureRequests = <double>[];
  int exposureRunning = 0;
  int exposureMaxRunning = 0;
  int _exposureSeq = 0;
  int _focusSeq = 0;

  @override
  Future<int> createCameraWithSettings(CameraDescription cameraDescription, MediaSettings mediaSettings) async {
    current = cameraDescription;
    created++;
    presets.add(mediaSettings.resolutionPreset);
    _log('create:${cameraDescription.name}:${mediaSettings.resolutionPreset?.name}');
    return _nextId++;
  }

  @override
  Future<int> createCamera(CameraDescription cameraDescription, ResolutionPreset? resolutionPreset, {bool enableAudio = false}) =>
      createCameraWithSettings(cameraDescription, MediaSettings(resolutionPreset: resolutionPreset, enableAudio: enableAudio));

  /// Error que la plataforma emite mientras la cámara se abre (lo anota
  /// CameraController en su valor antes de terminar de abrirla).
  String? errorDuringInit;

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    _log('init');
    final String? early = errorDuringInit;
    if (early != null) {
      errorDuringInit = null;
      _errors.add(CameraErrorEvent(cameraId, early));
      await Future<void>.microtask(() {});
    }
    final Completer<void>? gate = initGate;
    if (gate != null) {
      await gate.future;
    }
    _log('initialized');
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) => Stream<CameraInitializedEvent>.value(CameraInitializedEvent(cameraId, 1920, 1080, ExposureMode.auto, true, FocusMode.auto, true));

  // Flujos que nunca emiten ni se cierran, como los de una cámara sin
  // errores (el controlador espera el primer error con .first).
  final StreamController<CameraResolutionChangedEvent> _resolution = StreamController<CameraResolutionChangedEvent>.broadcast();
  final StreamController<CameraClosingEvent> _closing = StreamController<CameraClosingEvent>.broadcast();
  final StreamController<CameraErrorEvent> _errors = StreamController<CameraErrorEvent>.broadcast();

  @override
  Stream<CameraResolutionChangedEvent> onCameraResolutionChanged(int cameraId) => _resolution.stream;

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) => _closing.stream;

  @override
  // Cada cámara recibe sus errores. (En camera_android_camerax los avisos
  // del canal estático llegan a todos los controladores, también a los ya
  // cerrados; CameraController los anota en su valor y en modo de
  // depuración eso dispara una aserción. No afecta a la app publicada y la
  // app ya no lee CameraValue.errorDescription.)
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream.where((CameraErrorEvent e) => e.cameraId == cameraId);

  /// Simula un error de la cámara ya abierta (otra app la tomó, el sistema
  /// la cerró…).
  void emitError(String description) => _errors.add(CameraErrorEvent(_nextId - 1, description));

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => orientationCtrl.stream;

  @override
  Future<void> lockCaptureOrientation(int cameraId, DeviceOrientation orientation) async {
    _locked = orientation;
    _log('lock:${orientation.name}');
  }

  @override
  Future<void> unlockCaptureOrientation(int cameraId) async {
    _locked = null;
    _log('unlock');
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    _log('take');
    final Completer<void>? gate = takeGate;
    if (gate != null) {
      await gate.future;
    }
    if (_disposedIds.contains(cameraId)) {
      // Como CameraX: cerrar la cámara a mitad del disparo lo hace fallar.
      throw CameraException('captureFailed', 'La cámara se cerró durante el disparo');
    }
    final String path = '${directory.path}/toma_${calls.length}.jpg';
    File(path).writeAsBytesSync(picture(_locked));
    return XFile(path);
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    _log('flash:${mode.name}');
    // camera_android_camerax 0.6.30: la linterna en una cámara sin flash
    // falla en CameraX y el complemento lo manda al canal de errores.
    if (mode == FlashMode.torch && current?.lensDirection == CameraLensDirection.front) {
      _errors.add(CameraErrorEvent(cameraId, 'The camera was unable to change torch modes.'));
    }
  }

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {}

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}

  @override
  Future<double> getMinExposureOffset(int cameraId) async => -2;

  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 2;

  @override
  Future<double> getExposureOffsetStepSize(int cameraId) async => 0.5;

  @override
  Future<double> setExposureOffset(int cameraId, double offset) async {
    exposureRequests.add(offset);
    exposureRunning++;
    exposureMaxRunning = max(exposureMaxRunning, exposureRunning);
    final int mine = ++_exposureSeq;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    } finally {
      exposureRunning--;
    }
    if (mine != _exposureSeq) {
      // Como CameraX: la petición anterior se cancela y el complemento lo
      // avisa por el canal de errores antes de lanzar la excepción.
      _errors.add(CameraErrorEvent(cameraId, 'Setting exposure compensation index was canceled due to the camera being closed or a new request being submitted.'));
      throw CameraException('setExposureOffsetFailed', 'canceled');
    }
    return offset;
  }

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {}

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {
    // Como CameraX: un enfoque nuevo cancela el que no ha terminado, y el
    // complemento lo avisa por el canal de errores.
    final int mine = ++_focusSeq;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mine != _focusSeq) {
      _errors.add(CameraErrorEvent(cameraId, 'Starting focus and metering was canceled due to the camera being closed or a new request being submitted.'));
    }
  }

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 8;

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}

  @override
  Future<void> pausePreview(int cameraId) async => _log('pause');

  @override
  Future<void> resumePreview(int cameraId) async => _log('resume');

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Color(0xFF345678));

  @override
  Future<void> dispose(int cameraId) async {
    _disposedIds.add(cameraId);
    disposed++;
    _log('dispose');
  }
}

/// Canal de sellado que no dibuja nada: anota qué se pidió sellar y cuántos
/// sellados corren a la vez. [onStamp] puede demorar o fallar a propósito.
class RecordingPipeline extends CapturePipeline {
  RecordingPipeline({required super.store, required super.state, required super.settings});

  final List<String> stamped = <String>[];
  int running = 0;
  int maxRunning = 0;
  Future<void> Function(PhotoRecord p)? onStamp;

  /// Simula que la copia a la fototeca no tiene permiso.
  bool galleryDenied = false;

  @override
  Future<StampOutcome> stamp(PhotoRecord p, {ui.Image? logo, bool copyToGallery = false}) async {
    running++;
    maxRunning = max(maxRunning, running);
    try {
      final Future<void> Function(PhotoRecord p)? hook = onStamp;
      if (hook != null) {
        await hook(p);
      }
      stamped.add(p.id);
      p
        ..status = PhotoStatus.ok
        ..error = ''
        ..version = p.version + 1;
      await state.savePhotos();
      return StampOutcome(record: p, galleryDenied: galleryDenied, galleryError: galleryDenied ? 'sin permiso' : null);
    } finally {
      running--;
    }
  }
}

/// Pantalla encendida simulada: anota si está pedida.
class FakeKeepAwake extends KeepAwake {
  bool on = false;

  @override
  Future<void> set(bool v) async => on = v;
}

/// Selector de documentos y espacio libre simulados (copia completa).
class FakeDeviceFiles extends DeviceFiles {
  FakeDeviceFiles({this.free, this.picker = true});

  /// Bytes libres que informa (null: no se sabe).
  int? free;

  /// Usa el selector de documentos (Android) o la hoja de compartir (iOS).
  bool picker;

  /// Lo que se pidió guardar: ruta de origen y si existía en ese momento.
  final List<String> saved = <String>[];
  final List<int> savedSizes = <int>[];

  /// ZIP que "elige" el usuario al restaurar (null: cancela).
  String? toOpen;

  /// Tamaño que informa el proveedor del documento (null: el del archivo;
  /// -1: no lo dice).
  int? reportedSize;

  /// La copia falla por falta de espacio, como un ENOSPC del canal nativo.
  bool noSpaceWhileCopying = false;

  /// Se cancela al llegar a este avance (bytes copiados), como si el
  /// usuario tocara Cancelar a mitad de la copia.
  int? cancelAt;

  /// Avance que se avisó y si se llegó a copiar.
  final List<int> progress = <int>[];
  int copies = 0;

  @override
  bool get usesDocumentPicker => picker;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<bool> saveDocument(String sourcePath, String name, {String mime = 'application/zip'}) async {
    saved.add(sourcePath);
    savedSizes.add(File(sourcePath).lengthSync());
    return true;
  }

  /// iPhone: la copia que el selector de archivos deja en tmp (null: cancela).
  String? toPickCopy;

  /// Carpetas temporales simuladas. Borrar la copia usa la lógica real
  /// ([DeviceFiles.deletePickedCopy] con [isPickerCopy]).
  List<String> tempDirs = <String>[];

  @override
  Future<String?> pickZipCopy() async => toPickCopy;

  @override
  Future<List<String>> temporaryDirs() async => tempDirs;

  @override
  Future<PickedDocument?> pickDocument({List<String> mimes = const <String>[]}) async {
    final String? source = toOpen;
    if (source == null) {
      return null;
    }
    return PickedDocument(uri: 'content://fake/$source', name: 'copia.zip', size: reportedSize ?? File(source).lengthSync());
  }

  @override
  Future<int> copyDocument(PickedDocument doc, String targetPath, {void Function(int done, int total)? onProgress, ExportCancel? cancel}) async {
    copies++;
    final Uint8List bytes = File(doc.uri.substring('content://fake/'.length)).readAsBytesSync();
    final File tmp = File('$targetPath.tmp-open');
    tmp.parent.createSync(recursive: true);
    final RandomAccessFile out = tmp.openSync(mode: FileMode.write);
    try {
      const int chunk = 1024;
      for (int i = 0; i < bytes.length; i += chunk) {
        if (cancelAt != null && i >= cancelAt!) {
          cancel?.cancel();
        }
        if (cancel?.cancelled ?? false) {
          throw const DocumentCopyCancelled();
        }
        if (noSpaceWhileCopying && i > 0) {
          throw const DocumentNoSpace();
        }
        out.writeFromSync(bytes, i, min(i + chunk, bytes.length));
        progress.add(min(i + chunk, bytes.length));
        onProgress?.call(min(i + chunk, bytes.length), doc.size);
        // Un respiro entre bloques (microtarea: pump() la atiende).
        await Future<void>.microtask(() {});
      }
    } catch (_) {
      out.closeSync();
      tmp.deleteSync();
      rethrow;
    }
    out.closeSync();
    tmp.renameSync(targetPath);
    return bytes.length;
  }
}

/// Ajustes en memoria (preferencias simuladas), sin copia a la fototeca.
Future<AppSettings> testSettings() async {
  final AppSettings s = AppSettings();
  await s.load();
  s.saveToGallery = false;
  return s;
}

/// Estado nuevo sobre una carpeta temporal.
Future<AppState> testState(Directory root) async {
  final AppState st = AppState(JsonStore(root: root));
  await st.load();
  return st;
}

/// Espera, con tiempo real, a que se cumpla [done] (E/S de disco dentro de
/// una prueba de widgets).
Future<void> waitReal(WidgetTester tester, bool Function() done, {int maxTenths = 80}) async {
  for (int i = 0; i < maxTenths && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
}
