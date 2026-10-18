import 'dart:math' as math;

import 'package:clock/clock.dart';

import '../audio/sequencer.dart';

int _idCounter = 0;
final math.Random _idRandom = math.Random();

/// Identificador único: microsegundos reales + contador + azar (dos llamadas
/// en el mismo microsegundo no chocan).
String newId() {
  _idCounter = (_idCounter + 1) % 1679616; // 36^4
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_idCounter.toRadixString(36).padLeft(4, '0')}${_idRandom.nextInt(46656).toRadixString(36)}';
}

// ------------------------------------------------------------ lectura segura
// Lo que llega de un archivo (propio o importado) puede traer cualquier cosa:
// estos ayudantes devuelven el valor solo si tiene el tipo esperado y lo
// acotan.

/// Texto de [j] en [key], recortado a [max] caracteres, o [fallback].
String jsonText(Map<String, dynamic> j, String key, {String fallback = '', int max = 200}) {
  final Object? v = j[key];
  if (v is! String) {
    return fallback;
  }
  final String s = v.trim();
  return s.length > max ? s.substring(0, max) : s;
}

/// Número finito de [j] en [key], acotado a [min]..[max], o [fallback].
double jsonDouble(Map<String, dynamic> j, String key, {required double fallback, required double min, required double max}) {
  final Object? v = j[key];
  if (v is! num) {
    return fallback;
  }
  final double d = v.toDouble();
  if (!d.isFinite) {
    return fallback;
  }
  return d.clamp(min, max).toDouble();
}

/// Entero de [j] en [key], acotado a [min]..[max], o [fallback].
int jsonInt(Map<String, dynamic> j, String key, {required int fallback, required int min, required int max}) {
  final Object? v = j[key];
  if (v is! num || !v.isFinite) {
    return fallback;
  }
  return v.round().clamp(min, max);
}

bool jsonBool(Map<String, dynamic> j, String key, {required bool fallback}) {
  final Object? v = j[key];
  return v is bool ? v : fallback;
}

DateTime? jsonDate(Map<String, dynamic> j, String key) {
  final Object? v = j[key];
  if (v is! String) {
    return null;
  }
  return DateTime.tryParse(v);
}

/// Identificador válido: letras, números, guion o guion bajo, hasta 64.
String jsonId(Map<String, dynamic> j, String key) {
  final Object? v = j[key];
  if (v is String && RegExp(r'^[A-Za-z0-9_\-]{1,64}$').hasMatch(v)) {
    return v;
  }
  return newId();
}

/// Preajuste del metrónomo (una "canción").
class Preset {
  Preset({required this.id, required this.name, required this.rhythm, this.notes = '', DateTime? createdAt}) : createdAt = createdAt ?? clock.now();

  final String id;
  String name;
  RhythmConfig rhythm;
  String notes;
  final DateTime createdAt;

  static const int maxName = 120;
  static const int maxNotes = 2000;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'rhythm': rhythm.toJson(), 'notes': notes, 'createdAt': createdAt.toIso8601String()};

  static Preset fromJson(Map<String, dynamic> j) {
    final Object? rhythm = j['rhythm'];
    return Preset(
      id: jsonId(j, 'id'),
      name: jsonText(j, 'name', max: maxName),
      rhythm: rhythm is Map<String, dynamic> ? RhythmConfig.fromJson(rhythm) : const RhythmConfig(),
      notes: jsonText(j, 'notes', max: maxNotes),
      createdAt: jsonDate(j, 'createdAt') ?? clock.now(),
    );
  }
}

/// Lista de preajustes en orden (un repertorio o un ensayo).
class Setlist {
  Setlist({required this.id, required this.name, List<String>? presetIds}) : presetIds = presetIds ?? <String>[];

  final String id;
  String name;
  final List<String> presetIds;

  static const int maxItems = 500;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'presetIds': presetIds};

  static Setlist fromJson(Map<String, dynamic> j) {
    final Object? raw = j['presetIds'];
    final List<String> ids = <String>[];
    if (raw is List<dynamic>) {
      for (final Object? e in raw) {
        if (e is String && RegExp(r'^[A-Za-z0-9_\-]{1,64}$').hasMatch(e) && ids.length < maxItems) {
          ids.add(e);
        }
      }
    }
    return Setlist(id: jsonId(j, 'id'), name: jsonText(j, 'name', max: Preset.maxName), presetIds: ids);
  }
}

