import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../model/models.dart';
import 'storage.dart';

/// Un grupo de intervalos seguidos de una herramienta, para la lista de
/// "Últimas sesiones".
class SessionGroup {
  const SessionGroup({required this.tool, required this.instrumentId, required this.start, required this.end, required this.activeSeconds});

  final String tool;
  final String instrumentId;
  final DateTime start;
  final DateTime end;

  /// Segundos de actividad real (sin las pausas entre intervalos).
  final int activeSeconds;
}

/// Registro de práctica por intervalos de actividad de cada herramienta.
///
/// - El metrónomo cuenta mientras corre; el bordón, el teclado y los acordes
///   mientras suenan; la grabadora mientras graba ([start] y [stop]).
/// - El afinador cuenta mientras oye un tono estable de instrumento: cada
///   análisis así es un [ping], y el intervalo termina en el último ping si
///   pasan [pingTimeout] sin otro.
/// - El total de un día es la unión de los intervalos: dos herramientas a la
///   vez no cuentan doble. El desglose por herramienta suma el tiempo de
///   cada una.
/// - Dos intervalos de la misma herramienta separados por menos de
///   [mergeGap] se unen (las pausas entre notas del teclado).
/// - Los intervalos abiertos se guardan cada [checkpointEvery]; si el
///   sistema cierra la app, se pierde como mucho ese tiempo.
class PracticeLog extends ChangeNotifier {
  PracticeLog(this.store, {this.mergeGap = const Duration(seconds: 2), this.pingTimeout = const Duration(seconds: 2), this.checkpointEvery = const Duration(seconds: 30)});

  final JsonStore store;
  final Duration mergeGap;
  final Duration pingTimeout;
  final Duration checkpointEvery;

  static const String fileName = 'practice.json';

  /// Minutos al día para que el día cuente en la racha.
  static const int streakMinSeconds = 300;

  /// Días mínimos entre dos descansos dentro de una racha.
  static const int restSpacingDays = 7;

  /// Intervalos guardados y abiertos, en orden de inicio.
  final List<PracticeSession> sessions = <PracticeSession>[];
  final Map<String, _Open> _open = <String, _Open>{};
  Timer? _ticker;
  DateTime? _lastCheckpoint;
  bool loaded = false;

  Future<void> load() async {
    final Map<String, dynamic>? s = await store.readJson(fileName);
    sessions.clear();
    final Object? raw = s?['sessions'];
    if (raw is List<dynamic>) {
      for (final Object? e in raw) {
        if (e is Map<String, dynamic>) {
          final PracticeSession? p = PracticeSession.fromJson(e);
          if (p != null) {
            sessions.add(p);
          }
        }
      }
    }
    sessions.sort((PracticeSession a, PracticeSession b) => a.start.compareTo(b.start));
    loaded = true;
    notifyListeners();
  }

  bool isActive(String tool) => _open.containsKey(tool);

  bool get anyActive => _open.isNotEmpty;

  /// La herramienta empieza a estar activa con [instrumentId].
  void start(String tool, String instrumentId) {
    final DateTime now = clock.now();
    final _Open? o = _open[tool];
    if (o != null) {
      if (o.session.instrumentId == instrumentId) {
        o.continuous = true;
        return;
      }
      _close(tool, now);
    }
    _openSession(tool, instrumentId, now, continuous: true);
  }

  /// La herramienta deja de estar activa.
  void stop(String tool) {
    if (_open.containsKey(tool)) {
      _close(tool, clock.now());
    }
  }

  /// Actividad puntual (el afinador oye un tono estable en este momento).
  void ping(String tool, String instrumentId) {
    final DateTime now = clock.now();
    final _Open? o = _open[tool];
    if (o != null && o.session.instrumentId != instrumentId) {
      _close(tool, o.lastPing ?? now);
    }
    final _Open? current = _open[tool];
    if (current == null) {
      _openSession(tool, instrumentId, now, continuous: false);
      _open[tool]!.lastPing = now;
      return;
    }
    current.lastPing = now;
    if (now.isAfter(current.session.end)) {
      current.session.end = now;
    }
  }

