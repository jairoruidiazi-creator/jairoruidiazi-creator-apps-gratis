import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias (no sensibles) del usuario.
class AppSettings extends ChangeNotifier {
  SharedPreferences? _prefs;

  String language = 'es';
  String themeMode = 'system';
  bool showCents = false;
  bool onboarded = false;
  String defaultAccountId = '';
  bool dailyReminder = false;
  int dailyReminderHour = 20;
  int dailyReminderMinute = 30;
  bool billReminders = true;
  int billReminderDaysBefore = 1;
  bool noticesEnabled = false;
  bool noticesAutoPost = false;
  bool ratesAuto = true;
  bool autoBackup = true;
  /// Monedas además de la principal. Vacía al instalar: sin monedas extra la
  /// app no se conecta a internet.
  List<String> extraCurrencies = <String>[];
  DateTime? lastBackupAt;
  DateTime? lastRatesAttempt;
  bool hideBalances = false;

  bool get spanish => language == 'es';

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _prefs = p;
    language = p.getString('language') ?? 'es';
    themeMode = p.getString('themeMode') ?? 'system';
    showCents = p.getBool('showCents') ?? false;
    onboarded = p.getBool('onboarded') ?? false;
    defaultAccountId = p.getString('defaultAccountId') ?? '';
    dailyReminder = p.getBool('dailyReminder') ?? false;
    dailyReminderHour = p.getInt('dailyReminderHour') ?? 20;
    dailyReminderMinute = p.getInt('dailyReminderMinute') ?? 30;
    billReminders = p.getBool('billReminders') ?? true;
    billReminderDaysBefore = p.getInt('billReminderDaysBefore') ?? 1;
    noticesEnabled = p.getBool('noticesEnabled') ?? false;
    noticesAutoPost = p.getBool('noticesAutoPost') ?? false;
    ratesAuto = p.getBool('ratesAuto') ?? true;
    autoBackup = p.getBool('autoBackup') ?? true;
    extraCurrencies = p.getStringList('extraCurrencies') ?? <String>[];
    lastBackupAt = DateTime.tryParse(p.getString('lastBackupAt') ?? '');
    lastRatesAttempt = DateTime.tryParse(p.getString('lastRatesAttempt') ?? '');
    hideBalances = p.getBool('hideBalances') ?? false;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  Future<void> save() async {
    final SharedPreferences? p = _prefs;
    notifyListeners();
    if (p == null) {
      return;
    }
    await p.setString('language', language);
    await p.setString('themeMode', themeMode);
    await p.setBool('showCents', showCents);
    await p.setBool('onboarded', onboarded);
    await p.setString('defaultAccountId', defaultAccountId);
    await p.setBool('dailyReminder', dailyReminder);
    await p.setInt('dailyReminderHour', dailyReminderHour);
    await p.setInt('dailyReminderMinute', dailyReminderMinute);
    await p.setBool('billReminders', billReminders);
    await p.setInt('billReminderDaysBefore', billReminderDaysBefore);
    await p.setBool('noticesEnabled', noticesEnabled);
    await p.setBool('noticesAutoPost', noticesAutoPost);
    await p.setBool('ratesAuto', ratesAuto);
    await p.setBool('autoBackup', autoBackup);
    await p.setStringList('extraCurrencies', extraCurrencies);
    await p.setString('lastBackupAt', lastBackupAt?.toIso8601String() ?? '');
    await p.setString('lastRatesAttempt', lastRatesAttempt?.toIso8601String() ?? '');
    await p.setBool('hideBalances', hideBalances);
  }
}
