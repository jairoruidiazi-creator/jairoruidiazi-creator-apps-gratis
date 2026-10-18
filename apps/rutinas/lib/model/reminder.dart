import '../core/dates.dart';

/// Cómo se repite un recordatorio.
/// - once: una vez.
/// - everyNDays: cada N días (N = 1 es todos los días).
/// - weekdays: días concretos de la semana.
/// - monthlyDay: cada mes el día [Recurrence.day]; si el mes es más corto
///   (el 31 en abril, el 30 en febrero), cae en su último día.
/// - monthlyLast: el último día de cada mes.
/// - yearly: cada año el [Recurrence.day] de [Recurrence.month]; el 29 de
///   febrero cae el 28 en los años no bisiestos.
enum RecurrenceType { once, everyNDays, weekdays, monthlyDay, monthlyLast, yearly }

RecurrenceType recurrenceTypeFrom(Object? v) {
  for (final RecurrenceType r in RecurrenceType.values) {
    if (r.name == v) {
      return r;
    }
  }
  return RecurrenceType.once;
}

class Recurrence {
  const Recurrence({this.type = RecurrenceType.once, this.n = 1, this.weekdays = const <int>[], this.day = 1, this.month = 1});

  final RecurrenceType type;
  final int n;
  final List<int> weekdays;
  final int day;
  final int month;

  bool get repeats => type != RecurrenceType.once;

  Recurrence normalized() {
    switch (type) {
      case RecurrenceType.once:
      case RecurrenceType.monthlyLast:
        return Recurrence(type: type);
      case RecurrenceType.everyNDays:
        return Recurrence(type: type, n: n.clamp(1, 365));
      case RecurrenceType.weekdays:
        final List<int> days = weekdays.where((int d) => d >= 1 && d <= 7).toSet().toList()..sort();
        if (days.isEmpty) {
          return const Recurrence(type: RecurrenceType.everyNDays);
        }
        return Recurrence(type: type, weekdays: days);
      case RecurrenceType.monthlyDay:
        return Recurrence(type: type, day: day.clamp(1, 31));
      case RecurrenceType.yearly:
        final int m = month.clamp(1, 12);
        // El año de referencia es bisiesto para admitir el 29 de febrero.
        return Recurrence(type: type, month: m, day: day.clamp(1, daysInMonth(2024, m)));
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'type': type.name, 'n': n, 'days': weekdays, 'day': day, 'month': month};

  factory Recurrence.fromJson(Map<String, dynamic> j) {
    final Object? days = j['days'];
    return Recurrence(
      type: recurrenceTypeFrom(j['type']),
      n: (j['n'] as num?)?.toInt() ?? 1,
      weekdays: days is List ? days.whereType<num>().map((num d) => d.toInt()).toList() : const <int>[],
      day: (j['day'] as num?)?.toInt() ?? 1,
      month: (j['month'] as num?)?.toInt() ?? 1,
    ).normalized();
  }

  @override
  bool operator ==(Object other) => other is Recurrence && other.type == type && other.n == n && other.day == day && other.month == month && other.weekdays.join(',') == weekdays.join(',');

  @override
  int get hashCode => Object.hash(type, n, day, month, weekdays.join(','));
}

class Reminder {
  Reminder({
    required this.id,
    required this.title,
    this.notes = '',
    required this.dueAt,
    this.recurrence = const Recurrence(),
    this.nagMinutes = 0,
    this.countdownSeconds = 0,
    this.snoozedUntil,
    this.doneAt,
    List<DateTime>? completions,
    required this.createdAt,
  }) : completions = completions ?? <DateTime>[];

  final String id;
  String title;
  String notes;

  /// Fecha y hora de la ocurrencia actual (la próxima o la vencida sin hacer).
  DateTime dueAt;
  Recurrence recurrence;

  /// Repetir el aviso cada tantos minutos hasta marcarlo hecho (0 = no).
  int nagMinutes;

  /// Si se creó como cuenta regresiva ("avísame en 10 min"), su duración.
  int countdownSeconds;

  /// Pospuesto hasta esta hora (solo la ocurrencia actual).
  DateTime? snoozedUntil;

  /// Hecho (solo los que no se repiten; los que se repiten pasan a la siguiente).
  DateTime? doneAt;

  /// Veces que se marcó hecho (las últimas 200).
  List<DateTime> completions;
  DateTime createdAt;

  bool get done => doneAt != null;

  bool get isCountdown => countdownSeconds > 0;

  /// Hora en que suena el aviso de la ocurrencia actual.
  DateTime get alertAt => snoozedUntil ?? dueAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'notes': notes,
        'due': dueAt.toIso8601String(),
        'recurrence': recurrence.toJson(),
        'nag': nagMinutes,
        'countdown': countdownSeconds,
        'snoozed': snoozedUntil?.toIso8601String(),
        'done': doneAt?.toIso8601String(),
        'completions': completions.map((DateTime d) => d.toIso8601String()).toList(),
        'created': createdAt.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, dynamic> j) {
    final Object? rec = j['recurrence'];
    final Object? comp = j['completions'];
    final DateTime created = DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime(2026);
    return Reminder(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      notes: (j['notes'] as String?) ?? '',
      dueAt: DateTime.tryParse(j['due'] as String? ?? '') ?? created,
      recurrence: rec is Map<String, dynamic> ? Recurrence.fromJson(rec) : const Recurrence(),
      nagMinutes: ((j['nag'] as num?)?.toInt() ?? 0).clamp(0, 60),
      countdownSeconds: (j['countdown'] as num?)?.toInt() ?? 0,
      snoozedUntil: DateTime.tryParse(j['snoozed'] as String? ?? ''),
      doneAt: DateTime.tryParse(j['done'] as String? ?? ''),
      completions: comp is List ? comp.whereType<String>().map(DateTime.tryParse).whereType<DateTime>().toList() : <DateTime>[],
      createdAt: created,
    );
  }
}
