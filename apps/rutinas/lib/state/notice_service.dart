import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../core/notifications.dart';
import '../core/settings.dart';
import '../logic/notice_plan.dart';
import '../model/habit.dart';
import '../model/reminder.dart';
import 'habit_store.dart';
import 'reminder_store.dart';
import 'timer_store.dart';

/// Mantiene programadas las notificaciones que pide el plan: compara el plan
/// con lo pendiente en el sistema y solo programa o cancela lo que cambió.
class NoticeService extends ChangeNotifier {
  NoticeService({required this.gateway, required this.settings, required this.habits, required this.reminders, required this.timers});

  final NotificationGateway gateway;
  final AppSettings settings;
  final HabitStore habits;
  final ReminderStore reminders;
  final TimerStore timers;

  /// La app está en segundo plano: el plan incluye los cambios del temporizador.
  bool background = false;

  NoticePermissions permissions = const NoticePermissions(notifications: null, exactAlarms: true, exactAlarmsApply: false);
  Timer? _debounce;
  bool _syncing = false;
  bool _again = false;
  final Set<int> _timerIds = <int>{};
  void Function(NoticeResponse response)? _handler;
  NoticeResponse? _waiting;

  /// Último plan aplicado (para las pruebas y el diagnóstico).
  List<PlannedNotice> lastPlan = const <PlannedNotice>[];

  Future<void> init() async {
    await gateway.init(onResponse: _onResponse, spanish: settings.spanish);
    await refreshPermissions();
    final NoticeResponse? launch = await gateway.launchResponse();
    if (launch != null) {
      _onResponse(launch);
    }
  }

  /// Quién atiende los toques en las notificaciones (la pantalla principal).
  set handler(void Function(NoticeResponse response)? value) {
    _handler = value;
    final NoticeResponse? w = _waiting;
    if (value != null && w != null) {
      _waiting = null;
      value(w);
    }
  }

  void _onResponse(NoticeResponse r) {
    final void Function(NoticeResponse)? h = _handler;
    if (h == null) {
      _waiting = r;
    } else {
      h(r);
    }
  }

  Future<NoticePermissions> refreshPermissions() async {
    permissions = await gateway.permissions();
    notifyListeners();
    return permissions;
  }

  /// Pide el permiso de notificaciones (una sola vez por su cuenta; después,
  /// desde Ajustes).
  Future<bool> askNotifications({bool force = false}) async {
    if (!force && settings.askedNotifications) {
      return permissions.notifications ?? false;
    }
    settings.askedNotifications = true;
    unawaited(settings.save());
    final bool ok = await gateway.requestNotifications();
    await refreshPermissions();
    return ok;
  }

  Future<void> askExactAlarms() async {
    await gateway.requestExactAlarms();
    await refreshPermissions();
    await sync();
  }

  Future<void> openSystemSettings() => gateway.openSettings();

  /// Reprograma en un momento (agrupa varios cambios seguidos).
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(sync());
    });
  }

  Future<void> sync() async {
    _debounce?.cancel();
    _debounce = null;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again);
    } catch (e) {
      debugPrint('No se pudieron programar los avisos: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    final NoticePermissions perm = await gateway.permissions();
    permissions = perm;
    final DateTime now = clock.now();
    final List<PlannedNotice> plan = NoticePlanner.build(
      now: now,
      reminders: reminders.reminders,
      habits: habits.habits,
      entries: habits.entries,
      weekStart: settings.weekStart,
      spanish: settings.spanish,
      backgroundRun: background ? timers.run : null,
      budget: gateway.isIOS ? kIosNoticeBudget : kAndroidNoticeBudget,
    );
    final Map<int, PlannedNotice> byId = <int, PlannedNotice>{};
    for (final PlannedNotice n in plan) {
      int id = noticeIdFor(n.key);
      while (byId.containsKey(id)) {
        id = id % 0x7FFFFFFE + 1;
      }
      byId[id] = n;
    }
    final Map<int, String?> current = <int, String?>{};
    for (final PendingNotice p in await gateway.pending()) {
      current[p.id] = p.payload;
    }
    for (final MapEntry<int, PlannedNotice> e in byId.entries) {
      if (current[e.key] != e.value.payload || !current.containsKey(e.key)) {
        await gateway.schedule(e.value, e.key, exact: perm.exactAlarms);
      }
    }
    for (final int id in current.keys) {
      if (!byId.containsKey(id)) {
        await gateway.cancel(id);
      }
    }
    final Set<int> timerIds = byId.entries.where((MapEntry<int, PlannedNotice> e) => e.value.isTimer).map((MapEntry<int, PlannedNotice> e) => e.key).toSet();
    if (background) {
      _timerIds.addAll(timerIds);
    } else {
      // De vuelta en la app: se quitan también los avisos del temporizador que
      // ya se mostraron.
      for (final int id in _timerIds) {
        if (!byId.containsKey(id)) {
          await gateway.cancel(id);
        }
      }
      _timerIds.clear();
    }
    lastPlan = plan;
    notifyListeners();
  }

  /// Quita del panel las notificaciones ya mostradas de la ocurrencia actual
  /// de un recordatorio (al marcarlo hecho o posponerlo).
  Future<void> dismissReminder(Reminder r, DateTime alert) async {
    final DateTime now = clock.now();
    final List<String> keys = <String>['r:${r.id}:${alert.millisecondsSinceEpoch}'];
    if (r.nagMinutes > 0) {
      for (int j = 1; j <= kMaxNags; j++) {
        final DateTime t = alert.add(Duration(minutes: r.nagMinutes * j));
        if (t.isAfter(now)) {
          break;
        }
        keys.add('n:${r.id}:${t.millisecondsSinceEpoch}');
      }
    }
    for (final String k in keys) {
      await gateway.cancel(noticeIdFor(k));
    }
  }

  /// Igual para los avisos de un hábito en un día.
  Future<void> dismissHabit(Habit h, DateTime day) async {
    final DateTime now = clock.now();
    final DateTime d = dateOnly(day);
    for (final int m in h.reminders) {
      final DateTime at = DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
      if (at.isAfter(now)) {
        continue;
      }
      await gateway.cancel(noticeIdFor('h:${h.id}:${at.millisecondsSinceEpoch}'));
      if (h.nagMinutes > 0) {
        for (int j = 1; j <= kMaxNags; j++) {
          final DateTime t = at.add(Duration(minutes: h.nagMinutes * j));
          if (t.isAfter(now) || !t.isBefore(addDays(d, 1))) {
            break;
          }
          await gateway.cancel(noticeIdFor('g:${h.id}:${t.millisecondsSinceEpoch}'));
        }
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
