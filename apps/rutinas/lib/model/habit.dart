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

/// Un tramo de días, del [start] al [end] (los dos incluidos).
class DaySpan {
  const DaySpan(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  /// ¿Comparte algún día con el tramo del [a] al [b]?
  bool overlaps(DateTime a, DateTime b) => !b.isBefore(start) && !a.isAfter(end);

  Map<String, dynamic> toJson() => <String, dynamic>{'from': dayKey(start), 'to': dayKey(end)};

  /// Null si el tramo no se puede leer o termina antes de empezar.
  static DaySpan? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) {
      return null;
    }
    final DateTime? a = parseDayKey(j['from'] as String? ?? '');
    final DateTime? b = parseDayKey(j['to'] as String? ?? '');
    if (a == null || b == null || b.isBefore(a)) {
      return null;
    }
    return DaySpan(a, b);
  }
}

/// La frecuencia y la meta que rigieron hasta el día [until] (incluido). Al
/// cambiar la regla de un hábito, la anterior se guarda así y los días
/// pasados se siguen evaluando con ella: un cambio rige desde ese día.
class PastRule {
  const PastRule({required this.until, required this.frequency, required this.goal});

  final DateTime until;
  final Frequency frequency;
  final int goal;

  Map<String, dynamic> toJson() => <String, dynamic>{'until': dayKey(until), 'frequency': frequency.toJson(), 'goal': goal};

