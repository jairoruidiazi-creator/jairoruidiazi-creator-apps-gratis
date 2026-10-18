import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/sequencer.dart';
import '../music/notes.dart';

/// Aviso simple sin datos (para escuchar solo una parte de los ajustes).
class Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Idioma de la app para un locale del teléfono: español si es `es*`,
/// inglés en cualquier otro caso.
String languageForLocale(Locale? locale) => locale?.languageCode.toLowerCase() == 'es' ? 'es' : 'en';

/// Preferencias del usuario. Se guardan con SharedPreferences, y solo las
/// claves que cambiaron.
///
/// Sin nada guardado, el idioma sale de [deviceLocale] (el del teléfono) y la
/// notación lo acompaña: Do Re Mi en español, C D E en inglés. Sin locale
/// (pruebas), español.
class AppSettings extends ChangeNotifier {
  AppSettings({Locale? deviceLocale}) : language = deviceLocale == null ? 'es' : languageForLocale(deviceLocale) {
    notation = language == 'es' ? Notation.solfeo : Notation.english;
    // Punto de partida para saber qué cambió (aunque no se llame a load).
    _saved.addAll(_snapshot());
  }

  SharedPreferences? _prefs;
  final Map<String, Object> _saved = <String, Object>{};

  /// Avisa solo cuando cambian el idioma o el tema (la app entera se
  /// reconstruye con ellos; con el resto de ajustes, no).
  final Signal appearance = Signal();

  String language;
  String themeMode = 'system'; // system | light | dark
  double a4 = 440;
  Temperament temperament = Temperament.equal;
  int temperamentRoot = 0;
  List<double> customTemperament = List<double>.filled(12, 0);
  Notation notation = Notation.solfeo;
  bool flats = false;
  int indianTonic = 0;
  int transposition = 0;
  int capo = 0;
  String instrumentId = 'cromatico';
  double toleranceCents = 5;
  double damping = 0.6;
  bool haptics = false;
  bool flash = true;
  bool keepAwake = true;

  /// Retraso del audio en milisegundos (0 a 400): cuánto tarda en oírse el
  /// sonido después de que la app lo entrega (salida del teléfono y
  /// audífonos Bluetooth). La animación y la vibración se retrasan lo mismo.
  int audioDelayMs = 0;
  String recordingFormat = 'aac'; // aac | wav | flac
  int dailyGoalMinutes = 20;
  int weeklyGoalMinutes = 120;
  bool countInVoice = false;
  double metronomeVolume = 1.0;
  double droneVolume = 0.5;

  /// Vista del pulso en el metrónomo: péndulo o número grande.
  String beatView = 'pendulum'; // pendulum | number
  bool micAsked = false;

  /// Último ritmo del metrónomo (JSON), para abrir la app como se dejó.
  String metronomeConfig = '';

  /// Setlist en uso y posición dentro de ella.
  String activeSetlistId = '';
  int activeSetlistIndex = 0;

