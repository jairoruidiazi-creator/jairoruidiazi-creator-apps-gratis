import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../core/notifications.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../logic/notice_plan.dart';
import '../model/habit.dart';
import '../model/reminder.dart';
import 'habit_store.dart';
import 'reminder_store.dart';
import 'timer_store.dart';

/// Un aviso programado que ya debió sonar: puede seguir en el panel.
class _Shown {
  const _Shown(this.route, this.when);

  final String route;
  final DateTime when;
}

/// Mantiene programadas las notificaciones que pide el plan.
///
/// En iOS compara el plan con lo pendiente en el sistema y solo programa o
/// cancela lo que cambió. En Android la lista de pendientes es la del plugin,
/// que no se entera cuando el sistema borra las alarmas (forzar detención,
/// quitar el permiso de alarmas exactas, una copia restaurada en otro
/// teléfono): por eso en la primera sincronización de cada proceso se
/// reprograma todo. También se reprograma todo después de restaurar una copia,
/// al cambiar el permiso de alarmas exactas y al cambiar el idioma.
class NoticeService extends ChangeNotifier {
  NoticeService({required this.gateway, required this.settings, required this.habits, required this.reminders, required this.timers, this.store});

  final NotificationGateway gateway;
  final AppSettings settings;
  final HabitStore habits;
  final ReminderStore reminders;
  final TimerStore timers;

  /// Carpeta de la app, para el registro de avisos (`avisos.json`); null en
  /// pruebas que no lo necesitan.
  final JsonStore? store;

  /// Archivo con lo programado y lo que ya sonó. No viaja en las copias.
  static const String logFile = 'avisos.json';

  /// La app está en segundo plano: el plan incluye los cambios del temporizador.
  bool background = false;

  NoticePermissions permissions = const NoticePermissions(notifications: null, exactAlarms: true, exactAlarmsApply: false);
  Timer? _debounce;
  Timer? _transition;
  bool _syncing = false;
  bool _again = false;
  bool _fullResync = false;
  bool _syncedOnce = false;
  bool? _lastExact;
  bool? _lastSpanish;
  bool _logLoaded = false;
  final Set<int> _timerIds = <int>{};
  void Function(NoticeResponse response)? _handler;
  NoticeResponse? _waiting;

  /// Último plan aplicado (para las pruebas, el diagnóstico y la cobertura).
  NoticePlan lastPlan = const NoticePlan();

  /// Avisos ya vencidos que pueden seguir en el panel (id → ruta y hora).
  final Map<int, _Shown> _shown = <int, _Shown>{};

  /// Lo programado en la última sincronización (id → ruta y hora).
  final Map<int, _Shown> _scheduled = <int, _Shown>{};

  /// Número de cada aviso del último plan, por su clave.
  final Map<String, int> _idByKey = <String, int>{};

  NoticeLimits get limits => gateway.isIOS ? kIosLimits : kAndroidLimits;

  /// Hasta cuándo llegan los avisos si no se abre la app (null si cubre todo
  /// el horizonte normal).
  DateTime? get coveredUntil => lastPlan.coveredUntil;

  /// ¿La próxima sincronización reprograma todo? (para las pruebas)
  bool get pendingFullResync => _fullResync || (!gateway.isIOS && !_syncedOnce);

