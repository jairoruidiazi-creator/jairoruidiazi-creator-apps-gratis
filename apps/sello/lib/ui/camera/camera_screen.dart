import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/capture_session.dart';
import '../../core/settings.dart';
import '../../geo/coords.dart';
import '../../geo/device_orientation.dart';
import '../../geo/heading.dart';
import '../../geo/location_service.dart';
import '../../model/models.dart';
import '../../stamp/stamp_data.dart';
import '../../stamp/stamp_painter.dart';
import '../gallery/gallery_screen.dart';
import '../gallery/photo_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'gps_sheet.dart';
import 'photo_data_sheet.dart';

/// Cámara con vista previa del sello en vivo.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.enabled = true, this.active = true});

  /// Falso en pruebas sin cámara: no se abre la cámara ni se piden permisos.
  final bool enabled;

  /// La cámara está a la vista: es la pestaña elegida y ninguna otra
  /// pantalla la tapa. Si no, se liberan la cámara (y la linterna), la
  /// brújula y la ubicación, y la pantalla puede apagarse.
  final bool active;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  Services? _services;
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraController? _controller;
  int _cameraIndex = 0;
  String? _error;

  /// Error de la cámara ya abierta (otra app la tomó, el sistema la cerró…).
  String? _runtimeError;
  Future<void>? _initFuture;
  String? _activeResolution;
  double _zoom = 1;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _baseZoom = 1;
  double _exposure = 0;
  double _minExposure = 0;
  double _maxExposure = 0;
  FlashMode _flash = FlashMode.off;
  int _countdown = 0;
  Timer? _countdownTimer;
  String? _lastId;
  Offset? _focusPoint;
  Timer? _focusTimer;
  bool _showExposure = false;
  bool _capturing = false;
  bool _started = false;
  bool _appResumed = true;
  bool _wakelockOn = false;

  /// Orientación de la interfaz (vertical en teléfonos) y giro que se está
  /// mostrando para el sello y los íconos.
  DeviceOrientation _uiOrientation = DeviceOrientation.portraitUp;
  bool _tablet = false;
  int _shownTurns = 0;
  double _iconTurns = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services == null) {
      final Services s = AppScope.of(context);
      _services = s;
      s.location.addListener(_refresh);
      s.heading.addListener(_refresh);
      s.settings.addListener(_onSettings);
      s.state.addListener(_refresh);
      s.session.addListener(_refresh);
      s.queue.addListener(_refresh);
      s.location.geocodingEnabled = s.settings.geocoding;
      if (widget.enabled && widget.active) {
        unawaited(_start());
      }
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Primero la cámara (que pide su permiso) y después la ubicación: Android
  /// no admite dos pedidos de permiso a la vez y descarta el segundo.
  Future<void> _start() async {
    if (_started) {
      return;
    }
    _started = true;
    final Services s = _services!;
    s.heading.start();
    _applyWakelock();
    await _initCamera();
    if (!mounted || !widget.active) {
      return;
    }
    s.location.acquire(this);
  }

  /// La cámara vuelve a estar a la vista.
  void _activate() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    if (!_started) {
      unawaited(_start());
      return;
    }
    s.heading.start();
    _applyWakelock();
    unawaited(_initCamera().then((_) {
      if (mounted && widget.active) {
        s.location.acquire(this);
      }
    }));
  }

  /// La cámara dejó de verse (otra pestaña u otra pantalla encima): se
  /// libera del todo, también la linterna (que no vuelve sola), y se
  /// detienen la brújula y la ubicación. En iPhone una cámara solo pausada
  /// seguía capturando con el indicador de cámara en uso.
  void _deactivate() {
    final Services? s = _services;
    _cancelCountdown();
    if (_flash == FlashMode.torch) {
      _flash = FlashMode.off;
    }
    unawaited(_releaseCamera());
    unawaited(s?.heading.stop());
    s?.location.release(this);
    _applyWakelock();
  }

  void _onSettings() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    s.location.geocodingEnabled = s.settings.geocoding;
    _applyWakelock();
    // La resolución se aplica en el acto: hay que abrir la cámara de nuevo.
    if (widget.enabled && _controller != null && _activeResolution != null && _activeResolution != s.settings.resolution && _initFuture == null) {
      unawaited(_restartCamera());
    }
    _refresh();
  }

  void _applyWakelock() {
    final Services? s = _services;
    if (!widget.enabled || s == null) {
      return;
    }
    final bool on = widget.active && _appResumed && s.settings.keepAwake;
    if (on != _wakelockOn) {
      _wakelockOn = on;
      s.keepAwake.set(on).catchError((Object e) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) {
      return;
    }
    final Services? s = _services;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _appResumed = false;
      _cancelCountdown();
      unawaited(_releaseCamera());
      unawaited(s?.heading.stop());
      _applyWakelock();
    } else if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      // Por si el permiso de ubicación quedó sin respuesta o se dio en los ajustes.
      if (_started && widget.active) {
        unawaited(s?.location.retry());
      }
      // Solo se reabren la cámara y los sensores si la pestaña está a la vista.
      if (widget.active && _started) {
        unawaited(_initCamera());
        s?.heading.start();
      }
      _applyWakelock();
    }
  }

  /// Abre la cámara. Si ya se está abriendo, espera esa misma apertura.
  Future<void> _initCamera() => _initFuture ??= _openCamera().whenComplete(() => _initFuture = null);

  Future<void> _openCamera() async {
    final Services s = _services!;
    if (_controller != null) {
      return;
    }
    _error = null;
    _runtimeError = null;
    _refresh();
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        _error = 'no-camera';
        return;
      }
      _cameraIndex = _cameraIndex.clamp(0, _cameras.length - 1);
      final String resolution = s.settings.resolution;
      final CameraController c = CameraController(_cameras[_cameraIndex], _preset(resolution), enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      try {
        _minZoom = await c.getMinZoomLevel();
        _maxZoom = await c.getMaxZoomLevel();
        _minExposure = await c.getMinExposureOffset();
        _maxExposure = await c.getMaxExposureOffset();
      } catch (_) {}
      _zoom = _minZoom;
      _exposure = 0;
      try {
        await c.setFlashMode(_flash);
      } catch (_) {}
      // En iPhone la orientación de captura también gira el video de la
      // vista previa: se fija en vertical, como la interfaz, y cada foto se
      // toma girada según el teléfono (ver _takePicture).
      if (defaultTargetPlatform == TargetPlatform.iOS && !_tablet) {
        try {
          await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
        } catch (_) {}
      }
      // Si mientras se abría la cámara dejó de verse, se cierra en el acto.
      if (!mounted || !_appResumed || !widget.active) {
        await c.dispose();
        return;
      }
      _controller = c;
      _activeResolution = resolution;
      c.addListener(_onControllerValue);
    } on CameraException catch (e) {
      _error = e.code.startsWith('CameraAccess') || e.code == 'cameraPermission' ? 'denied' : (e.description ?? e.code);
    } catch (e) {
      _error = e.toString();
    } finally {
      _refresh();
    }
  }

  Future<void> _releaseCamera() async {
    final CameraController? c = _controller;
    _controller = null;
    _refresh();
    c?.removeListener(_onControllerValue);
    await c?.dispose();
  }

  /// Un error de la cámara ya abierta (otra app la tomó en pantalla
  /// dividida, el sistema la cerró, se interrumpió la sesión…) dejaba la
  /// vista congelada y el obturador sin responder. Ahora se libera y se
  /// ofrece reintentar.
  void _onControllerValue() {
    final CameraController? c = _controller;
    if (c == null || !mounted) {
      return;
    }
    final String? err = c.value.errorDescription;
    if (err != null && _runtimeError == null) {
      _runtimeError = err;
      _error = 'runtime';
      _cancelCountdown();
      // Fuera de este aviso: no se puede liberar un controlador mientras
      // está avisando a sus oyentes.
      scheduleMicrotask(() {
        if (identical(_controller, c)) {
          unawaited(_releaseCamera());
        }
      });
    }
  }

  Future<void> _restartCamera() async {
    await (_initFuture ?? Future<void>.value());
    await _releaseCamera();
    await _initCamera();
  }

  ResolutionPreset _preset(String r) {
    switch (r) {
      case 'high':
        return ResolutionPreset.high;
      case 'veryHigh':
        return ResolutionPreset.veryHigh;
      case 'ultraHigh':
        return ResolutionPreset.ultraHigh;
      default:
        return ResolutionPreset.max;
    }
  }

  bool get _front {
    final CameraController? c = _controller;
    return c != null && c.description.lensDirection == CameraLensDirection.front;
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _capturing) {
      return;
    }
    // Si la cámara se está abriendo, se espera antes de cambiarla.
    await (_initFuture ?? Future<void>.value());
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _releaseCamera();
    await _initCamera();
  }

  Future<void> _cycleFlash() async {
    const List<FlashMode> modes = <FlashMode>[FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    _flash = modes[(modes.indexOf(_flash) + 1) % modes.length];
    try {
      await _controller?.setFlashMode(_flash);
    } catch (_) {}
    _refresh();
  }

  Future<void> _setZoom(double z) async {
    _zoom = z.clamp(_minZoom, _maxZoom);
    try {
      await _controller?.setZoomLevel(_zoom);
    } catch (_) {}
    _refresh();
  }

  Future<void> _setExposure(double v) async {
    _exposure = v.clamp(_minExposure, _maxExposure);
    try {
      await _controller?.setExposureOffset(_exposure);
    } catch (_) {}
    _refresh();
  }

  Future<void> _focusAt(TapDownDetails d, BoxConstraints box) async {
    final CameraController? c = _controller;
    if (c == null) {
      return;
    }
    final Offset rel = Offset((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0), (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0));
    setState(() => _focusPoint = d.localPosition);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 2), () => _refreshWith(() => _focusPoint = null));
    try {
      await c.setFocusPoint(rel);
      await c.setExposurePoint(rel);
    } catch (_) {}
  }

  void _refreshWith(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdown != 0) {
      _countdown = 0;
      _refresh();
    }
  }

  Future<void> _shutter() async {
    final Services s = _services!;
    // Tocar el obturador durante la cuenta regresiva la cancela.
    if (_countdown > 0) {
      _cancelCountdown();
      return;
    }
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    final int timer = s.settings.timerSeconds;
    if (timer > 0) {
      setState(() => _countdown = timer);
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer tm) {
        if (!mounted) {
          tm.cancel();
          return;
        }
        setState(() => _countdown -= 1);
        if (_countdown <= 0) {
          tm.cancel();
          _countdownTimer = null;
          unawaited(_capture());
        }
      });
      return;
    }
    await _capture();
  }

  /// Toma la foto con la orientación física del teléfono. En Android la
  /// orientación de captura no toca la vista previa. En iPhone sí (gira el
  /// video): se congela el cuadro mientras se dispara y se vuelve a la
  /// vertical después.
  Future<XFile> _takePicture(CameraController c, DeviceOrientation target) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      await c.lockCaptureOrientation(target);
      return c.takePicture();
    }
    final DeviceOrientation previewOrientation = _tablet ? c.value.deviceOrientation : DeviceOrientation.portraitUp;
    if (target == previewOrientation) {
      return c.takePicture();
    }
    await c.pausePreview();
    try {
      await c.lockCaptureOrientation(target);
      return await c.takePicture();
    } finally {
      try {
        if (_tablet) {
          await c.unlockCaptureOrientation();
        } else {
          await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
        }
      } catch (_) {}
      try {
        await c.resumePreview();
      } catch (_) {}
    }
  }

  Future<void> _capture() async {
    final Services s = _services!;
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _capturing) {
      return;
    }
    _capturing = true;
    try {
      if (s.settings.hapticShutter) {
        unawaited(HapticFeedback.mediumImpact());
      }
      final CaptureSession session = s.session;
      final Project project = session.project;
      final Fix? fix = s.location.fix;
      final Orientation3? ori = _orientationForLens(s.heading.orientation);
      final DateTime now = clock.now();
      final DeviceOrientation target = s.heading.physicalOrientation;
      XFile file;
      try {
        file = await _takePicture(c, target);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo tomar la foto', 'Could not take the photo')}: $e')));
        }
        return;
      }
      final PhotoRecord rec = await s.pipeline.saveCapture(
        jpegPath: file.path,
        project: project,
        fix: fix,
        orientation: ori,
        address: s.location.addressFor(fix),
        fields: session.fields,
        notes: session.notes,
        tags: session.tags,
        frontCamera: _front,
        now: now,
      );
      s.queue.enqueue(rec.id);
      _refreshWith(() => _lastId = rec.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'Error al guardar', 'Error saving')}: $e')));
      }
    } finally {
      _capturing = false;
    }
  }

  /// La cámara frontal mira al lado contrario: su rumbo es 180° distinto.
  Orientation3? _orientationForLens(Orientation3? o) => o == null ? null : (_front ? o.forFrontCamera() : o);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _focusTimer?.cancel();
    _controller?.removeListener(_onControllerValue);
    unawaited(_controller?.dispose());
    final Services? s = _services;
    if (widget.enabled && _wakelockOn) {
      s?.keepAwake.set(false).catchError((Object e) {});
    }
    s?.location.release(this);
    s?.location.removeListener(_refresh);
    s?.heading.removeListener(_refresh);
    s?.settings.removeListener(_onSettings);
    s?.state.removeListener(_refresh);
    s?.session.removeListener(_refresh);
    s?.queue.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CameraScreen old) {
    super.didUpdateWidget(old);
    if (!widget.enabled || old.active == widget.active) {
      return;
    }
    if (widget.active) {
      _activate();
    } else {
      _deactivate();
    }
  }

  DeviceOrientation _computeUiOrientation(BuildContext context, HeadingService heading) {
    _tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    if (!_tablet) {
      return DeviceOrientation.portraitUp;
    }
    final CameraController? c = _controller;
    if (c != null && c.value.isInitialized && defaultTargetPlatform == TargetPlatform.android) {
      // En Android la cámara informa la orientación de la interfaz.
      return c.value.deviceOrientation;
    }
    final DeviceOrientation phys = heading.physicalOrientation;
    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return isLandscapeOrientation(phys) ? phys : DeviceOrientation.landscapeLeft;
    }
    return phys == DeviceOrientation.portraitDown ? DeviceOrientation.portraitDown : DeviceOrientation.portraitUp;
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppSettings st = s.settings;
    final CaptureSession session = s.session;
    final CameraController? c = _controller;
    final Project project = session.project;
    final StampTemplate tpl = session.template;
    final Fix? fix = s.location.fix;
    final Orientation3? ori = _orientationForLens(s.heading.orientation);
    final bool spanish = st.spanish;
    _uiOrientation = _computeUiOrientation(context, s.heading);
    // Giro del sello y de los íconos para que se lean derechos con el
    // teléfono como esté (el giro animado va por el camino más corto).
    final int turns = quarterTurnsBetween(_uiOrientation, s.heading.physicalOrientation);
    if (turns != _shownTurns) {
      int delta = (turns - _shownTurns) % 4;
      if (delta == 3) {
        delta = -1;
      }
      _iconTurns += delta / 4;
      _shownTurns = turns;
    }
    final PhotoRecord preview = s.pipeline.buildRecord(
      id: 'vista-previa',
      project: project,
      originalFile: '',
      stampedFile: '',
      time: clock.now(),
      fix: fix,
      orientation: ori,
      address: s.location.addressFor(fix),
      fields: session.fields,
      notes: session.notes,
      tags: session.tags,
      frontCamera: _front,
    );
    final StampData data = StampData.fromRecord(preview, project: project, spanish: spanish);
    final Widget stamp = IgnorePointer(child: RotatedBox(quarterTurns: turns, child: CustomPaint(painter: StampPainter(template: tpl, data: data, logo: session.logo))));

    Widget previewArea;
    if (!widget.enabled) {
      // Sin cámara (pruebas): fondo negro con el sello en vivo encima.
      previewArea = Center(
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: Colors.black, child: Center(child: Icon(Icons.photo_camera_outlined, color: Colors.white54, size: 64))),
              stamp,
            ],
          ),
        ),
      );
    } else if (_error != null) {
      previewArea = ColoredBox(
        color: Colors.black,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
                const SizedBox(height: 12),
                Text(
                  _error == 'denied'
                      ? t(context, 'Sin permiso de cámara. Actívalo en los ajustes del teléfono.', 'Camera permission denied. Enable it in the phone settings.')
                      : (_error == 'no-camera'
                          ? t(context, 'Este equipo no tiene cámara.', 'This device has no camera.')
                          : (_error == 'runtime'
                              ? t(context, 'La cámara dejó de responder; puede que otra app la esté usando. Toca Reintentar.', 'The camera stopped responding; another app may be using it. Tap Retry.')
                              : '${t(context, 'Error de cámara', 'Camera error')}: $_error')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                if (_error == 'runtime' && (_runtimeError ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(_runtimeError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    FilledButton(onPressed: _initCamera, child: Text(t(context, 'Reintentar', 'Retry'))),
                    if (_error == 'denied') OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Colors.white), onPressed: () => s.location.backend.openAppSettings(), child: Text(t(context, 'Abrir ajustes', 'Open settings'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else if (c == null || !c.value.isInitialized) {
      previewArea = const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()));
    } else {
      Widget cam = _SelloPreview(controller: c);
      if (st.redFilter) {
        cam = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFFFF3B30), BlendMode.multiply), child: cam);
      }
      final bool landscapeUi = isLandscapeOrientation(_uiOrientation);
      previewArea = Center(
        child: AspectRatio(
          aspectRatio: landscapeUi ? c.value.aspectRatio : 1 / c.value.aspectRatio,
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
            return Semantics(
              label: t(context, 'Vista previa de la cámara. Toca un punto para enfocar.', 'Camera preview. Tap a spot to focus.'),
              child: GestureDetector(
              onTapDown: (TapDownDetails d) => _focusAt(d, box),
              onScaleStart: (_) => _baseZoom = _zoom,
              onScaleUpdate: (ScaleUpdateDetails d) => _setZoom(_baseZoom * d.scale),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  cam,
                  if (st.grid) const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
                  if (st.level && ori != null) IgnorePointer(child: CustomPaint(painter: _LevelPainter(roll: _levelRoll(ori.roll, turns), pitch: ori.pitch, turns: turns))),
                  stamp,
                  if (_focusPoint != null)
                    Positioned(
                      left: _focusPoint!.dx - 32,
                      top: _focusPoint!.dy - 32,
                      child: Container(width: 64, height: 64, decoration: BoxDecoration(border: Border.all(color: Colors.amber, width: 2), borderRadius: BorderRadius.circular(8))),
                    ),
                  if (_countdown > 0)
                    Center(
                      child: AnimatedRotation(
                        turns: _iconTurns,
                        duration: const Duration(milliseconds: 250),
                        child: Text('$_countdown', style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w800, color: Colors.white, shadows: <Shadow>[Shadow(blurRadius: 12, color: Colors.black)])),
                      ),
                    ),
                ],
              ),
              ),
            );
          }),
        ),
      );
    }

    final _GpsChipInfo gps = _gpsChip(context, s.location, fix);
    final int stamping = s.queue.pendingCount;
    final PhotoRecord? last = _lastId == null ? null : s.state.photoById(_lastId!);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Barra superior: proyecto, GPS, rumbo, ajustes. Crece con el texto.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  _Chip(icon: Icons.folder_outlined, label: '${project.emoji.isNotEmpty ? '${project.emoji} ' : ''}${project.name}', semanticsHint: t(context, 'Proyecto, campos y notas de la próxima foto', 'Project, fields and notes for the next photo'), onTap: () => showPhotoDataSheet(context)),
                  const SizedBox(width: 6),
                  _Chip(icon: Icons.gps_fixed, label: gps.label, color: gps.color, semanticsHint: t(context, 'Detalle del GPS y la brújula', 'GPS and compass details'), onTap: () => showGpsSheet(context)),
                  const SizedBox(width: 6),
                  _Chip(
                    icon: Icons.explore_outlined,
                    label: ori == null ? '—' : '${ori.cameraHeading.toStringAsFixed(0)}° ${Coords.cardinal(ori.cameraHeading, spanish: spanish)}${ori.trueNorth ? '' : t(context, ' magn.', ' magn.')}${ori.flat ? '' : ' · ${ori.pitch.toStringAsFixed(0)}°'}',
                    semanticsHint: t(context, 'Rumbo de la cámara', 'Camera heading'),
                    onTap: () => showGpsSheet(context),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: t(context, 'Ajustes', 'Settings'),
                    color: Colors.white,
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
            Expanded(child: previewArea),
            // Controles secundarios (desplazables en pantallas angostas) y zoom.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: <Widget>[
                  _Round(icon: _flashIcon(), turns: _iconTurns, onTap: _cycleFlash, label: '${t(context, 'Flash', 'Flash')}: ${_flashName(context)}'),
                  _Round(icon: st.grid ? Icons.grid_on : Icons.grid_off, turns: _iconTurns, onTap: () => _toggle(() => st.grid = !st.grid), label: t(context, 'Rejilla', 'Grid'), toggled: st.grid),
                  _Round(icon: Icons.straighten, turns: _iconTurns, onTap: () => _toggle(() => st.level = !st.level), label: t(context, 'Nivel', 'Level'), toggled: st.level),
                  _Round(
                    icon: st.timerSeconds == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
                    turns: _iconTurns,
                    badge: st.timerSeconds == 0 ? null : '${st.timerSeconds}',
                    onTap: () => _toggle(() => st.timerSeconds = st.timerSeconds == 0 ? 3 : (st.timerSeconds == 3 ? 10 : 0)),
                    label: st.timerSeconds == 0 ? t(context, 'Temporizador apagado', 'Timer off') : '${t(context, 'Temporizador', 'Timer')}: ${st.timerSeconds} s',
                  ),
                  _Round(icon: Icons.exposure, turns: _iconTurns, onTap: () => setState(() => _showExposure = !_showExposure), label: t(context, 'Exposición', 'Exposure'), toggled: _showExposure),
                  _Round(icon: Icons.nightlight_outlined, turns: _iconTurns, onTap: () => _toggle(() => st.redFilter = !st.redFilter), label: t(context, 'Filtro rojo', 'Red filter'), toggled: st.redFilter),
                  if (_maxZoom > _minZoom + 0.01) ...<Widget>[
                    const SizedBox(width: 8),
                    for (final double z in <double>[1, 2, 4, 8])
                      if (z <= _maxZoom) _ZoomChip(label: '${z.toStringAsFixed(0)}x', semantics: '${t(context, 'Zoom', 'Zoom')} ${z.toStringAsFixed(0)}x', selected: (_zoom - z).abs() < 0.3, onTap: () => _setZoom(z)),
                  ],
                ],
              ),
            ),
            if (_showExposure)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.brightness_low, color: Colors.white70, size: 18),
                    Expanded(
                      child: Slider(
                        min: _minExposure,
                        max: _maxExposure <= _minExposure ? _minExposure + 1 : _maxExposure,
                        value: _exposure.clamp(_minExposure, _maxExposure <= _minExposure ? _minExposure + 1 : _maxExposure),
                        onChanged: _setExposure,
                        label: _exposure.toStringAsFixed(1),
                        semanticFormatterCallback: (double v) => '${t(context, 'Exposición', 'Exposure')} ${v.toStringAsFixed(1)}',
                      ),
                    ),
                    const Icon(Icons.brightness_high, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            // Obturador
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: last == null
                        ? const SizedBox.shrink()
                        : Semantics(
                            button: true,
                            label: t(context, 'Abrir la última foto', 'Open the last photo'),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoDetailScreen(photoId: last.id))),
                              child: AnimatedRotation(
                                turns: _iconTurns,
                                duration: const Duration(milliseconds: 250),
                                child: ExcludeSemantics(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: PhotoThumb(key: ValueKey<String>('${last.id}-${last.version}-${last.status.name}'), record: last, cacheWidth: kCameraThumbWidth))),
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: _countdown > 0 ? t(context, 'Cancelar el temporizador', 'Cancel the timer') : t(context, 'Tomar foto', 'Take photo'),
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _shutter,
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _capturing ? Colors.white54 : Colors.white),
                              child: _countdown > 0 ? const Icon(Icons.close, color: Colors.black, size: 34) : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          onPressed: _cameras.length > 1 ? _switchCamera : null,
                          icon: AnimatedRotation(turns: _iconTurns, duration: const Duration(milliseconds: 250), child: const Icon(Icons.cameraswitch_outlined, color: Colors.white)),
                          tooltip: t(context, 'Cambiar cámara', 'Switch camera'),
                        ),
                        if (stamping > 0)
                          Semantics(
                            liveRegion: true,
                            child: Text('${t(context, 'sellando', 'stamping')} $stamping', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(VoidCallback change) {
    change();
    unawaited(_services!.settings.save());
  }

  /// Giro del nivel respecto a la orientación de la foto (0 = nivelado en
  /// vertical u horizontal).
  static double _levelRoll(double roll, int turns) {
    double r = roll - turns * 90;
    while (r > 180) {
      r -= 360;
    }
    while (r <= -180) {
      r += 360;
    }
    return r;
  }

  _GpsChipInfo _gpsChip(BuildContext context, LocationService loc, Fix? fix) {
    if (fix == null) {
      final String label = loc.status == 'denied' || loc.status == 'deniedForever'
          ? t(context, 'GPS sin permiso', 'GPS denied')
          : (loc.status == 'disabled' ? t(context, 'GPS apagado', 'GPS off') : t(context, 'Buscando GPS…', 'Searching GPS…'));
      return _GpsChipInfo(label, Colors.redAccent);
    }
    if (fix.manual) {
      return _GpsChipInfo(t(context, 'posición manual', 'manual position'), Colors.lightBlueAccent);
    }
    final double acc = fix.accuracy ?? 999;
    final StringBuffer b = StringBuffer(fix.accuracy == null ? '±?' : '± ${acc.toStringAsFixed(0)} m');
    if (fix.locked) {
      b.write(' · ${fix.source == PositionSource.averaged ? t(context, 'promedio fijo', 'averaged') : t(context, 'fija', 'locked')}');
    }
    if (loc.averaging) {
      b.write(' · ${t(context, 'promediando', 'averaging')} ${loc.averagingSamples}');
    }
    Color color = acc <= 10 ? Colors.lightGreenAccent : (acc <= 30 ? Colors.amber : Colors.orangeAccent);
    final Duration? age = loc.liveAge;
    if (loc.stale && age != null) {
      b.write(_services!.settings.spanish ? ' · hace ${_ageText(age)}' : ' · ${_ageText(age)} ago');
      color = Colors.orangeAccent;
    }
    return _GpsChipInfo(b.toString(), color);
  }

  static String _ageText(Duration d) {
    if (d.inSeconds < 90) {
      return '${d.inSeconds} s';
    }
    if (d.inMinutes < 90) {
      return '${d.inMinutes} min';
    }
    return '${d.inHours} h';
  }

  IconData _flashIcon() {
    switch (_flash) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }

  String _flashName(BuildContext context) {
    switch (_flash) {
      case FlashMode.off:
        return t(context, 'apagado', 'off');
      case FlashMode.auto:
        return t(context, 'automático', 'auto');
      case FlashMode.always:
        return t(context, 'siempre', 'always');
      case FlashMode.torch:
        return t(context, 'linterna', 'torch');
    }
  }
}

class _GpsChipInfo {
  const _GpsChipInfo(this.label, this.color);

  final String label;
  final Color color;
}

/// Vista previa de la cámara con la orientación de la interfaz. A
/// diferencia de CameraPreview, no gira con la orientación de captura (que
/// aquí cambia en cada foto según cómo se sostenga el teléfono).
class _SelloPreview extends StatelessWidget {
  const _SelloPreview({required this.controller});

  final CameraController controller;

  static const Map<DeviceOrientation, int> _turns = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeRight: 1,
    DeviceOrientation.portraitDown: 2,
    DeviceOrientation.landscapeLeft: 3,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (BuildContext context, CameraValue value, Widget? _) {
        if (!value.isInitialized) {
          return const SizedBox.shrink();
        }
        final Widget preview = controller.buildPreview();
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
          return preview;
        }
        // En Android la cámara informa la orientación de la interfaz.
        return RotatedBox(quarterTurns: _turns[value.deviceOrientation] ?? 0, child: preview);
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap, this.color, this.semanticsHint});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: semanticsHint,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 18, color: color ?? Colors.white),
                  if (label.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap, required this.label, required this.turns, this.toggled, this.badge});

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final double turns;
  final bool? toggled;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final bool active = toggled ?? false;
    // excludeSemantics deja fuera la acción del InkWell: se declara aquí.
    return Semantics(
      button: true,
      toggled: toggled,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.amber.withValues(alpha: 0.3) : Colors.transparent),
                child: AnimatedRotation(
                  turns: turns,
                  duration: const Duration(milliseconds: 250),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(icon, color: active ? Colors.amber : Colors.white),
                      if (badge != null) Positioned(right: 4, bottom: 4, child: Text(badge!, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w800))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.label, required this.semantics, required this.selected, required this.onTap});

  final String label;
  final String semantics;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: selected ? Colors.white : Colors.white24, borderRadius: BorderRadius.circular(14)),
              child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), p);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => false;
}