  static const int maxAudioDelayMs = 400;

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
        indianTonic: indianTonic,
      );

  /// Ritmo guardado, ya saneado, o null si no hay.
  RhythmConfig? get savedRhythm {
    if (metronomeConfig.isEmpty) {
      return null;
    }
    try {
      final Object? j = jsonDecode(metronomeConfig);
      return j is Map<String, dynamic> ? RhythmConfig.fromJson(j) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _prefs = p;
    T? read<T>(String key) {
      final Object? v = p.get(key);
      return v is T ? v : null;
    }

    final String? lang = read<String>('language');
    if (lang == 'es' || lang == 'en') {
      language = lang!;
    }
    final String? mode = read<String>('themeMode');
    themeMode = mode == 'light' || mode == 'dark' ? mode! : 'system';
    a4 = _finite(read<double>('a4'), 440).clamp(400.0, 480.0).toDouble();
    temperament = Temperament.values[(read<int>('temperament') ?? 0).clamp(0, Temperament.values.length - 1)];
    temperamentRoot = (read<int>('temperamentRoot') ?? 0).clamp(0, 11);
    final List<String>? custom = p.getStringList('customTemperament');
    if (custom != null && custom.length == 12) {
      customTemperament = custom.map((String s) => _finite(double.tryParse(s), 0).clamp(-50.0, 50.0).toDouble()).toList();
    }
    final int? notationIndex = read<int>('notation');
    notation = notationIndex == null ? (spanish ? Notation.solfeo : Notation.english) : Notation.values[notationIndex.clamp(0, Notation.values.length - 1)];
    flats = read<bool>('flats') ?? false;
    indianTonic = (read<int>('indianTonic') ?? 0).clamp(0, 11);
    transposition = (read<int>('transposition') ?? 0).clamp(-12, 14);
    capo = (read<int>('capo') ?? 0).clamp(0, 12);
    instrumentId = read<String>('instrumentId') ?? 'cromatico';
    toleranceCents = _finite(read<double>('toleranceCents'), 5).clamp(1.0, 15.0).toDouble();
    damping = _finite(read<double>('damping'), 0.6).clamp(0.0, 0.95).toDouble();
    haptics = read<bool>('haptics') ?? false;
    flash = read<bool>('flash') ?? true;
    keepAwake = read<bool>('keepAwake') ?? true;
    audioDelayMs = (read<int>('audioDelayMs') ?? 0).clamp(0, maxAudioDelayMs);
    final String? fmt = read<String>('recordingFormat');
    recordingFormat = fmt == 'wav' || fmt == 'flac' ? fmt! : 'aac';
    dailyGoalMinutes = (read<int>('dailyGoalMinutes') ?? 20).clamp(5, 180);
    weeklyGoalMinutes = (read<int>('weeklyGoalMinutes') ?? 120).clamp(30, 1200);
    countInVoice = read<bool>('countInVoice') ?? false;
    metronomeVolume = _finite(read<double>('metronomeVolume'), 1).clamp(0.0, 1.0).toDouble();
    droneVolume = _finite(read<double>('droneVolume'), 0.5).clamp(0.0, 1.0).toDouble();
    beatView = read<String>('beatView') == 'number' ? 'number' : 'pendulum';
    micAsked = read<bool>('micAsked') ?? false;
    metronomeConfig = read<String>('metronomeConfig') ?? '';
    activeSetlistId = read<String>('activeSetlistId') ?? '';
    activeSetlistIndex = (read<int>('activeSetlistIndex') ?? 0).clamp(0, 9999);
    _saved
      ..clear()
      ..addAll(_snapshot());
    notifyListeners();
    appearance.fire();
  }

  static double _finite(double? v, double fallback) => v == null || !v.isFinite ? fallback : v;

  Map<String, Object> _snapshot() => <String, Object>{
        'language': language,
        'themeMode': themeMode,
        'a4': a4,
        'temperament': temperament.index,
        'temperamentRoot': temperamentRoot,
        'customTemperament': customTemperament.map((double d) => d.toString()).toList(),
        'notation': notation.index,
        'flats': flats,
        'indianTonic': indianTonic,
        'transposition': transposition,
        'capo': capo,
        'instrumentId': instrumentId,
        'toleranceCents': toleranceCents,
        'damping': damping,
        'haptics': haptics,
        'flash': flash,
        'keepAwake': keepAwake,
        'audioDelayMs': audioDelayMs,
        'recordingFormat': recordingFormat,
        'dailyGoalMinutes': dailyGoalMinutes,
        'weeklyGoalMinutes': weeklyGoalMinutes,
        'countInVoice': countInVoice,
        'metronomeVolume': metronomeVolume,
        'droneVolume': droneVolume,
        'beatView': beatView,
        'micAsked': micAsked,
        'metronomeConfig': metronomeConfig,
        'activeSetlistId': activeSetlistId,
        'activeSetlistIndex': activeSetlistIndex,
      };

  /// Avisa del cambio y escribe solo las claves que cambiaron.
  Future<void> save() async {
    final Map<String, Object> now = _snapshot();
    final List<String> changed = <String>[
      for (final MapEntry<String, Object> e in now.entries)
        if (!_same(_saved[e.key], e.value)) e.key,
    ];
    final bool look = changed.contains('language') || changed.contains('themeMode');
    for (final String k in changed) {
      _saved[k] = now[k]!;
    }
    notifyListeners();
    if (look) {
      appearance.fire();
    }
    final SharedPreferences? p = _prefs;
    if (p == null) {
      return;
    }
    for (final String k in changed) {
      final Object v = now[k]!;
      if (v is String) {
        await p.setString(k, v);
      } else if (v is bool) {
        await p.setBool(k, v);
      } else if (v is int) {
        await p.setInt(k, v);
      } else if (v is double) {
        await p.setDouble(k, v);
      } else if (v is List<String>) {
        await p.setStringList(k, v);
      }
    }
  }

  static bool _same(Object? a, Object b) {
    if (a is List<String> && b is List<String>) {
      return listEquals(a, b);
    }
    return a == b;
  }
}
