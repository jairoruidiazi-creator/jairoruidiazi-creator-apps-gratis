import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../audio/take_recorder.dart';
import '../model/models.dart';
import 'storage.dart';

/// Resultado de importar un archivo de preajustes.
class ImportResult {
  const ImportResult({required this.presets, required this.setlists});

  final int presets;
  final int setlists;
}

/// Datos de la app: preajustes, setlists y grabaciones. Todo se guarda en
/// archivos JSON locales (el registro de práctica va en [PracticeLog]).
class AppState extends ChangeNotifier {
  AppState(this.store);

  final JsonStore store;
  final List<Preset> presets = <Preset>[];
  final List<Setlist> setlists = <Setlist>[];
  final List<Recording> recordings = <Recording>[];
  bool loaded = false;

  /// Número de la próxima "Toma N" (no se repite aunque se borren tomas).
  int nextTake = 1;

  /// Tomas rescatadas en esta apertura (para avisar).
  int recoveredTakes = 0;

  static const int maxPresets = 2000;
  static const int maxSetlists = 200;

  Future<void> load() async {
    final Map<String, dynamic>? p = await store.readJson('presets.json');
    presets.clear();
    setlists.clear();
    _readPresets(p, presets, setlists);
    final Map<String, dynamic>? r = await store.readJson('recordings.json');
    recordings.clear();
    final Object? rawRecs = r?['recordings'];
    if (rawRecs is List<dynamic>) {
      for (final Object? e in rawRecs) {
        if (e is Map<String, dynamic>) {
          final Recording? rec = Recording.fromJson(e);
          if (rec != null && !recordings.any((Recording x) => x.id == rec.id)) {
            recordings.add(rec);
          }
        }
      }
    }
    recordings.sort((Recording a, Recording b) => b.createdAt.compareTo(a.createdAt));
    final Object? next = r?['nextTake'];
    nextTake = next is int && next > 0 ? next : recordings.length + 1;
    loaded = true;
    notifyListeners();
  }

  static void _readPresets(Map<String, dynamic>? data, List<Preset> outPresets, List<Setlist> outSetlists) {
    final Object? rawPresets = data?['presets'];
    if (rawPresets is List<dynamic>) {
      for (final Object? e in rawPresets) {
        if (e is Map<String, dynamic> && outPresets.length < maxPresets) {
          outPresets.add(Preset.fromJson(e));
        }
      }
    }
    final Object? rawSetlists = data?['setlists'];
    if (rawSetlists is List<dynamic>) {
      for (final Object? e in rawSetlists) {
        if (e is Map<String, dynamic> && outSetlists.length < maxSetlists) {
          outSetlists.add(Setlist.fromJson(e));
        }
      }
    }
  }

  // ------------------------------------------------------------ preajustes

  Future<void> savePresets() async {
    notifyListeners();
    await store.writeJson('presets.json', <String, dynamic>{
      'presets': presets.map((Preset p) => p.toJson()).toList(),
      'setlists': setlists.map((Setlist s) => s.toJson()).toList(),
    });
  }

  Future<Preset> addPreset(Preset p) async {
    presets.insert(0, p);
    await savePresets();
    return p;
  }

  Future<void> deletePreset(String id) async {
    presets.removeWhere((Preset p) => p.id == id);
    for (final Setlist s in setlists) {
      s.presetIds.remove(id);
    }
    await savePresets();
  }

