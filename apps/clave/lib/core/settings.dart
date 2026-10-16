import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../music/notes.dart';

/// Preferencias del usuario. Se guardan con SharedPreferences.
class AppSettings extends ChangeNotifier {
  SharedPreferences? _prefs;

  String language = 'es';
  String themeMode = 'system'; // system | light | dark
  double a4 = 440;
  Temperament temperament = Temperament.equal;
  int temperamentRoot = 0;
  List<double> customTemperament = List<double>.filled(12, 0);
  Notation notation = Notation.solfeo;
  bool flats = false;
  int transposition = 0;
  int capo = 0;
  String instrumentId = 'cromatico';
  double toleranceCents = 5;
  double damping = 0.6;
  bool haptics = false;
  bool flash = true;
  bool keepAwake = true;
  int visualOffsetMs = 0;
  String recordingFormat = 'aac'; // aac | wav | flac
  int dailyGoalMinutes = 20;
  int weeklyGoalMinutes = 120;
  bool countInVoice = false;
  double metronomeVolume = 1.0;
  double droneVolume = 0.5;

  bool get spanish => language == 'es';

  PitchSettings get pitch => PitchSettings(
        a4: a4,
        temperament: temperament,
        temperamentRoot: temperamentRoot,
        custom: customTemperament,
        transposition: transposition,
        capo: capo,
        notation: notation,
        flats: flats,
      );

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _prefs = p;
    language = p.getString('language') ?? 'es';
    themeMode = p.getString('themeMode') ?? 'system';
    a4 = p.getDouble('a4') ?? 440;
    temperament = Temperament.values[(p.getInt('temperament') ?? 0).clamp(0, Temperament.values.length - 1)];
    temperamentRoot = p.getInt('temperamentRoot') ?? 0;
    final List<String>? custom = p.getStringList('customTemperament');
    if (custom != null && custom.length == 12) {
      customTemperament = custom.map((String s) => double.tryParse(s) ?? 0).toList();
    }
    notation = Notation.values[(p.getInt('notation') ?? 0).clamp(0, Notation.values.length - 1)];
    flats = p.getBool('flats') ?? false;
    transposition = p.getInt('transposition') ?? 0;
    capo = p.getInt('capo') ?? 0;
    instrumentId = p.getString('instrumentId') ?? 'cromatico';
    toleranceCents = p.getDouble('toleranceCents') ?? 5;
    damping = p.getDouble('damping') ?? 0.6;
    haptics = p.getBool('haptics') ?? false;
    flash = p.getBool('flash') ?? true;
    keepAwake = p.getBool('keepAwake') ?? true;
    visualOffsetMs = p.getInt('visualOffsetMs') ?? 0;
    recordingFormat = p.getString('recordingFormat') ?? 'aac';
    dailyGoalMinutes = p.getInt('dailyGoalMinutes') ?? 20;
    weeklyGoalMinutes = p.getInt('weeklyGoalMinutes') ?? 120;
    countInVoice = p.getBool('countInVoice') ?? false;
    metronomeVolume = p.getDouble('metronomeVolume') ?? 1.0;
    droneVolume = p.getDouble('droneVolume') ?? 0.5;
    notifyListeners();
  }

  Future<void> save() async {
    final SharedPreferences? p = _prefs;
    notifyListeners();
    if (p == null) {
      return;
    }
    await p.setString('language', language);
    await p.setString('themeMode', themeMode);
    await p.setDouble('a4', a4);
    await p.setInt('temperament', temperament.index);
    await p.setInt('temperamentRoot', temperamentRoot);
    await p.setStringList('customTemperament', customTemperament.map((double d) => d.toString()).toList());
    await p.setInt('notation', notation.index);
    await p.setBool('flats', flats);
    await p.setInt('transposition', transposition);
    await p.setInt('capo', capo);
    await p.setString('instrumentId', instrumentId);
    await p.setDouble('toleranceCents', toleranceCents);
    await p.setDouble('damping', damping);
    await p.setBool('haptics', haptics);
    await p.setBool('flash', flash);
    await p.setBool('keepAwake', keepAwake);
    await p.setInt('visualOffsetMs', visualOffsetMs);
    await p.setString('recordingFormat', recordingFormat);
    await p.setInt('dailyGoalMinutes', dailyGoalMinutes);
    await p.setInt('weeklyGoalMinutes', weeklyGoalMinutes);
    await p.setBool('countInVoice', countInVoice);
    await p.setDouble('metronomeVolume', metronomeVolume);
    await p.setDouble('droneVolume', droneVolume);
  }
}
