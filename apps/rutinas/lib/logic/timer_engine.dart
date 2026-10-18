import 'dart:math' as math;

import '../model/workout.dart';

/// Vuelta de un bloque en la que va un intervalo: "Ronda 3 de 8".
class RoundInfo {
  const RoundInfo({required this.label, required this.index, required this.total, required this.depth});

  /// Nombre del bloque (vacío = nombre por nivel: Ronda, Serie…).
  final String label;
  final int index;
  final int total;

  /// 0 es el bloque más externo.
  final int depth;

  Map<String, dynamic> toJson() => <String, dynamic>{'l': label, 'i': index, 't': total, 'd': depth};

  factory RoundInfo.fromJson(Map<String, dynamic> j) => RoundInfo(label: (j['l'] as String?) ?? '', index: (j['i'] as num?)?.toInt() ?? 1, total: (j['t'] as num?)?.toInt() ?? 1, depth: (j['d'] as num?)?.toInt() ?? 0);
}

/// Un intervalo ya desplegado, listo para correr.
class TimerSegment {
  const TimerSegment({required this.name, required this.seconds, required this.kind, required this.color, required this.sound, this.rounds = const <RoundInfo>[]});

  final String name;
  final int seconds;
  final StepKind kind;
  final int color;

  /// Sonido al empezar (ya resuelto: nunca [CueSound.auto]).
  final CueSound sound;

  /// Vueltas de los bloques que lo contienen, de afuera hacia adentro.
  final List<RoundInfo> rounds;

  int get ms => seconds * 1000;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'seconds': seconds,
        'kind': kind.name,
        'color': color,
        'sound': sound.name,
        'rounds': rounds.map((RoundInfo r) => r.toJson()).toList(),
      };

  factory TimerSegment.fromJson(Map<String, dynamic> j) {
    final Object? rounds = j['rounds'];
    return TimerSegment(
      name: (j['name'] as String?) ?? '',
      seconds: ((j['seconds'] as num?)?.toInt() ?? 1).clamp(1, 24 * 3600),
      kind: stepKindFrom(j['kind']),
      color: (j['color'] as num?)?.toInt() ?? defaultStepColor(StepKind.work),
      sound: cueSoundFrom(j['sound'], fallback: CueSound.beep),
      rounds: rounds is List ? rounds.whereType<Map<String, dynamic>>().map(RoundInfo.fromJson).toList() : const <RoundInfo>[],
    );
  }
}

/// Colores por tipo de intervalo. Todos tienen contraste AA (4,5:1 o más) con
/// texto blanco; la prueba de accesibilidad lo verifica.
int defaultStepColor(StepKind kind) {
  switch (kind) {
    case StepKind.prepare:
      return 0xFF8A5A00;
    case StepKind.warmup:
      return 0xFFB2410C;
    case StepKind.work:
      return 0xFFC62828;
    case StepKind.rest:
      return 0xFF2E7D32;
    case StepKind.cooldown:
      return 0xFF1565C0;
  }
}

/// Sonido por defecto al empezar un intervalo de este tipo.
CueSound defaultStepSound(StepKind kind) {
  switch (kind) {
    case StepKind.prepare:
    case StepKind.warmup:
    case StepKind.work:
      return CueSound.beep;
    case StepKind.rest:
    case StepKind.cooldown:
      return CueSound.bell;
  }
}

/// Más intervalos que esto no caben en una pantalla ni en un entrenamiento real.
const int kMaxSegments = 3000;

class TimerEngine {
  TimerEngine._();

  /// Despliega los bloques en la lista de intervalos que se van a correr.
  /// En la última repetición de un bloque con [RepeatBlock.skipLastRest], el
  /// descanso con que termina el bloque no se hace.
  static List<TimerSegment> flatten(List<TimerNode> nodes) {
    final List<TimerSegment> out = <TimerSegment>[];
    void walk(List<TimerNode> list, List<RoundInfo> ctx, bool dropTrailingRest) {
      for (int i = 0; i < list.length; i++) {
        if (out.length >= kMaxSegments) {
          return;
        }
        final TimerNode node = list[i];
        final bool last = i == list.length - 1;
        if (node is IntervalStep) {
          if (node.seconds <= 0) {
            continue;
          }
          if (dropTrailingRest && last && node.kind == StepKind.rest) {
            continue;
          }
          out.add(TimerSegment(
            name: node.name,
            seconds: node.seconds,
            kind: node.kind,
            color: node.color ?? defaultStepColor(node.kind),
            sound: node.sound == CueSound.auto ? defaultStepSound(node.kind) : node.sound,
            rounds: ctx,
          ));
        } else if (node is RepeatBlock) {
          final int reps = node.repeats.clamp(1, 99);
          for (int r = 1; r <= reps; r++) {
            final List<RoundInfo> inner = List<RoundInfo>.unmodifiable(<RoundInfo>[...ctx, RoundInfo(label: node.name, index: r, total: reps, depth: ctx.length)]);
            walk(node.children, inner, node.skipLastRest && r == reps);
          }
        }
      }
    }

    walk(nodes, const <RoundInfo>[], false);
    return out;
  }

