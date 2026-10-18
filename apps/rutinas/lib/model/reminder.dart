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
  const Recurrence({this.type = RecurrenceType.once, this.n = 1, this.weekdays = const <int>[], this.day = 1, this.month = 1, this.hour, this.minute});

  final RecurrenceType type;
  final int n;
  final List<int> weekdays;
  final int day;
  final int month;

  /// Hora y minuto de cada ocurrencia, en hora local. Se guardan en la regla y
  /// no se sacan de la ocurrencia anterior: el día del cambio de horario en que
  /// esa hora no existe (el reloj salta de 2:00 a 3:00), el aviso suena a la
  /// hora que da el sistema, y desde el día siguiente vuelve a la de la regla.
  /// Null en las reglas viejas: se toma la hora del recordatorio.
  final int? hour;
  final int? minute;

  bool get repeats => type != RecurrenceType.once;

  /// La misma regla a la hora [h]:[m].
  Recurrence withTime(int h, int m) => Recurrence(type: type, n: n, weekdays: weekdays, day: day, month: month, hour: h, minute: m);

  /// La misma regla con la hora de [d] si todavía no tiene una.
  Recurrence withTimeOf(DateTime d) => hour != null ? this : withTime(d.hour, d.minute);

  Recurrence normalized() {
    final int? rawHour = hour;
    final int? h = rawHour?.clamp(0, 23);
    final int? m = h == null ? null : (minute ?? 0).clamp(0, 59);
    switch (type) {
      case RecurrenceType.once:
      case RecurrenceType.monthlyLast:
        return Recurrence(type: type, hour: h, minute: m);
      case RecurrenceType.everyNDays:
        return Recurrence(type: type, n: n.clamp(1, 365), hour: h, minute: m);
      case RecurrenceType.weekdays:
        final List<int> days = weekdays.where((int d) => d >= 1 && d <= 7).toSet().toList()..sort();
        if (days.isEmpty) {
          return Recurrence(type: RecurrenceType.everyNDays, hour: h, minute: m);
        }
        return Recurrence(type: type, weekdays: days, hour: h, minute: m);
      case RecurrenceType.monthlyDay:
        return Recurrence(type: type, day: day.clamp(1, 31), hour: h, minute: m);
      case RecurrenceType.yearly:
        final int mo = month.clamp(1, 12);
        // El año de referencia es bisiesto para admitir el 29 de febrero.
        return Recurrence(type: type, month: mo, day: day.clamp(1, daysInMonth(2024, mo)), hour: h, minute: m);
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'n': n,
        'days': weekdays,
        'day': day,
        'month': month,
        if (hour != null) 'hour': hour,
        if (hour != null) 'minute': minute ?? 0,
      };

  factory Recurrence.fromJson(Map<String, dynamic> j) {
    final Object? days = j['days'];
    return Recurrence(
      type: recurrenceTypeFrom(j['type']),
      n: (j['n'] as num?)?.toInt() ?? 1,
      weekdays: days is List ? days.whereType<num>().map((num d) => d.toInt()).toList() : const <int>[],
      day: (j['day'] as num?)?.toInt() ?? 1,
      month: (j['month'] as num?)?.toInt() ?? 1,
      hour: (j['hour'] as num?)?.toInt(),
      minute: (j['minute'] as num?)?.toInt(),
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      other is Recurrence && other.type == type && other.n == n && other.day == day && other.month == month && other.hour == hour && other.minute == minute && other.weekdays.join(',') == weekdays.join(',');

  @override
  int get hashCode => Object.hash(type, n, day, month, hour, minute, weekdays.join(','));
}

class Reminder {
  Reminder({
    required this.id,
    required this.title,
    this.notes = '',
    required this.dueAt,
    Recurrence recurrence = const Recurrence(),
    this.nagMinutes = 0,
    this.countdownSeconds = 0,
    this.snoozedUntil,
    this.doneAt,
    List<DateTime>? completions,
    required this.createdAt,
  })  : recurrence = recurrence.repeats ? recurrence.withTimeOf(dueAt) : recurrence,
        completions = completions ?? <DateTime>[];

  final String id;
  String title;
  String notes;

  /// Fecha y hora de la ocurrencia actual (la próxima o la vencida sin hacer).
  DateTime dueAt;

  /// Cómo se repite. Si se repite, siempre lleva su hora (la de [dueAt] al
  /// crearlo, si la regla no traía una).
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