  Future<void> init() async {
    await gateway.init(onResponse: _onResponse, spanish: settings.spanish);
    _lastSpanish = settings.spanish;
    _loadLog();
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

  /// Con la app abierta: pasa los recordatorios vencidos a la ocurrencia que
  /// toca y vuelve a planear (al sonar el primer aviso de algo que insiste o al
  /// llegar al final de lo cubierto).
  void _transitionNow() {
    reminders.rollOverAll();
    requestSync();
  }

  /// Al volver a la app: si cambió el permiso de alarmas exactas (por ejemplo,
  /// se concedió en Configuración), todo se vuelve a programar con el modo nuevo.
  Future<void> resumed() async {
    await refreshPermissions();
    await sync();
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

  /// Abre el ajuste de alarmas exactas. Al volver, [resumed] reprograma todo
  /// si el permiso cambió.
  Future<void> askExactAlarms() async {
    await gateway.requestExactAlarms();
    await refreshPermissions();
    await sync();
  }

  Future<void> openSystemSettings() => gateway.openSettings();

  /// Cambió el idioma de la app: canales, botones y textos en el idioma nuevo.
  Future<void> languageChanged() async {
    _fullResync = true;
    await sync();
  }

  /// Se restauró una copia: todo se vuelve a programar desde cero.
  Future<void> afterRestore() async {
    _fullResync = true;
    await sync();
  }

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
    _loadLog();
    final NoticePermissions perm = await gateway.permissions();
    permissions = perm;
    if (_lastExact != null && perm.exactAlarms != _lastExact) {
      // Con el permiso nuevo, todo pasa a alarmas exactas (o deja de serlo).
      _fullResync = true;
    }
    if (_lastSpanish != null && _lastSpanish != settings.spanish) {
      await gateway.setLanguage(settings.spanish);
      _fullResync = true;
    }
    final DateTime now = clock.now();
    _rememberShown(now);
    final NoticePlan plan = NoticePlanner.build(
      now: now,
      reminders: reminders.reminders,
      habits: habits.habits,
      entries: habits.entries,
      weekStart: settings.weekStart,
      spanish: settings.spanish,
      backgroundRun: background ? timers.run : null,
      limits: limits,
      sounds: settings.sounds,
      vibration: settings.vibration,
    );
    final Map<int, PlannedNotice> byId = <int, PlannedNotice>{};
    for (final PlannedNotice n in plan.notices) {
      int id = noticeIdFor(n.key);
      while (byId.containsKey(id)) {
        id = id % 0x7FFFFFFE + 1;
      }
      byId[id] = n;
    }
    final bool exact = perm.exactAlarms;
    // En iOS la lista de pendientes es la real; en Android, la primera vez en
    // cada proceso no se le cree a la lista del plugin.
    final bool full = _fullResync || (!gateway.isIOS && !_syncedOnce);
    final Map<int, String?> current = <int, String?>{};
    for (final PendingNotice p in await gateway.pending()) {
      current[p.id] = p.payload;
    }
    if (!background) {
      // De vuelta en la app: se quitan del panel los avisos del temporizador
      // que ya sonaron (los que siguen pendientes los cancela lo de abajo).
      for (final int id in _timerIds) {
        if (!byId.containsKey(id) && !current.containsKey(id)) {
          await gateway.cancel(id);
        }
      }
      _timerIds.clear();
    }
    if (full) {
      // Primero se programa todo (el mismo número reemplaza la alarma que
      // hubiera) y después se cancela lo que sobra: si el proceso muere a mitad
      // de camino, lo que ya estaba programado sigue en pie. Lo que sobra sale
      // de la lista del plugin y del registro propio (lo que todavía no sonó).
      final Set<int> stale = <int>{
        ...current.keys,
        for (final MapEntry<int, _Shown> e in _scheduled.entries)
          if (e.value.when.isAfter(now)) e.key,
      };
      for (final MapEntry<int, PlannedNotice> e in byId.entries) {
        await gateway.schedule(e.value, e.key, exact: exact, payload: e.value.payload(exact: exact));
      }
      for (final int id in stale) {
        if (!byId.containsKey(id)) {
          await gateway.cancel(id);
        }
      }
    } else {
      // Primero se cancela lo que sobra y después se programa lo nuevo: así
      // nunca hay más pendientes que el cupo (iOS guarda 64).
      for (final int id in current.keys) {
        if (!byId.containsKey(id)) {
          await gateway.cancel(id);
        }
      }
      for (final MapEntry<int, PlannedNotice> e in byId.entries) {
        final String payload = e.value.payload(exact: exact);
        if (!current.containsKey(e.key) || current[e.key] != payload) {
          await gateway.schedule(e.value, e.key, exact: exact, payload: payload);
        }
      }
    }
    _fullResync = false;
    _syncedOnce = true;
    _lastExact = exact;
    _lastSpanish = settings.spanish;
    final Set<int> timerIds = byId.entries.where((MapEntry<int, PlannedNotice> e) => e.value.isTimer).map((MapEntry<int, PlannedNotice> e) => e.key).toSet();
    if (background) {
      _timerIds.addAll(timerIds);
    }
    _scheduled
      ..clear()
      ..addEntries(byId.entries.map((MapEntry<int, PlannedNotice> e) => MapEntry<int, _Shown>(e.key, _Shown(e.value.route, e.value.when))));
    _idByKey
      ..clear()
      ..addEntries(byId.entries.map((MapEntry<int, PlannedNotice> e) => MapEntry<String, int>(e.value.key, e.key)));
    _saveLog();
    lastPlan = plan;
    _armTransition(plan, now);
    notifyListeners();
  }

  /// Con la app abierta, al sonar el primer aviso de algo que insiste se vuelve
  /// a planear: su insistencia pasa a una sola solicitud que se repite. También
  /// al llegar al final de lo cubierto, para extenderlo.
  void _armTransition(NoticePlan plan, DateTime now) {
    _transition?.cancel();
    _transition = null;
    if (background) {
      return;
    }
    DateTime? at = plan.coveredUntil;
    final Set<String> nagging = <String>{
      for (final Reminder r in reminders.reminders)
        if (!r.done && r.nagMinutes > 0) 'reminder:${r.id}',
    };
    for (final PlannedNotice n in plan.notices) {
      if (n.kind == NoticeKind.first && nagging.contains(n.route) && (at == null || n.when.isBefore(at))) {
        at = n.when;
      }
    }
    if (at == null) {
      return;
    }
    Duration wait = at.difference(now) + const Duration(seconds: 1);
    if (wait.isNegative) {
      wait = const Duration(seconds: 1);
    }
    // Los temporizadores de Dart no pasan de unos 24 días; con un día basta.
    if (wait > const Duration(days: 1)) {
      wait = const Duration(days: 1);
    }
    _transition = Timer(wait, _transitionNow);
  }

  // ------------------------------------------------------------------ registro

  void _loadLog() {
    final JsonStore? s = store;
    if (_logLoaded || s == null) {
      return;
    }
    _logLoaded = true;
    try {
      final Map<String, dynamic>? j = s.readJsonSync(logFile);
      void read(Object? list, Map<int, _Shown> into) {
        if (list is! List) {
          return;
        }
        for (final Object? item in list) {
          if (item is Map<String, dynamic>) {
            final int? id = (item['id'] as num?)?.toInt();
            final String? route = item['route'] as String?;
            final int? when = (item['when'] as num?)?.toInt();
            if (id != null && route != null && when != null) {
              into[id] = _Shown(route, DateTime.fromMillisecondsSinceEpoch(when));
            }
          }
        }
      }

      read(j?['scheduled'], _scheduled);
      read(j?['shown'], _shown);
    } catch (e) {
      debugPrint('No se pudo leer el registro de avisos: $e');
    }
  }

  void _saveLog() {
    final JsonStore? s = store;
    if (s == null) {
      return;
    }
    List<Map<String, dynamic>> write(Map<int, _Shown> m) => m.entries.map((MapEntry<int, _Shown> e) => <String, dynamic>{'id': e.key, 'route': e.value.route, 'when': e.value.when.millisecondsSinceEpoch}).toList();
    try {
      s.writeJsonSync(logFile, <String, dynamic>{'scheduled': write(_scheduled), 'shown': write(_shown)});
    } catch (e) {
      debugPrint('No se pudo guardar el registro de avisos: $e');
    }
  }

  /// Lo que se programó y ya debió sonar puede estar en el panel: se anota
  /// para poder quitarlo después. Se olvida a los 15 días.
  void _rememberShown(DateTime now) {
    for (final MapEntry<int, _Shown> e in _scheduled.entries) {
      if (!e.value.when.isAfter(now)) {
        _shown[e.key] = e.value;
      }
    }
    final DateTime old = now.subtract(const Duration(days: 15));
    _shown.removeWhere((int id, _Shown s) => s.when.isBefore(old));
  }

  Future<void> _dismissRoute(bool Function(String route) match) async {
    final DateTime now = clock.now();
    _rememberShown(now);
    final Set<int> ids = <int>{};
    for (final MapEntry<int, _Shown> e in _shown.entries) {
      if (match(e.value.route)) {
        ids.add(e.key);
      }
    }
    // Lo que ya sonó en este plan y la solicitud que se repite.
    for (final MapEntry<int, _Shown> e in _scheduled.entries) {
      if (match(e.value.route) && !e.value.when.isAfter(now)) {
        ids.add(e.key);
      }
    }
    for (final PlannedNotice n in lastPlan.notices) {
      final int? id = _idByKey[n.key];
      if (n.kind == NoticeKind.repeating && match(n.route) && id != null) {
        ids.add(id);
      }
    }
    for (final int id in ids) {
      await gateway.cancel(id);
      _shown.remove(id);
    }
    _saveLog();
  }

  /// Quita del panel todas las notificaciones de un recordatorio, también las
  /// de ocurrencias anteriores (al marcarlo hecho, posponerlo o borrarlo).
  Future<void> dismissReminder(Reminder r) => _dismissRoute((String route) => route == 'reminder:${r.id}');

  /// Igual para los avisos de un hábito en un día.
  Future<void> dismissHabit(Habit h, DateTime day) {
    final String route = 'habit:${h.id}:${dayKey(dateOnly(day))}';
    return _dismissRoute((String r) => r == route);
  }

  /// Quita del panel una sola notificación (la de una ocurrencia vieja).
  Future<void> dismissOne(int id) async {
    await gateway.cancel(id);
    _shown.remove(id);
    _saveLog();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _transition?.cancel();
    super.dispose();
  }
}
