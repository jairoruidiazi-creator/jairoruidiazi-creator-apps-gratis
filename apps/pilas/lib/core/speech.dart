import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../content/money.dart';
import 'settings.dart';

/// Voz del sistema en español. Toda instrucción se puede repetir tocando el
/// altavoz; si el dispositivo no tiene voz en español, la app sigue con el
/// texto en pantalla y lo avisa (en Ajustes y en el inicio de los niños que
/// todavía no leen). Avisa a quien escuche cuando termina de prepararse.
class Voice extends ChangeNotifier {
  Voice(this.settings, {FlutterTts? tts}) : _ttsOverride = tts;

  final AppSettings settings;
  final FlutterTts? _ttsOverride;
  FlutterTts? _tts;
  Future<void>? _initFuture;

  /// Ya se intentó preparar la voz (con o sin éxito).
  bool ready = false;

  /// Hay una voz en español.
  bool available = false;

  /// Idioma de la voz elegida (por ejemplo es-CO).
  String? language;

  /// Idiomas preferidos, del más local al más general.
  static const List<String> preferred = <String>['es-CO', 'es-MX', 'es-US', 'es-419', 'es-AR', 'es-ES', 'es'];

  FlutterTts get _engine => _tts ??= _ttsOverride ?? FlutterTts();

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      final FlutterTts tts = _engine;
      String? chosen;
      for (final String lang in preferred) {
        final dynamic ok = await tts.isLanguageAvailable(lang);
        if (ok == true) {
          chosen = lang;
          break;
        }
      }
      if (chosen == null) {
        final dynamic langs = await tts.getLanguages;
        if (langs is List) {
          for (final dynamic l in langs) {
            if (l is String && l.toLowerCase().startsWith('es')) {
              chosen = l;
              break;
            }
          }
        }
      }
      if (chosen != null) {
        await tts.setLanguage(chosen);
        language = chosen;
        available = true;
        await _preferLocalVoice(tts, chosen);
      }
      await tts.setSpeechRate(settings.voiceRate);
      await tts.setPitch(1.05);
      await tts.setVolume(1.0);
      await tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('Voz no disponible: $e');
      available = false;
    }
    ready = true;
    notifyListeners();
  }

  /// En Android, si el motor ofrece una voz instalada en el teléfono para el
  /// idioma elegido, se usa esa y no una que necesite internet.
  Future<void> _preferLocalVoice(FlutterTts tts, String lang) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final dynamic voices = await tts.getVoices;
      if (voices is! List) {
        return;
      }
      final String want = lang.toLowerCase();
      Map<dynamic, dynamic>? best;
      for (final dynamic v in voices) {
        if (v is! Map) {
          continue;
        }
        final String locale = '${v['locale'] ?? ''}'.toLowerCase();
        final bool red = '${v['network_required'] ?? '0'}' == '1';
        final bool noInstalada = '${v['features'] ?? ''}'.contains('notInstalled');
        if (red || noInstalada || !locale.startsWith(want.split('-').first)) {
          continue;
        }
        if (best == null || locale == want) {
          best = v;
        }
      }
      if (best != null) {
        await tts.setVoice(<String, String>{'name': '${best['name']}', 'locale': '${best['locale']}'});
      }
    } catch (e) {
      debugPrint('No se pudo elegir una voz local: $e');
    }
  }

  /// El texto como debe sonar: los precios, porcentajes, medidas y signos de
  /// las cuentas en palabras. Así la voz del sistema no lee "$ 3.500" como
  /// dólares ni "12 m" como "doce eme".
  static String paraVoz(String text) {
    String t = text.replaceAllMapped(RegExp(r'\$[ \u00A0]?(\d{1,3}(?:\.\d{3})+|\d+)'), (Match m) => pesosEnPalabras(int.parse(m.group(1)!.replaceAll('.', ''))));
    t = t.replaceAllMapped(RegExp(r'(\d)[ \u00A0]?%'), (Match m) => '${m.group(1)} por ciento');
    String unidad(Match m, String singular, String plural) => '${m.group(1)} ${m.group(1) == '1' ? singular : plural}';
    t = t.replaceAllMapped(RegExp(r'(\d+)[ \u00A0]?m²'), (Match m) => unidad(m, 'metro cuadrado', 'metros cuadrados'));
    t = t.replaceAllMapped(RegExp(r'(\d+)[ \u00A0]?cm(?![a-záéíóúñ])'), (Match m) => unidad(m, 'centímetro', 'centímetros'));
    t = t.replaceAllMapped(RegExp(r'(\d+)[ \u00A0]?m(?![a-záéíóúñ²])'), (Match m) => unidad(m, 'metro', 'metros'));
    return t.replaceAll(' × ', ' por ').replaceAll(' ÷ ', ' dividido entre ').replaceAll(' = ', ' es igual a ').replaceAll(' + ', ' más ').replaceAll(' − ', ' menos ');
  }

  /// Si devuelve true, la voz no lee lo que piden los juegos (el niño está
  /// en su descanso). Lo conecta [Services].
  bool Function()? callada;

  /// Lo último que se calló durante el descanso (casi siempre la pregunta
  /// siguiente del juego que quedó debajo).
  String? _retenido;

  /// Dice un texto. Interrumpe lo que se estuviera diciendo. Durante el
  /// descanso no dice nada (lo guarda para [soltarRetenido]).
  Future<void> say(String text) async {
    if (callada?.call() ?? false) {
      if (text.trim().isNotEmpty) {
        _retenido = text;
      }
      return;
    }
    await hablar(text);
  }

  /// Dice un texto aunque el niño esté en su descanso (la pantalla de
  /// descanso y la puerta para adultos).
  void sayAlways(String text) {
    unawaited(hablar(text));
  }

  /// Al volver del descanso, dice lo que se calló (la pregunta que quedó en
  /// pantalla), para que el niño que no lee sepa qué hacer.
  void soltarRetenido() {
    final String? t = _retenido;
    _retenido = null;
    if (t != null) {
      sayLater(t);
    }
  }

  /// Olvida lo que se calló (al cambiar de jugador).
  void descartarRetenido() => _retenido = null;

  /// Habla de verdad con la voz del sistema.
  @protected
  Future<void> hablar(String text) async {
    if (!settings.voiceEnabled || text.trim().isEmpty) {
      return;
    }
    await init();
    if (!available) {
      return;
    }
    try {
      await _engine.stop();
      await _engine.setSpeechRate(settings.voiceRate);
      await _engine.speak(paraVoz(text));
    } catch (e) {
      debugPrint('Error al hablar: $e');
    }
  }

  /// Dice un texto sin esperar a que termine (para no bloquear la interfaz).
  void sayLater(String text) {
    unawaited(say(text));
  }

  Future<void> stop() async {
    if (_tts == null) {
      return;
    }
    try {
      await _tts!.stop();
    } catch (_) {}
  }
}