  static PastRule? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) {
      return null;
    }
    final DateTime? until = parseDayKey(j['until'] as String? ?? '');
    final Object? f = j['frequency'];
    if (until == null) {
      return null;
    }
    return PastRule(until: until, frequency: f is Map<String, dynamic> ? Frequency.fromJson(f) : const Frequency(), goal: (j['goal'] as num?)?.toInt() ?? 1);
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
    this.archivedAt,
    List<DaySpan>? pauses,
    List<PastRule>? pastRules,
    this.order = 0,
    required this.createdAt,
    this.notes = '',
  })  : reminders = reminders ?? <int>[],
        pauses = pauses ?? <DaySpan>[],
        pastRules = pastRules ?? <PastRule>[];

  final String id;
  String name;

  /// No cambia si el hábito ya tiene registros: cambiaría lo que significan
  /// (veces, segundos o recaídas). El editor ofrece crear uno nuevo.
  HabitKind kind;

  /// Frecuencia vigente (la de hoy). Las anteriores están en [pastRules].
  Frequency frequency;

  /// Meta diaria vigente: veces (count) o segundos (timed). Sin uso en check y
  /// negative. Las anteriores están en [pastRules].
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

  /// Día en que se archivó (null si no está archivado). Desde ese día sus
  /// periodos no cuentan como fallados.
  DateTime? archivedAt;

  /// Tramos en que estuvo archivado y luego se recuperó: tampoco fallan.
  List<DaySpan> pauses;

  /// Reglas anteriores (frecuencia y meta), de la más vieja a la más nueva.
  List<PastRule> pastRules;
  int order;
  DateTime createdAt;

  /// Para qué se hace (opcional).
  String notes;

  bool get isNegative => kind == HabitKind.negative;

  /// Meta diaria vigente.
  int get target => targetOn(null);

  /// Regla que rige el día [day] (la vigente si [day] es null o posterior a
  /// los cambios).
  PastRule? _ruleOn(DateTime? day) {
    if (day == null) {
      return null;
    }
    for (final PastRule p in pastRules) {
      if (!day.isAfter(p.until)) {
        return p;
      }
    }
    return null;
  }

  /// Frecuencia que regía el día [day].
  Frequency frequencyOn(DateTime day) => (_ruleOn(day)?.frequency ?? frequency).normalized();

  /// Lo que había que juntar el día [day] para darlo por hecho (con la meta
  /// que regía ese día).
  int targetOn(DateTime? day) {
    switch (kind) {
      case HabitKind.check:
      case HabitKind.negative:
        return 1;
      case HabitKind.count:
      case HabitKind.timed:
        final int g = _ruleOn(day)?.goal ?? goal;
        return g < 1 ? 1 : g;
    }
  }

  /// ¿El día [day] cae en un tramo archivado (el actual o uno ya recuperado)?
  bool pausedOn(DateTime day) {
    final DateTime? a = archivedAt;
    if (archived && a != null && !day.isBefore(a)) {
      return true;
    }
    for (final DaySpan p in pauses) {
      if (p.contains(day)) {
        return true;
      }
    }
    return false;
  }

  /// ¿Algún día del [a] al [b] cae en un tramo archivado?
  bool pausedBetween(DateTime a, DateTime b) {
    final DateTime? at = archivedAt;
    if (archived && at != null && !b.isBefore(at)) {
      return true;
    }
    for (final DaySpan p in pauses) {
      if (p.overlaps(a, b)) {
        return true;
      }
    }
    return false;
  }

  /// Archiva el hábito desde [today].
  void archive(DateTime today) {
    archived = true;
    archivedAt = dateOnly(today);
  }

  /// Lo recupera desde [today]: el tramo archivado queda como pausa.
  void unarchive(DateTime today) {
    final DateTime? from = archivedAt;
    archived = false;
    archivedAt = null;
    if (from != null) {
      final DateTime to = addDays(dateOnly(today), -1);
      if (!to.isBefore(from)) {
        pauses.add(DaySpan(from, to));
      }
    }
  }

  /// Cambia la frecuencia o la meta desde [today]: los días anteriores siguen
  /// evaluándose con la regla que tenían. [since] es el primer día que cuenta
  /// del hábito; si el cambio es antes de ese día, no hace falta guardar nada.
  void changeRule({required Frequency frequency, required int goal, required DateTime today, required DateTime since}) {
    final Frequency f = frequency.normalized();
    final DateTime day = dateOnly(today);
    final DateTime yesterday = addDays(day, -1);
    // Un reloj que se atrasó no deja reglas que terminen hoy o después.
    pastRules.removeWhere((PastRule p) => !p.until.isBefore(day));
    if (f == this.frequency.normalized() && goal == this.goal) {
      return;
    }
    final bool changedToday = pastRules.isNotEmpty && sameDay(pastRules.last.until, yesterday);
    if (changedToday) {
      // Segundo cambio del mismo día: la regla de ayer ya quedó guardada. Si el
      // cambio deja todo como estaba ayer, la marca sobra.
      final PastRule last = pastRules.last;
      if (last.frequency.normalized() == f && last.goal == goal) {
        pastRules.removeLast();
      }
    } else if (!yesterday.isBefore(dateOnly(since))) {
      pastRules.add(PastRule(until: yesterday, frequency: this.frequency.normalized(), goal: this.goal));
    }
    this.frequency = f;
    this.goal = goal;
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
        if (archivedAt != null) 'archivedAt': dayKey(archivedAt!),
        if (pauses.isNotEmpty) 'pauses': pauses.map((DaySpan p) => p.toJson()).toList(),
        if (pastRules.isNotEmpty) 'rules': pastRules.map((PastRule p) => p.toJson()).toList(),
        'order': order,
        'created': createdAt.toIso8601String(),
        'notes': notes,
      };

  factory Habit.fromJson(Map<String, dynamic> j) {
    final DateTime created = DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime(2026);
    final Object? rem = j['reminders'];
    final Object? freq = j['frequency'];
    final Object? pauses = j['pauses'];
    final Object? rules = j['rules'];
    final HabitKind kind = habitKindFrom(j['kind']);
    final bool archived = (j['archived'] as bool?) ?? false;
    final DateTime start = parseDayKey(j['start'] as String? ?? '') ?? (isSaneDate(created) ? dateOnly(created) : DateTime(2026));
    final List<PastRule> past = rules is List ? rules.map(PastRule.fromJson).whereType<PastRule>().toList() : <PastRule>[];
    past.sort((PastRule a, PastRule b) => a.until.compareTo(b.until));
    return Habit(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      kind: kind,
      frequency: freq is Map<String, dynamic> ? Frequency.fromJson(freq) : const Frequency(),
      goal: (j['goal'] as num?)?.toInt() ?? 1,
      unit: (j['unit'] as String?) ?? '',
      icon: (j['icon'] as String?) ?? 'task_alt',
      color: (j['color'] as num?)?.toInt() ?? 0xFF3949AB,
      startDate: start,
      reminders: rem is List ? (rem.whereType<num>().map((num m) => m.toInt()).where((int m) => m >= 0 && m < 24 * 60).toSet().toList()..sort()) : <int>[],
      nagMinutes: ((j['nag'] as num?)?.toInt() ?? 0).clamp(0, 60),
      archived: archived,
      archivedAt: archived ? parseDayKey(j['archivedAt'] as String? ?? '') : null,
      pauses: pauses is List ? pauses.map(DaySpan.fromJson).whereType<DaySpan>().toList() : <DaySpan>[],
      pastRules: past,
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
