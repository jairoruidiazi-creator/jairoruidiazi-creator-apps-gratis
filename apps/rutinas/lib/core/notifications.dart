import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/notice_plan.dart';

/// Respuesta a una notificación: un toque o uno de sus botones.
class NoticeResponse {
  const NoticeResponse(this.payload, this.actionId, {this.id});

  final String? payload;

  /// `done`, `snooze`, `plus` o `start`; null si se tocó la notificación.
  final String? actionId;

  /// Número de la notificación (para quitarla del panel).
  final int? id;

  String get route => routeOfPayload(payload);

  /// Ocurrencia a la que pertenece la notificación (null si no la trae).
  DateTime? get occurrence => NoticePayload.parse(payload).occurrence;
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

  /// Cambia el idioma de los canales de Android y de los botones de iOS.
  Future<void> setLanguage(bool spanish);

  /// Si la app se abrió desde una notificación, su respuesta.
  Future<NoticeResponse?> launchResponse();

  Future<NoticePermissions> permissions();

  Future<bool> requestNotifications();

  /// Abre el ajuste del sistema para las alarmas exactas (Android 12+).
  Future<bool> requestExactAlarms();

  /// Abre los ajustes de notificaciones de la app en el sistema.
  Future<void> openSettings();

  /// Lo pendiente según el sistema. En iOS es el estado real; en Android es la
  /// lista que guarda el plugin, que no se entera de lo que el sistema borra
  /// (forzar detención, quitar el permiso de alarmas exactas, una copia
  /// restaurada en otro teléfono): por eso no basta para decidir.
  Future<List<PendingNotice>> pending();

  Future<void> schedule(PlannedNotice notice, int id, {required bool exact, required String payload});

  /// Cancela una programada y la quita del panel si ya se mostró.
  Future<void> cancel(int id);

  /// Cancela todo lo programado (lo que ya está en el panel se queda).
  Future<void> cancelAllPending();

  /// iOS guarda menos notificaciones programadas que Android.
  bool get isIOS;
}