  static int totalSeconds(List<TimerSegment> segments) => segments.fold<int>(0, (int a, TimerSegment s) => a + s.seconds);

  /// Profundidad de bloques (0 si no hay bloques).
  static int depth(List<TimerNode> nodes) {
    int best = 0;
    for (final TimerNode n in nodes) {
      if (n is RepeatBlock) {
        best = math.max(best, 1 + depth(n.children));
      }
    }
    return best;
  }
}

/// Qué está corriendo: un entrenamiento, una cuenta regresiva o el tiempo de un hábito.
enum RunKind { workout, countdown, habit }

RunKind runKindFrom(Object? v) {
  for (final RunKind k in RunKind.values) {
    if (k.name == v) {
      return k;
    }
  }
  return RunKind.workout;
}

/// Foto del temporizador en un instante.
class RunSnapshot {
  const RunSnapshot({required this.index, required this.segmentElapsedMs, required this.segmentMs, required this.elapsedMs, required this.totalMs, required this.finished, required this.paused});

  final int index;
  final int segmentElapsedMs;
  final int segmentMs;
  final int elapsedMs;
  final int totalMs;
  final bool finished;
  final bool paused;

  int get segmentRemainingMs => math.max(0, segmentMs - segmentElapsedMs);

  int get totalRemainingMs => math.max(0, totalMs - elapsedMs);

  /// Segundos que se muestran: hacia arriba, como cualquier temporizador (el
  /// último segundo se ve como 0:01 y el cambio llega en 0:00).
  int get segmentRemainingSeconds => (segmentRemainingMs + 999) ~/ 1000;

  int get totalRemainingSeconds => (totalRemainingMs + 999) ~/ 1000;

  double get segmentProgress => segmentMs == 0 ? 1 : (segmentElapsedMs / segmentMs).clamp(0.0, 1.0).toDouble();
}

/// Un temporizador en marcha. Su estado sale siempre del reloj: inicio, pausas
/// acumuladas y saltos, nunca de contar ticks; así, al volver de segundo plano
/// o de la pantalla apagada, está exacto.
class TimerRun {
  TimerRun({required this.kind, this.refId, required this.name, required List<TimerSegment> segments, required this.startedAt, this.pausedAt, this.pausedMs = 0, this.offsetMs = 0, this.finishSound = CueSound.gong})
      : segments = List<TimerSegment>.unmodifiable(segments),
        _starts = _cumulative(segments);

  final RunKind kind;

  /// Entrenamiento, preajuste o hábito de origen.
  final String? refId;
  final String name;
  final List<TimerSegment> segments;
  final DateTime startedAt;
  DateTime? pausedAt;

  /// Tiempo total en pausa (sin la pausa actual).
  int pausedMs;

  /// Saltos hacia adelante (+) o atrás (−) con los botones de intervalo.
  int offsetMs;
  final CueSound finishSound;
  final List<int> _starts;

  static List<int> _cumulative(List<TimerSegment> segments) {
    final List<int> out = <int>[];
    int acc = 0;
    for (final TimerSegment s in segments) {
      out.add(acc);
      acc += s.ms;
    }
    out.add(acc);
    return out;
  }

  int get totalMs => _starts.last;

  bool get paused => pausedAt != null;

  /// Inicio (en ms desde el arranque del temporizador) del intervalo [i].
  int startOf(int i) => _starts[i.clamp(0, segments.length)];

  /// Tiempo del temporizador (con saltos, sin pausas) en [now].
  int elapsedMs(DateTime now) {
    final DateTime wall = pausedAt ?? now;
    final int ms = wall.difference(startedAt).inMilliseconds - pausedMs + offsetMs;
    return ms.clamp(0, totalMs);
  }

  /// Tiempo realmente en marcha (sin pausas ni saltos), para el historial.
  int activeMs(DateTime now) {
    final DateTime wall = pausedAt ?? now;
    return math.max(0, wall.difference(startedAt).inMilliseconds - pausedMs);
  }

