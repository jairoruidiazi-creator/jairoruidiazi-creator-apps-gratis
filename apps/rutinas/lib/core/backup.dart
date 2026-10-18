import 'dart:convert';

import '../logic/stopwatch.dart';
import '../logic/timer_engine.dart';
import '../model/habit.dart';
import '../model/reminder.dart';
import '../model/workout.dart';
import '../state/habit_store.dart';
import '../state/reminder_store.dart';
import '../state/timer_store.dart';
import 'app_info.dart';
import 'settings.dart';

/// Lo que trae un archivo de copia, para confirmarlo antes de restaurar.
class BackupContents {
  const BackupContents({required this.data, required this.exportedAt, required this.habits, required this.days, required this.reminders, required this.workouts, required this.sessions});

  final Map<String, dynamic> data;
  final DateTime? exportedAt;
  final int habits;

  /// Días con algún registro de hábito.
  final int days;
  final int reminders;
  final int workouts;
  final int sessions;
}

/// Copia de seguridad en un archivo JSON propio. Sin cuenta, es la forma de
/// pasar los datos a otro teléfono: se exporta con la hoja de compartir y se
/// importa eligiendo el archivo.
class Backups {
  Backups._();

  static const String format = 'rutinas-backup';
  static const int version = 1;

  static Map<String, dynamic> build({required HabitStore habits, required ReminderStore reminders, required TimerStore timers, required AppSettings settings, required DateTime now}) => <String, dynamic>{
        'format': format,
        'version': version,
        'app': '$kAppName $kAppVersion',
        'exportedAt': now.toIso8601String(),
        'habits': habits.toJson(),
        'reminders': reminders.toJson(),
        'timers': timers.toBackupJson(),
        'settings': settings.toJson(),
      };

  static String encode(Map<String, dynamic> data) => const JsonEncoder.withIndent(' ').convert(data);

  /// Nombre del archivo: `rutinas-2026-10-18.json`.
  static String fileName(DateTime now) => 'rutinas-${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';

  /// Lee y valida un archivo de copia. Lanza [FormatException] con un motivo
  /// legible si no es una copia de Rutinas o no se puede leer.
  static BackupContents decode(String text) {
    dynamic root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      throw const FormatException('not-json');
    }
    if (root is! Map<String, dynamic> || root['format'] != format) {
      throw const FormatException('not-rutinas');
    }
    final Object? v = root['version'];
    if (v is! num || v.toInt() > version) {
      throw const FormatException('newer-version');
    }
    Map<String, dynamic> part(String key) {
      final Object? p = root[key];
      return p is Map<String, dynamic> ? p : <String, dynamic>{};
    }

    // Se prueba a leer todo con los mismos lectores de la app: si algo está
    // dañado, se sabe antes de borrar lo que hay.
    int habits = 0;
    int days = 0;
    int reminders = 0;
    int workouts = 0;
    int sessions = 0;
    try {
      final Map<String, dynamic> h = part('habits');
      final Object? hl = h['habits'];
      if (hl is List) {
        habits = hl.whereType<Map<String, dynamic>>().map(Habit.fromJson).toList().length;
      }
      final Object? e = h['entries'];
      if (e is Map<String, dynamic>) {
        final Set<String> keys = <String>{};
        for (final Object? m in e.values) {
          if (m is Map<String, dynamic>) {
            keys.addAll(m.keys);
            m.values.whereType<Map<String, dynamic>>().map(HabitEntry.fromJson).toList();
          }
        }
        days = keys.length;
      }
      final Object? rl = part('reminders')['reminders'];
      if (rl is List) {
        reminders = rl.whereType<Map<String, dynamic>>().map(Reminder.fromJson).toList().length;
      }
      final Map<String, dynamic> t = part('timers');
      final Object? wl = t['workouts'];
      if (wl is List) {
        workouts = wl.whereType<Map<String, dynamic>>().map(Workout.fromJson).toList().length;
      }
      final Object? sl = t['sessions'];
      if (sl is List) {
        sessions = sl.whereType<Map<String, dynamic>>().map(WorkoutSession.fromJson).toList().length;
      }
    } catch (_) {
      throw const FormatException('damaged');
    }
    return BackupContents(
      data: root,
      exportedAt: DateTime.tryParse(root['exportedAt'] as String? ?? ''),
      habits: habits,
      days: days,
      reminders: reminders,
      workouts: workouts,
      sessions: sessions,
    );
  }

  /// Reemplaza todos los datos por los de la copia.
  static Future<void> restore(BackupContents c, {required HabitStore habits, required ReminderStore reminders, required TimerStore timers, required AppSettings settings}) async {
    Map<String, dynamic> part(String key) {
      final Object? p = c.data[key];
      return p is Map<String, dynamic> ? p : <String, dynamic>{};
    }

    habits.reset();
    habits.fromJson(part('habits'));
    habits.changed();
    habits.flush();
    reminders.reset();
    reminders.fromJson(part('reminders'));
    reminders.changed();
    reminders.flush();
    // El cronómetro y el temporizador en marcha no viajan: se conservan.
    final TimerRunKeeper keep = TimerRunKeeper(timers);
    timers.reset();
    timers.fromJson(part('timers'));
    keep.putBack(timers);
    timers.changed();
    timers.flush();
    final Map<String, dynamic> s = part('settings');
    if (s.isNotEmpty) {
      settings.applyJson(s);
      await settings.save();
    }
  }
}

/// Guarda el cronómetro y el temporizador en marcha mientras se restaura.
class TimerRunKeeper {
  TimerRunKeeper(TimerStore t)
      : _stopwatch = t.stopwatch,
        _run = t.run;

  final StopwatchState _stopwatch;
  final TimerRun? _run;

  void putBack(TimerStore t) {
    t.stopwatch = _stopwatch;
    t.run = _run;
  }
}