  /// La herramienta activa cambia de instrumento (por ejemplo, desde Ajustes).
  void changeInstrument(String instrumentId) {
    final DateTime now = clock.now();
    for (final String tool in _open.keys.toList()) {
      final _Open o = _open[tool]!;
      if (o.session.instrumentId != instrumentId) {
        final bool continuous = o.continuous;
        _close(tool, continuous ? now : (o.lastPing ?? now));
        if (continuous) {
          _openSession(tool, instrumentId, now, continuous: true);
        }
      }
    }
  }

  void _openSession(String tool, String instrumentId, DateTime now, {required bool continuous}) {
    PracticeSession? last;
    for (int i = sessions.length - 1; i >= 0; i--) {
      if (sessions[i].tool == tool) {
        last = sessions[i];
        break;
      }
    }
    PracticeSession s;
    if (last != null && last.instrumentId == instrumentId && !now.isBefore(last.end) && now.difference(last.end) <= mergeGap) {
      // Pausa corta: sigue el mismo intervalo.
      s = last;
      s.end = now;
    } else {
      s = PracticeSession(id: newId(), start: now, end: now, tool: tool, instrumentId: instrumentId);
      sessions.add(s);
    }
    _open[tool] = _Open(s, continuous: continuous);
    _ensureTicker();
    notifyListeners();
  }

  void _close(String tool, DateTime at) {
    final _Open? o = _open.remove(tool);
    if (o == null) {
      return;
    }
    final DateTime end = o.continuous ? at : (o.lastPing ?? at);
    if (end.isAfter(o.session.end)) {
      o.session.end = end;
    }
    // Un intervalo de menos de un segundo se queda en memoria por si la
    // siguiente nota llega antes de [mergeGap] (las notas cortas del teclado
    // se unen); suelto, no se guarda (ver [_save]).
    if (_open.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
    unawaited(_save());
    notifyListeners();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
    _lastCheckpoint ??= clock.now();
  }

  /// Avanza los intervalos abiertos (cada segundo): extiende los continuos,
  /// cierra los del afinador sin ping reciente, guarda cada [checkpointEvery]
  /// y avisa a la pantalla de Práctica.
  @visibleForTesting
  void tick() {
    final DateTime now = clock.now();
    for (final String tool in _open.keys.toList()) {
      final _Open o = _open[tool]!;
      if (o.continuous) {
        o.session.end = now;
      } else {
        final DateTime? lp = o.lastPing;
        if (lp == null || now.difference(lp) > pingTimeout) {
          _close(tool, lp ?? now);
        }
      }
    }
    final DateTime? last = _lastCheckpoint;
    if (last == null || now.difference(last) >= checkpointEvery) {
      _lastCheckpoint = now;
      unawaited(_save());
    }
    notifyListeners();
  }

  /// Guarda ya los intervalos abiertos (al pasar a segundo plano).
  Future<void> checkpoint() async {
    _lastCheckpoint = clock.now();
    await _save();
  }

  /// Cierra todos los intervalos (al salir de la app) y guarda.
  Future<void> closeAll() async {
    final DateTime now = clock.now();
    for (final String tool in _open.keys.toList()) {
      _close(tool, now);
    }
    await _save();
  }

  Future<void> _save() async {
    final DateTime now = clock.now();
    // Se conserva un año de historial; los instantes sueltos (menos de un
    // segundo, sin otra nota cerca) no son práctica.
    final DateTime limit = now.subtract(const Duration(days: 366));
    sessions.removeWhere((PracticeSession s) {
      if (_isOpen(s)) {
        return false;
      }
      final bool instant = s.end.difference(s.start) < const Duration(seconds: 1) && now.difference(s.end) > mergeGap;
      return s.end.isBefore(limit) || instant;
    });
    await store.writeJson(fileName, <String, dynamic>{
      'sessions': <Map<String, dynamic>>[
        for (final PracticeSession s in sessions)
          if (_effectiveEnd(s, now).difference(s.start) >= const Duration(seconds: 1))
            PracticeSession(id: s.id, start: s.start, end: _effectiveEnd(s, now), tool: s.tool, instrumentId: s.instrumentId).toJson(),
      ],
    });
  }

  bool _isOpen(PracticeSession s) {
    for (final _Open o in _open.values) {
      if (identical(o.session, s)) {
        return true;
      }
    }
    return false;
  }

  /// Fin real de un intervalo: los continuos abiertos llegan hasta ahora.
  DateTime _effectiveEnd(PracticeSession s, DateTime now) {
    for (final _Open o in _open.values) {
      if (identical(o.session, s) && o.continuous && now.isAfter(s.end)) {
        return now;
      }
    }
    return s.end;
  }

  // ------------------------------------------------------------ consultas

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  static DateTime nextDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);

