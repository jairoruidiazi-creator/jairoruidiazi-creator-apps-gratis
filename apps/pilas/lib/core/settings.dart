import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ajustes del adulto. Se guardan en SharedPreferences.
class AppSettings extends ChangeNotifier {
  AppSettings();

  static const String _kVoice = 'voiceEnabled';
  static const String _kVoiceRate = 'voiceRate';
  static const String _kSfx = 'sfxEnabled';
  static const String _kLimit = 'sessionLimitMinutes';
  static const String _kLargeText = 'largeText';
  static const String _kDyslexia = 'dyslexiaFont';
  static const String _kContrast = 'highContrast';
  static const String _kLastProfile = 'lastProfileId';
  static const String _kTeacher = 'teacherMode';
  static const String _kOnboarded = 'onboarded';
  static const String _kGateFails = 'gateFails';
  static const String _kGateLockedUntil = 'gateLockedUntil';

  /// Cuánto agranda la letra el ajuste "Texto grande" (se multiplica por la
  /// escala del sistema, con un tope en Dim.maxTextScale).
  static const double largeTextFactor = 1.25;

  SharedPreferences? _prefs;

  bool voiceEnabled = true;

  /// Velocidad de la voz, de 0.3 (lenta) a 0.7 (rápida). flutter_tts usa 0.0 a 1.0.
  double voiceRate = 0.45;
  bool sfxEnabled = true;

  /// Minutos por sesión de cada niño antes del descanso. 0 = sin límite.
  int sessionLimitMinutes = 20;
  bool largeText = false;
  bool dyslexiaFont = false;
  bool highContrast = false;
  String? lastProfileId;
  bool teacherMode = false;
  bool onboarded = false;

  /// Errores seguidos en la puerta parental y hasta cuándo queda bloqueada.
  int gateFails = 0;
  DateTime? gateLockedUntil;

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _prefs = p;
    voiceEnabled = p.getBool(_kVoice) ?? true;
    voiceRate = p.getDouble(_kVoiceRate) ?? 0.45;
    sfxEnabled = p.getBool(_kSfx) ?? true;
    sessionLimitMinutes = p.getInt(_kLimit) ?? 20;
    largeText = p.getBool(_kLargeText) ?? false;
    dyslexiaFont = p.getBool(_kDyslexia) ?? false;
    highContrast = p.getBool(_kContrast) ?? false;
    lastProfileId = p.getString(_kLastProfile);
    teacherMode = p.getBool(_kTeacher) ?? false;
    onboarded = p.getBool(_kOnboarded) ?? false;
    gateFails = p.getInt(_kGateFails) ?? 0;
    final int? locked = p.getInt(_kGateLockedUntil);
    gateLockedUntil = locked == null ? null : DateTime.fromMillisecondsSinceEpoch(locked);
    notifyListeners();
  }

  Future<void> setVoiceEnabled(bool v) async {
    voiceEnabled = v;
    await _prefs?.setBool(_kVoice, v);
    notifyListeners();
  }

  Future<void> setVoiceRate(double v) async {
    voiceRate = v.clamp(0.3, 0.7).toDouble();
    await _prefs?.setDouble(_kVoiceRate, voiceRate);
    notifyListeners();
  }

  Future<void> setSfxEnabled(bool v) async {
    sfxEnabled = v;
    await _prefs?.setBool(_kSfx, v);
    notifyListeners();
  }

  Future<void> setSessionLimitMinutes(int v) async {
    sessionLimitMinutes = v < 0 ? 0 : v;
    await _prefs?.setInt(_kLimit, sessionLimitMinutes);
    notifyListeners();
  }

  Future<void> setLargeText(bool v) async {
    largeText = v;
    await _prefs?.setBool(_kLargeText, v);
    notifyListeners();
  }

  Future<void> setDyslexiaFont(bool v) async {
    dyslexiaFont = v;
    await _prefs?.setBool(_kDyslexia, v);
    notifyListeners();
  }

  Future<void> setHighContrast(bool v) async {
    highContrast = v;
    await _prefs?.setBool(_kContrast, v);
    notifyListeners();
  }

  Future<void> setLastProfileId(String? id) async {
    lastProfileId = id;
    if (id == null) {
      await _prefs?.remove(_kLastProfile);
    } else {
      await _prefs?.setString(_kLastProfile, id);
    }
    notifyListeners();
  }

  Future<void> setTeacherMode(bool v) async {
    teacherMode = v;
    await _prefs?.setBool(_kTeacher, v);
    notifyListeners();
  }

  Future<void> setOnboarded(bool v) async {
    onboarded = v;
    await _prefs?.setBool(_kOnboarded, v);
    notifyListeners();
  }

  /// Guarda el estado de la puerta parental (sobrevive a cerrar la app).
  Future<void> setGateState({required int fails, DateTime? lockedUntil}) async {
    gateFails = fails;
    gateLockedUntil = lockedUntil;
    await _prefs?.setInt(_kGateFails, fails);
    if (lockedUntil == null) {
      await _prefs?.remove(_kGateLockedUntil);
    } else {
      await _prefs?.setInt(_kGateLockedUntil, lockedUntil.millisecondsSinceEpoch);
    }
  }
}
