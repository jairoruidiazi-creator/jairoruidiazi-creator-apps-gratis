import 'package:flutter/widgets.dart';

import '../state/habit_store.dart';
import '../state/notice_service.dart';
import '../state/reminder_store.dart';
import '../state/timer_controller.dart';
import '../state/timer_store.dart';
import 'backup_io.dart';
import 'cues.dart';
import 'notifications.dart';
import 'settings.dart';
import 'storage.dart';

/// Servicios compartidos de la app.
class Services {
  Services({required this.settings, required this.store, required this.habits, required this.reminders, required this.timers, required this.timer, required this.notices, required this.cues, required this.io});

  /// Arma los servicios sobre una carpeta ya resuelta ([JsonStore.root]) y
  /// carga los datos guardados.
  factory Services.create({required AppSettings settings, required JsonStore store, required NotificationGateway gateway, required CuePlayer cues, required ScreenWake screen, required BackupIO io}) {
    final HabitStore habits = HabitStore(store)..load();
    final ReminderStore reminders = ReminderStore(store)..load();
    final TimerStore timers = TimerStore(store)..load();
    final TimerController timer = TimerController(store: timers, cues: cues, settings: settings, habits: habits, screen: screen);
    final NoticeService notices = NoticeService(gateway: gateway, settings: settings, habits: habits, reminders: reminders, timers: timers, store: store);
    habits.onChanged = notices.requestSync;
    reminders.onChanged = notices.requestSync;
    return Services(settings: settings, store: store, habits: habits, reminders: reminders, timers: timers, timer: timer, notices: notices, cues: cues, io: io);
  }

  final AppSettings settings;
  final JsonStore store;
  final HabitStore habits;
  final ReminderStore reminders;
  final TimerStore timers;
  final TimerController timer;
  final NoticeService notices;
  final CuePlayer cues;
  final BackupIO io;

  /// Escribe lo pendiente de todos los almacenes.
  void flushAll() {
    habits.flush();
    reminders.flush();
    timers.flush();
  }

  void dispose() {
    timer.dispose();
    notices.dispose();
    flushAll();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final Services services;

  static Services of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No hay AppScope en el árbol');
    return scope!.services;
  }

  /// Sin suscribirse a cambios (para callbacks).
  static Services read(BuildContext context) {
    final AppScope? scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No hay AppScope en el árbol');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}

/// Texto en el idioma de la app: `t(context, 'Hábitos', 'Habits')`.
String t(BuildContext context, String es, String en) => AppScope.of(context).settings.spanish ? es : en;

bool isSpanish(BuildContext context) => AppScope.of(context).settings.spanish;