/// Nivel: horizonte que gira con el teléfono y sube o baja con la inclinación
/// de la cámara. Verde cuando está nivelado (±1°), en vertical u horizontal.
class _LevelPainter extends CustomPainter {
  const _LevelPainter({required this.roll, required this.pitch, required this.turns});

  /// Giro respecto a la orientación de la foto.
  final double roll;
  final double pitch;

  /// Cuartos de vuelta de la foto respecto a la pantalla.
  final int turns;

  @override
  void paint(Canvas canvas, Size size) {
    final bool level = roll.abs() < 1 && pitch.abs() < 1;
    final Color color = level ? const Color(0xFF69F0AE) : const Color(0xFFFFD54F);
    final Paint fixed = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final Offset c = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Todo se dibuja en el sistema de la foto (girado como el teléfono).
    canvas.rotate(turns * math.pi / 2);
    // Marca fija (la cámara).
    canvas.drawLine(const Offset(-26, 0), const Offset(-10, 0), fixed);
    canvas.drawLine(const Offset(10, 0), const Offset(26, 0), fixed);
    canvas.drawCircle(Offset.zero, 4, fixed);
    // Horizonte: 1° de inclinación ≈ 1 % de la altura (saturado a ±25°).
    final double frameHeight = turns.isOdd ? size.width : size.height;
    final double dy = (pitch.clamp(-25.0, 25.0)) / 100 * frameHeight;
    canvas.save();
    canvas.translate(0, dy);
    canvas.rotate(-roll * math.pi / 180);
    final Paint h = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-70, 0), const Offset(-34, 0), h);
    canvas.drawLine(const Offset(34, 0), const Offset(70, 0), h);
    canvas.restore();
    final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 11, textAlign: TextAlign.center))
      ..pushStyle(ui.TextStyle(color: color, shadows: <Shadow>[const Shadow(blurRadius: 3, color: Colors.black)]))
      ..addText('${roll.toStringAsFixed(0)}° / ${pitch.toStringAsFixed(0)}°');
    final ui.Paragraph par = pb.build()..layout(const ui.ParagraphConstraints(width: 120));
    canvas.drawParagraph(par, const Offset(-60, 34));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) => old.roll != roll || old.pitch != pitch || old.turns != turns;
}
