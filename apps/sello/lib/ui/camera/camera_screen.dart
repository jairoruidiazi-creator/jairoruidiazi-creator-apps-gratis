import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/settings.dart';
import '../../geo/coords.dart';
import '../../geo/heading.dart';
import '../../geo/location_service.dart';
import '../../model/models.dart';
import '../../stamp/capture_pipeline.dart';
import '../../stamp/stamp_data.dart';
import '../../stamp/stamp_painter.dart';
import '../gallery/photo_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'gps_sheet.dart';
import 'photo_data_sheet.dart';

/// Cámara con vista previa del sello en vivo.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.enabled = true, this.active = true});

  final bool enabled;
  final bool active;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  Services? _services;
  CapturePipeline? _pipeline;
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraController? _controller;
  int _cameraIndex = 0;
  String? _error;
  bool _initializing = false;
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
  int _processing = 0;
  PhotoRecord? _last;
  Offset? _focusPoint;
  Timer? _focusTimer;
  ui.Image? _logo;
  String? _logoPath;
  final Map<String, String> _fields = <String, String>{};
  String _notes = '';
  final List<String> _tags = <String>[];
  bool _showExposure = false;

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
      _pipeline = CapturePipeline(store: s.store, state: s.state, settings: s.settings);
      s.location.addListener(_refresh);
      s.heading.addListener(_refresh);
      s.settings.addListener(_onSettings);
      s.state.addListener(_refresh);
      if (widget.enabled) {
        s.location.start();
        s.heading.start();
        _initCamera();
        WakelockPlus.toggle(enable: s.settings.keepAwake).catchError((Object e) {});
      }
      s.location.geocodingEnabled = s.settings.geocoding;
      _loadLogo();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onSettings() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    s.location.geocodingEnabled = s.settings.geocoding;
    if (widget.enabled) {
      WakelockPlus.toggle(enable: s.settings.keepAwake).catchError((Object e) {});
    }
    _loadLogo();
    _refresh();
  }

  Future<void> _loadLogo() async {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    final Project p = _project;
    final StampTemplate tpl = s.state.templateForProject(p);
    if (tpl.logoPath == _logoPath) {
      return;
    }
    _logoPath = tpl.logoPath;
    _logo = null;
    try {
      final File? f = await s.state.logoFile(tpl);
      if (f != null) {
        _logo = await decodeLogo(await f.readAsBytes());
      }
    } catch (_) {}
    _refresh();
  }

  Project get _project {
    final Services s = _services!;
    final String id = s.settings.currentProjectId;
    return s.state.projectById(id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? c = _controller;
    if (!widget.enabled) {
      return;
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _controller = null;
      c?.dispose();
      _services?.heading.stop();
      _refresh();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
      _services?.heading.start();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing) {
      return;
    }
    _initializing = true;
    _error = null;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        _error = 'no-camera';
        return;
      }
      _cameraIndex = _cameraIndex.clamp(0, _cameras.length - 1);
      final CameraController c = CameraController(_cameras[_cameraIndex], _preset(_services!.settings.resolution), enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
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
      try {
        await c.lockCaptureOrientation();
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
    } on CameraException catch (e) {
      _error = e.code.startsWith('CameraAccess') || e.code == 'cameraPermission' ? 'denied' : (e.description ?? e.code);
    } catch (e) {
      _error = e.toString();
    } finally {
      _initializing = false;
      _refresh();
    }
  }

  ResolutionPreset _preset(String r) {
    switch (r) {
      case 'high':
        return ResolutionPreset.high;
      case 'veryHigh':
        return ResolutionPreset.veryHigh;
      case 'max':
        return ResolutionPreset.max;
      default:
        return ResolutionPreset.ultraHigh;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) {
      return;
    }
    final CameraController? old = _controller;
    _controller = null;
    _refresh();
    await old?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
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
    _focusTimer = Timer(const Duration(seconds: 2), () => setState(() => _focusPoint = null));
    try {
      await c.setFocusPoint(rel);
      await c.setExposurePoint(rel);
    } catch (_) {}
  }

  Future<void> _shutter() async {
    final Services s = _services!;
    if (_controller == null || !_controller!.value.isInitialized || _countdown > 0) {
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
          _capture();
        }
      });
      return;
    }
    await _capture();
  }

  Future<void> _capture() async {
    final Services s = _services!;
    final CameraController? c = _controller;
    if (c == null || c.value.isTakingPicture) {
      return;
    }
    if (s.settings.hapticShutter) {
      unawaited(HapticFeedback.mediumImpact());
    }
    final Project project = _project;
    final StampTemplate tpl = s.state.templateForProject(project);
    final StampData data = _pipeline!.buildData(project: project, fix: s.location.fix, orientation: s.heading.orientation, address: s.location.address, fields: _fields, notes: _notes);
    XFile file;
    try {
      file = await c.takePicture();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo tomar la foto', 'Could not take the photo')}: $e')));
      }
      return;
    }
    setState(() => _processing += 1);
    try {
      final CaptureOutcome out = await _pipeline!.process(jpegPath: file.path, project: project, template: tpl, data: data, logo: _logo, fields: _fields, notes: _notes, tags: _tags);
      if (mounted) {
        setState(() => _last = out.record);
        if (out.galleryError != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Guardada en la app; no se pudo copiar a la fototeca.', 'Saved in the app; could not copy to the photo library.'))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'Error al guardar', 'Error saving')}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _processing -= 1);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _focusTimer?.cancel();
    _controller?.dispose();
    if (widget.enabled) {
      WakelockPlus.disable().catchError((Object e) {});
    }
    _services?.location.removeListener(_refresh);
    _services?.heading.removeListener(_refresh);
    _services?.settings.removeListener(_onSettings);
    _services?.state.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CameraScreen old) {
    super.didUpdateWidget(old);
    if (!widget.enabled || old.active == widget.active) {
      return;
    }
    // Al salir de la pestaña se pausan la vista previa y los sensores de
    // orientación; la ubicación sigue para que el mapa y la galería la usen.
    if (widget.active) {
      _controller?.resumePreview().catchError((Object e) {});
      _services?.heading.start();
    } else {
      _controller?.pausePreview().catchError((Object e) {});
      _services?.heading.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppSettings st = s.settings;
    final CameraController? c = _controller;
    final Project project = _project;
    final StampTemplate tpl = s.state.templateForProject(project);
    final Fix? fix = s.location.fix;
    final Orientation3? ori = s.heading.orientation;
    final StampData data = _pipeline!.buildData(project: project, fix: fix, orientation: ori, address: s.location.address, fields: _fields, notes: _notes);
    final bool spanish = st.spanish;

    Widget preview;
    if (!widget.enabled) {
      // Sin cámara (pruebas): fondo negro con el sello en vivo encima.
      preview = Center(
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: Colors.black, child: Center(child: Icon(Icons.photo_camera_outlined, color: Colors.white54, size: 64))),
              IgnorePointer(child: CustomPaint(painter: StampPainter(template: tpl, data: data, logo: _logo))),
            ],
          ),
        ),
      );
    } else if (_error != null) {
      preview = ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
                const SizedBox(height: 12),
                Text(
                  _error == 'denied'
                      ? t(context, 'Sin permiso de cámara. Actívalo en los ajustes del teléfono.', 'Camera permission denied. Enable it in the phone settings.')
                      : (_error == 'no-camera' ? t(context, 'Este equipo no tiene cámara.', 'This device has no camera.') : '${t(context, 'Error de cámara', 'Camera error')}: $_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _initCamera, child: Text(t(context, 'Reintentar', 'Retry'))),
              ],
            ),
          ),
        ),
      );
    } else if (c == null || !c.value.isInitialized) {
      preview = const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()));
    } else {
      Widget cam = CameraPreview(c);
      if (st.redFilter) {
        cam = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFFFF3B30), BlendMode.multiply), child: cam);
      }
      preview = LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
        return GestureDetector(
          onTapDown: (TapDownDetails d) => _focusAt(d, box),
          onScaleStart: (_) => _baseZoom = _zoom,
          onScaleUpdate: (ScaleUpdateDetails d) => _setZoom(_baseZoom * d.scale),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              cam,
              if (st.grid) const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
              if (st.level && ori != null) IgnorePointer(child: CustomPaint(painter: _LevelPainter(roll: ori.roll, pitch: ori.pitch))),
              IgnorePointer(child: CustomPaint(painter: StampPainter(template: tpl, data: data, logo: _logo))),
              if (_focusPoint != null)
                Positioned(
                  left: _focusPoint!.dx - 32,
                  top: _focusPoint!.dy - 32,
                  child: Container(width: 64, height: 64, decoration: BoxDecoration(border: Border.all(color: Colors.amber, width: 2), borderRadius: BorderRadius.circular(8))),
                ),
              if (_countdown > 0) Center(child: Text('$_countdown', style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w800, color: Colors.white, shadows: <Shadow>[Shadow(blurRadius: 12, color: Colors.black)]))),
            ],
          ),
        );
      });
      final bool landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
      preview = Center(child: AspectRatio(aspectRatio: landscape ? c.value.aspectRatio : 1 / c.value.aspectRatio, child: preview));
    }

    final String gpsLabel = fix == null
        ? (s.location.status == 'denied' ? t(context, 'GPS sin permiso', 'GPS denied') : (s.location.status == 'disabled' ? t(context, 'GPS apagado', 'GPS off') : t(context, 'Buscando GPS…', 'Searching GPS…')))
        : '± ${fix.accuracy.toStringAsFixed(0)} m${fix.locked ? ' · ${t(context, 'fija', 'locked')}' : ''}${s.location.averaging ? ' · ${t(context, 'promediando', 'averaging')}' : ''}';
    final Color gpsColor = fix == null ? Colors.redAccent : (fix.accuracy <= 10 ? Colors.lightGreenAccent : (fix.accuracy <= 30 ? Colors.amber : Colors.orangeAccent));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Barra superior: proyecto, GPS, rumbo, ajustes
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: <Widget>[
                  _Chip(icon: Icons.folder_outlined, label: project.name, onTap: () => showPhotoDataSheet(context, fields: _fields, notes: _notes, tags: _tags, onChanged: (String notes) => setState(() => _notes = notes))),
                  const SizedBox(width: 6),
                  _Chip(icon: Icons.gps_fixed, label: gpsLabel, color: gpsColor, onTap: () => showGpsSheet(context)),
                  const SizedBox(width: 6),
                  _Chip(
                    icon: Icons.explore_outlined,
                    label: ori == null ? '—' : '${ori.cameraHeading.toStringAsFixed(0)}° ${Coords.cardinal(ori.cameraHeading, spanish: spanish)}${ori.flat ? '' : ' · ${ori.pitch.toStringAsFixed(0)}°'}',
                    onTap: () => showGpsSheet(context),
                  ),
                  const SizedBox(width: 6),
                  _Chip(icon: Icons.settings_outlined, label: '', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()))),
                ],
              ),
            ),
            Expanded(child: preview),
            // Controles secundarios (desplazables en pantallas angostas) y zoom.
            SizedBox(
              height: 48,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  children: <Widget>[
                    _Round(icon: _flashIcon(), onTap: _cycleFlash, label: t(context, 'Flash', 'Flash')),
                    _Round(icon: st.grid ? Icons.grid_on : Icons.grid_off, onTap: () { st.grid = !st.grid; st.save(); }, label: t(context, 'Rejilla', 'Grid')),
                    _Round(icon: Icons.straighten, onTap: () { st.level = !st.level; st.save(); }, label: t(context, 'Nivel', 'Level'), active: st.level),
                    _Round(icon: st.timerSeconds == 0 ? Icons.timer_off_outlined : Icons.timer_outlined, badge: st.timerSeconds == 0 ? null : '${st.timerSeconds}', onTap: () { st.timerSeconds = st.timerSeconds == 0 ? 3 : (st.timerSeconds == 3 ? 10 : 0); st.save(); }, label: t(context, 'Temporizador', 'Timer')),
                    _Round(icon: Icons.exposure, onTap: () => setState(() => _showExposure = !_showExposure), label: t(context, 'Exposición', 'Exposure'), active: _showExposure),
                    _Round(icon: Icons.nightlight_outlined, onTap: () { st.redFilter = !st.redFilter; st.save(); }, label: t(context, 'Filtro rojo', 'Red filter'), active: st.redFilter),
                    if (_maxZoom > _minZoom + 0.01) ...<Widget>[
                      const SizedBox(width: 12),
                      for (final double z in <double>[1, 2, 4, 8])
                        if (z <= _maxZoom)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: _ZoomChip(label: '${z.toStringAsFixed(0)}x', selected: (_zoom - z).abs() < 0.3, onTap: () => _setZoom(z)),
                          ),
                    ],
                  ],
                ),
              ),
            ),
            if (_showExposure)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.brightness_low, color: Colors.white70, size: 18),
                    Expanded(child: Slider(min: _minExposure, max: _maxExposure <= _minExposure ? _minExposure + 1 : _maxExposure, value: _exposure.clamp(_minExposure, _maxExposure <= _minExposure ? _minExposure + 1 : _maxExposure), onChanged: _setExposure, label: _exposure.toStringAsFixed(1))),
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
                    child: _last == null
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoDetailScreen(photoId: _last!.id))),
                            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _Thumb(record: _last!)),
                          ),
                  ),
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: _shutter,
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _processing > 0 ? Colors.white54 : Colors.white),
                          child: _processing > 0 ? const Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black)) : null,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(onPressed: _cameras.length > 1 ? _switchCamera : null, icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white), tooltip: t(context, 'Cambiar cámara', 'Switch camera')),
                        if (_processing > 0) Text('${t(context, 'sellando', 'stamping')} $_processing', style: const TextStyle(color: Colors.white70, fontSize: 10)),
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
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap, required this.label, this.active = false, this.badge});

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final bool active;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.amber.withValues(alpha: 0.3) : Colors.transparent),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Icon(icon, color: active ? Colors.amber : Colors.white),
              if (badge != null) Positioned(right: 4, bottom: 4, child: Text(badge!, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w800))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: selected ? Colors.white : Colors.white24, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.record});

  final PhotoRecord record;

  @override
  Widget build(BuildContext context) {
    final AppState st = AppScope.of(context).state;
    return FutureBuilder<File>(
      future: st.fileOf(record.stampedFile),
      builder: (BuildContext context, AsyncSnapshot<File> snap) {
        if (!snap.hasData) {
          return const ColoredBox(color: Colors.white24);
        }
        return Image.file(snap.data!, fit: BoxFit.cover, cacheWidth: 128, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white24));
      },
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
/// de la cámara. Verde cuando está nivelado (±1°).
class _LevelPainter extends CustomPainter {
  const _LevelPainter({required this.roll, required this.pitch});

  final double roll;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final bool level = roll.abs() < 1 && pitch.abs() < 1;
    final Color color = level ? const Color(0xFF69F0AE) : const Color(0xFFFFD54F);
    final Paint fixed = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final Offset c = Offset(size.width / 2, size.height / 2);
    // Marca fija (la cámara).
    canvas.drawLine(c + const Offset(-26, 0), c + const Offset(-10, 0), fixed);
    canvas.drawLine(c + const Offset(10, 0), c + const Offset(26, 0), fixed);
    canvas.drawCircle(c, 4, fixed);
    // Horizonte: 1° de inclinación ≈ 1 % de la altura (saturado a ±25°).
    final double dy = (pitch.clamp(-25.0, 25.0)) / 100 * size.height;
    final double rad = -roll * math.pi / 180;
    canvas.save();
    canvas.translate(c.dx, c.dy + dy);
    canvas.rotate(rad);
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
    canvas.drawParagraph(par, Offset(c.dx - 60, c.dy + 34));
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) => old.roll != roll || old.pitch != pitch;
}
