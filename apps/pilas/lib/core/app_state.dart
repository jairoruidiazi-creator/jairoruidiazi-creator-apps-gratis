import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/game_def.dart';
import '../engine/mastery.dart';
import '../model/age_band.dart';
import '../model/group.dart';
import '../model/profile.dart';
import '../model/progress.dart';
import 'storage.dart';

/// Qué pasó al registrar una ronda: sirve para que la pantalla celebre lo justo.
class RoundFeedback {
  const RoundFeedback({required this.event, required this.sticker, required this.skillId});

  final MasteryEvent event;
  final StickerAward? sticker;

  /// Habilidad lograda en esta ronda, si se completó el último nivel del tramo.
  final String? skillId;
}

/// Estado de la app: perfiles, progreso, grupos y sesión activa.
class AppState extends ChangeNotifier {
  AppState(this.store);

  final JsonStore store;
  final List<Profile> profiles = <Profile>[];
  final List<ClassGroup> groups = <ClassGroup>[];
  final Map<String, ProfileProgress> _progress = <String, ProfileProgress>{};

  Profile? current;
  SessionLog? _session;
  Timer? _tick;
  DateTime? _lastTick;
  bool loaded = false;

  /// Minutos extra concedidos por un adulto en la sesión de hoy.
  int extraMinutes = 0;

  static const String _profilesFile = 'profiles.json';
  static const String _groupsFile = 'groups.json';

  static const List<String> stickerPool = <String>[
    '2b50', '1f31f', '1f308', '1f984', '1f98b', '1f41e', '1f338', '1f33b', '1f34e', '1f353',
    '1f680', '1f3a8', '1f3b8', '1f3c6', '1f947', '1f4a1', '1f40b', '1f42c', '1f99c', '1f981',
    '1f43c', '1f428', '1f9a5', '1f999', '1f409', '1f96d', '1f349', '1f369', '1f9c1', '1f3c0',
    '26bd', '1f3af', '1f3a2', '1f6f8', '1f30d', '1f30b', '1f3dd', '1f41d', '1f98e', '1f419',
  ];

  // ---------------------------------------------------------------- carga