  Preset? presetById(String id) {
    for (final Preset p in presets) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  Setlist? setlistById(String id) {
    for (final Setlist s in setlists) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }

  /// Preajustes de una setlist, en su orden (sin los borrados).
  List<Preset> presetsOf(Setlist s) => s.presetIds.map(presetById).whereType<Preset>().toList();

  Future<Setlist> addSetlist(String name) async {
    final Setlist s = Setlist(id: newId(), name: name.length > Preset.maxName ? name.substring(0, Preset.maxName) : name);
    setlists.add(s);
    await savePresets();
    return s;
  }

  Future<void> deleteSetlist(String id) async {
    setlists.removeWhere((Setlist s) => s.id == id);
    await savePresets();
  }

  /// Exporta preajustes y setlists como JSON (para compartir entre equipos).
  Map<String, dynamic> exportPresets() => <String, dynamic>{
        'app': 'clave',
        'version': 1,
        'presets': presets.map((Preset p) => p.toJson()).toList(),
        'setlists': setlists.map((Setlist s) => s.toJson()).toList(),
      };

  /// Importa sin duplicar ids. Todo lo que llega se valida y se acota (un
  /// archivo de otra persona puede traer cualquier cosa). Lanza
  /// [FormatException] si el archivo no tiene preajustes de Clave.
  Future<ImportResult> importPresets(Map<String, dynamic> data) async {
    final Object? rawPresets = data['presets'];
    final Object? rawSetlists = data['setlists'];
    if (rawPresets is! List<dynamic> && rawSetlists is! List<dynamic>) {
      throw const FormatException('El archivo no tiene preajustes de Clave');
    }
    final List<Preset> inPresets = <Preset>[];
    final List<Setlist> inSetlists = <Setlist>[];
    _readPresets(data, inPresets, inSetlists);
    int n = 0;
    final Set<String> ids = presets.map((Preset p) => p.id).toSet();
    for (final Preset p in inPresets) {
      if (presets.length >= maxPresets) {
        break;
      }
      if (ids.add(p.id)) {
        presets.add(p);
        n += 1;
      }
    }
    int m = 0;
    final Set<String> sids = setlists.map((Setlist s) => s.id).toSet();
    for (final Setlist s in inSetlists) {
      if (setlists.length >= maxSetlists) {
        break;
      }
      if (sids.add(s.id)) {
        // Solo quedan las referencias a preajustes que existen.
        s.presetIds.removeWhere((String id) => !ids.contains(id));
        setlists.add(s);
        m += 1;
      }
    }
    await savePresets();
    return ImportResult(presets: n, setlists: m);
  }

  // ------------------------------------------------------------ grabaciones

  Future<void> saveRecordings() async {
    notifyListeners();
    await store.writeJson('recordings.json', <String, dynamic>{
      'nextTake': nextTake,
      'recordings': recordings.map((Recording r) => r.toJson()).toList(),
    });
  }

  /// Toma el siguiente número de toma.
  int takeNumber() => nextTake++;

  Future<void> addRecording(Recording r) async {
    recordings.insert(0, r);
    await saveRecordings();
  }

  /// Pasa una toma terminada a la lista como "Toma N" (la detuviera la
  /// persona o el sistema).
  Future<Recording> addTake(TakeResult take, {required String takeWord}) async {
    final Recording r = Recording(
      id: newId(),
      name: '$takeWord ${takeNumber()}',
      file: take.file,
      format: take.format,
      durationMs: take.durationMs,
      createdAt: take.startedAt,
      folder: take.folder,
      instrumentId: take.instrumentId,
      bpm: take.bpm,
    );
    await addRecording(r);
    return r;
  }

  /// La duración real de una toma (la da el reproductor; las rescatadas no
  /// la traen).
  Future<void> setDuration(Recording r, int durationMs) async {
    if (durationMs <= 0 || r.durationMs == durationMs) {
      return;
    }
    r.durationMs = durationMs;
    await saveRecordings();
  }

  Future<void> deleteRecording(Recording r) async {
    recordings.removeWhere((Recording x) => x.id == r.id);
    await store.delete(r.file);
    await saveRecordings();
  }

  List<String> get folders {
    final Set<String> f = <String>{};
    for (final Recording r in recordings) {
      if (r.folder.isNotEmpty) {
        f.add(r.folder);
      }
    }
    final List<String> out = f.toList()..sort();
    return out;
  }

  /// Rescata las tomas de una grabación que no terminó (la app se cerró de
  /// golpe) y los archivos de la carpeta que no están en la lista. Los
  /// archivos vacíos se borran. Devuelve cuántas tomas se rescataron.
  Future<int> recoverTakes({required String takeWord, String instrumentId = ''}) async {
    final Set<String> known = recordings.map((Recording r) => r.file).toSet();
    final List<String> candidates = <String>[];
    final Map<String, dynamic>? pending = await store.readJson(TakeRecorder.pendingFile);
    final Object? pendingFile = pending?['file'];
    if (pendingFile is String) {
      candidates.add(pendingFile);
    }
    for (final String rel in await store.list('recordings')) {
      if (RegExp(r'\.(m4a|wav|flac)$').hasMatch(rel) && !candidates.contains(rel)) {
        candidates.add(rel);
      }
    }
    int n = 0;
    for (final String rel in candidates) {
      if (known.contains(rel)) {
        continue;
      }
      final int size = await store.size(rel);
      if (size <= 0) {
        if (await store.exists(rel)) {
          await store.delete(rel);
        }
        continue;
      }
      final String ext = rel.split('.').last;
      // La toma a medias trae del marcador su hora, carpeta e instrumento.
      final bool fromPending = rel == pendingFile;
      final Recording? r = Recording.fromJson(<String, dynamic>{
        'id': newId(),
        'name': '$takeWord ${takeNumber()}',
        'file': rel,
        'format': ext == 'm4a' ? 'aac' : ext,
        'durationMs': 0,
        'createdAt': (fromPending ? jsonDate(pending!, 'startedAt') : null)?.toIso8601String() ?? _fileTime(rel) ?? clock.now().toIso8601String(),
        'folder': fromPending ? jsonText(pending!, 'folder', max: 60) : '',
        'instrumentId': fromPending ? jsonText(pending!, 'instrumentId', max: 40, fallback: instrumentId) : instrumentId,
        'recovered': true,
      });
      if (r != null) {
        recordings.insert(0, r);
        known.add(rel);
        n++;
      }
    }
    if (pending != null) {
      await store.delete(TakeRecorder.pendingFile);
    }
    if (n > 0) {
      recordings.sort((Recording a, Recording b) => b.createdAt.compareTo(a.createdAt));
      recoveredTakes += n;
      await saveRecordings();
    }
    return n;
  }

  /// Hora de la toma según el nombre del archivo (milisegundos de cuando
  /// empezó), si lo tiene.
  static String? _fileTime(String rel) {
    final RegExpMatch? m = RegExp(r'/(\d{12,14})\.[a-z0-9]+$').firstMatch(rel);
    if (m == null) {
      return null;
    }
    final int? ms = int.tryParse(m.group(1)!);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();
  }
}
