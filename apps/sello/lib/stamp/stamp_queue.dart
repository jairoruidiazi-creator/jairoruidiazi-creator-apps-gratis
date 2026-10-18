import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../model/models.dart';
import 'capture_pipeline.dart';
import 'stamp_painter.dart';

/// Qué pasó con una foto de la cola.
enum StampEventKind {
  /// Quedó sellada.
  stamped,

  /// No se pudo sellar: queda el original y se puede reintentar.
  failed,

  /// Sellada, pero no se copió a la fototeca por falta de permiso.
  galleryDenied,

  /// Sellada, pero la copia a la fototeca falló.
  galleryError,
}

class StampEvent {
  const StampEvent(this.kind, this.record, [this.detail = '']);

  final StampEventKind kind;
  final PhotoRecord record;
  final String detail;
}

/// Cola de sellado: una foto a la vez (la composición de una foto de 12 MP
/// usa más de 100 MB; varias en paralelo podían agotar la memoria). Las
/// fotos pendientes quedan guardadas con su ficha, así que si la app se
/// cierra a mitad de camino el sellado se reanuda al abrirla
/// ([resumePending]). Cada resultado se anuncia en [events] para que la
/// interfaz avise si algo falló.
class StampQueue extends ChangeNotifier {
  StampQueue({required this.pipeline, Future<ui.Image?> Function(File file)? logoDecoder}) : _logoDecoder = logoDecoder ?? _decode;

  final CapturePipeline pipeline;
  final Future<ui.Image?> Function(File file) _logoDecoder;

  static Future<ui.Image?> _decode(File f) async => decodeLogo(await f.readAsBytes());

  AppState get state => pipeline.state;

  final List<_Job> _queue = <_Job>[];
  _Job? _current;
  bool _running = false;
  final StreamController<StampEvent> _events = StreamController<StampEvent>.broadcast();
  final Map<String, ui.Image?> _logos = <String, ui.Image?>{};
  Completer<void>? _idle;

  /// Resultados de la cola.
  Stream<StampEvent> get events => _events.stream;

  /// Fotos por sellar, incluida la que se está sellando.
  int get pendingCount => _queue.length + (_current == null ? 0 : 1);

  /// Id de la foto que se está sellando ahora, si hay.
  String? get currentId => _current?.id;

  bool contains(String id) => _current?.id == id || _queue.any((_Job j) => j.id == id);

  /// Pone en cola una foto recién tomada (o pendiente de una sesión
  /// anterior). Si se copia a la fototeca al terminar lo decide la ficha:
  /// solo la primera vez que queda sellada.
  void enqueue(String id) => _add(_Job(id, copyToGallery: true));

  /// Vuelve a sellar una foto con la plantilla actual de su proyecto (o
  /// reintenta una que falló). Completa con verdadero si quedó sellada.
  Future<bool> restamp(String id) {
    final PhotoRecord? p = state.photoById(id);
    if (p == null) {
      return Future<bool>.value(false);
    }
    p.templateId = state.projectById(p.projectId).templateId;
    final _Job job = _Job(id, copyToGallery: p.status != PhotoStatus.ok);
    _add(job);
    return job.done.future;
  }

  /// Encola todas las fotos que quedaron pendientes (de la más antigua a la
  /// más nueva).
  int resumePending() {
    final List<PhotoRecord> pending = state.photos.where((PhotoRecord p) => p.status == PhotoStatus.pending).toList()..sort((PhotoRecord a, PhotoRecord b) => a.takenAt.compareTo(b.takenAt));
    for (final PhotoRecord p in pending) {
      enqueue(p.id);
    }
    return pending.length;
  }

  /// Completa cuando la cola queda vacía.
  Future<void> idle() {
    if (!_running && _queue.isEmpty) {
      return Future<void>.value();
    }
    return (_idle ??= Completer<void>()).future;
  }

  void _add(_Job job) {
    if (contains(job.id)) {
      // Ya está en cola: quien espera recibe el mismo resultado.
      final _Job existing = _current?.id == job.id ? _current! : _queue.firstWhere((_Job j) => j.id == job.id);
      existing.followers.add(job.done);
      return;
    }
    _queue.add(job);
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final _Job job = _queue.removeAt(0);
        _current = job;
        notifyListeners();
        final bool ok = await _process(job);
        job.complete(ok);
        _current = null;
        notifyListeners();
      }
    } finally {
      _running = false;
      final Completer<void>? idle = _idle;
      _idle = null;
      idle?.complete();
    }
  }

  Future<ui.Image?> _logoFor(PhotoRecord p) async {
    final String? path = pipeline.templateFor(p).logoPath;
    if (path == null || path.isEmpty) {
      return null;
    }
    if (_logos.containsKey(path)) {
      return _logos[path];
    }
    ui.Image? logo;
    try {
      final File? f = await state.logoFile(pipeline.templateFor(p));
      if (f != null) {
        logo = await _logoDecoder(f);
      }
    } catch (e) {
      debugPrint('Logo: $e');
    }
    _logos[path] = logo;
    return logo;
  }

  /// Olvida los logos cargados (por ejemplo, al cambiar el de una plantilla).
  void forgetLogos() => _logos.clear();

  Future<bool> _process(_Job job) async {
    final PhotoRecord? p = state.photoById(job.id);
    if (p == null) {
      return false;
    }
    try {
      final StampOutcome out = await pipeline.stamp(p, logo: await _logoFor(p), copyToGallery: job.copyToGallery);
      _events.add(StampEvent(StampEventKind.stamped, p));
      if (out.galleryDenied) {
        _events.add(StampEvent(StampEventKind.galleryDenied, p, out.galleryError ?? ''));
      } else if (out.galleryError != null) {
        _events.add(StampEvent(StampEventKind.galleryError, p, out.galleryError!));
      }
      return true;
    } catch (e) {
      debugPrint('No se pudo sellar ${p.id}: $e');
      // Una foto ya sellada que no se pudo volver a sellar conserva su copia.
      if (p.status != PhotoStatus.ok) {
        p
          ..status = PhotoStatus.failed
          ..error = e is StampException ? e.code : e.toString();
        try {
          await state.savePhotos();
        } catch (_) {}
      }
      _events.add(StampEvent(StampEventKind.failed, p, e is StampException ? e.code : e.toString()));
      return false;
    }
  }

  @override
  void dispose() {
    unawaited(_events.close());
    super.dispose();
  }
}

class _Job {
  _Job(this.id, {required this.copyToGallery});

  final String id;
  final bool copyToGallery;
  final Completer<bool> done = Completer<bool>();
  final List<Completer<bool>> followers = <Completer<bool>>[];

  void complete(bool ok) {
    if (!done.isCompleted) {
      done.complete(ok);
    }
    for (final Completer<bool> f in followers) {
      if (!f.isCompleted) {
        f.complete(ok);
      }
    }
  }
}
