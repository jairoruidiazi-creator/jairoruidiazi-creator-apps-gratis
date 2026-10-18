import 'dart:convert';

import '../model/habit.dart';
import '../model/reminder.dart';
import '../model/workout.dart';
import '../state/habit_store.dart';
import '../state/reminder_store.dart';
import '../state/timer_store.dart';
import 'app_info.dart';
import 'dates.dart';
import 'settings.dart';
import 'storage.dart';

/// Lo que trae un archivo de copia, ya leído entero y validado, para
/// confirmarlo antes de restaurar.
class BackupContents {
  const BackupContents({required this.data, required this.exportedAt, required this.habitStore, required this.reminderStore, required this.timerStore});

  final Map<String, dynamic> data;
  final DateTime? exportedAt;

  /// Los datos de la copia en almacenes en memoria (no tocan el disco).
  final HabitStore habitStore;
  final ReminderStore reminderStore;
  final TimerStore timerStore;

  int get habits => habitStore.habits.length;

  /// Días con algún registro de hábito.
  int get days => habitStore.entries.values.expand((Map<String, HabitEntry> m) => m.keys).toSet().length;
  int get reminders => reminderStore.reminders.length;
  int get workouts => timerStore.workouts.length;
  int get sessions => timerStore.sessions.length;
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

  /// Lee y valida un archivo de copia entero, con los mismos lectores de la
  /// app y en memoria: si algo está dañado se sabe antes de borrar lo que hay.
  /// Lanza [FormatException] con un motivo legible si no es una copia de
  /// Rutinas o no se puede leer.
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
    for (final String key in <String>['habits', 'reminders', 'timers', 'settings']) {
      final Object? p = root[key];
      if (p != null && p is! Map<String, dynamic>) {
        throw const FormatException('damaged');
      }
    }
    Map<String, dynamic> part(String key) {
      final Object? p = root[key];
      return p is Map<String, dynamic> ? p : <String, dynamic>{};
    }

    // Almacenes en memoria sobre una carpeta sin resolver: leer JSON no toca el disco.
    final JsonStore nowhere = JsonStore();
    final HabitStore habits = HabitStore(nowhere);
    final ReminderStore reminders = ReminderStore(nowhere);
    final TimerStore timers = TimerStore(nowhere);
    try {
      habits.fromJson(part('habits'));
      reminders.fromJson(part('reminders'));
      timers.fromJson(part('timers'));
    } catch (_) {
      throw const FormatException('damaged');
    }
    // Fechas fuera de lo razonable vienen de un archivo dañado o manipulado.
    for (final Habit h in habits.habits) {
      if (h.id.isEmpty || !isSaneDate(h.startDate)) {
        throw const FormatException('damaged');
      }
    }
    for (final Reminder r in reminders.reminders) {
      if (r.id.isEmpty || !isSaneDate(r.dueAt) || (r.snoozedUntil != null && !isSaneDate(r.snoozedUntil!))) {
        throw const FormatException('damaged');
      }
    }
    if (timers.workouts.any((Workout w) => w.id.isEmpty) || timers.presets.any((CountdownPreset p) => p.id.isEmpty) || timers.sessions.any((WorkoutSession s) => s.id.isEmpty)) {
      throw const FormatException('damaged');
    }
    return BackupContents(
      data: root,
      exportedAt: DateTime.tryParse(root['exportedAt'] as String? ?? ''),
      habitStore: habits,
      reminderStore: reminders,
      timerStore: timers,
    );
  }

  /// Reemplaza todos los datos por los de la copia, ya leída entera en
  /// [decode]: aquí no queda nada que pueda fallar a mitad de camino. El
  /// cronómetro y el temporizador en marcha no viajan y se conservan.
  static Future<void> restore(BackupContents c, {required HabitStore habits, required ReminderStore reminders, required TimerStore timers, required AppSettings settings}) async {
    habits.replaceWith(c.habitStore);
    reminders.replaceWith(c.reminderStore);
    timers.replaceBackupWith(c.timerStore);
    final Object? s = c.data['settings'];
    if (s is Map<String, dynamic> && s.isNotEmpty) {
      settings.applyJson(s);
      await settings.save();
    }
  }
}
