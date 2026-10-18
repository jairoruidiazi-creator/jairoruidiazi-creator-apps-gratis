import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
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

  static const RoundFeedback none = RoundFeedback(event: MasteryEvent.none, sticker: null, skillId: null);

  final MasteryEvent event;
  final StickerAward? sticker;

  /// Habilidad lograda en esta ronda, si se dominó el último nivel del tramo.
  final String? skillId;
}

/// Un aviso para el panel de adultos (por ejemplo, un archivo dañado).
class StorageNotice {
  const StorageNotice(this.texto, this.fecha);

  final String texto;
  final DateTime fecha;

  Map<String, dynamic> toJson() => <String, dynamic>{'texto': texto, 'fecha': fecha.toIso8601String()};

  static StorageNotice fromJson(Map<String, dynamic> j) => StorageNotice((j['texto'] as String?) ?? '', DateTime.tryParse((j['fecha'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0));
}

/// Estado de la app: perfiles, progreso, grupos, sesión de juego y descanso.
///
/// El tiempo de juego se mide por perfil y por sesión, solo con la app en
/// primer plano. Una sesión termina tras [sessionGap] sin jugar (app cerrada,
/// en segundo plano o en la pantalla de perfiles). Al llegar al límite de la
/// sesión empieza un descanso de [restLength] que se guarda en disco: cerrar y
/// abrir la app no lo salta. Toda la hora sale de `clock` (package:clock) para
/// poder probarlo con un reloj falso.
class AppState extends ChangeNotifier {
  AppState(this.store);

  final JsonStore store;
  final List<Profile> profiles = <Profile>[];
  final List<ClassGroup> groups = <ClassGroup>[];
  final Map<String, ProfileProgress> _progress = <String, ProfileProgress>{};

  /// Avisos de almacenamiento pendientes para el adulto.
  final List<StorageNotice> notices = <StorageNotice>[];

  Profile? current;
  bool loaded = false;

  /// Límite de la sesión en minutos (0 = sin límite). La app lo enlaza a los ajustes.
  int Function() sessionLimitMinutes = () => 0;

  /// Se llama cuando el límite de la sesión hace empezar un descanso.
  VoidCallback? onRestStarted;

  static const Duration sessionGap = Duration(minutes: 10);
  static const Duration restLength = Duration(minutes: 10);
  static const Duration extraTime = Duration(minutes: 10);

  static const String _profilesFile = 'profiles.json';
  static const String _groupsFile = 'groups.json';
  static const String _noticesFile = 'avisos.json';

  bool _foreground = true;
  DateTime? _countingSince;
  Timer? _tick;
  int _ticks = 0;

  static const List<String> stickerPool = <String>[
    '2b50', '1f31f', '1f308', '1f984', '1f98b', '1f41e', '1f338', '1f33b', '1f34e', '1f353',
    '1f680', '1f3a8', '1f3b8', '1f3c6', '1f947', '1f4a1', '1f40b', '1f42c', '1f99c', '1f981',
    '1f43c', '1f428', '1f9a5', '1f999', '1f409', '1f96d', '1f349', '1f369', '1f9c1', '1f3c0',
    '26bd', '1f3af', '1f3a2', '1f6f8', '1f30d', '1f30b', '1f3dd', '1f41d', '1f98e', '1f419',
  ];

  // ---------------------------------------------------------------- carga

  /// Lee perfiles, grupos y el progreso de todos los perfiles. Nunca lanza:
  /// lo que no se pudo leer queda como aviso para el panel de adultos.
  Future<void> load() async {
    profiles.clear();
    groups.clear();
    _progress.clear();
    notices.clear();
    try {
      final Map<String, dynamic>? avisos = await store.readJson(_noticesFile);
      for (final dynamic e in (avisos?['avisos'] as List<dynamic>?) ?? <dynamic>[]) {
        if (e is Map<String, dynamic>) {
          notices.add(StorageNotice.fromJson(e));
        }
      }
    } catch (e) {
      debugPrint('No se pudieron leer los avisos: $e');
    }
    final List<StorageNotice> nuevos = <StorageNotice>[];

    final JsonRead pr = await _safeRead(_profilesFile);
    _noteRead(pr, 'la lista de perfiles', nuevos);
    for (final dynamic e in (pr.data?['profiles'] as List<dynamic>?) ?? <dynamic>[]) {
      try {
        profiles.add(Profile.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        nuevos.add(StorageNotice('Se ignoró un perfil que no se pudo leer.', clock.now()));
      }
    }
    final JsonRead gr = await _safeRead(_groupsFile);
    _noteRead(gr, 'los grupos del modo docente', nuevos);
    for (final dynamic e in (gr.data?['groups'] as List<dynamic>?) ?? <dynamic>[]) {
      try {
        groups.add(ClassGroup.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        nuevos.add(StorageNotice('Se ignoró un grupo que no se pudo leer.', clock.now()));
      }
    }
    final DateTime now = clock.now();
    for (final Profile p in profiles) {
      final String rel = 'progress/${p.id}.json';
      final JsonRead r = await _safeRead(rel);
      _noteRead(r, 'el avance de ${p.nombre}', nuevos);
      ProfileProgress prog = ProfileProgress();
      if (r.data != null) {
        try {
          prog = ProfileProgress.fromJson(r.data!);
        } catch (_) {
          // JSON válido pero con un formato que no se entiende: se aparta tal
          // cual (no se pisa) y se empieza de cero, con aviso.
          final String aside = await _setAside(rel);
          nuevos.add(StorageNotice('No se pudo interpretar el avance de ${p.nombre}; el archivo se guardó aparte ($aside) y su avance empezó de cero.', now));
        }
      }
      _progress[p.id] = prog;
      if (_closeStale(prog, now)) {
        await _saveProgressSafe(p.id);
      }
    }
    if (nuevos.isNotEmpty) {
      notices.addAll(nuevos);
      await _saveNotices();
    }
    loaded = true;
    notifyListeners();
  }

  Future<JsonRead> _safeRead(String rel) async {
    try {
      return await store.readJsonSafe(rel);
    } catch (e) {
      debugPrint('No se pudo leer $rel: $e');
      return const JsonRead(null, ReadOutcome.missing);
    }
  }

  Future<String> _setAside(String rel) async {
    try {
      final Map<String, dynamic>? data = await store.readJson(rel);
      final String name = '$rel.corrupto-${clock.now().millisecondsSinceEpoch}';
      if (data != null) {
        await store.writeJson(name, data);
      }
      await store.delete(rel);
      return name;
    } catch (_) {
      return rel;
    }
  }

  void _noteRead(JsonRead r, String what, List<StorageNotice> out) {
    final DateTime now = clock.now();
    if (r.outcome == ReadOutcome.recovered) {
      out.add(StorageNotice('Se recuperó $what desde la copia de seguridad, porque el archivo estaba dañado.', now));
    } else if (r.outcome == ReadOutcome.corrupt) {
      final String donde = r.asidePath == null ? '' : ' (quedó guardado aparte como ${r.asidePath!.split(RegExp(r'[\\/]')).last})';
      out.add(StorageNotice('No se pudo leer $what: el archivo y su copia estaban dañados$donde. Se empezó de cero.', now));
    }
  }

  Future<void> _saveNotices({bool sinRastro = false}) async {
    try {
      await store.writeJson(_noticesFile, <String, dynamic>{'avisos': notices.map((StorageNotice n) => n.toJson()).toList()}, sinRastro: sinRastro);
    } catch (e) {
      debugPrint('No se pudieron guardar los avisos: $e');
    }
  }

  /// El adulto leyó los avisos.
  Future<void> dismissNotices() async {
    notices.clear();
    await _saveNotices();
    notifyListeners();
  }

  Future<void> _saveProfiles({bool sinRastro = false}) async {
    await store.writeJson(_profilesFile, <String, dynamic>{
      'profiles': profiles.map((Profile p) => p.toJson()).toList(),
    }, sinRastro: sinRastro);
  }

  Future<void> _saveGroups({bool sinRastro = false}) async {
    await store.writeJson(_groupsFile, <String, dynamic>{
      'groups': groups.map((ClassGroup g) => g.toJson()).toList(),
    }, sinRastro: sinRastro);
  }

  String _newId() {
    final Random r = Random();
    final int t = clock.now().millisecondsSinceEpoch;
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
      createdAt: clock.now(),
    );
    profiles.add(p);
    _progress[p.id] = ProfileProgress();
    await _saveProfiles();
    notifyListeners();
    return p;
  }

  Future<void> updateProfile(Profile p) async {
    await _saveProfiles();
    notifyListeners();
  }

  /// Borra el perfil, su avance y sus dibujos.
  /// Borra un perfil y todo lo suyo: su nombre y fecha de nacimiento (de la
  /// lista de perfiles y de su respaldo), su avance con su respaldo y sus
  /// copias dañadas apartadas, sus dibujos, su lugar en los grupos, las
  /// copias dañadas de la lista de perfiles o de grupos que lo incluyan y
  /// los avisos del panel que lo nombran. Es lo que dice la política.
  Future<void> deleteProfile(String id) async {
    Profile? borrado;
    for (final Profile p in profiles) {
      if (p.id == id) {
        borrado = p;
      }
    }
    if (current?.id == id) {
      _stopCounting();
      current = null;
    }
    profiles.removeWhere((Profile p) => p.id == id);
    _progress.remove(id);
    for (final ClassGroup g in groups) {
      g.profileIds.remove(id);
    }
    await store.delete('progress/$id.json');
    try {
      await store.deleteAsides('progress/$id.json');
      await store.deleteDir('drawings/$id');
    } catch (e) {
      debugPrint('No se pudieron borrar los archivos de $id: $e');
    }
    // El respaldo (.bak) también se reescribe: el perfil borrado no puede
    // volver si un día hay que recuperar el archivo.
    await _saveProfiles(sinRastro: true);
    await _saveGroups(sinRastro: true);
    // Copias dañadas apartadas que todavía lo incluyen: no se pueden
    // reescribir sin él (están dañadas), así que se borran, y se avisa.
    int copias = 0;
    try {
      copias += await store.deleteAsides(_profilesFile, si: (String t) => t.contains(id));
      copias += await store.deleteAsides(_groupsFile, si: (String t) => t.contains(id));
    } catch (e) {
      debugPrint('No se pudieron borrar las copias dañadas: $e');
    }
    final String? nombre = borrado?.nombre;
    final int antes = notices.length;
    if (nombre != null && nombre.trim().isNotEmpty && !profiles.any((Profile p) => p.nombre == nombre)) {
      final RegExp nombra = RegExp('(^|[^\\p{L}])${RegExp.escape(nombre)}(\$|[^\\p{L}])', unicode: true);
      notices.removeWhere((StorageNotice n) => nombra.hasMatch(n.texto));
    }
    if (copias > 0) {
      notices.add(StorageNotice('Se borraron copias dañadas de la lista de perfiles o de grupos que incluían al perfil borrado.', clock.now()));
    }
    if (notices.length != antes || copias > 0) {
      await _saveNotices(sinRastro: true);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- progreso

  /// Progreso de un perfil. Se carga completo en [load], así que nunca se
  /// devuelve un progreso vacío que luego se guarde encima del real.
  ProfileProgress progressOf(String profileId) {
    final ProfileProgress? p = _progress[profileId];
    if (p != null) {
      return p;
    }
    // Perfil desconocido (por ejemplo, borrado mientras una pantalla lo
    // mostraba): un progreso vacío que no se guarda en ningún lado.
    return ProfileProgress();
  }

  /// Igual que [progressOf]; se mantiene asíncrono por compatibilidad.
  Future<ProfileProgress> progressFor(String profileId) async => progressOf(profileId);

  ProfileProgress? get currentProgress => current == null ? null : progressOf(current!.id);

  Future<void> saveProgress(String profileId) async {
    final ProfileProgress? p = _progress[profileId];
    if (p == null) {
      return;
    }
    await store.writeJson('progress/$profileId.json', p.toJson());
  }

  Future<void> _saveProgressSafe(String profileId) async {
    try {
      await saveProgress(profileId);
    } catch (e) {
      debugPrint('No se pudo guardar el avance de $profileId: $e');
    }
  }

  /// Registra una ronda del perfil actual. [success] es "acertó al primer
  /// intento". Los juegos libres solo cuentan como actividad de la sesión: no
  /// tienen niveles, ni aciertos, ni habilidades.
  Future<RoundFeedback> recordRound(GameDef game, AgeBand band, bool success) async {
    final Profile? p = current;
    if (p == null || !_progress.containsKey(p.id)) {
      return RoundFeedback.none;
    }
    if (!game.roundBased) {
      await recordActivity(game);
      return RoundFeedback.none;
    }
    final ProfileProgress prog = _progress[p.id]!;
    final SessionLog? s = prog.live;
    final MasteryState m = prog.masteryFor(game.id, band);
    final int levelBefore = m.level;
    final MasteryEvent event = m.record(success, game.levelsFor(band), rule: game.mastery);

    StickerAward? sticker;
    String? skillId;
    if (event.completedLevel) {
      final int completedLevel = levelBefore;
      if (!prog.hasSticker(game.id, band, completedLevel)) {
        final String emoji = stickerPool[(game.id.codeUnits.fold<int>(0, (int a, int b) => a + b) + band.index * 7 + completedLevel * 13) % stickerPool.length];
        sticker = StickerAward(gameId: game.id, band: band, level: completedLevel, emoji: emoji, date: clock.now());
        prog.stickers.add(sticker);
      }
      if (completedLevel == game.levelsFor(band)) {
        final String? sid = game.skillFor(band);
        if (sid != null && !prog.skillsAchieved.containsKey(sid)) {
          prog.skillsAchieved[sid] = clock.now();
          skillId = sid;
        }
      }
    }

    if (s != null) {
      s.rounds += 1;
      if (success) {
        s.correct += 1;
      }
      s.gameRounds[game.id] = (s.gameRounds[game.id] ?? 0) + 1;
    }
    await _saveProgressSafe(p.id);
    notifyListeners();
    return RoundFeedback(event: event, sticker: sticker, skillId: skillId);
  }

  /// Actividad libre (colorear libre, dibujo, pixel libre): cuenta en la
  /// sesión como juego usado, sin rondas evaluadas ni aciertos.
  Future<void> recordActivity(GameDef game) async {
    final Profile? p = current;
    if (p == null || !_progress.containsKey(p.id)) {
      return;
    }
    final SessionLog? s = _progress[p.id]!.live;
    if (s != null) {
      s.gameRounds[game.id] = (s.gameRounds[game.id] ?? 0) + 1;
    }
    await _saveProgressSafe(p.id);
    notifyListeners();
  }

  /// Guarda una marca personal si supera la anterior. Devuelve true si es
  /// una marca nueva que celebrar: nunca con cero aciertos (la primera
  /// carrera sin aciertos se guarda, pero no se celebra).
  Future<bool> saveRecord(String key, int value) async {
    final Profile? p = current;
    if (p == null || !_progress.containsKey(p.id)) {
      return false;
    }
    final ProfileProgress prog = _progress[p.id]!;
    final int? before = prog.records[key];
    if (before != null && before >= value) {
      return false;
    }
    prog.records[key] = value;
    await _saveProgressSafe(p.id);
    notifyListeners();
    return value > 0;
  }

  int? recordOf(String key) {
    final Profile? p = current;
    return p == null ? null : progressOf(p.id).records[key];
  }

  // ---------------------------------------------------------------- sesiones

  /// Cambia de jugador. La sesión del anterior queda en pausa (y se cierra
  /// sola si pasan [sessionGap] sin volver).
  Future<void> selectProfile(Profile? p) async {
    if (current?.id == p?.id) {
      if (p != null) {
        _openOrResume(p);
      }
      notifyListeners();
      return;
    }
    final Profile? before = current;
    _stopCounting();
    current = p;
    if (before != null) {
      await _saveProgressSafe(before.id);
    }
    if (p != null) {
      _openOrResume(p);
      await _saveProgressSafe(p.id);
    }
    notifyListeners();
  }

  /// Cierra la sesión si lleva [sessionGap] sin jugar, y el descanso si terminó.
  /// Devuelve true si cambió algo.
  bool _closeStale(ProfileProgress prog, DateTime now) {
    bool changed = false;
    final DateTime? rest = prog.restUntil;
    if (rest != null) {
      if (!rest.isAfter(now)) {
        prog.restUntil = null;
        changed = true;
      } else if (rest.isAfter(now.add(restLength))) {
        // El reloj del teléfono se atrasó: el descanso no puede durar más.
        prog.restUntil = now.add(restLength);
        changed = true;
      }
    }
    final SessionLog? live = prog.live;
    if (live != null && prog.restUntil == null && now.difference(live.lastActive) >= sessionGap) {
      if (live.meaningful) {
        prog.addSession(live);
      }
      prog.live = null;
      changed = true;
    }
    return changed;
  }

  void _openOrResume(Profile p) {
    final ProfileProgress? prog = _progress[p.id];
    if (prog == null) {
      return;
    }
    final DateTime now = clock.now();
    _closeStale(prog, now);
    if (isResting(p.id)) {
      return;
    }
    prog.live ??= SessionLog(start: now, lastActive: now);
    _startCounting();
  }

  void _startCounting() {
    final Profile? p = current;
    if (!_foreground || p == null) {
      return;
    }
    final ProfileProgress? prog = _progress[p.id];
    if (prog == null || prog.live == null || isResting(p.id)) {
      return;
    }
    if (_countingSince == null) {
      _countingSince = clock.now();
      prog.live!.lastActive = _countingSince!;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 15), (_) => unawaited(tick()));
  }

  void _accumulate() {
    final Profile? p = current;
    final DateTime? since = _countingSince;
    if (p == null || since == null) {
      return;
    }
    final SessionLog? s = _progress[p.id]?.live;
    if (s == null) {
      return;
    }
    final DateTime now = clock.now();
    final int secs = now.difference(since).inSeconds;
    if (secs > 0) {
      s.seconds += secs;
      _countingSince = since.add(Duration(seconds: secs));
    }
    s.lastActive = now;
  }

  void _stopCounting() {
    _accumulate();
    _countingSince = null;
    _tick?.cancel();
    _tick = null;
  }

  /// Si el reloj de la sesión está corriendo (app en primer plano, con jugador).
  bool get counting => _countingSince != null;

  /// La app pasó a segundo plano (o quedó inactiva): se deja de contar.
  Future<void> pauseClock() async {
    _foreground = false;
    final bool wasCounting = counting;
    _stopCounting();
    final Profile? p = current;
    if (p != null && wasCounting) {
      await _saveProgressSafe(p.id);
    }
  }

  /// La app volvió al primer plano.
  Future<void> resumeClock() async {
    _foreground = true;
    final Profile? p = current;
    if (p == null) {
      return;
    }
    final ProfileProgress prog = progressOf(p.id);
    final bool changed = _closeStale(prog, clock.now());
    _openOrResume(p);
    if (changed) {
      await _saveProgressSafe(p.id);
    }
    notifyListeners();
  }

  /// Un paso del reloj: acumula, revisa el límite y guarda cada minuto.
  Future<void> tick() async {
    final Profile? p = current;
    if (p == null || !counting) {
      return;
    }
    _accumulate();
    _ticks += 1;
    if (limitReached) {
      await startRest();
      return;
    }
    if (_ticks % 4 == 0) {
      await _saveProgressSafe(p.id);
    }
  }

  /// Segundos jugados en la sesión abierta del perfil actual.
  int get sessionSeconds {
    final Profile? p = current;
    if (p == null) {
      return 0;
    }
    final SessionLog? s = progressOf(p.id).live;
    if (s == null) {
      return 0;
    }
    final DateTime? since = _countingSince;
    return s.seconds + (since == null ? 0 : clock.now().difference(since).inSeconds);
  }

  /// Si la sesión actual ya usó su tiempo (con el extra que dio un adulto).
  bool get limitReached {
    final int limit = sessionLimitMinutes();
    final Profile? p = current;
    if (limit <= 0 || p == null) {
      return false;
    }
    final SessionLog? s = progressOf(p.id).live;
    if (s == null) {
      return false;
    }
    return sessionSeconds >= limit * 60 + s.extraSeconds;
  }

  /// Revisa el límite ahora (la pantalla lo llama al abrir un juego).
  Future<void> checkLimit() async {
    final Profile? p = current;
    if (p != null && counting) {
      _accumulate();
    }
    if (p != null && limitReached && !isResting(p.id)) {
      await startRest();
    }
  }

  bool isResting(String profileId) {
    final DateTime? until = _progress[profileId]?.restUntil;
    return until != null && until.isAfter(clock.now());
  }

  /// Tiempo que le falta al descanso del perfil (cero si no descansa).
  Duration restRemaining(String profileId) {
    final DateTime? until = _progress[profileId]?.restUntil;
    if (until == null) {
      return Duration.zero;
    }
    final Duration d = until.difference(clock.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// Otro perfil que esté en su descanso (para pedir la puerta al cambiar).
  Profile? restingProfileOtherThan(String profileId) {
    for (final Profile p in profiles) {
      if (p.id != profileId && isResting(p.id)) {
        return p;
      }
    }
    return null;
  }

  /// Empieza el descanso del perfil actual: se deja de contar y se guarda
  /// hasta cuándo dura, para que cerrar y abrir la app no lo salte.
  Future<void> startRest() async {
    final Profile? p = current;
    if (p == null) {
      return;
    }
    _stopCounting();
    final ProfileProgress prog = progressOf(p.id);
    prog.restUntil = clock.now().add(restLength);
    await _saveProgressSafe(p.id);
    notifyListeners();
    onRestStarted?.call();
  }

  /// El descanso terminó: la sesión anterior se cierra y empieza otra.
  Future<void> finishRest() async {
    final Profile? p = current;
    if (p == null) {
      return;
    }
    final ProfileProgress prog = progressOf(p.id);
    if (isResting(p.id)) {
      return;
    }
    prog.restUntil = null;
    final SessionLog? live = prog.live;
    if (live != null) {
      if (live.meaningful) {
        prog.addSession(live);
      }
      prog.live = null;
    }
    _openOrResume(p);
    await _saveProgressSafe(p.id);
    notifyListeners();
  }

  /// Un adulto da [extraTime] más: se acaba el descanso y la sesión sigue.
  Future<void> grantExtraTime() async {
    final Profile? p = current;
    if (p == null) {
      return;
    }
    final ProfileProgress prog = progressOf(p.id);
    prog.restUntil = null;
    final DateTime now = clock.now();
    prog.live ??= SessionLog(start: now, lastActive: now);
    prog.live!.extraSeconds += extraTime.inSeconds;
    // La sesión sigue desde ahora, aunque el adulto tardara en venir.
    prog.live!.lastActive = now;
    _openOrResume(p);
    await _saveProgressSafe(p.id);
    notifyListeners();
  }

  /// Cierra ya la sesión abierta del perfil actual (idempotente).
  Future<void> endSession() async {
    final Profile? p = current;
    _stopCounting();
    if (p == null) {
      return;
    }
    final ProfileProgress? prog = _progress[p.id];
    final SessionLog? live = prog?.live;
    if (prog == null || live == null) {
      return;
    }
    if (live.meaningful) {
      prog.addSession(live);
    }
    prog.live = null;
    await _saveProgressSafe(p.id);
    notifyListeners();
  }

  // ---------------------------------------------------------------- grupos

  Future<ClassGroup> addGroup(String nombre) async {
    final ClassGroup g = ClassGroup(id: _newId(), nombre: nombre, createdAt: clock.now());
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

  /// Todos los perfiles, grupos y avances, tal como están guardados.
  Future<Map<String, dynamic>> exportAll() async {
    final Map<String, dynamic> progress = <String, dynamic>{};
    for (final Profile p in profiles) {
      progress[p.id] = progressOf(p.id).toJson();
    }
    return <String, dynamic>{
      'app': 'pilas',
      'version': 2,
      'exportedAt': clock.now().toIso8601String(),
      'profiles': profiles.map((Profile p) => p.toJson()).toList(),
      'groups': groups.map((ClassGroup g) => g.toJson()).toList(),
      'progress': progress,
    };
  }

  /// Importa perfiles, grupos y avance de otra tableta. Un perfil que ya
  /// existe (mismo id) conserva sus datos y junta el avance importado
  /// ([ProfileProgress.mergeFrom]: sesiones, pegatinas y habilidades sin
  /// repetir, y de cada juego el registro más avanzado); los
  /// grupos con el mismo id juntan sus integrantes. Lanza [FormatException]
  /// con un mensaje para el adulto si el archivo no sirve.
  Future<int> importAll(Map<String, dynamic> data) async {
    if (data['app'] != 'pilas') {
      throw const FormatException('El archivo no es de Pilas.');
    }
    final List<Profile> nuevos = <Profile>[];
    final Map<String, ProfileProgress> avances = <String, ProfileProgress>{};
    final List<ClassGroup> grupos = <ClassGroup>[];
    try {
      final List<dynamic> ps = (data['profiles'] as List<dynamic>?) ?? <dynamic>[];
      final Map<String, dynamic> prog = (data['progress'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      for (final dynamic e in ps) {
        final Profile p = Profile.fromJson(e as Map<String, dynamic>);
        nuevos.add(p);
        final dynamic pj = prog[p.id];
        if (pj is Map<String, dynamic>) {
          avances[p.id] = ProfileProgress.fromJson(pj);
        }
      }
      for (final dynamic e in (data['groups'] as List<dynamic>?) ?? <dynamic>[]) {
        grupos.add(ClassGroup.fromJson(e as Map<String, dynamic>));
      }
    } catch (e) {
      throw const FormatException('El archivo está incompleto o tiene un formato que Pilas no reconoce.');
    }
    for (final Profile p in nuevos) {
      final Profile? existing = profileById(p.id);
      if (existing == null) {
        profiles.add(p);
        _progress[p.id] = avances[p.id] ?? ProfileProgress();
      } else {
        final ProfileProgress mine = progressOf(p.id);
        final ProfileProgress? theirs = avances[p.id];
        if (theirs != null) {
          mine.mergeFrom(theirs);
        }
        _progress[p.id] = mine;
      }
      await saveProgress(p.id);
    }
    for (final ClassGroup g in grupos) {
      ClassGroup? mine;
      for (final ClassGroup x in groups) {
        if (x.id == g.id) {
          mine = x;
        }
      }
      if (mine == null) {
        groups.add(g);
      } else {
        for (final String id in g.profileIds) {
          if (!mine.profileIds.contains(id)) {
            mine.profileIds.add(id);
          }
        }
      }
    }
    await _saveProfiles();
    await _saveGroups();
    notifyListeners();
    return nuevos.length;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }
}
