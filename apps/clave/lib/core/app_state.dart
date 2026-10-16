import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import 'storage.dart';

/// Datos de la app: preajustes, setlists, grabaciones y registro de práctica.
/// Todo se guarda en archivos JSON locales.
class AppState extends ChangeNotifier {
  AppState(this.store);

  final JsonStore store;
  final List<Preset> presets = <Preset>[];
  final List<Setlist> setlists = <Setlist>[];
  final List<Recording> recordings = <Recording>[];
  final List<PracticeSession> sessions = <PracticeSession>[];
  PracticeSession? _active;
  Timer? _sessionTimer;
  bool loaded = false;

  Future<void> load() async {
    final Map<String, dynamic>? p = await store.readJson('presets.json');
    presets
      ..clear()
      ..addAll(((p?['presets'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Preset.fromJson));
    setlists
      ..clear()
      ..addAll(((p?['setlists'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Setlist.fromJson));
    final Map<String, dynamic>? r = await store.readJson('recordings.json');
    recordings
      ..clear()
      ..addAll(((r?['recordings'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Recording.fromJson));
    recordings.sort((Recording a, Recording b) => b.createdAt.compareTo(a.createdAt));
    final Map<String, dynamic>? s = await store.readJson('practice.json');
    sessions
      ..clear()
      ..addAll(((s?['sessions'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(PracticeSession.fromJson));
    loaded = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ preajustes

  Future<void> savePresets() async {
    await store.writeJson('presets.json', <String, dynamic>{
      'presets': presets.map((Preset p) => p.toJson()).toList(),
      'setlists': setlists.map((Setlist s) => s.toJson()).toList(),
    });
    notifyListeners();
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

  Future<Setlist> addSetlist(String name) async {
    final Setlist s = Setlist(id: newId(), name: name);
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

  /// Importa sin duplicar ids. Devuelve cuántos preajustes nuevos entraron.
  Future<int> importPresets(Map<String, dynamic> data) async {
    int n = 0;
    final Set<String> ids = presets.map((Preset p) => p.id).toSet();
    for (final Map<String, dynamic> j in ((data['presets'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>()) {
      final Preset p = Preset.fromJson(j);
      if (ids.add(p.id)) {
        presets.add(p);
        n += 1;
      }
    }
    final Set<String> sids = setlists.map((Setlist s) => s.id).toSet();
    for (final Map<String, dynamic> j in ((data['setlists'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>()) {
      final Setlist s = Setlist.fromJson(j);
      if (sids.add(s.id)) {
        setlists.add(s);
      }
    }
    await savePresets();
    return n;
  }

  // ------------------------------------------------------------ grabaciones

  Future<void> saveRecordings() async {
    await store.writeJson('recordings.json', <String, dynamic>{'recordings': recordings.map((Recording r) => r.toJson()).toList()});
    notifyListeners();
  }

  Future<void> addRecording(Recording r) async {
    recordings.insert(0, r);
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

  // ------------------------------------------------------------ práctica

  /// Marca que una herramienta está en uso activo. Las sesiones se cierran
  /// solas tras 90 segundos sin actividad.
  void touchPractice(String tool, String instrumentId) {
    final DateTime now = DateTime.now();
    final PracticeSession? a = _active;
    if (a != null && a.tool == tool && a.instrumentId == instrumentId) {
      a.end = now;
    } else {
      if (a != null) {
        _closeActive();
      }
      _active = PracticeSession(id: newId(), start: now, end: now, tool: tool, instrumentId: instrumentId);
    }
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(seconds: 90), _closeActive);
  }

  void _closeActive() {
    final PracticeSession? a = _active;
    _active = null;
    _sessionTimer?.cancel();
    if (a == null) {
      return;
    }
    if (a.seconds >= 10) {
      sessions.add(a);
      unawaited(savePractice());
    }
  }

  /// Cierra la sesión activa (al salir de la herramienta o de la app).
  void endPractice() => _closeActive();

  Future<void> savePractice() async {
    // Se conserva un año de historial.
    final DateTime limit = DateTime.now().subtract(const Duration(days: 366));
    sessions.removeWhere((PracticeSession s) => s.end.isBefore(limit));
    await store.writeJson('practice.json', <String, dynamic>{'sessions': sessions.map((PracticeSession s) => s.toJson()).toList()});
    notifyListeners();
  }

  /// Segundos practicados en un día (incluye la sesión activa).
  int secondsOn(DateTime day) {
    int total = 0;
    for (final PracticeSession s in <PracticeSession>[...sessions, if (_active != null) _active!]) {
      if (_sameDay(s.start, day)) {
        total += s.seconds;
      }
    }
    return total;
  }

  int secondsBetween(DateTime from, DateTime to) {
    int total = 0;
    for (final PracticeSession s in <PracticeSession>[...sessions, if (_active != null) _active!]) {
      if (!s.start.isBefore(from) && s.start.isBefore(to)) {
        total += s.seconds;
      }
    }
    return total;
  }

  /// Días seguidos (hasta hoy o ayer) con al menos [minSeconds] de práctica.
  int streak({int minSeconds = 300}) {
    int n = 0;
    DateTime day = DateTime.now();
    if (secondsOn(day) < minSeconds) {
      day = day.subtract(const Duration(days: 1));
    }
    while (secondsOn(day) >= minSeconds) {
      n += 1;
      day = day.subtract(const Duration(days: 1));
      if (n > 3660) {
        break;
      }
    }
    return n;
  }

  Map<String, int> secondsByInstrument({int days = 30}) {
    final DateTime from = DateTime.now().subtract(Duration(days: days));
    final Map<String, int> out = <String, int>{};
    for (final PracticeSession s in sessions) {
      if (s.start.isAfter(from)) {
        out[s.instrumentId] = (out[s.instrumentId] ?? 0) + s.seconds;
      }
    }
    return out;
  }

  Map<String, int> secondsByTool({int days = 30}) {
    final DateTime from = DateTime.now().subtract(Duration(days: days));
    final Map<String, int> out = <String, int>{};
    for (final PracticeSession s in sessions) {
      if (s.start.isAfter(from)) {
        out[s.tool] = (out[s.tool] ?? 0) + s.seconds;
      }
    }
    return out;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}
