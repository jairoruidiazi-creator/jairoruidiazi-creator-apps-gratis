import 'dart:io';
import 'dart:ui' show Color;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/notice_plan.dart';

/// Respuesta a una notificación: un toque o uno de sus botones.
class NoticeResponse {
  const NoticeResponse(this.payload, this.actionId);

  final String? payload;

  /// `done`, `snooze` o `plus`; null si se tocó la notificación.
  final String? actionId;

  String get route => routeOfPayload(payload);
}

/// Estado de los permisos de avisos.
class NoticePermissions {
  const NoticePermissions({required this.notifications, required this.exactAlarms, required this.exactAlarmsApply});

  /// ¿Se pueden mostrar notificaciones? Null si no se sabe.
  final bool? notifications;

  /// ¿Se pueden programar alarmas exactas? (Siempre en iOS y antes de Android 12.)
  final bool exactAlarms;

  /// El permiso de alarmas exactas existe en este teléfono (Android 12 o superior).
  final bool exactAlarmsApply;
}

class PendingNotice {
  const PendingNotice(this.id, this.payload);

  final int id;
  final String? payload;
}

/// Lo que la app necesita del sistema de notificaciones.
abstract class NotificationGateway {
  Future<void> init({required void Function(NoticeResponse) onResponse, required bool spanish});

  /// Si la app se abrió desde una notificación, su respuesta.
  Future<NoticeResponse?> launchResponse();

  Future<NoticePermissions> permissions();

  Future<bool> requestNotifications();

  /// Abre el ajuste del sistema para las alarmas exactas (Android 12+).
  Future<bool> requestExactAlarms();

  /// Abre los ajustes de notificaciones de la app en el sistema.
  Future<void> openSettings();

  Future<List<PendingNotice>> pending();

  Future<void> schedule(PlannedNotice notice, int id, {required bool exact});

  Future<void> cancel(int id);

  /// iOS guarda menos notificaciones programadas que Android.
  bool get isIOS;
}

