import '../core/dates.dart';

/// Tipo de hábito.
/// - check: se hace o no se hace (meditar, leer).
/// - count: varias veces al día hasta una meta con unidad (8 vasos de agua).
/// - timed: minutos al día con el temporizador integrado (meditar 10 min).
/// - negative: "dejar de…": se cuentan los días sin recaer.
enum HabitKind { check, count, timed, negative }

/// Cada cuánto toca un hábito.
/// - daily: todos los días.
/// - weekdays: días concretos de la semana.
/// - everyN: una vez en cada bloque de N días, contados desde el inicio.
/// - perWeek / perMonth: N días por semana o por mes, cualquiera de ellos.
enum FrequencyType { daily, weekdays, everyN, perWeek, perMonth }

HabitKind habitKindFrom(Object? v) {
  for (final HabitKind k in HabitKind.values) {
    if (k.name == v) {
      return k;
    }
  }
  return HabitKind.check;
}

FrequencyType frequencyTypeFrom(Object? v) {
  for (final FrequencyType f in FrequencyType.values) {
    if (f.name == v) {
      return f;
    }
  }
  return FrequencyType.daily;
}

class Frequency {
  const Frequency({this.type = FrequencyType.daily, this.weekdays = const <int>[], this.n = 1});

  final FrequencyType type;

  /// Días de la semana (1 lunes … 7 domingo) para [FrequencyType.weekdays].
  final List<int> weekdays;

  /// Días del bloque (everyN) o veces por semana o por mes.
  final int n;

  /// Valor válido: semanas de 1 a 7 veces, meses de 1 a 31, bloques de 2 a 365
  /// días y al menos un día de la semana.
  Frequency normalized() {
    switch (type) {
      case FrequencyType.daily:
        return const Frequency();
      case FrequencyType.weekdays:
        final List<int> days = weekdays.where((int d) => d >= 1 && d <= 7).toSet().toList()..sort();
        if (days.isEmpty || days.length == 7) {
          return const Frequency();
        }
        return Frequency(type: FrequencyType.weekdays, weekdays: days);
      case FrequencyType.everyN:
        return Frequency(type: FrequencyType.everyN, n: n.clamp(2, 365));
      case FrequencyType.perWeek:
        return Frequency(type: FrequencyType.perWeek, n: n.clamp(1, 7));
      case FrequencyType.perMonth:
        return Frequency(type: FrequencyType.perMonth, n: n.clamp(1, 31));
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'type': type.name, 'days': weekdays, 'n': n};

  factory Frequency.fromJson(Map<String, dynamic> j) {
    final Object? days = j['days'];
    return Frequency(
      type: frequencyTypeFrom(j['type']),
      weekdays: days is List ? days.whereType<num>().map((num d) => d.toInt()).toList() : const <int>[],
      n: (j['n'] as num?)?.toInt() ?? 1,
    ).normalized();
  }

  @override
  bool operator ==(Object other) => other is Frequency && other.type == type && other.n == n && _sameDays(other.weekdays, weekdays);

  @override
  int get hashCode => Object.hash(type, n, Object.hashAll(weekdays));

  static bool _sameDays(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class Habit {
  Habit({
    required this.id,
    required this.name,
    this.kind = HabitKind.check,
    this.frequency = const Frequency(),
    this.goal = 1,
    this.unit = '',
    this.icon = 'task_alt',
    this.color = 0xFF3949AB,
    required this.startDate,
    List<int>? reminders,
    this.nagMinutes = 0,
    this.archived = false,
    this.order = 0,
    required this.createdAt,
    this.notes = '',
  }) : reminders = reminders ?? <int>[];

  final String id;
  String name;
  HabitKind kind;
  Frequency frequency;

  /// Meta diaria: veces (count) o segundos (timed). Sin uso en check y negative.
  int goal;

  /// Unidad de las veces (count): "vasos", "páginas".
  String unit;
  String icon;
  int color;

  /// Primer día que cuenta (a medianoche).
  DateTime startDate;

  /// Horas de aviso, en minutos desde la medianoche.
  List<int> reminders;

  /// Repetir el aviso cada tantos minutos hasta marcarlo hecho (0 = no).
  int nagMinutes;
  bool archived;
  int order;
  DateTime createdAt;

  /// Para qué se hace (opcional).
  String notes;

  bool get isNegative => kind == HabitKind.negative;

  /// Lo que hay que juntar en un día para darlo por hecho.
  int get target {
    switch (kind) {
      case HabitKind.check:
      case HabitKind.negative:
        return 1;
      case HabitKind.count:
      case HabitKind.timed:
        return goal < 1 ? 1 : goal;
    }
  }

  Habit copy() => Habit.fromJson(toJson());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'frequency': frequency.toJson(),
        'goal': goal,
        'unit': unit,
        'icon': icon,
        'color': color,
        'start': dayKey(startDate),
        'reminders': reminders,
        'nag': nagMinutes,
        'archived': archived,
        'order': order,
        'created': createdAt.toIso8601String(),
        'notes': notes,
      };

  factory Habit.fromJson(Map<String, dynamic> j) {
    final DateTime created = DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime(2026);
    final Object? rem = j['reminders'];
    final Object? freq = j['frequency'];
    final HabitKind kind = habitKindFrom(j['kind']);
    return Habit(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      kind: kind,
      frequency: freq is Map<String, dynamic> ? Frequency.fromJson(freq) : const Frequency(),
      goal: (j['goal'] as num?)?.toInt() ?? 1,
      unit: (j['unit'] as String?) ?? '',
      icon: (j['icon'] as String?) ?? 'task_alt',
      color: (j['color'] as num?)?.toInt() ?? 0xFF3949AB,
      startDate: parseDayKey(j['start'] as String? ?? '') ?? dateOnly(created),
      reminders: rem is List ? (rem.whereType<num>().map((num m) => m.toInt()).where((int m) => m >= 0 && m < 24 * 60).toSet().toList()..sort()) : <int>[],
      nagMinutes: ((j['nag'] as num?)?.toInt() ?? 0).clamp(0, 60),
      archived: (j['archived'] as bool?) ?? false,
      order: (j['order'] as num?)?.toInt() ?? 0,
      createdAt: created,
      notes: (j['notes'] as String?) ?? '',
    );
  }
}

/// Lo registrado de un hábito en un día.
class HabitEntry {
  HabitEntry({this.value = 0, this.skipped = false, this.note = '', DateTime? updatedAt}) : updatedAt = updatedAt ?? DateTime(2026);

  /// Veces (check y count), segundos (timed) o recaídas (negative).
  int value;

  /// Día saltado a propósito: no rompe la racha.
  bool skipped;
  String note;
  DateTime updatedAt;

  bool get isEmpty => value == 0 && !skipped && note.trim().isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': value,
        if (skipped) 's': true,
        if (note.isNotEmpty) 'n': note,
        'u': updatedAt.toIso8601String(),
      };

  factory HabitEntry.fromJson(Map<String, dynamic> j) => HabitEntry(
        value: ((j['v'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
        skipped: (j['s'] as bool?) ?? false,
        note: (j['n'] as String?) ?? '',
        updatedAt: DateTime.tryParse(j['u'] as String? ?? ''),
      );
}
