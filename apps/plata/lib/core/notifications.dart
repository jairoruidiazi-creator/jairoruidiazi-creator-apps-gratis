import 'dart:async';
import 'dart:ui' show Color;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Lo que hizo la persona con un aviso: tocarlo ([actionId] nulo) o tocar
/// uno de sus botones. [payload] dice de qué era (por ejemplo,
/// `o:<tarjeta>:<corte>` para un pago pendiente).
class NotifierResponse {
  const NotifierResponse({required this.payload, this.actionId});

  final String payload;
  final String? actionId;
}

/// Recordatorios locales (facturas y registro diario). Sin servidor.
abstract class Notifier {
  /// Botón «Ya lo pagué» del aviso de pago pendiente.
  static const String paidAction = 'pagado';

  /// Toques en los avisos y en sus botones mientras la app está abierta (o
  /// la abren: los botones traen la app al frente).
  Stream<NotifierResponse> get responses;

  /// El aviso con que se abrió la app, si se abrió desde uno.
  Future<NotifierResponse?> launchResponse();

  Future<void> init();

  /// Si la app puede mostrar notificaciones, sin preguntarle nada al usuario
  /// (null si no se sabe, por ejemplo en una plataforma sin soporte).
  Future<bool?> permissionStatus();

  /// Pide el permiso de notificaciones (Android 13+ e iOS). Devuelve si quedó
  /// concedido.
  Future<bool> requestPermission();

  /// Abre los ajustes de notificaciones de la app en el sistema (cuando el
  /// permiso se negó y el sistema ya no deja volver a preguntar).
  Future<bool> openSettings();

  /// Idioma del canal de notificaciones (el nombre que muestra Android en los
  /// ajustes de la app).
  void setLanguage({required bool spanish});

  /// Aviso diario a la misma hora. Con [private], la pantalla de bloqueo de
  /// Android muestra solo que hay un aviso de Plata, no su texto.
  Future<void> scheduleDaily({required int id, required int hour, required int minute, required String title, required String body, bool private = false});

  /// Aviso único en una fecha y hora.
  Future<void> scheduleAt({required int id, required DateTime when, required String title, required String body, bool private = false});

  /// Aviso inmediato (por ejemplo, un pago de tarjeta que se venció).
  /// Devuelve si de verdad se mostró: sin permiso, o si el sistema lo
  /// rechaza, es falso y quien llama puede volver a intentarlo después. Con
  /// [paidButton], el aviso trae el botón «Ya lo pagué» ([paidAction]).
  Future<bool> showNow({required int id, required String title, required String body, bool private = false, String? payload, bool paidButton = false});

  /// Avisos programados que aún no se han mostrado.
  Future<List<int>> pendingIds();
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

/// Implementación de pruebas (y de plataformas sin soporte): guarda lo que se
/// programa y puede negar el permiso.
class NoopNotifier implements Notifier {
  NoopNotifier({this.granted = true, this.grantOnRequest = true});

  /// Estado del permiso (null = desconocido).
  bool? granted;

  /// Si pedir el permiso lo concede (el usuario dice que sí).
  bool grantOnRequest;
  int requests = 0;
  int settingsOpened = 0;
  final List<String> log = <String>[];

  /// Botones y datos de los avisos mostrados, por id.
  final Map<int, String> payloads = <int, String>{};
  final Set<int> withPaidButton = <int>{};
  final StreamController<NotifierResponse> _responses = StreamController<NotifierResponse>.broadcast();

  /// Respuesta con que "se abrió" la app (pruebas).
  NotifierResponse? launch;

  /// Simula que la persona toca un aviso o uno de sus botones.
  void respond(NotifierResponse r) => _responses.add(r);

  @override
  Stream<NotifierResponse> get responses => _responses.stream;

  @override
  Future<NotifierResponse?> launchResponse() async => launch;

  /// Avisos programados por id: `daily:20:30:título` o `at:<fecha>:título:texto`.
  final Map<int, String> pending = <int, String>{};

  /// Títulos de los avisos mostrados al instante.
  final List<String> shown = <String>[];

  /// Ids de los avisos marcados como privados en la pantalla de bloqueo.
  final Set<int> privateIds = <int>{};
  bool spanish = true;

