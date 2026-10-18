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

/// Preajuste del metrónomo (una "canción").
class Preset {
  Preset({required this.id, required this.name, required this.rhythm, this.notes = '', DateTime? createdAt}) : createdAt = createdAt ?? clock.now();

  final String id;
  String name;
  RhythmConfig rhythm;
  String notes;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'rhythm': rhythm.toJson(), 'notes': notes, 'createdAt': createdAt.toIso8601String()};

  static Preset fromJson(Map<String, dynamic> j) => Preset(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        rhythm: j['rhythm'] is Map<String, dynamic> ? RhythmConfig.fromJson(j['rhythm'] as Map<String, dynamic>) : const RhythmConfig(),
        notes: j['notes'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? clock.now(),
      );
}

/// Lista de preajustes en orden (un repertorio o un ensayo).
class Setlist {
  Setlist({required this.id, required this.name, List<String>? presetIds}) : presetIds = presetIds ?? <String>[];

  final String id;
  String name;
  final List<String> presetIds;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'presetIds': presetIds};

  static Setlist fromJson(Map<String, dynamic> j) => Setlist(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        presetIds: ((j['presetIds'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
      );
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
  });

  final String id;
  String name;

  /// Ruta relativa dentro del almacén.
  final String file;
  final String format;
  int durationMs;
  final DateTime createdAt;
  String folder;
  String instrumentId;
  String notes;
  double? bpm;

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
      };

  static Recording fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        file: j['file'] as String? ?? '',
        format: j['format'] as String? ?? 'aac',
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? clock.now(),
        folder: j['folder'] as String? ?? '',
        instrumentId: j['instrumentId'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        bpm: (j['bpm'] as num?)?.toDouble(),
      );
}

/// Sesión de práctica registrada automáticamente.
class PracticeSession {
  PracticeSession({required this.id, required this.start, required this.end, required this.tool, required this.instrumentId});

  final String id;
  final DateTime start;
  DateTime end;

  /// afinador | metronomo | tono | grabadora
  final String tool;
  final String instrumentId;

  int get seconds => end.difference(start).inSeconds;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'start': start.toIso8601String(), 'end': end.toIso8601String(), 'tool': tool, 'instrumentId': instrumentId};

  static PracticeSession fromJson(Map<String, dynamic> j) => PracticeSession(
        id: j['id'] as String? ?? newId(),
        start: DateTime.tryParse(j['start'] as String? ?? '') ?? clock.now(),
        end: DateTime.tryParse(j['end'] as String? ?? '') ?? clock.now(),
        tool: j['tool'] as String? ?? '',
        instrumentId: j['instrumentId'] as String? ?? '',
      );
}