  List<_Span> _spans({DateTime? from, DateTime? to, String? tool, String? instrumentId}) {
    final DateTime now = clock.now();
    final List<_Span> out = <_Span>[];
    for (final PracticeSession s in sessions) {
      if (tool != null && s.tool != tool) {
        continue;
      }
      if (instrumentId != null && s.instrumentId != instrumentId) {
        continue;
      }
      DateTime a = s.start;
      DateTime b = _effectiveEnd(s, now);
      if (from != null && a.isBefore(from)) {
        a = from;
      }
      if (to != null && b.isAfter(to)) {
        b = to;
      }
      if (b.isAfter(a)) {
        out.add(_Span(a.microsecondsSinceEpoch, b.microsecondsSinceEpoch));
      }
    }
    return out;
  }

  static int _unionSeconds(List<_Span> spans) {
    if (spans.isEmpty) {
      return 0;
    }
    spans.sort((_Span x, _Span y) => x.a.compareTo(y.a));
    int total = 0;
    int curA = spans.first.a;
    int curB = spans.first.b;
    for (int i = 1; i < spans.length; i++) {
      final _Span s = spans[i];
      if (s.a <= curB) {
        if (s.b > curB) {
          curB = s.b;
        }
      } else {
        total += curB - curA;
        curA = s.a;
        curB = s.b;
      }
    }
    total += curB - curA;
    return total ~/ 1000000;
  }

  /// Segundos practicados entre [from] y [to] (unión de herramientas).
  int secondsBetween(DateTime from, DateTime to) => _unionSeconds(_spans(from: from, to: to));

  /// Segundos practicados en el día de [day] (de medianoche a medianoche).
  int secondsOn(DateTime day) {
    final DateTime d = dayOf(day);
    return secondsBetween(d, nextDay(d));
  }

  /// Segundos por herramienta desde [from] (cada una cuenta su tiempo).
  Map<String, int> secondsByTool({required DateTime from, DateTime? to}) {
    final Map<String, int> out = <String, int>{};
    for (final String tool in PracticeSession.tools) {
      final int s = _unionSeconds(_spans(from: from, to: to, tool: tool));
      if (s > 0) {
        out[tool] = s;
      }
    }
    return out;
  }

  /// Segundos por instrumento desde [from] (unión de herramientas).
  Map<String, int> secondsByInstrument({required DateTime from, DateTime? to}) {
    final Set<String> ids = <String>{for (final PracticeSession s in sessions) s.instrumentId};
    final Map<String, int> out = <String, int>{};
    for (final String id in ids) {
      final int s = _unionSeconds(_spans(from: from, to: to, instrumentId: id));
      if (s > 0) {
        out[id] = s;
      }
    }
    return out;
  }

