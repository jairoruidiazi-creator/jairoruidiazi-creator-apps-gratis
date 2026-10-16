import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Recordatorios locales (facturas y registro diario). Sin servidor.
abstract class Notifier {
  Future<void> init();
  Future<bool> requestPermission();

  /// Aviso diario a la misma hora.
  Future<void> scheduleDaily({required int id, required int hour, required int minute, required String title, required String body});

  /// Aviso único en una fecha y hora.
  Future<void> scheduleAt({required int id, required DateTime when, required String title, required String body});
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

/// Implementación muda (pruebas y plataformas sin soporte).
class NoopNotifier implements Notifier {
  final List<String> log = <String>[];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleDaily({required int id, required int hour, required int minute, required String title, required String body}) async => log.add('daily:$id:$hour:$minute:$title');

  @override
  Future<void> scheduleAt({required int id, required DateTime when, required String title, required String body}) async => log.add('at:$id:${when.toIso8601String()}:$title');

  @override
  Future<void> cancel(int id) async => log.add('cancel:$id');

  @override
  Future<void> cancelAll() async => log.add('cancelAll');
}

class LocalNotifier implements Notifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  late final tz.Location _local;

  static const AndroidNotificationDetails _android = AndroidNotificationDetails('plata_recordatorios', 'Recordatorios', channelDescription: 'Facturas por pagar y registro diario', importance: Importance.defaultImportance, priority: Priority.defaultPriority);
  static const NotificationDetails _details = NotificationDetails(android: _android, iOS: DarwinNotificationDetails());

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
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notificaciones: $e');
    }
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

  tz.TZDateTime _tz(DateTime d) => tz.TZDateTime(_local, d.year, d.month, d.day, d.hour, d.minute);

  @override
  Future<void> scheduleDaily({required int id, required int hour, required int minute, required String title, required String body}) async {
    await init();
    if (!_ready) {
      return;
    }
    final DateTime now = DateTime.now();
    DateTime first = DateTime(now.year, now.month, now.day, hour, minute);
    if (!first.isAfter(now)) {
      first = first.add(const Duration(days: 1));
    }
    try {
      await _plugin.zonedSchedule(id: id, title: title, body: body, scheduledDate: _tz(first), notificationDetails: _details, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, matchDateTimeComponents: DateTimeComponents.time);
    } catch (e) {
      debugPrint('No se pudo programar el recordatorio diario: $e');
    }
  }

  @override
  Future<void> scheduleAt({required int id, required DateTime when, required String title, required String body}) async {
    await init();
    if (!_ready || !when.isAfter(DateTime.now())) {
      return;
    }
    try {
      await _plugin.zonedSchedule(id: id, title: title, body: body, scheduledDate: _tz(when), notificationDetails: _details, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    } catch (e) {
      debugPrint('No se pudo programar el recordatorio: $e');
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