/// Pasarela real con flutter_local_notifications. Las horas van en UTC: así
/// cada aviso queda en su instante exacto aunque cambie el horario de verano.
class LocalNotificationGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _spanish = true;
  void Function(NoticeResponse)? _onResponse;

  static const Color _brand = Color(0xFF3949AB);

  /// Canales de versiones de prueba anteriores, que se borran al empezar.
  static const List<String> _oldChannels = <String>[
    'rutinas_cuentas_1',
    'rutinas_temporizador_pitido_1',
    'rutinas_temporizador_campana_1',
    'rutinas_temporizador_bocina_1',
    'rutinas_temporizador_gong_1',
    'rutinas_temporizador_silencio_1',
  ];

  @override
  bool get isIOS => Platform.isIOS;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  InitializationSettings _settings() {
    String tr(String es, String en) => _spanish ? es : en;
    final Set<DarwinNotificationActionOption> fg = <DarwinNotificationActionOption>{DarwinNotificationActionOption.foreground};
    return InitializationSettings(
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
          DarwinNotificationCategory('habit_timed', actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain('start', tr('Empezar', 'Start'), options: fg),
          ]),
        ],
      ),
    );
  }

  void _handle(NotificationResponse r) => _onResponse?.call(NoticeResponse(r.payload, r.actionId, id: r.id));

  @override
  Future<void> init({required void Function(NoticeResponse) onResponse, required bool spanish}) async {
    _spanish = spanish;
    _onResponse = onResponse;
    try {
      await _plugin.initialize(settings: _settings(), onDidReceiveNotificationResponse: _handle);
      _ready = true;
      await _createChannels();
      if (Platform.isIOS) {
        await _installIosSounds();
      }
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
  }

  @override
  Future<void> setLanguage(bool spanish) async {
    if (!_ready || spanish == _spanish) {
      _spanish = spanish;
      return;
    }
    _spanish = spanish;
    try {
      if (Platform.isIOS) {
        // Los botones de iOS van en las categorías: se vuelven a registrar
        // (sin pedir permisos otra vez).
        await _plugin.initialize(settings: _settings(), onDidReceiveNotificationResponse: _handle);
      } else {
        // Android deja cambiar el nombre y la descripción de un canal ya creado.
        await _createChannels();
      }
    } catch (e) {
      debugPrint('No se pudo cambiar el idioma de los avisos: $e');
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

  /// Canales de Android: el sonido, la vibración y la importancia de un canal
  /// no se pueden cambiar después de creado, por eso cada combinación tiene el
  /// suyo. Van en dos grupos para que la lista del sistema se entienda.
  Future<void> _createChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? a = _android;
    if (a == null) {
      return;
    }
    String tr(String es, String en) => _spanish ? es : en;
    await a.createNotificationChannelGroup(AndroidNotificationChannelGroup('rutinas_avisos', tr('Recordatorios y hábitos', 'Reminders and habits')));
    await a.createNotificationChannelGroup(AndroidNotificationChannelGroup('rutinas_temporizador', tr('Temporizador', 'Timer')));
    for (final NoticeChannel c in NoticeChannel.values) {
      final _ChannelSpec s = _spec(c);
      await a.createNotificationChannel(AndroidNotificationChannel(
        s.id,
        s.name,
        description: s.description,
        groupId: s.group,
        importance: s.importance,
        playSound: s.sound != null || s.defaultSound,
        sound: s.sound == null ? null : RawResourceAndroidNotificationSound(s.sound),
        enableVibration: s.vibration,
        audioAttributesUsage: s.alarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      ));
    }
    for (final String old in _oldChannels) {
      try {
        await a.deleteNotificationChannel(channelId: old);
      } catch (_) {}
    }
  }

  _ChannelSpec _spec(NoticeChannel c) {
    final bool es = _spanish;
    String tr(String a, String b) => es ? a : b;
    final String changes = tr('Cambios de intervalo y final con la pantalla apagada', 'Interval changes and the end, with the screen off');
    switch (c) {
      case NoticeChannel.reminders:
        return _ChannelSpec('rutinas_recordatorios_1', tr('Recordatorios', 'Reminders'), tr('Avisos de tus recordatorios y sus repeticiones.', 'Your reminders and their repeated alerts.'), Importance.high, 'rutinas_bell', group: 'rutinas_avisos');
      case NoticeChannel.countdowns:
        return _ChannelSpec('rutinas_cuentas_2', tr('Cuentas regresivas', 'Countdowns'), tr('Avisos de «Avísame en…» y sus repeticiones.', '"Remind me in…" alerts and their repeats.'), Importance.high, 'rutinas_bell', group: 'rutinas_avisos', alarm: true);
      case NoticeChannel.habits:
        return _ChannelSpec('rutinas_habitos_1', tr('Hábitos', 'Habits'), tr('Avisos de tus hábitos.', 'Your habit reminders.'), Importance.defaultImportance, null, defaultSound: true, group: 'rutinas_avisos');
      case NoticeChannel.timerBeep:
        return _ChannelSpec('rutinas_temporizador_pitido_2', tr('Temporizador: pitido', 'Timer: beep'), changes, Importance.high, 'rutinas_beep', group: 'rutinas_temporizador', alarm: true);
      case NoticeChannel.timerBell:
        return _ChannelSpec('rutinas_temporizador_campana_2', tr('Temporizador: campana', 'Timer: bell'), changes, Importance.high, 'rutinas_bell', group: 'rutinas_temporizador', alarm: true);
      case NoticeChannel.timerHorn:
        return _ChannelSpec('rutinas_temporizador_bocina_2', tr('Temporizador: bocina', 'Timer: horn'), changes, Importance.high, 'rutinas_horn', group: 'rutinas_temporizador', alarm: true);
      case NoticeChannel.timerGong:
        return _ChannelSpec('rutinas_temporizador_gong_2', tr('Temporizador: gong', 'Timer: gong'), changes, Importance.high, 'rutinas_gong', group: 'rutinas_temporizador', alarm: true);
      case NoticeChannel.timerBeepNoVibration:
        return _ChannelSpec('rutinas_temporizador_pitido_sin_vibrar_2', tr('Temporizador: pitido sin vibración', 'Timer: beep, no vibration'), changes, Importance.high, 'rutinas_beep', group: 'rutinas_temporizador', alarm: true, vibration: false);
      case NoticeChannel.timerBellNoVibration:
        return _ChannelSpec('rutinas_temporizador_campana_sin_vibrar_2', tr('Temporizador: campana sin vibración', 'Timer: bell, no vibration'), changes, Importance.high, 'rutinas_bell', group: 'rutinas_temporizador', alarm: true, vibration: false);
      case NoticeChannel.timerHornNoVibration:
        return _ChannelSpec('rutinas_temporizador_bocina_sin_vibrar_2', tr('Temporizador: bocina sin vibración', 'Timer: horn, no vibration'), changes, Importance.high, 'rutinas_horn', group: 'rutinas_temporizador', alarm: true, vibration: false);
      case NoticeChannel.timerGongNoVibration:
        return _ChannelSpec('rutinas_temporizador_gong_sin_vibrar_2', tr('Temporizador: gong sin vibración', 'Timer: gong, no vibration'), changes, Importance.high, 'rutinas_gong', group: 'rutinas_temporizador', alarm: true, vibration: false);
      case NoticeChannel.timerVibrate:
        return _ChannelSpec('rutinas_temporizador_vibracion_2', tr('Temporizador: solo vibración', 'Timer: vibration only'), tr('Con los sonidos apagados o un intervalo sin sonido.', 'With sounds off or an interval set to no sound.'), Importance.high, null, group: 'rutinas_temporizador');
      case NoticeChannel.timerSilent:
        return _ChannelSpec('rutinas_temporizador_silencio_2', tr('Temporizador: sin sonido ni vibración', 'Timer: no sound or vibration'), tr('Con los sonidos y la vibración apagados.', 'With sounds and vibration turned off.'), Importance.high, null, group: 'rutinas_temporizador', vibration: false);
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
      case NoticeActions.habitTimed:
        actions = <AndroidNotificationAction>[AndroidNotificationAction('start', tr('Empezar', 'Start'), showsUserInterface: true)];
        category = 'habit_timed';
        break;
      case NoticeActions.none:
        break;
    }
    final bool timer = n.isTimer;
    final bool alarmLike = timer || n.channel == NoticeChannel.countdowns;
    final bool audible = s.sound != null || s.defaultSound;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        s.id,
        s.name,
        channelDescription: s.description,
        importance: s.importance,
        priority: s.importance == Importance.high ? Priority.high : Priority.defaultPriority,
        playSound: audible,
        sound: s.sound == null ? null : RawResourceAndroidNotificationSound(s.sound),
        enableVibration: s.vibration,
        audioAttributesUsage: s.alarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
        icon: 'ic_stat_rutinas',
        color: _brand,
        category: alarmLike ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
        visibility: timer ? NotificationVisibility.public : NotificationVisibility.private,
        // Se borra sola al llegar el siguiente aviso del mismo elemento.
        timeoutAfter: n.timeoutMs,
        actions: actions,
        styleInformation: BigTextStyleInformation(n.body),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: audible,
        sound: s.sound == null ? null : '${s.sound}.wav',
        categoryIdentifier: category,
        threadIdentifier: timer ? 'timer' : (n.route.startsWith('habit:') ? 'habits' : 'reminders'),
        // Recordatorios, cuentas regresivas y temporizador: pasan por encima de
        // los modos de concentración si el usuario lo permite (no del modo
        // silencio: con el iPhone en silencio llegan sin sonido).
        interruptionLevel: n.urgent ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
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
      return NoticeResponse(r.payload, r.actionId, id: r.id);
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
  Future<void> schedule(PlannedNotice notice, int id, {required bool exact, required String payload}) async {
    if (!_ready) {
      return;
    }
    final AndroidScheduleMode mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      final Duration? every = notice.repeatEvery;
      if (every != null) {
        // Una sola solicitud que se repite: la primera vez suena dentro de
        // [every] y luego cada [every], en Android y en iOS, hasta cancelarla.
        await _plugin.periodicallyShowWithDuration(
          id: id,
          title: notice.title,
          body: notice.body,
          repeatDurationInterval: every,
          notificationDetails: _details(notice),
          androidScheduleMode: mode,
          payload: payload,
        );
      } else {
        await _plugin.zonedSchedule(
          id: id,
          title: notice.title,
          body: notice.body,
          scheduledDate: tz.TZDateTime.from(notice.when.toUtc(), tz.UTC),
          notificationDetails: _details(notice),
          androidScheduleMode: mode,
          payload: payload,
        );
      }
    } on PlatformException catch (e) {
      if (exact && e.code == 'exact_alarms_not_permitted') {
        // El permiso se quitó entre la consulta y la programación.
        await schedule(notice, id, exact: false, payload: payload);
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

  @override
  Future<void> cancelAllPending() async {
    if (!_ready) {
      return;
    }
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (e) {
      debugPrint('No se pudo cancelar lo programado: $e');
    }
  }
}

class _ChannelSpec {
  const _ChannelSpec(this.id, this.name, this.description, this.importance, this.sound, {this.defaultSound = false, required this.group, this.alarm = false, this.vibration = true});

  final String id;
  final String name;
  final String description;
  final Importance importance;

  /// Recurso de sonido (res/raw en Android, Library/Sounds en iOS).
  final String? sound;

  /// Sin sonido propio pero con el del sistema.
  final bool defaultSound;
  final String group;

  /// Suena por el volumen de alarma, como el temporizador del reloj: se oye
  /// aunque el volumen de las notificaciones esté bajo.
  final bool alarm;
  final bool vibration;
}

/// Pasarela de prueba. Separa lo que el sistema tiene de verdad programado
/// ([scheduled]) de la lista que guarda el plugin en Android ([cache]), para
/// poder simular lo que en un teléfono las separa: «forzar detención», quitar
/// el permiso de alarmas exactas o restaurar una copia en otro teléfono.
class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({this.ios = false, this.notificationsAllowed = true, this.exactAllowed = true});

  final bool ios;
  bool notificationsAllowed;
  bool exactAllowed;

  /// Lo que de verdad va a sonar (alarmas de Android, solicitudes de iOS).
  final Map<int, PlannedNotice> scheduled = <int, PlannedNotice>{};

  /// Carga útil de cada aviso programado, como la guarda el sistema o el plugin.
  final Map<int, String> payloads = <int, String>{};

  /// Lo que el plugin de Android cree que está programado (id → carga útil).
  final Map<int, String> cache = <int, String>{};

  /// Notificaciones a la vista en el panel.
  final Map<int, PlannedNotice> shown = <int, PlannedNotice>{};
  final Map<int, DateTime> _shownAt = <int, DateTime>{};
  final Map<int, bool> exactById = <int, bool>{};
  final List<int> cancelled = <int>[];
  final List<bool> languages = <bool>[];
  int scheduleCalls = 0;
  int cancelAllCalls = 0;

  /// Orden de las llamadas (`programar:<id>` y `cancelar:<id>`).
  final List<String> ops = <String>[];

  /// Lo más que hubo programado a la vez (iOS guarda 64).
  int peak = 0;
  void Function(NoticeResponse)? _onResponse;
  NoticeResponse? launch;

  @override
  bool get isIOS => ios;

  @override
  Future<void> init({required void Function(NoticeResponse) onResponse, required bool spanish}) async {
    _onResponse = onResponse;
    languages.add(spanish);
  }

  @override
  Future<void> setLanguage(bool spanish) async => languages.add(spanish);

  /// Simula un toque en una notificación o en uno de sus botones.
  void respond(String payload, [String? actionId, int? id]) => _onResponse?.call(NoticeResponse(payload, actionId, id: id));

  /// «Forzar detención» o un ahorrador de batería: el sistema borra las alarmas
  /// de la app, pero la lista del plugin sigue igual.
  void forceStop() => scheduled.clear();

  /// Lo que sonó hasta [now] pasa al panel (las que se repiten siguen
  /// programadas), y se quita lo que ya se borró solo por su `timeoutAfter`.
  void deliver(DateTime now) {
    for (final int id in scheduled.keys.toList()) {
      final PlannedNotice n = scheduled[id]!;
      if (n.when.isAfter(now)) {
        continue;
      }
      shown[id] = n;
      final Duration? every = n.repeatEvery;
      if (every == null) {
        _shownAt[id] = n.when;
        scheduled.remove(id);
        payloads.remove(id);
        cache.remove(id);
      } else {
        // La última vez que sonó.
        DateTime last = n.when;
        while (!last.add(every).isAfter(now)) {
          last = last.add(every);
        }
        _shownAt[id] = last;
      }
    }
    // `timeoutAfter` solo existe en Android: en iOS lo mostrado se queda.
    for (final int id in ios ? const <int>[] : shown.keys.toList()) {
      final int? timeout = shown[id]!.timeoutMs;
      final DateTime? at = _shownAt[id];
      if (timeout != null && at != null && !at.add(Duration(milliseconds: timeout)).isAfter(now)) {
        shown.remove(id);
        _shownAt.remove(id);
      }
    }
  }

  @override
  Future<NoticeResponse?> launchResponse() async => launch;

  @override
  Future<NoticePermissions> permissions() async => NoticePermissions(notifications: notificationsAllowed, exactAlarms: ios || exactAllowed, exactAlarmsApply: !ios);

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
    deliver(clock.now());
    if (ios) {
      // iOS responde con su estado real.
      return scheduled.keys.map((int id) => PendingNotice(id, payloads[id])).toList();
    }
    return cache.entries.map((MapEntry<int, String> e) => PendingNotice(e.key, e.value)).toList();
  }

  @override
  Future<void> schedule(PlannedNotice notice, int id, {required bool exact, required String payload}) async {
    scheduleCalls++;
    ops.add('programar:$id');
    scheduled[id] = notice;
    if (scheduled.length > peak) {
      peak = scheduled.length;
    }
    payloads[id] = payload;
    cache[id] = payload;
    exactById[id] = exact;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    ops.add('cancelar:$id');
    scheduled.remove(id);
    payloads.remove(id);
    cache.remove(id);
    shown.remove(id);
    _shownAt.remove(id);
  }

  @override
  Future<void> cancelAllPending() async {
    cancelAllCalls++;
    scheduled.clear();
    payloads.clear();
    cache.clear();
  }
}