  /// Segundos practicados por día (unión de herramientas; un intervalo que
  /// cruza la medianoche se reparte entre los dos días).
  Map<DateTime, int> dailySeconds() {
    final List<_Span> spans = _spans()..sort((_Span x, _Span y) => x.a.compareTo(y.a));
    final List<_Span> merged = <_Span>[];
    for (final _Span s in spans) {
      if (merged.isNotEmpty && s.a <= merged.last.b) {
        if (s.b > merged.last.b) {
          merged.last.b = s.b;
        }
      } else {
        merged.add(_Span(s.a, s.b));
      }
    }
    final Map<DateTime, int> micros = <DateTime, int>{};
    for (final _Span m in merged) {
      DateTime a = DateTime.fromMicrosecondsSinceEpoch(m.a);
      final DateTime b = DateTime.fromMicrosecondsSinceEpoch(m.b);
      while (a.isBefore(b)) {
        final DateTime day = dayOf(a);
        final DateTime next = nextDay(day);
        final DateTime segmentEnd = next.isBefore(b) ? next : b;
        micros[day] = (micros[day] ?? 0) + segmentEnd.difference(a).inMicroseconds;
        a = segmentEnd;
      }
    }
    return <DateTime, int>{for (final MapEntry<DateTime, int> e in micros.entries) e.key: e.value ~/ 1000000};
  }

  /// Racha: días con al menos [minSeconds] de práctica, contando hacia atrás
  /// desde hoy. Hoy todavía no la rompe aunque no se haya practicado. Un día
  /// de descanso no la rompe si el descanso anterior de la racha fue hace
  /// [restSpacingDays] días o más (un día de descanso de cada siete) y antes
  /// de él hay práctica.
  int streak({int minSeconds = streakMinSeconds}) {
    final Map<DateTime, int> daily = dailySeconds();
    bool practiced(int back, DateTime today) => (daily[DateTime(today.year, today.month, today.day - back)] ?? 0) >= minSeconds;
    final DateTime today = dayOf(clock.now());
    int count = 0;
    int? lastRest;
    for (int back = 0; back < 3660; back++) {
      if (practiced(back, today)) {
        count++;
        continue;
      }
      if (back == 0) {
        continue;
      }
      if ((lastRest == null || back - lastRest >= restSpacingDays) && practiced(back + 1, today)) {
        lastRest = back;
        continue;
      }
      break;
    }
    return count;
  }

  /// Últimas sesiones: intervalos seguidos de una herramienta con pausas de
  /// menos de 5 minutos, de la más reciente a la más antigua.
  List<SessionGroup> recentGroups({int limit = 30}) {
    final DateTime now = clock.now();
    final List<PracticeSession> sorted = List<PracticeSession>.from(sessions)..sort((PracticeSession a, PracticeSession b) => b.start.compareTo(a.start));
    final List<SessionGroup> out = <SessionGroup>[];
    final Map<String, int> openGroup = <String, int>{};
    final List<List<PracticeSession>> groups = <List<PracticeSession>>[];
    for (final PracticeSession s in sorted) {
      final String key = '${s.tool}|${s.instrumentId}';
      final int? gi = openGroup[key];
      if (gi != null) {
        final PracticeSession newest = groups[gi].last;
        if (newest.start.difference(_effectiveEnd(s, now)) < const Duration(minutes: 5)) {
          groups[gi].add(s);
          continue;
        }
      }
      openGroup[key] = groups.length;
      groups.add(<PracticeSession>[s]);
    }
    for (final List<PracticeSession> g in groups) {
      int active = 0;
      DateTime start = g.first.start;
      DateTime end = _effectiveEnd(g.first, now);
      for (final PracticeSession s in g) {
        final DateTime e = _effectiveEnd(s, now);
        active += e.difference(s.start).inSeconds;
        if (s.start.isBefore(start)) {
          start = s.start;
        }
        if (e.isAfter(end)) {
          end = e;
        }
      }
      out.add(SessionGroup(tool: g.first.tool, instrumentId: g.first.instrumentId, start: start, end: end, activeSeconds: active));
    }
    out.sort((SessionGroup a, SessionGroup b) => b.start.compareTo(a.start));
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}

class _Open {
  _Open(this.session, {required this.continuous});

  final PracticeSession session;

  /// true para herramientas con inicio y fin (metrónomo, bordón, grabadora).
  bool continuous;
  DateTime? lastPing;
}

class _Span {
  _Span(this.a, this.b);

  final int a;
  int b;
}