/// Pasarela real con flutter_local_notifications. Las horas van en UTC: así
/// cada aviso queda en su instante exacto aunque cambie el horario de verano.
class LocalNotificationGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _spanish = true;

  static const Color _brand = Color(0xFF3949AB);

  @override
  bool get isIOS => Platform.isIOS;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init({required void Function(NoticeResponse) onResponse, required bool spanish}) async {
    _spanish = spanish;
    String tr(String es, String en) => spanish ? es : en;
    final Set<DarwinNotificationActionOption> fg = <DarwinNotificationActionOption>{DarwinNotificationActionOption.foreground};
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_rutinas'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: <DarwinNotificationCategory>[
              DarwinNotificationCategory('reminder', actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain('done', tr('Hecho', 'Done'), options: fg),
                DarwinNotificationAction.plain('snooze', tr('Posponer 10 min', 'Snooze 10 min'), options: fg),
              ]),
              DarwinNotificationCategory('habit_check', actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain('done', tr('Hecho', 'Done'), options: fg),
              ]),
              DarwinNotificationCategory('habit_count', actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain('plus', tr('Sumar 1', 'Add 1'), options: fg),
              ]),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse r) => onResponse(NoticeResponse(r.payload, r.actionId)),
      );
      _ready = true;
      await _createChannels();
      if (Platform.isIOS) {
        await _installIosSounds();
      }
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
  }

  /// iOS busca los sonidos de las notificaciones en Library/Sounds.
  Future<void> _installIosSounds() async {
    try {
      final Directory lib = await getLibraryDirectory();
      final Directory dir = Directory('${lib.path}/Sounds');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      for (final String name in <String>['rutinas_beep.wav', 'rutinas_bell.wav', 'rutinas_horn.wav', 'rutinas_gong.wav']) {
        final File f = File('${dir.path}/$name');
        final ByteData data = await rootBundle.load('assets/sounds/$name');
        if (!await f.exists() || await f.length() != data.lengthInBytes) {
          await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
        }
      }
    } catch (e) {
      debugPrint('No se pudieron copiar los sonidos: $e');
    }
  }

  /// Canales de Android: el sonido y la importancia de un canal no se pueden
  /// cambiar después de creado, por eso cada sonido tiene el suyo.
  Future<void> _createChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? a = _android;
    if (a == null) {
      return;
    }
    for (final NoticeChannel c in NoticeChannel.values) {
      final _ChannelSpec s = _spec(c);
      await a.createNotificationChannel(AndroidNotificationChannel(
        s.id,
        s.name,
        description: s.description,
        importance: s.importance,
        playSound: s.sound != null || s.defaultSound,
        sound: s.sound == null ? null : RawResourceAndroidNotificationSound(s.sound),
      ));
    }
  }

  _ChannelSpec _spec(NoticeChannel c) {
    final bool es = _spanish;
    String tr(String a, String b) => es ? a : b;
    switch (c) {
      case NoticeChannel.reminders:
        return _ChannelSpec('rutinas_recordatorios_1', tr('Recordatorios', 'Reminders'), tr('Avisos de tus recordatorios y sus repeticiones.', 'Your reminders and their repeated alerts.'), Importance.high, 'rutinas_bell');
      case NoticeChannel.countdowns:
        return _ChannelSpec('rutinas_cuentas_1', tr('Cuentas regresivas', 'Countdowns'), tr('Avisos de "avísame en…" que insisten hasta que los apagas.', '"Remind me in…" alerts that keep going until you stop them.'), Importance.high, 'rutinas_bell');
      case NoticeChannel.habits:
        return _ChannelSpec('rutinas_habitos_1', tr('Hábitos', 'Habits'), tr('Avisos de tus hábitos.', 'Your habit reminders.'), Importance.defaultImportance, null, defaultSound: true);
      case NoticeChannel.timerBeep:
        return _ChannelSpec('rutinas_temporizador_pitido_1', tr('Temporizador: pitido', 'Timer: beep'), tr('Cambios de intervalo con la pantalla apagada.', 'Interval changes while the screen is off.'), Importance.high, 'rutinas_beep');
      case NoticeChannel.timerBell:
        return _ChannelSpec('rutinas_temporizador_campana_1', tr('Temporizador: campana', 'Timer: bell'), tr('Cambios de intervalo con la pantalla apagada.', 'Interval changes while the screen is off.'), Importance.high, 'rutinas_bell');
      case NoticeChannel.timerHorn:
        return _ChannelSpec('rutinas_temporizador_bocina_1', tr('Temporizador: bocina', 'Timer: horn'), tr('Cambios de intervalo con la pantalla apagada.', 'Interval changes while the screen is off.'), Importance.high, 'rutinas_horn');
      case NoticeChannel.timerGong:
        return _ChannelSpec('rutinas_temporizador_gong_1', tr('Temporizador: gong', 'Timer: gong'), tr('Final del entrenamiento con la pantalla apagada.', 'End of a workout while the screen is off.'), Importance.high, 'rutinas_gong');
      case NoticeChannel.timerSilent:
        return _ChannelSpec('rutinas_temporizador_silencio_1', tr('Temporizador: sin sonido', 'Timer: silent'), tr('Intervalos configurados sin sonido.', 'Intervals set to play no sound.'), Importance.defaultImportance, null);
    }
  }

  NotificationDetails _details(PlannedNotice n) {
    final _ChannelSpec s = _spec(n.channel);
    String tr(String es, String en) => _spanish ? es : en;
    List<AndroidNotificationAction>? actions;
    String? category;
    switch (n.actions) {
      case NoticeActions.reminder:
        actions = <AndroidNotificationAction>[
          AndroidNotificationAction('done', tr('Hecho', 'Done'), showsUserInterface: true),
          AndroidNotificationAction('snooze', tr('Posponer 10 min', 'Snooze 10 min'), showsUserInterface: true),
        ];
        category = 'reminder';
        break;
      case NoticeActions.habitCheck:
        actions = <AndroidNotificationAction>[AndroidNotificationAction('done', tr('Hecho', 'Done'), showsUserInterface: true)];
        category = 'habit_check';
        break;
      case NoticeActions.habitCount:
        actions = <AndroidNotificationAction>[AndroidNotificationAction('plus', tr('Sumar 1', 'Add 1'), showsUserInterface: true)];
        category = 'habit_count';
        break;
      case NoticeActions.none:
        break;
    }
    final bool timer = n.isTimer;
    final bool alarmLike = timer || n.channel == NoticeChannel.countdowns;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        s.id,
        s.name,
        channelDescription: s.description,
        importance: s.importance,
        priority: s.importance == Importance.high ? Priority.high : Priority.defaultPriority,
        playSound: s.sound != null || s.defaultSound,
        sound: s.sound == null ? null : RawResourceAndroidNotificationSound(s.sound),
        icon: 'ic_stat_rutinas',
        color: _brand,
        category: alarmLike ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
        visibility: timer ? NotificationVisibility.public : NotificationVisibility.private,
        // Los avisos del temporizador se borran solos al llegar el siguiente.
        timeoutAfter: n.timeoutMs,
        actions: actions,
        styleInformation: BigTextStyleInformation(n.body),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: s.sound != null || s.defaultSound,
        sound: s.sound == null ? null : '${s.sound}.wav',
        categoryIdentifier: category,
        threadIdentifier: timer ? 'timer' : (n.route.startsWith('habit:') ? 'habits' : 'reminders'),
      ),
    );
  }

  @override
  Future<NoticeResponse?> launchResponse() async {
    try {
      final NotificationAppLaunchDetails? d = await _plugin.getNotificationAppLaunchDetails();
      final NotificationResponse? r = d?.notificationResponse;
      if (d == null || !d.didNotificationLaunchApp || r == null) {
        return null;
      }
      return NoticeResponse(r.payload, r.actionId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NoticePermissions> permissions() async {
    if (!_ready) {
      return const NoticePermissions(notifications: null, exactAlarms: true, exactAlarmsApply: false);
    }
    try {
      final AndroidFlutterLocalNotificationsPlugin? a = _android;
      if (a != null) {
        final bool? enabled = await a.areNotificationsEnabled();
        final bool exact = await a.canScheduleExactNotifications() ?? true;
        // Antes de Android 12 las alarmas exactas siempre están permitidas.
        return NoticePermissions(notifications: enabled, exactAlarms: exact, exactAlarmsApply: true);
      }
      final IOSFlutterLocalNotificationsPlugin? i = _ios;
      if (i != null) {
        final NotificationsEnabledOptions? o = await i.checkPermissions();
        return NoticePermissions(notifications: o?.isEnabled, exactAlarms: true, exactAlarmsApply: false);
      }
    } catch (e) {
      debugPrint('Permisos de notificaciones: $e');
    }
    return const NoticePermissions(notifications: null, exactAlarms: true, exactAlarmsApply: false);
  }

  @override
  Future<bool> requestNotifications() async {
    if (!_ready) {
      return false;
    }
    try {
      final AndroidFlutterLocalNotificationsPlugin? a = _android;
      if (a != null) {
        return await a.requestNotificationsPermission() ?? false;
      }
      return await _ios?.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    } catch (e) {
      debugPrint('Permiso de notificaciones: $e');
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarms() async {
    if (!_ready) {
      return false;
    }
    try {
      return await _android?.requestExactAlarmsPermission() ?? true;
    } catch (e) {
      debugPrint('Permiso de alarmas exactas: $e');
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _plugin.openAppNotificationSettings();
    } catch (e) {
      debugPrint('No se pudieron abrir los ajustes: $e');
    }
  }

  @override
  Future<List<PendingNotice>> pending() async {
    if (!_ready) {
      return const <PendingNotice>[];
    }
    try {
      final List<PendingNotificationRequest> list = await _plugin.pendingNotificationRequests();
      return list.map((PendingNotificationRequest p) => PendingNotice(p.id, p.payload)).toList();
    } catch (e) {
      debugPrint('Notificaciones pendientes: $e');
      return const <PendingNotice>[];
    }
  }

  @override
  Future<void> schedule(PlannedNotice notice, int id, {required bool exact}) async {
    if (!_ready) {
      return;
    }
    final tz.TZDateTime when = tz.TZDateTime.from(notice.when.toUtc(), tz.UTC);
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: notice.title,
        body: notice.body,
        scheduledDate: when,
        notificationDetails: _details(notice),
        androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: notice.payload,
      );
    } on PlatformException catch (e) {
      if (exact && e.code == 'exact_alarms_not_permitted') {
        // El permiso se quitó entre la consulta y la programación.
        await schedule(notice, id, exact: false);
      } else {
        debugPrint('No se pudo programar ${notice.key}: $e');
      }
    } catch (e) {
      debugPrint('No se pudo programar ${notice.key}: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) {
      return;
    }
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('No se pudo cancelar $id: $e');
    }
  }
}

class _ChannelSpec {
  const _ChannelSpec(this.id, this.name, this.description, this.importance, this.sound, {this.defaultSound = false});

  final String id;
  final String name;
  final String description;
  final Importance importance;

  /// Recurso de sonido (res/raw en Android, Library/Sounds en iOS).
  final String? sound;

  /// Sin sonido propio pero con el del sistema.
  final bool defaultSound;
}

/// Pasarela de prueba: guarda lo programado en memoria.
class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({this.ios = false, this.notificationsAllowed = true, this.exactAllowed = true});

  final bool ios;
  bool notificationsAllowed;
  bool exactAllowed;
  final Map<int, PlannedNotice> scheduled = <int, PlannedNotice>{};
  final Map<int, bool> exactById = <int, bool>{};
  final List<int> cancelled = <int>[];
  int scheduleCalls = 0;
  void Function(NoticeResponse)? _onResponse;
  NoticeResponse? launch;

  @override
  bool get isIOS => ios;

  @override
  Future<void> init({required void Function(NoticeResponse) onResponse, required bool spanish}) async {
    _onResponse = onResponse;
  }

  /// Simula un toque en una notificación o en uno de sus botones.
  void respond(String payload, [String? actionId]) => _onResponse?.call(NoticeResponse(payload, actionId));

  @override
  Future<NoticeResponse?> launchResponse() async => launch;

  @override
  Future<NoticePermissions> permissions() async => NoticePermissions(notifications: notificationsAllowed, exactAlarms: exactAllowed, exactAlarmsApply: !ios);

  @override
  Future<bool> requestNotifications() async {
    notificationsAllowed = true;
    return true;
  }

  @override
  Future<bool> requestExactAlarms() async {
    exactAllowed = true;
    return true;
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<PendingNotice>> pending() async {
    final DateTime now = clock.now();
    // Las que ya sonaron dejan de estar pendientes, como en el teléfono.
    scheduled.removeWhere((int id, PlannedNotice n) => !n.when.isAfter(now));
    return scheduled.entries.map((MapEntry<int, PlannedNotice> e) => PendingNotice(e.key, e.value.payload)).toList();
  }

  @override
  Future<void> schedule(PlannedNotice notice, int id, {required bool exact}) async {
    scheduleCalls++;
    scheduled[id] = notice;
    exactById[id] = exact;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
}