  Future<void> load() async {
    final Map<String, dynamic>? pj = await store.readJson(_profilesFile);
    profiles.clear();
    if (pj != null) {
      final List<dynamic> list = (pj['profiles'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic e in list) {
        profiles.add(Profile.fromJson(e as Map<String, dynamic>));
      }
    }
    final Map<String, dynamic>? gj = await store.readJson(_groupsFile);
    groups.clear();
    if (gj != null) {
      final List<dynamic> list = (gj['groups'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic e in list) {
        groups.add(ClassGroup.fromJson(e as Map<String, dynamic>));
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _saveProfiles() async {
    await store.writeJson(_profilesFile, <String, dynamic>{
      'profiles': profiles.map((Profile p) => p.toJson()).toList(),
    });
  }

  Future<void> _saveGroups() async {
    await store.writeJson(_groupsFile, <String, dynamic>{
      'groups': groups.map((ClassGroup g) => g.toJson()).toList(),
    });
  }

  String _newId() {
    final Random r = Random();
    final int t = DateTime.now().millisecondsSinceEpoch;
    return '${t.toRadixString(36)}${r.nextInt(1 << 20).toRadixString(36)}';
  }

  // ---------------------------------------------------------------- perfiles

  Profile? profileById(String? id) {
    if (id == null) {
      return null;
    }
    for (final Profile p in profiles) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  Future<Profile> addProfile({
    required String nombre,
    required String avatar,
    required int birthYear,
    required int birthMonth,
    AgeBand? bandOverride,
    bool leftHanded = false,
  }) async {
    final Profile p = Profile(
      id: _newId(),
      nombre: nombre,
      avatar: avatar,
      birthYear: birthYear,
      birthMonth: birthMonth,
      bandOverride: bandOverride,
      leftHanded: leftHanded,
    );
    profiles.add(p);
    await _saveProfiles();
    notifyListeners();
    return p;
  }

  Future<void> updateProfile(Profile p) async {
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    profiles.removeWhere((Profile p) => p.id == id);
    _progress.remove(id);
    for (final ClassGroup g in groups) {
      g.profileIds.remove(id);
    }
    if (current?.id == id) {
      current = null;
    }
    await store.delete('progress/$id.json');
    await _saveProfiles();
    await _saveGroups();
    notifyListeners();
  }

  Future<void> selectProfile(Profile? p) async {
    if (current?.id != p?.id) {
      await endSession();
    }
    current = p;
    extraMinutes = 0;
    if (p != null) {
      await progressFor(p.id);
      startSession();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- progreso

  Future<ProfileProgress> progressFor(String profileId) async {
    final ProfileProgress? cached = _progress[profileId];
    if (cached != null) {
      return cached;
    }
    final Map<String, dynamic>? json = await store.readJson('progress/$profileId.json');
    final ProfileProgress p = json == null ? ProfileProgress() : ProfileProgress.fromJson(json);
    _progress[profileId] = p;
    return p;
  }

  /// Progreso ya cargado (vacío si todavía no se leyó).
  ProfileProgress progressOf(String profileId) {
    return _progress.putIfAbsent(profileId, () => ProfileProgress());
  }

  ProfileProgress? get currentProgress => current == null ? null : progressOf(current!.id);

  Future<void> saveProgress(String profileId) async {
    final ProfileProgress? p = _progress[profileId];
    if (p == null) {
      return;
    }
    await store.writeJson('progress/$profileId.json', p.toJson());
  }

  /// Registra una ronda del perfil actual y aplica la regla de dominio.
  Future<RoundFeedback> recordRound(GameDef game, AgeBand band, bool success) async {
    final Profile? p = current;
    if (p == null) {
      return const RoundFeedback(event: MasteryEvent.none, sticker: null, skillId: null);
    }
    final ProfileProgress prog = progressOf(p.id);
    final MasteryState m = prog.masteryFor(game.id, band);
    final int levelBefore = m.level;
    final MasteryEvent event = m.record(success, game.levelsFor(band));

    StickerAward? sticker;
    String? skillId;
    if (event.completedLevel) {
      final int completedLevel = levelBefore;
      if (!prog.hasSticker(game.id, band, completedLevel)) {
        final String emoji = stickerPool[(game.id.hashCode.abs() + band.index * 7 + completedLevel * 13) % stickerPool.length];
        sticker = StickerAward(gameId: game.id, band: band, level: completedLevel, emoji: emoji, date: DateTime.now());
        prog.stickers.add(sticker);
      }
      if (completedLevel == game.levelsFor(band)) {
        final String? sid = game.skillFor(band);
        if (sid != null && !prog.skillsAchieved.containsKey(sid)) {
          prog.skillsAchieved[sid] = DateTime.now();
          skillId = sid;
        }
      }
    }

    final SessionLog? s = _session;
    if (s != null) {
      s.rounds += 1;
      if (success) {
        s.correct += 1;
      }
      s.gameRounds[game.id] = (s.gameRounds[game.id] ?? 0) + 1;
    }
    await saveProgress(p.id);
    notifyListeners();
    return RoundFeedback(event: event, sticker: sticker, skillId: skillId);
  }

  // ---------------------------------------------------------------- sesiones

  void startSession() {
    if (_session != null) {
      return;
    }
    _session = SessionLog(start: DateTime.now());
    _lastTick = DateTime.now();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => _accumulate());
  }

  void _accumulate() {
    final SessionLog? s = _session;
    final DateTime? last = _lastTick;
    if (s == null || last == null) {
      return;
    }
    final DateTime now = DateTime.now();
    s.seconds += now.difference(last).inSeconds;
    _lastTick = now;
  }

  /// Segundos jugados en la sesión activa.
  int get sessionSeconds {
    final SessionLog? s = _session;
    final DateTime? last = _lastTick;
    if (s == null || last == null) {
      return 0;
    }
    return s.seconds + DateTime.now().difference(last).inSeconds;
  }

  /// Minutos jugados hoy por el perfil actual, sesión activa incluida.
  int get minutesToday {
    final Profile? p = current;
    if (p == null) {
      return 0;
    }
    final ProfileProgress prog = progressOf(p.id);
    return (prog.secondsOn(DateTime.now()) + sessionSeconds) ~/ 60;
  }

  Future<void> endSession() async {
    final Profile? p = current;
    final SessionLog? s = _session;
    _tick?.cancel();
    _tick = null;
    if (p == null || s == null) {
      _session = null;
      return;
    }
    _accumulate();
    _session = null;
    if (s.seconds >= 10 || s.rounds > 0) {
      final ProfileProgress prog = progressOf(p.id);
      prog.sessions.add(s);
      while (prog.sessions.length > 400) {
        prog.sessions.removeAt(0);
      }
      await saveProgress(p.id);
    }
    notifyListeners();
  }

  /// Guarda lo acumulado sin cerrar la sesión (al pasar a segundo plano).
  Future<void> flushSession() async {
    final Profile? p = current;
    final SessionLog? s = _session;
    if (p == null || s == null) {
      return;
    }
    _accumulate();
    final ProfileProgress prog = progressOf(p.id);
    if (!prog.sessions.contains(s)) {
      prog.sessions.add(s);
    }
    await saveProgress(p.id);
  }

  // ---------------------------------------------------------------- grupos

  Future<ClassGroup> addGroup(String nombre) async {
    final ClassGroup g = ClassGroup(id: _newId(), nombre: nombre);
    groups.add(g);
    await _saveGroups();
    notifyListeners();
    return g;
  }

  Future<void> updateGroup(ClassGroup g) async {
    await _saveGroups();
    notifyListeners();
  }

  Future<void> deleteGroup(String id) async {
    groups.removeWhere((ClassGroup g) => g.id == id);
    await _saveGroups();
    notifyListeners();
  }

  // ---------------------------------------------------------------- exportar

  Future<Map<String, dynamic>> exportAll() async {
    final Map<String, dynamic> progress = <String, dynamic>{};
    for (final Profile p in profiles) {
      final ProfileProgress prog = await progressFor(p.id);
      progress[p.id] = prog.toJson();
    }
    return <String, dynamic>{
      'app': 'pilas',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'profiles': profiles.map((Profile p) => p.toJson()).toList(),
      'groups': groups.map((ClassGroup g) => g.toJson()).toList(),
      'progress': progress,
    };
  }

  /// Importa perfiles y progreso. Los perfiles con el mismo id se reemplazan.
  Future<int> importAll(Map<String, dynamic> data) async {
    if (data['app'] != 'pilas') {
      throw const FormatException('El archivo no es de Pilas');
    }
    int count = 0;
    final List<dynamic> ps = (data['profiles'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> prog = (data['progress'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    for (final dynamic e in ps) {
      final Profile p = Profile.fromJson(e as Map<String, dynamic>);
      profiles.removeWhere((Profile x) => x.id == p.id);
      profiles.add(p);
      final dynamic pj = prog[p.id];
      if (pj is Map<String, dynamic>) {
        _progress[p.id] = ProfileProgress.fromJson(pj);
        await saveProgress(p.id);
      }
      count += 1;
    }
    final List<dynamic> gs = (data['groups'] as List<dynamic>?) ?? <dynamic>[];
    for (final dynamic e in gs) {
      final ClassGroup g = ClassGroup.fromJson(e as Map<String, dynamic>);
      groups.removeWhere((ClassGroup x) => x.id == g.id);
      groups.add(g);
    }
    await _saveProfiles();
    await _saveGroups();
    notifyListeners();
    return count;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
