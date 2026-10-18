import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del usuario. Se guardan con SharedPreferences y viajan en la
/// copia de seguridad.
class AppSettings extends ChangeNotifier {
  AppSettings({this.deviceLanguage = 'es'});

  /// Idioma del teléfono al abrir la app: si nunca se eligió uno, la app lo
  /// sigue (español si el teléfono está en español; si no, inglés).
  final String deviceLanguage;

  SharedPreferences? _prefs;

  String? _language;
  String themeMode = 'system'; // system | light | dark
  int accent = 0;
  bool sounds = true;
  double volume = 1.0;
  bool voice = true;
  bool voiceCountdown = true;
  bool vibration = true;
  int weekStart = DateTime.monday; // 1 lunes, 7 domingo
  bool keepAwake = true;

  /// Insistencia por defecto de las cuentas regresivas rápidas, en minutos.
  int countdownNag = 1;
  DateTime? lastExportAt;

  /// Ya se pidió el permiso de notificaciones una vez (para no insistir).
  bool askedNotifications = false;

  String get language => _language ?? (deviceLanguage == 'es' ? 'es' : 'en');

  set language(String value) => _language = value;

  bool get spanish => language == 'es';

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _prefs = p;
    _language = p.getString('language');
    themeMode = p.getString('themeMode') ?? 'system';
    accent = p.getInt('accent') ?? 0;
    sounds = p.getBool('sounds') ?? true;
    volume = p.getDouble('volume') ?? 1.0;
    voice = p.getBool('voice') ?? true;
    voiceCountdown = p.getBool('voiceCountdown') ?? true;
    vibration = p.getBool('vibration') ?? true;
    weekStart = p.getInt('weekStart') ?? DateTime.monday;
    keepAwake = p.getBool('keepAwake') ?? true;
    countdownNag = p.getInt('countdownNag') ?? 1;
    lastExportAt = DateTime.tryParse(p.getString('lastExportAt') ?? '');
    askedNotifications = p.getBool('askedNotifications') ?? false;
    _sanitize();
    notifyListeners();
  }

  void _sanitize() {
    if (_language != null && _language != 'es' && _language != 'en') {
      _language = null;
    }
    if (!<String>['system', 'light', 'dark'].contains(themeMode)) {
      themeMode = 'system';
    }
    if (weekStart != DateTime.monday && weekStart != DateTime.sunday) {
      weekStart = DateTime.monday;
    }
    volume = volume.clamp(0.0, 1.0).toDouble();
    countdownNag = countdownNag.clamp(1, 60);
    if (accent < 0) {
      accent = 0;
    }
  }

  Future<void> save() async {
    _sanitize();
    notifyListeners();
    final SharedPreferences? p = _prefs;
    if (p == null) {
      return;
    }
    if (_language == null) {
      await p.remove('language');
    } else {
      await p.setString('language', _language!);
    }
    await p.setString('themeMode', themeMode);
    await p.setInt('accent', accent);
    await p.setBool('sounds', sounds);
    await p.setDouble('volume', volume);
    await p.setBool('voice', voice);
    await p.setBool('voiceCountdown', voiceCountdown);
    await p.setBool('vibration', vibration);
    await p.setInt('weekStart', weekStart);
    await p.setBool('keepAwake', keepAwake);
    await p.setInt('countdownNag', countdownNag);
    await p.setString('lastExportAt', lastExportAt?.toIso8601String() ?? '');
    await p.setBool('askedNotifications', askedNotifications);
  }

  /// Lo que viaja en la copia de seguridad (no el estado de los permisos).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'language': language,
        'themeMode': themeMode,
        'accent': accent,
        'sounds': sounds,
        'volume': volume,
        'voice': voice,
        'voiceCountdown': voiceCountdown,
        'vibration': vibration,
        'weekStart': weekStart,
        'keepAwake': keepAwake,
        'countdownNag': countdownNag,
      };

  void applyJson(Map<String, dynamic> j) {
    final Object? lang = j['language'];
    if (lang is String) {
      _language = lang;
    }
    final Object? theme = j['themeMode'];
    if (theme is String) {
      themeMode = theme;
    }
    accent = _int(j['accent'], accent);
    sounds = _bool(j['sounds'], sounds);
    volume = _double(j['volume'], volume);
    voice = _bool(j['voice'], voice);
    voiceCountdown = _bool(j['voiceCountdown'], voiceCountdown);
    vibration = _bool(j['vibration'], vibration);
    weekStart = _int(j['weekStart'], weekStart);
    keepAwake = _bool(j['keepAwake'], keepAwake);
    countdownNag = _int(j['countdownNag'], countdownNag);
    _sanitize();
  }

  static int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  static double _double(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

  static bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;
}