/// Grabación guardada.
class Recording {
  Recording({
    required this.id,
    required this.name,
    required this.file,
    required this.format,
    required this.durationMs,
    required this.createdAt,
    this.folder = '',
    this.instrumentId = '',
    this.notes = '',
    this.bpm,
    this.recovered = false,
  });

  final String id;
  String name;

  /// Ruta relativa dentro del almacén (siempre en recordings/).
  final String file;
  final String format;

  /// Duración en milisegundos (0 si no se conoce, por ejemplo en una toma
  /// recuperada tras un cierre inesperado).
  int durationMs;
  final DateTime createdAt;
  String folder;
  String instrumentId;
  String notes;
  double? bpm;

  /// Toma rescatada de un cierre inesperado de la app.
  bool recovered;

  static const List<String> formats = <String>['aac', 'wav', 'flac'];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'file': file,
        'format': format,
        'durationMs': durationMs,
        'createdAt': createdAt.toIso8601String(),
        'folder': folder,
        'instrumentId': instrumentId,
        'notes': notes,
        if (bpm != null) 'bpm': bpm,
        if (recovered) 'recovered': true,
      };

  /// null si la entrada no apunta a un archivo válido de la carpeta de tomas.
  static Recording? fromJson(Map<String, dynamic> j) {
    final String file = jsonText(j, 'file', max: 200);
    if (!RegExp(r'^recordings/[A-Za-z0-9_\-.]+\.(m4a|wav|flac)$').hasMatch(file) || file.contains('..')) {
      return null;
    }
    final String format = jsonText(j, 'format', fallback: 'aac');
    final Object? bpm = j['bpm'];
    return Recording(
      id: jsonId(j, 'id'),
      name: jsonText(j, 'name', max: Preset.maxName),
      file: file,
      format: formats.contains(format) ? format : 'aac',
      durationMs: jsonInt(j, 'durationMs', fallback: 0, min: 0, max: 24 * 3600 * 1000),
      createdAt: jsonDate(j, 'createdAt') ?? clock.now(),
      folder: jsonText(j, 'folder', max: 60),
      instrumentId: jsonText(j, 'instrumentId', max: 40),
      notes: jsonText(j, 'notes', max: Preset.maxNotes),
      bpm: bpm is num && bpm.isFinite ? bpm.toDouble().clamp(20.0, 400.0).toDouble() : null,
      recovered: jsonBool(j, 'recovered', fallback: false),
    );
  }
}

/// Intervalo de práctica de una herramienta.
class PracticeSession {
  PracticeSession({required this.id, required this.start, required this.end, required this.tool, required this.instrumentId});

  final String id;
  final DateTime start;
  DateTime end;

  /// afinador | metronomo | tono | grabadora
  final String tool;
  final String instrumentId;

  static const List<String> tools = <String>['afinador', 'metronomo', 'tono', 'grabadora'];

  int get seconds => end.difference(start).inSeconds;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'start': start.toIso8601String(), 'end': end.toIso8601String(), 'tool': tool, 'instrumentId': instrumentId};

  /// null si la entrada no es un intervalo válido.
  static PracticeSession? fromJson(Map<String, dynamic> j) {
    final DateTime? start = jsonDate(j, 'start');
    final DateTime? end = jsonDate(j, 'end');
    final String tool = jsonText(j, 'tool', max: 20);
    if (start == null || end == null || end.isBefore(start) || !tools.contains(tool)) {
      return null;
    }
    // Un intervalo de más de un día no puede venir de una sola herramienta.
    final DateTime cappedEnd = end.difference(start) > const Duration(hours: 24) ? start.add(const Duration(hours: 24)) : end;
    return PracticeSession(id: jsonId(j, 'id'), start: start, end: cappedEnd, tool: tool, instrumentId: jsonText(j, 'instrumentId', max: 40));
  }
}