  RunSnapshot snapshot(DateTime now) {
    final int e = elapsedMs(now);
    if (segments.isEmpty) {
      return RunSnapshot(index: 0, segmentElapsedMs: 0, segmentMs: 0, elapsedMs: 0, totalMs: 0, finished: true, paused: paused);
    }
    if (e >= totalMs) {
      final int last = segments.length - 1;
      return RunSnapshot(index: last, segmentElapsedMs: segments[last].ms, segmentMs: segments[last].ms, elapsedMs: totalMs, totalMs: totalMs, finished: true, paused: paused);
    }
    // Búsqueda binaria del intervalo que contiene a e.
    int lo = 0;
    int hi = segments.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) ~/ 2;
      if (_starts[mid] <= e) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return RunSnapshot(index: lo, segmentElapsedMs: e - _starts[lo], segmentMs: segments[lo].ms, elapsedMs: e, totalMs: totalMs, finished: false, paused: paused);
  }

  void pause(DateTime now) {
    pausedAt ??= now;
  }

  void resume(DateTime now) {
    final DateTime? p = pausedAt;
    if (p == null) {
      return;
    }
    pausedMs += now.difference(p).inMilliseconds;
    pausedAt = null;
  }

  /// Salta al inicio del intervalo siguiente (o al final si es el último).
  void next(DateTime now) {
    final RunSnapshot s = snapshot(now);
    if (s.finished) {
      return;
    }
    offsetMs += startOf(s.index + 1) - s.elapsedMs;
  }

  /// Vuelve al inicio del intervalo actual; si acaba de empezar (menos de 2 s),
  /// al del anterior.
  void previous(DateTime now) {
    final RunSnapshot s = snapshot(now);
    int target = startOf(s.index);
    if (s.segmentElapsedMs < 2000 && s.index > 0) {
      target = startOf(s.index - 1);
    }
    if (s.finished) {
      target = startOf(segments.length - 1);
    }
    offsetMs += target - s.elapsedMs;
  }

  /// Hora real en que el temporizador llegará a [msOnTimer] si nadie pausa ni salta.
  DateTime wallTimeOf(int msOnTimer) => startedAt.add(Duration(milliseconds: msOnTimer + pausedMs - offsetMs));

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'ref': refId,
        'name': name,
        'segments': segments.map((TimerSegment s) => s.toJson()).toList(),
        'started': startedAt.toIso8601String(),
        'pausedAt': pausedAt?.toIso8601String(),
        'pausedMs': pausedMs,
        'offsetMs': offsetMs,
        'finishSound': finishSound.name,
      };

  static TimerRun? fromJson(Map<String, dynamic> j) {
    final Object? segs = j['segments'];
    final DateTime? started = DateTime.tryParse(j['started'] as String? ?? '');
    if (segs is! List || started == null) {
      return null;
    }
    final List<TimerSegment> list = segs.whereType<Map<String, dynamic>>().map(TimerSegment.fromJson).toList();
    if (list.isEmpty) {
      return null;
    }
    return TimerRun(
      kind: runKindFrom(j['kind']),
      refId: j['ref'] as String?,
      name: (j['name'] as String?) ?? '',
      segments: list,
      startedAt: started,
      pausedAt: DateTime.tryParse(j['pausedAt'] as String? ?? ''),
      pausedMs: (j['pausedMs'] as num?)?.toInt() ?? 0,
      offsetMs: (j['offsetMs'] as num?)?.toInt() ?? 0,
      finishSound: cueSoundFrom(j['finishSound'], fallback: CueSound.gong),
    );
  }
}

/// Avisos del temporizador: empieza un intervalo, 3-2-1, terminó.
enum CueType { segmentStart, countdown, finished }

class CueEvent {
  const CueEvent(this.type, {this.index = 0, this.number = 0});

  final CueType type;
  final int index;
  final int number;

  @override
  String toString() => '${type.name}:$index:$number';
}

/// Decide qué avisos tocan al comparar una foto con la anterior. Si la app
/// estuvo congelada (segundo plano), no suelta una ráfaga de avisos atrasados:
/// solo anuncia el intervalo en que va.
class CueTracker {
  int _lastIndex = -1;
  int _lastCountdown = 0;
  bool _finished = false;

  /// Se sincroniza con la foto sin avisar nada (al volver a la app).
  void sync(RunSnapshot s) {
    _lastIndex = s.index;
    _finished = s.finished;
    _lastCountdown = s.finished ? 0 : _countdownNumber(s);
  }

  /// Vuelve a empezar: el próximo [update] anuncia el intervalo actual.
  void reset() {
    _lastIndex = -1;
    _lastCountdown = 0;
    _finished = false;
  }

  /// Los 3-2-1 suenan en intervalos de 5 s o más, en los últimos tres segundos.
  static int _countdownNumber(RunSnapshot s) {
    if (s.segmentMs < 5000) {
      return 0;
    }
    final int sec = s.segmentRemainingSeconds;
    return sec >= 1 && sec <= 3 ? sec : 0;
  }

  List<CueEvent> update(RunSnapshot s) {
    final List<CueEvent> out = <CueEvent>[];
    if (s.finished) {
      if (!_finished) {
        _finished = true;
        out.add(const CueEvent(CueType.finished));
      }
      _lastIndex = s.index;
      return out;
    }
    _finished = false;
    if (s.index != _lastIndex) {
      _lastIndex = s.index;
      _lastCountdown = 0;
      out.add(CueEvent(CueType.segmentStart, index: s.index));
    }
    if (s.paused) {
      return out;
    }
    final int n = _countdownNumber(s);
    if (n != 0 && n != _lastCountdown) {
      _lastCountdown = n;
      out.add(CueEvent(CueType.countdown, index: s.index, number: n));
    }
    return out;
  }
}