  @override
  Future<void> init() async {}

  @override
  Future<bool?> permissionStatus() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests += 1;
    if (grantOnRequest) {
      granted = true;
    } else {
      granted = false;
    }
    return granted ?? false;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened += 1;
    return true;
  }

  @override
  void setLanguage({required bool spanish}) => this.spanish = spanish;

  @override
  Future<void> scheduleDaily({required int id, required int hour, required int minute, required String title, required String body, bool private = false}) async {
    final String entry = 'daily:$hour:$minute:$title';
    pending[id] = entry;
    _private(id, private);
    log.add(entry);
  }

  @override
  Future<void> scheduleAt({required int id, required DateTime when, required String title, required String body, bool private = false}) async {
    final String entry = 'at:${when.toIso8601String()}:$title:$body';
    pending[id] = entry;
    _private(id, private);
    log.add(entry);
  }

  @override
  Future<bool> showNow({required int id, required String title, required String body, bool private = false, String? payload, bool paidButton = false}) async {
    if (payload != null) {
      payloads[id] = payload;
    }
    if (paidButton) {
      withPaidButton.add(id);
    }
    if (granted != true) {
      log.add('blocked:$title');
      return false;
    }
    shown.add(title);
    _private(id, private);
    log.add('now:$title:$body');
    return true;
  }

  void _private(int id, bool private) {
    if (private) {
      privateIds.add(id);
    } else {
      privateIds.remove(id);
    }
  }

  @override
  Future<List<int>> pendingIds() async => pending.keys.toList();

  @override
  Future<void> cancel(int id) async {
    pending.remove(id);
    log.add('cancel:$id');
  }

  @override
  Future<void> cancelAll() async {
    pending.clear();
    log.add('cancelAll');
  }
}

