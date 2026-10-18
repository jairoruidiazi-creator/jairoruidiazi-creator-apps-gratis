import '../core/ids.dart';

/// Tipo de intervalo: define su color y su sonido por defecto.
enum StepKind { prepare, warmup, work, rest, cooldown }

/// Sonidos propios de la app (tools/gen_rutinas_sounds.py). [auto] usa el del
/// tipo de intervalo y [none] no suena.
enum CueSound { auto, beep, bell, horn, gong, none }

StepKind stepKindFrom(Object? v) {
  for (final StepKind k in StepKind.values) {
    if (k.name == v) {
      return k;
    }
  }
  return StepKind.work;
}

CueSound cueSoundFrom(Object? v, {CueSound fallback = CueSound.auto}) {
  for (final CueSound s in CueSound.values) {
    if (s.name == v) {
      return s;
    }
  }
  return fallback;
}

/// Un elemento de un entrenamiento: un intervalo o un bloque que se repite.
abstract class TimerNode {
  TimerNode(this.id);

  final String id;

  Map<String, dynamic> toJson();

  TimerNode clone();

  static TimerNode fromJson(Map<String, dynamic> j) {
    if (j['t'] == 'block') {
      return RepeatBlock.fromJson(j);
    }
    return IntervalStep.fromJson(j);
  }
}

class IntervalStep extends TimerNode {
  IntervalStep({String? id, required this.name, required this.seconds, this.kind = StepKind.work, this.color, this.sound = CueSound.auto}) : super(id ?? newId());

  String name;
  int seconds;
  StepKind kind;

  /// Color propio (ARGB); null usa el del tipo.
  int? color;
  CueSound sound;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        't': 'step',
        'id': id,
        'name': name,
        'seconds': seconds,
        'kind': kind.name,
        'color': color,
        'sound': sound.name,
      };

  factory IntervalStep.fromJson(Map<String, dynamic> j) => IntervalStep(
        id: j['id'] as String?,
        name: (j['name'] as String?) ?? '',
        seconds: ((j['seconds'] as num?)?.toInt() ?? 30).clamp(1, 24 * 3600),
        kind: stepKindFrom(j['kind']),
        color: (j['color'] as num?)?.toInt(),
        sound: cueSoundFrom(j['sound']),
      );

  @override
  IntervalStep clone() => IntervalStep(name: name, seconds: seconds, kind: kind, color: color, sound: sound);
}

class RepeatBlock extends TimerNode {
  RepeatBlock({String? id, this.name = '', this.repeats = 2, this.skipLastRest = true, List<TimerNode>? children}) : children = children ?? <TimerNode>[], super(id ?? newId());

  /// Nombre de la vuelta ("Ronda", "Serie"); vacío usa el nombre por nivel.
  String name;
  int repeats;

  /// En la última repetición se omite el descanso final del bloque.
  bool skipLastRest;
  List<TimerNode> children;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        't': 'block',
        'id': id,
        'name': name,
        'repeats': repeats,
        'skipLastRest': skipLastRest,
        'children': children.map((TimerNode c) => c.toJson()).toList(),
      };

  factory RepeatBlock.fromJson(Map<String, dynamic> j) {
    final Object? kids = j['children'];
    return RepeatBlock(
      id: j['id'] as String?,
      name: (j['name'] as String?) ?? '',
      repeats: ((j['repeats'] as num?)?.toInt() ?? 2).clamp(1, 99),
      skipLastRest: (j['skipLastRest'] as bool?) ?? true,
      children: kids is List ? kids.whereType<Map<String, dynamic>>().map(TimerNode.fromJson).toList() : <TimerNode>[],
    );
  }

  @override
  RepeatBlock clone() => RepeatBlock(name: name, repeats: repeats, skipLastRest: skipLastRest, children: children.map((TimerNode c) => c.clone()).toList());
}

/// Plantilla con la que se creó un entrenamiento.
enum WorkoutTemplate { hiit, tabata, circuit, custom }

WorkoutTemplate workoutTemplateFrom(Object? v) {
  for (final WorkoutTemplate t in WorkoutTemplate.values) {
    if (t.name == v) {
      return t;
    }
  }
  return WorkoutTemplate.custom;
}

class Workout {
  Workout({required this.id, required this.name, List<TimerNode>? nodes, this.template = WorkoutTemplate.custom, this.finishSound = CueSound.gong, required this.createdAt, this.order = 0}) : nodes = nodes ?? <TimerNode>[];

  final String id;
  String name;
  List<TimerNode> nodes;
  WorkoutTemplate template;
  CueSound finishSound;
  DateTime createdAt;
  int order;

  Workout copy() => Workout.fromJson(toJson());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'nodes': nodes.map((TimerNode n) => n.toJson()).toList(),
        'template': template.name,
        'finishSound': finishSound.name,
        'created': createdAt.toIso8601String(),
        'order': order,
      };

  factory Workout.fromJson(Map<String, dynamic> j) {
    final Object? nodes = j['nodes'];
    return Workout(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      nodes: nodes is List ? nodes.whereType<Map<String, dynamic>>().map(TimerNode.fromJson).toList() : <TimerNode>[],
      template: workoutTemplateFrom(j['template']),
      finishSound: cueSoundFrom(j['finishSound'], fallback: CueSound.gong),
      createdAt: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime(2026),
      order: (j['order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cuenta atrás guardada (té, siesta, horno).
class CountdownPreset {
  CountdownPreset({required this.id, required this.name, required this.seconds});

  final String id;
  String name;
  int seconds;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'seconds': seconds};

  factory CountdownPreset.fromJson(Map<String, dynamic> j) => CountdownPreset(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        seconds: ((j['seconds'] as num?)?.toInt() ?? 60).clamp(1, 24 * 3600),
      );
}

/// Un entrenamiento hecho (o interrumpido) para los resúmenes.
class WorkoutSession {
  WorkoutSession({required this.id, this.workoutId, required this.name, required this.startedAt, required this.endedAt, required this.activeSeconds, required this.completed});

  final String id;
  final String? workoutId;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Tiempo en marcha, sin las pausas.
  final int activeSeconds;
  final bool completed;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'workout': workoutId,
        'name': name,
        'start': startedAt.toIso8601String(),
        'end': endedAt.toIso8601String(),
        'active': activeSeconds,
        'completed': completed,
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) {
    final DateTime start = DateTime.tryParse(j['start'] as String? ?? '') ?? DateTime(2026);
    return WorkoutSession(
      id: j['id'] as String,
      workoutId: j['workout'] as String?,
      name: (j['name'] as String?) ?? '',
      startedAt: start,
      endedAt: DateTime.tryParse(j['end'] as String? ?? '') ?? start,
      activeSeconds: (j['active'] as num?)?.toInt() ?? 0,
      completed: (j['completed'] as bool?) ?? false,
    );
  }
}
