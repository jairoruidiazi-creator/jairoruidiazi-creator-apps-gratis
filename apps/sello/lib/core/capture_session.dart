import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../stamp/stamp_painter.dart';
import 'app_state.dart';
import 'settings.dart';

/// Datos de la próxima foto: proyecto activo, valores de sus campos, notas,
/// etiquetas y el logo de su plantilla.
///
/// Sigue a los ajustes y al estado, así que no importa por dónde cambien:
/// - al cambiar de proyecto (en la hoja de datos de la cámara, en la
///   pestaña Proyectos, al crear uno nuevo o al borrar el activo) los campos
///   vuelven a los valores iniciales del nuevo proyecto y las notas y
///   etiquetas se vacían: nunca pasan las del anterior;
/// - si se agregan o quitan campos al proyecto, se agregan con su valor
///   inicial o se quitan;
/// - si cambia el logo de la plantilla (o la plantilla del proyecto), el
///   logo se vuelve a cargar.
class CaptureSession extends ChangeNotifier {
  CaptureSession({required this.state, required this.settings, Future<ui.Image?> Function(File file)? logoDecoder}) : _logoDecoder = logoDecoder ?? _decode {
    state.addListener(_sync);
    settings.addListener(_sync);
    _sync();
  }

  final AppState state;
  final AppSettings settings;
  final Future<ui.Image?> Function(File file) _logoDecoder;

  static Future<ui.Image?> _decode(File f) async => decodeLogo(await f.readAsBytes());

  /// Valores de los campos del proyecto activo, por clave.
  final Map<String, String> fields = <String, String>{};
  final List<String> tags = <String>[];
  String _notes = '';
  String? _projectId;
  List<FieldDef> _fieldDefs = const <FieldDef>[];
  ui.Image? _logo;
  String? _logoKey;
  int _logoRequest = 0;
  bool _disposed = false;

  Project get project => state.projectById(settings.currentProjectId);

  StampTemplate get template => state.templateForProject(project);

  /// Logo de la plantilla del proyecto activo (null si no tiene).
  ui.Image? get logo => _logo;

  String get notes => _notes;

  set notes(String v) {
    if (_notes != v) {
      _notes = v;
      notifyListeners();
    }
  }

  /// Cambia el proyecto activo. Los campos se reinician al notar el cambio.
  Future<void> selectProject(String id) async {
    settings.currentProjectId = id;
    await settings.save();
  }

  void setField(String key, String value) {
    if (fields[key] != value) {
      fields[key] = value;
      notifyListeners();
    }
  }

  void addTag(String tag) {
    if (tag.isNotEmpty && !tags.contains(tag)) {
      tags.add(tag);
      notifyListeners();
    }
  }

  void removeTag(String tag) {
    if (tags.remove(tag)) {
      notifyListeners();
    }
  }

  void _sync() {
    if (_disposed) {
      return;
    }
    final Project p = project;
    bool changed = false;
    if (p.id != _projectId) {
      _projectId = p.id;
      fields
        ..clear()
        ..addAll(<String, String>{for (final FieldDef f in p.fields) f.key: f.defaultValue});
      _fieldDefs = List<FieldDef>.of(p.fields);
      // Las notas y etiquetas eran del proyecto anterior: no pasan al nuevo.
      _notes = '';
      tags.clear();
      changed = true;
    } else if (!_sameDefs(_fieldDefs, p.fields)) {
      final Map<String, FieldDef> before = <String, FieldDef>{for (final FieldDef f in _fieldDefs) f.key: f};
      fields.removeWhere((String k, String _) => !p.fields.any((FieldDef f) => f.key == k));
      for (final FieldDef f in p.fields) {
        final FieldDef? old = before[f.key];
        if (!fields.containsKey(f.key)) {
          fields[f.key] = f.defaultValue;
        } else if (old != null && old.defaultValue != f.defaultValue && fields[f.key] == old.defaultValue) {
          // Si nadie lo había cambiado, sigue al nuevo valor inicial.
          fields[f.key] = f.defaultValue;
        }
      }
      _fieldDefs = List<FieldDef>.of(p.fields);
      changed = true;
    }
    unawaited(_maybeReloadLogo());
    if (changed) {
      notifyListeners();
    }
  }

  static bool _sameDefs(List<FieldDef> a, List<FieldDef> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key || a[i].label != b[i].label || a[i].defaultValue != b[i].defaultValue) {
        return false;
      }
    }
    return true;
  }

  Future<void>? _logoLoading;

  /// Completa cuando termina de cargar el logo pedido más reciente.
  Future<void> logoReady() => _logoLoading ?? Future<void>.value();

  Future<void> _maybeReloadLogo() {
    final StampTemplate t = template;
    final String key = '${t.id}|${t.logoPath ?? ''}';
    if (key == _logoKey) {
      return _logoLoading ?? Future<void>.value();
    }
    _logoKey = key;
    final int request = ++_logoRequest;
    return _logoLoading = _loadLogo(t, request);
  }

  Future<void> _loadLogo(StampTemplate t, int request) async {
    ui.Image? image;
    try {
      final File? f = await state.logoFile(t);
      if (f != null) {
        image = await _logoDecoder(f);
      }
    } catch (e) {
      debugPrint('Logo: $e');
    }
    if (_disposed || request != _logoRequest) {
      return;
    }
    _logo = image;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_sync);
    settings.removeListener(_sync);
    super.dispose();
  }
}