class LocalNotifier implements Notifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _spanish = true;
  late final tz.Location _local;

  /// Ícono propio de la barra de estado: monocromo y vectorial
  /// (res/drawable/ic_stat_plata.xml). El ícono de la app es adaptativo, con
  /// fondo, y en la barra se vería como una mancha (o fallaría en Android 8).
  static const String _icon = 'ic_stat_plata';

  /// El canal se crea (o se renombra) con cada aviso programado, en el idioma
  /// actual de la app.
  final StreamController<NotifierResponse> _responses = StreamController<NotifierResponse>.broadcast();

  @override
  Stream<NotifierResponse> get responses => _responses.stream;

  static NotifierResponse? _from(NotificationResponse r) {
    final String? payload = r.payload;
    return payload == null || payload.isEmpty ? null : NotifierResponse(payload: payload, actionId: r.actionId);
  }

  @override
  Future<NotifierResponse?> launchResponse() async {
    await init();
    if (!_ready) {
      return null;
    }
    try {
      final NotificationAppLaunchDetails? d = await _plugin.getNotificationAppLaunchDetails();
      final NotificationResponse? r = d?.notificationResponse;
      return d != null && d.didNotificationLaunchApp && r != null ? _from(r) : null;
    } catch (e) {
      debugPrint('Aviso de arranque: $e');
      return null;
    }
  }

  /// Categoría de iOS con el botón «Ya lo pagué» (se registra al iniciar).
  static const String _paidCategory = 'plata_pago';

  NotificationDetails _details({required bool private, bool paidButton = false}) => NotificationDetails(
        android: AndroidNotificationDetails(
          'plata_recordatorios',
          _spanish ? 'Recordatorios' : 'Reminders',
          channelDescription: _spanish ? 'Pagos por vencer y registro diario' : 'Upcoming payments and daily logging',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: _icon,
          color: const Color(0xFF0B3D2E),
          // Con clave o saldos ocultos, la pantalla de bloqueo solo dice que hay
          // un aviso de Plata.
          visibility: private ? NotificationVisibility.private : NotificationVisibility.public,
          // El botón trae la app al frente, que es donde se marca el pago.
          actions: paidButton ? <AndroidNotificationAction>[AndroidNotificationAction(Notifier.paidAction, _spanish ? 'Ya lo pagué' : 'I already paid', showsUserInterface: true)] : null,
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: paidButton ? _paidCategory : null),
      );

  @override
  void setLanguage({required bool spanish}) => _spanish = spanish;

  @override
  Future<void> init() async {
    if (_ready) {
      return;
    }
    // Zona horaria fija con el desfase actual del teléfono: exacta en países
    // sin horario de verano (Colombia) y suficiente en los demás, porque los
    // recordatorios se reprograman cada vez que se abre la app.
    final Duration offset = DateTime.now().timeZoneOffset;
    _local = tz.Location('Local', <int>[tz.minTime], <int>[0], <tz.TimeZone>[tz.TimeZone(offset, isDst: false, abbreviation: DateTime.now().timeZoneName)]);
    tz.setLocalLocation(_local);
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings(_icon),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: <DarwinNotificationCategory>[
              DarwinNotificationCategory(_paidCategory, actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain(Notifier.paidAction, _spanish ? 'Ya lo pagué' : 'I already paid', options: const <DarwinNotificationActionOption>{DarwinNotificationActionOption.foreground}),
              ]),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse r) {
          final NotifierResponse? n = _from(r);
          if (n != null) {
            _responses.add(n);
          }
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notificaciones: $e');
    }
  }

  @override
  Future<bool?> permissionStatus() async {
    await init();
    if (!_ready) {
      return null;
    }
    try {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.areNotificationsEnabled();
      }
      final IOSFlutterLocalNotificationsPlugin? ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final NotificationsEnabledOptions? o = await ios.checkPermissions();
        return o?.isEnabled;
      }
    } catch (e) {
      debugPrint('Permiso de notificaciones: $e');
    }
    return null;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) {
      return false;
    }
    try {
      final bool? android = await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      if (android != null) {
        return android;
      }
      final bool? ios = await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
      return ios ?? false;
    } catch (e) {
      debugPrint('Permiso de notificaciones: $e');
      return false;
    }
  }

  @override
  Future<bool> openSettings() async {
    await init();
    try {
      return await _plugin.openAppNotificationSettings() ?? false;
    } catch (e) {
      debugPrint('Ajustes de notificaciones: $e');
      return false;
    }
  }

  tz.TZDateTime _tz(DateTime d) => tz.TZDateTime(_local, d.year, d.month, d.day, d.hour, d.minute);

  @override
  Future<void> scheduleDaily({required int id, required int hour, required int minute, required String title, required String body, bool private = false}) async {
    await init();
    if (!_ready) {
      return;
    }
    final DateTime now = clock.now();
    DateTime first = DateTime(now.year, now.month, now.day, hour, minute);
    if (!first.isAfter(now)) {
      first = DateTime(now.year, now.month, now.day + 1, hour, minute);
    }
    try {
      await _plugin.zonedSchedule(id: id, title: title, body: body, scheduledDate: _tz(first), notificationDetails: _details(private: private), androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, matchDateTimeComponents: DateTimeComponents.time);
    } catch (e) {
      debugPrint('No se pudo programar el recordatorio diario: $e');
    }
  }

  @override
  Future<void> scheduleAt({required int id, required DateTime when, required String title, required String body, bool private = false}) async {
    await init();
    if (!_ready || !when.isAfter(clock.now())) {
      return;
    }
    try {
      await _plugin.zonedSchedule(id: id, title: title, body: body, scheduledDate: _tz(when), notificationDetails: _details(private: private), androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    } catch (e) {
      debugPrint('No se pudo programar el recordatorio: $e');
    }
  }

  @override
  Future<bool> showNow({required int id, required String title, required String body, bool private = false, String? payload, bool paidButton = false}) async {
    await init();
    if (!_ready || await permissionStatus() != true) {
      return false;
    }
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details(private: private, paidButton: paidButton), payload: payload);
      return true;
    } catch (e) {
      debugPrint('No se pudo mostrar el aviso: $e');
      return false;
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    await init();
    if (!_ready) {
      return <int>[];
    }
    try {
      return (await _plugin.pendingNotificationRequests()).map((PendingNotificationRequest r) => r.id).toList();
    } catch (e) {
      debugPrint('Avisos pendientes: $e');
      return <int>[];
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (_ready) {
      await _plugin.cancel(id: id);
    }
  }

  @override
  Future<void> cancelAll() async {
    if (_ready) {
      await _plugin.cancelAll();
    }
  }
}
